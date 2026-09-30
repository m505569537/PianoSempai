import SwiftData
import XCTest
@testable import PianoSempai

/// 课程推进状态机单测（ADR-0003）：条目状态为唯一真相、current* 为物化派生缓存。
/// 覆盖纯函数（间隔表/fail streak）、reactToAnalyzedTake 全分支、解锁/游标、
/// 复习 roll、定级补建与既有用户对账。brief §6 测试清单 1-16。
final class CourseAdvancementStateMachineTests: XCTestCase {

    // MARK: 夹具

    /// in-memory 容器（对齐 CourseEngineTests harness；react 端到端需全链模型）
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: AppSettings.self, PlacementResult.self, CoursePathState.self,
            Piece.self, ScoreFile.self, Take.self, TakeAnalysis.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// 建 practicing 条目（可指定 book/status；插入点首条等场景复用）
    @MainActor
    @discardableResult
    private func makePiece(
        book: String = "拜厄", number: Int, status: String = "practicing",
        intervalStage: Int = 0, nextReviewAt: Date? = nil, in context: ModelContext
    ) -> Piece {
        let piece = Piece(
            title: "\(book) 第\(number)条", book: book, number: number,
            status: status, nextReviewAt: nextReviewAt, intervalStage: intervalStage
        )
        context.insert(piece)
        return piece
    }

    /// 建一条已分析的 take（pieceTakeHistory 的历史输入：canEvaluate/passesHardMetrics 由 TakeAnalysis 行表达）
    @MainActor
    @discardableResult
    private func insertTake(
        _ piece: Piece, eligible: Bool, passed: Bool,
        startedAt: Date = Date(), in context: ModelContext
    ) -> Take {
        let take = Take()
        take.pieceId = piece.entityId
        take.startedAt = startedAt
        take.hasMidi = true
        context.insert(take)
        let analysis = TakeAnalysis()
        analysis.takeId = take.entityId
        analysis.canEvaluate = eligible
        analysis.passesHardMetrics = passed
        context.insert(analysis)
        take.analysisId = analysis.entityId
        return take
    }

    private func react(
        _ piece: Piece, canEvaluate: Bool = true, passed: Bool = true, hasMidi: Bool = true,
        in context: ModelContext
    ) -> CourseEngine.ProgressionEvent {
        CourseEngine.reactToAnalyzedTake(
            piece: piece, canEvaluate: canEvaluate,
            passedHardMetrics: passed, hasMidi: hasMidi, in: context
        )
    }

    /// 天数差（brief §6：真实日期断言用 dateComponents day，避免时分秒误判）
    private func dayDiff(from a: Date, to b: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)
        ).day ?? 0
    }

    private func fetchPiece(book: String, number: Int, in context: ModelContext) -> Piece? {
        let descriptor = FetchDescriptor<Piece>(
            predicate: #Predicate { $0.book == book && $0.number == number }
        )
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: 纯函数（1-2）

    func testNextReviewDateIntervalTable() {
        let now = Date()
        // stage 0→+1 天、1→+3、2→+7、3→+14
        XCTAssertEqual(dayDiff(from: now, to: CourseEngine.nextReviewDate(currentStage: 0, from: now).date), 1)
        XCTAssertEqual(dayDiff(from: now, to: CourseEngine.nextReviewDate(currentStage: 1, from: now).date), 3)
        XCTAssertEqual(dayDiff(from: now, to: CourseEngine.nextReviewDate(currentStage: 2, from: now).date), 7)
        XCTAssertEqual(dayDiff(from: now, to: CourseEngine.nextReviewDate(currentStage: 3, from: now).date), 14)
        // 超界封顶：已在 14 档再触发仍 +14 天、档位停在末档（Q14 循环不毕业）
        let capped = CourseEngine.nextReviewDate(currentStage: 4, from: now)
        XCTAssertEqual(dayDiff(from: now, to: capped.date), 14)
        XCTAssertEqual(capped.stage, CourseEngine.reviewIntervalDays.count - 1)
        // 返回的 stage 即封顶后的档位（正常范围内透传）
        XCTAssertEqual(CourseEngine.nextReviewDate(currentStage: 1, from: now).stage, 1)
    }

    func testConsecutiveFailStreak() {
        // 尾部连续 fail 计数
        XCTAssertEqual(CourseEngine.consecutiveFailStreak(eligibleTakes: [
            (true, false), (true, false), (true, false),
        ]), 3)
        // 尾部 2 连 fail（更早的 fail 被中间 pass 清零）
        XCTAssertEqual(CourseEngine.consecutiveFailStreak(eligibleTakes: [
            (true, false), (true, true), (true, false), (true, false),
        ]), 2)
        // 中间夹 pass 归零（尾部全是 pass）
        XCTAssertEqual(CourseEngine.consecutiveFailStreak(eligibleTakes: [
            (true, false), (true, true),
        ]), 0)
        // 非可评中性：跳过不清零
        XCTAssertEqual(CourseEngine.consecutiveFailStreak(eligibleTakes: [
            (true, false), (false, false), (true, false),
        ]), 2)
        // 尾部不可评不计入
        XCTAssertEqual(CourseEngine.consecutiveFailStreak(eligibleTakes: [
            (true, false), (false, false),
        ]), 1)
    }

    // MARK: reactToAnalyzedTake（3-10）

    @MainActor
    func testNotStartedWithMidiStartsPracticing() throws {
        let context = ModelContext(try makeContainer())
        let piece = makePiece(number: 45, status: "notStarted", in: context)

        // 无 MIDI take 不触发（首个有效 take 才转 practicing）
        XCTAssertEqual(react(piece, hasMidi: false, in: context), .none)
        XCTAssertEqual(piece.status, "notStarted")

        // 有 MIDI → practicing（ADR 转换 2）
        XCTAssertEqual(react(piece, hasMidi: true, in: context), .startedPracticing)
        XCTAssertEqual(piece.status, "practicing")
    }

    @MainActor
    func testTwoConsecutivePassesAdvanceAndUnlockNext() throws {
        let context = ModelContext(try makeContainer())
        let piece = makePiece(number: 45, in: context)
        insertTake(piece, eligible: true, passed: true, startedAt: Date(timeIntervalSinceNow: -200), in: context)
        insertTake(piece, eligible: true, passed: true, startedAt: Date(timeIntervalSinceNow: -100), in: context)

        let event = react(piece, in: context)
        XCTAssertEqual(event, .passedAdvanced)
        XCTAssertEqual(piece.status, "passed")
        XCTAssertEqual(piece.passedRulesVersion, CourseEngine.scoringRulesVersion, "过关留痕规则版本")
        XCTAssertEqual(piece.intervalStage, 0, "过关从第 0 档起")
        XCTAssertEqual(dayDiff(from: Date(), to: piece.nextReviewAt ?? .distantFuture), 1, "首次复习间隔 1 天")

        // 下一条立刻解锁为 notStarted（Q2：不等下次会话）
        let next = fetchPiece(book: "拜厄", number: 46, in: context)
        XCTAssertNotNil(next)
        XCTAssertEqual(next?.status, "notStarted")

        // 派生游标推进到下一条
        let pathState = try context.fetch(FetchDescriptor<CoursePathState>()).first
        XCTAssertEqual(pathState?.currentBeyer, 46)
    }

    @MainActor
    func testThreeConsecutiveFailuresRegress() throws {
        let context = ModelContext(try makeContainer())
        let current = makePiece(number: 3, in: context)
        let previous = makePiece(number: 2, status: "passed", in: context)
        for offset in 0..<3 {
            insertTake(current, eligible: true, passed: false,
                       startedAt: Date(timeIntervalSinceNow: Double(offset * 60 - 300)), in: context)
        }

        XCTAssertEqual(react(current, passed: false, in: context), .regressed)
        // 原子两落态（Q13）：当前→notStarted、上一条 passed→practicing
        XCTAssertEqual(current.status, "notStarted")
        XCTAssertEqual(previous.status, "practicing")

        // 游标回退到上一条
        let pathState = try context.fetch(FetchDescriptor<CoursePathState>()).first
        XCTAssertEqual(pathState?.currentBeyer, 2)
    }

    @MainActor
    func testRegressAtPlacementHeadKeepsWaivedPrevious() throws {
        let context = ModelContext(try makeContainer())
        // 定级插入点第 1 条（其上一条是 waived 终态）：1 waived + 2 practicing
        _ = makePiece(number: 1, status: "waived", in: context)
        let head = makePiece(number: 2, in: context)
        for offset in 0..<3 {
            insertTake(head, eligible: true, passed: false,
                       startedAt: Date(timeIntervalSinceNow: Double(offset * 60 - 300)), in: context)
        }

        XCTAssertEqual(react(head, passed: false, in: context), .regressed)
        // waived 是终态，不改回 practicing；当前条目回 notStarted 重新开始
        XCTAssertEqual(head.status, "notStarted")
        XCTAssertEqual(fetchPiece(book: "拜厄", number: 1, in: context)?.status, "waived")
    }

    @MainActor
    func testIneligibleTakeIsNeutralForStreaks() throws {
        let context = ModelContext(try makeContainer())
        let piece = makePiece(number: 10, in: context)
        // 历史：1 pass + 2 fail（failStreak=2 < 3），再夹一条不可评 take
        insertTake(piece, eligible: true, passed: true, startedAt: Date(timeIntervalSinceNow: -400), in: context)
        insertTake(piece, eligible: true, passed: false, startedAt: Date(timeIntervalSinceNow: -300), in: context)
        insertTake(piece, eligible: true, passed: false, startedAt: Date(timeIntervalSinceNow: -200), in: context)
        insertTake(piece, eligible: false, passed: false, startedAt: Date(timeIntervalSinceNow: -100), in: context)

        // 非可评 take：不触发过关/回退，也不清零既有的 fail 连计（failStreak 仍 2）
        XCTAssertEqual(react(piece, canEvaluate: false, passed: false, in: context), .none)
        XCTAssertEqual(piece.status, "practicing")

        // 补一条可评 fail → failStreak=3 → 回退（证明不可评夹在中间没有清零）
        insertTake(piece, eligible: true, passed: false, startedAt: Date(), in: context)
        XCTAssertEqual(react(piece, canEvaluate: true, passed: false, in: context), .regressed)
        XCTAssertEqual(piece.status, "notStarted")
    }

    @MainActor
    func testReviewCompletedAdvancesStage() throws {
        let context = ModelContext(try makeContainer())
        // 已过关一条、当前在 stage 1（下次间隔 3 天档）复习中
        let piece = makePiece(number: 5, status: "reviewing", intervalStage: 1, in: context)

        // 非可评 take：中性，保持 reviewing
        XCTAssertEqual(react(piece, canEvaluate: false, passed: false, in: context), .none)
        XCTAssertEqual(piece.status, "reviewing")

        // 单次达标 → passed、进一档（stage 2 → +7 天）
        XCTAssertEqual(react(piece, canEvaluate: true, passed: true, in: context), .reviewCompleted)
        XCTAssertEqual(piece.status, "passed")
        XCTAssertEqual(piece.intervalStage, 2)
        XCTAssertEqual(dayDiff(from: Date(), to: piece.nextReviewAt ?? .distantFuture), 7)
    }

    @MainActor
    func testReviewFailedBackToPracticing() throws {
        let context = ModelContext(try makeContainer())
        let piece = makePiece(number: 5, status: "reviewing", intervalStage: 2, in: context)

        XCTAssertEqual(react(piece, canEvaluate: true, passed: false, in: context), .reviewFailed)
        XCTAssertEqual(piece.status, "practicing", "复习 take 不达标 → 退回 practicing（Q9）")
    }

    @MainActor
    func testReviewIneligibleStaysReviewing() throws {
        let context = ModelContext(try makeContainer())
        let piece = makePiece(number: 5, status: "reviewing", intervalStage: 0, in: context)

        XCTAssertEqual(react(piece, canEvaluate: false, passed: false, in: context), .none)
        XCTAssertEqual(piece.status, "reviewing", "非可评 take 中性：保持 reviewing")
    }

    // MARK: 解锁 / 游标（11-13）

    @MainActor
    func testBeyer106PassUnlocks599() throws {
        let context = ModelContext(try makeContainer())
        let last = makePiece(number: 106, in: context)
        insertTake(last, eligible: true, passed: true, startedAt: Date(timeIntervalSinceNow: -100), in: context)
        insertTake(last, eligible: true, passed: true, startedAt: Date(), in: context)

        XCTAssertEqual(react(last, in: context), .passedAdvanced)
        // 599 第 1 条解锁为 notStarted，且 current599 = 1（599 开始的唯一信号）
        let first599 = fetchPiece(book: "车尔尼599", number: 1, in: context)
        XCTAssertNotNil(first599, "拜厄 106 通关 → 解锁 599 #1")
        XCTAssertEqual(first599?.status, "notStarted")
        let pathState = try context.fetch(FetchDescriptor<CoursePathState>()).first
        XCTAssertEqual(pathState?.current599, 1)
        // 拜厄轨全通关 → currentBeyer = 107（通关值）
        XCTAssertEqual(pathState?.currentBeyer, 107)
    }

    @MainActor
    func testUnlockDoesNotSkipAhead() throws {
        let context = ModelContext(try makeContainer())
        let piece = makePiece(number: 45, in: context)
        insertTake(piece, eligible: true, passed: true, startedAt: Date(timeIntervalSinceNow: -100), in: context)
        insertTake(piece, eligible: true, passed: true, startedAt: Date(), in: context)

        XCTAssertEqual(react(piece, in: context), .passedAdvanced)
        XCTAssertNotNil(fetchPiece(book: "拜厄", number: 46, in: context), "只解锁紧邻下一条")
        XCTAssertNil(fetchPiece(book: "拜厄", number: 47, in: context), "顺序解锁铁律：不提前解锁 n+2")
    }

    @MainActor
    func testRefreshDerivedCursors() throws {
        let context = ModelContext(try makeContainer())
        // waived 跳过、reviewing 不计入主游标、practicing 劫持最小
        _ = makePiece(number: 1, status: "waived", in: context)
        _ = makePiece(number: 2, status: "passed", in: context)
        _ = makePiece(number: 3, status: "reviewing", in: context)
        _ = makePiece(number: 4, status: "notStarted", in: context)
        _ = makePiece(number: 5, status: "practicing", in: context)
        _ = makePiece(book: "哈农", number: 7, status: "notStarted", in: context)

        CourseEngine.refreshDerivedCursors(in: context)
        let pathState = try context.fetch(FetchDescriptor<CoursePathState>()).first
        XCTAssertEqual(pathState?.currentBeyer, 4, "当前 = 最小 practicing/notStarted；waived/passed/reviewing 跳过")

        // 全通关（无 practicing/notStarted）→ 通关值 107
        let all = try context.fetch(FetchDescriptor<Piece>())
        for piece in all where piece.book == "拜厄" {
            piece.status = "passed"
        }
        CourseEngine.refreshDerivedCursors(in: context)
        XCTAssertEqual(pathState?.currentBeyer, 107, "全 passed/waived → 通关值（106+1）")
    }

    // MARK: 复习 roll（14）

    @MainActor
    func testRollDueReviews() throws {
        let context = ModelContext(try makeContainer())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let due = makePiece(number: 1, status: "passed", nextReviewAt: yesterday, in: context)
        let notDue = makePiece(number: 2, status: "passed", nextReviewAt: tomorrow, in: context)
        _ = makePiece(number: 3, status: "passed", nextReviewAt: nil, in: context) // 无 nextReviewAt 不进池
        let practicing = makePiece(number: 4, status: "practicing", nextReviewAt: yesterday, in: context) // 非 passed

        let rolled = CourseEngine.rollDueReviews(asOf: Date(), in: context)
        XCTAssertEqual(rolled.map(\.entityId), [due.entityId], "只翻到期条目，且返回被翻转的条目")
        XCTAssertEqual(due.status, "reviewing")
        XCTAssertEqual(notDue.status, "passed", "未到期不动")
        // nextReviewAt 保留（留作排序/审计）
        XCTAssertNotNil(due.nextReviewAt)
        XCTAssertEqual(practicing.status, "practicing")
    }

    // MARK: 定级补建 / 既有用户对账（15-16）

    @MainActor
    func testBootstrapPiecesForPlacement() throws {
        let context = ModelContext(try makeContainer())
        CourseEngine.bootstrapPiecesForPlacement(beyerEntry: 45, hanonEntry: 1, in: context)

        // 拜厄 1-44 waived、45 notStarted
        let first = fetchPiece(book: "拜厄", number: 1, in: context)
        XCTAssertEqual(first?.status, "waived")
        XCTAssertEqual(fetchPiece(book: "拜厄", number: 44, in: context)?.status, "waived")
        XCTAssertEqual(fetchPiece(book: "拜厄", number: 45, in: context)?.status, "notStarted")
        XCTAssertNil(fetchPiece(book: "拜厄", number: 46, in: context), "不预置插入点之后的行")
        // 哈农插入点 1：无 waived、1 notStarted
        XCTAssertNil(fetchPiece(book: "哈农", number: 0, in: context))
        XCTAssertEqual(fetchPiece(book: "哈农", number: 1, in: context)?.status, "notStarted")

        // 幂等：重复调用不改已有状态
        fetchPiece(book: "拜厄", number: 45, in: context)?.status = "practicing"
        CourseEngine.bootstrapPiecesForPlacement(beyerEntry: 45, hanonEntry: 1, in: context)
        XCTAssertEqual(fetchPiece(book: "拜厄", number: 45, in: context)?.status, "practicing", "已存在不动")

        // refresh 后游标 = 插入点
        let pathState = try context.fetch(FetchDescriptor<CoursePathState>()).first
        XCTAssertEqual(pathState?.currentBeyer, 45)
        XCTAssertEqual(pathState?.currentHanon, 1)
    }

    @MainActor
    func testReconcileIfNeeded() throws {
        let context = ModelContext(try makeContainer())

        // 未定级：no-op
        CourseEngine.reconcileIfNeeded(in: context)
        XCTAssertNil(fetchPiece(book: "拜厄", number: 20, in: context))

        // 已定级 + 无拜厄 Piece → 按游标补建（waived + 当前 notStarted）
        let pathState = try context.fetch(FetchDescriptor<CoursePathState>()).first
        pathState?.placementResultId = UUID()
        pathState?.currentBeyer = 20
        pathState?.currentHanon = 3
        CourseEngine.reconcileIfNeeded(in: context)
        XCTAssertEqual(fetchPiece(book: "拜厄", number: 19, in: context)?.status, "waived")
        XCTAssertEqual(fetchPiece(book: "拜厄", number: 20, in: context)?.status, "notStarted")
        XCTAssertEqual(fetchPiece(book: "哈农", number: 2, in: context)?.status, "waived")
        XCTAssertEqual(fetchPiece(book: "哈农", number: 3, in: context)?.status, "notStarted")
        XCTAssertEqual(pathState?.currentBeyer, 20, "refresh 后游标不变")
        XCTAssertEqual(pathState?.currentHanon, 3)

        // 幂等：已有拜厄 Piece 时 no-op（不重置、不重建）
        fetchPiece(book: "拜厄", number: 20, in: context)?.status = "practicing"
        CourseEngine.reconcileIfNeeded(in: context)
        XCTAssertEqual(fetchPiece(book: "拜厄", number: 20, in: context)?.status, "practicing")
        XCTAssertEqual(fetchPiece(book: "拜厄", number: 21, in: context), nil)
    }
}

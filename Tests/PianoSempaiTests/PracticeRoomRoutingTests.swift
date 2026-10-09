import SwiftData
import XCTest
@testable import PianoSempai

/// Today → 练习室路由纯决策（Fix 批次 2026-09-30）：谱坐标解析 / 循环格诚实文案 /
/// 断连顶栏副行按真实 phase。纯函数断言，不依赖视图；Stage B §4 追加的
/// resolveRoomPiece / TodayReviewPicker 用 in-memory 容器（对齐 CourseEngineTests harness）。
final class PracticeRoomRoutingTests: XCTestCase {

    // MARK: Stage B §4 夹具（resolveRoomPiece / TodayReviewPicker）

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: AppSettings.self, PlacementResult.self, CoursePathState.self,
            Piece.self, ScoreFile.self, Take.self, TakeAnalysis.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    // MARK: BundledScoreCoordinates.resolve

    func testResolveBeyerBounds() {
        XCTAssertEqual(BundledScoreCoordinates.resolve(book: "拜厄", number: 1),
                       BundledScoreCoordinates(book: "拜厄", number: 1))
        XCTAssertEqual(BundledScoreCoordinates.resolve(book: "拜厄", number: 106),
                       BundledScoreCoordinates(book: "拜厄", number: 106))
        XCTAssertNil(BundledScoreCoordinates.resolve(book: "拜厄", number: 107))
    }

    func testResolveHanonBounds() {
        XCTAssertEqual(BundledScoreCoordinates.resolve(book: "哈农", number: 20),
                       BundledScoreCoordinates(book: "哈农", number: 20))
        XCTAssertNil(BundledScoreCoordinates.resolve(book: "哈农", number: 21))
    }

    func testResolveNonBundledBookIsNil() {
        XCTAssertNil(BundledScoreCoordinates.resolve(book: "车尔尼599", number: 1))
    }

    func testResolveNilOrEmptyBookIsNil() {
        XCTAssertNil(BundledScoreCoordinates.resolve(book: nil, number: 1))
        XCTAssertNil(BundledScoreCoordinates.resolve(book: "", number: 1))
    }

    // MARK: LoopConfig.cellLabel(totalMeasures:)

    func testCellLabelNoScoreIsNil() {
        // 无谱（totalMeasures 0）：不给区间文案，也不给假默认 1–8
        XCTAssertNil(LoopConfig().cellLabel(totalMeasures: 0))
    }

    func testCellLabelValidRange() {
        // 有效区间：起–止小节（en dash U+2013）
        XCTAssertEqual(LoopConfig().cellLabel(totalMeasures: 8), "1–8小节")
    }

    func testCellLabelRangeExceedingScoreIsNil() {
        // 默认 1…8 但曲目只有 6 小节：区间无效 → nil（不显示越界假数据）
        XCTAssertNil(LoopConfig().cellLabel(totalMeasures: 6))
    }

    // MARK: PracticeStatusSubtitle.text

    func testSubtitleIdle() {
        XCTAssertEqual(PracticeStatusSubtitle.text(phase: .idle), "待开始")
    }

    func testSubtitleActiveTake() {
        XCTAssertEqual(PracticeStatusSubtitle.text(phase: .counting), "Take · 练习进行中")
        XCTAssertEqual(PracticeStatusSubtitle.text(phase: .performing), "Take · 练习进行中")
        XCTAssertEqual(PracticeStatusSubtitle.text(phase: .paused), "Take · 练习进行中")
    }

    func testSubtitleFinished() {
        XCTAssertEqual(PracticeStatusSubtitle.text(phase: .finished), "已结束")
    }

    // MARK: CourseEngine.resolveRoomPiece（Stage B §4.1）
    // 上下文用 `ModelContext(container)`（对齐 CourseEngineTests harness；
    // in-memory 容器的 mainContext 在测试环境会触发 SwiftData trap）。

    /// 已有 Piece 行：原样返回同一行（不改状态、不重建，幂等）
    func testResolveRoomPieceExistingRowReturned() throws {
        let context = ModelContext(try makeContainer())
        let piece = Piece(title: "拜厄 第1条", book: "拜厄", number: 1, status: "passed")
        context.insert(piece)
        try context.save()

        let resolved = CourseEngine.resolveRoomPiece(book: "拜厄", number: 1, in: context)
        XCTAssertEqual(resolved?.entityId, piece.entityId)
        XCTAssertEqual(resolved?.status, "passed") // 不被建档逻辑重置
    }

    /// 无行但内置目录有该条：ensurePiece 建档返回，status=notStarted（只建行、不改状态）
    func testResolveRoomPieceCreatesFromCatalog() throws {
        let context = ModelContext(try makeContainer())

        let resolved = CourseEngine.resolveRoomPiece(book: "拜厄", number: 1, in: context)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.book, "拜厄")
        XCTAssertEqual(resolved?.number, 1)
        XCTAssertEqual(resolved?.status, "notStarted")

        // 幂等：第二次解析返回同一行
        let again = CourseEngine.resolveRoomPiece(book: "拜厄", number: 1, in: context)
        XCTAssertEqual(again?.entityId, resolved?.entityId)
    }

    /// book+number 不在内置目录（异常/越界）：nil，诚实降级（take 不带 pieceId）
    func testResolveRoomPieceNotInCatalogIsNil() throws {
        let context = ModelContext(try makeContainer())
        XCTAssertNil(CourseEngine.resolveRoomPiece(book: "拜厄", number: 107, in: context))
        XCTAssertNil(CourseEngine.resolveRoomPiece(book: "不存在教材", number: 1, in: context))
    }

    // MARK: TodayReviewPicker.pick（Stage B §4.2）

    private func makeReviewingPiece(
        _ number: Int, nextReviewAt: Date?, in context: ModelContext
    ) -> Piece {
        let piece = Piece(
            title: "拜厄 第\(number)条", book: "拜厄", number: number,
            status: CourseEngine.statusReviewing, nextReviewAt: nextReviewAt
        )
        context.insert(piece)
        return piece
    }

    /// 多个 reviewing：取 nextReviewAt 最早者（ADR「nextReviewAt 最早优先」）
    func testPickReturnsEarliestNextReviewAt() throws {
        let context = ModelContext(try makeContainer())
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        _ = makeReviewingPiece(1, nextReviewAt: base.addingTimeInterval(7200), in: context)
        let earliest = makeReviewingPiece(2, nextReviewAt: base, in: context)
        _ = makeReviewingPiece(3, nextReviewAt: base.addingTimeInterval(3600), in: context)

        let picked = TodayReviewPicker.pick((try? context.fetch(FetchDescriptor<Piece>())) ?? [])
        XCTAssertEqual(picked?.entityId, earliest.entityId)
    }

    /// 非 reviewing（practicing / passed）不参与选择
    func testPickIgnoresNonReviewingPieces() throws {
        let context = ModelContext(try makeContainer())
        let practicing = Piece(title: "拜厄 第1条", book: "拜厄", number: 1, status: "practicing")
        let passed = Piece(title: "拜厄 第2条", book: "拜厄", number: 2, status: "passed")
        context.insert(practicing)
        context.insert(passed)

        XCTAssertNil(TodayReviewPicker.pick([practicing, passed]))
    }

    /// 空列表 → nil（无 reviewing 条目今日不出复习卡）
    @MainActor
    func testPickEmptyIsNil() {
        XCTAssertNil(TodayReviewPicker.pick([]))
    }

    // MARK: taskType "review" 文案（Stage B §4.3；可抽出的纯函数层）

    func testContextBuilderTaskTypeLabelReview() {
        XCTAssertEqual(ContextBuilder.taskTypeLabel("review"), "review（复习）")
    }
}

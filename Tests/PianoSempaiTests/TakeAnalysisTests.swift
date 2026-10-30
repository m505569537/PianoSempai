import SwiftData
import XCTest
@testable import PianoSempai

/// M6b 验收（Hermes）：
/// ① 分析只算真实维度、不可测维度空标（无编造值）；
/// ② 被标谱错小节从错音率剔除、其他小节不受影响；
/// ③ 自由弹奏 take 无分析/门禁字段；
/// ④ 报告分析绝不写课程解锁状态。
final class TakeAnalysisTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Take.self, ScoreErrorMark.self, Piece.self, CoursePathState.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
    }

    private func makeTake(
        noteCount: Int = 132,
        wrongNoteRecords: [String] = ["21:62", "21:64", "22:59", "18:70"],
        wrongNoteCount: Int? = nil,
        isFreePlay: Bool = false
    ) -> Take {
        let take = Take(
            durationSec: 134,
            taskType: isFreePlay ? "free" : "main",
            hasMidi: true,
            isFreePlay: isFreePlay,
            tempoAvg: 72,
            noteCount: noteCount,
            wrongNoteCount: wrongNoteCount ?? wrongNoteRecords.count,
            pedalEventCount: 4,
            midiEventCount: 1284
        )
        take.wrongNoteRecords = wrongNoteRecords
        return take
    }

    // MARK: PieceTrend（S09「全部 Take 与趋势」序列构建；PRD 288/210）

    /// 带可分辨 startedAt 的 take（daysAgo 越大越旧）
    private func makeDatedTake(daysAgo: Int) -> Take {
        let take = Take(durationSec: 100, taskType: "main", hasMidi: true, tempoAvg: 60)
        take.startedAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return take
    }

    func testPieceTrendPointsAreChronologicalRegardlessOfInputOrder() {
        let oldest = makeDatedTake(daysAgo: 30)
        let middle = makeDatedTake(daysAgo: 20)
        let newest = makeDatedTake(daysAgo: 10)
        let analyses = [
            TakeAnalysis(takeId: newest.entityId, engineVersion: "test", weakTotal: 90),
            TakeAnalysis(takeId: oldest.entityId, engineVersion: "test", weakTotal: 60),
            TakeAnalysis(takeId: middle.entityId, engineVersion: "test", weakTotal: 75),
        ]
        let points = PieceTrend.points(series: .weakTotal, takes: [middle, newest, oldest], analyses: analyses)
        XCTAssertEqual(points.map(\.value), [60, 75, 90], "乱序输入 → startedAt 升序输出")
        XCTAssertEqual(points.map(\.index), [0, 1, 2], "index 是序列序（画图 x 轴），与输入顺序无关")
    }

    func testPieceTrendSkipsTakesWithoutRealValue() {
        let withScore = makeDatedTake(daysAgo: 20)
        let noAnalysis = makeDatedTake(daysAgo: 15)
        let nilDimension = makeDatedTake(daysAgo: 10) // 力度不可测 → dynamicsScore nil
        let analyses = [
            TakeAnalysis(takeId: withScore.entityId, engineVersion: "test", dynamicsScore: 70),
            TakeAnalysis(takeId: nilDimension.entityId, engineVersion: "test", pitchScore: 88),
        ]
        let dynamics = PieceTrend.points(series: .dynamics, takes: [noAnalysis, withScore, nilDimension], analyses: analyses)
        XCTAssertEqual(
            dynamics.map(\.value), [70],
            "无真实值的 take 不产点（无零值、无插值）；存活值恰为真实值"
        )
        // 换一条序列，nil 维度的 take 在它自己的维度上有真实值
        let pitch = PieceTrend.points(series: .pitch, takes: [withScore, nilDimension], analyses: analyses)
        XCTAssertEqual(pitch.map(\.value), [88], "各维度各画各的真实序列")
    }

    func testPieceTrendLatestAnalysisWinsPerTake() {
        let take = makeDatedTake(daysAgo: 5)
        let older = TakeAnalysis(
            takeId: take.entityId, analyzedAt: Date(timeIntervalSinceNow: -3600),
            engineVersion: "test", weakTotal: 40
        )
        let newer = TakeAnalysis(
            takeId: take.entityId, analyzedAt: Date(),
            engineVersion: "test", weakTotal: 82
        )
        let points = PieceTrend.points(series: .weakTotal, takes: [take], analyses: [older, newer])
        XCTAssertEqual(points.map(\.value), [82], "同 take 多条分析 → analyzedAt 最新者胜")
    }

    func testPieceTrendCanDrawTrendRequiresTwoRealPoints() {
        XCTAssertFalse(PieceTrend.canDrawTrend([]), "没有真实点不画")
        let single = [PieceTrend.Point(index: 0, value: 60, date: Date())]
        XCTAssertFalse(PieceTrend.canDrawTrend(single), "1 个真实点不画——视图据此显「数据不足」")
        let two = single + [PieceTrend.Point(index: 1, value: 80, date: Date())]
        XCTAssertTrue(PieceTrend.canDrawTrend(two), "≥2 个真实点才画趋势")
    }

    // MARK: ① 真实维度 + 不可测维度空标（无编造）

    func testAnalysisComputesRealDimsAndFlagsUnmeasurable() {
        let analysis = TakeAnalysisService.analyze(take: makeTake(), errorMarks: [])
        // 真实维度逐项等于 take 真值
        XCTAssertEqual(analysis.durationSec, 134)
        XCTAssertEqual(analysis.noteCount, 132)
        XCTAssertEqual(analysis.pedalEventCount, 4)
        XCTAssertEqual(analysis.midiEventCount, 1284)
        XCTAssertEqual(analysis.tempoAvg, 72)
        XCTAssertEqual(analysis.wrongNotes.count, 4)
        XCTAssertEqual(analysis.effectiveWrongCount, 4)
        // 错音率真实可算
        XCTAssertEqual(analysis.wrongNoteRate ?? 0, 4.0 / 132.0, accuracy: 0.0001)
        // M5b：P1 不提供六维/热力/弱总成的占位名单已删除——
        // 没有数据就由 P2TakeReport 显式「数据不足」，不留假装会有的文案
        XCTAssertNil(TakeReportPresentation.build(analysis: nil, standards: .beginner).weakTotal)
        XCTAssertEqual(TakeReportPresentation.build(analysis: nil, standards: .beginner).state, .noAnalysis)
        // 无标记时剔除不生效
        XCTAssertFalse(analysis.exclusionApplied)
    }

    func testZeroNoteTakeYieldsNilRateNotFakeZero() {
        let analysis = TakeAnalysisService.analyze(take: makeTake(noteCount: 0, wrongNoteRecords: [], wrongNoteCount: 0), errorMarks: [])
        XCTAssertNil(analysis.wrongNoteRate, "0 音符时不显示 0% 错音率（不编数字）")
    }

    // MARK: ② 谱错小节剔除（引擎规则）

    func testMarkedMeasureExcludedFromWrongNoteRate() {
        let marks = [
            ScoreErrorMark(scoreName: "样例", measure: 21, type: "note"),
            ScoreErrorMark(scoreName: "样例", measure: 22, type: "note"),
        ]
        let analysis = TakeAnalysisService.analyze(take: makeTake(), errorMarks: marks)
        // 21、22 被剔除（3 条），18 保留（1 条）——其他小节不受影响
        XCTAssertEqual(analysis.excludedMeasures, [21, 22])
        XCTAssertEqual(analysis.effectiveWrongCount, 1)
        XCTAssertEqual(analysis.wrongNoteRate ?? 0, 1.0 / 132.0, accuracy: 0.0001)
        XCTAssertTrue(analysis.exclusionApplied)

        // 未标记任何小节时全部计入
        let clean = TakeAnalysisService.analyze(take: makeTake(), errorMarks: [])
        XCTAssertEqual(clean.effectiveWrongCount, 4)
    }

    func testLegacyTakeWithoutDetailsSkipsExclusionHonestly() {
        // 旧 take 只有总数、无逐音明细
        let legacy = makeTake(wrongNoteRecords: [], wrongNoteCount: 5)
        let marks = [ScoreErrorMark(scoreName: "样例", measure: 21, type: "note")]
        let analysis = TakeAnalysisService.analyze(take: legacy, errorMarks: marks)
        XCTAssertFalse(analysis.hasDetail)
        XCTAssertEqual(analysis.effectiveWrongCount, 5, "无明细时不能假装做了剔除")
        XCTAssertFalse(analysis.exclusionApplied)
    }

    // MARK: ③ 自由弹奏 take：无分析/门禁字段

    @MainActor
    func testFreePlayTakePersistsWithoutScoringOrGateFields() throws {
        var summary = TakeSummary()
        summary.durationSec = 754
        summary.noteCount = 486
        summary.tempoAvg = 0 // 自由弹奏无参考速度
        summary.midiEventCount = 1500
        summary.midiFileName = "take-free.jsonl"

        let take = PracticeSession.persist(
            summary, taskType: "free", isFreePlay: true,
            startedAt: Date(), interruptions: [], title: "瞎弹了一段 Summer",
            in: context
        )
        try context.save()

        XCTAssertEqual(take.taskType, "free")
        XCTAssertTrue(take.isFreePlay)
        XCTAssertNil(take.measureFrom, "自由弹奏无小节区间（无跟谱）")
        XCTAssertNil(take.measureTo)
        // 无分析产物：P1 分析表不存在，take 上也没有判分维度字段（类型层面即无）
        // 无门禁关联：不产生 GateEvent
        let gates = try context.fetch(FetchDescriptor<GateEvent>())
        XCTAssertTrue(gates.isEmpty)
        // 分析器对自由弹奏 take 也能如实计算（统计维度真实、无六维）
        let analysis = TakeAnalysisService.analyze(take: take, errorMarks: [])
        XCTAssertEqual(analysis.noteCount, 486)
        // 无分析行 → 报告诚实空态（不编六维、不给弱总分）
        let report = TakeReportPresentation.build(analysis: nil, standards: .beginner)
        XCTAssertEqual(report.state, .noAnalysis)
        XCTAssertTrue(report.dimensions.isEmpty)
        XCTAssertNil(report.weakTotal)
        XCTAssertFalse(report.canEvaluate)
    }

    // MARK: ④ 报告分析绝不写课程解锁状态

    @MainActor
    func testReportAnalysisNeverWritesCourseUnlockState() throws {
        let pathState = CoursePathState(currentBeyer: 45, currentHanon: 1, projected599Week: 8)
        context.insert(pathState)
        let piece = Piece(title: "拜厄 第45条", book: "拜厄", number: 45, status: "practicing")
        context.insert(piece)
        try context.save()

        let take = makeTake()
        context.insert(take)
        let marks = [ScoreErrorMark(scoreName: "样例", measure: 21, type: "note")]
        context.insert(marks[0])

        // 跑分析（任意次）
        for _ in 0..<3 {
            _ = TakeAnalysisService.analyze(take: take, errorMarks: marks)
        }
        try context.save()

        // 课程状态零变化（analyze 是只读；连续 2 遍达标判定只在课程引擎消费时发生）
        let states = try context.fetch(FetchDescriptor<CoursePathState>())
        XCTAssertEqual(states.first?.currentBeyer, 45)
        XCTAssertEqual(states.first?.currentHanon, 1)
        let pieces = try context.fetch(FetchDescriptor<Piece>())
        XCTAssertEqual(pieces.first?.status, "practicing")
        XCTAssertEqual(pieces.first?.suspectedErrorCount, 0)
    }
}

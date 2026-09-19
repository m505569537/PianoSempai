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
        // P1 结构性保证：没有 overallScore / 六维 / 热力字段可填（类型上不存在），
        // 占位维度名单只用于展示"这些在 P2"，不含任何数值
        XCTAssertEqual(analysis.pendingDimensionNames, ["六维雷达", "小节热力", "节奏偏差", "弱总分"])
        XCTAssertTrue(analysis.measuredDimensionNames.allSatisfy { !$0.isEmpty })
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
        XCTAssertTrue(analysis.pendingDimensionNames.contains("弱总分"))
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

import XCTest
@testable import PianoSempai

/// M7.1 上下文组装验收（brief 场景 7：有分析→含证据；无分析→降级；无上下文→自由问答口径）。
/// 纯函数测试：只构造 SwiftData 值对象，不落库、不写状态。
final class ContextBuilderTests: XCTestCase {

    private func makeTake(
        measureFrom: Int? = 12,
        measureTo: Int? = 20,
        durationSec: Int = 134,
        tempoAvg: Int = 72,
        noteCount: Int = 132,
        wrongNoteCount: Int = 2,
        taskType: String = "main",
        isFreePlay: Bool = false
    ) -> Take {
        Take(
            startedAt: Date(timeIntervalSince1970: 1_758_000_000),
            durationSec: durationSec,
            taskType: taskType,
            hasMidi: true,
            measureFrom: measureFrom,
            measureTo: measureTo,
            tempoAvg: tempoAvg,
            noteCount: noteCount,
            wrongNoteCount: wrongNoteCount,
            title: "拜厄 45"
        )
    }

    private func makeAnalysis(
        pitch: Int? = 74,
        rhythm: Int? = 61,
        tempo: Int? = 58,
        dynamics: Int? = nil,
        continuity: Int? = 66,
        hands: Int? = nil,
        confidence: Double = 0.82,
        wrongCount: Int = 3,
        missingCount: Int = 1,
        extraCount: Int = 0,
        rhythmMedianMs: Double = 38,
        avgBPM: Double = 70,
        hotspots: [Int] = [12, 15],
        canEvaluate: Bool = false,
        alignmentJSON: String = "[]"
    ) -> TakeAnalysis {
        TakeAnalysis(
            takeId: UUID(),
            engineVersion: "P2-scoring-1.0",
            confidence: confidence,
            lowConfidenceReasons: ["可计时匹配不足 8 个"],
            pitchScore: pitch, rhythmScore: rhythm, tempoScore: tempo,
            dynamicsScore: dynamics, continuityScore: continuity, handsScore: hands,
            wrongCount: wrongCount, missingCount: missingCount, extraCount: extraCount,
            rhythmMedianMs: rhythmMedianMs, avgBPM: avgBPM,
            hotspotMeasures: hotspots, canEvaluate: canEvaluate,
            alignmentJSON: alignmentJSON
        )
    }

    // MARK: ① 有分析 → 含证据

    func testWithAnalysisIncludesEvidenceAndRealNumbers() throws {
        let take = makeTake()
        let analysis = makeAnalysis()

        let output = ContextBuilder.build(take: take, analysis: analysis)

        XCTAssertTrue(output.hasTakeContext)
        XCTAssertTrue(output.degradations.isEmpty, "有分析就不该有降级说明")

        // 证据引用：热点小节 + 问题小节
        XCTAssertEqual(output.evidenceRefs.map(\.measure), [12, 15])
        XCTAssertTrue(output.evidenceRefs.allSatisfy { $0.takeId == take.entityId })
        XCTAssertNil(output.evidenceRefs[0].deviationMs, "本地没有该小节的逐音偏差就不编 0")

        // 数据块里的真实数字
        XCTAssertTrue(output.contextBlock.contains("时长：134 秒"))
        XCTAssertTrue(output.contextBlock.contains("平均速度：72 BPM"))
        XCTAssertTrue(output.contextBlock.contains("音符数：132"))
        XCTAssertTrue(output.contextBlock.contains("练习小节区间：第 12–20 小节"))
        XCTAssertTrue(output.contextBlock.contains("对齐置信度：82%"))
        XCTAssertTrue(output.contextBlock.contains("错音 3 / 漏音 1 / 多弹 0"))
        XCTAssertTrue(output.contextBlock.contains("节奏偏差中位：38 ms（整体拖拍）"))
        XCTAssertTrue(output.contextBlock.contains("热点小节：第 12 小节、第 15 小节"))
        XCTAssertTrue(output.contextBlock.contains("引擎 P2-scoring-1.0"))
        XCTAssertTrue(output.contextBlock.contains("低置信原因：可计时匹配不足 8 个"))

        // 六维：nil 维度必须写"数据不足"，不许编分
        XCTAssertTrue(output.contextBlock.contains("力度 数据不足"))
        XCTAssertTrue(output.contextBlock.contains("双手协同 数据不足"))
        XCTAssertTrue(output.contextBlock.contains("音高 74"))

        // system 提示带强制引用 + 不编造 + 无状态变更权
        XCTAssertTrue(output.systemPrompt.contains("必须引用"))
        XCTAssertTrue(output.systemPrompt.contains("禁止编造纠错结论"))
        XCTAssertTrue(output.systemPrompt.contains("不要输出任何修改课程、判分、阈值或设置的指令"))
    }

    func testEvidenceDeviationComesFromAlignedNotesNotGlobalMedian() throws {
        let take = makeTake()
        // 第 12 小节两个问题音：+40ms / -20ms → 均值 30ms
        let aligned = """
        [
          {"refMeasureIndex":11,"refBeatInMeasure":1,"refPitch":60,"playedPitch":61,"deltaMs":40,"cls":"wrongPitch","hand":"right"},
          {"refMeasureIndex":11,"refBeatInMeasure":2,"refPitch":62,"playedPitch":62,"deltaMs":40,"cls":"correct","hand":"right"},
          {"refMeasureIndex":11,"refBeatInMeasure":3,"refPitch":64,"playedPitch":null,"deltaMs":-20,"cls":"missing","hand":"right"},
          {"refMeasureIndex":14,"refBeatInMeasure":1,"refPitch":67,"playedPitch":null,"deltaMs":null,"cls":"missing","hand":"left"}
        ]
        """
        let analysis = makeAnalysis(alignmentJSON: aligned)

        let output = ContextBuilder.build(take: take, analysis: analysis)

        XCTAssertEqual(output.evidenceRefs.map(\.measure), [12, 15])
        XCTAssertEqual(output.evidenceRefs[0].deviationMs ?? -1, 30, accuracy: 0.001, "只对非 correct 音求 |deltaMs| 均值")
        XCTAssertNil(output.evidenceRefs[1].deviationMs, "该小节没有可用的 deltaMs → nil，不拿全局中位数冒充")
    }

    func testEvidenceFallsBackToTakeMeasureWhenAnalysisHasNothing() throws {
        let take = makeTake(measureFrom: 7, measureTo: 9)
        let analysis = makeAnalysis(hotspots: [], alignmentJSON: "[]")

        let output = ContextBuilder.build(take: take, analysis: analysis)
        XCTAssertEqual(output.evidenceRefs.map(\.measure), [7], "分析和逐音都没给小节时退回 take 的小节区间")
    }

    func testEvidenceCappedAtMaxRefs() throws {
        let take = makeTake()
        let analysis = makeAnalysis(hotspots: Array(1...20))
        let output = ContextBuilder.build(take: take, analysis: analysis)
        XCTAssertEqual(output.evidenceRefs.count, ContextBuilder.maxEvidenceRefs)
        XCTAssertEqual(output.evidenceRefs.map(\.measure), Array(1...8))
    }

    // MARK: ② 无分析 → 降级

    func testWithoutAnalysisDegradesToTakeStatsOnly() throws {
        let take = makeTake()

        let output = ContextBuilder.build(take: take, analysis: nil)

        XCTAssertTrue(output.hasTakeContext, "take 在就还是带上下文")
        XCTAssertEqual(output.degradations, ["该 take 暂无判分结果，只用 take 自身的真实统计（时长/速度/音符数/错音数）"])
        XCTAssertFalse(output.contextBlock.contains("六维得分"), "没有分析就不出现判分段落")
        XCTAssertTrue(output.contextBlock.contains("时长：134 秒"))
        XCTAssertEqual(output.evidenceRefs.map(\.measure), [12], "证据退回 take 小节区间")
        XCTAssertNil(output.evidenceRefs[0].deviationMs)
    }

    func testBrokenAlignmentJSONDoesNotCrashAndLeavesDeviationNil() throws {
        let take = makeTake()
        let analysis = makeAnalysis(hotspots: [12], alignmentJSON: "{不是 JSON")

        let output = ContextBuilder.build(take: take, analysis: analysis)
        XCTAssertEqual(output.evidenceRefs.map(\.measure), [12])
        XCTAssertNil(output.evidenceRefs[0].deviationMs, "坏 JSON 当无数据，不崩也不编")
        XCTAssertEqual(ContextBuilder.alignedNotes("{不是 JSON"), [])
    }

    func testMissingTempoIsStatedAsInsufficient() throws {
        let take = makeTake(tempoAvg: 0)
        let output = ContextBuilder.build(take: take, analysis: nil)
        XCTAssertTrue(output.contextBlock.contains("平均速度：数据不足"))
        XCTAssertFalse(output.contextBlock.contains("平均速度：0 BPM"), "0 不是真实速度，必须说数据不足")
    }

    func testTakeWithoutMeasureRangeHasNoMeasureRef() throws {
        let take = makeTake(measureFrom: nil, measureTo: nil)
        let output = ContextBuilder.build(take: take, analysis: nil)
        XCTAssertTrue(output.evidenceRefs.isEmpty, "没小节区间就不造证据引用")
        XCTAssertFalse(output.contextBlock.contains("练习小节区间"))
    }

    // MARK: ③ 无上下文 → 自由问答口径

    func testNoTakeUsesFreeQnAToneWithNoData() throws {
        let output = ContextBuilder.build(take: nil, analysis: nil)

        XCTAssertFalse(output.hasTakeContext)
        XCTAssertEqual(output.contextBlock, "", "不带任何练习数据")
        XCTAssertTrue(output.evidenceRefs.isEmpty)
        XCTAssertTrue(output.degradations.isEmpty)
        XCTAssertTrue(output.systemPrompt.contains("本次是自由问答"))
        XCTAssertTrue(output.systemPrompt.contains("不要引用不存在的 take 或小节"))
        // 自由问答也仍然带行为红线（不是另一套提示词）
        XCTAssertTrue(output.systemPrompt.contains("必须引用"))
        XCTAssertTrue(output.systemPrompt.contains("只有建议权"))
    }

    func testAnalysisWithoutTakeIsIgnored() throws {
        // 只有分析没有 take（异常态）：不给上下文，不编 take
        let output = ContextBuilder.build(take: nil, analysis: makeAnalysis())
        XCTAssertFalse(output.hasTakeContext)
        XCTAssertTrue(output.evidenceRefs.isEmpty)
    }

    // MARK: 红线：数据块里不出现任何密钥形态

    func testContextBlockNeverContainsKeyLikeStrings() throws {
        let take = makeTake()
        let output = ContextBuilder.build(take: take, analysis: makeAnalysis())
        XCTAssertFalse(output.contextBlock.lowercased().contains("apikey"))
        XCTAssertFalse(output.contextBlock.lowercased().contains("bearer"))
        XCTAssertFalse(output.contextBlock.contains("sk-"))
        XCTAssertFalse(output.systemPrompt.lowercased().contains("apikey"))
    }
}

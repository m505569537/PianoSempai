import SwiftData
import XCTest
@testable import PianoSempai

/// M5b：S13 报告呈现（TakeReportPresentation 纯函数）。
/// 验收：六维真实渲染、nil 维度诚实标注、统计级/无分析空态、问题音与热力解码、
/// 门禁三项与 CourseEngine gate 同源、连续达标透传；绝不编分（红线 1）。
final class ScoringPresentationTests: XCTestCase {

    // MARK: 夹具

    private func makeAnalysis(
        takeId: UUID = UUID(),
        pitch: Int? = 90,
        rhythm: Int? = 92,
        tempo: Int? = 88,
        dynamics: Int? = 70,
        continuity: Int? = 100,
        hands: Int? = nil,
        weakTotal: Int? = 88,
        wrong: Int = 1,
        missing: Int = 0,
        extra: Int = 1,
        referenceNoteCount: Int = 100,
        rhythmMedianMs: Double = 40,
        rhythmMeanMs: Double = 12,
        tempoTargetHit: Bool = true,
        avgBPM: Double = 62,
        canEvaluate: Bool = true,
        passesHardMetrics: Bool = true,
        confidence: Double = 0.92,
        lowConfidenceReasons: [String] = [],
        hotspotMeasures: [Int] = [2, 4],
        alignmentJSON: String = "[]",
        measureHeatJSON: String = "{\"2\":1.0,\"4\":0.5}"
    ) -> TakeAnalysis {
        TakeAnalysis(
            takeId: takeId, engineVersion: ScoringOrchestrator.engineVersion,
            confidence: confidence, lowConfidenceReasons: lowConfidenceReasons,
            pitchScore: pitch, rhythmScore: rhythm, tempoScore: tempo,
            dynamicsScore: dynamics, continuityScore: continuity, handsScore: hands,
            weakTotal: weakTotal,
            wrongCount: wrong, missingCount: missing, extraCount: extra,
            wrongPitchCount: wrong, referenceNoteCount: referenceNoteCount,
            rhythmMedianMs: rhythmMedianMs, rhythmMeanMs: rhythmMeanMs,
            tempoTargetHit: tempoTargetHit, avgBPM: avgBPM, hotspotMeasures: hotspotMeasures,
            measureHeatJSON: measureHeatJSON,
            canEvaluate: canEvaluate, passesHardMetrics: passesHardMetrics,
            alignmentJSON: alignmentJSON
        )
    }

    private func alignedJSON(_ notes: [AlignedNote]) -> String {
        (try? JSONEncoder().encode(notes)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    // MARK: 六维真实渲染

    func testScoredReportRendersAllDimensionsAndCounts() {
        let report = TakeReportPresentation.build(
            analysis: makeAnalysis(rhythmMeanMs: 45), standards: .beginner
        )
        XCTAssertEqual(report.state, .scored)
        XCTAssertEqual(report.dimensions.map(\.name), ["音高", "节奏", "速度稳定性", "力度", "连续性", "双手协同"])
        XCTAssertEqual(report.dimensions.map(\.score), [90, 92, 88, 70, 100, nil])
        XCTAssertEqual(report.weakTotal, 88)
        XCTAssertEqual(report.wrongCount, 1)
        XCTAssertEqual(report.missingCount, 0)
        XCTAssertEqual(report.extraCount, 1)
        XCTAssertEqual(report.rhythmMedianMs, 40, accuracy: 0.0001)
        XCTAssertEqual(report.rhythmTendency, "偏拖拍", "mean deltaMs > 带宽/4 且为正 → 偏拖拍（与 TakeScorer 同口径）")
        XCTAssertTrue(report.tempoTargetHit)
        XCTAssertEqual(report.hotspotMeasures, [2, 4])
        XCTAssertEqual(report.consecutivePasses, 0, "默认不透传连续次数")
    }

    /// nil 维度必须显式「数据不足」+ 原因，禁止填 0 或估算值
    func testNilDimensionsAreHonestNotFake() {
        let report = TakeReportPresentation.build(
            analysis: makeAnalysis(rhythm: nil, tempo: nil, dynamics: nil, continuity: nil),
            standards: .beginner
        )
        XCTAssertEqual(report.state, .scored)
        let byName = Dictionary(uniqueKeysWithValues: report.dimensions.map { ($0.name, $0) })
        XCTAssertNil(byName["节奏"]?.score)
        XCTAssertEqual(byName["节奏"]?.displayScore, "数据不足")
        XCTAssertFalse(byName["节奏"]?.note.isEmpty ?? true, "算不出要给原因")
        XCTAssertNil(byName["速度稳定性"]?.score)
        XCTAssertEqual(byName["速度稳定性"]?.displayScore, "数据不足")
        XCTAssertNil(byName["力度"]?.score)
        XCTAssertEqual(byName["连续性"]?.displayScore, "数据不足")
        // 单谱表 → 双手 nil（§6）
        XCTAssertNil(byName["双手协同"]?.score)
        XCTAssertTrue(byName["双手协同"]?.note.contains("单谱表") ?? false)
        // 有分的不受影响
        XCTAssertEqual(byName["音高"]?.score, 90)
    }

    func testRhythmTendencyLabels() {
        func tendency(_ meanMs: Double, _ windowMs: Double, measurable: Bool = true) -> String {
            TakeReportPresentation.tendency(meanMs: meanMs, windowMs: windowMs, measurable: measurable)
        }
        XCTAssertEqual(tendency(0, 120), "稳定", "|mean| < 带宽/4 → 稳定")
        XCTAssertEqual(tendency(40, 120), "偏拖拍")
        XCTAssertEqual(tendency(-40, 120), "偏抢拍")
        XCTAssertEqual(tendency(0, 120, measurable: false), "数据不足")
    }

    // MARK: 统计级 / 无分析：诚实态，不出对错分

    func testStatisticsOnlyReportHasNoScoresOrGate() {
        let row = makeAnalysis(
            pitch: nil, rhythm: nil, tempo: nil, dynamics: nil, continuity: nil,
            weakTotal: nil, canEvaluate: false, passesHardMetrics: false, confidence: 0,
            lowConfidenceReasons: ["暂无参考谱，不判定对错/过关"]
        )
        let report = TakeReportPresentation.build(analysis: row, standards: .beginner)
        XCTAssertEqual(report.state, .statistics)
        XCTAssertTrue(report.dimensions.isEmpty, "统计级不出六维行")
        XCTAssertNil(report.weakTotal, "不给弱总分")
        XCTAssertNil(report.dimensions.first?.score)
        XCTAssertFalse(report.canEvaluate)
        XCTAssertFalse(report.passesHardMetrics)
        XCTAssertTrue(report.passMetrics.isEmpty, "不进门禁就不展示三项")
        XCTAssertTrue(report.passGaps.isEmpty)
        XCTAssertEqual(report.consecutivePasses, 0, "统计级不累计连续达标")
        XCTAssertTrue(report.reasons.contains { $0.contains("暂无参考谱") })
    }

    func testNoAnalysisRowIsHonestEmptyState() {
        let report = TakeReportPresentation.build(analysis: nil, standards: .beginner)
        XCTAssertEqual(report.state, .noAnalysis)
        XCTAssertTrue(report.dimensions.isEmpty)
        XCTAssertNil(report.weakTotal)
        XCTAssertTrue(report.problems.isEmpty)
        XCTAssertTrue(report.measureHeat.isEmpty)
        XCTAssertFalse(report.canEvaluate)
        XCTAssertEqual(report.requiredConsecutivePasses, 2)
    }

    // MARK: 问题音定位 + 小节热力（从持久化 JSON 解码）

    func testProblemNotesDecodedFromAlignmentJSON() {
        let notes = [
            AlignedNote(refID: 0, refMeasureIndex: 2, refBeatInMeasure: 1, refPitch: 60,
                        playedPitch: 61, deltaMs: 8, cls: .wrongPitch, hand: .right),
            AlignedNote(refID: 1, refMeasureIndex: 4, refBeatInMeasure: 0, refPitch: 62,
                        playedPitch: nil, deltaMs: nil, cls: .missing, hand: .right),
            AlignedNote(refID: nil, refMeasureIndex: nil, refBeatInMeasure: nil, refPitch: nil,
                        playedPitch: 64, deltaMs: nil, cls: .extra, hand: .right),
            // correct 不进问题清单
            AlignedNote(refID: 2, refMeasureIndex: 2, refBeatInMeasure: 2, refPitch: 64,
                        playedPitch: 64, deltaMs: 0, cls: .correct, hand: .right),
        ]
        let report = TakeReportPresentation.build(
            analysis: makeAnalysis(alignmentJSON: alignedJSON(notes)), standards: .beginner
        )
        XCTAssertEqual(report.problems.count, 3, "correct 不算问题")
        XCTAssertEqual(report.problems[0].kind, .wrongPitch)
        XCTAssertEqual(report.problems[0].measure, 3, "measureIndex 0-based → 展示 1-based")
        XCTAssertEqual(report.problems[0].beatInMeasure ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(report.problems[0].pitchText, "C4", "错音显示参考音名")
        XCTAssertEqual(report.problems[1].kind, .missing)
        XCTAssertEqual(report.problems[1].measure, 5)
        XCTAssertEqual(report.problems[1].pitchText, "D4")
        // 多弹音谱面无对应参考音 → 不编小节，如实标「无法定位」
        XCTAssertEqual(report.problems[2].kind, .extra)
        XCTAssertNil(report.problems[2].measure, "多弹不定位到小节（§6 不编造）")
        XCTAssertNil(report.problems[2].beatInMeasure)
        XCTAssertEqual(report.problems[2].pitchText, "E4", "多弹显示实际弹奏音名")
    }

    func testMeasureHeatDecodedSortedAndOneBased() {
        let report = TakeReportPresentation.build(
            analysis: makeAnalysis(measureHeatJSON: "{\"4\":0.5,\"2\":1.0}"), standards: .beginner
        )
        XCTAssertEqual(report.measureHeat.map(\.measure), [3, 5], "按小节升序 + 1-based")
        XCTAssertEqual(report.measureHeat.map(\.heat), [1.0, 0.5])
    }

    func testBrokenJSONDecodesToEmptyNotCrash() {
        let report = TakeReportPresentation.build(
            analysis: makeAnalysis(alignmentJSON: "{不是 JSON", measureHeatJSON: "oops"),
            standards: .beginner
        )
        XCTAssertTrue(report.problems.isEmpty, "派生缓存解析失败 = 空，不编造")
        XCTAssertTrue(report.measureHeat.isEmpty)
    }

    // MARK: 门禁三项与 CourseEngine gate 同源（S13 展示不得与判定分叉）

    func testPassMetricsMatchCourseEngineGate() {
        let row = makeAnalysis(
            wrong: 3, missing: 2, referenceNoteCount: 100,
            rhythmMedianMs: 65, tempoTargetHit: false,
            canEvaluate: true, passesHardMetrics: false
        )
        let standards = ScoringStandards.beginner
        let report = TakeReportPresentation.build(analysis: row, standards: standards)
        let gate = CourseEngine.evaluatePass(
            wrongPitchCount: 3, missingCount: 2, referenceNonGraceCount: 100,
            rhythmMedianMs: 65, tempoTargetHit: false,
            confidence: row.confidence, coversFullScope: true, hasScore: true,
            isFreePlay: false, standards: standards
        )
        XCTAssertEqual(report.passMetrics, gate.metrics, "S13 展示的三项必须与 gate 同源")
        XCTAssertEqual(report.passMetrics.count, 3)
        XCTAssertEqual(report.passMetrics.first?.name, "错音率")
        XCTAssertEqual(report.passMetrics.first?.actualDisplay, "5.0%")
        XCTAssertEqual(report.passMetrics.first?.thresholdDisplay, "≤ 10%")
        XCTAssertEqual(report.passGaps, CourseEngine.passGap(
            wrongPitchCount: 3, missingCount: 2, referenceNonGraceCount: 100,
            rhythmMedianMs: 65, standards: standards
        ))
        XCTAssertTrue(report.passGaps.isEmpty, "两项都在阈值内 → 没有「差多少」")
        XCTAssertTrue(report.passesHardMetrics == false)
    }

    /// 错音率可算：5/100 = 5%（入门阈值 10%）→ 过关卡在节奏与速度
    func testPassMetricsUseReferenceDenominator() {
        let report = TakeReportPresentation.build(
            analysis: makeAnalysis(wrong: 5, missing: 0, referenceNoteCount: 100,
                                   rhythmMedianMs: 120, tempoTargetHit: false, avgBPM: 40),
            standards: .beginner
        )
        XCTAssertEqual(report.passMetrics[0].actualDisplay, "5.0%", "分母 = referenceNoteCount（100）")
        XCTAssertTrue(report.passMetrics[0].passed, "5% ≤ 10% 阈值")
        XCTAssertFalse(report.passMetrics[1].passed, "120ms > 100ms 阈值 → 节奏不过")
        XCTAssertFalse(report.passMetrics[2].passed)
        // 速度维实测值单独展示（门禁三项仍与 gate 同源，不被改写）
        XCTAssertEqual(report.avgBPM, 40, accuracy: 0.0001)
        // passGap 只覆盖错音率/节奏两项（M4 CourseEngine 口径），速度靠指标行展示
        XCTAssertEqual(report.passGaps.count, 1)
        XCTAssertTrue(report.passGaps.contains { $0.contains("节奏") })
    }

    /// 全部达标时没有「差多少」
    func testNoPassGapWhenWithinThresholds() {
        let report = TakeReportPresentation.build(
            analysis: makeAnalysis(wrong: 2, missing: 0, referenceNoteCount: 100,
                                   rhythmMedianMs: 40, tempoTargetHit: true),
            standards: .beginner
        )
        XCTAssertTrue(report.passGaps.isEmpty)
        XCTAssertTrue(report.passesHardMetrics)
        XCTAssertTrue(report.passMetrics.allSatisfy(\.passed))
    }

    /// 低置信 take：可显示六维，但不给门禁三项、不计连续（§7）
    func testLowConfidenceKeepsDimensionsButWithholdsGate() {
        let report = TakeReportPresentation.build(
            analysis: makeAnalysis(canEvaluate: false, confidence: 0.35,
                                   lowConfidenceReasons: ["匹配率低于 50%，多数音符没对上"]),
            standards: .beginner
        )
        XCTAssertEqual(report.state, .scored, "六维仍如实展示")
        XCTAssertFalse(report.canEvaluate)
        XCTAssertTrue(report.passMetrics.isEmpty, "低置信不展示门禁三项")
        XCTAssertEqual(report.consecutivePasses, 0)
        XCTAssertTrue(report.reasons.contains { $0.contains("匹配率") })
    }

    func testConsecutivePassesPassedThroughOnlyWhenEligible() {
        let eligible = TakeReportPresentation.build(
            analysis: makeAnalysis(canEvaluate: true, passesHardMetrics: true),
            standards: .beginner, consecutivePasses: 2
        )
        XCTAssertEqual(eligible.consecutivePasses, 2)
        XCTAssertEqual(eligible.requiredConsecutivePasses, 2)

        let notEligible = TakeReportPresentation.build(
            analysis: makeAnalysis(canEvaluate: false), standards: .beginner, consecutivePasses: 2
        )
        XCTAssertEqual(notEligible.consecutivePasses, 0, "不可评 take 不计连续")
    }

    // MARK: 分级阈值真值（S09/S13 展示同一份）

    func testStandardsThresholdsMatchSpec() {
        XCTAssertEqual(ScoringStandards.beginner.maxWrongNoteRate, 0.10, accuracy: 0.0001)
        XCTAssertEqual(ScoringStandards.beginner.maxRhythmMedianMs, 100, accuracy: 0.0001)
        XCTAssertEqual(ScoringStandards.beginner.targetTempoRatio, 0.80, accuracy: 0.0001)
        XCTAssertEqual(ScoringStandards.intermediate.tolerance.timingWindowMs, 80, accuracy: 0.0001)
        XCTAssertEqual(ScoringStandards.advanced.maxRhythmMedianMs, 50, accuracy: 0.0001)
        XCTAssertEqual(ScoringStandards.standards(forBook: "车尔尼599"), .intermediate)
        XCTAssertEqual(ScoringStandards.standards(forBook: "拜厄"), .beginner)
        XCTAssertEqual(ScoringStandards.standards(forBook: "示例"), .beginner)
        XCTAssertEqual(ScoringStandards.confidenceGateThreshold, 0.6, accuracy: 0.0001)
    }
}

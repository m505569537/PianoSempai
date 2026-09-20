import SwiftData
import XCTest
@testable import PianoSempai

/// P2 M4：六维评分（§6，nil 不编分）+ CourseEngine 过关门禁（§7 连续 2 次/清零/低置信/无谱）。
final class TakeScorerTests: XCTestCase {

    // MARK: 夹具

    /// 8 个参考音 beat 0..7（BPM60 = 1s/拍，4/4 两小节，双 staff 用 hand 区分）
    private func makeRefs(hands: [Hand] = .init(repeating: .right, count: 8)) -> [ReferenceNote] {
        (0..<8).map { beat in
            ReferenceNote(
                id: beat, pitch: UInt8(60 + beat), onsetBeat: Double(beat), durationBeats: 1,
                measureIndex: beat / 4, beatInMeasure: Double(beat % 4),
                hand: beat < hands.count ? hands[beat] : .right, isGrace: false
            )
        }
    }

    private func perfectPlayed() -> [PlayedNote] {
        (0..<8).map { beat in
            PlayedNote(pitch: UInt8(60 + beat), onsetSec: Double(beat), endSec: Double(beat) + 0.8,
                       velocity: 80, isSuspicious: false)
        }
    }

    private func alignPerfect() -> AlignmentResult {
        NoteAligner.align(references: makeRefs(), played: perfectPlayed(),
                          tolerance: .beginner, startBPM: 60)
    }

    // MARK: 六维：完美演奏 → 全维有分、弱总分非 nil、小节热力

    func testPerfectPerformanceScoresAllDimensions() {
        let result = alignPerfect()
        let scored = TakeScorer.score(
            result: result, played: perfectPlayed(), references: makeRefs(),
            calibration: nil, referenceTempo: 60, standards: .beginner
        )
        // 全维非 nil（数据充足时禁止用 nil 逃编分——nil 只属于数据不足）
        XCTAssertNotNil(scored.pitch.score)
        XCTAssertNotNil(scored.rhythm.score)
        XCTAssertNotNil(scored.tempo.score)
        XCTAssertNotNil(scored.dynamics.score)
        XCTAssertNotNil(scored.continuity.score)
        // 单 hand 谱（全 right）→ 双手协同 = nil（§6，不编分）
        XCTAssertNil(scored.hands.score)
        XCTAssertTrue(scored.hands.score == nil && scored.hands.summary.contains("不判双手协同"))
        // 完美演奏：音高满分
        XCTAssertEqual(scored.pitch.score, 100)
        // 弱总分 = 非 nil 五维等权
        XCTAssertNotNil(scored.weakTotal)
        // 无问题 → 热力空
        XCTAssertTrue(scored.measureHeat.isEmpty)
    }

    func testWrongNoteLowersPitchAndMarksHotspot() {
        var played = perfectPlayed()
        played[3] = PlayedNote(pitch: 66, onsetSec: 3.0, endSec: 3.8, velocity: 80, isSuspicious: false) // 错音
        let result = NoteAligner.align(references: makeRefs(), played: played, tolerance: .beginner, startBPM: 60)
        let scored = TakeScorer.score(result: result, played: played, references: makeRefs(),
                                      calibration: nil, referenceTempo: 60, standards: .beginner)
        XCTAssertEqual(result.aligned.filter { $0.cls == .wrongPitch }.count, 1)
        XCTAssertLessThan(scored.pitch.score ?? 0, 100)
        XCTAssertEqual(scored.pitch.hotspotMeasures, [0], "beat3 ∈ 小节 0 → 热点小节 0")
        XCTAssertEqual(scored.measureHeat[0] ?? 0, 1.0, accuracy: 0.001, "唯一问题小节热度 1.0")
    }

    func testTwoHandScoreEnablesHandsDimension() {
        var hands: [Hand] = .init(repeating: .right, count: 8)
        for beat in 4..<8 { hands[beat] = .left }
        let refs = makeRefs(hands: hands)
        let result = NoteAligner.align(references: refs, played: perfectPlayed(), tolerance: .beginner, startBPM: 60)
        let scored = TakeScorer.score(result: result, played: perfectPlayed(), references: refs,
                                      calibration: nil, referenceTempo: 60, standards: .beginner)
        XCTAssertNotNil(scored.hands.score, "双 staff 数据齐全 → 双手协同有分")
        XCTAssertEqual(scored.hands.score, 100)
    }

    // MARK: nil 不编分：低置信/样本不足 → nil + 原因

    func testUnmeasurableDimensionsReturnNilNotFake() {
        // 仅 2 个参考音：tempo <8 样本 → nil；但齐奏时全维可算——构造样本不足的力度
        let refs = [
            ReferenceNote(id: 0, pitch: 60, onsetBeat: 0, durationBeats: 1, measureIndex: 0, beatInMeasure: 0, hand: .right, isGrace: false),
            ReferenceNote(id: 1, pitch: 62, onsetBeat: 1, durationBeats: 1, measureIndex: 0, beatInMeasure: 1, hand: .right, isGrace: false),
        ]
        let played = [
            PlayedNote(pitch: 60, onsetSec: 0, endSec: 0.5, velocity: 80, isSuspicious: false),
            PlayedNote(pitch: 62, onsetSec: 1, endSec: 1.5, velocity: 80, isSuspicious: false),
        ]
        let result = NoteAligner.align(references: refs, played: played, tolerance: .beginner, startBPM: 60)
        let scored = TakeScorer.score(result: result, played: played, references: refs,
                                      calibration: nil, referenceTempo: 60, standards: .beginner)
        // tempo 维：<8 可计时样本 → nil（§6），不编分
        XCTAssertNil(scored.tempo.score)
        // 力度：<8 样本 → nil
        XCTAssertNil(scored.dynamics.score)
        // 弱总分只由非 nil 维度等权——不包含 nil 维的假分
        XCTAssertNotNil(scored.weakTotal)
    }

    /// gate 实测回归：UInt8 力度求和溢出（8×127=1016 > 255）曾致 EXC_BREAKPOINT 崩溃。
    /// 8+ 音全 127 力度 → dynamics.score 非 nil 且不崩溃。
    func testHighVelocitySumDoesNotOverflow() {
        let played = (0..<12).map { beat in
            PlayedNote(pitch: UInt8(60 + beat), onsetSec: Double(beat),
                       endSec: Double(beat) + 0.5, velocity: 127, isSuspicious: false)
        }
        let result = NoteAligner.align(references: makeRefs(), played: played, tolerance: .beginner, startBPM: 60)
        let scored = TakeScorer.score(result: result, played: played, references: makeRefs(),
                                      calibration: nil, referenceTempo: 60, standards: .beginner)
        XCTAssertNotNil(scored.dynamics.score, "12×127 力度求和不得溢出崩溃")
        // 全 127（CV=0）→ 控制力满分
        XCTAssertEqual(scored.dynamics.score, 100)
    }

    // MARK: 过关门禁（§7）

    private let standards = ScoringStandards.beginner

    private func evaluate(
        wrongPitch: Int = 0, missing: Int = 0, refNonGrace: Int = 100,
        median: Double = 40, tempoHit: Bool = true,
        confidence: Double = 0.9, covers: Bool = true,
        hasScore: Bool = true, isFreePlay: Bool = false,
        standards: ScoringStandards = .beginner
    ) -> CourseEngine.PassEvaluation {
        CourseEngine.evaluatePass(
            wrongPitchCount: wrongPitch, missingCount: missing,
            referenceNonGraceCount: refNonGrace, rhythmMedianMs: median,
            tempoTargetHit: tempoHit, confidence: confidence, coversFullScope: covers,
            hasScore: hasScore, isFreePlay: isFreePlay, standards: standards
        )
    }

    func testPassEvaluationAllMetricsPass() {
        let eval = evaluate(wrongPitch: 3, missing: 0, refNonGrace: 100, median: 40, tempoHit: true) // 3% ≤ 10%
        XCTAssertTrue(eval.canEvaluate)
        XCTAssertTrue(eval.passesAllHardMetrics)
        XCTAssertEqual(eval.metrics.count, 3, "错音率/节奏/速度三硬指标")
        XCTAssertEqual(eval.metrics[0].thresholdDisplay, "≤ 10%")
    }

    func testLowConfidenceCannotEvaluateAndDoesNotClear() {
        let eval = evaluate(wrongPitch: 0, confidence: 0.5) // < 0.6 门禁
        XCTAssertFalse(eval.canEvaluate)
        XCTAssertFalse(eval.passesAllHardMetrics)
        XCTAssertTrue(eval.reasons[0].contains("不计入过关（也不清零）"), "低置信：不参与计数也不清零")
    }

    func testNoScoreOrFreePlayCannotEvaluate() {
        XCTAssertTrue(evaluate(hasScore: false).reasons[0].contains("无参考谱"))
        XCTAssertTrue(evaluate(isFreePlay: true).reasons[0].contains("自由弹奏"))
    }

    func testIncompleteCoverageCannotEvaluate() {
        let eval = evaluate(covers: false)
        XCTAssertFalse(eval.canEvaluate)
        XCTAssertTrue(eval.reasons[0].contains("不计入过关"))
    }

    func testHardMetricFailuresReportedWithGap() {
        let eval = evaluate(wrongPitch: 20, missing: 0, refNonGrace: 100, median: 150, tempoHit: false) // 20% > 10%；150ms > 100ms
        XCTAssertTrue(eval.canEvaluate)
        XCTAssertFalse(eval.passesAllHardMetrics)
        XCTAssertEqual(eval.reasons.count, 3, "三项全不达标 → 三条原因")
        let gaps = CourseEngine.passGap(
            wrongPitchCount: 20, missingCount: 0, referenceNonGraceCount: 100,
            rhythmMedianMs: 150, standards: standards
        )
        XCTAssertFalse(gaps.isEmpty, "「差多少过关」应有内容")
        XCTAssertTrue(gaps[0].contains("10"), "错音率差值以真实数值展示")
    }

    // MARK: B1/B2 分级标准（容差带 / 速度达标比例）

    /// 同一组 delta 数据：容差越严，节奏分越低（§9 120/80/50ms）
    func testStricterToleranceLowersRhythmScore() {
        var result = NoteAligner.align(references: makeRefs(), played: perfectPlayed(),
                                       tolerance: .beginner, startBPM: 60)
        // 注入固定 -100ms 偏差：落在 beginner(120) 带内、intermediate(80) 带外
        let drifted = result.aligned.map { note in
            guard note.deltaMs != nil else { return note }
            return AlignedNote(
                refID: note.refID, refMeasureIndex: note.refMeasureIndex,
                refBeatInMeasure: note.refBeatInMeasure, refPitch: note.refPitch,
                playedPitch: note.playedPitch, deltaMs: -100.0,
                cls: note.cls, hand: note.hand
            )
        }
        result = AlignmentResult(
            aligned: drifted, matchedRefCount: result.matchedRefCount,
            missingCount: result.missingCount, extraCount: result.extraCount,
            wrongCount: result.wrongCount, tempoMap: result.tempoMap,
            tempoKnots: result.tempoKnots, confidence: result.confidence,
            lowConfidenceReasons: result.lowConfidenceReasons,
            passesPlayed: result.passesPlayed, coversFullScope: result.coversFullScope
        )
        let beginner = TakeScorer.rhythmDimension(result: result, tolerance: .beginner)
        let intermediate = TakeScorer.rhythmDimension(result: result, tolerance: .intermediate)
        XCTAssertGreaterThan(beginner.score ?? 0, intermediate.score ?? 1, "容差越严分越低")
        XCTAssertEqual(beginner.score, 100, "-100ms 落在 ±120ms 带内 → 满分")
        XCTAssertEqual(intermediate.score, 0, "-100ms 超出 ±80ms 带 → 0 分")
    }

    /// 速度达标比例边界：0.9（intermediate）与 1.0（advanced）。
    /// 实际演奏按 actualAvg BPM 生成（8 音 beat 0..7，onset = beat × 60/actualAvg）。
    func testTempoRatioBoundariesByLevel() {
        func hitFor(_ standards: ScoringStandards, actualAvg: Double) -> Bool {
            let secPerBeat = 60.0 / actualAvg
            let played = (0..<8).map { beat in
                PlayedNote(pitch: UInt8(60 + beat), onsetSec: Double(beat) * secPerBeat,
                           endSec: Double(beat) * secPerBeat + 0.3, velocity: 90, isSuspicious: false)
            }
            let result = NoteAligner.align(
                references: makeRefs(), played: played, tolerance: .beginner, startBPM: 60
            )
            let dim = TakeScorer.tempoDimension(
                result: result, references: makeRefs(), referenceTempo: 100,
                targetTempoRatio: standards.targetTempoRatio
            )
            return dim.tempoTargetHit
        }
        // 实际 90 BPM、参考 100：intermediate(0.9 → 目标 90) 达标，advanced(1.0 → 目标 100) 不达标
        XCTAssertTrue(hitFor(.intermediate, actualAvg: 90))
        XCTAssertFalse(hitFor(.advanced, actualAvg: 90))
    }

    /// gate 返修 2 新增：92 BPM 命中 intermediate(0.9 → 目标 90)；88 BPM 不命中
    func testTempoRatioFineBoundaries() {
        func hitFor(_ actualAvg: Double) -> Bool {
            let secPerBeat = 60.0 / actualAvg
            let played = (0..<8).map { beat in
                PlayedNote(pitch: UInt8(60 + beat), onsetSec: Double(beat) * secPerBeat,
                           endSec: Double(beat) * secPerBeat + 0.3, velocity: 90, isSuspicious: false)
            }
            let result = NoteAligner.align(
                references: makeRefs(), played: played, tolerance: .beginner, startBPM: 60
            )
            return TakeScorer.tempoDimension(
                result: result, references: makeRefs(), referenceTempo: 100, targetTempoRatio: 0.9
            ).tempoTargetHit
        }
        XCTAssertTrue(hitFor(92), "92 ≥ 90 → intermediate 达标")
        XCTAssertFalse(hitFor(88), "88 < 90 → intermediate 不达标")
    }

    /// gate 返修 2 新增：首匹配不在 beat0（参考 beat2 起弹 / 跳过开头）时，
    /// avgBPM 仍须与真实 BPM 偏差 < 0.5（锁死去趋势 offset 缺陷不复发）。
    func testAvgBPMAccurateWhenFirstMatchNotAtBeatZero() {
        // 参考 beat 2..9（8 音），演奏按真实 90 BPM 从 beat2 开始（onset = beat×2/3s）
        let refs = (2..<10).map { beat in
            ReferenceNote(id: beat, pitch: UInt8(60 + beat), onsetBeat: Double(beat), durationBeats: 1,
                          measureIndex: beat / 4, beatInMeasure: Double(beat % 4), hand: .right, isGrace: false)
        }
        let secPerBeat = 60.0 / 90.0
        let played = (2..<10).map { beat in
            PlayedNote(pitch: UInt8(60 + beat), onsetSec: Double(beat) * secPerBeat,
                       endSec: Double(beat) * secPerBeat + 0.3, velocity: 90, isSuspicious: false)
        }
        let result = NoteAligner.align(
            references: refs, played: played, tolerance: .beginner, startBPM: 60
        )
        let dim = TakeScorer.tempoDimension(
            result: result, references: refs, referenceTempo: 100, targetTempoRatio: 0.9
        )
        let avg = try! XCTUnwrap(dim.avgBPM)
        XCTAssertEqual(avg, 90.0, accuracy: 0.5, "首匹配不在 beat0 时 avgBPM 仍须真实（去趋势 offset 缺陷锁死）")
    }

    // MARK: B3 错音率口径（gate B3：漏音计罚、多弹不稀释）

    func testOmissionsPenalizedEvenWithoutWrongPitches() {
        // 参考 100 音、wrongPitch=0、missing=50 → rate=50%，beginner(10%) 也不过
        let eval = evaluate(wrongPitch: 0, missing: 50, refNonGrace: 100)
        XCTAssertTrue(eval.canEvaluate)
        XCTAssertFalse(eval.passesAllHardMetrics, "漏一半音必须不过关（漏音计罚）")
        XCTAssertTrue(eval.reasons.contains(where: { $0.contains("错音率") }))
    }

    func testWrongRateExactlyAtBeginnerThresholdPasses() {
        // wrong=5 + missing=5 = 10 / 100 = 10% → 恰好达 beginner 阈值（≤）
        let eval = evaluate(wrongPitch: 5, missing: 5, refNonGrace: 100)
        XCTAssertTrue(eval.passesAllHardMetrics, "10% ≤ 10% → 达标（≤ 语义）")
    }

    func testExtraNotesDoNotDiluteWrongRate() {
        // 多弹不进分子分母：extra 多也不改变 rate（SPEC 三硬指标不含多弹率）
        let withExtras = evaluate(wrongPitch: 5, missing: 5, refNonGrace: 100)
        XCTAssertEqual(withExtras.metrics[0].actualDisplay, "10.0%")
    }

    // MARK: B4 过关留痕 rulesVersion

    @MainActor
    func testPassedRulesVersionStampsOnPassAndStaysNilOnFail() throws {
        let container = try ModelContainer(
            for: Piece.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let failPiece = Piece(title: "t", book: "拜厄", number: 1, status: "practicing")
        context.insert(failPiece)
        XCTAssertFalse(CourseEngine.applyPassIfConsecutive(
            piece: failPiece, takesOldestFirst: [(true, true), (true, false)], in: context
        ))
        XCTAssertNil(failPiece.passedRulesVersion, "未过关保持 nil")

        let passPiece = Piece(title: "t2", book: "拜厄", number: 2, status: "practicing")
        context.insert(passPiece)
        XCTAssertTrue(CourseEngine.applyPassIfConsecutive(
            piece: passPiece, takesOldestFirst: [(true, true), (true, true)], in: context
        ))
        XCTAssertEqual(passPiece.passedRulesVersion, "P2-scoring-1.0")
    }

    // MARK: 连续 2 次过关（清零 / 跳过语义）

    func testConsecutiveStreakLogic() {
        // 达标+达标 = 2
        XCTAssertEqual(CourseEngine.consecutivePassStreak(eligibleTakes: [
            (true, true), (true, true),
        ]), 2)
        // 达标+不达标（中间）→ 清零
        XCTAssertEqual(CourseEngine.consecutivePassStreak(eligibleTakes: [
            (true, true), (true, false), (true, true),
        ]), 0, "可评但不达标 → 连续计数清零")
        // 低置信/无谱（不可评）跳过不清零
        XCTAssertEqual(CourseEngine.consecutivePassStreak(eligibleTakes: [
            (true, true), (false, false), (true, true),
        ]), 2, "不可评 take 不参与计数也不清零")
    }

    @MainActor
    func testApplyPassWritesPieceStatusOnlyAfterTwoConsecutive() throws {
        let container = try ModelContainer(
            for: Piece.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let piece = Piece(title: "拜厄 第45条", book: "拜厄", number: 45, status: "practicing")
        context.insert(piece)

        // 1 次达标 → 不过
        XCTAssertFalse(CourseEngine.applyPassIfConsecutive(
            piece: piece, takesOldestFirst: [(true, true)], in: context
        ))
        XCTAssertEqual(piece.status, "practicing")

        // 连续 2 次达标 → passed（唯一写手）
        XCTAssertTrue(CourseEngine.applyPassIfConsecutive(
            piece: piece, takesOldestFirst: [(true, true), (true, true)], in: context
        ))
        XCTAssertEqual(piece.status, "passed")
        XCTAssertEqual(piece.passedRulesVersion, CourseEngine.scoringRulesVersion, "过关留痕规则版本")
    }
}

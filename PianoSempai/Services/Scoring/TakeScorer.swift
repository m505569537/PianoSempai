import Foundation

// 六维评分（SPEC §6）：AlignmentResult + 演奏 velocity + 校准 → 六维 0...100。
// 算不出的维度返回 nil（UI 显式「数据不足」，禁止编分，红线 1）。
// 弱总分仅由非 nil 维度等权得到，不作过关依据（红线 4）。
// 纯函数、只读、不写课程状态（红线 2）。

enum TakeScorer {

    struct DimensionResult: Equatable, Sendable {
        let score: Int?
        let summary: String
        /// 该维贡献的热点小节（0-based）
        let hotspotMeasures: [Int]
        /// 仅速度维有语义（门禁达标布尔）；其余维恒 false
        var tempoTargetHit: Bool = false
        /// 仅速度维有语义：真实平均 BPM（gate 返修 2：偏差测试断言用）
        var avgBPM: Double? = nil
    }

    /// 节奏维统计透传（中位/均值 ms；TakeAnalysis 落库用）
    struct RhythmStats: Equatable, Sendable {
        let medianMs: Double
        let meanMs: Double
    }

    struct Scored: Equatable, Sendable {
        let pitch: DimensionResult
        let rhythm: DimensionResult
        let tempo: DimensionResult
        let dynamics: DimensionResult
        let continuity: DimensionResult
        let hands: DimensionResult
        /// 弱总分（非 nil 维度等权；全 nil → nil）。仅进步曲线用，不作过关依据
        let weakTotal: Int?
        /// 节奏偏差中位/均值 ms（TakeAnalysis 落库；无可计时匹配 = nil）
        let rhythmStats: RhythmStats?
        /// 小节热力：小节 → 0...1 热度
        let measureHeat: [Int: Double]
        let hotspotMeasures: [Int]
    }

    // MARK: - 入口

    /// - Parameters:
    ///   - result: NoteAligner 产出
    ///   - played: 演奏音（velocity 分布用）
    ///   - references: 参考音（含 grace；分母剔除 grace）
    ///   - calibration: 力度个人校准（nil → 力度只给原始相对统计）
    ///   - referenceTempo: 曲目参考速度（速度达标布尔用；0 = 无参考，达标恒 false）
    ///   - standards: 分级课程标准（§9：节奏容差带/速度达标比例由等级决定，禁硬编码）
    ///   - segmentStartSecs: 各非中断段的起始秒（升序；中断间隙不计停顿，§4/§6）
    static func score(
        result: AlignmentResult,
        played: [PlayedNote],
        references: [ReferenceNote],
        calibration: VelocityCalibration?,
        referenceTempo: Int,
        standards: ScoringStandards,
        segmentStartSecs: [Double] = []
    ) -> Scored {
        let refByID = Dictionary(uniqueKeysWithValues: references.map { ($0.id, $0) })
        let pitch = pitchDimension(result: result, references: references)
        let rhythm = rhythmDimension(result: result, tolerance: standards.tolerance)
        let tempo = tempoDimension(
            result: result, references: references, referenceTempo: referenceTempo,
            targetTempoRatio: standards.targetTempoRatio
        )
        let dynamics = dynamicsDimension(played: played, calibration: calibration)
        let continuity = continuityDimension(
            result: result, refByID: refByID, segmentStartSecs: segmentStartSecs
        )
        let hands = handsDimension(result: result)

        let dims: [Int?] = [pitch.score, rhythm.score, tempo.score, dynamics.score, continuity.score, hands.score]
        let nonNil = dims.compactMap { $0 }
        let weakTotal: Int? = nonNil.isEmpty
            ? nil
            : Int((Double(nonNil.reduce(0, +)) / Double(nonNil.count)).rounded())

        return Scored(
            pitch: pitch, rhythm: rhythm, tempo: tempo,
            dynamics: dynamics, continuity: continuity, hands: hands,
            weakTotal: weakTotal,
            rhythmStats: rhythmStats(result: result),
            measureHeat: measureHeat(result: result, pauses: continuity.hotspotMeasures),
            hotspotMeasures: Array(Set(pitch.hotspotMeasures + continuity.hotspotMeasures)).sorted()
        )
    }

    /// 节奏偏差统计（中位/均值 ms；可计时匹配 < 4 → nil）
    static func rhythmStats(result: AlignmentResult) -> RhythmStats? {
        let deltas = result.aligned
            .filter { $0.cls == .correct || $0.cls == .wrongPitch }
            .compactMap(\.deltaMs)
        guard deltas.count >= 4 else { return nil }
        let sorted = deltas.sorted()
        let median: Double = sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        let mean = deltas.reduce(0, +) / Double(deltas.count)
        return RhythmStats(medianMs: median, meanMs: mean)
    }

    // MARK: - 1 音高

    static func pitchDimension(result: AlignmentResult, references: [ReferenceNote]) -> DimensionResult {
        let nonGraceRefs = references.filter { !$0.isGrace }
        guard !nonGraceRefs.isEmpty else {
            return DimensionResult(score: nil, summary: "无参考谱，不判音高", hotspotMeasures: [])
        }
        let correct = result.aligned.filter { $0.cls == .correct }.count
        let denominator = nonGraceRefs.count // grace 不进分母（§6）
        let score = Int((Double(correct) / Double(denominator) * 100).rounded())
        let wrong = result.aligned.filter { $0.cls == .wrongPitch }
        let missing = result.aligned.filter { $0.cls == .missing }
        let hotspots = Set(wrong.compactMap(\.refMeasureIndex) + missing.compactMap(\.refMeasureIndex)).sorted()
        let summary = "命中 \(correct)/\(denominator) · 错音 \(wrong.count) · 漏音 \(missing.count)"
        return DimensionResult(score: score, summary: summary, hotspotMeasures: hotspots)
    }

    // MARK: - 2 节奏

    /// 节奏分：带内比例 ×100，抢/拖倾向来自 mean deltaMs 符号（§6）
    static func rhythmDimension(result: AlignmentResult, tolerance: ScoringTolerance) -> DimensionResult {
        let deltas = result.aligned
            .filter { $0.cls == .correct || $0.cls == .wrongPitch }
            .compactMap(\.deltaMs)
        guard deltas.count >= 4 else {
            return DimensionResult(score: nil, summary: "可计时匹配不足 4 个", hotspotMeasures: [])
        }
        let window = tolerance.timingWindowMs
        let inBand = deltas.filter { abs($0) <= window }.count
        let score = Int((Double(inBand) / Double(deltas.count) * 100).rounded())
        let mean = deltas.reduce(0, +) / Double(deltas.count)
        let sorted = deltas.sorted()
        let median = sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        let tendency = abs(mean) < window / 4 ? "稳定" : (mean > 0 ? "偏拖拍" : "偏抢拍")
        let summary = "中位偏差 \(String(format: "%.0f", median))ms · \(tendency)"
        return DimensionResult(score: score, summary: summary, hotspotMeasures: [])
    }

    // MARK: - 3 速度稳定性

    /// 瞬时速度变异度（CV）→ 分数；对照参考速度给达标布尔（门禁用）。
    /// 可计时匹配 < 8 → nil（§6）。速度真值 = AlignedNote.playedOnsetSec（gate 返修 2：
    /// 直接消费真实演奏 onset，不走去趋势节奏图反推）；参考拍差用绝对 onsetBeat。
    /// deltaMs 仍归节奏维。达标比例 targetTempoRatio 来自 ScoringStandards（§9：0.8/0.9/1.0）。
    static func tempoDimension(
        result: AlignmentResult,
        references: [ReferenceNote],
        referenceTempo: Int,
        targetTempoRatio: Double
    ) -> DimensionResult {
        let refByID = Dictionary(uniqueKeysWithValues: references.map { ($0.id, $0) })
        let timed = result.aligned
            .filter { $0.cls == .correct || $0.cls == .wrongPitch }
            .compactMap { note -> (beat: Double, playedOnset: Double)? in
                guard let onset = note.playedOnsetSec,
                      let id = note.refID, let ref = refByID[id] else { return nil }
                return (ref.onsetBeat, onset)
            }
        guard timed.count >= 8 else {
            return DimensionResult(score: nil, summary: "可计时匹配不足 8 个", hotspotMeasures: [])
        }
        var bpms: [Double] = []
        for i in 1..<timed.count {
            let dBeat = timed[i].beat - timed[i - 1].beat
            let dSec = timed[i].playedOnset - timed[i - 1].playedOnset
            if dBeat > 0.01, dSec > 0.01 {
                bpms.append(60.0 * dBeat / dSec)
            }
        }
        guard !bpms.isEmpty else {
            return DimensionResult(score: nil, summary: "无有效速度样本", hotspotMeasures: [])
        }
        let mean = bpms.reduce(0, +) / Double(bpms.count)
        let variance = bpms.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(bpms.count)
        let cv = (variance.squareRoot() / mean) * 100
        // CV 越小越稳：100 分 = CV 0；CV ≥ 30% 记 0 分（线性，端点显式）
        let score = Int(max(0, min(100, (1.0 - cv / 30.0) * 100)).rounded())
        let target = Double(referenceTempo)
        let playedSpan = timed.last!.playedOnset - timed.first!.playedOnset
        let beatSpan = timed.last!.beat - timed.first!.beat
        let avgBPM = playedSpan > 0.01 && beatSpan > 0.01 ? 60.0 * beatSpan / playedSpan : mean
        let hit = referenceTempo > 0 && avgBPM >= target * targetTempoRatio
        let summary = "平均 ♩=\(Int(avgBPM.rounded())) · 参考 ♩=\(referenceTempo) · CV \(String(format: "%.0f", cv))%"
        return DimensionResult(score: score, summary: summary, hotspotMeasures: [],
                               tempoTargetHit: hit, avgBPM: avgBPM)
    }

    /// 从 tempoKnots 重建预测函数（秒）。连续性/速度维用。
    static func tempoFnOf(result: AlignmentResult) -> (Double) -> Double {
        let knots = result.tempoKnots
        guard !knots.isEmpty else { return { _ in 0 } }
        if knots.count == 1 {
            let s = knots[0]
            return { beat in s.sec + (beat - s.beat) }
        }
        return { beat in
            if beat <= knots[0].beat {
                let slope = (knots[1].sec - knots[0].sec) / max(0.0001, knots[1].beat - knots[0].beat)
                return knots[0].sec + (beat - knots[0].beat) * slope
            }
            let n = knots.count
            if beat >= knots[n - 1].beat {
                let slope = (knots[n - 1].sec - knots[n - 2].sec) / max(0.0001, knots[n - 1].beat - knots[n - 2].beat)
                return knots[n - 1].sec + (beat - knots[n - 1].beat) * slope
            }
            var k = 0
            while k < n - 1 && knots[k + 1].beat < beat { k += 1 }
            let a = knots[k], b = knots[min(k + 1, n - 1)]
            guard b.beat > a.beat else { return a.sec }
            let t = (beat - a.beat) / (b.beat - a.beat)
            return a.sec + t * (b.sec - a.sec)
        }
    }

    // MARK: - 4 力度

    /// velocity 均匀度（CV）；有校准标注「已按个人校准」，无校准标注「未校准，仅相对值」。
    /// 样本 < 8 → nil（§6）。
    static func dynamicsDimension(played: [PlayedNote], calibration: VelocityCalibration?) -> DimensionResult {
        // velocity 是 UInt8：必须先映射为 Double 再求和（8×80=640 会 UInt8 溢出崩溃，gate 实测）
        let velocities = played.map(\.velocity).filter { $0 > 0 }.map(Double.init)
        guard velocities.count >= 8 else {
            return DimensionResult(score: nil, summary: "力度样本不足 8 个", hotspotMeasures: [])
        }
        let mean = velocities.reduce(0, +) / Double(velocities.count)
        guard mean > 0 else {
            return DimensionResult(score: nil, summary: "力度数据无效", hotspotMeasures: [])
        }
        let variance = velocities.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(velocities.count)
        let cv = (variance.squareRoot() / mean) * 100
        // 控制力口径：CV ≤15% 满分；15%–45% 线性扣到 0（端点显式，§6 禁黑箱）
        let score = Int(max(0, min(100, (1.0 - max(0, cv - 15.0) / 30.0) * 100)).rounded())
        let calibrated = calibration?.isCalibrated == true
        let note = calibrated ? "已按个人校准" : "未校准，仅相对值"
        let summary = "平均力度 \(Int(mean.rounded()))/127 · \(note)"
        return DimensionResult(score: score, summary: summary, hotspotMeasures: [])
    }

    // MARK: - 5 连续性

    /// 停顿：相邻 matched 的 played 间隔超过「预测间隔 × 2 且 > 1.5s」（§6）。
    /// predicted 秒由 tempoKnots 重建；跨中断段起点的间隔不算（§4 中断空白不判停顿）。
    static func continuityDimension(
        result: AlignmentResult,
        refByID: [Int: ReferenceNote],
        segmentStartSecs: [Double]
    ) -> DimensionResult {
        let tempoFn = tempoFnOf(result: result)
        let timed = result.aligned
            .filter { $0.cls == .correct || $0.cls == .wrongPitch }
            .compactMap { note -> (measure: Int, predictedSec: Double, playedSec: Double)? in
                // playedSec 真值 = AlignedNote.playedOnsetSec（gate 返修 2）；预测秒仍走节奏图
                guard let id = note.refID, let ref = refByID[id],
                      let playedOnset = note.playedOnsetSec else { return nil }
                return (ref.measureIndex, tempoFn(ref.onsetBeat), playedOnset)
            }
        guard timed.count >= 2 else {
            return DimensionResult(score: nil, summary: "无可计时匹配", hotspotMeasures: [])
        }
        var pauses = 0
        var hotspots: [Int] = []
        for i in 1..<timed.count {
            // 跨中断段起点 = 空白期（PRD L64），不计停顿
            if segmentStartSecs.contains(where: { $0 > timed[i - 1].playedSec && $0 <= timed[i].playedSec }) {
                continue
            }
            let predictedGap = timed[i].predictedSec - timed[i - 1].predictedSec
            let playedGap = timed[i].playedSec - timed[i - 1].playedSec
            if playedGap > predictedGap * 2.0, playedGap > 1.5 {
                pauses += 1
                hotspots.append(timed[i].measure)
            }
        }
        let score = max(0, 100 - pauses * 15)
        let summary = pauses == 0 ? "无卡顿" : "停顿 \(pauses) 次"
        return DimensionResult(score: score, summary: summary, hotspotMeasures: hotspots)
    }

    // MARK: - 6 双手协同

    /// 仅双 staff 谱；RHLH 各自 correct 率的均衡度。单 staff/unknown → nil（§6）
    static func handsDimension(result: AlignmentResult) -> DimensionResult {
        let byHand = Dictionary(grouping: result.aligned.filter { $0.cls == .correct || $0.cls == .wrongPitch || $0.cls == .missing }) { $0.hand }
        let right = byHand[.right] ?? []
        let left = byHand[.left] ?? []
        guard !right.isEmpty, !left.isEmpty else {
            return DimensionResult(score: nil, summary: "单谱表/无分手数据，不判双手协同", hotspotMeasures: [])
        }
        func rate(_ items: [AlignedNote]) -> Double {
            let good = items.filter { $0.cls == .correct }.count
            return Double(good) / Double(max(1, items.count))
        }
        let rr = rate(right), lr = rate(left)
        let balance = 1.0 - abs(rr - lr) // 均衡度：两手正确率差越小越高
        let score = Int((balance * 100).rounded())
        let summary = "右手 \(Int(rr * 100))% · 左手 \(Int(lr * 100))%"
        return DimensionResult(score: score, summary: summary, hotspotMeasures: [])
    }

    // MARK: - 小节热力

    /// 聚合该小节 wrong/missing/extra + 停顿 → 0...1 热度（§6）。
    /// 归一化：该小节问题数 / 全谱最大小节问题数（无问题全 0）。
    static func measureHeat(result: AlignmentResult, pauses: [Int]) -> [Int: Double] {
        var counts: [Int: Double] = [:]
        for note in result.aligned where note.cls != .correct {
            let m = note.refMeasureIndex ?? -1
            guard m >= 0 else { continue }
            counts[m, default: 0] += 1
        }
        for m in pauses {
            counts[m, default: 0] += 1
        }
        guard let maxCount = counts.values.max(), maxCount > 0 else { return [:] }
        var heat: [Int: Double] = [:]
        for (m, c) in counts {
            heat[m] = c / Double(maxCount)
        }
        return heat
    }
}

import Foundation

// P1 简化分析（brief：S13 报告先给时长/音符数/错音数/速度/踏板事件数/MIDI 事件数）。
// 纯函数、只读、不写任何课程状态（红线 3；测试断言）。
// 谱错剔除规则（S13b）：被标"疑似谱错"的小节从该 take 错音率分子中扣除；其他小节不受影响。
// 旧 take 只有错音总数（无逐音明细）→ 无法按小节剔除时如实标注，不假装剔除。
//
// M5b：P2 六维/热力/置信/过关进度改为真实渲染（TakeReportPresentation）。
// 旧占位名单（"六维雷达：分析将在 P2 提供"等）已删除——没有数据就显式说没有，
// 不允许留一句假装会有的文案（SPEC §11）。

struct P1TakeAnalysis: Equatable {
    // 真实统计维度
    let durationSec: Int
    let noteCount: Int
    let pedalEventCount: Int
    let midiEventCount: Int
    let tempoAvg: Int
    /// 逐音错音明细（M6b 起的 take 才有；旧 take 为空）
    let wrongNotes: [WrongNoteRecord]
    /// 旧口径错音总数（无明细时的唯一真值）
    let wrongNoteTotal: Int
    let hasDetail: Bool

    /// S13b 已标记小节（从错音率分子扣除）
    let excludedMeasures: Set<Int>

    /// 剔除后的错音数（引擎规则；无明细时按总数，剔除不适用）
    var effectiveWrongCount: Int {
        hasDetail
            ? wrongNotes.filter { !excludedMeasures.contains($0.measure) }.count
            : wrongNoteTotal
    }

    /// 错音率（音符数为 0 时返回 nil——显示"没有音符"，不编 0%）
    var wrongNoteRate: Double? {
        noteCount > 0 ? Double(effectiveWrongCount) / Double(noteCount) : nil
    }

    /// 剔除是否实际生效（有明细且有被标小节）
    var exclusionApplied: Bool {
        hasDetail && !excludedMeasures.isEmpty
    }
}

enum TakeAnalysisService {

    /// 从 take 与谱错标记计算 P1 分析。只读：不改 take、不改任何模型（测试断言课程状态不变）。
    static func analyze(take: Take, errorMarks: [ScoreErrorMark]) -> P1TakeAnalysis {
        let excluded = Set(errorMarks.map(\.measure))
        let details = take.wrongNoteRecords.compactMap { record -> WrongNoteRecord? in
            // 存储格式 "measure:pitch"
            let parts = record.split(separator: ":")
            guard parts.count == 2, let m = Int(parts[0]), let p = UInt8(parts[1]) else { return nil }
            return WrongNoteRecord(measure: m, actualPitch: p)
        }
        return P1TakeAnalysis(
            durationSec: take.durationSec,
            noteCount: take.noteCount,
            pedalEventCount: take.pedalEventCount,
            midiEventCount: take.midiEventCount,
            tempoAvg: take.tempoAvg,
            wrongNotes: details,
            wrongNoteTotal: take.wrongNoteCount,
            hasDetail: !details.isEmpty,
            excludedMeasures: excluded
        )
    }
}

// MARK: - P2 S13 报告呈现（真实数据；nil = 数据不足，禁止编分，红线 1）

/// 六维展示行。`score == nil` → 显式「数据不足」+ `note` 说明为什么算不出。
struct DimensionRow: Equatable {
    let name: String
    let score: Int?
    let note: String

    var displayScore: String { score.map { "\($0)" } ?? "数据不足" }
    var isMeasured: Bool { score != nil }
}

/// 问题音定位（小节·拍；来自 TakeAnalysis.alignmentJSON 的 AlignedNote）。
/// 多弹音在谱面上没有对应参考位置 → `measure == nil`（诚实标注，不编一个小节）。
struct ProblemNote: Equatable, Hashable {
    enum Kind: String, Equatable {
        case wrongPitch = "错音"
        case missing = "漏音"
        case extra = "多弹"
    }

    /// 1-based 展示值（对齐结果里 refMeasureIndex 是 0-based）；nil = 无法定位
    let measure: Int?
    let beatInMeasure: Double?
    let kind: Kind
    /// 参考音高（错音/漏音）或实际弹奏音高（多弹）
    let pitchText: String
}

/// 小节热度（1-based 展示值 + 0...1 热度）
struct MeasureHeat: Equatable {
    let measure: Int
    let heat: Double
}

/// S13 报告的 P2 呈现（纯函数产出；视图只渲染，不在这里做任何判定）。
struct P2TakeReport: Equatable {
    enum State: Equatable {
        /// 没有分析行（旧 take / 分析还没跑）
        case noAnalysis
        /// 统计级：无参考谱或自由弹奏——有行但没有任何对错分
        case statistics
        /// 有六维真实分
        case scored
    }

    let state: State
    /// 统计级/不可评的原因（低置信原因原文，中文）
    let reasons: [String]
    let canEvaluate: Bool
    let passesHardMetrics: Bool
    let confidence: Double
    let dimensions: [DimensionRow]
    let weakTotal: Int?
    let wrongCount: Int
    let missingCount: Int
    let extraCount: Int
    /// 节奏偏差中位（ms）+ 抢/拖倾向标签
    let rhythmMedianMs: Double
    let rhythmTendency: String
    let tempoTargetHit: Bool
    /// 实测平均速度（BPM；0 = 速度维算不出）
    let avgBPM: Double
    /// 热点小节（1-based）
    let hotspotMeasures: [Int]
    let measureHeat: [MeasureHeat]
    let problems: [ProblemNote]
    /// 门禁三项（实际值 vs 阈值；复用 CourseEngine.evaluatePass，与 gate 同源）
    let passMetrics: [CourseEngine.MetricResult]
    /// 「差多少过关」（CourseEngine.passGap 同源）
    let passGaps: [String]
    let consecutivePasses: Int
    let requiredConsecutivePasses: Int
}

enum TakeReportPresentation {

    /// 连续达标次数要求（SPEC §7；唯一来源 CourseEngine 规则）
    static let requiredConsecutivePasses = 2

    /// 由持久化的 TakeAnalysis 行构造报告呈现。只读、纯函数：
    /// 不写任何模型、不改课程状态；算不出的一律 nil + 诚实文案。
    /// - Parameters:
    ///   - analysis: 该 take 的分析行（nil = 旧 take/未分析）
    ///   - standards: 该曲目分级阈值（S09/S13 展示与 gate 同源）
    ///   - consecutivePasses: 该曲目当前连续达标次数（视图层用 CourseEngine 只读统计）
    static func build(
        analysis: TakeAnalysis?,
        standards: ScoringStandards,
        consecutivePasses: Int = 0
    ) -> P2TakeReport {
        guard let analysis else {
            return P2TakeReport(
                state: .noAnalysis, reasons: [], canEvaluate: false, passesHardMetrics: false,
                confidence: 0, dimensions: [], weakTotal: nil,
                wrongCount: 0, missingCount: 0, extraCount: 0,
                rhythmMedianMs: 0, rhythmTendency: "数据不足", tempoTargetHit: false, avgBPM: 0,
                hotspotMeasures: [], measureHeat: [], problems: [],
                passMetrics: [], passGaps: [], consecutivePasses: 0,
                requiredConsecutivePasses: requiredConsecutivePasses
            )
        }

        let problems = decodeProblems(analysis.alignmentJSON)
        let heat = decodeHeat(analysis.measureHeatJSON)
        let hotspots = analysis.hotspotMeasures.sorted()

        // 统计级判定：六维全 nil（编排器对无谱/自由弹奏就是这样落的）→ 没有任何对错分
        guard analysis.pitchScore != nil else {
            return P2TakeReport(
                state: .statistics,
                reasons: analysis.lowConfidenceReasons,
                canEvaluate: false, passesHardMetrics: false,
                confidence: analysis.confidence, dimensions: [], weakTotal: nil,
                wrongCount: analysis.wrongCount, missingCount: analysis.missingCount,
                extraCount: analysis.extraCount,
                rhythmMedianMs: analysis.rhythmMedianMs, rhythmTendency: "数据不足",
                tempoTargetHit: analysis.tempoTargetHit, avgBPM: analysis.avgBPM,
                hotspotMeasures: hotspots, measureHeat: heat, problems: problems,
                passMetrics: [], passGaps: [], consecutivePasses: 0,
                requiredConsecutivePasses: requiredConsecutivePasses
            )
        }

        let dimensions = [
            DimensionRow(name: "音高", score: analysis.pitchScore, note: "无参考谱，不判音高"),
            DimensionRow(
                name: "节奏", score: analysis.rhythmScore,
                note: "可计时匹配不足 4 个（对齐置信不足）"
            ),
            DimensionRow(
                name: "速度稳定性", score: analysis.tempoScore,
                note: "可计时匹配不足 8 个"
            ),
            DimensionRow(name: "力度", score: analysis.dynamicsScore, note: "力度样本不足 8 个"),
            DimensionRow(name: "连续性", score: analysis.continuityScore, note: "无可计时匹配"),
            DimensionRow(
                name: "双手协同", score: analysis.handsScore,
                note: "单谱表/无分手数据，不判双手协同"
            ),
        ]

        // 门禁三项：用持久化后的真值重算，保证 S13 展示与 gate 判定完全同源（§7 非黑箱）。
        // canEvaluate 已蕴含 confidence≥0.6 && coversFullScope，故这里用它回传这两个入参。
        let evaluation = CourseEngine.evaluatePass(
            wrongPitchCount: analysis.wrongPitchCount,
            missingCount: analysis.missingCount,
            referenceNonGraceCount: analysis.referenceNoteCount,
            rhythmMedianMs: analysis.rhythmMedianMs,
            tempoTargetHit: analysis.tempoTargetHit,
            confidence: analysis.confidence,
            coversFullScope: analysis.canEvaluate,
            hasScore: true,
            isFreePlay: false,
            standards: standards
        )
        let gaps = CourseEngine.passGap(
            wrongPitchCount: analysis.wrongPitchCount,
            missingCount: analysis.missingCount,
            referenceNonGraceCount: analysis.referenceNoteCount,
            rhythmMedianMs: analysis.rhythmMedianMs,
            standards: standards
        )

        return P2TakeReport(
            state: .scored,
            reasons: analysis.lowConfidenceReasons + evaluation.reasons,
            canEvaluate: analysis.canEvaluate,
            passesHardMetrics: analysis.passesHardMetrics,
            confidence: analysis.confidence,
            dimensions: dimensions,
            weakTotal: analysis.weakTotal,
            wrongCount: analysis.wrongCount,
            missingCount: analysis.missingCount,
            extraCount: analysis.extraCount,
            rhythmMedianMs: analysis.rhythmMedianMs,
            rhythmTendency: tendency(
                meanMs: analysis.rhythmMeanMs,
                windowMs: standards.tolerance.timingWindowMs,
                measurable: analysis.rhythmScore != nil
            ),
            tempoTargetHit: analysis.tempoTargetHit,
            avgBPM: analysis.avgBPM,
            hotspotMeasures: hotspots,
            measureHeat: heat,
            problems: problems,
            passMetrics: analysis.canEvaluate ? evaluation.metrics : [],
            passGaps: analysis.canEvaluate ? gaps : [],
            consecutivePasses: analysis.canEvaluate ? consecutivePasses : 0,
            requiredConsecutivePasses: requiredConsecutivePasses
        )
    }

    // MARK: - 抢/拖倾向（与 TakeScorer.rhythmDimension 同口径：mean deltaMs 符号）

    static func tendency(meanMs: Double, windowMs: Double, measurable: Bool) -> String {
        guard measurable else { return "数据不足" }
        if abs(meanMs) < windowMs / 4 { return "稳定" }
        return meanMs > 0 ? "偏拖拍" : "偏抢拍"
    }

    // MARK: - JSON 解码（analysisJSON 是派生缓存；解析失败 = 空，不编造）

    static func decodeProblems(_ json: String) -> [ProblemNote] {
        guard let data = json.data(using: .utf8),
              let aligned = try? JSONDecoder().decode([AlignedNote].self, from: data) else { return [] }
        return aligned.compactMap { note -> ProblemNote? in
            guard note.cls != .correct else { return nil }
            let kind: ProblemNote.Kind
            switch note.cls {
            case .wrongPitch: kind = .wrongPitch
            case .missing: kind = .missing
            case .extra: kind = .extra
            case .correct: return nil
            }
            let pitch = note.cls == .extra ? note.playedPitch : note.refPitch
            let pitchText = pitch.map { SightReadSession.noteName($0) } ?? "—"
            return ProblemNote(
                // 多弹音谱面无对应参考音 → 不定位小节（§6：不编造）
                measure: note.refMeasureIndex.map { $0 + 1 },
                beatInMeasure: note.refBeatInMeasure,
                kind: kind,
                pitchText: pitchText
            )
        }
    }

    static func decodeHeat(_ json: String) -> [MeasureHeat] {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([Int: Double].self, from: data) else { return [] }
        return raw.map { MeasureHeat(measure: $0.key + 1, heat: $0.value) }
            .sorted { $0.measure < $1.measure }
    }
}

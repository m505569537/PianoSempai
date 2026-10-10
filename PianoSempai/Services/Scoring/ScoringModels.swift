import Foundation

// P2 判分引擎核心值类型（SPEC §2）+ 容差/课程数据（§9）。
// 纯值类型，持久层（TakeAnalysis @Model）在 Models.swift，二者分开。
// 本文件不触库、不发网络请求（红线 6）。

// MARK: - §2 领域模型

/// 左右手（钢琴单 Part 双 Staff：staffIndex 0=右手、1=左手；单 staff 谱 = unknown）
enum Hand: String, Codable, Equatable, Sendable {
    case right, left, unknown
}

/// 参考音符（从谱面提取，全局按小节/拍定位）
struct ReferenceNote: Equatable, Identifiable, Sendable {
    /// 提取顺序稳定 id（最终排序后顺序赋值）
    let id: Int
    /// MIDI 0...127
    let pitch: UInt8
    /// 相对评分区间起点的拍数（累计，含跨小节；区间起点归零/rebased）
    let onsetBeat: Double
    let durationBeats: Double
    /// 0-based；展示 +1
    let measureIndex: Int
    /// 小节内拍（错音定位「第几小节第几拍」）
    let beatInMeasure: Double
    let hand: Hand
    /// 倚音/装饰音：true 时不进判分分母（§6）
    let isGrace: Bool
}

/// 演奏音符（从 MIDI jsonl 解析，踏板修正后）
struct PlayedNote: Equatable, Sendable {
    let pitch: UInt8
    /// 相对 take 演奏锚点（PracticeSession 只在 performing 且 connected 时落盘，
    /// 解析到的首事件即演奏起点，min(t) 归零）
    let onsetSec: Double
    /// 踏板修正后的实际收音（§4：CC64 按住时抬手延到抬踏板）
    let endSec: Double
    let velocity: UInt8
    let isSuspicious: Bool
}

enum NoteMatchClass: String, Codable, Equatable, Sendable {
    case correct, wrongPitch, missing, extra
}

struct AlignedNote: Codable, Equatable, Sendable {
    /// 匹配到的 ReferenceNote.id（回查绝对 onsetBeat 用；extra = nil）
    let refID: Int?
    let refMeasureIndex: Int?
    let refBeatInMeasure: Double?
    let refPitch: UInt8?
    let playedPitch: UInt8?
    /// 实测 onset 相对节奏图预测 onset，正=拖拍/负=抢拍
    let deltaMs: Double?
    let cls: NoteMatchClass
    let hand: Hand
    /// 真实演奏 onset（秒；M4 gate 返修 2：速度/连续性维直接消费，不走节奏图反推）。
    /// correct/wrongPitch/extra 有值；missing = nil。默认 nil 便于测试构造。
    var playedOnsetSec: Double? = nil
}

/// tempoMap 摘要（M3 NoteAligner 产出；M2 仅定义结构）
struct TempoMapSummary: Codable, Equatable, Sendable {
    /// 高置信锚点数（<3 判低置信，§5）
    let anchorCount: Int
    /// 拟合后的瞬时速度范围（BPM）
    let minBPM: Double
    let maxBPM: Double
}

/// 节奏图节点（beat → sec；P2 M4 从 NoteAligner 嵌套提升为顶层，ScoringModels 共用）
struct TempoPoint: Equatable, Sendable {
    let beat: Double
    let sec: Double
}

struct AlignmentResult: Equatable, Sendable {
    let aligned: [AlignedNote]
    let matchedRefCount: Int
    let missingCount: Int
    let extraCount: Int
    let wrongCount: Int
    let tempoMap: TempoMapSummary
    /// 节奏图节点（去趋势+段偏移前的绝对预测曲线；连续性/速度维重建 predicted 秒用）
    let tempoKnots: [TempoPoint]
    /// 0...1；公式在 NoteAligner 内注释（§5 禁黑箱）
    let confidence: Double
    /// 低置信原因（逐条中文，§5）
    let lowConfidenceReasons: [String]
    /// 演奏遍数（本批取首遍评分，§5 多遍口径）
    let passesPlayed: Int
    /// 首遍是否覆盖区间内全部小节
    let coversFullScope: Bool
}

// MARK: - §9 容差与课程标准（公开可查，非黑箱）

/// 节奏容差（按水平分级；BLE 10–20ms 抖动的带宽，PRD L57 不假装亚毫秒）
struct ScoringTolerance: Equatable, Sendable {
    /// 节奏容差窗（毫秒；匹配对 |deltaMs| 落带内算节奏正确）
    let timingWindowMs: Double

    static let beginner = ScoringTolerance(timingWindowMs: 120)
    static let intermediate = ScoringTolerance(timingWindowMs: 80)
    static let advanced = ScoringTolerance(timingWindowMs: 50)
}

/// 过关硬指标（阈值公开可查，S09/S13 以真实数值渲染并显示「差多少」）
struct ScoringStandards: Equatable, Sendable {
    enum Level: String, CaseIterable, Sendable {
        case beginner, intermediate, advanced
    }

    let level: Level
    let tolerance: ScoringTolerance
    /// 错音率阈值（0...1）
    let maxWrongNoteRate: Double
    /// 节奏偏差中位数阈值（毫秒）
    let maxRhythmMedianMs: Double
    /// 目标速度 = 参考速度 × 该比例
    let targetTempoRatio: Double

    /// 静态表（SPEC §9；集中一处，P2.1 再细化）
    static let beginner = ScoringStandards(
        level: .beginner, tolerance: .beginner,
        maxWrongNoteRate: 0.10, maxRhythmMedianMs: 100, targetTempoRatio: 0.80
    )
    static let intermediate = ScoringStandards(
        level: .intermediate, tolerance: .intermediate,
        maxWrongNoteRate: 0.05, maxRhythmMedianMs: 70, targetTempoRatio: 0.90
    )
    static let advanced = ScoringStandards(
        level: .advanced, tolerance: .advanced,
        maxWrongNoteRate: 0.03, maxRhythmMedianMs: 50, targetTempoRatio: 1.00
    )

    /// 难度映射（写死集中；入门：拜厄/哈农/示例/导入；进阶：599。P2.1 再细化）
    static func standards(forBook book: String) -> ScoringStandards {
        switch book {
        case "车尔尼599": .intermediate
        default: .beginner
        }
    }

    /// confidence 门禁阈值（固定 0.6；<0.6 不进门禁，§9 可调集中点）
    static let confidenceGateThreshold: Double = 0.6
}

// MARK: - G3 矫正处方核心层（ADR-0005；诊断 → 处方 → 复查闭环的纯函数部分）
// 全部非隔离纯值型/纯函数：不碰 ModelContext、不碰 Piece.status、不写 Take/TakeAnalysis
//（红线 4：处方不锁过关，过关唯一依据仍是硬指标）。

/// 错误类型全量 8 类（ADR-0005 决策一，一次建全）
enum CorrectionErrorType: String, CaseIterable, Codable, Sendable {
    case wrongPitch // 错音
    case missing // 漏音
    case extra // 多弹
    case rhythm // 节奏偏差
    case tempo // 速度不足
    case dynamics // 力度
    case continuity // 连续性中断
    case hands // 双手配合
}

/// 一条练习法（ADR-0005 决策二：手工编表、集中一处、非黑箱，不跨曲推荐）。
/// Codable：处方快照需经 JSONEncoder/JSONDecoder 编解码（remedySnapshotJSON / remedies）。
struct Remedy: Codable, Equatable, Sendable {
    /// 慢练速度比（相对参考速度，0 < ratio <= 1）
    let tempoRatio: Double
    let separateHands: Bool
    let useMetronome: Bool
    /// 中文达成目标（Stage B 矫正卡展示）
    let goal: String
}

/// 一次分析喂给分类器的非持久输入（从 TakeAnalysis 转换而来，见 CorrectionPrescriptionStore.makeSignals）。
/// nil = 该维算不出，分类器据此**不判**该类（红线 1：诚实，禁止编错）。
struct CorrectionSignals: Equatable, Sendable {
    let alignedNotes: [AlignedNote]
    let pitchScore: Int?
    let rhythmScore: Int?
    let tempoScore: Int?
    let dynamicsScore: Int?
    let continuityScore: Int?
    let handsScore: Int?
    let rhythmMedianMs: Double
    let avgBPM: Double
    let tempoTargetHit: Bool
    /// 节奏容差窗（来自 ScoringTolerance，判断 |deltaMs| 用）
    let timingWindowMs: Double
    let maxRhythmMedianMs: Double
    /// 目标速度比（判定速度不足用；本 Stage 目标 BPM 需参考速度才可算，signals 不带，
    /// 故 tempo 判定不走 avgBPM 与它的组合，见 CorrectionEngine.classify 注释）
    let targetTempoRatio: Double
    let hotspotMeasures: [Int]
}

/// 错误类型 → 矫正处方引擎（纯函数命名空间；ADR-0005 决策一/二/三）
enum CorrectionEngine {

    /// 六维分「低」阈值：得分 < 60 判该类错误（0-100 口径）。
    /// 60 取「明显弱项」保守口径：更低阈值（如 50）会漏掉真实弱项，更高（如 70）会把
    /// 中等波动误判成系统性错误。集中一处，调参只改这里。（用户 2026-10-09 拍板 60）
    static let lowScoreThreshold: Int = 60

    /// 8 类归并（ADR-0005 决策一）。某维 nil（算不出）→ 不判该类；一次可同时命中多类。
    static func classify(_ s: CorrectionSignals) -> Set<CorrectionErrorType> {
        var result: Set<CorrectionErrorType> = []

        // wrongPitch：逐音错音，或 pitchScore 低（两个信号源任一即可）
        if s.alignedNotes.contains(where: { $0.cls == .wrongPitch }) || isLow(s.pitchScore) {
            result.insert(.wrongPitch)
        }
        // missing / extra：只来自逐音信号（无分数维度对应）
        if s.alignedNotes.contains(where: { $0.cls == .missing }) {
            result.insert(.missing)
        }
        if s.alignedNotes.contains(where: { $0.cls == .extra }) {
            result.insert(.extra)
        }
        // rhythm：逐音 |deltaMs| 超容差窗 / 中位数超标 / rhythmScore 低
        let hasOutOfWindowDelta = s.alignedNotes.contains { note in
            guard let delta = note.deltaMs else { return false }
            return abs(delta) > s.timingWindowMs
        }
        if hasOutOfWindowDelta || s.rhythmMedianMs > s.maxRhythmMedianMs || isLow(s.rhythmScore) {
            result.insert(.rhythm)
        }
        // tempo：未达目标速，或 tempoScore 低。avgBPM == 0 = 速度维算不出（Models.swift 注释口径），
        // 此时 tempoTargetHit 恒为默认 false，不据此判错（诚实：算不出的维度不判）
        if (s.avgBPM > 0 && !s.tempoTargetHit) || isLow(s.tempoScore) {
            result.insert(.tempo)
        }
        // dynamics / continuity / hands：只看分数（停顿信号 Stage A 不新增，靠分即可）
        if isLow(s.dynamicsScore) { result.insert(.dynamics) }
        if isLow(s.continuityScore) { result.insert(.continuity) }
        if isLow(s.handsScore) { result.insert(.hands) }

        return result
    }

    /// 分数维度是否「低」：nil（算不出）恒 false —— 不判，不编
    private static func isLow(_ score: Int?) -> Bool {
        guard let score else { return false }
        return score < lowScoreThreshold
    }

    /// 可评/过关结论（shouldPrescribe 的输入；从 TakeAnalysis 派生，不持久化）
    struct EvaluableOutcome: Equatable, Sendable {
        let canEvaluate: Bool
        let passesHardMetrics: Bool
        let confidence: Double
    }

    /// 连续 2 次可评不过即触发（ADR-0005 决策三）。
    /// 只挑「可评」= canEvaluate && confidence >= ScoringStandards.confidenceGateThreshold 的元素，
    /// 不可评/低置信不计入、也不打断连续计数；最近一次可评通过 = 清零 → false。
    /// - Parameter outcomesOldToNew: 时间旧→新排列
    static func shouldPrescribe(_ outcomesOldToNew: [EvaluableOutcome]) -> Bool {
        let evaluable = outcomesOldToNew.filter {
            $0.canEvaluate && $0.confidence >= ScoringStandards.confidenceGateThreshold
        }
        guard let latest = evaluable.last else { return false }
        if latest.passesHardMetrics { return false } // 已通过 → 清零
        guard evaluable.count >= 2 else { return false } // 只有一次可评不过 → 还不触发
        return !evaluable[evaluable.count - 2].passesHardMetrics
    }

    /// 「错误类型 → 练习法」手工表（ADR-0005 决策二示例数值定稿；8 类全覆盖）。
    /// 纯数据集中一处、公开可查非黑箱；不跨曲推荐其它教材条目。
    static func remedyTable() -> [CorrectionErrorType: Remedy] {
        [
            // 错音：定位看谱 + 极慢速单手单小节，先唱后弹
            .wrongPitch: Remedy(tempoRatio: 0.5, separateHands: true, useMetronome: false,
                                goal: "该段音高全部正确"),
            // 漏音：分手把隐藏的内声部/和弦音逐个出声
            .missing: Remedy(tempoRatio: 0.5, separateHands: true, useMetronome: false,
                             goal: "齐奏音一个不丢"),
            // 多弹：数拍克制，只弹谱面音
            .extra: Remedy(tempoRatio: 0.6, separateHands: false, useMetronome: true,
                           goal: "只弹谱面音，无额外触键"),
            // 节奏偏差：节拍器慢速，先拍手/单音跟拍再上键
            .rhythm: Remedy(tempoRatio: 0.6, separateHands: false, useMetronome: true,
                            goal: "节奏偏差落入容差带"),
            // 速度不足：从能稳的速度起步、节拍器阶梯提速
            .tempo: Remedy(tempoRatio: 0.7, separateHands: false, useMetronome: true,
                           goal: "达到目标速度且不中断"),
            // 力度：分句做力度对比、强调弱指下键
            .dynamics: Remedy(tempoRatio: 0.8, separateHands: false, useMetronome: false,
                              goal: "力度层次清晰可辨"),
            // 连续性：分段接缝（四小节一组接缝）、减少停
            .continuity: Remedy(tempoRatio: 0.7, separateHands: false, useMetronome: true,
                                goal: "一遍不停顿走完"),
            // 双手配合：先分手各自成型再合，合时降速
            .hands: Remedy(tempoRatio: 0.6, separateHands: true, useMetronome: false,
                           goal: "双手对齐"),
        ]
    }

    /// hotspot 兜底：空 → 返回空数组，调用方据此走整曲级练习法（慢练全曲/分手，不指定小节），
    /// 不造小节（ADR-0005 决策二）。非空原样透传（排序去重交给展示层，不在此改语义）。
    static func prescriptionHotspots(_ hotspotMeasures: [Int]) -> [Int] {
        hotspotMeasures
    }
}

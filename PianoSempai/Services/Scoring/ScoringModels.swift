import Foundation
import SheetMusicCore

// P2 判分引擎核心值类型（SPEC §2）+ 容差/课程数据（§9）。
// 纯值类型，持久层（TakeAnalysis @Model）在 Models.swift，二者分开。
// 本文件不触库、不发网络请求（红线 6）；SheetMusicCore 仅谱面值类型（Score/Chord），
// 供 G5 静态难度提取（同 ScoreExpectedPitches 的只读取音范式），仍不触 ModelContext。

// MARK: - §2 领域模型

/// 左右手（钢琴单 Part 双 Staff：staffIndex 0=右手、1=左手；单 staff 谱 = unknown）
enum Hand: String, Codable, Equatable, Sendable {
    case right, left, unknown
}

/// 练习室 hand 模式（P3 分手能力）
enum HandMode: String, Codable, Equatable, Sendable {
    case both      // 双手
    case right     // 仅右手
    case left      // 仅左手
}

/// 参考音符（从谱面提取，全局按小节/拍定位）
struct ReferenceNote: Equatable, Identifiable, Sendable {
    /// 提取顺序稳定 id（最终排序后顺序赋值）
    let id: Int
    /// 命中音符在谱面中的唯一标识（P2 逐音符着色用；nil = 无法定位）
    var noteID: NoteID?
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

    init(
        id: Int,
        noteID: NoteID? = nil,
        pitch: UInt8,
        onsetBeat: Double,
        durationBeats: Double,
        measureIndex: Int,
        beatInMeasure: Double,
        hand: Hand,
        isGrace: Bool
    ) {
        self.id = id
        self.noteID = noteID
        self.pitch = pitch
        self.onsetBeat = onsetBeat
        self.durationBeats = durationBeats
        self.measureIndex = measureIndex
        self.beatInMeasure = beatInMeasure
        self.hand = hand
        self.isGrace = isGrace
    }
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
    /// 命中音符在谱面中的唯一标识（P2 逐音符着色用；nil = 无法定位）
    let noteID: NoteID?
    /// 实测 onset 相对节奏图预测 onset，正=拖拍/负=抢拍
    let deltaMs: Double?
    let cls: NoteMatchClass
    let hand: Hand
    /// 真实演奏 onset（秒；M4 gate 返修 2：速度/连续性维直接消费，不走节奏图反推）。
    /// correct/wrongPitch/extra 有值；missing = nil。默认 nil 便于测试构造。
    var playedOnsetSec: Double? = nil

    enum CodingKeys: String, CodingKey {
        case refID, refMeasureIndex, refBeatInMeasure, refPitch, playedPitch
        case noteID, deltaMs, cls, hand, playedOnsetSec
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        refID = try c.decodeIfPresent(Int.self, forKey: .refID)
        refMeasureIndex = try c.decodeIfPresent(Int.self, forKey: .refMeasureIndex)
        refBeatInMeasure = try c.decodeIfPresent(Double.self, forKey: .refBeatInMeasure)
        refPitch = try c.decodeIfPresent(UInt8.self, forKey: .refPitch)
        playedPitch = try c.decodeIfPresent(UInt8.self, forKey: .playedPitch)
        deltaMs = try c.decodeIfPresent(Double.self, forKey: .deltaMs)
        cls = try c.decode(NoteMatchClass.self, forKey: .cls)
        hand = try c.decode(Hand.self, forKey: .hand)
        playedOnsetSec = try c.decodeIfPresent(Double.self, forKey: .playedOnsetSec)
        // NoteID 不可直接 Codable；序列化时降级为 nil，避免破坏持久化格式
        noteID = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(refID, forKey: .refID)
        try c.encodeIfPresent(refMeasureIndex, forKey: .refMeasureIndex)
        try c.encodeIfPresent(refBeatInMeasure, forKey: .refBeatInMeasure)
        try c.encodeIfPresent(refPitch, forKey: .refPitch)
        try c.encodeIfPresent(playedPitch, forKey: .playedPitch)
        try c.encodeIfPresent(deltaMs, forKey: .deltaMs)
        try c.encode(cls, forKey: .cls)
        try c.encode(hand, forKey: .hand)
        try c.encodeIfPresent(playedOnsetSec, forKey: .playedOnsetSec)
        // noteID 不参与编解码（NoteID 不可 Codable）
    }

    init(
        refID: Int? = nil,
        refMeasureIndex: Int? = nil,
        refBeatInMeasure: Double? = nil,
        refPitch: UInt8? = nil,
        playedPitch: UInt8? = nil,
        noteID: NoteID? = nil,
        deltaMs: Double? = nil,
        cls: NoteMatchClass,
        hand: Hand,
        playedOnsetSec: Double? = nil
    ) {
        self.refID = refID
        self.refMeasureIndex = refMeasureIndex
        self.refBeatInMeasure = refBeatInMeasure
        self.refPitch = refPitch
        self.playedPitch = playedPitch
        self.noteID = noteID
        self.deltaMs = deltaMs
        self.cls = cls
        self.hand = hand
        self.playedOnsetSec = playedOnsetSec
    }
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

    /// hotspot（0-based，同 TakeAnalysis.hotspotMeasures 口径）→ 进房初始循环区间（1-based）。
    /// 空 hotspot = 整曲级 → (1, totalMeasures)；非空 → 包围盒 min/max +1（0-based 转 1-based），
    /// 不连续热点也按包围盒收（用户可再手动收窄，同 LoopService.hotspotRange 口径）。
    /// 再经钳制保证 1 ≤ start < end ≤ total；单热点终点自然顶到相邻下一小节。
    /// totalMeasures <= 0（谱未加载/无小节）无法构成合法区间 → (1,1) 诚实兜底，不编。
    /// 钳制逻辑内联自 LoopService.clamped（ScoringModels 不 import 业务模块，避免跨层依赖）。
    static func initialLoopRange(hotspots: [Int], totalMeasures: Int) -> (start: Int, end: Int) {
        let total = max(1, totalMeasures)
        guard total >= 2 else { return (1, 1) }
        let s0: Int
        let e0: Int
        if let minM = hotspots.min(), let maxM = hotspots.max(), minM >= 0 {
            s0 = minM + 1
            e0 = maxM + 1
        } else {
            s0 = 1
            e0 = total
        }
        // 内联 LoopService.clamped：1 ≤ start < end ≤ total（负/越界 hotspot 一并钳回合法）
        let s = min(max(1, s0), total - 1)
        let e = min(max(s + 1, e0), total)
        return (s, e)
    }

    /// 命中类练习法 → 进房初始速度比（取最保守、最慢的那个，避免一开始就快；ADR-0005 决策四）。
    /// 空 → 1.0（不降速）；非空 → min(tempoRatio)，夹在 0.3...1.0（0.3 防病态极慢值）。
    static func initialTempoRatio(_ remedies: [CorrectionErrorType: Remedy]) -> Double {
        guard let minRatio = remedies.values.map(\.tempoRatio).min() else { return 1.0 }
        return min(max(minRatio, 0.3), 1.0)
    }
}

// MARK: - G3 Stage B：错误类型展示名（只做展示映射，不改 rawValue/判定口径）

extension CorrectionErrorType {
    /// 展示中文名（ADR-0005 决策一 8 类依次；卡面/练习法行用）
    var displayName: String {
        switch self {
        case .wrongPitch: "错音"
        case .missing: "漏音"
        case .extra: "多弹"
        case .rhythm: "节奏偏差"
        case .tempo: "速度不足"
        case .dynamics: "力度"
        case .continuity: "连续性中断"
        case .hands: "双手配合"
        }
    }
}

// MARK: - G5 奖励曲静态难度（ADR-0006 Stage A 纯核心；三档定级 / 难点窗口 / 每日铺路选择）
// 全部纯函数：不碰 ModelContext、不碰 Piece.status、不写 Take/TakeAnalysis，不做 IO——
// 谱由调用方加载后传入（当前拜厄/哈农条目谱的定位与加载在 store/调用侧，ADR-0006 决策一）。

/// 奖励曲（导入曲）静态难度评估（ADR-0006 决策一/三/五/七）
enum RewardDifficulty {

    // MARK: 常量（集中公开、非黑箱；调参只改这里，ADR-0006 决策一）

    /// 分量归一化上限：原始分量 / 上限后 clamp 到 0...1（量纲不同，合成前必须归一）
    /// density：单小节音符数上限（4/4 双手八分音符常见 ~16，24 留足余量）
    static let densityCap: Double = 24
    /// maxIntervalJump：旋律相邻音最大半音跳度上限（两个八度）
    static let intervalCap: Double = 24
    /// maxChordThickness：单 chord 同时键数上限（一只手最多 5 键，6 留余量）
    static let chordThicknessCap: Double = 6

    /// 小节难度分量合成权重（和为 1，单测固定；黑键是 beginner 物理难点，密度/跳度代表读谱与手位负担）
    static let wBlackKeyRatio: Double = 0.2
    static let wDensity: Double = 0.3
    static let wIntervalJump: Double = 0.3
    static let wChordThickness: Double = 0.2

    /// 整体分 = 均值 + 峰值加权（既看平均负担也看最难句；和为 1，单测固定）
    static let wMean: Double = 0.7
    static let wMax: Double = 0.3

    /// 三档阈值（相对基准；ADR-0006 决策一。边界等值归属用 ≤）
    static let kPlay: Double = 1.15
    static let kFar: Double = 1.8

    /// 边界判定的相对浮点容差：抵消 1.15 等二进制近似造成的边界误判（ADR-0006 边界等值归属）。
    static let boundaryTolerance: Double = 1e-9

    /// 难点窗口长度（连续小节数；ADR-0006 决策五）
    static let windowMinSize = 2
    static let windowMaxSize = 4

    /// 引擎版本（评估留痕；改口径必须升版本，upsert 时写入）
    static let engineVersion = "G5-difficulty-1.0"

    /// 三档定级（ADR-0006 决策一：相对当前课程进度，非绝对标尺）
    enum Grade: String, CaseIterable, Sendable {
        case play // 现在能弹
        case stretch // 偏难（可铺路）
        case far // 远超当前（只标档，不铺路）
    }

    /// 黑键判定（纯基于 MIDI pitch class，确定性）。beginner 产品口径——黑键物理上更难
    ///（手位收窄+变音记号读谱负担），因此**调号里"实为黑键"的音同样计入**：本函数只看
    /// pitch class，不查谱面记谱写法，天然满足该口径。
    static func isBlackKey(_ midiPitch: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(midiPitch % 12) // C#/D#/F#/G#/A#
    }

    /// 谱 → 每小节 chord 分组音高：[measure][chord][pitch]（0-based 小节，不去重、保留出现序）。
    /// 遍历范式同 ScoreExpectedPitches.extract（parts.first 的首个 staff，voices → elements → chord.notes）；
    /// 保留 chord 分组是为了区分「同 chord 同时音」（和弦厚度）与「跨 chord 旋律跳度」。
    static func extractChords(score: Score) -> [[[Int]]] {
        guard let staff = score.parts.first?.staves.first else { return [] }
        var result: [[[Int]]] = []
        for measure in staff.measures {
            var chords: [[Int]] = []
            for voice in measure.voices {
                for element in voice.elements {
                    if case let .chord(chord) = element {
                        chords.append(chord.notes.map(\.pitch))
                    }
                }
            }
            result.append(chords)
        }
        return result
    }

    /// 一个小节的静态难度分量 + 合成分（各分量先归一化再加权，见常量注释）
    struct MeasureDifficulty: Equatable, Sendable {
        /// 黑键音符数 / 总音符数（空小节 0）
        var blackKeyRatio: Double
        /// 该小节音符数（同 chord 的同时音也计）
        var density: Double
        /// 相邻旋律音最大半音差：旋律线 = 每 chord 取代表音（出现序首音），只在跨 chord 的
        /// 进行上算，同 chord 内不算跳；不足 2 个 chord 为 0
        var maxIntervalJump: Int
        /// 单个 chord 同时键数最大值（空小节 0）
        var maxChordThickness: Int
        /// 加权合成分 0...1（分量归一后按 w* 权重合成）
        var score: Double
    }

    /// 小节难度（输入 = 该小节的 chord 序列，来自 extractChords 的一行）。
    /// 空 chord 序列 / 全空 chord → 各分量 0、score 0（不编，红线 1）。
    static func measureDifficulty(_ chords: [[Int]]) -> MeasureDifficulty {
        let totalPitches = chords.reduce(0) { $0 + $1.count }
        guard totalPitches > 0 else {
            return MeasureDifficulty(blackKeyRatio: 0, density: 0,
                                     maxIntervalJump: 0, maxChordThickness: 0, score: 0)
        }
        let blackCount = chords.reduce(0) { $0 + $1.filter { isBlackKey($0) }.count }
        let blackKeyRatio = Double(blackCount) / Double(totalPitches)
        let density = Double(totalPitches)
        let maxChordThickness = chords.map(\.count).max() ?? 0
        let melody = chords.compactMap(\.first)
        var maxIntervalJump = 0
        if melody.count >= 2 {
            for i in 1..<melody.count {
                maxIntervalJump = max(maxIntervalJump, abs(melody[i] - melody[i - 1]))
            }
        }
        let score = wBlackKeyRatio * clamp01(blackKeyRatio)
            + wDensity * clamp01(density / densityCap)
            + wIntervalJump * clamp01(Double(maxIntervalJump) / intervalCap)
            + wChordThickness * clamp01(Double(maxChordThickness) / chordThicknessCap)
        return MeasureDifficulty(blackKeyRatio: blackKeyRatio, density: density,
                                 maxIntervalJump: maxIntervalJump, maxChordThickness: maxChordThickness,
                                 score: score)
    }

    /// 整体难度分 = 小节分均值 × wMean + 峰值 × wMax（均值看平均负担、峰值看最难句）。
    /// 空曲 → 0。
    static func overallDifficulty(_ measures: [MeasureDifficulty]) -> Double {
        guard !measures.isEmpty else { return 0 }
        let mean = measures.map(\.score).reduce(0, +) / Double(measures.count)
        let peak = measures.map(\.score).max() ?? 0
        return mean * wMean + peak * wMax
    }

    /// 难点连续窗口（ADR-0006 决策五：2-4 小节，累计难度最高的连续窗口）。
    /// 返回 0-based 小节下标（同 TakeAnalysis.hotspotMeasures 口径）。确定性规则：
    /// 同分取更短窗、再同分取起点更靠前，禁随机。小节总数 < minSize → 返回全部小节；
    /// 空曲 → []；窗口长度钳制到实际小节数。
    static func hardestWindow(_ measures: [MeasureDifficulty],
                              minSize: Int = 2, maxSize: Int = 4) -> [Int] {
        let count = measures.count
        guard count > 0 else { return [] }
        let lower = max(1, minSize)
        guard count >= lower else { return Array(0..<count) }
        let upper = min(maxSize, count)
        guard lower <= upper else { return Array(0..<count) } // 调用方误传 maxSize < minSize：不崩，退全曲
        // 前缀和：sum(start..<start+size) = prefix[start+size] - prefix[start]
        var prefix = [0.0]
        for measure in measures { prefix.append(prefix.last! + measure.score) }
        var best: (start: Int, size: Int, sum: Double)? = nil
        // size 升序（同分取更短）、start 升序（再同分取更靠前）→ 严格大于才替换即为确定性
        for size in lower...upper {
            for start in 0...(count - size) {
                let sum = prefix[start + size] - prefix[start]
                if best == nil || sum > best!.sum {
                    best = (start, size, sum)
                }
            }
        }
        guard let best else { return Array(0..<count) }
        return Array(best.start..<(best.start + best.size))
    }

    /// 当前水平基准分：对当前在练的拜厄/哈农条目谱（调用方加载后传入，本函数不做 IO）
    /// 用同一套 overallDifficulty 计算，取较高者（代表当下能处理的上限）。两者都 nil / 都算不出 → 0。
    static func baselineScore(currentBeyerScore: Score?, currentHanonScore: Score?) -> Double {
        func overall(of score: Score?) -> Double {
            guard let score else { return 0 }
            return overallDifficulty(extractChords(score: score).map { measureDifficulty($0) })
        }
        return max(overall(of: currentBeyerScore), overall(of: currentHanonScore))
    }

    /// 相对基准定级（ADR-0006 决策一）。baseline <= 0（当前条目谱算不出）→ 无法相对定级，
    /// 返回 nil，调用方按「暂无法分析」诚实处理（红线 1：禁止编档位）。
    static func grade(difficulty: Double, baseline: Double) -> Grade? {
        guard baseline > 0 else { return nil }
        if difficulty <= baseline * kPlay * (1 + boundaryTolerance) { return .play }
        if difficulty <= baseline * kFar  * (1 + boundaryTolerance) { return .stretch }
        return .far
    }

    /// 每日 1 条铺路选择的候选（ADR-0006 决策三；值类型，Equatable）
    struct PavingCandidate: Equatable, Sendable {
        let pieceId: UUID
        let title: String
        let difficulty: Double
        let baseline: Double
        /// 该曲最近一次铺路卡 prescribedAt；nil = 从未铺路
        let lastPavedAt: Date?
    }

    /// 每日至多 1 条铺路选择（ADR-0006 决策三/七，确定性）：
    /// 仅 stretch 档进入候选（play 无需铺、far 铺了也跟不上）；
    /// excludedPieceIds = 当天已有未完成铺路卡的 piece（调用方查库得出），排除；
    /// 按「超出基准比例 difficulty/baseline」降序 → lastPavedAt 最早（从未铺路排最前）→
    /// title 升序 → entityId 升序 tie-break。空 → nil。
    static func pickDailyPaving(_ candidates: [PavingCandidate],
                                excludedPieceIds: Set<UUID> = []) -> PavingCandidate? {
        let eligible = candidates.filter { candidate in
            !excludedPieceIds.contains(candidate.pieceId)
                && grade(difficulty: candidate.difficulty, baseline: candidate.baseline) == .stretch
        }
        return eligible.min(by: pavingOrder)
    }

    /// 候选排序（严格弱序：a 应排在 b 前则 true）
    private static func pavingOrder(_ a: PavingCandidate, _ b: PavingCandidate) -> Bool {
        let ratioA = a.difficulty / a.baseline
        let ratioB = b.difficulty / b.baseline
        if ratioA != ratioB { return ratioA > ratioB }
        switch (a.lastPavedAt, b.lastPavedAt) {
        case (nil, nil): break
        case (nil, _): return true // 从未铺路排最前
        case (_, nil): return false
        case (let x?, let y?):
            if x != y { return x < y }
        }
        if a.title != b.title { return a.title < b.title }
        return a.pieceId < b.pieceId
    }

    /// 归一到 0...1（上限做除法后钳制；负值输入视作 0）
    private static func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

// MARK: - HandMode UI

extension HandMode {
    var title: String {
        switch self {
        case .both: "双手"
        case .right: "右手"
        case .left: "左手"
        }
    }
}

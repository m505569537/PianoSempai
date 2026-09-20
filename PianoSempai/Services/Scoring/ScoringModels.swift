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

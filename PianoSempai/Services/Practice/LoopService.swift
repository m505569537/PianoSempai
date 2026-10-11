import Foundation

// 段落循环逻辑（S12）——可测服务（Hermes M5 指令：循环逻辑放可测服务）。
// 规则（practice.md / S12 spec）：
// - region：1 ≤ start < end ≤ 总小节数（1-based 展示，内部转 0-based）；
// - 三种模式：loop（逐遍循环）/ adaptiveUp（连续两遍零错音 → +5 BPM）/ adaptiveDown（一遍有错音 → −5；连崩 2 遍 → 建议休息）；
// - 速度上限 = 参考速度（曲目 referenceTempo，P1 用固定参考 84——拜厄入门段；不越上限）；
// - 连崩 2 遍后第三遍开始前建议休息（重置连崩计数）。
// TODO(P2)：错误计数接 M5 完整对齐判分（容差带/踏板参与），当前按"简单匹配错音数"口径（brief 授权）。

enum LoopMode: String, CaseIterable {
    case loop // 逐遍循环（练完停 3 秒再来）
    case adaptiveUp // 达标后自动 +5 BPM
    case adaptiveDown // 崩了自动 −5 BPM（连崩 2 遍暂停，提示休息）
}

struct LoopConfig: Equatable {
    var startMeasure: Int = 1 // 1-based
    var endMeasure: Int = 8 // 1-based inclusive
    var mode: LoopMode = .loop
    var gapSec: Int = 3
    var countIn: Bool = true
    /// 目标遍数（P1 循环遍数面板）：0 = 不限（维持原状），>0 = 顶栏/循环格显示「已完成/目标」进度。
    /// 只作交互层计数展示，不进过关判定、不改引擎 wrap 行为（wrap 检测本就在 consumeFollow 内）。
    var targetLoopCount: Int = 0

    var measureCount: Int { endMeasure - startMeasure + 1 }
}

struct LoopTempoState: Equatable {
    var bpm: Int
    var referenceBpm: Int
    /// 连续零错音遍数（adaptiveUp 用）
    var consecutiveCleanPasses: Int = 0
    /// 连续有错音遍数（adaptiveDown 用）
    var consecutiveBadPasses: Int = 0
    /// 是否应提示休息（连崩 2 遍）
    var shouldSuggestRest: Bool = false
    /// 最近一次速度变化（toast 文案用；nil = 无变化）
    var lastChange: TempoChange?
}

struct TempoChange: Equatable {
    enum Direction { case up, down }
    let direction: Direction
    let newBpm: Int
}

enum LoopService {

    /// 区间合法性（S12 交互态：越界时步进器禁用/拒绝开始循环）
    static func isValid(start: Int, end: Int, totalMeasures: Int) -> Bool {
        let total = max(1, totalMeasures)
        return start >= 1 && start < end && end <= total
    }

    /// 越界钳制：1 ≤ start < end ≤ totalMeasures（S12 交互态）
    static func clamped(start: Int, end: Int, totalMeasures: Int) -> (start: Int, end: Int) {
        let total = max(1, totalMeasures)
        let s = min(max(1, start), total - 1)
        let e = min(max(s + 1, end), total)
        return (s, e)
    }

    /// 一遍结束后按模式与错音数推进速度状态（纯函数）
    static func afterPass(_ state: LoopTempoState, mode: LoopMode, wrongNotesThisPass: Int) -> LoopTempoState {
        var s = state
        s.lastChange = nil
        s.shouldSuggestRest = false
        let clean = wrongNotesThisPass == 0

        switch mode {
        case .loop:
            break
        case .adaptiveUp:
            if clean {
                s.consecutiveCleanPasses += 1
                s.consecutiveBadPasses = 0
                if s.consecutiveCleanPasses >= 2, s.bpm + 5 <= s.referenceBpm {
                    s.bpm += 5
                    s.consecutiveCleanPasses = 0 // 提速后重新计"连续两遍"
                    s.lastChange = TempoChange(direction: .up, newBpm: s.bpm)
                }
            } else {
                s.consecutiveCleanPasses = 0
            }
        case .adaptiveDown:
            if clean {
                s.consecutiveBadPasses = 0
                s.consecutiveCleanPasses += 1
            } else {
                s.consecutiveCleanPasses = 0
                s.consecutiveBadPasses += 1
                if s.bpm - 5 >= 40 {
                    s.bpm -= 5
                    s.lastChange = TempoChange(direction: .down, newBpm: s.bpm)
                }
                if s.consecutiveBadPasses >= 2 {
                    s.shouldSuggestRest = true
                    s.consecutiveBadPasses = 0 // 提示后重置
                }
            }
        }
        return s
    }

    /// toast 文案（S11 交互态锁定语气；纯函数便于测）
    static func toastText(for change: TempoChange) -> String {
        switch change.direction {
        case .up: "很稳，速度提到 ♩=\(change.newBpm)"
        case .down: "慢一点，回到 ♩=\(change.newBpm)"
        }
    }

    /// 错误热点 → 1-based 循环区间（S12 快捷 chip「错误热点」）。
    /// 热点小节是 0-based（TakeScorer 口径：beat3 ∈ 小节 0）。取连续跨度 min...max 转 1-based；
    /// 单热点（min==max）为保 start<end 终点向后扩 1 小节；再经 clamped 钳制，
    /// 钳制后必须 start ≥ 1 且 start < end，否则 nil（无数据/total 不足也 nil）。
    /// 保持简单稳健：不做聚类，跨度大先接受，用户可再手动收窄。
    static func hotspotRange(hotspotMeasures: [Int], totalMeasures: Int) -> (start: Int, end: Int)? {
        let total = max(1, totalMeasures)
        guard let minM = hotspotMeasures.min(), let maxM = hotspotMeasures.max(), minM >= 0 else { return nil }
        let start = minM + 1
        var end = maxM + 1
        if minM == maxM { end = minM + 2 }
        let c = clamped(start: start, end: end, totalMeasures: total)
        return c.start >= 1 && c.start < c.end ? c : nil
    }

    /// 该曲目最近一次判分出的错误热点小节（0-based；无数据 → 空数组）。
    /// 数据口径：TakeAnalysis.takeId == Take.entityId，Take.pieceId == Piece.entityId。
    /// 只取 hotspotMeasures 非空的分析里 analyzedAt 最新的一条（调用方全量取后内存 join，量小）。
    static func latestHotspotMeasures(pieceId: UUID?, takes: [Take], analyses: [TakeAnalysis]) -> [Int] {
        guard let pieceId else { return [] }
        let takeIds = Set(takes.filter { $0.pieceId == pieceId }.map(\.entityId))
        guard let latest = analyses
            .filter({ takeIds.contains($0.takeId) && !$0.hotspotMeasures.isEmpty })
            .max(by: { $0.analyzedAt < $1.analyzedAt })
        else { return [] }
        return latest.hotspotMeasures
    }
}

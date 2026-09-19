import Foundation

// 在线跟弹引擎（P1 简化匹配，M5 对齐算法 P2 替换——brief「与谱面对比的简单匹配」）。
// 纯逻辑、可单测。规则：
// - 每小节维护"期望音多重集"；noteOn 命中当前小节剩余期望 → 消耗并推进；音序打乱允许（不要求严格顺序）；
// - 未命中当前小节任何期望 → 记一次错音（含小节号 + 实际音高），光标不打断（PRD：错音不丢光标）；
// - 当前小节期望耗尽 → 光标推进到下一小节（超出循环终点回到起点，由 LoopService 决定）；
// - 多弹同一音而期望已耗尽 → 同样计错音。

struct WrongNoteRecord: Equatable, Hashable {
    let measure: Int // 1-based 展示用小节号
    let actualPitch: UInt8
}

struct ScoreFollowState: Equatable {
    /// 当前小节（0-based 内部索引；展示时 +1）
    var measureIndex: Int = 0
    /// 各小节剩余期望音多重集
    var remaining: [Int: [UInt8]] = [:]
    /// 错音清单
    var wrongNotes: [WrongNoteRecord] = []
    /// 已命中的期望音数
    var matchedCount: Int = 0
    /// 已弹的 noteOn 总数
    var playedCount: Int = 0
}

enum ScoreFollowEngine {

    /// 初始化跟随状态：region 内每小节的期望音多重集
    static func initialState(expectedPerMeasure: [[UInt8]], startMeasureIndex: Int = 0) -> ScoreFollowState {
        var remaining: [Int: [UInt8]] = [:]
        for (idx, pitches) in expectedPerMeasure.enumerated() {
            remaining[idx] = pitches
        }
        return ScoreFollowState(measureIndex: startMeasureIndex, remaining: remaining)
    }

    /// 喂入一个 noteOn，返回新状态（值语义，便于测试与撤销）。
    /// endMeasureIndex：循环终点（exclusive 的下一索引；region 内最后一小节索引）。
    static func consume(
        _ state: ScoreFollowState,
        pitch: UInt8,
        expectedPerMeasure: [[UInt8]],
        endMeasureIndex: Int,
        loopEnabled: Bool
    ) -> ScoreFollowState {
        var state = state
        state.playedCount += 1

        var measure = state.measureIndex
        // 越界保护（region 变更等）
        measure = min(measure, endMeasureIndex)

        if let idx = state.remaining[measure]?.firstIndex(of: pitch) {
            state.remaining[measure]?.remove(at: idx)
            state.matchedCount += 1
        } else {
            state.wrongNotes.append(WrongNoteRecord(measure: measure + 1, actualPitch: pitch))
        }

        // 当前小节期望耗尽 → 推进到下一小节（循环或停尾）
        if (state.remaining[measure] ?? []).isEmpty {
            if measure < endMeasureIndex {
                measure += 1
            } else if loopEnabled {
                measure = 0
                // 回到起点：重置 region 内剩余期望
                for i in 0...endMeasureIndex {
                    state.remaining[i] = expectedPerMeasure.indices.contains(i) ? expectedPerMeasure[i] : []
                }
            }
        }
        state.measureIndex = measure
        return state
    }

    /// 当前小节是否整段走完（用于一遍循环结束判定：光标在终点且终点耗尽）
    static func passCompleted(_ state: ScoreFollowState, endMeasureIndex: Int) -> Bool {
        state.measureIndex == endMeasureIndex && (state.remaining[endMeasureIndex] ?? []).isEmpty
    }
}

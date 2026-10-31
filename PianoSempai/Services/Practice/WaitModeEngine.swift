import Foundation

// 等待模式推进引擎（G10 / ADR-0013）：「弹对才前进」的学谱形态。
// 推进语义与 ScoreFollowEngine 同构（期望音多重集消耗、音序不敏感），
// 三点收紧（ADR-0013 决策二）：
// 1. 弹错不动光标——ScoreFollowEngine 的错音不打断在这里升级为「错音不前进」：
//    光标即进度，未命中当前小节任何期望音时光标原地不动（错音照记，供会话内反馈）。
// 2. wrap 即一遍完成——终点小节期望耗尽 → 遍数 +1 并 wrap 回起点重置期望；
//    无时钟、无速度概念（tempoState 不参与），遍数只作展示不进任何判定。
// 3. 回退可控——长按回退上一小节（期望重置为该小节全量），解决「忘记音了」；
//    不做「等 5 秒自动提示」（那是假自动演奏）。
// 纯函数、值语义、零 UI；判分链隔离由 Take.isWaitSession 承担（本文件不触模型）。

/// 等待模式推进事件：引擎对单个 noteOn 的裁决结果（视图据此做反馈，如轻点闪光）。
enum WaitModeOutcome: Equatable {
    /// 命中当前小节期望音（已消耗；若该音耗尽了整小节，measureAdvanced = true）
    case hit(measureAdvanced: Bool)
    /// 未命中任何期望音（错音记入 state.wrongNotes，光标不动）
    case miss
    /// 本遍完成（终点小节耗尽，已 wrap 回起点；loopCompletedCount 已 +1）
    case passCompleted
}

enum WaitModeEngine {

    // MARK: - 推进

    /// 喂入一个 noteOn，返回新状态与裁决。值语义（与 ScoreFollowEngine.consume 一致）。
    /// - Parameters:
    ///   - state: 当前跟随状态（复用 ScoreFollowState：measureIndex / remaining / wrongNotes / matchedCount / playedCount）
    ///   - pitch: 实际弹的音（velocity > 0 的 noteOn；上游已过滤 velocity=0）
    ///   - expectedPerMeasure: region 内每小节期望音（region 外小节为空数组；下标 = 0-based 小节索引）
    ///   - endMeasureIndex: 循环终点小节索引（0-based，inclusive）
    ///   - loopCompletedCount: 当前遍数（传入旧值，返回 +1 后的新值；仅 passCompleted 时变）
    static func consume(
        _ state: ScoreFollowState,
        pitch: UInt8,
        expectedPerMeasure: [[UInt8]],
        endMeasureIndex: Int,
        loopCompletedCount: Int
    ) -> (state: ScoreFollowState, outcome: WaitModeOutcome, loopCompletedCount: Int) {
        var state = state
        state.playedCount += 1

        // 越界保护（region 变更等）：与 ScoreFollowEngine 同款
        let measure = min(state.measureIndex, endMeasureIndex)
        state.measureIndex = measure

        guard let idx = state.remaining[measure]?.firstIndex(of: pitch) else {
            // 弹错：记错音、光标原地不动（ADR-0013 决策二「弹错不动光标」）
            state.wrongNotes.append(WrongNoteRecord(measure: measure + 1, actualPitch: pitch))
            return (state, .miss, loopCompletedCount)
        }

        state.remaining[measure]?.remove(at: idx)
        state.matchedCount += 1

        // 整小节耗尽 → 推进
        if (state.remaining[measure] ?? []).isEmpty {
            if measure < endMeasureIndex {
                state.measureIndex = measure + 1
                return (state, .hit(measureAdvanced: true), loopCompletedCount)
            }
            // 终点耗尽 = 一遍完成：wrap 回起点、重置 region 内期望、遍数 +1
            state.measureIndex = 0
            for i in 0...endMeasureIndex {
                state.remaining[i] = expectedPerMeasure.indices.contains(i) ? expectedPerMeasure[i] : []
            }
            return (state, .passCompleted, loopCompletedCount + 1)
        }
        return (state, .hit(measureAdvanced: false), loopCompletedCount)
    }

    // MARK: - 回退

    /// 长按回退：光标退到上一小节（起点小节则原地不动），该小节期望重置为全量。
    /// 中途已消耗的期望不恢复（只恢复目标小节自身）——回退语义是「重弹这一小节」，
    /// 不追求账面严格（等待模式无判分，账面只服务进度显示）。
    static func retreat(
        _ state: ScoreFollowState,
        expectedPerMeasure: [[UInt8]],
        startMeasureIndex: Int,
        endMeasureIndex: Int
    ) -> ScoreFollowState {
        var state = state
        let current = min(state.measureIndex, endMeasureIndex)
        guard current > startMeasureIndex else { return state } // 已在起点：不回退
        let target = current - 1
        state.measureIndex = target
        state.remaining[target] = expectedPerMeasure.indices.contains(target) ? expectedPerMeasure[target] : []
        return state
    }

    // MARK: - 进度展示口径

    /// 顶栏副行文案（「小节 x/y · 第 N 遍」）。纯函数供单测与 Stage B 视图共用。
    static func progressText(
        measureIndex: Int,
        startMeasure: Int,
        endMeasure: Int,
        loopCompletedCount: Int
    ) -> String {
        let x = startMeasure + max(0, min(measureIndex, endMeasure - startMeasure))
        let y = endMeasure
        return "小节 \(x)/\(y) · 第 \(max(1, loopCompletedCount + 1)) 遍"
    }
}

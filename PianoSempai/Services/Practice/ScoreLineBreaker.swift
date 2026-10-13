import Foundation
import SheetMusicCore
import SheetMusicLayout

/// 把谱面重排成「每行 N 小节」（问题4）。纯转换、不依赖 SwiftUI、可单测。
///
/// 背景：内置公版谱（Beyer/Hanon）在 MusicXML 里带了 `<newline>`/system-layout，
/// loader 把它们映射成每个 Measure 的 `lineBreak = true`，于是每行只放一两小节，
/// 与可用宽度无关。所以转换分两步：
/// 1. 清掉所有原稿强制换行（lineBreak/pageBreak 都清，pageBreak 也会连带换行）；
/// 2. measuresPerLine ≥ 2 时，每 N 小节（除最后一小节外）注入 lineBreak。
///
/// measuresPerLine == 0（自动）：只清不注，引擎纯按可用宽度排。
///
/// 换行只看 staff 0，但为保持多谱表/落库一致，这里对每个 part 的每个 staff 同步设置。
enum ScoreLineBreaker {
    static func apply(to score: Score, measuresPerLine: Int) -> Score {
        var score = score
        let perLine = measuresPerLine >= 2 ? measuresPerLine : 0
        for partIndex in score.parts.indices {
            score.parts.updateValue(at: partIndex) { part in
                for staffIndex in part.staves.indices {
                    part.staves.updateValue(at: staffIndex) { staff in
                        staff.measures = staff.measures.enumerated().map { idx, measure in
                            var m = measure
                            // 1) 清原稿强制换行
                            m.lineBreak = false
                            m.pageBreak = false
                            // 2) 每 N 小节注入（最后一小节不注：后面没东西可换）
                            if perLine > 0,
                               (idx + 1) % perLine == 0,
                               idx < staff.measures.count - 1 {
                                m.lineBreak = true
                            }
                            return m
                        }
                    }
                }
            }
        }
        return score
    }

    /// 计算应在哪些 0-based 小节后换行（测试/调试用的纯决策，不碰 Score）。
    /// 自动档（perLine<2）返回空集。
    static func breakIndices(measureCount: Int, perLine: Int) -> [Int] {
        guard perLine >= 2 else { return [] }
        return Swift.stride(from: perLine - 1, through: measureCount - 2, by: perLine).map { $0 }
    }

    /// 固定档自适应字号：二分搜索「除最后一行外每行恰 N 小节」能放下的最大 staffSize。
    ///
    /// 背景：注入 lineBreak 后引擎仍会按可用宽度提前折行——可用宽度放不下 N 小节时
    /// 每行小节数不齐（如哈农每小节 8 个十六分音符，字号 11 时每行只塞得下 4 个）。
    /// 实测可行字号：拜厄 8/行=8.5、哈农 4/行=11.0、哈农 8/行=6.0（微缩，档位本身的选择）。
    /// 无满足解（≥floor 仍放不下）返回 baseSize 布局，档位诚实不生效但不错乱。
    static func fittingStaffSize(
        score: Score, perLine: Int, availableWidth: CGFloat,
        baseSize: CGFloat = 28, floorSize: CGFloat = 5.5,
        makeOptions: (CGFloat) -> ScoreViewOptions
    ) -> (size: CGFloat, document: LayoutDocument) {
        func layout(_ size: CGFloat) -> LayoutDocument {
            LayoutEngine.layout(score: score, options: makeOptions(size), availableWidth: availableWidth)
        }
        // 可行性 P(size) 随字号单调递减（越小越放得下）。目标：P 为真的最大字号。
        let base = layout(baseSize)
        // 基础字号直接满足 → 不缩
        if breaksRespected(base, perLine: perLine) { return (baseSize, base) }
        // 下限都不满足 → 无解，诚实回退基础布局
        let floorDoc = layout(floorSize)
        guard breaksRespected(floorDoc, perLine: perLine) else { return (baseSize, base) }
        var lo = floorSize
        var hi = baseSize
        for _ in 0..<8 {
            let mid = (lo + hi) / 2
            if breaksRespected(layout(mid), perLine: perLine) {
                lo = mid   // mid 可行 → 边界在更大字号一侧
            } else {
                hi = mid   // mid 不可行 → 边界在更小字号一侧
            }
        }
        // lo 是已知可行的最大字号（P(lo) 已为真，除非循环没进过——floorDoc 已保证进过）
        let final = layout(lo)
        if breaksRespected(final, perLine: perLine) {
            return (lo, final)
        }
        return (floorSize, floorDoc)
    }

    /// 「除最后一行外每行恰 perLine 小节」判定（行空或某行为 0 视为不满足）。
    static func breaksRespected(_ doc: LayoutDocument, perLine: Int) -> Bool {
        let counts = doc.systems.map(\.measures.count)
        guard !counts.isEmpty, counts.allSatisfy({ $0 > 0 }) else { return false }
        for (i, c) in counts.enumerated() where i < counts.count - 1 {
            if c != perLine { return false }
        }
        return true
    }
}

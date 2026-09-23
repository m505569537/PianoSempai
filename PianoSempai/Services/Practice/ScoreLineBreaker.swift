import Foundation
import SheetMusicCore

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
}

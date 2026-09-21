import Foundation

/// 谱可用性四态（SPEC §10 / M5a-C 纯决策；UI 呈现见 M5b）：
/// - realScore：有真实 scoreFile（导入曲/未来教材谱）→ 可评分，take 关联 pieceId/scoreFileId
/// - samplePiece：显式「示例曲」入口 → 加载 Bundle SpikeSample32（不冒充教材）
/// - bundledScore：内置教材条目配有随 app 分发的公版谱（拜厄/哈农）→ 可跟弹可评分
/// - unavailable：内置教材条目但无谱（车尔尼599）→ **禁止静默回退任何别的谱**
enum ScoreAvailability: Equatable {

    case realScore(ScoreFile)
    case samplePiece
    case bundledScore(book: String, number: Int)
    case unavailable

    /// 决策函数（纯）。优先级：真实谱 > 示例曲 > 内置公版谱 > 不可用。
    /// - Parameters:
    ///   - scoreFile: 关联的可跟弹谱文件（可为 nil）
    ///   - isSampleEntry: 该入口是否为显式「示例曲」（CatalogEntry.isSample）
    ///   - bundledBook: 内置教材 book（目录条目传入；示例曲 book="示例" 永不打中内置谱）
    ///   - bundledNumber: 该教材条数
    static func resolve(
        scoreFile: ScoreFile?,
        isSampleEntry: Bool,
        bundledBook: String? = nil,
        bundledNumber: Int = 0
    ) -> ScoreAvailability {
        if let scoreFile { return .realScore(scoreFile) }
        if isSampleEntry { return .samplePiece }
        if let book = bundledBook,
           BundledScore.resourceName(book: book, number: bundledNumber) != nil {
            return .bundledScore(book: book, number: bundledNumber)
        }
        return .unavailable
    }
}

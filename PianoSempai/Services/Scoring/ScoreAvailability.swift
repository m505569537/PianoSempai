import Foundation

/// 谱可用性三态（SPEC §10 / M5a-C 纯决策；UI 三态呈现留 M5b）：
/// - realScore：有真实 scoreFile（导入曲/未来教材谱）→ 可评分，take 关联 pieceId/scoreFileId
/// - samplePiece：显式「示例曲」入口 → 加载 Bundle SpikeSample32（不冒充教材）
/// - unavailable：内置教材条目但无 scoreFile → **禁止静默回退 SpikeSample32**
enum ScoreAvailability: Equatable {

    case realScore(ScoreFile)
    case samplePiece
    case unavailable

    /// 决策函数（纯）：真实谱优先于示例曲；示例曲标记次之；否则不可用。
    /// - Parameters:
    ///   - scoreFile: 关联的可跟弹谱文件（可为 nil）
    ///   - isSampleEntry: 该入口是否为显式「示例曲」（CatalogEntry.isSample）
    static func resolve(scoreFile: ScoreFile?, isSampleEntry: Bool) -> ScoreAvailability {
        if let scoreFile { return .realScore(scoreFile) }
        if isSampleEntry { return .samplePiece }
        return .unavailable
    }
}

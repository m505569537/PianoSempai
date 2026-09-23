import SwiftUI

/// 谱面显示偏好（全局，@AppStorage 持久）。目前只含「每行小节数」，
/// 后续若加谱面缩放/行距也收口在这里，避免各处散落 UserDefaults key。
///
/// measuresPerLine：
/// - 0 = 自动（清掉原稿强制换行，纯按可用宽度排，越多越挤一行）；
/// - N ≥ 2 = 每行固定 N 小节（ScoreLineBreaker 每 N 小节注入 lineBreak）。
///
/// 用 Int 而非枚举存盘，便于档位扩展且 SwiftUI Picker 直接绑定。
enum ScoreDisplayPrefs {
    static let measuresPerLineKey = "score.measuresPerLine.v1"

    /// 可选档位（Picker 用）。0 在 UI 上显示为「自动」。
    static let choices: [Int] = [0, 2, 4, 8]

    static func label(for choice: Int) -> String {
        choice == 0 ? "自动" : "\(choice) 小节/行"
    }
}

import Foundation

// 时长文案（周报 S19 / 月报 S22 共用，一处定义两处复用）。
// 纯函数、无 UI 依赖；语义与视觉规范一致：整小时省略 0 分，不足 1 小时只说分钟。
// 只在本地已有真实秒数时调用——上游缺数据时调用方给「—」/省略该行，不补 0 冒充。

enum DurationText {
    /// 「8 小时 32 分」/「8 小时」（整小时省 0 分）/「45 分」；0 秒如实给「0 分」（不省略成空串）。
    /// 负值只可能来自坏数据：取绝对值，不显示带负号的时长。
    static func hoursMinutes(_ totalSec: Int) -> String {
        let seconds = max(totalSec, 0)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分" : "\(hours) 小时"
        }
        return "\(minutes) 分"
    }
}

import UIKit

/// 触觉反馈统一收口（2026-11-12）。
///
/// 只在 UI 层调用：服务层（PracticeSession / MetronomeService）保持纯逻辑，
/// 单测不触达 UIKit 触觉；模拟器上系统自动降级为 no-op，不会崩。
/// 生成器做成静态复用并 prepare()，避免每次触发新建带来的延迟。
enum Haptics {

    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()

    /// 预热：进练习室时调一次，降低首拍触觉延迟。
    static func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        notification.prepare()
    }

    /// 节拍器每拍（含预备拍）——轻点。
    static func beat() {
        lightImpact.impactOccurred()
    }

    /// 遍数达标 / 通关闭环——比节拍明确一档。
    static func milestone() {
        mediumImpact.impactOccurred()
    }

    /// 等待模式：弹对推进。
    static func hit() {
        lightImpact.impactOccurred()
    }

    /// 等待模式：弹错（光标不动，给出可感知的否定）。
    static func miss() {
        notification.notificationOccurred(.warning)
    }

    /// 会话收尾保存。
    static func finish() {
        notification.notificationOccurred(.success)
    }
}

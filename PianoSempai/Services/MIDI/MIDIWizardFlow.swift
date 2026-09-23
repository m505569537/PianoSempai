import Foundation

/// S03 连接步推进判定（idb 走查发现的真实 bug：模拟源路径按钮可点但不动）。
/// 判定必须与按钮 enabled 条件一致：选定了真机设备，或已切到模拟源。
enum MIDIWizardFlow {
    static func canAdvanceFromConnect(
        systemDevices: [String],
        selectedDevice: String?,
        mode: MIDIHub.Mode
    ) -> Bool {
        selectedDevice != nil || mode == .simulated
    }
}

/// S03 验证步判定（onboarding.md 域契约：2 秒内收到 ≥1 个 Note On 且 velocity 有效）。
/// 纯函数：View 只把监听窗状态喂进来，规则集中在此、可单测。
enum MIDIVerifyGate {
    /// 监听窗内收到有效 Note On → 通过。
    /// 窗外到达（窗口已过期 / 未武装）只更新三格实时反馈，不放行——用户可「再听一次」重开窗口。
    static func passes(windowArmed: Bool, windowExpired: Bool, velocity: UInt8) -> Bool {
        windowArmed && !windowExpired && velocity > 0
    }
}

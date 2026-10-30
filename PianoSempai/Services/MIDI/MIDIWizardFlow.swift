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

/// S03 验证步判定（PRD：首次连接向导「弹两音验证信号」——2 秒监听窗内收到 ≥2 个不同音名的有效 Note On）。
/// 纯函数：View 只把监听窗状态与窗内去重后的音名集合喂进来，规则集中在此、可单测。
enum MIDIVerifyGate {
    /// 监听窗内收到 ≥2 个不同音名的有效 Note On → 通过（弹两音验证；同一音重复不算第二个）。
    /// 窗外到达（窗口已过期 / 未武装）只更新三格实时反馈，不放行——用户可「再听一次」重开窗口。
    static func passes(windowArmed: Bool, windowExpired: Bool, pitches: [UInt8]) -> Bool {
        windowArmed && !windowExpired && Set(pitches).count >= 2
    }
}

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

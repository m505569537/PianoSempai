import Foundation

// 设备标签映射（红线 2：模拟源永不冒充真机；S07c/S24/S11b 文案一致来源）。
//
// 2026-11-17 修正：此前真机分支把型号写死成「特伦斯 V70」——换一台电钢（Yamaha/Roland…）
// 也会显示 V70，属于编造。现改为：真机名一律取 CoreMIDI 上报的端点名，
// 拿不到就诚实说「电钢琴」，任何路径都不写死具体型号。模拟源仍恒为「模拟输入」。

enum MIDIDeviceLabel {

    enum State: Equatable {
        case realConnected
        case simulatedConnected
        case disconnected
    }

    /// 连接态 + 当前源模式 → 标签状态
    static func state(isConnected: Bool, mode: MIDIHub.Mode) -> State {
        guard isConnected else { return .disconnected }
        return mode == .simulated ? .simulatedConnected : .realConnected
    }

    /// 设置页设备行 / 连接语义标签
    /// - Parameter deviceName: CoreMIDI 上报的真实端点名（`MIDIHub.connectedDeviceName`）。
    static func label(for state: State, deviceName: String? = nil) -> String {
        switch state {
        case .realConnected: "\(realDeviceName(deviceName)) · 已连接"
        case .simulatedConnected: "模拟输入 · 已连接"
        case .disconnected: "未连接 · 去连接"
        }
    }

    /// S11b 重连遮罩卡等待文案（只对真机源点名，且点的是真名）
    static func waitingText(for state: State, deviceName: String? = nil) -> String {
        switch state {
        case .realConnected, .disconnected: "等待\(realDeviceName(deviceName)) 重新连接…"
        case .simulatedConnected: "等待模拟输入重新连接…"
        }
    }

    /// 真机名的诚实回落：空/全空白 → 通用「电钢琴」，绝不编造型号。
    static func realDeviceName(_ name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "电钢琴" : trimmed
    }
}

import Foundation

// 设备标签映射（红线 2：模拟源永不冒充真机 V70；S07c/S24/S11b 文案一致来源）。

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
    static func label(for state: State) -> String {
        switch state {
        case .realConnected: "特伦斯 V70 · 已连接"
        case .simulatedConnected: "模拟输入 · 已连接"
        case .disconnected: "未连接 · 去连接"
        }
    }

    /// S11b 重连遮罩卡等待文案（只对真机源点名 V70）
    static func waitingText(for state: State) -> String {
        switch state {
        case .realConnected, .disconnected: "等待特伦斯 V70 重新连接…"
        case .simulatedConnected: "等待模拟输入重新连接…"
        }
    }
}

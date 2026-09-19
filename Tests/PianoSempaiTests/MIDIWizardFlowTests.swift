import XCTest
@testable import PianoSempai

/// S03 连接步推进判定（idb 走查发现的死路 bug 的回归测试）。
final class MIDIWizardFlowTests: XCTestCase {

    func testSimulatedSelectedWithZeroDevicesAdvances() {
        // 模拟器无任何系统设备，用户点了「使用模拟输入」→ 必须可推进
        XCTAssertTrue(MIDIWizardFlow.canAdvanceFromConnect(
            systemDevices: [], selectedDevice: nil, mode: .simulated
        ))
    }

    func testRealDeviceSelectedAdvances() {
        XCTAssertTrue(MIDIWizardFlow.canAdvanceFromConnect(
            systemDevices: ["特伦斯 V70"], selectedDevice: "特伦斯 V70", mode: .real
        ))
    }

    func testNothingSelectedDoesNotAdvance() {
        // 无设备且未选模拟源 → 按钮禁用语义，推进拒绝
        XCTAssertFalse(MIDIWizardFlow.canAdvanceFromConnect(
            systemDevices: [], selectedDevice: nil, mode: .real
        ))
        // 有设备但没选定也不放行（选定动作才置 selectedDevice）
        XCTAssertFalse(MIDIWizardFlow.canAdvanceFromConnect(
            systemDevices: ["特伦斯 V70"], selectedDevice: nil, mode: .real
        ))
    }
}

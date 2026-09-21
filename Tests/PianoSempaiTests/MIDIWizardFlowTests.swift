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

    // MARK: BLE-MIDI 路径（2026-09-21 P0）

    /// BLE 连上后 iOS 才创建 CoreMIDI 源；S03 用系统暴露的源名回填 selectedDevice，
    /// 因此与 USB 路径共用同一判定即可放行。
    func testBLEConnectedDeviceAdvancesOnceSourceNameIsSelected() {
        // V70 广播名 "V70" → iOS 建出的 CoreMIDI 源名
        let sourceNames = ["V70"]
        XCTAssertTrue(MIDIWizardFlow.canAdvanceFromConnect(
            systemDevices: sourceNames, selectedDevice: "V70", mode: .real
        ))
    }

    /// 只扫到设备、还没连上（源名未出现、未选定）→ 不得放行。
    /// 这条锁死"BLE 已 discover ≠ 可推进"，与不乐观假连接的红线一致。
    func testBLEDiscoveredButNotConnectedDoesNotAdvance() {
        XCTAssertFalse(MIDIWizardFlow.canAdvanceFromConnect(
            systemDevices: [], selectedDevice: nil, mode: .real
        ))
    }

    /// 模拟源路径永不受 BLE 影响：即使扫到了真设备，选模拟源也照常放行，
    /// 但 UI 绝不给它贴 V70 的标签（由 MIDIDeviceLabel 保证）。
    func testSimulatedModeStillAdvancesWithBLEDevicePresent() {
        XCTAssertTrue(MIDIWizardFlow.canAdvanceFromConnect(
            systemDevices: ["V70"], selectedDevice: nil, mode: .simulated
        ))
    }
}

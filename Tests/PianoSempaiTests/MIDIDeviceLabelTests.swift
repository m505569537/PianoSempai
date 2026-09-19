import XCTest
@testable import PianoSempai

/// 红线 2：设备标签模式感知——模拟源永不显示为真机 V70。
final class MIDIDeviceLabelTests: XCTestCase {

    func testStateMapping() {
        XCTAssertEqual(MIDIDeviceLabel.state(isConnected: true, mode: .real), .realConnected)
        XCTAssertEqual(MIDIDeviceLabel.state(isConnected: true, mode: .simulated), .simulatedConnected)
        XCTAssertEqual(MIDIDeviceLabel.state(isConnected: false, mode: .real), .disconnected)
        XCTAssertEqual(MIDIDeviceLabel.state(isConnected: false, mode: .simulated), .disconnected)
    }

    func testLabelsForThreeStates() {
        XCTAssertEqual(
            MIDIDeviceLabel.label(for: .realConnected),
            "特伦斯 V70 · 已连接",
            "真机连接才点名 V70"
        )
        XCTAssertEqual(
            MIDIDeviceLabel.label(for: .simulatedConnected),
            "模拟输入 · 已连接",
            "模拟源必须如实标注，不得冒充 V70"
        )
        XCTAssertEqual(
            MIDIDeviceLabel.label(for: .disconnected),
            "未连接 · 去连接"
        )
    }

    func testWaitingTextNamesV70OnlyForRealSource() {
        // S11b：断连遮罩文案——模拟源断连时不得出现 V70 字样
        XCTAssertFalse(
            MIDIDeviceLabel.waitingText(for: .simulatedConnected).contains("V70"),
            "模拟源路径不得出现 V70"
        )
        XCTAssertTrue(MIDIDeviceLabel.waitingText(for: .realConnected).contains("特伦斯 V70"))
        XCTAssertFalse(MIDIDeviceLabel.waitingText(for: .simulatedConnected).isEmpty)
    }
}

import XCTest
@testable import PianoSempai

/// 红线 2：设备标签模式感知——模拟源永不冒充真机；
/// 真机名一律取 CoreMIDI 上报的端点名，**任何路径都不写死具体型号**（2026-11-17 修正）。
final class MIDIDeviceLabelTests: XCTestCase {

    func testStateMapping() {
        XCTAssertEqual(MIDIDeviceLabel.state(isConnected: true, mode: .real), .realConnected)
        XCTAssertEqual(MIDIDeviceLabel.state(isConnected: true, mode: .simulated), .simulatedConnected)
        XCTAssertEqual(MIDIDeviceLabel.state(isConnected: false, mode: .real), .disconnected)
        XCTAssertEqual(MIDIDeviceLabel.state(isConnected: false, mode: .simulated), .disconnected)
    }

    // MARK: 真机：显示真实端点名

    func testRealConnectedShowsReportedDeviceName() {
        XCTAssertEqual(
            MIDIDeviceLabel.label(for: .realConnected, deviceName: "Yamaha P-125"),
            "Yamaha P-125 · 已连接",
            "换任何一台电钢都应显示它自己的名字"
        )
        XCTAssertEqual(
            MIDIDeviceLabel.label(for: .realConnected, deviceName: "特伦斯 V70"),
            "特伦斯 V70 · 已连接",
            "真的接了 V70 才出现 V70——来自设备本身，不是写死"
        )
    }

    func testRealConnectedFallsBackToGenericWhenNameMissing() {
        XCTAssertEqual(MIDIDeviceLabel.label(for: .realConnected, deviceName: nil), "电钢琴 · 已连接")
        XCTAssertEqual(MIDIDeviceLabel.label(for: .realConnected, deviceName: "   "), "电钢琴 · 已连接",
                       "全空白按缺失处理")
    }

    // MARK: 模拟源：恒为「模拟输入」，绝不出现任何型号

    func testSimulatedNeverShowsModelName() {
        let label = MIDIDeviceLabel.label(for: .simulatedConnected, deviceName: "特伦斯 V70")
        XCTAssertEqual(label, "模拟输入 · 已连接",
                       "即便宿主传了真机名，模拟源也不得显示它（不冒充）")
        XCTAssertFalse(label.contains("V70"))
    }

    func testDisconnectedLabel() {
        XCTAssertEqual(MIDIDeviceLabel.label(for: .disconnected), "未连接 · 去连接")
        XCTAssertEqual(MIDIDeviceLabel.label(for: .disconnected, deviceName: "Yamaha P-125"), "未连接 · 去连接",
                       "未连接态不点名任何设备")
    }

    // MARK: 断连遮罩文案

    func testWaitingTextUsesRealNameForRealSource() {
        XCTAssertEqual(
            MIDIDeviceLabel.waitingText(for: .disconnected, deviceName: "Yamaha P-125"),
            "等待Yamaha P-125 重新连接…"
        )
        XCTAssertEqual(
            MIDIDeviceLabel.waitingText(for: .disconnected, deviceName: nil),
            "等待电钢琴 重新连接…",
            "拿不到设备名时诚实说「电钢琴」，不编造型号"
        )
    }

    func testWaitingTextForSimulatedNeverNamesAModel() {
        let text = MIDIDeviceLabel.waitingText(for: .simulatedConnected, deviceName: "特伦斯 V70")
        XCTAssertEqual(text, "等待模拟输入重新连接…")
        XCTAssertFalse(text.contains("V70"))
    }

    /// 回归护栏：所有标签路径都不得凭空产出「特伦斯 V70」。
    func testNoPathInventsTerranceV70WithoutDeviceReporting() {
        let samples: [String?] = [nil, "", "  ", "Yamaha P-125", "Roland FP-30X"]
        for name in samples {
            let outputs = [
                MIDIDeviceLabel.label(for: .realConnected, deviceName: name),
                MIDIDeviceLabel.label(for: .simulatedConnected, deviceName: name),
                MIDIDeviceLabel.label(for: .disconnected, deviceName: name),
                MIDIDeviceLabel.waitingText(for: .disconnected, deviceName: name),
                MIDIDeviceLabel.waitingText(for: .simulatedConnected, deviceName: name),
            ]
            for output in outputs {
                XCTAssertFalse(
                    output.contains("特伦斯"),
                    "设备未上报该型号时不得出现「特伦斯」：\(output)"
                )
            }
        }
    }
}

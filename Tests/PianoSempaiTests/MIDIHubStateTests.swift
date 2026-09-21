import XCTest
@testable import PianoSempai

/// 可注入的假源（不触碰真机 CoreMIDI；file-scope 避免 MainActor 隔离与协议冲突）
private final class FakeSource: MIDIEventSource {
    let name: String
    let reportsConnected: Bool
    let isSimulated = false
    var onEvent: ((MIDIEvent) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    init(name: String, reportsConnected: Bool) {
        self.name = name
        self.reportsConnected = reportsConnected
    }

    func start() throws {
        onConnectionChanged?(reportsConnected)
    }

    func stop() {
        onConnectionChanged?(false)
    }
}

/// 工厂状态盒（测试中动态更换 makeRealSource 的产出）
private final class SourceBox {
    var real: MIDIEventSource?
}

/// 真机 P0 修复（2026-09-20 idb 走查）：未连琴不得显示「模拟输入 · 已连接」假连接。
/// 连接态唯一事实来源 = 激活源回调；初始模式真机 .real / 模拟器 .simulated；
/// CoreMIDI 失败 fallback 不得借模拟源冒充 V70（红线 2）。
@MainActor
final class MIDIHubStateTests: XCTestCase {

    
    // MARK: ① 设备默认语义：无真机源 → disconnected、mode=.real

    func testDeviceDefaultWithNoSourceIsDisconnectedInRealMode() {
        let hub = MIDIHub(
            initialMode: .real,
            makeRealSource: { FakeSource(name: "empty", reportsConnected: false) },
            makeSimulatedSource: { FakeSource(name: "sim", reportsConnected: true) } // 即使模拟源"能连"，未被选择也无效
        )
        XCTAssertEqual(hub.mode, .real)
        XCTAssertFalse(hub.isConnected, "真机默认且无设备 = 未连接")
        XCTAssertEqual(
            MIDIDeviceLabel.state(isConnected: hub.isConnected, mode: hub.mode),
            .disconnected
        )
        XCTAssertFalse(hub.isConnected && hub.mode == .simulated, "启动不得进入模拟假连接")
    }

    func testInitialModeResolver() {
        XCTAssertEqual(MIDIHub.initialMode(isSimulatorEnvironment: false), .real, "真机（含 debug 真机）默认 .real")
        XCTAssertEqual(MIDIHub.initialMode(isSimulatorEnvironment: true), .simulated)
    }

    // MARK: ② 主动选择模拟源 → connected + simulatedConnected 标签

    func testUserChosenSimulatedConnectsAndLabelsHonestly() {
        let hub = MIDIHub(
            initialMode: .real,
            makeRealSource: { FakeSource(name: "empty", reportsConnected: false) },
            makeSimulatedSource: { FakeSource(name: "模拟输入", reportsConnected: true) }
        )
        XCTAssertFalse(hub.isConnected)

        hub.mode = .simulated // 用户在 S03 主动点「使用模拟输入」
        XCTAssertTrue(hub.isConnected, "用户主动选择模拟源后才允许 connected")
        XCTAssertEqual(hub.mode, .simulated)
        let labelState = MIDIDeviceLabel.state(isConnected: hub.isConnected, mode: hub.mode)
        XCTAssertEqual(labelState, .simulatedConnected)
        XCTAssertFalse(MIDIDeviceLabel.label(for: labelState).contains("V70"), "模拟源永不显示 V70")
    }

    // MARK: ③ CoreMIDI 失败 fallback：mode=.real、disconnected，绝不冒充 V70

    func testCoreMIDIFailureFallbackStaysDisconnectedInRealMode() {
        let hub = MIDIHub(
            initialMode: .real,
            makeRealSource: { nil }, // CoreMIDISource() 返回 nil 的等价场景
            makeSimulatedSource: { FakeSource(name: "sim", reportsConnected: true) }
        )
        XCTAssertEqual(hub.mode, .real)
        XCTAssertFalse(hub.isConnected, "fallback 占位源恒 disconnected")
        XCTAssertNil(hub.simulated, "fallback 不得挂模拟源（其 start 会报 true 冒充 V70）")
        XCTAssertEqual(
            MIDIDeviceLabel.state(isConnected: hub.isConnected, mode: hub.mode),
            .disconnected,
            "绝不 realConnected"
        )
    }

    // MARK: ④ 切源瞬间不残留上一源连接态

    func testSwitchingSourcesResetsStaleConnectedState() {
        let box = SourceBox()
        box.real = FakeSource(name: "V70", reportsConnected: true)
        let hub = MIDIHub(
            initialMode: .real,
            makeRealSource: { box.real },
            makeSimulatedSource: { FakeSource(name: "sim", reportsConnected: true) }
        )
        XCTAssertTrue(hub.isConnected, "前置：真机源已连接")

        // 切到无设备的真机源（设备拔出后重装源的场景）
        box.real = FakeSource(name: "empty", reportsConnected: false)
        hub.mode = .real // 同值赋值也触发重装
        XCTAssertFalse(hub.isConnected, "切源后由新源回调给真值：无设备 = 未连接")

        // 再切到有设备的源 → 恢复连接
        box.real = FakeSource(name: "V70", reportsConnected: true)
        hub.switchSource(.real)
        XCTAssertTrue(hub.isConnected)
    }

    func testRealConnectedLabelsV70() {
        let hub = MIDIHub(
            initialMode: .real,
            makeRealSource: { FakeSource(name: "特伦斯 V70", reportsConnected: true) },
            makeSimulatedSource: { FakeSource(name: "sim", reportsConnected: true) }
        )
        XCTAssertTrue(hub.isConnected)
        XCTAssertEqual(
            MIDIDeviceLabel.state(isConnected: hub.isConnected, mode: hub.mode),
            .realConnected
        )
    }

    // MARK: ⑤ BLE-MIDI P0：BLE 层连上 ≠ App 已连接

    /// 红线：外设在 BLE 层已连上、甚至名字就叫 V70，只要 iOS 还没创建 CoreMIDI 源
    /// （hub.isConnected 仍为 false），就绝不允许显示「特伦斯 V70 · 已连接」。
    func testBLEConnectedPeripheralDoesNotFakeRealConnection() {
        let hub = MIDIHub(
            initialMode: .real,
            makeRealSource: { FakeSource(name: "empty", reportsConnected: false) },
            makeSimulatedSource: { FakeSource(name: "sim", reportsConnected: true) }
        )
        let peripheral = BLEMIDIDevice(id: UUID(), name: "V70", rssi: -50, state: .connected)
        XCTAssertEqual(peripheral.name, "V70", "外设广播名照实展示")

        XCTAssertFalse(hub.isConnected, "连接态只能来自 CoreMIDI 源回调")
        let labelState = MIDIDeviceLabel.state(isConnected: hub.isConnected, mode: hub.mode)
        XCTAssertEqual(labelState, .disconnected)
        XCTAssertNotEqual(MIDIDeviceLabel.label(for: labelState), "特伦斯 V70 · 已连接")
    }
}

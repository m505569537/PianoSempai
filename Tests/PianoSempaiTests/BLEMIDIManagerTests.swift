import XCTest
@testable import PianoSempai

/// BLE-MIDI P0 修复的纯逻辑回归：列表去重/排序、外设状态机、
/// CoreMIDI 源验证判据、上次设备持久化。
/// CoreBluetooth 本身只能在真机验证（模拟器无 BLE 外设），这里只锁不依赖硬件的部分。
final class BLEMIDIManagerTests: XCTestCase {

    private let idA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let idB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    private let idC = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!

    // MARK: 列表去重 / 排序

    func testDiscoveryDedupesByIdKeepingLatestRSSI() {
        let first = BLEMIDIDevice(id: idA, name: "V70", rssi: -60, state: .discovered)
        let again = BLEMIDIDevice(id: idA, name: "V70", rssi: -42, state: .discovered)

        let merged = BLEMIDILogic.merged([first], with: again)

        XCTAssertEqual(merged.count, 1, "同一外设重复上报只能有一条")
        XCTAssertEqual(merged[0].rssi, -42, "RSSI 取最新")
        XCTAssertEqual(merged[0].name, "V70")
    }

    func testDiscoveryDoesNotDowngradeConnectingState() {
        let connecting = BLEMIDIDevice(id: idA, name: "V70", rssi: -60, state: .connecting)
        let rediscovered = BLEMIDIDevice(id: idA, name: nil, rssi: -55, state: .discovered)

        let merged = BLEMIDILogic.merged([connecting], with: rediscovered)

        XCTAssertEqual(merged[0].state, .connecting, "扫描重复命中不得打断正在进行的连接")
        XCTAssertEqual(merged[0].name, "V70", "原名已知时不得被空广播名覆盖")
    }

    func testSortingPutsConnectedFirstThenNameOrder() {
        let discoveredB = BLEMIDIDevice(id: idB, name: "B", rssi: -50, state: .discovered)
        let discoveredA = BLEMIDIDevice(id: idA, name: "A", rssi: -50, state: .discovered)
        let connected = BLEMIDIDevice(id: idC, name: "C", rssi: -90, state: .connected)

        let sorted = BLEMIDILogic.sortedForDisplay([discoveredB, discoveredA, connected])

        XCTAssertEqual(sorted.map(\.name), ["C", "A", "B"])
    }

    func testUnnamedDeviceGetsPlaceholderName() {
        let device = BLEMIDIDevice(id: idA, name: "   ", rssi: -60, state: .discovered)
        XCTAssertEqual(device.name, "未命名设备")
    }

    func testDiscoveryMarksAdvertisedMIDIServiceAsConfirmed() {
        // 广播带 MIDI 服务 UUID = 已确认；不带 = 候选（待用户点连接后 GATT 验证）
        let confirmed = BLEMIDIDevice(id: idA, name: "V70", rssi: -50, state: .discovered, advertisedMIDIService: true)
        let candidate = BLEMIDIDevice(id: idA, name: "V70", rssi: -50, state: .discovered)
        XCTAssertTrue(confirmed.advertisedMIDIService)
        XCTAssertFalse(candidate.advertisedMIDIService, "默认是候选")
    }

    func testMergeKeepsConfirmedFlagFromEitherSide() {
        let candidate = BLEMIDIDevice(id: idA, name: "V70", rssi: -60, state: .discovered)
        let confirmed = BLEMIDIDevice(id: idA, name: "V70", rssi: -55, state: .discovered, advertisedMIDIService: true)
        XCTAssertTrue(candidate.merged(with: confirmed).advertisedMIDIService, "任一带 UUID 即已确认")
        XCTAssertTrue(confirmed.merged(with: candidate).advertisedMIDIService, "已确认永不被降级成候选")
        XCTAssertFalse(candidate.merged(with: BLEMIDIDevice(id: idA, name: "V70", rssi: -55, state: .discovered)).advertisedMIDIService)
    }

    // MARK: 外设状态机

    func testStateMachineHappyPath() {
        var state = BLEMIDIDevice.State.discovered
        state = BLEMIDILogic.nextState(from: state, event: .connectStarted)
        XCTAssertEqual(state, .connecting)
        state = BLEMIDILogic.nextState(from: state, event: .connectSucceeded)
        XCTAssertEqual(state, .connected)
        state = BLEMIDILogic.nextState(from: state, event: .disconnected)
        XCTAssertEqual(state, .discovered, "断开回到可重连的发现态")
    }

    func testStateMachineFailureAndRetry() {
        var state = BLEMIDILogic.nextState(from: .discovered, event: .connectStarted)
        XCTAssertEqual(state, .connecting)
        state = BLEMIDILogic.nextState(from: state, event: .connectFailed)
        XCTAssertEqual(state, .failed)
        // 失败态可重试
        state = BLEMIDILogic.nextState(from: state, event: .connectStarted)
        XCTAssertEqual(state, .connecting)
    }

    func testStateMachineIgnoresNonsenseTransitions() {
        // 没连上就报断开：不得凭空变成 connected
        XCTAssertEqual(
            BLEMIDILogic.nextState(from: .discovered, event: .disconnected),
            .discovered
        )
        // 已连接再点连接：保持 connected，不得退回 connecting
        XCTAssertEqual(
            BLEMIDILogic.nextState(from: .connected, event: .connectStarted),
            .connected
        )
        // 连接中重复上报成功：保持（不会从未连接跳成 connected）
        XCTAssertEqual(
            BLEMIDILogic.nextState(from: .discovered, event: .connectSucceeded),
            .discovered
        )
    }

    // MARK: CoreMIDI 源验证判据

    func testCoreMIDISourceAppearanceRequiresIncrease() {
        XCTAssertTrue(BLEMIDILogic.midiSourceAppeared(before: 0, after: 1), "iOS 建源后数量必须变多")
        XCTAssertFalse(BLEMIDILogic.midiSourceAppeared(before: 1, after: 1), "数量没变不得算连上")
        XCTAssertFalse(BLEMIDILogic.midiSourceAppeared(before: 0, after: 0), "没有源就是没连上")
    }

    func testSourceConfirmedByCountIncrease() {
        // 本 App 连接触发 iOS 建源：数量变多即成立，不依赖名字
        XCTAssertTrue(BLEMIDILogic.midiSourceConfirmed(
            countIncreased: true, sourceNames: [], deviceName: "V70"
        ))
    }

    func testSourceConfirmedByNameMatchForAdoptedPeripheral() {
        // 接管路径：设备早已被 GarageBand 建链，源在连接前就存在、数量不会 +1，
        // 靠源名单与设备名互相匹配确认（口径同 S03 名字匹配）
        XCTAssertTrue(BLEMIDILogic.midiSourceConfirmed(
            countIncreased: false, sourceNames: ["特伦斯 V70"], deviceName: "V70"
        ))
        XCTAssertTrue(BLEMIDILogic.midiSourceConfirmed(
            countIncreased: false, sourceNames: ["V70"], deviceName: "特伦斯 V70"
        ))
        XCTAssertFalse(BLEMIDILogic.midiSourceConfirmed(
            countIncreased: false, sourceNames: ["Network Session 1"], deviceName: "V70"
        ), "名字对不上不得猜")
    }

    func testSourceNotConfirmedForUnnamedDevice() {
        // 空串会匹配任何源：未命名设备不得靠名字匹配蒙混过关
        XCTAssertFalse(BLEMIDILogic.midiSourceConfirmed(
            countIncreased: false, sourceNames: ["特伦斯 V70"], deviceName: BLEMIDIDevice.unnamed
        ))
        XCTAssertFalse(BLEMIDILogic.midiSourceConfirmed(
            countIncreased: false, sourceNames: ["特伦斯 V70"], deviceName: "   "
        ))
    }

    func testRejectingCandidateRemovesOnlyThatPeripheral() {
        let devices = [
            BLEMIDIDevice(id: idA, name: "V70", rssi: -50, state: .discovered),
            BLEMIDIDevice(id: idB, name: "AirPods", rssi: -40, state: .discovered)
        ]
        let remaining = BLEMIDILogic.rejectingCandidate(devices, id: idB)
        XCTAssertEqual(remaining.map(\.id), [idA], "GATT 验证未通过的候选被移除，其它候选保留")
    }

    // MARK: 上次连接设备持久化（UserDefaults，非 keychain）

    func testLastDeviceStoreRoundTrip() {
        let suiteName = "BLEMIDIManagerTests.roundtrip.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let store = LastDeviceStore(defaults: suite)

        XCTAssertNil(store.id, "初始无记录")
        XCTAssertNil(store.name)

        store.save(id: idA, name: "V70")
        XCTAssertEqual(store.id, idA)
        XCTAssertEqual(store.name, "V70")

        store.clear()
        XCTAssertNil(store.id, "断开后清除，避免立刻自动重连")
        XCTAssertNil(store.name)
    }

    func testLastDeviceStoreIgnoresCorruptValue() {
        let suite = UserDefaults(suiteName: "BLEMIDIManagerTests.corrupt")!
        defer { suite.removePersistentDomain(forName: "BLEMIDIManagerTests.corrupt") }
        suite.set("not-a-uuid", forKey: "ble-midi.last-device-id")
        let store = LastDeviceStore(defaults: suite)
        XCTAssertNil(store.id, "坏值不得崩溃，按无记录处理")
    }
}

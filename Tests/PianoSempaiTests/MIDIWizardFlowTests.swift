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

    // MARK: 验证步判定（2 秒监听窗；PRD：弹两音验证——两个不同音名）

    /// 监听窗内只收到 1 个音 → 不放行（旧单音规则已废弃）
    func testSinglePitchInsideWindowDoesNotPass() {
        XCTAssertFalse(MIDIVerifyGate.passes(windowArmed: true, windowExpired: false, pitches: [60]))
    }

    /// 监听窗内两个不同音名 → 通过（PRD「弹两音验证信号」）
    func testTwoDistinctPitchesInsideWindowPass() {
        XCTAssertTrue(MIDIVerifyGate.passes(windowArmed: true, windowExpired: false, pitches: [60, 64]))
    }

    /// 两个音到了但监听窗已过期 → 不放行（「再听一次」重开窗重算）
    func testTwoPitchesButWindowExpiredDoesNotPass() {
        XCTAssertFalse(MIDIVerifyGate.passes(windowArmed: true, windowExpired: true, pitches: [60, 64]))
    }

    /// 监听窗还没武装（未进入验证步）→ 不放行
    func testPitchesWithoutWindowDoNotPass() {
        XCTAssertFalse(MIDIVerifyGate.passes(windowArmed: false, windowExpired: false, pitches: [60, 64]))
    }

    /// 同一个音重复两遍 ≠ 两个音：音名必须互异（distinct，不是次数）
    func testDuplicateSamePitchTwiceDoesNotPass() {
        XCTAssertFalse(MIDIVerifyGate.passes(windowArmed: true, windowExpired: false, pitches: [60, 60]))
    }

    // MARK: 源选择（2026-11-19 测试者反馈"电钢琴连不上"的回归）

    /// 单一源：无论品牌都认（旧实现本来就对，锁住不被改坏）。
    func testSingleSourceIsPickedRegardlessOfBrand() {
        XCTAssertEqual(
            MIDIWizardFlow.preferredSource(["Yamaha P-125"], keeping: nil),
            "Yamaha P-125"
        )
    }

    /// 核心回归：**多源 + 非特伦斯品牌**。
    /// 旧实现给 nil → canAdvanceFromConnect 为 false → CTA 永久禁用 → 用户报"连不上"。
    func testMultipleSourcesWithoutTerenceStillPicksOne() {
        let sources = ["Yamaha P-125", "Network Session 1"]
        let picked = MIDIWizardFlow.preferredSource(sources, keeping: nil)
        XCTAssertNotNil(picked, "多源时不能返回 nil，否则用户被永久卡在连接步")
        XCTAssertEqual(picked, "Yamaha P-125", "无偏好时取第一个源")
        XCTAssertTrue(MIDIWizardFlow.canAdvanceFromConnect(
            systemDevices: sources, selectedDevice: picked, mode: .real
        ))
    }

    /// 多源里有特伦斯时优先它（锦上添花，不影响其它品牌）。
    func testTerencePreferenceAmongMultipleSources() {
        XCTAssertEqual(
            MIDIWizardFlow.preferredSource(["Yamaha P-125", "特伦斯 V70"], keeping: nil),
            "特伦斯 V70"
        )
    }

    /// 用户手动选过的源要保留，不被自动启发式覆盖。
    func testManualSelectionIsKept() {
        let sources = ["Yamaha P-125", "Roland FP-30X"]
        XCTAssertEqual(
            MIDIWizardFlow.preferredSource(sources, keeping: "Roland FP-30X"),
            "Roland FP-30X"
        )
    }

    /// 手动选的设备拔掉后，回退到仍可用的源而不是 nil。
    func testStaleSelectionFallsBackInsteadOfNil() {
        XCTAssertEqual(
            MIDIWizardFlow.preferredSource(["Yamaha P-125"], keeping: "已拔掉的琴"),
            "Yamaha P-125"
        )
    }

    /// 没有任何源时才返回 nil。
    func testNoSourcesReturnsNil() {
        XCTAssertNil(MIDIWizardFlow.preferredSource([], keeping: "旧设备"))
    }

}

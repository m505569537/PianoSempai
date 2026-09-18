import XCTest
@testable import PianoSempai

/// brief M1 验收：BLE 丢 noteOff 双保险（velocity=0 转换 + 800ms 超时截断）单测。
final class HeldNoteTrackerTests: XCTestCase {
    private let t0: UInt64 = 1_000_000_000

    private func noteOn(_ note: UInt8, vel: UInt8 = 90, at offset: UInt64 = 0, channel: UInt8 = 0) -> MIDIEvent {
        MIDIEvent(kind: .noteOn(note: note, velocity: vel), channel: channel, timeNanos: t0 + offset)
    }

    private func noteOff(_ note: UInt8, vel: UInt8 = 0, at offset: UInt64, channel: UInt8 = 0) -> MIDIEvent {
        MIDIEvent(kind: .noteOff(note: note, velocity: vel), channel: channel, timeNanos: t0 + offset)
    }

    func testNormalOnOffPassesThrough() {
        let tracker = HeldNoteTracker()
        let on = tracker.process(noteOn(60))
        XCTAssertEqual(on.count, 1)
        XCTAssertEqual(on[0].kind, .noteOn(note: 60, velocity: 90))
        XCTAssertFalse(on[0].isSuspicious)

        let off = tracker.process(noteOff(60, at: 300_000_000))
        XCTAssertEqual(off.count, 1)
        XCTAssertEqual(off[0].kind, .noteOff(note: 60, velocity: 0))
        XCTAssertFalse(off[0].isSuspicious)
        XCTAssertEqual(tracker.heldNoteCount, 0)
    }

    func testVelocityZeroNoteOnBecomesNoteOff() {
        let tracker = HeldNoteTracker()
        _ = tracker.process(noteOn(64))
        // BLE 丢包形态：noteOn velocity=0 到达，必须按 noteOff 处理
        let out = tracker.process(noteOn(64, vel: 0, at: 100_000_000))
        XCTAssertEqual(out.count, 1)
        guard case let .noteOff(note, velocity) = out[0].kind else {
            return XCTFail("velocity=0 noteOn 应转为 noteOff")
        }
        XCTAssertEqual(note, 64)
        XCTAssertEqual(velocity, 0)
        XCTAssertEqual(tracker.heldNoteCount, 0)
    }

    func testTimeoutTruncatesAtExactly800msMarkedSuspicious() {
        let tracker = HeldNoteTracker()
        _ = tracker.process(noteOn(60, at: 0))
        // 799ms：不应截断
        XCTAssertTrue(tracker.truncateExpired(now: t0 + 799_000_000).isEmpty)
        XCTAssertEqual(tracker.heldNoteCount, 1)
        // 801ms：在 start+800ms 处补发可疑 noteOff
        let truncated = tracker.truncateExpired(now: t0 + 801_000_000)
        XCTAssertEqual(truncated.count, 1)
        let event = truncated[0]
        XCTAssertEqual(event.timeNanos, t0 + HeldNoteTracker.defaultTimeoutNanos, "截断点应严格在 start+800ms")
        guard case let .noteOff(note, velocity) = event.kind else {
            return XCTFail("截断应产出 noteOff")
        }
        XCTAssertEqual(note, 60)
        XCTAssertEqual(velocity, 0)
        XCTAssertTrue(event.isSuspicious, "截断事件必须标记可疑，禁止静默修正")
        XCTAssertEqual(tracker.heldNoteCount, 0)
    }

    func testReleasedBeforeTimeoutNotTruncated() {
        let tracker = HeldNoteTracker()
        _ = tracker.process(noteOn(62, at: 0))
        _ = tracker.process(noteOff(62, at: 200_000_000))
        XCTAssertTrue(tracker.truncateExpired(now: t0 + 2_000_000_000).isEmpty)
        XCTAssertEqual(tracker.heldNoteCount, 0)
    }

    func testRepeatedNoteOnTruncatesPreviousInstance() {
        let tracker = HeldNoteTracker()
        _ = tracker.process(noteOn(67, at: 0))
        // 同音重复 noteOn（BLE 丢了前一个 noteOff）→ 先补发可疑 noteOff 再放行新 noteOn
        let out = tracker.process(noteOn(67, vel: 100, at: 150_000_000))
        XCTAssertEqual(out.count, 2)
        guard case .noteOff = out[0].kind else { return XCTFail("第一条应为补发 noteOff") }
        XCTAssertTrue(out[0].isSuspicious)
        XCTAssertEqual(out[0].timeNanos, t0 + 150_000_000)
        guard case let .noteOn(note, velocity) = out[1].kind else { return XCTFail("第二条应为新 noteOn") }
        XCTAssertEqual(note, 67)
        XCTAssertEqual(velocity, 100)
    }

    func testMultipleHeldNotesTruncateIndependently() {
        let tracker = HeldNoteTracker()
        _ = tracker.process(noteOn(60, at: 0))
        _ = tracker.process(noteOn(64, at: 500_000_000))
        // 1.2s：60 已超时，64 还没到 800ms
        let first = tracker.truncateExpired(now: t0 + 1_200_000_000)
        XCTAssertEqual(first.map(\.note), [60])
        // 1.4s：64 也超时
        let second = tracker.truncateExpired(now: t0 + 1_400_000_000)
        XCTAssertEqual(second.map(\.note), [64])
        XCTAssertEqual(tracker.heldNoteCount, 0)
    }

    func testSustainPedalPassesThroughUntracked() {
        let tracker = HeldNoteTracker()
        let cc = MIDIEvent(kind: .sustainPedal(value: 127), channel: 0, timeNanos: t0)
        let out = tracker.process(cc)
        XCTAssertEqual(out, [cc])
        XCTAssertEqual(tracker.heldNoteCount, 0)
        XCTAssertTrue(tracker.truncateExpired(now: t0 + 5_000_000_000).isEmpty)
    }
}

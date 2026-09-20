import XCTest
@testable import PianoSempai

/// MIDI 1.0 running status：CoreMIDI 交的是原始 cable 字节，不展开 running status；
/// BLE-MIDI（特伦斯 V70 链路）多消息共用同一时间戳时会大量省略 status 字节。
/// 这里锁死「带 running status 的字节流必须全部解析出来」的行为。
final class CoreMIDISourceParseTests: XCTestCase {
    private let timebase = mach_timebase_info_data_t(numer: 1, denom: 1)

    // 1. 同一 status 字节 0x90 后连续三条 noteOn：只有第一条带 status，后两条省略
    func testRunningStatusChainOfNoteOn() {
        let data: [UInt8] = [0x90, 60, 88, 62, 90, 64, 80]
        let events = CoreMIDISource.parse(data: data, timeStamp: 1_000_000, timebase: timebase)

        XCTAssertEqual(events.count, 3, "running status 下被省略 status 的音必须全部解析出来")
        XCTAssertEqual(events.map(\.kind), [
            .noteOn(note: 60, velocity: 88),
            .noteOn(note: 62, velocity: 90),
            .noteOn(note: 64, velocity: 80),
        ])
        XCTAssertTrue(events.allSatisfy { $0.channel == 0 }, "running status 沿用同一声道的 status")
        XCTAssertTrue(events.allSatisfy { $0.timeNanos == 1_000_000 }, "同一包内事件共用包时间戳")
    }

    // 2. running status 与不同类型 status 混排：0x80 出现后，最后一条 noteOff 65 复用 0x80
    func testRunningStatusSwitchesToNoteOff() {
        let data: [UInt8] = [0x90, 60, 88, 62, 90, 0x80, 64, 40, 65, 40]
        let events = CoreMIDISource.parse(data: data, timeStamp: 2_000_000, timebase: timebase)

        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.map(\.kind), [
            .noteOn(note: 60, velocity: 88),
            .noteOn(note: 62, velocity: 90),
            .noteOff(note: 64, velocity: 40),
            .noteOff(note: 65, velocity: 40),
        ])
        XCTAssertTrue(events.allSatisfy { $0.channel == 0 })
    }

    // 3. CC64 running status：0xB0 64 127 后省略 status 的 64 0 → 松踏板
    func testRunningStatusSustainPedal() {
        let data: [UInt8] = [0xB0, 64, 127, 64, 0]
        let events = CoreMIDISource.parse(data: data, timeStamp: 3_000_000, timebase: timebase)

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.kind), [.sustainPedal(value: 127), .sustainPedal(value: 0)])
    }

    // 4. 包尾截断的 running status 载荷：只出完整的那条，不崩溃、不产出垃圾事件
    func testTruncatedRunningStatusPayloadAtBufferEnd() {
        let data: [UInt8] = [0x90, 60, 88, 62]
        let events = CoreMIDISource.parse(data: data, timeStamp: 4_000_000, timebase: timebase)

        XCTAssertEqual(events.count, 1, "数据字节不够拼第二条时应丢弃，不得臆造")
        XCTAssertEqual(events.first?.kind, .noteOn(note: 60, velocity: 88))
    }

    // 5. 开头就是数据字节、没有任何 status：不能凭空发明 status，必须 0 事件
    func testLeadingDataBytesWithoutPriorStatus() {
        let data: [UInt8] = [60, 88]
        let events = CoreMIDISource.parse(data: data, timeStamp: 5_000_000, timebase: timebase)

        XCTAssertEqual(events.count, 0)
    }
}

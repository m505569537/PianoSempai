import XCTest
@testable import PianoSempai

/// M1 Spike B 验收：模拟源产出与真机同构的结构化事件流，并过双保险管线。
final class SimulatedSourcePipelineTests: XCTestCase {
    func testAutoReplayEmitsStructuredNoteOnOffPairs() throws {
        let source = SimulatedMIDIEventSource()
        try source.start()

        var events: [MIDIEvent] = []
        let done = expectation(description: "收到自动回放事件")
        source.onEvent = { event in
            events.append(event)
            // 4 个音 × noteOn/noteOff = 8
            if events.count == 8 { done.fulfill() }
        }

        source.autoReplayScale(count: 4, noteInterval: 0.5)
        wait(for: [done], timeout: 10)

        XCTAssertEqual(events.count, 8)
        // 成对出现：noteOn 后紧跟 noteOff，同一音高
        for pair in stride(from: 0, to: 8, by: 2) {
            guard case let .noteOn(noteOn, onVel) = events[pair].kind else {
                return XCTFail("第 \(pair) 条应为 noteOn")
            }
            guard case let .noteOff(noteOff, offVel) = events[pair + 1].kind else {
                return XCTFail("第 \(pair + 1) 条应为 noteOff")
            }
            XCTAssertEqual(noteOn, noteOff)
            XCTAssertGreaterThan(onVel, 0)
            XCTAssertEqual(offVel, 0)
            XCTAssertFalse(events[pair].isSuspicious)
        }
        // 时间戳单调不减（mach uptime 域）
        let times = events.map(\.timeNanos)
        XCTAssertEqual(times, times.sorted(), "事件时间应单调")
    }

    func testRealCoreMIDIParseLayer() {
        // 0x90 60 vel 88 ch0；0x90 62 vel 0（丢 noteOff 形态）；0xB0 64 127（CC64）
        let timebase = mach_timebase_info_data_t(numer: 1, denom: 1)
        let data: [UInt8] = [0x90, 60, 88, 0x90, 62, 0, 0xB0, 64, 127]
        let events = CoreMIDISource.parse(data: data, timeStamp: 1_000_000, timebase: timebase)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].kind, .noteOn(note: 60, velocity: 88))
        XCTAssertEqual(events[1].kind, .noteOff(note: 62, velocity: 0), "velocity=0 noteOn 应解析为 noteOff")
        XCTAssertEqual(events[2].kind, .sustainPedal(value: 127))
    }
}

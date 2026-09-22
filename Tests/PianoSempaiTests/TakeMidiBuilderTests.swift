import XCTest
@testable import PianoSempai
import SheetMusicMIDI

/// TakeMidiBuilder 的纯转换测试（不依赖音频宿主）。锁定：
/// 真实墙钟时序映射、tick 排序（同 tick noteOff 先于 noteOn）、velocity clamp、空/零时长安全。
final class TakeMidiBuilderTests: XCTestCase {

    private func note(_ pitch: UInt8, _ onset: Double, _ end: Double, _ vel: UInt8 = 90) -> PlayedNote {
        PlayedNote(pitch: pitch, onsetSec: onset, endSec: end, velocity: vel, isSuspicious: false)
    }

    private func events(_ file: MidiFile) -> [(tick: Int, event: MidiEvent)] {
        file.tracks.flatMap { track in
            track.events.map { ($0.tick, $0.event) }
        }
    }

    private func tempo(_ file: MidiFile) -> Int? {
        for (_, event) in events(file) {
            if case let .meta(.tempo(microsecondsPerQuarter: t)) = event { return t }
        }
        return nil
    }

    func testEmptyTakeProducesValidSilentFile() {
        let file = TakeMidiBuilder.build(notes: [])
        XCTAssertEqual(file.division, 480)
        XCTAssertEqual(file.format, 0)
        XCTAssertEqual(file.tracks.count, 1)
        XCTAssertFalse(events(file).contains { if case .noteOn = $0.event { return true }; return false },
                       "空 take 不应有任何 noteOn")
    }

    func testSingleNoteTimingAndTempo() {
        // span = 1s，对齐 1 拍 → tempo = 1_000_000 µs/四分音符（=60 BPM），totalTicks=480
        let file = TakeMidiBuilder.build(notes: [note(60, 0, 1)])

        XCTAssertEqual(tempo(file), 1_000_000)

        let ons = events(file).filter { if case .noteOn = $0.event { return true }; return false }
        let offs = events(file).filter { if case .noteOff = $0.event { return true }; return false }
        XCTAssertEqual(ons.count, 1)
        XCTAssertEqual(ons.first?.tick, 0)
        if case let .noteOn(channel, pitch, velocity) = ons.first?.event {
            XCTAssertEqual(channel, 0)
            XCTAssertEqual(pitch, 60)
            XCTAssertEqual(velocity, 90)
        } else { XCTFail("应是 noteOn") }

        XCTAssertEqual(offs.first?.tick, 480, "1 秒 = 480 tick")
    }

    func testVelocityZeroClampedToOne() {
        // 线上 velocity-0 noteOn 等价 noteOff；builder 必须把它钳到 >=1 才会发音
        let file = TakeMidiBuilder.build(notes: [note(60, 0, 1, 0)])
        let ons = events(file).filter { if case .noteOn = $0.event { return true }; return false }
        if case let .noteOn(_, _, velocity) = ons.first?.event {
            XCTAssertEqual(velocity, 1)
        } else { XCTFail("应是 noteOn") }
    }

    func testVelocity127NotClampedDown() {
        let file = TakeMidiBuilder.build(notes: [note(60, 0, 1, 127)])
        let ons = events(file).filter { if case .noteOn = $0.event { return true }; return false }
        if case let .noteOn(_, _, velocity) = ons.first?.event {
            XCTAssertEqual(velocity, 127)
        } else { XCTFail("应是 noteOn") }
    }

    func testRelativeTimingPreserved() {
        // 两音 onset 间隔 0.5s。span=1（末音 end=1）→ totalTicks=480，第二音应在 tick 240
        let file = TakeMidiBuilder.build(notes: [
            note(60, 0, 0.6),
            note(62, 0.5, 1.0),
        ])
        var onTickByPitch: [Int: Int] = [:]
        for (tick, event) in events(file) {
            if case let .noteOn(_, pitch, _) = event { onTickByPitch[pitch] = tick }
        }
        XCTAssertEqual(onTickByPitch[60], 0)
        XCTAssertEqual(onTickByPitch[62], 240, "0.5s 的 onset 差必须保留，不得被量化到拍点")
    }

    func testNoteOffOrderedBeforeNoteOnAtSameTick() {
        // A 在 1s 结束（off→tick480），B 在 1s 开始（on→tick480）。
        // 同 tick 上 noteOff 必须排在 noteOn 前，否则同音 articulation 会吃掉一个音。
        let file = TakeMidiBuilder.build(notes: [
            note(60, 0, 1),
            note(60, 1, 2),
        ])
        let at480 = events(file).filter { $0.tick == 480 }.map { $0.event }
        guard let first = at480.first, let last = at480.last else {
            return XCTFail("tick 480 应有事件")
        }
        if case .noteOff = first { } else { XCTFail("tick 480 首个事件应是 noteOff，实际 \(first)") }
        if case .noteOn = last { } else { XCTFail("tick 480 末个事件应是 noteOn，实际 \(last)") }
    }

    func testAllTicksNonDecreasing() {
        let file = TakeMidiBuilder.build(notes: [
            note(60, 0, 1), note(62, 0.5, 1.5), note(64, 1, 2),
        ])
        let ticks = events(file).map { $0.tick }
        XCTAssertEqual(ticks, ticks.sorted(), "事件必须按 tick 升序（MidiWriter precondition）")
    }

    func testZeroSpanUsesFallbackTempoAndDoesNotDivideByZero() {
        // onset == end → span 0：走兜底 tempo，音落 tick 0，off 至少 +1 tick
        let file = TakeMidiBuilder.build(notes: [note(60, 0, 0)])
        XCTAssertEqual(tempo(file), 500_000, "零时长用 120BPM 兜底 tempo")
        let ons = events(file).filter { if case .noteOn = $0.event { return true }; return false }
        let offs = events(file).filter { if case .noteOff = $0.event { return true }; return false }
        XCTAssertEqual(ons.first?.tick, 0)
        XCTAssertEqual(offs.first?.tick, 1, "零时值音也给至少 1 tick 以便发音")
    }

    func testProgramChangePianoAtTickZero() {
        let file = TakeMidiBuilder.build(notes: [note(60, 0, 1)])
        let pc = events(file).first { if case .programChange = $0.event { return true }; return false }
        XCTAssertEqual(pc?.tick, 0)
        if case let .programChange(channel, program) = pc?.event {
            XCTAssertEqual(channel, 0)
            XCTAssertEqual(program, 0, "GM program 0 = Acoustic Grand Piano")
        } else { XCTFail("应有 programChange") }
    }
}

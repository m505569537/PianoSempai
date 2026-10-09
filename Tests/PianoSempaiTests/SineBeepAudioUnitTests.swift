import AVFoundation
import XCTest
@testable import PianoSempai
import SheetMusicCore
import SheetMusicMIDI

/// SineBeepAudioUnit（Stage A 核心）的验证：
/// 1. 纯映射/包络数学——无音频、任何宿主确定性通过；
/// 2. 直接触发路径——triggerNote 经 scheduleMIDIEventBlock 进同一合成路径，混音器出信号；
/// 3. Sequencer 驱动路径——SMF ch9 note 经 destinationAudioUnit 驱动单元并出信号，
///    同时 sequencer 时钟前进——这是 Stage B（示范 click track 换音色）的路由前提。
///
/// 音频测试在无头 CI（输出格式 sampleRate <= 0）时按既有模式 XCTSkip，不失败。
/// 本单元纯合成，不依赖任何音源文件。
final class SineBeepAudioUnitTests: XCTestCase {

    // MARK: - 纯数学（无音频）

    func testNoteToSpecMappingMatchesOriginalSineBuffer() {
        // note 76 = 重拍档：1500Hz / 35ms
        let accent = SineBeepAudioUnit.spec(forNote: 76)
        XCTAssertEqual(accent.frequency, 1500, accuracy: 1e-9, "重拍必须是 1500Hz（原重拍蜂鸣）")
        XCTAssertEqual(accent.duration, 0.035, accuracy: 1e-12, "重拍时长必须是 35ms")
        // 其余所有 note（含 77）= 常拍档：1000Hz / 30ms
        for note: UInt8 in [0, 1, 60, 77, 78, 127] {
            let spec = SineBeepAudioUnit.spec(forNote: note)
            XCTAssertEqual(spec.frequency, 1000, accuracy: 1e-9, "note \(note) 必须是常拍 1000Hz")
            XCTAssertEqual(spec.duration, 0.030, accuracy: 1e-12, "note \(note) 必须是常拍 30ms")
        }
    }

    func testVelocityScalesEnvelopeAmplitude() {
        XCTAssertEqual(SineBeepAudioUnit.velocityScale(forVelocity: 100), 1.0, accuracy: 1e-12,
                       "76/100 → 满幅（1.0×）")
        XCTAssertEqual(SineBeepAudioUnit.velocityScale(forVelocity: 80), 0.8, accuracy: 1e-12,
                       "77/80 → 0.8×（与原 sineBuffer 的 0.5 峰值×0.8 对应）")
        XCTAssertEqual(SineBeepAudioUnit.velocityScale(forVelocity: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(SineBeepAudioUnit.velocityScale(forVelocity: 127), 1.0, accuracy: 1e-12,
                       "速度超过 100 封顶 1.0×")
    }

    // MARK: - 信号级（需要音频输出；无头 CI 跳过）

    /// 共用骨架：建引擎、挂/连 SineBeep、装 mainMixer tap、启动引擎。
    /// 返回（引擎，读峰值 RMS 的闭包）；引擎必须外泄给测试 2 的 sequencer 绑定。
    @MainActor
    private func makeTappedEngine(unit: AVAudioUnit) throws -> (engine: AVAudioEngine, readPeak: () -> Float) {
        let engine = AVAudioEngine()
        engine.attach(unit)
        let format = engine.outputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw XCTSkip("宿主无音频输出（无头 CI）——跳过而非失败")
        }
        engine.connect(unit, to: engine.mainMixerNode, format: format)

        let lock = NSLock()
        var peakRMS: Float = 0
        // format 传 nil：按节点自身输出格式送 tap，避免 format 不匹配的运行时异常。
        // bufferSize 256（≈5.8ms @44.1k）远小于 30ms 的蜂鸣，才能整块抓到单拍。
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 256, format: nil) { buffer, _ in
            guard let data = buffer.floatChannelData?[0] else { return }
            var sum: Float = 0
            for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
            let rms = sqrt(sum / Float(max(1, buffer.frameLength)))
            lock.lock(); peakRMS = max(peakRMS, rms); lock.unlock()
        }
        engine.prepare()
        try engine.start()
        return (engine, { lock.lock(); defer { lock.unlock() }; return peakRMS })
    }

    /// 直接触发：triggerNote(76, vel 100) 与 triggerNote(77, vel 80) 相隔 ~0.4s，
    /// 混音器上必须采到非零 RMS——直接触发路径（Stage B 练习节拍器的用法）是活的。
    @MainActor
    func testDirectTriggerProducesNonZeroRMSAtMainMixer() async throws {
        let unit = try await SineBeepAudioUnitFactory.make()
        let (engine, readPeak) = try makeTappedEngine(unit: unit)

        unit.triggerNote(76, velocity: 100)
        try await Task.sleep(nanoseconds: 400_000_000)
        unit.triggerNote(77, velocity: 80)
        try await Task.sleep(nanoseconds: 400_000_000)

        engine.stop()
        engine.mainMixerNode.removeTap(onBus: 0)
        XCTAssertGreaterThan(readPeak(), 1e-3,
                             "直接触发必须在混音器上产生非零 RMS——否则 triggerNote 管线是死的")
    }

    /// Sequencer 驱动：4 拍小节（76 + 三个 77，ch9，120 BPM）写入临时 SMF、load 进
    /// 绑定同一引擎的 AVAudioSequencer、track.destinationAudioUnit = 单元，开播后混音器
    /// 出非零 RMS 且 sequencer 时钟前进——Stage B（示范 ch9 click track 驱动本单元）的路由前提。
    @MainActor
    func testSequencerDrivesUnitAndClockAdvances() async throws {
        let unit = try await SineBeepAudioUnitFactory.make()
        let (engine, readPeak) = try makeTappedEngine(unit: unit)

        // 4 拍小节：division 480、120 BPM（四分音符 = 0.5s = 480 tick）；note-off 在
        // 0.125 拍后（≈示范 click track 的 note-off 落点）。
        var events: [TimedMidiEvent] = [
            TimedMidiEvent(tick: 0, event: .meta(.tempo(microsecondsPerQuarter: 500_000))),
        ]
        events.append(TimedMidiEvent(tick: 0, event: .noteOn(channel: 9, pitch: 76, velocity: 100)))
        events.append(TimedMidiEvent(tick: 240, event: .noteOff(channel: 9, pitch: 76, velocity: 0)))
        for beat in 1...3 {
            let onset = beat * 480
            events.append(TimedMidiEvent(tick: onset, event: .noteOn(channel: 9, pitch: 77, velocity: 80)))
            events.append(TimedMidiEvent(tick: onset + 240, event: .noteOff(channel: 9, pitch: 77, velocity: 0)))
        }
        events.append(TimedMidiEvent(tick: 1920, event: .endOfTrack))
        let midi = MidiFile(division: 480, format: 1, tracks: [MidiTrack(events: events)])

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sinebeep-\(UUID().uuidString).mid")
        try MidiWriter.write(midi).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        // sequencer 必须绑定 attach 了 unit 的**同一**引擎——destinationAudioUnit 的
        // 事件派发以引擎的 render 管线为前提。
        let sequencer = AVAudioSequencer(audioEngine: engine)
        try sequencer.load(from: url, options: [])
        XCTAssertEqual(sequencer.tracks.count, 1, "测试 SMF 应为单 track")
        sequencer.tracks[0].destinationAudioUnit = unit

        try sequencer.start()
        // 时钟前进断言：0.5s 后必须已越过第 0 tick（播放真的在走）。
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertGreaterThan(sequencer.currentPositionInSeconds, 0,
                             "sequencer 时钟必须前进——停在 0 说明传输没跑起来")
        // 让整条 2s 小节播完（4 拍 × 0.5s），tap 横跨全程。
        try await Task.sleep(nanoseconds: 2_000_000_000)

        sequencer.stop()
        engine.stop()
        engine.mainMixerNode.removeTap(onBus: 0)
        XCTAssertGreaterThan(readPeak(), 1e-3,
                             "sequencer 驱动必须在混音器上产生非零 RMS——否则 destinationAudioUnit 路由是死的")
    }
}

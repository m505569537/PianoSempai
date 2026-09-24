import AVFoundation
import XCTest
@testable import PianoSempai
import SheetMusicAudioCore
import SheetMusicCore
import SheetMusicMIDI

/// SamplerSynthBackend 的契约测试。
///
/// 边界：这里**不验证真出声**（测试宿主不保证有音频输出，且「听见了」无法在进程内断言）。
/// 真出声由主会话模拟器 + 用户真机听验。这里只锁两件事：
/// 1. 不崩——所有协议入口在「无音源 / 未启动引擎 / 未加载序列」下都是安全 no-op；
/// 2. 契约——同步后端（isReady 恒 true）、节拍器静音真的落在 mixer outputVolume 上、
///    未播放时位置/tick/终点位都是确定的初值。
@MainActor
final class SamplerSynthBackendTests: XCTestCase {

    /// 一个自建引擎：只创建不 start（不给硬件，纯节点图操作）。
    private func makeAttachedBackend() -> SamplerSynthBackend {
        let backend = SamplerSynthBackend()
        let engine = AVAudioEngine()
        backend.attach(to: engine)
        return backend
    }

    /// 一音的最小合法 SMF（走 TakeMidiBuilder，与 TakePlaybackService 同一构造路径）。
    private func makeMidi() -> SheetMusicMIDI.MidiFile {
        TakeMidiBuilder.build(notes: [
            PlayedNote(pitch: 60, onsetSec: 0, endSec: 1, velocity: 90, isSuspicious: false),
        ])
    }

    // MARK: - 构造 / 音频图

    func testInitAndOutputNodeAreUsable() {
        let backend = SamplerSynthBackend()
        XCTAssertNotNil(backend.outputNode, "outputNode 必须存在（宿主引擎要连它）")
    }

    func testAttachConnectsWholeGraph() {
        let backend = SamplerSynthBackend()
        let engine = AVAudioEngine()
        backend.attach(to: engine)

        // attach 后 outputNode（combiner）必须已挂到引擎上——宿主据此判断要不要 attach。
        XCTAssertTrue(backend.outputNode.engine === engine)
        // 两条传输都随 engine 创建
        XCTAssertFalse(backend.isAtEnd, "未加载序列时不能读成「已播完」")
    }

    // MARK: - 音源准备

    func testPrepareWithMissingSoundfontIsSafeNoOp() {
        let backend = makeAttachedBackend()
        // 不存在的 URL：loadSoundBankInstrument 失败被 try? 吞掉，不崩、渲染静音。
        backend.prepare(
            soundfontURL: URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).sf2"),
            metronomeSoundfontURL: nil,
            drumChannels: [],
        )
        XCTAssertTrue(backend.isReady, "同步后端：prepare 之后恒 ready")
    }

    func testPrepareWithNilSoundfontIsSafeNoOp() {
        let backend = makeAttachedBackend()
        backend.prepare(soundfontURL: nil, metronomeSoundfontURL: nil, drumChannels: [9])
        XCTAssertTrue(backend.isReady)
    }

    // MARK: - 序列加载 / 初始位

    func testLoadSequenceLeavesTransportAtStart() {
        let backend = makeAttachedBackend()
        let midi = makeMidi()

        backend.loadSequence(
            midi, timeline: PlaybackTimeline(score: Score(division: midi.division)),
        )

        XCTAssertFalse(backend.isAtEnd, "加载后未播放：不能是终点")
        XCTAssertEqual(backend.currentTick, 0)
        XCTAssertEqual(backend.currentPositionSeconds, 0)
    }

    func testLoadMetronomeSequenceIsSafe() {
        let backend = makeAttachedBackend()
        let midi = makeMidi()
        backend.loadSequence(midi, timeline: PlaybackTimeline(score: Score(division: midi.division)))
        backend.loadMetronomeSequence(midi, offsetSeconds: 0)
        backend.loadMetronomeSequence(midi, offsetSeconds: 2)
        // 只锁不崩 + 乐谱位置不受节拍器加载影响
        XCTAssertEqual(backend.currentPositionSeconds, 0)
    }

    // MARK: - 节拍器静音 / 音量（权威观测点 = mixer outputVolume）

    func testMetronomeMuteControlsMixerOutputVolume() {
        let backend = makeAttachedBackend()
        backend.setMetronomeVolume(0.5)
        XCTAssertEqual(backend.metronomeOutputVolumeForTests, 0.5, accuracy: 1e-6)

        backend.setMetronomeMuted(true)
        XCTAssertEqual(backend.metronomeOutputVolumeForTests, 0, accuracy: 1e-6,
                       "mute 必须真的落在 mixer 上，否则播放会响 click")

        backend.setMetronomeMuted(false)
        XCTAssertEqual(backend.metronomeOutputVolumeForTests, 0.5, accuracy: 1e-6,
                       "取消静音要恢复到静音前的音量，不是回 1.0")
    }

    func testMetronomeVolumeWhileMutedStaysSilent() {
        let backend = makeAttachedBackend()
        backend.setMetronomeMuted(true)
        backend.setMetronomeVolume(0.8)
        XCTAssertEqual(backend.metronomeOutputVolumeForTests, 0, accuracy: 1e-6,
                       "静音中调音量不能把声音放出来")
    }

    func testNegativeMetronomeVolumeClamped() {
        let backend = makeAttachedBackend()
        backend.setMetronomeVolume(-3)
        XCTAssertEqual(backend.metronomeOutputVolumeForTests, 0, accuracy: 1e-6)
    }

    // MARK: - 变速 / seek / 传输 / 生命周期（只锁不崩与位置夹紧）

    func testRateAndSeekKeepPositionNonNegative() {
        let backend = makeAttachedBackend()
        let midi = makeMidi()
        backend.loadSequence(midi, timeline: PlaybackTimeline(score: Score(division: midi.division)))

        backend.setRate(0.5)
        backend.seek(toTick: 0)
        XCTAssertGreaterThanOrEqual(backend.currentPositionSeconds, 0)

        // 目标 tick 超过序列末端：秒数由 timeline 外推给出，位置仍须 ≥ 0（不崩即契约）。
        backend.seek(toTick: 100_000)
        XCTAssertGreaterThanOrEqual(backend.currentPositionSeconds, 0)
    }

    func testSeekBeforeAnySequenceIsSafeNoOp() {
        let backend = makeAttachedBackend()
        backend.seek(toTick: 480)
        XCTAssertEqual(backend.currentTick, 0, "无 timeline 时 currentTick 读 0，不能崩")
    }

    func testTransportAndTeardownAreIdempotent() {
        let backend = makeAttachedBackend()
        let midi = makeMidi()
        backend.loadSequence(midi, timeline: PlaybackTimeline(score: Score(division: midi.division)))

        backend.play()
        backend.pause()
        backend.play()
        backend.stop()
        XCTAssertEqual(backend.currentPositionSeconds, 0, "stop 后位置归零")

        backend.teardown()
        backend.teardown() // 幂等：不崩
        backend.play()     // teardown 后仍可调，不崩
        backend.stop()
    }

    func testNoteAndProgramMessagesAreSafeWithoutSoundfont() {
        let backend = makeAttachedBackend()
        backend.startNote(channel: 0, pitch: 60, velocity: 90)
        backend.stopNote(channel: 0, pitch: 60)
        backend.setProgram(channel: 0, program: 0)
        backend.sendVolume(channel: 0, cc7: 100)
        backend.setTuning(cents: 0, transposeSemitones: 0)
        // 无音源时这些消息被 sampler 静默吞掉；只锁不崩。
        XCTAssertTrue(backend.isReady)
    }
}

import AVFoundation
import Foundation
import SheetMusicAudioApple
import SheetMusicAudioCore
import SheetMusicAudioSwiftySynth
import SheetMusicCore
import SheetMusicMIDI

// Take 回放服务（CURRENT.md Issue 2 · Stage A）——「我弹的」那一半。
//
// 为什么不用 DemoPlaybackService 的 PlaybackEngine：
// PlaybackEngine.play(from:in:) 只接受 Score，而一次 take 不是谱面。虽然可以走
// SheetMusicMIDI.MidiImporter 把 take 转成 Score，但那条管线带 BarSegmenter + MeasureQuantizer
// （MidiImporter.swift:6-11），会把演奏**量化到记谱网格**上——时序误差被抹平，
// 那就听不出自己到底弹得多不准了。所以这里直连 SwiftySynthBackend，保原始时序。
//
// 自带 AVAudioEngine：PlaybackEngine 内部的 engine 是 internal，外部拿不到。
// 与 DemoPlaybackService 各自一个引擎可共存（同进程共享 AVAudioSession），
// 但**不要同时播**——同一首曲子两个引擎错相位播放没法听，且音频内存翻倍。
//
// 明确不做 seek：SwiftySynthBackend 的 seek(toTick:) 依赖传入的 PlaybackTimeline 的
// tick→秒映射（SwiftySynthBackend.swift:453-505），而那个 timeline 来自**参考谱**的 tempo 表，
// 与 take 自己 SMF 里的 tempo 不是一张表。take 无反复，unrolled == notated，本就不需要 seek；
// 进度只读 currentPositionSeconds。

@MainActor
final class TakePlaybackService {

    /// 已加载的音源 span（秒）。进度分母。
    private var totalSeconds: TimeInterval = 0
    /// SF2 后台解析完成后要把 pendingMidi 送进 sequencer（加载期间 loadSequence 会被静默丢弃，
    /// 见 SynthBackend.swift:52-56 的 isReady == false 契约）
    private var pendingMidi: SheetMusicMIDI.MidiFile?
    private var isTornDown = false

    private let backend = SwiftySynthBackend()
    private let engine = AVAudioEngine()

    init() {
        backend.attach(to: engine)
        engine.connect(backend.sourceNode, to: engine.mainMixerNode, format: nil)
    }

    // MARK: - 状态

    /// 播放进度（0...1）；未加载或零时长时为 0
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, backend.currentPositionSeconds / totalSeconds))
    }

    var positionSeconds: TimeInterval {
        backend.currentPositionSeconds
    }

    var isAtEnd: Bool {
        backend.isAtEnd
    }

    var isReady: Bool {
        backend.isReady
    }

    // MARK: - 准备 / 播放

    /// 准备一次 take 回放。SF2 解析在后台线程进行，期间 `isReady == false`；
    /// 落地后自动把序列送进 sequencer，此时 `play()` 才有效。
    /// - Parameters:
    ///   - notes: MidiTakeParser.parse 的输出
    ///   - soundfontURL: 音源 URL；nil 时后端建不出 synth，回放静默（不崩——
    ///     这条路径根本不实例化 AUMIDISynth，没有 EXC_BAD_ACCESS 风险）
    func prepareTake(notes: [PlayedNote], soundfontURL: URL?) {
        guard !isTornDown else { return }
        let midi = TakeMidiBuilder.build(notes: notes)
        totalSeconds = spanSeconds(of: notes)
        pendingMidi = midi

        backend.onReadyChanged = { [weak self] ready in
            guard let self, ready else { return }
            self.flushPendingSequence()
        }
        backend.prepare(soundfontURL: soundfontURL, metronomeSoundfontURL: nil, drumChannels: [])

        // 换 take 时 backend 可能早已 ready（onReadyChanged 不会再触发），立即 flush。
        if backend.isReady {
            flushPendingSequence()
        }
    }

    func play() {
        guard !isTornDown, pendingMidi != nil, backend.isReady else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        backend.play()
    }

    /// 停止：先后端断音，再停引擎释放音频图。
    func stop() {
        guard !isTornDown else { return }
        backend.stop()
        engine.stop()
    }

    /// 宿主在视图消失时调用。幂等。
    func teardown() {
        guard !isTornDown else { return }
        stop()
        backend.teardown()
        pendingMidi = nil
        isTornDown = true
    }

    // MARK: - 私有

    /// SF2 落地后把序列送进 sequencer。timeline 用空 Score 现构一个：
    /// loadSequence 只把它存下来供 seek/currentTick 投影用，而本服务不 seek（见文件头），
    /// take 也无反复，空 timeline 安全。
    private func flushPendingSequence() {
        guard let midi = pendingMidi else { return }
        backend.loadSequence(midi, timeline: PlaybackTimeline(score: Score(division: midi.division)))
    }

    /// take 的墙钟跨度（首事件归零后的末事件时刻）
    private func spanSeconds(of notes: [PlayedNote]) -> TimeInterval {
        guard let first = notes.map(\.onsetSec).min() else { return 0 }
        let lastEnd = notes.map(\.endSec).max() ?? first
        return max(0, lastEnd - first)
    }

    /// deinit 到不了 @MainActor 的 teardown()，这里只做同步的引擎停机——
    /// 与包内 PlaybackEngine.deinit 同一处理（PlaybackEngine.swift:2702-2706）。
    deinit {
        engine.stop()
    }
}

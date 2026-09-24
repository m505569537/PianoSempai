import AVFoundation
import Foundation
import SheetMusicAudioApple
import SheetMusicAudioCore
import SheetMusicMIDI

// Apple 系统采样器合成后端：替换纯 Swift 的 SwiftySynthBackend（修复哈农播放全噪音）。
//
// 根因（主会话已用分层 probe 定量定位，勿重新调查）：SwiftySynth 在实时 AVAudioSourceNode
// render block 里算不过来——同一段哈农 SMF 离线渲染要 ~2.2 倍实时（且这是 CPU 远强于 iPhone 的 Mac），
// 真机持续错过缓冲截止期 → 爆音/噪音。乐谱 / MIDI / SoundFont 数据本身极干净（离线渲染
// spectral flatness 0.009、>6kHz 能量 0.3%、无削波）。这是实时算力问题，不是采样率数学错误
// （connect 的 `format: nil` 让引擎自动做 SRC，是 Apple 正常用法）。
//
// 本后端把 DSP（变调 / 多复调 / 混音 / SRC）全部交回系统高优先级音频线程，App CPU 不参与采样渲染：
// AVAudioUnitSampler × 2（乐谱 / 节拍器）+ AVAudioSequencer × 2。
// 已实证：AVAudioUnitSampler 能加载本 App 的 215MB MuseScore_General.sf2，
// 用 AVAudioSequencer 实时播同一哈农 SMF，输出 peak 0.365、无 NaN、spectral flatness 0.0007。
//
// 与 SwiftySynthBackend 的三处差异（都在 SynthBackend 协议容许范围内，任务书明确选定）：
// 1. **同步**加载：prepare 里直接 `try? loadSoundBankInstrument`，不实现 isReady / onReadyChanged
//    （用协议 extension 默认值，恒 ready）。代价是 215MB 音源的解析发生在主线程——
//    这是「不重设计后端加载生命周期」与「不卡 UI」之间按任务书选的前者。
// 2. 无 count-in：play(afterCountInSeconds:) 用协议默认（= 直接 play；本 App 从不使用）。
// 3. 无离线导出：makeOfflineInstance 用协议默认（返回 nil；本 App 无音频导出入口，
//    已实证 0 调用方）。

@MainActor
final class SamplerSynthBackend: SynthBackend {

    // MARK: - 音频图节点

    /// 乐谱音源。score sequencer 的每条 track 都路由到这里。
    private let scoreSampler = AVAudioUnitSampler()
    /// 节拍器音源（click = note 76/77，走 ch9）。与乐谱分开：节拍器要能独立静音 / 调音量
    /// 而不影响乐谱在响的音。
    private let metronomeSampler = AVAudioUnitSampler()
    /// 节拍器专用 mixer。**sampler（AVAudioUnit / AVAudioNode）没有 volume 属性，只有
    /// AVAudioMixerNode 有 outputVolume**（已从 SDK 头文件实证：AVAudioUnitSampler.h 只有
    /// stereoPan / overallGain / masterGain / globalTuning；outputVolume 在 AVAudioMixerNode.h）。
    /// 故节拍器的静音 / 音量必须经过这个 mixer，不能写 sampler.volume。
    private let metronomeMixer = AVAudioMixerNode()
    /// 汇总节点：乐谱直连 + 节拍器经 mixer，作为唯一 outputNode 交给宿主引擎连接。
    private let combiner = AVAudioMixerNode()

    var outputNode: AVAudioNode { combiner }

    // MARK: - 传输

    /// 乐谱 / 节拍器各一个 sequencer（在 `attach(to:)` 里用宿主 engine 创建）。
    /// 分开两条传输才能「live mute 节拍器而不重载乐谱 SMF」——协议注释的核心要求。
    private var scoreSequencer: AVAudioSequencer?
    private var metronomeSequencer: AVAudioSequencer?

    // MARK: - 持久状态（跨 sequence / 音源重载保留，与 setRate / setTuning 同契约）

    private var rate: Float = 1
    private var timeline: PlaybackTimeline?
    private var unrolledTimeMap: UnrolledTimeMap = .identity
    private var metronomeOffsetSeconds = 0.0
    private var metronomeVolume: Float = 1
    private var metronomeMuted = false
    private var scoreLengthSeconds = 0.0

    /// 已写出的临时 SMF 文件，teardown 时统一清理。加载成功后 sequencer 已把内容读进
    /// MusicSequence，但保守起见留到 teardown 再删。
    private var tempFileURLs: [URL] = []

    // MARK: - SynthBackend

    func attach(to engine: AVAudioEngine) {
        engine.attach(combiner)
        engine.attach(metronomeMixer)
        engine.attach(scoreSampler)
        engine.attach(metronomeSampler)
        engine.connect(scoreSampler, to: combiner, format: nil)
        engine.connect(metronomeSampler, to: metronomeMixer, format: nil)
        engine.connect(metronomeMixer, to: combiner, format: nil)
        scoreSequencer = AVAudioSequencer(audioEngine: engine)
        metronomeSequencer = AVAudioSequencer(audioEngine: engine)
    }

    func prepare(soundfontURL: URL?, metronomeSoundfontURL: URL?, drumChannels: Set<UInt8>) {
        // `drumChannels` 不使用：AVAudioUnitSampler 按 MIDI channel 9 自动当打击乐处理
        // （任务书实证：加载 program 0 后，ch9/note76 与 ch0/note60 都正常发声，
        // 故乐谱与节拍器各用一个 sampler 即可）。
        // 旋律 GM 钢琴：bankMSB = 0x79（Apple 头文件原话：melodic 常用 0x79，percussion 0x78）。
        if let soundfontURL {
            // try?：加载失败不崩，渲染静音。调用方（DemoPlaybackService）的 gate 已保证
            // URL 非 nil 才走到这里，这里只是双保险。
            try? scoreSampler.loadSoundBankInstrument(at: soundfontURL, program: 0, bankMSB: 0x79, bankLSB: 0)
        }
        // 节拍器优先用宿主的 click 音源；没有就与乐谱共用同一份 SF2（GM wood blocks 兜底）。
        if let metronomeURL = metronomeSoundfontURL ?? soundfontURL {
            try? metronomeSampler.loadSoundBankInstrument(at: metronomeURL, program: 0, bankMSB: 0x79, bankLSB: 0)
        }
    }

    func setUnrolledTimeMap(_ map: UnrolledTimeMap) {
        unrolledTimeMap = map
    }

    func loadSequence(_ midi: MidiFile, timeline: PlaybackTimeline) {
        self.timeline = timeline
        loadSMF(midi, into: scoreSequencer, sampler: scoreSampler, prefix: "score")
        // 时长取所有 track 的最大值（AVMusicTrack.lengthInSeconds，iOS 9+）。
        scoreLengthSeconds = scoreSequencer?.tracks.map { $0.lengthInSeconds }.max() ?? 0
        scoreSequencer?.rate = rate
        scoreSequencer?.currentPositionInSeconds = 0
    }

    func loadMetronomeSequence(_ midi: MidiFile, offsetSeconds: TimeInterval) {
        metronomeOffsetSeconds = offsetSeconds
        loadSMF(midi, into: metronomeSequencer, sampler: metronomeSampler, prefix: "metronome")
        metronomeSequencer?.rate = rate
        // `load` 会把传输位置重置到序列起点；按 seek 的同一口径把它拉回乐谱当前位置
        // （首加载时乐谱在 0，即 max(0, 0 + offset)）。
        metronomeSequencer?.currentPositionInSeconds = metronomePosition(
            forScoreSeconds: currentPositionSeconds,
        )
    }

    func play() {
        // 节拍器即使静音也让它跑：静音走 mixer.outputVolume（见 setMetronomeMuted），
        // 取消静音时 click 才能落在拍上。
        scoreSequencer?.prepareToPlay()
        try? scoreSequencer?.start()
        metronomeSequencer?.prepareToPlay()
        try? metronomeSequencer?.start()
    }

    func pause() {
        scoreSequencer?.stop()
        metronomeSequencer?.stop()
        // 停传输只是停事件派发：当时在响的音符的 note-off 永远不会来，声音会被冻在延音段，
        // 宿主随即停掉引擎 → 下次启动时那个和弦会整块回来（协议 pause() 注释的原文理由）。
        // 故 pause 与 stop 一样必须主动断音。
        silenceAllNotes(of: scoreSampler)
        silenceAllNotes(of: metronomeSampler)
    }

    func stop() {
        pause()
        // 乐谱归零；节拍器按同一口径回 offset（count-in 场景下 0 + offset 才是序列起点）。
        scoreSequencer?.currentPositionInSeconds = 0
        metronomeSequencer?.currentPositionInSeconds = metronomePosition(forScoreSeconds: 0)
    }

    func seek(toTick tick: Int) {
        guard let timeline else { return }
        // 半 tick 提前：`currentPositionInSeconds` 是连续时间轴，严格等于目标起点的位置
        // 可能因浮点/取整把目标音吃掉；退回半 tick（≪ 任何两个相邻 onset 的间隔）保证目标音发声。
        let notated = timeline.seconds(atTick: Double(tick) - 0.5)
        // `tick` 是记谱坐标，加载的 SMF 是 unrolled 渲染结果，必须先投影到传输自己的时钟。
        let unrolled = unrolledTimeMap.unrolledSeconds(fromNotated: notated)
        scoreSequencer?.currentPositionInSeconds = unrolled
        metronomeSequencer?.currentPositionInSeconds = metronomePosition(forScoreSeconds: unrolled)
    }

    var currentPositionSeconds: TimeInterval {
        scoreSequencer?.currentPositionInSeconds ?? 0
    }

    var currentTick: Int {
        guard let timeline else { return 0 }
        // 传输的时钟是 unrolled 序列的，`timeline` 是记谱的——先投影再查。
        let notated = unrolledTimeMap.notatedSeconds(fromUnrolled: currentPositionSeconds)
        return timeline.frame(atTime: notated)?.tick ?? 0
    }

    /// 是否已派发完加载 SMF 的全部事件。 sequencer 的位置停在序列长度处（或继续往前走），
    /// 故 `>= length - 0.05` 既覆盖「播完」，也覆盖宿主轮询略过终点。未加载时长度 0 → false
    /// （「不知道」不能读成「播完了」，否则引擎会在刚开始播的一刻就停）。
    var isAtEnd: Bool {
        scoreLengthSeconds > 0 && currentPositionSeconds >= scoreLengthSeconds - 0.05
    }

    func setRate(_ newRate: Float) {
        // 夹到 >0：负 rate 没有意义，且 sequencer.rate 不接受。本 App 只产生正 rate
        // （DemoPlaybackService 的 BPM 换算 ≥ 40/referenceBpm）。
        rate = max(0.01, newRate)
        scoreSequencer?.rate = rate
        metronomeSequencer?.rate = rate
    }

    func setTuning(cents: Double, transposeSemitones: Int) {
        // 本 App 无任何调用方：PlaybackEngine 只把 masterTuningCents（默认 0）与 transpose
        // 推下来，而 App 从不设置 A4 校准 / 移调（移调已在 MusicXML 内 baked），
        // 故这里只有 cents == 0 一条真实路径。
        // 注：AVAudioUnitSampler.globalTuning 的口径是 **cents**（SDK 头文件：范围
        // -2400...+2400，默认 0），不是频率倍率，故直接透传 cents。
        scoreSampler.globalTuning = Float(cents)
    }

    func setProgram(channel: UInt8, program: UInt8) {
        scoreSampler.sendProgramChange(program, onChannel: channel)
    }

    func sendVolume(channel: UInt8, cc7: UInt8) {
        scoreSampler.sendController(7, withValue: cc7, onChannel: channel)
    }

    func startNote(channel: UInt8, pitch: UInt8, velocity: UInt8) {
        scoreSampler.startNote(pitch, withVelocity: velocity, onChannel: channel)
    }

    func stopNote(channel: UInt8, pitch: UInt8) {
        scoreSampler.stopNote(pitch, onChannel: channel)
    }

    func setMetronomeMuted(_ muted: Bool) {
        metronomeMuted = muted
        // 只动 mixer 音量、不动 sequencer：节拍器传输保持推进，取消静音时 click 落在拍上。
        metronomeMixer.outputVolume = muted ? 0 : metronomeVolume
    }

    func setMetronomeVolume(_ volume: Float) {
        metronomeVolume = max(0, volume)
        if !metronomeMuted {
            metronomeMixer.outputVolume = metronomeVolume
        }
    }

    func teardown() {
        scoreSequencer?.stop()
        metronomeSequencer?.stop()
        silenceAllNotes(of: scoreSampler)
        silenceAllNotes(of: metronomeSampler)
        for url in tempFileURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempFileURLs.removeAll()
        // 幂等：重复调用只是再停一遍已停的传输、遍历一个空数组。
    }

    // MARK: - 私有

    /// 测试可见：节拍器 mixer 的输出音量（静音态的权威观测点）。
    var metronomeOutputVolumeForTests: Float { metronomeMixer.outputVolume }

    /// 节拍器传输应在的位置：乐谱位置 + offset（count-in 时节拍器跑在前面），夹在 ≥ 0。
    private func metronomePosition(forScoreSeconds seconds: TimeInterval) -> TimeInterval {
        max(0, seconds + metronomeOffsetSeconds)
    }

    /// 立即断音：对 0..<16 通道发 CC123（all notes off）+ CC120（all sound off）。
    /// CC120 是必须的——CC123 只发 note-off，release 段还在 synth 里跑。
    private func silenceAllNotes(of sampler: AVAudioUnitSampler) {
        for channel in 0..<16 {
            sampler.sendController(123, withValue: 0, onChannel: UInt8(channel))
            sampler.sendController(120, withValue: 0, onChannel: UInt8(channel))
        }
    }

    /// 把 MidiFile 写成临时 SMF 文件并加载进 sequencer。AVAudioSequencer 只接受文件 URL
    /// （`load(from:)`，不接 Data），故必须经 MidiWriter 落盘。写盘 / 加载失败一律静默：
    /// 本后端无 isReady 契约，失败时渲染自然静音，不崩。
    private func loadSMF(
        _ midi: MidiFile, into sequencer: AVAudioSequencer?, sampler: AVAudioUnitSampler, prefix: String,
    ) {
        guard let sequencer, let data = try? MidiWriter.write(midi) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).smf")
        do {
            try data.write(to: url, options: .atomic)
            try sequencer.load(from: url, options: [])
        } catch {
            try? FileManager.default.removeItem(at: url)
            return
        }
        tempFileURLs.append(url)
        // 必须显式路由：不设 destinationAudioUnit 时 track 事件走系统内置 DLS 音源，
        // 而不是我们加载的 SF2（任务书实证）。
        for track in sequencer.tracks {
            track.destinationAudioUnit = sampler
        }
    }
}

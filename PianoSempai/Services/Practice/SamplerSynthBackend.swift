import AVFoundation
import Foundation
import SheetMusicAudioApple
import SheetMusicAudioCore
import SheetMusicMIDI

// Apple 系统采样器合成后端：替换纯 Swift 的 SwiftySynthBackend（修复哈农播放全噪音）。
//
// 根因（主会话已实证，勿重新调查）：SwiftySynth 在实时 AVAudioSourceNode render block 里
// 算不过来（真机持续错过缓冲截止期 → 爆音/噪音），DSP 交回系统音频线程即可。
//
// 拓扑（Stage B）：**1 条 AVAudioSequencer（合并 SMF）+ 双音源目的地 + 单输出 mixer**：
// - 乐谱 track（ch0/ch1）→ 钢琴 `AVAudioUnitSampler`；
// - ch9 click track → **SineBeepAudioUnit**（原始电子蜂鸣，与练习室 MetronomeService 同一个类
//   → 音色必然一致；不再经钢琴 sampler 出 GM 木鱼）；
// - 两路汇入 `outputMixer`，`outputNode` 返回它（宿主协议视角仍是单输出节点）。
// 为什么必须单 sequencer——系统行为，有包内作者注释背书（PlaybackEngine.swift ~2398 / ~2343）：
// 一条 AVAudioEngine 只有一个 MusicSequence 槽位，多个 `AVAudioSequencer(audioEngine:)` 里
// **只有最后创建的那个**真正把事件送进音频图；先建者时钟照走、`track.destinationAudioUnit`
// 照读，但音符事件永远到不了目的地。历史上双 sequencer 版本因此整曲静音。
// 节拍器 live mute 走 click track 的 `isMuted`（包内 MetronomeController 同款）；
// 音量走 click 链路上的 `beepGainMixer.outputVolume`（SineBeep 无音量输入，故给它挂独立增益）。
// SineBeep 单元是异步创建的（AVAudioUnit.instantiate）：创建完成前 click track **不路由**、
// `play()` 推迟起传输——绝不允许 click 落到钢琴 sampler（那会把木鱼带回来）。
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

    /// 乐谱音源：score track（ch0/ch1）的目的地。**不再接 ch9 click**（见 beepUnit）。
    private let sampler = AVAudioUnitSampler()
    /// click 音源（SineBeep 异步创建完成前为 nil；期间 click track 不路由任何目的地）。
    private var beepUnit: AVAudioUnit?
    /// click 链路增益（SineBeep 无音量输入）：beepUnit → beepGainMixer → outputMixer，
    /// `setMetronomeVolume` 写它的 outputVolume。
    private let beepGainMixer = AVAudioMixerNode()
    /// 汇总输出：sampler 与 beep 链路都汇到这里；`outputNode` 返回它（宿主仍只见一个节点）。
    private let outputMixer = AVAudioMixerNode()

    var outputNode: AVAudioNode { outputMixer }

    // MARK: - 传输

    /// 全后端唯一的 sequencer（在 `attach(to:)` 里用宿主 engine 创建）。
    /// **绝不创建第二个**——见类注释的「一条 engine 一个 MusicSequence 槽位」。
    /// 节拍器以额外 track 的形式与乐谱同乘此传输（合并 SMF，见 reloadMerged）。
    private var transport: AVAudioSequencer?

    // MARK: - beep 异步创建 / 路由状态

    /// attach 时的宿主引擎（weak：宿主持有 engine，后端只借用来挂节点）。
    private weak var hostEngine: AVAudioEngine?
    /// beep 单元的创建任务（attach 即启动；完成时挂载节点并补路由）。
    private var beepTask: Task<Void, Never>?
    /// true = click track 已加载但 beep 单元未就绪：暂不路由、play() 推迟起传输。
    private var pendingClickRouting = false
    /// true = beep 单元创建失败（无音频宿主等）：click 恒静默，play() 不再等待。
    private var beepUnavailable = false
    /// teardown 后 beep 挂载完成回调必须 no-op（不得引用已拆的图）。
    private var tornDown = false

    // MARK: - 持久状态（跨 sequence / 音源重载保留，与 setRate / setTuning 同契约）

    private var rate: Float = 1
    private var timeline: PlaybackTimeline?
    private var unrolledTimeMap: UnrolledTimeMap = .identity
    /// 乐谱 SMF 输入（loadSequence 存入；合并 SMF 的主体）。
    private var scoreMidi: MidiFile?
    /// 节拍器 SMF 输入（loadMetronomeSequence 存入；其 note track 被追加进合并 SMF）。
    private var metroMidi: MidiFile?
    /// 节拍器事件的整体 tick 平移（秒）。本 App 恒 0（playWhole/resume 均 countIn:false），
    /// 非 0 路径见 `metroOffsetTicks()` 的 best-effort 折算与局限说明。
    private var metroOffsetSeconds: TimeInterval = 0
    /// 合并 SMF 里**实际追加且经 load 存活**的节拍器 track 数：静音作用范围 =
    /// 已加载传输的**最后** `metroTrackCount` 条 track（`AVAudioSequencer.load` 保持顺序、
    /// 只丢弃空 track，而追加的 metro track 全部带音符，故存活者恰为末尾这几条）。
    /// 不能用「load 前的乐谱 track 数」当偏移——乐谱 SMF 末尾的空占位 track 会被
    /// load 丢弃，预载计数整体错位，静音会落空（回归即源于此）。
    private var metroTrackCount = 0
    private var metronomeVolume: Float = 1
    private var metronomeMuted = false
    /// 乐谱时长（score tracks 的 lengthInSeconds 最大值）；isAtEnd 的依据。
    private var scoreLengthSeconds = 0.0

    /// 最近一次写出的合并 SMF 临时文件（每次 (re)load 前删旧写新），teardown 统一清理。
    private var tempFileURLs: [URL] = []

    // MARK: - SynthBackend

    func attach(to engine: AVAudioEngine) {
        hostEngine = engine
        // 内部子图：sampler → outputMixer、beepGainMixer → outputMixer 在这里接好；
        // outputMixer 本身**不 connect**——宿主把 outputNode 连到它自己的 scoreGainMixer。
        engine.attach(outputMixer)
        engine.attach(beepGainMixer)
        engine.attach(sampler)
        engine.connect(sampler, to: outputMixer, format: nil)
        engine.connect(beepGainMixer, to: outputMixer, format: nil)
        transport = AVAudioSequencer(audioEngine: engine)
        // SineBeep 单元异步创建（AVAudioUnit.instantiate 无同步 API）；完成即挂载 + 补路由。
        // 失败（无音频宿主等）→ click 恒静默，不崩、不阻塞 play（与后端整体 no-output 语义一致）。
        beepTask = Task { [weak self] in
            let unit: AVAudioUnit?
            do {
                unit = try await SineBeepAudioUnitFactory.make()
            } catch {
                unit = nil
            }
            guard let self, !self.tornDown else { return }
            guard let unit else {
                self.beepUnavailable = true
                self.pendingClickRouting = false
                return
            }
            guard let hostEngine = self.hostEngine else { return }
            hostEngine.attach(unit)
            hostEngine.connect(unit, to: self.beepGainMixer, format: nil)
            self.beepUnit = unit
            self.beepGainMixer.outputVolume = self.metronomeVolume
            self.applyTrackRouting()
        }
    }

    func prepare(soundfontURL: URL?, metronomeSoundfontURL: URL?, drumChannels: Set<UInt8>) {
        // 三个入参都只喂**钢琴** sampler：乐谱 track（ch0/ch1）的目的地是它。
        // ch9 click track 走 SineBeepAudioUnit（见 attach/applyTrackRouting），不占用
        // sampler 的打击乐通道；`metronomeSoundfontURL`（宿主 click SF2）与 `drumChannels`
        // 因此均不使用。SF2 只加载一次。
        // 旋律 GM 钢琴：bankMSB = 0x79（Apple 头文件原话：melodic 常用 0x79，percussion 0x78）。
        // try?：加载失败不崩，渲染静音。调用方（DemoPlaybackService）的 gate 已保证
        // URL 非 nil 才走到这里，这里只是双保险。
        if let soundfontURL {
            try? sampler.loadSoundBankInstrument(at: soundfontURL, program: 0, bankMSB: 0x79, bankLSB: 0)
        }
    }

    func setUnrolledTimeMap(_ map: UnrolledTimeMap) {
        unrolledTimeMap = map
    }

    func loadSequence(_ midi: MidiFile, timeline: PlaybackTimeline) {
        self.timeline = timeline
        scoreMidi = midi
        // 首次调用时 metroMidi 可能尚未存入：合并 = 纯乐谱（宿主调用序恒为
        // loadSequence → setUnrolledTimeMap → loadMetronomeSequence）。
        reloadMerged()
        transport?.rate = rate
        transport?.currentPositionInSeconds = 0
    }

    func loadMetronomeSequence(_ midi: MidiFile, offsetSeconds: TimeInterval) {
        metroMidi = midi
        metroOffsetSeconds = offsetSeconds
        // load 会把传输位置重置到序列起点：先捕获当前位置，合并重载后原样恢复。
        // （App 调用序里此处恒在播放开始前，位置为 0；协议只要求位置保持，不要求续播。）
        let restoredPosition = transport?.currentPositionInSeconds ?? 0
        reloadMerged()
        transport?.currentPositionInSeconds = restoredPosition
    }

    func play() {
        // click 路由未定（beep 单元创建中）时不得起传输：等创建完成、路由应用后再开播，
        // 避免「click 落错目的地 / 前几拍无声」的竞态。beep 创建失败则按无输出语义直接开播。
        if pendingClickRouting, !beepUnavailable, let beepTask {
            transport?.prepareToPlay()
            Task { [weak self] in
                _ = await beepTask.value
                guard let self, !self.tornDown else { return }
                self.startTransport()
            }
            return
        }
        startTransport()
    }

    private func startTransport() {
        // 节拍器即使静音也让它跑：静音走 click track 的 isMuted（见 setMetronomeMuted），
        // 取消静音时 click 仍落在拍上。
        transport?.prepareToPlay()
        try? transport?.start()
    }

    func pause() {
        transport?.stop()
        // 停传输只是停事件派发：当时在响的音符的 note-off 永远不会来，声音会被冻在延音段，
        // 宿主随即停掉引擎 → 下次启动时那个和弦会整块回来（协议 pause() 注释的原文理由）。
        // 故 pause 与 stop 一样必须主动断音——但只断**钢琴**的音：click 在 SineBeep 单元里，
        // 单帧内自动终止（≤35ms），对钢琴 sampler 发 ch9 AllNotesOff 管不到它。
        silenceAllNotes()
    }

    func stop() {
        pause()
        transport?.currentPositionInSeconds = 0
    }

    func seek(toTick tick: Int) {
        guard let timeline else { return }
        // 半 tick 提前：`currentPositionInSeconds` 是连续时间轴，严格等于目标起点的位置
        // 可能因浮点/取整把目标音吃掉；退回半 tick（≪ 任何两个相邻 onset 的间隔）保证目标音发声。
        let notated = timeline.seconds(atTick: Double(tick) - 0.5)
        // `tick` 是记谱坐标，加载的 SMF 是 unrolled 渲染结果，必须先投影到传输自己的时钟。
        let unrolled = unrolledTimeMap.unrolledSeconds(fromNotated: notated)
        transport?.currentPositionInSeconds = unrolled
    }

    var currentPositionSeconds: TimeInterval {
        transport?.currentPositionInSeconds ?? 0
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
        transport?.rate = rate
    }

    func setTuning(cents: Double, transposeSemitones: Int) {
        // 本 App 无任何调用方：PlaybackEngine 只把 masterTuningCents（默认 0）与 transpose
        // 推下来，而 App 从不设置 A4 校准 / 移调（移调已在 MusicXML 内 baked），
        // 故这里只有 cents == 0 一条真实路径。
        // 注：AVAudioUnitSampler.globalTuning 的口径是 **cents**（SDK 头文件：范围
        // -2400...+2400，默认 0），不是频率倍率，故直接透传 cents。
        sampler.globalTuning = Float(cents)
    }

    func setProgram(channel: UInt8, program: UInt8) {
        sampler.sendProgramChange(program, onChannel: channel)
    }

    func sendVolume(channel: UInt8, cc7: UInt8) {
        sampler.sendController(7, withValue: cc7, onChannel: channel)
    }

    func startNote(channel: UInt8, pitch: UInt8, velocity: UInt8) {
        sampler.startNote(pitch, withVelocity: velocity, onChannel: channel)
    }

    func stopNote(channel: UInt8, pitch: UInt8) {
        sampler.stopNote(pitch, onChannel: channel)
    }

    func setMetronomeMuted(_ muted: Bool) {
        metronomeMuted = muted
        applyMetronomeMute()
    }

    func setMetronomeVolume(_ volume: Float) {
        // click 链路是 beepUnit → beepGainMixer → outputMixer；SineBeep 无音量输入，
        // 音量走独立增益 mixer 的 outputVolume（静音走 click track 的 isMuted，与之正交：
        // 静音中改音量不影响静音，取消静音后按新音量出声，故总是直接写）。
        let clamped = max(0, min(1, volume))
        metronomeVolume = clamped
        beepGainMixer.outputVolume = clamped
    }

    func teardown() {
        tornDown = true
        beepTask?.cancel()
        transport?.stop()
        silenceAllNotes()
        for url in tempFileURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempFileURLs.removeAll()
        // 幂等：重复调用只是再停一遍已停的传输、遍历一个空数组。
        // 节点 detach/disconnect 归宿主管（宿主只认识 outputNode）。
    }

    // MARK: - 测试钩子（只读观测 / 最小注入点，不改变产品行为）

    /// 合并传输的总 track 数（乐谱 track + 节拍器 track）。
    var mergedTrackCountForTests: Int { transport?.tracks.count ?? 0 }

    /// 实际追加且经 load 存活的节拍器 track 数（静音/路由范围 = 已加载传输的最后 N 条）。
    var metroTrackCountForTests: Int { metroTrackCount }

    /// 每条 track 的实时静音态（setMetronomeMuted 的权威观测点，下标与合并 track 对齐）。
    var tracksMutedForTests: [Bool] {
        transport?.tracks.map { $0.isMuted } ?? []
    }

    /// 合并传输的 rate（setRate 夹取的观测点）。
    var rateForTests: Float { rate }

    /// 合并 SMF 的乐谱时长（isAtEnd 的分母）。
    var scoreLengthSecondsForTests: TimeInterval { scoreLengthSeconds }

    /// 乐谱（非 click）track 的路由目的地——必须是钢琴 sampler。
    var scoreDestinationNodeForTests: AVAudioNode? {
        guard let transport, !transport.tracks.isEmpty else { return nil }
        return transport.tracks.first?.destinationAudioUnit
    }

    /// 首条 click track 的路由目的地——必须是 SineBeep 单元；beep 未就绪时为 nil（不路由），
    /// **绝不允许等于钢琴 sampler**（那会带回木鱼音色）。
    var clickDestinationNodeForTests: AVAudioNode? {
        guard let transport, !transport.tracks.isEmpty else { return nil }
        let tracks = transport.tracks
        let clickCount = min(metroTrackCount, tracks.count)
        guard clickCount > 0 else { return nil }
        return tracks[tracks.count - clickCount].destinationAudioUnit
    }

    /// 钢琴 sampler 节点（路由同一性断言的基准）。
    var pianoDestinationNodeForTests: AVAudioNode { sampler }

    /// SineBeep 单元节点（nil = 未就绪/创建失败）。
    var beepDestinationNodeForTests: AVAudioNode? { beepUnit }

    /// beep 单元创建失败（无音频宿主等）：click 恒静默，路由等待测试应跳过。
    var beepUnavailableForTests: Bool { beepUnavailable }

    /// click 链路增益 mixer 的输出音量（setMetronomeVolume 的权威观测点）。
    var beepGainVolumeForTests: Float { beepGainMixer.outputVolume }

    // MARK: - 私有

    /// 立即断音：对 0..<16 通道发 CC123（all notes off）+ CC120（all sound off）。
    /// CC120 是必须的——CC123 只发 note-off，release 段还在 synth 里跑。
    private func silenceAllNotes() {
        for channel in 0..<16 {
            sampler.sendController(123, withValue: 0, onChannel: UInt8(channel))
            sampler.sendController(120, withValue: 0, onChannel: UInt8(channel))
        }
    }

    /// 把 `metronomeMuted` 压到合并传输的节拍器 track 上——已加载 track 的**最后**
    /// `metroTrackCount` 条（见该字段的注释：不能用预载的乐谱 track 数当偏移）。
    /// 独立成函数是因为每次合并重载（load/`load(from:)`）都会重置 track 状态，需重放。
    private func applyMetronomeMute() {
        guard let transport else { return }
        let count = min(metroTrackCount, transport.tracks.count)
        for track in transport.tracks.suffix(count) {
            track.isMuted = metronomeMuted
        }
    }

    /// 显式路由乐谱/click track：乐谱（非末尾 metroTrackCount 条）→ 钢琴 sampler；
    /// click → SineBeep 单元。beep 未就绪时 click **不路由任何目的地**（记 pendingClickRouting，
    /// 由 beep 挂载完成回调补路由、play() 推迟起传输）——绝不允许 click 落到钢琴 sampler，
    /// 否则 click 会以 GM 木鱼音色经钢琴音源发声（Stage B 之前的历史行为）。
    /// beep 创建失败（beepUnavailable）时 click 恒静默：按无输出安全语义放行 play。
    private func applyTrackRouting() {
        guard let transport else { return }
        let tracks = transport.tracks
        guard !tracks.isEmpty else { return }
        let clickCount = min(metroTrackCount, tracks.count)
        for (index, track) in tracks.enumerated() {
            if index >= tracks.count - clickCount {
                if let beepUnit {
                    track.destinationAudioUnit = beepUnit
                }
                // beep 未就绪：留空（nil），不落钢琴
            } else {
                track.destinationAudioUnit = sampler
            }
        }
        let clickRouted = clickCount == 0 || tracks.suffix(clickCount)
            .allSatisfy { $0.destinationAudioUnit != nil && !($0.destinationAudioUnit === sampler) }
        pendingClickRouting = !clickRouted && !beepUnavailable
    }

    /// 节拍器 offset（秒）→ tick 的 best-effort 折算。
    ///
    /// 本 App 恒 0（playWhole/resume 均 countIn:false；包内 count-in 路径
    /// `startBackendCountIn` 不会走到这个后端）。合并 SMF 只保留乐谱的单一 tempo map
    /// （metro 的 meta-only track 被剔除），故无法表达随时间变化的 tempo——只能按常量
    /// tempo 折算：优先取乐谱 tempo map 的第一个 tempo 事件，缺省 120 BPM（SMF 缺省值）。
    /// count-in 若真被启用，此折算在变速谱上会有误差——届时应改由包内在装配期烘焙 offset。
    private func metroOffsetTicks() -> Int {
        guard metroOffsetSeconds != 0, let scoreMidi else { return 0 }
        var microsecondsPerQuarter = 500_000 // 120 BPM（SMF 缺省 tempo）
        outer: for track in scoreMidi.tracks {
            for event in track.events {
                if case let .meta(.tempo(usPerQuarter)) = event.event {
                    microsecondsPerQuarter = usPerQuarter
                    break outer
                }
            }
        }
        let beatsPerSecond = 60_000_000.0 / Double(microsecondsPerQuarter) / 60.0
        return Int((metroOffsetSeconds * beatsPerSecond * Double(scoreMidi.division)).rounded())
    }

    /// 用缓存的 scoreMidi + metroMidi 重建合并 SMF 并加载进唯一传输。
    /// 合并规则：
    /// - 主体 = score 的**全部** track（含其 tempo map —— 合并序列**只此一份** tempo map）；
    /// - metro 侧**只追加携带音符事件（noteOn/noteOff）的 track，且每条只追加一次**：
    ///   meta-only track（conductor/tempo 轨）一律剔除——合并序列不得出现第二份 tempo map，
    ///   click track 也不得重复（曾因「全量追加 + 过滤追加」双写导致两条 ch9 click，
    ///   suffix 静音只盖住末条，另一条永远出声——「节拍器关不掉」的回归）；
    /// - 被追加的 metro 事件 tick 整体平移 `metroOffsetTicks()`（App 恒 0；平移只作用于
    ///   本次合并的副本，**不回写 metroMidi**，否则每次重载都会累积漂移）。
    /// 写盘 / 加载失败一律静默早退：本后端无 isReady 契约，失败时渲染自然静音，不崩。
    private func reloadMerged() {
        guard let transport, let scoreMidi else { return }
        // 此刻 mergedTracks 恒等于 scoreMidi.tracks——metro 侧只经下方单次循环进入。
        var mergedTracks = scoreMidi.tracks
        let offsetTicks = metroOffsetTicks()
        // 追加前清零，逐条统计真正带音符、真正被追加的 metro track 数（load 后
        // 静音范围与乐谱时长都按这个数从**已加载** track 的末尾反推）。
        metroTrackCount = 0
        var appendedMetro: [MidiTrack] = []
        if let metroMidi {
            for track in metroMidi.tracks {
                let hasNotes = track.events.contains { event in
                    switch event.event {
                    case .noteOn, .noteOff: true
                    default: false
                    }
                }
                guard hasNotes else { continue }
                if offsetTicks != 0 {
                    // 平移只作用于本次合并的副本，**不回写 metroMidi**——否则每次重载都会
                    // 在上一次平移的基础上再叠一次 offset（累积漂移）。
                    appendedMetro.append(MidiTrack(events: track.events.map {
                        TimedMidiEvent(tick: $0.tick + offsetTicks, event: $0.event)
                    }))
                } else {
                    appendedMetro.append(track)
                }
                metroTrackCount += 1
            }
        }
        mergedTracks.append(contentsOf: appendedMetro)
        let merged = MidiFile(division: scoreMidi.division, format: 1, tracks: mergedTracks)
        guard let data = try? MidiWriter.write(merged) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("demo-merged-\(UUID().uuidString).smf")
        do {
            try data.write(to: url, options: .atomic)
            try transport.load(from: url, options: [])
        } catch {
            try? FileManager.default.removeItem(at: url)
            return
        }
        for old in tempFileURLs {
            try? FileManager.default.removeItem(at: old)
        }
        tempFileURLs = [url]
        // 必须显式路由：不设 destinationAudioUnit 时 track 事件走系统内置 DLS 音源。
        // 乐谱 track → 钢琴 sampler；click track → SineBeep 单元（未就绪则暂不路由、
        // play() 推迟起传输）——绝不允许 click 落到钢琴 sampler（木鱼回归）。
        applyTrackRouting()
        // `load` 会重置 rate 与 track 静音态：按持久真值重放（mute 状态跨重载保留）。
        transport.rate = rate
        applyMetronomeMute()
        // 乐谱时长 = 已加载 track 里**非 metro** 部分的最大值（AVMusicTrack.lengthInSeconds，
        // iOS 9+）。用 `dropLast(metroTrackCount)` 而非「预载乐谱 track 数」的 prefix：
        // 乐谱 SMF 末尾的空占位 track 会被 load 丢弃，预载计数会让 prefix 越界吃到
        // click track，把 isAtEnd 的分母算错。
        scoreLengthSeconds = transport.tracks
            .dropLast(min(metroTrackCount, transport.tracks.count))
            .map { $0.lengthInSeconds }.max() ?? 0
    }
}

import Foundation
import Observation
import SheetMusicAudioApple
import SheetMusicAudioCore
import SheetMusicCore

// 整曲示范播放服务（CURRENT.md Issue 2 · Stage A：只有核心，无 UI）。
// 包装 swift-sheet-music 的 PlaybackEngine（SheetMusicAudioApple），
// 音源走 BundledSoundfontResolver，合成后端注入 SamplerSynthBackend（系统 AVAudioUnitSampler：
// 纯 Swift 的 SwiftySynth 在实时 render block 里算不过来——真机哈农播放全噪音的根因，
// 详见 SamplerSynthBackend 文件头。采样 DSP 全部由系统高优先级音频线程承担，不占 App CPU）。
//
// 三个设计约束（都是包内文档明确写过的，别绕过）：
// 1. 音源 gate：URL 为 nil 时**绝不调用 engine.prepare**。见 BundledSoundfontResolver 文件头的
//    EXC_BAD_ACCESS 说明。availability == .unavailable 时所有入口都是安全 no-op。
// 2. 音频会话策略用 .mixUntilPlay：prepare 只拿 mixing 会话，用户第一次真按播放才独占。
//    默认的 .exclusiveOnPrepare 会在「打开曲目详情页」时就切走别人正在放的音频——本 app 的
//    入口形态（进页面就带着谱）正好踩这个坑。
// 3. teardown() 必须由宿主在视图消失时显式调用。包内 PlaybackEngine.swift:2718-2740 记录：
//    stop() 只是 pause 引擎，IO 线程与 render-notify 块还活着，此时释放 sequencer / 摘 synth
//    会和在飞的渲染周期竞争，在 IO 线程上 EXC_BAD_ACCESS（1.7.0 上有 ~118 人中招）。
//    deinit 到不了 @MainActor 的 teardown()，所以宿主不调就没人调。
//
// 观测：PlaybackEngine 是 @MainActor @Observable，故本类型同样 @MainActor @Observable，
// 视图用 @State 持有（不是 @StateObject——包 README 里那个示例是过时的，照抄编译不过）。

@MainActor
@Observable
final class DemoPlaybackService {

    /// 音源可用性。.unavailable = bundle 里没有 .sf2，示范功能整体禁用。
    enum Availability: Equatable {
        case ready
        case unavailable
    }

    enum DemoError: Error, Equatable {
        case soundfontUnavailable
    }

    private let resolver: BundledSoundfontResolver
    /// 注入到 PlaybackEngine 的合成后端。PlaybackEngine 没暴露 public 的节拍器开关，
    /// 但 backend 遵循 SynthBackend、有 public `setMetronomeMuted`（注入后端的 click 由它自己的 synth 产生），
    /// 故持有该引用以控制示范页节拍器。
    private let backend: SamplerSynthBackend
    private let engine: PlaybackEngine

    /// 参考速度（rate=1.0 对应的 BPM 口径，与练习室 tempoState.referenceBpm 一致）。
    private let referenceBpm: Int

    /// 已 prepare 过的谱（防止同一份谱重复 prepare；换谱才重新 prepare）
    private var preparedScore: Score?
    /// teardown 之后引擎不可再用（避免视图消失后又来一个 play）
    private var isTornDown = false

    /// 示范页节拍器开关。**默认 false**：示范是"听原曲"，不该像旧实现那样自带拍子
    /// （PlaybackEngine 的 MetronomeController.isEnabled 默认 true，必须显式关掉）。
    private(set) var metronomeEnabled = false

    /// 当前 BPM（与练习室口径一致：40...referenceBpm，默认 = 参考速度）。
    private(set) var bpm: Int

    init(
        resolver: BundledSoundfontResolver = BundledSoundfontResolver(),
        referenceBpm: Int = 72,
    ) {
        self.resolver = resolver
        // 参考速度兜底：传入 0/非法时回落 72，避免倍率计算除零。
        let ref = max(1, referenceBpm)
        self.referenceBpm = ref
        self.bpm = ref
        let backend = SamplerSynthBackend()
        self.backend = backend
        // 后端注入 SamplerSynthBackend：同步加载音源（AVAudioUnitSampler 的
        // loadSoundBankInstrument），isReady 恒 true，play 不会被推迟。
        self.engine = PlaybackEngine(
            soundfontResolver: resolver,
            backend: backend,
            audioSessionPolicy: .mixUntilPlay
        )
        // 注意：此刻不能在这里静音——mixer 通道要等 prepare(score:) 才建立（见 syncMetronome），
        // 而播放路径会用引擎内部 metronome.isEnabled(默认 true) 反压 backend。真值由 metronomeEnabled 持有，
        // prepare/play 时统一通过 syncMetronome() 压进去。
    }

    // MARK: - 状态（视图直接读）

    var availability: Availability {
        resolver.isAvailable ? .ready : .unavailable
    }

    /// 引擎状态：stopped / playing / paused / exporting
    var state: PlaybackState {
        engine.state
    }

    /// SF2 后台加载中（此时 play 会被推迟）
    var isPreparingSoundfont: Bool {
        engine.isPreparingSoundfont
    }

    /// 播放光标——直接喂给 ScoreView(playbackCursor:)。
    /// 注意引擎给的是 .item(ScoreItemID)（和弦级），比跟弹光标的 .beat 更细。
    var currentCursor: ScoreCursor? {
        engine.currentCursor
    }

    var currentTimeSeconds: TimeInterval {
        engine.currentTimeSeconds
    }

    var totalTimeSeconds: TimeInterval {
        engine.totalTimeSeconds
    }

    // MARK: - 传输

    /// 准备谱面。同步、首次调用可能较慢（音源加载 + preset 准备都在这里发起）。
    /// - Throws: `DemoError.soundfontUnavailable` 当 bundle 无音源——此时绝不碰引擎。
    func prepare(score: Score) throws {
        guard availability == .ready else { throw DemoError.soundfontUnavailable }
        guard !isTornDown else { return }
        try engine.prepare(score: score)
        preparedScore = score
        // prepare 刚按默认值（节拍器不静音）重建了 mixer 通道，立刻压回 App 真值，
        // 否则接下来 play 会用引擎默认 isEnabled=true 让 click 响。
        syncMetronome()
    }

    /// 从头播放整曲。未 prepare 时先 prepare（幂等）；音源缺失时安全 no-op。
    func playWhole(score: Score) {
        guard availability == .ready, !isTornDown else { return }
        if preparedScore == nil {
            try? prepare(score: score)
        }
        syncMetronome()
        engine.play(from: nil, in: score, countIn: false)
    }

    /// 示范按钮的两态语义（Stage B 的「示范」控件只有一个按钮）：
    /// playing → pause（保留位置，再按继续）；paused/stopped → stop（回卷并清光标）。
    func pauseOrStop() {
        guard !isTornDown else { return }
        if engine.state == .playing {
            engine.pause()
        } else {
            engine.stop()
        }
    }

    /// pause 后继续播放：从暂停处的光标继续（不能传 nil——那会从头播）。
    func resume(score: Score) {
        guard availability == .ready, !isTornDown else { return }
        syncMetronome()
        engine.play(from: engine.currentCursor, in: score, countIn: false)
    }

    /// 停止并回卷（区别于 pause：下一次 play 从开头开始）
    func stop() {
        guard !isTornDown else { return }
        engine.stop()
    }

    // MARK: - 节拍器 & 速度（与练习室同一套口径）

    /// 参考速度（rate=1.0 的 BPM）。视图显示上限与滑块范围用。
    var referenceBpmValue: Int { referenceBpm }

    /// 测试用：引擎 mixer 里 metronome 通道的静音态（nil = 通道尚未建立）。
    /// 这是「UI 显示关、播放却响」那条 bug 的权威观测点——真值必须压到引擎通道上。
    var metronomeChannelIsMuted: Bool? {
        engine.mixerChannels.first(where: { $0.id == .metronome })?.isMuted
    }

    /// 节拍器开关。默认关；开 = 在当前播放位置恢复 click（backend 内部会 reseek 到当前拍）。
    /// 播放中途切换是 live mute，不重载谱、不切断在响的琴声。
    func setMetronome(_ on: Bool) {
        guard !isTornDown else { return }
        metronomeEnabled = on
        syncMetronome()
    }

    /// 把 App 的节拍器真值压进引擎。这是必须的，因为 PlaybackEngine 在 prepare/seek/play 多处
    /// 会用它内部 `metronome.isEnabled`（默认 **true**）反压 backend 的静音状态（PlaybackEngine.swift
    /// 的 setMetronomeMuted 调用点），光在 backend 上静音会被播放路径冲掉——表现就是「UI 显示关、
    /// 一播放却有 click，手动切两次才真消失」。
    ///
    /// 走 public 的 mixer 静音：setMuted(.metronome) → applyMixerState → setMetronomeEnabled，
    /// 同时把引擎侧 isEnabled 与 backend 静音都设对。mixer 通道在 prepare 后才存在，
    /// 通道缺失时 setMuted 是 no-op，故 prepare 完成后必须再调一次。
    private func syncMetronome() {
        guard !isTornDown else { return }
        engine.setMuted(forChannel: .metronome, to: !metronomeEnabled)
        // 双保险：mixer 通道尚未建立（prepare 未完成）时，直接把当前意图写进 backend，
        // 等 prepare→syncMetronome 再由 mixer 权威压一次。
        backend.setMetronomeMuted(!metronomeEnabled)
    }

    /// BPM 步进调速（与练习室 changeTempo 一致：clamp 到 40...referenceBpm）。
    /// 引擎只认倍率，故以参考速度为 rate=1.0 基准换算；setRate 跨 sequencer 重建持续生效。
    func changeTempo(by delta: Int) {
        let next = min(max(40, bpm + delta), referenceBpm)
        setTempo(next)
    }

    /// 直接设定 BPM（同样 clamp）。
    func setTempo(_ nextBpm: Int) {
        let next = min(max(40, nextBpm), referenceBpm)
        guard next != bpm else { return }
        bpm = next
        engine.setRate(Float(next) / Float(referenceBpm))
    }

    /// 宿主必须在视图消失时调用。幂等。
    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        preparedScore = nil
        engine.teardown()
    }
}

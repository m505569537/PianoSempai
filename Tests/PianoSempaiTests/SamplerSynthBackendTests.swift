import AVFoundation
import XCTest
@testable import PianoSempai
import SheetMusicAudioCore
import SheetMusicCore
import SheetMusicMIDI

/// SamplerSynthBackend 的契约测试（单 sequencer 合并 SMF + 双音源拓扑）。
///
/// 边界：这里**不验证真出声**（测试宿主不保证有音频输出，且「听见了」无法在进程内断言）。
/// 真出声由主会话模拟器 + 用户真机听验。这里只锁五件事：
/// 1. 不崩——所有协议入口在「无音源 / 未启动引擎 / 未加载序列」下都是安全 no-op；
/// 2. 拓扑契约——outputNode 是 outputMixer（宿主只见一个输出节点）、唯一 sequencer，
///    乐谱 + 节拍器 track 合并在**同一条**传输里（一条 engine 只有一个 MusicSequence 槽位：
///    多 sequencer 时只有最后创建者出声——双 sequencer 版整曲静音的根因，死约束）；
/// 3. 路由契约——乐谱 track → 钢琴 sampler；ch9 click track → SineBeep 单元（未就绪时
///    不路由），**click 绝不路由到钢琴 sampler**（否则 GM 木鱼回归）；
/// 4. 合并/静音契约——已加载传输的**末尾** `metroTrackCount` 条是节拍器（乐谱 SMF 末尾的
///    空占位 track 是否被 `AVAudioSequencer.load` 丢弃是实现细节，静音范围必须按
///    「实际追加且存活的 metro track 数从末尾反推」）：setMetronomeMuted 只翻转这段
///    track 的 isMuted，不碰乐谱 track、不重载、不重置位置；音量写 beepGainMixer.outputVolume；
/// 5. 传输契约——同步后端 isReady 恒 true、位置/终点位/速率夹取确定。
@MainActor
final class SamplerSynthBackendTests: XCTestCase {

    /// 一个自建引擎：只创建不 start（不给硬件，纯节点图操作）。
    private func makeAttachedBackend() -> SamplerSynthBackend {
        let backend = SamplerSynthBackend()
        let engine = AVAudioEngine()
        backend.attach(to: engine)
        // Mirror the host: backend.outputNode must reach an output endpoint, otherwise
        // AVAudioSequencer.prepareToPlay() throws -10876 ("no output node"). Engine is
        // connected but not started — these tests assert graph/state behavior, not sound.
        engine.connect(backend.outputNode, to: engine.mainMixerNode, format: nil)
        return backend
    }

    /// 一音的最小合法 SMF（走 TakeMidiBuilder，与 TakePlaybackService 同一构造路径）。
    /// 单 track（tempo meta + noteOn/noteOff 对），故既能当乐谱也能当节拍器输入。
    private func makeMidi() -> SheetMusicMIDI.MidiFile {
        TakeMidiBuilder.build(notes: [
            PlayedNote(pitch: 60, onsetSec: 0, endSec: 1, velocity: 90, isSuspicious: false),
        ])
    }

    /// 真实乐谱形状（与 App 生成的示范 SMF 一致）：两条钢琴 note track（ch0/ch1）+
    /// 末尾一条**空占位 track**。`AVAudioSequencer.load` 会丢弃空 track——
    /// 静音范围回归（预载计数错位）正是踩在这个丢弃行为上，测试必须复刻它。
    private func makeScoreMidiWithEmptyPlaceholder() -> SheetMusicMIDI.MidiFile {
        func noteTrack(_ channel: Int, _ pitch: Int) -> SheetMusicMIDI.MidiTrack {
            SheetMusicMIDI.MidiTrack(events: [
                TimedMidiEvent(tick: 0, event: .noteOn(channel: channel, pitch: pitch, velocity: 90)),
                TimedMidiEvent(tick: 480, event: .noteOff(channel: channel, pitch: pitch, velocity: 0)),
            ])
        }
        return SheetMusicMIDI.MidiFile(division: 480, format: 1, tracks: [
            noteTrack(0, 60),
            noteTrack(1, 36),
            SheetMusicMIDI.MidiTrack(events: []), // 空占位：load 会被丢弃
        ])
    }

    private func makeTimeline(for midi: SheetMusicMIDI.MidiFile) -> PlaybackTimeline {
        PlaybackTimeline(score: Score(division: midi.division))
    }

    /// 加载乐谱 + 节拍器序列（节拍器 offset 0）——合并 SMF 的完整两步调用序
    /// （与 PlaybackEngine.loadBackendNormalSequence 一致）。乐谱用真实形状
    /// （含空占位 track），节拍器用单 note track。
    private func makeLoadedBackend() -> SamplerSynthBackend {
        let backend = makeAttachedBackend()
        backend.loadSequence(
            makeScoreMidiWithEmptyPlaceholder(),
            timeline: makeTimeline(for: makeScoreMidiWithEmptyPlaceholder()),
        )
        backend.loadMetronomeSequence(makeMidi(), offsetSeconds: 0)
        return backend
    }

    // MARK: - 构造 / 音频图拓扑（双音源 + 单输出 mixer / 单 sequencer）

    func testOutputNodeIsTheMixer() {
        let backend = SamplerSynthBackend()
        // outputNode 是 outputMixer（AVAudioMixerNode）：钢琴与 beep 两路在此汇总，
        // 宿主协议视角仍只有一个输出节点，连进它自己的 scoreGainMixer。
        let node = try? XCTUnwrap(backend.outputNode as? AVAudioMixerNode)
        XCTAssertNotNil(node, "outputNode 必须是汇总 mixer，不是任何音源单元本身")
    }

    func testAttachAttachesGraphToEngine() {
        let backend = SamplerSynthBackend()
        let engine = AVAudioEngine()
        backend.attach(to: engine)

        // attach 后 outputNode（outputMixer）必须已挂到引擎上——宿主据此判断要不要 attach。
        XCTAssertTrue(backend.outputNode.engine === engine)
        XCTAssertFalse(backend.isAtEnd, "未加载序列时不能读成「已播完」")
    }

    /// 单 sequencer 的行为证据：乐谱与节拍器前后两次 load 落在**同一条**传输上。
    /// 不锁绝对 track 总数，也不锁两次 load 间的净计数——空占位 track 被丢弃与否
    /// 是实现细节且非确定，两种情况产品修复（suffix 静音 + dropLast 时长）都成立；
    /// 只锁下限（乐谱 note track 载入、合并后至少 2 钢琴 + 1 click）、「节拍器 track
    /// 恰好 1 条」、以及乐谱 track 路由到钢琴 sampler（click 不在此断言——见
    /// testClickNeverRoutesToPianoSampler；beep 异步就绪不在此等待）。
    func testScoreAndMetronomeShareOneTransport() {
        let backend = makeAttachedBackend()
        backend.loadSequence(
            makeScoreMidiWithEmptyPlaceholder(),
            timeline: makeTimeline(for: makeScoreMidiWithEmptyPlaceholder()),
        )
        // 只加载乐谱：末尾空占位 track 可能被 load 丢弃也可能保留，但至少要载入
        // 两条钢琴 note track（一条被丢就说明 load 行为异常，仍须暴露）。
        let nAfterScore = backend.mergedTrackCountForTests
        XCTAssertGreaterThanOrEqual(nAfterScore, 2, "两条钢琴 note track 必须载入传输")
        XCTAssertTrue(backend.scoreDestinationNodeForTests === backend.pianoDestinationNodeForTests,
                      "乐谱 track 必须路由到钢琴 sampler")

        backend.loadMetronomeSequence(makeMidi(), offsetSeconds: 0)
        // 不锁「+1」净计数：空占位 track 在两次 load 中的丢/留非确定（实测 2→4），
        // 净计数等式不成立；只锁下限（至少 2 钢琴 + 1 click 载入）。
        XCTAssertGreaterThanOrEqual(backend.mergedTrackCountForTests, 3, "至少 2 钢琴 + 1 click 载入")
        XCTAssertEqual(backend.metroTrackCountForTests, 1)
        XCTAssertTrue(backend.scoreDestinationNodeForTests === backend.pianoDestinationNodeForTests,
                      "节拍器加载后乐谱 track 路由不受影响")
    }

    /// click track 不得重复（回归）：曾因「全量追加 + 过滤追加」双写导致合并序列里
    /// 有两条 ch9 click，suffix 静音只盖末条、另一条永远出声（「节拍器关不掉」）。
    /// 结构断言：载入的乐谱 track（2 或 3，取决于空占位 track 被 load 丢/留）+ 恰好
    /// 1 条 click；静音后**恰好末尾 1 条**为 true、其余全 false——若 click 被复制，
    /// suffix(1) 盖不住倒数第二条，这里即失败。
    func testMetronomeClickTrackIsAppendedExactlyOnce() {
        let backend = makeLoadedBackend()
        XCTAssertEqual(backend.metroTrackCountForTests, 1,
                       "节拍器侧只允许一条带音符的 click track 被追加")
        // fixture：乐谱 3 条（2 note + 1 空占位）+ 1 click = 内存 4 条；
        // load 后空占位去留非确定 → 已加载总数 ∈ {3, 4}。
        XCTAssertTrue((3...4).contains(backend.mergedTrackCountForTests),
                      "已加载 track 数应为乐谱（2 或 3）+ 恰好 1 条 click，实测 \(backend.mergedTrackCountForTests)")

        backend.setMetronomeMuted(true)
        let muted = backend.tracksMutedForTests
        XCTAssertEqual(muted.filter { $0 }.count, 1,
                       "静音后必须恰好一条 track（唯一的 click）为 true——多于一条即 click 重复")
        XCTAssertTrue(muted.last ?? false, "被静音的必须是末尾的 click track")
        for (idx, isMuted) in muted.enumerated() where idx < muted.count - 1 {
            XCTAssertFalse(isMuted,
                           "click 之前的乐谱 track \(idx) 不得被静音——若它竟是 true，说明存在盖不住的第二条 click")
        }

        backend.setMetronomeMuted(false)
        XCTAssertTrue(backend.tracksMutedForTests.allSatisfy { !$0 },
                      "取消静音恢复全可发声")
    }

    /// 路由死约束：ch9 click track **绝不**路由到钢琴 sampler——否则 click 以 GM 木鱼
    /// 音色经钢琴音源发声（Stage B 之前的回归）。beep 单元未就绪时 click 目的地必须是
    /// nil（不路由、play 推迟起传输），已就绪时必须是 SineBeep 单元——两者都不是钢琴。
    func testClickNeverRoutesToPianoSampler() {
        // 同步取 makeLoadedBackend() 后立即断言（不等异步 beep 创建——无论就绪与否都不许是钢琴）。
        let backend = makeLoadedBackend()
        if let click = backend.clickDestinationNodeForTests {
            XCTAssertFalse(click === backend.pianoDestinationNodeForTests,
                           "click track 不得路由到钢琴 sampler")
            if let beep = backend.beepDestinationNodeForTests {
                XCTAssertTrue(click === beep, "beep 就绪时 click 必须路由到 SineBeep 单元")
            }
        } else {
            // nil = 尚未路由（beep 创建中）：合法状态，此时也不得有目的地指向钢琴。
            if let score = backend.scoreDestinationNodeForTests {
                XCTAssertTrue(score === backend.pianoDestinationNodeForTests,
                              "乐谱 track 始终路由到钢琴 sampler")
            }
        }
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

        backend.loadSequence(midi, timeline: makeTimeline(for: midi))

        XCTAssertFalse(backend.isAtEnd, "加载后未播放：不能是终点")
        XCTAssertEqual(backend.currentTick, 0)
        XCTAssertEqual(backend.currentPositionSeconds, 0)
    }

    func testLoadMetronomeSequenceIsSafe() {
        let backend = makeAttachedBackend()
        let midi = makeMidi()
        backend.loadSequence(midi, timeline: makeTimeline(for: midi))
        backend.loadMetronomeSequence(midi, offsetSeconds: 0)
        backend.loadMetronomeSequence(midi, offsetSeconds: 2)
        // 只锁不崩 + 位置不受节拍器重载影响（恢复到捕获值）
        XCTAssertEqual(backend.currentPositionSeconds, 0)
    }

    /// loadMetronomeSequence 必须保持当前播放位置：捕获 → 重载 → 恢复（容差内相等）。
    func testLoadMetronomeSequencePreservesPosition() {
        let backend = makeAttachedBackend()
        let midi = makeMidi()
        backend.loadSequence(midi, timeline: makeTimeline(for: midi))
        backend.loadMetronomeSequence(midi, offsetSeconds: 0)

        let positionBefore = backend.currentPositionSeconds
        backend.loadMetronomeSequence(midi, offsetSeconds: 0)
        XCTAssertEqual(backend.currentPositionSeconds, positionBefore, accuracy: 0.05,
                       "节拍器重载（合并 SMF re-load）不得重置乐谱位置")
    }

    // MARK: - 节拍器静音（权威观测点 = 合并 track 的 isMuted，实时、不重载、不重置位置）

    func testMetronomeMuteTogglesOnlyMetroTracks() {
        let backend = makeLoadedBackend()
        XCTAssertEqual(backend.metroTrackCountForTests, 1)
        let total = backend.tracksMutedForTests.count
        let k = backend.metroTrackCountForTests
        XCTAssertGreaterThan(total, k, "前置：合并传输里除节拍器外还应有乐谱 track")
        XCTAssertTrue(backend.tracksMutedForTests.allSatisfy { !$0 }, "初始不静音")

        backend.setMetronomeMuted(true)
        // 只锁相对形状：恰好**末尾 k 条**（节拍器 track）为 true，其余（乐谱 track）一律 false。
        // 绝对 track 总数不锁——空占位 track 被 load 丢弃与否是系统实现细节。
        let muted = backend.tracksMutedForTests
        XCTAssertEqual(muted.count, total, "静音切换不得增删 track")
        for (idx, isMuted) in muted.enumerated() {
            if idx >= total - k {
                XCTAssertTrue(isMuted, "末尾的节拍器 track \(idx) 必须被静音")
            } else {
                XCTAssertFalse(isMuted, "乐谱 track \(idx) 不得被节拍器静音波及")
            }
        }

        backend.setMetronomeMuted(false)
        XCTAssertTrue(backend.tracksMutedForTests.allSatisfy { !$0 },
                      "取消静音要恢复全部 track 可发声")
    }

    func testMetronomeMuteIsLiveWithoutReloadOrPositionReset() {
        let backend = makeLoadedBackend()
        let positionBefore = backend.currentPositionSeconds
        // 连续 toggle（不重载序列、不重新 load）：状态正确翻转、位置不动。
        backend.setMetronomeMuted(true)
        backend.setMetronomeMuted(false)
        backend.setMetronomeMuted(true)
        XCTAssertTrue(backend.tracksMutedForTests.suffix(backend.metroTrackCountForTests)
            .allSatisfy { $0 })
        XCTAssertTrue(backend.tracksMutedForTests
            .prefix(backend.mergedTrackCountForTests - backend.metroTrackCountForTests)
            .allSatisfy { !$0 }, "乐谱 track 的静音态永不改变")
        XCTAssertEqual(backend.currentPositionSeconds, positionBefore, accuracy: 0.05,
                       "静音切换不得重置播放位置")
        XCTAssertFalse(backend.isAtEnd, "静音切换不影响终点位语义")

        backend.setMetronomeMuted(false)
        XCTAssertTrue(backend.tracksMutedForTests.allSatisfy { !$0 })
    }

    func testMetronomeMuteBeforeAnyLoadIsSafeNoOp() {
        let backend = makeAttachedBackend()
        backend.setMetronomeMuted(true)
        backend.setMetronomeMuted(false)
        XCTAssertTrue(backend.tracksMutedForTests.isEmpty, "未加载时无 track 可静音，但不崩")
    }

    /// 静音态要跨合并重载保留：loadMetronomeSequence 会 re-load 并重置 track 状态，
    /// 后端必须按持久真值重放 mute。
    func testMetronomeMuteSurvivesMetronomeReload() {
        let backend = makeLoadedBackend()
        backend.setMetronomeMuted(true)
        backend.loadMetronomeSequence(makeMidi(), offsetSeconds: 0) // 触发合并重载
        XCTAssertTrue(backend.tracksMutedForTests.suffix(backend.metroTrackCountForTests)
            .allSatisfy { $0 }, "重载后节拍器静音必须重放")
        XCTAssertTrue(backend.tracksMutedForTests
            .prefix(backend.mergedTrackCountForTests - backend.metroTrackCountForTests)
            .allSatisfy { !$0 }, "重载后乐谱 track 仍不静音")
    }

    // MARK: - 节拍器音量（写 beep 链路增益 mixer 的 outputVolume，夹取 0...1）

    func testMetronomeVolumeWritesBeepGain() {
        let backend = makeAttachedBackend()
        backend.setMetronomeVolume(0.5)
        XCTAssertEqual(backend.beepGainVolumeForTests, 0.5, accuracy: 1e-6,
                       "音量必须落到 click 链路的增益 mixer 上")
        backend.setMetronomeVolume(1.5)
        XCTAssertEqual(backend.beepGainVolumeForTests, 1.0, accuracy: 1e-6,
                       "超过 1 夹到 1")
        backend.setMetronomeVolume(-1)
        XCTAssertEqual(backend.beepGainVolumeForTests, 0.0, accuracy: 1e-6,
                       "负音量夹到 0")
        backend.setMetronomeVolume(1)
        XCTAssertEqual(backend.beepGainVolumeForTests, 1.0, accuracy: 1e-6)
    }

    // MARK: - 变速 / seek / 传输 / 生命周期（只锁不崩与位置夹紧）

    func testRateClampsAndApplies() {
        let backend = makeAttachedBackend()
        backend.setRate(0.5)
        XCTAssertEqual(backend.rateForTests, 0.5, accuracy: 1e-6)
        backend.setRate(-3)
        XCTAssertEqual(backend.rateForTests, 0.01, accuracy: 1e-6,
                       "负 rate 夹到 0.01（sequencer.rate 不接受非正值）")
        backend.setRate(2)
        XCTAssertEqual(backend.rateForTests, 2, accuracy: 1e-6)
    }

    func testRateAndSeekKeepPositionNonNegative() {
        let backend = makeAttachedBackend()
        let midi = makeMidi()
        backend.loadSequence(midi, timeline: makeTimeline(for: midi))

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

    func testStopResetsPositionAndTeardownIsIdempotent() {
        let backend = makeAttachedBackend()
        let midi = makeMidi()
        backend.loadSequence(midi, timeline: makeTimeline(for: midi))
        backend.loadMetronomeSequence(midi, offsetSeconds: 0)

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

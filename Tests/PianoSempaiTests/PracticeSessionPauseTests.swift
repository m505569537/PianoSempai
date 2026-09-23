import XCTest
@testable import PianoSempai

/// S11 Stage A：用户暂停/继续（主圆钮）的状态机与「活跃时间」记账。
/// 这里锁六件事：
/// 1. `pause()`/`resume()` 只在 `.performing`/`.paused` 生效，其余阶段 no-op（counting 不在本期范围）；
/// 2. 暂停期间停表：墙上时间继续走，`elapsedSec` 不动（tick 被 phase 挡掉，Timer 已 invalidate）；
/// 3. 恢复后 `elapsedSec` 只算活跃时间——暂停区间被 `totalPaused` 扣掉，10s 活跃 + 5s 暂停 = 10；
/// 4. `finish()` 时长用同一套公式，暂停的几分钟不计入 take duration（含「暂停中直接结束」）；
/// 5. 暂停期间 `handle()` 不消费/不判分/不落盘，恢复后从保留的 followState 继续；
/// 6. `timeUp` 按活跃时间算——暂停不烧倒计时；断连（isConnected=false）行为不受本期影响。
///
/// 时间全部经 `tick(now:)` / `pause(now:)` / `resume(now:)` / `finish(now:)` 注入，不 sleep、不看真实时钟。
/// 注意：标记点与 playedNotes 的相对秒仍按墙上时钟 startedAt（本期不改它们的基准），测试同样锁住这点。
final class PracticeSessionPauseTests: XCTestCase {

    private let region: [[UInt8]] = [[60], [62], [64]]

    @MainActor
    private func makePerformingSession() -> PracticeSession {
        let session = PracticeSession()
        session.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        // 节拍器 OFF → 跳过预备拍直接 performing（同时置 startedAt）。
        session.start(metronome: MetronomeService(), countIn: true, metronomeOn: false)
        XCTAssertEqual(session.phase, .performing)
        return session
    }

    // MARK: 1. 阶段门槛

    @MainActor
    func testPauseIsNoOpOutsidePerforming() {
        // idle：根本没有 startedAt，暂停必须无副作用
        let idle = PracticeSession()
        idle.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        idle.pause()
        XCTAssertEqual(idle.phase, .idle, "idle 暂停是 no-op")
        XCTAssertEqual(idle.totalPaused, 0, "没有暂停发生就不记暂停时长")

        // counting：预备拍期间的暂停不在本期范围，阶段必须原样留着
        let counting = PracticeSession()
        counting.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        let metronome = MetronomeService()
        counting.start(metronome: metronome, countIn: true, metronomeOn: true)
        XCTAssertEqual(counting.phase, .counting, "前置：预备拍中")
        counting.pause()
        XCTAssertEqual(counting.phase, .counting, "counting 期间 pause() 不生效，不能把阶段留在 .paused")
        XCTAssertEqual(counting.totalPaused, 0)
        counting.toggleMetronome(on: false, metronome: metronome) // 收尾，避免卡在 .counting
        metronome.stop()
        _ = counting.finish()

        // finished：结束后再点暂停不改阶段
        let finished = makePerformingSession()
        _ = finished.finish()
        finished.pause()
        XCTAssertEqual(finished.phase, .finished, "finished 暂停是 no-op")
        XCTAssertEqual(finished.totalPaused, 0)
    }

    @MainActor
    func testResumeIsNoOpOutsidePaused() {
        let session = makePerformingSession()
        session.resume()
        XCTAssertEqual(session.phase, .performing, "performing 中 resume() 不改变阶段")
        XCTAssertEqual(session.totalPaused, 0, "没有暂停可结算，totalPaused 不动")
        _ = session.finish()

        let idle = PracticeSession()
        idle.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        idle.resume()
        XCTAssertEqual(idle.phase, .idle, "idle 中 resume() 是 no-op")
    }

    // MARK: 2. 暂停期间时间冻结

    @MainActor
    func testPauseFreezesElapsedSeconds() {
        let session = makePerformingSession()
        defer { _ = session.finish() }
        let start = session.startedAt!

        session.tick(now: start.addingTimeInterval(10))
        XCTAssertEqual(session.elapsedSec, 10, "前置：演奏到第 10 秒")

        session.pause(now: start.addingTimeInterval(10))
        XCTAssertEqual(session.phase, .paused, "主圆钮按下 → .paused")
        XCTAssertEqual(session.totalPaused, 0, "暂停尚未结算，resume 时才累加")

        // 墙上时间继续走（含远超 1 秒心跳的间隔），tick 一律被 phase 挡掉
        session.tick(now: start.addingTimeInterval(11))
        session.tick(now: start.addingTimeInterval(30))
        session.tick(now: start.addingTimeInterval(120))
        XCTAssertEqual(session.elapsedSec, 10, "暂停期间墙上时间不推进 elapsedSec")
        XCTAssertFalse(session.timeUp, "暂停期间不到点")
    }

    // MARK: 3. 恢复后只算活跃时间

    @MainActor
    func testResumeElapsedExcludesPausedGap() {
        let session = makePerformingSession()
        defer { _ = session.finish() }
        let start = session.startedAt!

        session.tick(now: start.addingTimeInterval(10))
        session.pause(now: start.addingTimeInterval(10))

        session.resume(now: start.addingTimeInterval(15)) // 暂停了 5 秒
        XCTAssertEqual(session.phase, .performing, "继续 → 回到 .performing")
        XCTAssertEqual(session.totalPaused, 5, accuracy: 0.001, "暂停区间累加进 totalPaused")

        // 活跃 10s + 暂停 5s：墙上第 15 秒时，elapsedSec 必须是 10 而不是 15
        session.tick(now: start.addingTimeInterval(15))
        XCTAssertEqual(session.elapsedSec, 10, "暂停区间不计入 elapsedSec")

        // 之后每秒照常推进，起点仍是开始那一刻（不重置 startedAt）
        session.tick(now: start.addingTimeInterval(25))
        XCTAssertEqual(session.elapsedSec, 20, "恢复后续弹：25s 墙上 - 5s 暂停 = 20")
        XCTAssertEqual(session.startedAt, start, "resume 不重置 startedAt")
    }

    @MainActor
    func testMultiplePauseGapsAllExcluded() {
        let session = makePerformingSession()
        defer { _ = session.finish() }
        let start = session.startedAt!

        session.tick(now: start.addingTimeInterval(4))
        session.pause(now: start.addingTimeInterval(4))
        session.resume(now: start.addingTimeInterval(6))  // 暂停 2s
        session.pause(now: start.addingTimeInterval(9))
        session.resume(now: start.addingTimeInterval(16)) // 又暂停 7s

        XCTAssertEqual(session.totalPaused, 9, accuracy: 0.001, "多段暂停累计")

        session.tick(now: start.addingTimeInterval(20)) // 20 - 9 = 11
        XCTAssertEqual(session.elapsedSec, 11, "多段暂停全部扣除，且计时不倒退")
    }

    // MARK: 4. finish() 时长同样扣暂停

    @MainActor
    func testFinishDurationExcludesPausedTime() {
        let session = makePerformingSession()
        let start = session.startedAt!

        session.tick(now: start.addingTimeInterval(10))
        session.pause(now: start.addingTimeInterval(10))
        session.resume(now: start.addingTimeInterval(15)) // 5s 暂停

        // 墙上第 20 秒结束：活跃 20 - 5 = 15
        let summary = session.finish(now: start.addingTimeInterval(20))
        XCTAssertEqual(summary.durationSec, 15, "take 时长只算活跃时间，暂停的 5 秒不计入")
        XCTAssertEqual(session.phase, .finished)
    }

    @MainActor
    func testFinishWhilePausedExcludesInProgressPause() {
        let session = makePerformingSession()
        let start = session.startedAt!

        session.tick(now: start.addingTimeInterval(10))
        session.pause(now: start.addingTimeInterval(10))

        // 暂停中直接点「结束并保存」：从暂停起点到结束的这段也不能算进去
        let summary = session.finish(now: start.addingTimeInterval(40))
        XCTAssertEqual(summary.durationSec, 10, "暂停中结束：只算暂停前那 10 秒")
    }

    // MARK: 5. 暂停期间不判分

    @MainActor
    func testHandleIgnoresEventsWhilePausedThenResumesScoring() {
        let session = makePerformingSession()
        defer { _ = session.finish() }

        session.handle(MIDIEvent(kind: .noteOn(note: 60, velocity: 90), channel: 0, timeNanos: 1))
        XCTAssertEqual(session.midiEventCount, 1, "前置：演奏中消费一个事件")
        XCTAssertEqual(session.followState.playedCount, 1, "前置：判分计数 1")

        session.pause()
        // 暂停期间弹的音一律忽略：不计数、不判分、不推进光标
        session.handle(MIDIEvent(kind: .noteOn(note: 62, velocity: 90), channel: 0, timeNanos: 2))
        session.handle(MIDIEvent(kind: .noteOn(note: 61, velocity: 90), channel: 0, timeNanos: 3))
        session.handle(MIDIEvent(kind: .sustainPedal(value: 127), channel: 0, timeNanos: 4))
        XCTAssertEqual(session.midiEventCount, 1, "暂停期间不消费事件")
        XCTAssertEqual(session.followState.playedCount, 1, "暂停期间不判分")
        XCTAssertEqual(session.pedalCount, 0, "暂停期间不计踏板")
        XCTAssertEqual(session.followState.measureIndex, 1, "光标停在暂停前的位置（小节 0 的 60 已耗尽）")

        session.resume()
        session.handle(MIDIEvent(kind: .noteOn(note: 62, velocity: 90), channel: 0, timeNanos: 5))
        XCTAssertEqual(session.midiEventCount, 2, "恢复后续录")
        XCTAssertEqual(session.followState.playedCount, 2, "恢复后从保留的 followState 继续判分")
        XCTAssertEqual(session.followState.measureIndex, 2, "小节 1 期望耗尽 → 推进到小节 2")
    }

    // MARK: 6. timeUp 按活跃时间；断连行为不变

    @MainActor
    func testTimeUpUsesActiveElapsedNotWallClock() {
        let session = makePerformingSession()
        defer { _ = session.finish() }
        let start = session.startedAt!
        session.timeLimitSec = 5

        session.tick(now: start.addingTimeInterval(4))
        XCTAssertFalse(session.timeUp, "未到上限")

        session.pause(now: start.addingTimeInterval(4))
        session.tick(now: start.addingTimeInterval(30)) // 暂停中：tick 被挡掉
        XCTAssertFalse(session.timeUp, "暂停期间不到点——暂停时间不烧倒计时")

        session.resume(now: start.addingTimeInterval(34)) // 暂停了 30 秒
        session.tick(now: start.addingTimeInterval(34))
        XCTAssertEqual(session.elapsedSec, 4, "恢复瞬间仍是 4 秒活跃时间")
        XCTAssertFalse(session.timeUp, "活跃时间没到上限")

        session.tick(now: start.addingTimeInterval(35))
        XCTAssertTrue(session.timeUp, "活跃时间满 5 秒才到点")
        XCTAssertEqual(session.elapsedSec, 5)
    }

    @MainActor
    func testDisconnectBehaviorUnchangedByPauseWork() {
        let session = makePerformingSession()
        defer { _ = session.finish() }

        session.handle(MIDIEvent(kind: .noteOn(note: 60, velocity: 90), channel: 0, timeNanos: 1))
        session.setConnected(false)
        session.handle(MIDIEvent(kind: .noteOn(note: 64, velocity: 90), channel: 0, timeNanos: 2))
        XCTAssertEqual(session.midiEventCount, 1, "断连期间不消费事件（判分暂停）")
        XCTAssertEqual(session.phase, .performing, "断连只置 isConnected=false，不改阶段")
        XCTAssertEqual(session.interruptionStarts.count, 1, "断连标记 interruption 起点")

        session.setConnected(true)
        session.handle(MIDIEvent(kind: .noteOn(note: 62, velocity: 90), channel: 0, timeNanos: 3))
        XCTAssertEqual(session.midiEventCount, 2, "重连后续录")
        XCTAssertEqual(session.interruptionStarts.count, 1, "重连不新增断点")
    }

    // MARK: 7. 恢复不清零任何东西

    @MainActor
    func testResumeKeepsMarksPlayedNotesAndCounters() {
        let session = makePerformingSession()
        defer { _ = session.finish() }
        let start = session.startedAt!

        session.tick(now: start.addingTimeInterval(8))
        session.addMark()
        session.handle(MIDIEvent(kind: .noteOn(note: 60, velocity: 90), channel: 0, timeNanos: 1))
        session.handle(MIDIEvent(kind: .sustainPedal(value: 127), channel: 0, timeNanos: 2))
        session.changeTempo(by: 4)

        let marksBefore = session.marks
        let notesBefore = session.playedNotes
        let followBefore = session.followState
        let elapsedBefore = session.elapsedSec
        let tempoBefore = session.tempoState.bpm

        session.pause(now: start.addingTimeInterval(9))
        session.resume(now: start.addingTimeInterval(12))

        XCTAssertEqual(session.marks, marksBefore, "标记点原样保留（仍按墙上时钟 startedAt）")
        XCTAssertEqual(session.playedNotes.count, notesBefore.count, "playedNotes 不清零")
        XCTAssertEqual(session.playedNotes.first?.sec, notesBefore.first?.sec, "playedNotes 相对秒基准不变")
        XCTAssertEqual(session.followState, followBefore, "跟弹状态原样保留")
        XCTAssertEqual(session.elapsedSec, elapsedBefore, "resume 不当场改写 elapsedSec（等下一次 tick）")
        XCTAssertEqual(session.midiEventCount, 2, "事件计数保留")
        XCTAssertEqual(session.pedalCount, 1, "踏板计数保留")
        XCTAssertEqual(session.tempoState.bpm, tempoBefore, "速度保留")
        XCTAssertEqual(session.startedAt, start, "startedAt 不重置")
    }
}

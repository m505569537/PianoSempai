import XCTest
@testable import PianoSempai

/// 演奏计时心跳（问题2：进度卡冻在 0:00）。
/// 根因：PracticeSession 的 1 秒 Timer 平时不发布任何重绘信号，视图里现算 Date() 的
/// elapsed 没有触发就不刷新。修复后每秒走纯逻辑 tick(now:)，把整秒写进 @Published elapsedSec。
/// 这里锁三件事：performing 中按 startedAt 推进 elapsedSec；非 performing 不推进；到点置 timeUp。
final class PracticeSessionTickTests: XCTestCase {

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

    @MainActor
    func testTickAdvancesElapsedSeconds() {
        let session = makePerformingSession()
        defer { _ = session.finish() }
        let start = session.startedAt!

        session.tick(now: start.addingTimeInterval(3))
        XCTAssertEqual(session.elapsedSec, 3, "performing 中 tick 应把整秒推进到 3")

        session.tick(now: start.addingTimeInterval(7))
        XCTAssertEqual(session.elapsedSec, 7)
    }

    @MainActor
    func testTickSetsTimeUpAtLimit() {
        let session = makePerformingSession()
        defer { _ = session.finish() }
        let start = session.startedAt!
        session.timeLimitSec = 5

        session.tick(now: start.addingTimeInterval(4))
        XCTAssertFalse(session.timeUp, "未到上限不置 timeUp")
        XCTAssertEqual(session.elapsedSec, 4)

        session.tick(now: start.addingTimeInterval(5))
        XCTAssertTrue(session.timeUp, "达到上限应置 timeUp，由视图收尾")
    }

    @MainActor
    func testTickAfterTimeUpDoesNotAdvance() {
        let session = makePerformingSession()
        defer { _ = session.finish() }
        let start = session.startedAt!
        session.timeLimitSec = 5

        session.tick(now: start.addingTimeInterval(5))
        XCTAssertTrue(session.timeUp)
        session.tick(now: start.addingTimeInterval(9))
        XCTAssertEqual(session.elapsedSec, 5, "已 timeUp 后不再推进")
    }

    @MainActor
    func testTickWhileIdleDoesNothing() {
        let session = PracticeSession()
        session.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        session.tick(now: Date())
        XCTAssertEqual(session.elapsedSec, 0, "idle 状态 tick 不应推进计时")
    }

    // MARK: 时长目标（PRD：循环 3/5/10 遍或 5 分钟——达标自动一次「完整收尾遍」）

    /// 弹完一整遍（region = [[60],[62],[64]]：三音耗尽即 wrap 回起点）
    @MainActor
    private func playOneLoopPass(_ session: PracticeSession) {
        session.handle(MIDIEvent(kind: .noteOn(note: 60, velocity: 90), channel: 0, timeNanos: 1))
        session.handle(MIDIEvent(kind: .noteOn(note: 62, velocity: 90), channel: 0, timeNanos: 2))
        session.handle(MIDIEvent(kind: .noteOn(note: 64, velocity: 90), channel: 0, timeNanos: 3))
    }

    @MainActor
    func testMinutesTargetSetsPendingThenFinishesOnWrap() {
        let session = PracticeSession()
        session.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        session.loopConfig.targetLoopMinutes = 5
        session.start(metronome: MetronomeService(), countIn: false, metronomeOn: false)
        defer { _ = session.finish() }
        let start = session.startedAt!

        session.tick(now: start.addingTimeInterval(299))
        XCTAssertFalse(session.finalPassPending, "299 秒未达标")
        XCTAssertFalse(session.timeUp, "时长目标不是 timeUp 机制——不立即收尾")

        session.tick(now: start.addingTimeInterval(300))
        XCTAssertTrue(session.finalPassPending, "活跃满 5 分钟 → 待「完整收尾遍」")
        XCTAssertEqual(session.phase, .performing, "达标不立即 finish——当前遍要弹完")

        session.tick(now: start.addingTimeInterval(400))
        XCTAssertTrue(session.finalPassPending, "达标后没 wrap 就一直 pending")

        playOneLoopPass(session)
        XCTAssertEqual(session.phase, .finished, "完整收尾遍弹完 → 自动收尾")
        XCTAssertFalse(session.finalPassPending, "收尾遍完成即清标记")
    }

    @MainActor
    func testCountTargetStillFinishesFirstWhenBothSet() {
        let session = PracticeSession()
        session.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        session.loopConfig.targetLoopCount = 1
        session.loopConfig.targetLoopMinutes = 5
        session.start(metronome: MetronomeService(), countIn: false, metronomeOn: false)
        defer { _ = session.finish() }
        let start = session.startedAt!

        session.tick(now: start.addingTimeInterval(10))
        XCTAssertFalse(session.finalPassPending, "时长未达标，pending 从未置位")

        playOneLoopPass(session)
        XCTAssertEqual(session.phase, .finished, "遍数目标先到 → 先收尾（谁先达标谁触发）")
        XCTAssertFalse(session.finalPassPending)
        XCTAssertEqual(session.completedLoopCount, 1)
    }

    @MainActor
    func testMinutesTargetWithCountTargetFinishesExactlyOnce() {
        let session = PracticeSession()
        session.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        session.loopConfig.targetLoopCount = 3
        session.loopConfig.targetLoopMinutes = 5
        session.start(metronome: MetronomeService(), countIn: false, metronomeOn: false)
        defer { _ = session.finish() }
        let start = session.startedAt!

        session.tick(now: start.addingTimeInterval(400))
        XCTAssertTrue(session.finalPassPending, "时长先达标")

        playOneLoopPass(session)
        XCTAssertEqual(session.phase, .finished, "wrap 时按 pending 收尾")
        XCTAssertFalse(session.finalPassPending, "收尾即清标记")
        XCTAssertEqual(session.completedLoopCount, 1, "只 wrap 了一次（< 遍数目标 3，无双重收尾）")
    }

    @MainActor
    func testFreePlayNeverSetsMinutesPending() {
        let session = PracticeSession(isFreePlay: true)
        session.loopConfig.targetLoopMinutes = 5
        session.start(metronome: MetronomeService(), countIn: false, metronomeOn: false)
        XCTAssertEqual(session.phase, .performing, "前置：自由弹奏直接演奏")
        let start = session.startedAt!

        session.tick(now: start.addingTimeInterval(400))
        XCTAssertFalse(session.finalPassPending, "自由弹奏没有「完整收尾遍」概念（guard）")
        XCTAssertEqual(session.phase, .performing, "自由弹奏不因时长目标自动收尾")
    }
}

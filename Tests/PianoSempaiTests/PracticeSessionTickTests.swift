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
}

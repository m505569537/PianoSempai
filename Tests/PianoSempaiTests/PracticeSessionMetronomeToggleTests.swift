import XCTest
@testable import PianoSempai

/// 节拍器开关与预备拍的纠缠（RC2）。历史上预备拍不看 metronomeOn：开关 OFF 时照样打满
/// 一小节、之后还持续响；而在 .counting 期间拨开关会调 metronome.stop()，把
/// countInBeatsRemaining 清零 → onCountInFinished 永不触发 → phase 永远卡死在 .counting，
/// 会话无声且不判分。这里锁定「开关管住含预备拍在内的全部声音，且不留死路」。
///
/// 断言分层（correction v2）：
/// - 阶段/状态语义 → 无条件断言，与音频宿主无关；
/// - 「真的打出几拍」这类必须有真引擎才观察得到的 → 用 XCTSkip 明确跳过并写明原因，
///   不做 `if isRunning { … }` 那种静默跳过。
/// 不打「start() 之后同步剩几拍」这种 Brittle 断言：首拍在 start() 内已同步响，
/// 4 → 3 与 4 都语义正确；这里锁的是「正好 4 拍 + 正好一次回调」这个真契约。
final class PracticeSessionMetronomeToggleTests: XCTestCase {

    private let region: [[UInt8]] = [
        [60], // 小节 1
        [62], // 小节 2
        [64], // 小节 3
        [65], // 小节 4
    ]

    @MainActor
    private func makeSession() -> PracticeSession {
        let session = PracticeSession()
        session.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        return session
    }

    /// 无音频宿主时明确跳过打拍计数（而非静默 if）：没有引擎就打不出拍，计数观察不到。
    @MainActor
    private func requireAudioHost(_ metronome: MetronomeService) throws {
        try XCTSkipIf(!metronome.isRunning, "宿主无音频输出：节拍器安全 no-op，打拍计数观察不到")
    }

    /// 开关 OFF → 完全不打预备拍，直接进演奏。
    @MainActor
    func testMetronomeOffSkipsCountInEntirely() {
        let session = makeSession()
        let metronome = MetronomeService()
        var finished = false
        metronome.onCountInFinished = { finished = true }

        session.start(metronome: metronome, countIn: true, metronomeOn: false)

        XCTAssertEqual(session.phase, .performing, "开关 OFF 时不该有预备拍")
        XCTAssertEqual(metronome.countInBeatsRemaining, 0, "不打预备拍")
        XCTAssertFalse(finished, "不该触发预备拍结束回调")
        metronome.stop()
    }

    /// 开关 ON + 循环设置也开着预备拍 → 进 .counting，打满正好 4 拍后正好一次回调。
    @MainActor
    func testMetronomeOnKeepsCountIn() throws {
        let session = makeSession()
        let metronome = MetronomeService()
        var clicks = 0
        var finishCount = 0
        let countInDone = expectation(description: "预备拍结束回调")

        metronome.onBeat = { clicks += 1 }
        metronome.onCountInFinished = {
            finishCount += 1
            session.beginPerforming()
            countInDone.fulfill()
        }

        session.start(metronome: metronome, countIn: true, metronomeOn: true)

        // 无条件：阶段语义与音频宿主无关
        XCTAssertEqual(session.phase, .counting, "开关 ON 且预备拍设置 ON → 进 .counting")

        try requireAudioHost(metronome)

        // 72 BPM：4 拍 ≈ 3.4s，10s 是充裕余量
        wait(for: [countInDone], timeout: 10)

        XCTAssertEqual(clicks, 4, "一小节 = 4 拍，click 数必须正好 4")
        XCTAssertEqual(finishCount, 1, "onCountInFinished 必须在第 4 拍后正好触发一次")
        XCTAssertEqual(metronome.countInBeatsRemaining, 0, "回调后预备拍耗尽")
        XCTAssertEqual(session.phase, .performing, "回调驱动进入演奏")
        metronome.stop()
    }

    /// 循环设置里关掉预备拍 → 即使开关 ON 也直接进演奏。
    @MainActor
    func testCountInSettingOffGoesStraightToPerforming() {
        let session = makeSession()
        session.loopConfig.countIn = false
        let metronome = MetronomeService()

        session.start(metronome: metronome, countIn: true, metronomeOn: true)

        XCTAssertEqual(session.phase, .performing, "预备拍设置关着 → 无 .counting 阶段")
        metronome.stop()
    }

    /// 核心回归：计数中把开关关掉，必须收尾到 .performing，绝不能卡死在 .counting。
    /// 旧实现在这里调 metronome.stop() 后没有任何东西推进阶段。
    @MainActor
    func testTogglingOffDuringCountInNeverStrandsPhase() {
        let session = makeSession()
        let metronome = MetronomeService()

        session.start(metronome: metronome, countIn: true, metronomeOn: true)
        XCTAssertEqual(session.phase, .counting, "前置：进 .counting")

        session.toggleMetronome(on: false, metronome: metronome)

        XCTAssertEqual(session.phase, .performing, "计数中关开关必须收尾到 .performing，不能卡死")
        XCTAssertEqual(metronome.countInBeatsRemaining, 0, "预备拍已收尾")
        metronome.stop()
    }

    /// 计数中把开关打开：重打一小节（正好 4 拍），阶段保持 .counting 直到重打结束。
    @MainActor
    func testTogglingOnDuringCountInRestartsCountIn() throws {
        let session = makeSession()
        let metronome = MetronomeService()
        var clicks = 0
        var finishCount = 0
        let countInDone = expectation(description: "重打一小节后预备拍结束")

        metronome.onBeat = { clicks += 1 }
        metronome.onCountInFinished = {
            finishCount += 1
            session.beginPerforming()
            countInDone.fulfill()
        }

        session.start(metronome: metronome, countIn: true, metronomeOn: true)
        XCTAssertEqual(session.phase, .counting, "前置：进 .counting")

        // 计数中再开：metronome.start 重打一小节（首拍同步响，上一轮计数作废）
        clicks = 0       // 必须在 toggle 之前清零：重启的第 1 拍在 toggle→start→scheduleNextBeat 内同步触发
        finishCount = 0
        session.toggleMetronome(on: true, metronome: metronome)
        XCTAssertEqual(session.phase, .counting, "计数中开开关 → 重打一小节，阶段不变")
        // 关键：toggleMetronome(.counting,on:true) 内部会把 metronome.onCountInFinished 重写为
        // 它自己的 beginPerforming 闭包（PracticeSession.swift:124），覆盖掉上面 line126 装的测试回调。
        // 故必须在 toggle 之后重新安装测试回调，否则 expectation 永不 fulfill（曾误判为生产 bug）。
        metronome.onCountInFinished = {
            finishCount += 1
            session.beginPerforming()
            countInDone.fulfill()
        }

        try requireAudioHost(metronome)

        wait(for: [countInDone], timeout: 10)

        XCTAssertEqual(clicks, 4, "重打后又是正好 4 拍")
        XCTAssertEqual(finishCount, 1, "重打后 onCountInFinished 正好触发一次")
        XCTAssertEqual(session.phase, .performing, "重打结束后进演奏")
        metronome.stop()
    }

    /// 演奏中开关 OFF → 立刻静音；再开 → 恢复常拍。对应 S11 spec「开关即响/即停」。
    @MainActor
    func testTogglingDuringPerformingStartsAndStops() {
        let session = makeSession()
        let metronome = MetronomeService()
        session.start(metronome: metronome, countIn: true, metronomeOn: false)
        XCTAssertEqual(session.phase, .performing, "前置：开关 OFF 直接进演奏")
        XCTAssertFalse(metronome.isRunning, "前置：不应有节拍器在跑")

        session.toggleMetronome(on: true, metronome: metronome)
        // countInBeatsRemaining 在 start() 里、引擎 guard 之前就置 0，故与宿主无关
        XCTAssertEqual(metronome.countInBeatsRemaining, 0, "演奏中开启走常拍，不再打预备拍")

        session.toggleMetronome(on: false, metronome: metronome)
        XCTAssertFalse(metronome.isRunning, "关开关即停")
        metronome.stop()
    }
}

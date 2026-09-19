import XCTest
@testable import PianoSempai

/// 节拍器安全性与 S12 预备拍语义：
/// 测试宿主可能无音频输出 → start 必须是安全 no-op（不崩溃）；
/// 音频可用时断言图已连接 + 预备拍 1 小节 = 4 拍后回调。
final class MetronomeServiceTests: XCTestCase {

    @MainActor
    func testStartThenStopDoesNotCrash() {
        let metronome = MetronomeService()
        metronome.start(bpm: 120, countInBars: 0)
        if metronome.isRunning {
            XCTAssertTrue(metronome.graphConnected, "运行中则音频图必须已连接")
        } else {
            // 无音频宿主：start 是安全 no-op
            XCTAssertFalse(metronome.graphConnected)
        }
        metronome.stop()
        XCTAssertFalse(metronome.isRunning)
        // 二次 stop 依旧安全
        metronome.stop()
        XCTAssertFalse(metronome.isRunning)
        XCTAssertFalse(metronome.graphConnected)
    }

    @MainActor
    func testCountInOneBarIsFourBeatsThenCallback() {
        let metronome = MetronomeService()
        let finished = expectation(description: "预备拍结束回调")
        metronome.onCountInFinished = { finished.fulfill() }

        metronome.start(bpm: 300, countInBars: 1) // 高 BPM 缩短测试等待（4 × 0.2s）
        guard metronome.isRunning else {
            // 无音频宿主：只验证 no-op 安全性，预备拍语义无法驱动（音频相关 CI 验证）
            metronome.stop()
            return
        }
        // 第一拍在 start 内同步打响：4 → 3；总数恒为 4 拍（1 小节）
        let remainingAfterFirstBeat = metronome.countInBeatsRemaining
        XCTAssertTrue((1...3).contains(remainingAfterFirstBeat), "预备拍应在 1–3 之间（首拍已打响）")
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(metronome.countInBeatsRemaining, 0, "回调只在预备拍耗尽后触发")
        metronome.stop()
        // engine.stop() 的图释放经渲染线程，异步完成——稍作让步再断言
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        XCTAssertFalse(metronome.graphConnected, "stop 后音频图已释放")
        metronome.stop()
    }

    @MainActor
    func testStartWithoutCountInGoesStraightToBeats() {
        let metronome = MetronomeService()
        metronome.start(bpm: 120, countInBars: 0)
        guard metronome.isRunning else {
            metronome.stop()
            return
        }
        XCTAssertEqual(metronome.countInBeatsRemaining, 0, "无预备拍直接进入常拍")
        metronome.stop()
    }
}

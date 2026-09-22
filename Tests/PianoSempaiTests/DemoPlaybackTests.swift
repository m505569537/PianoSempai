import XCTest
@testable import PianoSempai
import SheetMusicAudioCore
import SheetMusicCore
import SheetMusicLoader

/// DemoPlaybackService 的音源 gate / 生命周期测试。
///
/// 边界：这里**不验证真出声**（AVAudioEngine 在模拟器测试宿主里不稳定，且无法断言"听见了"）。
/// 真出声留给 Stage B 的端到端 + 用户真机听验。这里只锁定设计文档里的硬约束：
/// 1. 无音源 → availability=.unavailable、prepare throw、playWhole 安全 no-op（绝不碰引擎 prepare）。
/// 2. teardown 后所有入口幂等安全。
/// 3. 有音源（注入假 URL）→ gate 判 ready，但本测试不触发播放。
@MainActor
final class DemoPlaybackTests: XCTestCase {

    /// 从测试宿主（PianoSempai.app）Bundle 加载一份真实内置谱，仅作参数载体。
    private func bundledScore() throws -> Score {
        guard let url = BundledScore.url(book: "拜厄", number: 1) else {
            throw XCTSkip("测试宿主 Bundle 缺内置谱，跳过")
        }
        return try ScoreLoader.loadScore(contentsOf: url)
    }

    func testUnavailableWhenNoSoundfont() {
        let svc = DemoPlaybackService(resolver: BundledSoundfontResolver(url: nil))
        XCTAssertEqual(svc.availability, .unavailable)
    }

    func testPrepareThrowsWhenSoundfontMissing() throws {
        let svc = DemoPlaybackService(resolver: BundledSoundfontResolver(url: nil))
        let score = try bundledScore()
        XCTAssertThrowsError(try svc.prepare(score: score)) { error in
            XCTAssertEqual(error as? DemoPlaybackService.DemoError, .soundfontUnavailable)
        }
    }

    func testPlayWholeIsSafeNoOpWhenSoundfontMissing() throws {
        let svc = DemoPlaybackService(resolver: BundledSoundfontResolver(url: nil))
        let score = try bundledScore()

        svc.playWhole(score: score)
        // 无音源：引擎不应进入播放/暂停，保持 stopped（核心防线——绝不在 nil URL 下 prepare）。
        XCTAssertEqual(svc.state, .stopped)
        XCTAssertNil(svc.currentCursor)
    }

    func testResumeIsSafeNoOpWhenSoundfontMissing() throws {
        let svc = DemoPlaybackService(resolver: BundledSoundfontResolver(url: nil))
        svc.resume(score: try bundledScore())
        XCTAssertEqual(svc.state, .stopped)
    }

    func testReadyWhenSoundfontPresent() {
        let fake = URL(fileURLWithPath: "/tmp/fake.sf2")
        let svc = DemoPlaybackService(resolver: BundledSoundfontResolver(url: fake))
        XCTAssertEqual(svc.availability, .ready)
    }

    func testEntriesAreSafeAfterTeardown() throws {
        let svc = DemoPlaybackService(resolver: BundledSoundfontResolver(url: nil))
        let score = try bundledScore()

        svc.teardown()
        svc.teardown() // 幂等，不应崩
        // teardown 后全部入口必须是 no-op，不抛、不崩。
        svc.playWhole(score: score)
        svc.resume(score: score)
        svc.pauseOrStop()
        svc.stop()
        // teardown 后 prepare 仍安全（nil 音源本就 throw；这里只确认不崩）。
        XCTAssertThrowsError(try svc.prepare(score: score))
    }

    func testPauseOrStopDoesNotStartWhenStopped() throws {
        // stopped 状态下按「示范」= stop（回卷），状态必须仍是 stopped，不能误启动。
        let svc = DemoPlaybackService(resolver: BundledSoundfontResolver(url: nil))
        svc.pauseOrStop()
        XCTAssertEqual(svc.state, .stopped)
    }

    // MARK: - 节拍器真值必须压到引擎 mixer（回归：UI 显示关、播放却响 click）

    func testMetronomeChannelMutedByDefaultAfterPrepare() throws {
        // 用真实内置音源 resolver（gate=ready），prepare 会同步建立 mixer 通道（不依赖 SF2 后台加载完成）。
        let svc = DemoPlaybackService(referenceBpm: 72)
        XCTAssertEqual(svc.availability, .ready, "测试宿主缺内置音源时此用例不成立")
        let score = try bundledScore()
        try svc.prepare(score: score)

        // 默认节拍器关：引擎 metronome 通道必须真的是静音态——否则播放路径会让 click 响。
        XCTAssertEqual(svc.metronomeChannelIsMuted, true)
        XCTAssertFalse(svc.metronomeEnabled)
    }

    func testMetronomeToggleReflectsOnEngineChannel() throws {
        let svc = DemoPlaybackService(referenceBpm: 72)
        let score = try bundledScore()
        try svc.prepare(score: score)

        svc.setMetronome(true)
        XCTAssertEqual(svc.metronomeChannelIsMuted, false)
        XCTAssertTrue(svc.metronomeEnabled)

        // 用户报告的关键路径：on → off 后通道必须回到静音，不需要切两次。
        svc.setMetronome(false)
        XCTAssertEqual(svc.metronomeChannelIsMuted, true)
        XCTAssertFalse(svc.metronomeEnabled)
    }
}

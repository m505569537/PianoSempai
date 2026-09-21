import XCTest
@testable import PianoSempai

/// 详情页练习 CTA 纯决策（S09 / M5b 延伸）：无谱条目（车尔尼599）开放自由弹奏，
/// 锁定只禁掉可判分的练习入口。断言纯函数，不依赖视图/SwiftData。
final class PracticeCTATests: XCTestCase {

    private func scoreFile() -> ScoreFile {
        ScoreFile(kind: "musicxml", fileURL: "scores/cta-\(UUID().uuidString).musicxml",
                  title: "CTA", canFollow: true)
    }

    // MARK: A 文案

    func testTitleUnavailableIsFreePlayEvenWhenLocked() {
        // 599 全部锁定：锁定文案必须让位给自由弹奏（自由弹奏不打分、不推进路线）
        XCTAssertEqual(PracticeCTA.title(availability: .unavailable, isLocked: true), "自由弹奏（不判分）")
        XCTAssertEqual(PracticeCTA.title(availability: .unavailable, isLocked: false), "自由弹奏（不判分）")
    }

    func testTitleUnlockedScoredAndSample() {
        XCTAssertEqual(PracticeCTA.title(availability: .realScore(scoreFile()), isLocked: false), "开始练习")
        XCTAssertEqual(
            PracticeCTA.title(availability: .bundledScore(book: "拜厄", number: 1), isLocked: false), "开始练习")
        XCTAssertEqual(
            PracticeCTA.title(availability: .bundledScore(book: "哈农", number: 20), isLocked: false), "开始练习")
        XCTAssertEqual(PracticeCTA.title(availability: .samplePiece, isLocked: false), "开始练习（示例曲）")
    }

    func testTitleLockedScoredBeatsPracticeText() {
        // 未到达的拜厄/哈农条目：保持原锁定引导，不因为 599 改动而失锁
        XCTAssertEqual(
            PracticeCTA.title(availability: .bundledScore(book: "拜厄", number: 30), isLocked: true), "路线到达后解锁")
        XCTAssertEqual(
            PracticeCTA.title(availability: .realScore(scoreFile()), isLocked: true), "路线到达后解锁")
        XCTAssertEqual(PracticeCTA.title(availability: .samplePiece, isLocked: true), "路线到达后解锁")
    }

    // MARK: B 可点性

    func testEnabledUnavailableAlwaysEnabled() {
        // 无谱 → 自由弹奏无害：锁定也放行（按钮不能再是 disabled）
        XCTAssertTrue(PracticeCTA.isEnabled(availability: .unavailable, isLocked: true))
        XCTAssertTrue(PracticeCTA.isEnabled(availability: .unavailable, isLocked: false))
    }

    func testEnabledLockedScoredDisabled() {
        let real: ScoreAvailability = .realScore(scoreFile())
        XCTAssertFalse(PracticeCTA.isEnabled(availability: real, isLocked: true))
        XCTAssertFalse(
            PracticeCTA.isEnabled(availability: .bundledScore(book: "哈农", number: 5), isLocked: true))
        XCTAssertFalse(PracticeCTA.isEnabled(availability: .samplePiece, isLocked: true))
    }

    func testEnabledUnlockedScoredEnabled() {
        let real: ScoreAvailability = .realScore(scoreFile())
        XCTAssertTrue(PracticeCTA.isEnabled(availability: real, isLocked: false))
        XCTAssertTrue(
            PracticeCTA.isEnabled(availability: .bundledScore(book: "拜厄", number: 1), isLocked: false))
        XCTAssertTrue(PracticeCTA.isEnabled(availability: .samplePiece, isLocked: false))
    }

    // MARK: C 接真实目录（不造假数据：599 每条都 locked + unavailable）

    /// 目录里车尔尼599 每条都是「锁定 + 无谱」→ 文案自由弹奏、按钮可点
    func testEvery599EntryOffersEnabledFreePlay() {
        let entries = CatalogLoader.loadBuiltin().filter { $0.book == "车尔尼599" }
        XCTAssertFalse(entries.isEmpty, "目录应有 599 锁定占位条目")
        for entry in entries {
            let locked = CourseEngine.catalogStatus(
                book: entry.book, number: entry.number, pathState: CoursePathState()
            ) == .locked
            let availability = ScoreAvailability.resolve(
                scoreFile: nil, isSampleEntry: entry.isSample,
                bundledBook: entry.book, bundledNumber: entry.number
            )
            XCTAssertEqual(availability, .unavailable, "\(entry.title) 无内置谱，不应冒充")
            XCTAssertTrue(locked, "\(entry.title) 599 P1 全部锁定")
            XCTAssertEqual(PracticeCTA.title(availability: availability, isLocked: locked), "自由弹奏（不判分）")
            XCTAssertTrue(PracticeCTA.isEnabled(availability: availability, isLocked: locked))
        }
    }

    /// 拜厄/哈农行为不变：未到达条目仍禁用 + 解锁引导；已到达条目正常练习
    func testBeyerAndHanonEntriesUnchanged() {
        let fresh = CoursePathState(currentBeyer: 1, currentHanon: 1)
        let locked = CatalogEntry(book: "拜厄", number: 5, referenceTempo: 72)
        let practicing = CatalogEntry(book: "哈农", number: 1, referenceTempo: 60)

        for (entry, pathState) in [(locked, fresh), (practicing, fresh)] {
            let isLocked = CourseEngine.catalogStatus(
                book: entry.book, number: entry.number, pathState: pathState
            ) == .locked
            let availability = ScoreAvailability.resolve(
                scoreFile: nil, isSampleEntry: false,
                bundledBook: entry.book, bundledNumber: entry.number
            )
            XCTAssertEqual(availability, .bundledScore(book: entry.book, number: entry.number))
            if isLocked {
                XCTAssertEqual(PracticeCTA.title(availability: availability, isLocked: true), "路线到达后解锁")
                XCTAssertFalse(PracticeCTA.isEnabled(availability: availability, isLocked: true))
            } else {
                XCTAssertEqual(PracticeCTA.title(availability: availability, isLocked: false), "开始练习")
                XCTAssertTrue(PracticeCTA.isEnabled(availability: availability, isLocked: false))
            }
        }
    }

    // MARK: D 路由（fullScreenCover(item:) 需要稳定且互不相同的 id）

    /// 两个去向 id 必须稳定且不同，否则 item: 路由会互相吞（PracticeRoute 收口单 cover）
    func testRouteIDsAreStableAndDistinct() {
        XCTAssertEqual(PracticeRoute.practice.id, "practice")
        XCTAssertEqual(PracticeRoute.freePlay.id, "freePlay")
        XCTAssertNotEqual(PracticeRoute.practice.id, PracticeRoute.freePlay.id)
    }
}

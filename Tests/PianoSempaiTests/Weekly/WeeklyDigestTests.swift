import Foundation
import SwiftData
import XCTest

@testable import PianoSempai

/// M7.2 周报聚合 + 文案（PRD M9 有效练习口径；数字全部来自真实 take，0 数据周如实显示）。
@MainActor
final class WeeklyDigestTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    /// 固定「现在」：2026-09-23（周三）12:00；本周 = 09-21（周一）~ 09-27（周日）
    private var now: Date!
    private var monday: Date!
    private var sunday: Date!
    private var nextMonday: Date!
    private var lastSunday: Date!

    private let pieceAId = UUID()
    private let pieceBId = UUID()

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Take.self, Piece.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)

        let formatter = DateFormatter()
        formatter.calendar = WeekCalendar.calendar
        formatter.timeZone = WeekCalendar.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        monday = formatter.date(from: "2026-09-21 00:00:00")!
        sunday = formatter.date(from: "2026-09-27 23:59:59")!
        nextMonday = formatter.date(from: "2026-09-28 00:00:00")!
        lastSunday = formatter.date(from: "2026-09-20 23:59:59")!
        now = formatter.date(from: "2026-09-23 12:00:00")!
    }

    override func tearDown() {
        container = nil
        context = nil
    }

    // MARK: 夹具

    private func makePiece(_ id: UUID, _ title: String) -> Piece {
        Piece(entityId: id, title: title, book: "拜厄", number: 45)
    }

    private func makeTake(
        at date: Date,
        durationSec: Int,
        hasMidi: Bool = true,
        isFreePlay: Bool = false,
        pieceId: UUID? = nil,
        title: String = ""
    ) -> Take {
        Take(
            startedAt: date,
            durationSec: durationSec,
            taskType: isFreePlay ? "free" : "main",
            hasMidi: hasMidi,
            isFreePlay: isFreePlay,
            pieceId: pieceId,
            title: title
        )
    }

    private func build(goal: Int = 3, now: Date? = nil) -> WeeklyDigest {
        let takes = (try? context.fetch(FetchDescriptor<Take>())) ?? []
        let pieces = (try? context.fetch(FetchDescriptor<Piece>())) ?? []
        return WeeklyDigestBuilder.build(takes: takes, pieces: pieces, goal: goal, now: now ?? self.now)
    }

    /// 标准一周：4 次有效 / 6 条 take（含 1 无 MIDI、1 条 599 秒；周界内外各 1 条）
    private func seedStandardWeek() {
        context.insert(makePiece(pieceAId, "拜厄 45"))
        context.insert(makePiece(pieceBId, "小星星"))
        context.insert(makeTake(at: monday.addingTimeInterval(10 * 3600), durationSec: 900, pieceId: pieceAId))
        context.insert(makeTake(at: monday.addingTimeInterval(24 * 3600 + 19 * 3600), durationSec: 1200, hasMidi: false, pieceId: pieceAId))
        context.insert(makeTake(at: monday.addingTimeInterval(2 * 24 * 3600 + 8 * 3600), durationSec: 599, pieceId: nil))
        context.insert(makeTake(at: monday.addingTimeInterval(3 * 24 * 3600 + 20 * 3600), durationSec: 600, pieceId: pieceAId))
        context.insert(makeTake(at: monday.addingTimeInterval(4 * 24 * 3600 + 21 * 3600), durationSec: 700, isFreePlay: true, pieceId: pieceBId, title: "随便弹弹"))
        context.insert(makeTake(at: sunday, durationSec: 800, pieceId: pieceAId))
        // 界外：下周一 00:00 与上周日 23:59
        context.insert(makeTake(at: nextMonday, durationSec: 1800, pieceId: pieceBId))
        context.insert(makeTake(at: lastSunday, durationSec: 1800, pieceId: pieceAId))
        try? context.save()
    }

    // MARK: 有效口径

    func testStandardWeekCountsValidSessionsOnly() {
        seedStandardWeek()
        let digest = build()
        XCTAssertEqual(digest.weekKey, "2026-09-21")
        XCTAssertEqual(digest.sessions, 4, "有效 = 有 MIDI 且 ≥600 秒（900/600/700/800）")
        XCTAssertEqual(digest.totalDurationSec, 900 + 600 + 700 + 800)
        XCTAssertEqual(digest.takeCount, 6, "本周全部 take（含无效）")
        XCTAssertEqual(digest.goalMet, true)
        XCTAssertEqual(digest.topPieceTitle, "拜厄 45")
    }

    func testNoMidiAnd599SecondsNotCounted() {
        context.insert(makeTake(at: monday.addingTimeInterval(3600), durationSec: 1200, hasMidi: false))
        context.insert(makeTake(at: monday.addingTimeInterval(7200), durationSec: 599))
        let digest = build()
        XCTAssertEqual(digest.sessions, 0)
        XCTAssertEqual(digest.totalDurationSec, 0)
        XCTAssertEqual(digest.takeCount, 2)
    }

    func testExactly600SecondsCounts() {
        context.insert(makeTake(at: monday.addingTimeInterval(3600), durationSec: 600))
        XCTAssertEqual(build().sessions, 1)
        XCTAssertEqual(build().totalDurationSec, 600)
    }

    func testFreePlayWithMidiCounts() {
        context.insert(makeTake(at: monday.addingTimeInterval(3600), durationSec: 700, isFreePlay: true))
        let digest = build()
        XCTAssertEqual(digest.sessions, 1, "自由弹奏有 MIDI 且 ≥10 分钟也计（PRD M9）")
        XCTAssertNil(digest.topPieceTitle, "无 pieceId 不编造曲目")
    }

    func testTotalDurationOnlySumsValidTakes() {
        seedStandardWeek()
        let digest = build()
        XCTAssertEqual(digest.totalDurationSec, 3000, "无效 take（1200 无 MIDI / 599 秒）不计时长")
    }

    // MARK: 周区间边界

    func testWeekBoundaryIncludesSundayLastMinuteExcludesNextMonday() {
        seedStandardWeek()
        let digest = build()
        // 界外两条（下周一 1800s、上周日 1800s）不影响任何数字
        XCTAssertEqual(digest.sessions, 4)
        XCTAssertEqual(digest.totalDurationSec, 3000)
        XCTAssertEqual(digest.takeCount, 6)
    }

    func testTakeJustBeforeMondayCountsForPreviousWeek() {
        context.insert(makeTake(at: lastSunday, durationSec: 900))
        let digest = build()
        XCTAssertEqual(digest.sessions, 0)
        XCTAssertEqual(digest.takeCount, 0)
        XCTAssertEqual(digest.weekKey, "2026-09-21")
    }

    func testTakeAtNextMondayCountsForNextWeek() {
        context.insert(makeTake(at: nextMonday, durationSec: 900))
        let digest = build()
        XCTAssertEqual(digest.sessions, 0)
        XCTAssertEqual(digest.weekKey, "2026-09-21")
        // 用「下周一」当 now 时它进入新的一周
        let nextDigest = build(now: nextMonday)
        XCTAssertEqual(nextDigest.weekKey, "2026-09-28")
        XCTAssertEqual(nextDigest.sessions, 1)
    }

    // MARK: 目标与曲目

    func testGoalMetTrueAndFalse() {
        seedStandardWeek()
        XCTAssertTrue(build(goal: 3).goalMet)
        XCTAssertTrue(build(goal: 4).goalMet, "4 次 ≥ 目标 4")
        XCTAssertFalse(build(goal: 5).goalMet)
    }

    func testTopPieceIsMostPracticed() {
        seedStandardWeek()
        XCTAssertEqual(build().topPieceTitle, "拜厄 45", "pieceA 3 次 > pieceB 1 次")
    }

    func testTopPieceTieBreaksByMostRecent() {
        context.insert(makePiece(pieceAId, "拜厄 45"))
        context.insert(makePiece(pieceBId, "小星星"))
        context.insert(makeTake(at: monday.addingTimeInterval(3600), durationSec: 900, pieceId: pieceAId))
        context.insert(makeTake(at: monday.addingTimeInterval(2 * 24 * 3600), durationSec: 600, pieceId: pieceBId))
        XCTAssertEqual(build().topPieceTitle, "小星星", "并列取最近一次")
    }

    func testTopPieceNilPieceIdNotFabricated() {
        context.insert(makePiece(pieceAId, "拜厄 45"))
        context.insert(makeTake(at: monday.addingTimeInterval(3600), durationSec: 900, pieceId: nil))
        XCTAssertNil(build().topPieceTitle)
    }

    func testTopPieceUnknownPieceIdNotFabricated() {
        context.insert(makeTake(at: monday.addingTimeInterval(3600), durationSec: 900, pieceId: UUID()))
        XCTAssertNil(build().topPieceTitle)
    }

    func testTopPieceEmptyTitleNotFabricated() {
        context.insert(makePiece(pieceAId, ""))
        context.insert(makeTake(at: monday.addingTimeInterval(3600), durationSec: 900, pieceId: pieceAId))
        XCTAssertNil(build().topPieceTitle)
    }

    // MARK: 文案：通知

    func testNotificationTitleNeverEmpty() {
        let zero = WeeklyDigest(weekKey: "2026-09-21", weekStart: monday, sessions: 0, totalDurationSec: 0, takeCount: 0, goal: 3, goalMet: false, topPieceTitle: nil, items: [])
        XCTAssertEqual(DigestText.notificationTitle(zero), "本周练了 0 次")
        XCTAssertFalse(DigestText.weeklyReportNoteTitle(zero).isEmpty)
    }

    func testNotificationBodyZeroSessionsHasNoDurationLine() {
        let digest = WeeklyDigest(weekKey: "2026-09-21", weekStart: monday, sessions: 0, totalDurationSec: 0, takeCount: 0, goal: 3, goalMet: false, topPieceTitle: nil, items: [])
        XCTAssertEqual(
            DigestText.notificationBody(digest),
            "距离周目标还差 3 次，10 分钟也算数，下周回来从复习池旧条目开始，不用从头补"
        )
    }

    func testNotificationBodyNotMet() {
        let digest = WeeklyDigest(weekKey: "2026-09-21", weekStart: monday, sessions: 2, totalDurationSec: 1500, takeCount: 3, goal: 3, goalMet: false, topPieceTitle: nil, items: [])
        XCTAssertEqual(
            DigestText.notificationBody(digest),
            "共 25 分，距离周目标还差 1 次，10 分钟也算数，下周争取练满 3 次"
        )
    }

    func testNotificationBodyMetWithPiece() {
        let digest = WeeklyDigest(weekKey: "2026-09-21", weekStart: monday, sessions: 4, totalDurationSec: 3000, takeCount: 6, goal: 3, goalMet: true, topPieceTitle: "拜厄 45", items: [])
        XCTAssertEqual(
            DigestText.notificationBody(digest),
            "共 50 分，周目标 3 次达成 ✓，下周可以继续练《拜厄 45》"
        )
    }

    func testNotificationBodyMetWithoutPiece() {
        let digest = WeeklyDigest(weekKey: "2026-09-21", weekStart: monday, sessions: 4, totalDurationSec: 7400, takeCount: 4, goal: 3, goalMet: true, topPieceTitle: nil, items: [])
        XCTAssertEqual(
            DigestText.notificationBody(digest),
            "共 2 小时 3 分，周目标 3 次达成 ✓，下周保持这个节奏"
        )
    }

    func testNotificationBodyWholeHoursOmitsZeroMinutes() {
        let digest = WeeklyDigest(weekKey: "2026-09-21", weekStart: monday, sessions: 5, totalDurationSec: 7200, takeCount: 5, goal: 3, goalMet: true, topPieceTitle: nil, items: [])
        XCTAssertTrue(DigestText.notificationBody(digest).hasPrefix("共 2 小时，"))
    }

    func testNotificationBodyNeverNegativeWhenOverGoal() {
        let digest = WeeklyDigest(weekKey: "2026-09-21", weekStart: monday, sessions: 5, totalDurationSec: 1800, takeCount: 5, goal: 3, goalMet: true, topPieceTitle: nil, items: [])
        let body = DigestText.notificationBody(digest)
        XCTAssertFalse(body.contains("-"), "超出目标不得出现负号")
        XCTAssertTrue(body.contains("周目标 3 次达成 ✓"))
    }

    func testNotificationBodyNumbersMatchDigest() {
        seedStandardWeek()
        let digest = build()
        let body = DigestText.notificationBody(digest)
        XCTAssertTrue(body.contains("共 50 分"))
        XCTAssertTrue(body.contains("周目标 3 次达成 ✓"))
        XCTAssertTrue(body.contains("《拜厄 45》"))
    }

    // MARK: 文案：周报笔记正文

    func testWeeklyReportNoteBodyContainsFullTextAndDetails() {
        seedStandardWeek()
        let digest = build()
        let noteBody = DigestText.weeklyReportNoteBody(digest)

        // 至少含通知全文
        XCTAssertTrue(noteBody.contains(DigestText.notificationBody(digest)))
        // 统计区间与口径如实
        XCTAssertTrue(noteBody.contains("统计区间：09-21 至 09-27（周一起始）"))
        XCTAssertTrue(noteBody.contains("有效练习 4 次（有 MIDI 且 ≥10 分钟）"))
        XCTAssertTrue(noteBody.contains("本周共 6 条 take"))
        // 明细：日期 + 真实标题 + 时长（周几标签）
        XCTAssertTrue(noteBody.contains("· 09-21（一）拜厄 45 · 15 分钟"))
        XCTAssertTrue(noteBody.contains("· 09-24（四）拜厄 45 · 10 分钟"))
        XCTAssertTrue(noteBody.contains("· 09-25（五）小星星 · 11 分钟"))
        XCTAssertTrue(noteBody.contains("· 09-27（日）拜厄 45 · 13 分钟"))
    }

    func testWeeklyReportNoteBodyZeroSessionsIsHonest() {
        context.insert(makeTake(at: monday.addingTimeInterval(3600), durationSec: 300))
        let digest = build()
        let noteBody = DigestText.weeklyReportNoteBody(digest)
        XCTAssertTrue(noteBody.contains("本周没有有效练习（有 MIDI 且 ≥10 分钟）"))
        XCTAssertTrue(noteBody.contains("本周共 1 条 take"))
        XCTAssertFalse(noteBody.contains("练习明细"))
        XCTAssertTrue(noteBody.contains(DigestText.notificationBody(digest)))
    }

    func testNotificationIdentifierIsPerWeek() {
        XCTAssertEqual(
            WeeklyDigest.notificationIdentifier(weekKey: "2026-09-21"),
            "weekly-digest.2026-09-21"
        )
        XCTAssertNotEqual(
            WeeklyDigest.notificationIdentifier(weekKey: "2026-09-21"),
            WeeklyDigest.notificationIdentifier(weekKey: "2026-09-28")
        )
    }
}

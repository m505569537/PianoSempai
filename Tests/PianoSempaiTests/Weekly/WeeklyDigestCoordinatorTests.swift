import Foundation
import SwiftData
import XCTest

@testable import PianoSempai

/// M7.2 周报协调器：周中排期（一条、内容随练习更新）、周日 21:00 后落库去重、
/// 全关移除排期、未授权静默跳过。Fake 调度 + 内存库 + 固定 now。
@MainActor
final class WeeklyDigestCoordinatorTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var fake: FakeNotificationScheduling!
    private var coordinator: WeeklyDigestCoordinator!

    private let weekKey = "2026-09-21"
    private var notificationId: String { WeeklyDigest.notificationIdentifier(weekKey: weekKey) }

    /// 固定「现在」：周三 12:00（周日 21:00 之前）
    private var midWeekNow: Date!
    /// 周日 21:01（通知时刻已过）
    private var afterFireNow: Date!
    private var monday: Date!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: AppSettings.self, Take.self, Piece.self, PracticeNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        fake = FakeNotificationScheduling()

        let formatter = DateFormatter()
        formatter.calendar = WeekCalendar.calendar
        formatter.timeZone = WeekCalendar.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        monday = formatter.date(from: "2026-09-21 00:00:00")!
        midWeekNow = formatter.date(from: "2026-09-23 12:00:00")!
        afterFireNow = formatter.date(from: "2026-09-27 21:01:00")!

        coordinator = WeeklyDigestCoordinator(scheduler: fake, context: context, now: { self.midWeekNow })
    }

    override func tearDown() {
        coordinator = nil
        fake = nil
        container = nil
        context = nil
    }

    // MARK: 夹具

    private func validTake(at offset: TimeInterval, durationSec: Int = 900) {
        context.insert(Take(
            startedAt: monday.addingTimeInterval(offset),
            durationSec: durationSec,
            taskType: "main",
            hasMidi: true
        ))
        try? context.save()
    }

    private func weeklyReportNotes() throws -> [PracticeNote] {
        let notes = try context.fetch(FetchDescriptor<PracticeNote>())
        return notes.filter { $0.kind == "weeklyReport" }
    }

    private func allNotes() throws -> [PracticeNote] {
        try context.fetch(FetchDescriptor<PracticeNote>())
    }

    // MARK: 周中：只排期，不落库

    func testMidWeekSchedulesSingleRequest() async throws {
        validTake(at: 3600)
        await coordinator.refresh()

        XCTAssertEqual(fake.pending.count, 1)
        XCTAssertEqual(fake.pending[notificationId]?.title, "本周练了 1 次")
        XCTAssertEqual(fake.pending[notificationId]?.fireComponents.weekday, 1)
        XCTAssertEqual(fake.pending[notificationId]?.fireComponents.hour, 21)
        let notes = try weeklyReportNotes()
        XCTAssertTrue(notes.isEmpty, "周中不落库")
    }

    func testMidWeekRefreshUpdatesContentButKeepsSingleRequest() async throws {
        validTake(at: 3600)
        await coordinator.refresh()
        XCTAssertEqual(fake.pending[notificationId]?.title, "本周练了 1 次")

        // 又练了一次（后台会再刷新）
        validTake(at: 2 * 3600)
        await coordinator.refresh()

        XCTAssertEqual(fake.pending.count, 1, "一周一条：覆盖更新不新增")
        XCTAssertEqual(fake.pending[notificationId]?.title, "本周练了 2 次")
        let notes = try weeklyReportNotes()
        XCTAssertTrue(notes.isEmpty)
    }

    func testUnauthorizedSilentlySkipsScheduling() async throws {
        validTake(at: 3600)

        fake.status = .notDetermined
        await coordinator.refresh()
        XCTAssertTrue(fake.pending.isEmpty, "未授权静默失败：不排期、不报错")

        fake.status = .denied
        await coordinator.refresh()
        XCTAssertTrue(fake.pending.isEmpty)
        let notes = try weeklyReportNotes()
        XCTAssertTrue(notes.isEmpty)
    }

    func testProvisionalAuthorizationStillSchedules() async {
        validTake(at: 3600)
        fake.status = .provisional
        await coordinator.refresh()
        XCTAssertEqual(fake.pending.count, 1)
    }

    // MARK: 周日 21:00 后：落库去重 + 清通知

    func testAfterFireWithDeliveredPersistsOnce() async throws {
        coordinator = WeeklyDigestCoordinator(scheduler: fake, context: context, now: { self.afterFireNow })
        validTake(at: 3600)
        validTake(at: 2 * 3600)
        fake.delivered = [notificationId]

        await coordinator.refresh()

        let notes = try weeklyReportNotes()
        XCTAssertEqual(notes.count, 1, "同一周只落一条")
        XCTAssertEqual(notes[0].weekKey, weekKey)
        XCTAssertEqual(notes[0].status, "open")
        XCTAssertEqual(notes[0].title, "本周练了 2 次")
        XCTAssertTrue(notes[0].body.contains("共 30 分"))
        XCTAssertTrue(fake.pending.isEmpty, "通知时刻已过：移除排期")
        XCTAssertEqual(fake.removeDeliveredCalls, [notificationId], "已送达：从通知中心移除")

        // 再次 refresh（反复进后台）不重复落库
        await coordinator.refresh()
        let repeated = try weeklyReportNotes()
        XCTAssertEqual(repeated.count, 1)
    }

    func testAfterFireWithoutDeliveryStillPersistsNoReschedule() async throws {
        coordinator = WeeklyDigestCoordinator(scheduler: fake, context: context, now: { self.afterFireNow })
        validTake(at: 3600)
        // 手机关机：通知没弹出，delivered 为空

        await coordinator.refresh()

        let notes = try weeklyReportNotes()
        XCTAssertEqual(notes.count, 1, "没送达周报也进 S19 时间线")
        XCTAssertEqual(notes[0].weekKey, weekKey)
        XCTAssertTrue(fake.pending.isEmpty, "不重排通知")
        XCTAssertTrue(fake.removeDeliveredCalls.isEmpty)
    }

    // MARK: 全关

    func testDisabledRemovesPendingAndSkipsEverything() async throws {
        context.insert(AppSettings(weeklyDigestEnabled: false))
        // 之前排过的请求（开关打开时排的）
        try await fake.upsert(identifier: notificationId, title: "旧", body: "旧", fireComponents: WeekCalendar.sundayEveningComponents(from: monday))

        await coordinator.refresh()

        XCTAssertTrue(fake.pending.isEmpty, "全关：移除已排请求")
        let notes = try allNotes()
        XCTAssertTrue(notes.isEmpty, "全关：不落库")
    }

    func testDisabledNeverSchedules() async throws {
        context.insert(AppSettings(weeklyDigestEnabled: false))
        validTake(at: 3600)
        await coordinator.refresh()
        XCTAssertTrue(fake.pending.isEmpty)
        let notes = try allNotes()
        XCTAssertTrue(notes.isEmpty)
    }

    // MARK: 跨周补漏：上周周报本周开 App 时补落 S19

    func testMondayAfterUnopenedSundayCatchesUpPreviousWeek() async throws {
        // 现在 = 新一周周一 12:00（上周日 21:00 通知已送达，但用户当时没开 App）
        let nextMonday = WeekCalendar.calendar.date(byAdding: .day, value: 7, to: monday)!
        coordinator = WeeklyDigestCoordinator(scheduler: fake, context: context, now: { nextMonday })

        // 上周二（相对旧周一 +1 天）有一条有效 take
        context.insert(Take(
            startedAt: monday.addingTimeInterval(86400 + 3600),
            durationSec: 900,
            taskType: "main",
            hasMidi: true
        ))
        let previousWeekKey = weekKey // 2026-09-21
        let previousId = WeeklyDigest.notificationIdentifier(weekKey: previousWeekKey)
        fake.delivered = [previousId]

        await coordinator.refresh()

        let notes = try weeklyReportNotes()
        XCTAssertEqual(notes.count, 1, "周一开 App：上周周报补落 S19，不丢")
        XCTAssertEqual(notes.first?.weekKey, previousWeekKey)
        XCTAssertEqual(fake.removeDeliveredCalls, [previousId], "上周已送达通知被清理")
        // 新一周当前不该有排期被误删/误加之外的副作用：本周一中午会排本周通知
        // （未授权 fake 默认状态见 FakeNotificationScheduling；只断言上周周报存在即可）
    }

    func testCatchUpDoesNotDuplicateAlreadyPersistedPreviousWeek() async throws {
        let nextMonday = WeekCalendar.calendar.date(byAdding: .day, value: 7, to: monday)!
        coordinator = WeeklyDigestCoordinator(scheduler: fake, context: context, now: { nextMonday })
        context.insert(Take(
            startedAt: monday.addingTimeInterval(86400),
            durationSec: 900,
            taskType: "main",
            hasMidi: true
        ))

        // 上周日已经落过一次（模拟同周已 catchup）
        context.insert(PracticeNote(
            kind: "weeklyReport",
            title: "本周练了 1 次",
            body: "x",
            weekKey: weekKey
        ))
        try? context.save()

        await coordinator.refresh()
        let notes = try weeklyReportNotes()
        XCTAssertEqual(notes.count, 1, "已落库的上周周报不重复")
    }

    // MARK: 红线：周报笔记不含任何凭据

    func testWeeklyReportNoteContainsNoSecrets() async throws {
        coordinator = WeeklyDigestCoordinator(scheduler: fake, context: context, now: { self.afterFireNow })
        validTake(at: 3600)
        fake.delivered = [notificationId]
        await coordinator.refresh()

        let note = try XCTUnwrap(try weeklyReportNotes().first)
        for field in [note.title, note.body] {
            let lowered = field.lowercased()
            for needle in ["sk-", "apikey", "api-key", "bearer", "secret", "token", "key"] {
                XCTAssertFalse(lowered.contains(needle), "周报不得含凭据字样：\(needle)")
            }
        }
    }
}

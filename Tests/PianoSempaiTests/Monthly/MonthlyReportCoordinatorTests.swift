import Foundation
import SwiftData
import XCTest

@testable import PianoSempai

/// M7.2 月报协调器：每月 1 号为上月起草（幂等）、观察回填 ok/failed、retryObservation、
/// 非起草日且已有月报不重算（快照语义）、只写 MonthlyReport（不碰 Take/DailyPlan/AppSettings）。
/// 假观察服务 + 假 runner + 内存库 + 固定 now：不打网络、不读 Keychain。
@MainActor
final class MonthlyReportCoordinatorTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var fakeService: FakeObservationService!
    private var fakeRunner: FakeMonthlyRunner!

    /// 2026-10-01 10:00（每月 1 号 → 起草 2026-09）
    private var firstOfMonth: Date!
    /// 2026-09-21 12:00（月中，非起草日）
    private var midMonth: Date!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: MonthlyReport.self, Take.self, TakeAnalysis.self, DailyPlan.self, GateEvent.self,
                CoursePathState.self, AppSettings.self, PracticeNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        fakeService = FakeObservationService()
        fakeRunner = FakeMonthlyRunner()

        // 2026-10-01 10:00（每月 1 号 → 起草 2026-09）/ 2026-09-21 12:00（月中，非起草日）
        firstOfMonth = date("2026-10-01 10:00:00")
        midMonth = date("2026-09-21 12:00:00")
    }

    override func tearDown() {
        container = nil
        context = nil
        fakeService = nil
        fakeRunner = nil
    }

    // MARK: 假依赖

    private final class FakeObservationService: MonthlyObservationGenerating {
        private(set) var snapshots: [MonthlyReportSnapshot] = []
        var failure: ProviderChainFailure?
        var title = "转指稳住了"
        var body = "这个月转指的节奏偏差收窄了不少，下月可以开始摸新曲子的前 16 小节。"
        var providerModel = "百炼 qwen3-max"

        func makeObservation(
            snapshot: MonthlyReportSnapshot,
            providers: [AIProvider],
            runner: any MonthlyObservationRunning
        ) async throws -> MonthlyObservation {
            snapshots.append(snapshot)
            if let failure { throw failure }
            return MonthlyObservation(title: title, body: body, providerModel: providerModel)
        }
    }

    private final class FakeMonthlyRunner: MonthlyObservationRunning {
        private(set) var callCount = 0
        func run(providers: [AIProvider], input: ChainInput) async throws -> ChainResult {
            callCount += 1
            return ChainResult(text: "x", providerModel: "假", evidenceRefs: [], attempts: [])
        }
    }

    private final class FakeProviderSource: MonthlyProviderSource {
        func currentProviders() -> [AIProvider] { [] }
    }

    // MARK: 夹具

    private func makeCoordinator(now: Date) -> MonthlyReportCoordinator {
        MonthlyReportCoordinator(
            context: context,
            observationService: fakeService,
            providerSource: FakeProviderSource(),
            runner: fakeRunner,
            now: { now }
        )
    }

    /// 在给定「yyyy-MM-dd」插一条有效 take（有 MIDI、900 秒）
    private func insertValidTake(onDay day: String) {
        let startedAt = date("\(day) 10:00:00")
        context.insert(Take(startedAt: startedAt, durationSec: 900, taskType: "main", hasMidi: true))
        try? context.save()
    }

    /// "yyyy-MM-dd HH:mm:ss"（本地时区，与 MonthlyCalendar 同一套语义）
    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = MonthlyCalendar.calendar
        formatter.timeZone = MonthlyCalendar.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }

    private func reports() -> [MonthlyReport] {
        (try? context.fetch(FetchDescriptor<MonthlyReport>(sortBy: [SortDescriptor(\.periodKey)]))) ?? []
    }

    private func takes() -> [Take] { (try? context.fetch(FetchDescriptor<Take>())) ?? [] }
    private func plans() -> [DailyPlan] { (try? context.fetch(FetchDescriptor<DailyPlan>())) ?? [] }
    private func settings() -> [AppSettings] { (try? context.fetch(FetchDescriptor<AppSettings>())) ?? [] }
    private func notes() -> [PracticeNote] { (try? context.fetch(FetchDescriptor<PracticeNote>())) ?? [] }
    private func pathStates() -> [CoursePathState] { (try? context.fetch(FetchDescriptor<CoursePathState>())) ?? [] }

    // MARK: 每月 1 号起草上月

    func testFirstOfMonthDraftsPreviousMonth() async {
        insertValidTake(onDay: "2026-09-03")
        insertValidTake(onDay: "2026-09-18")
        let coordinator = makeCoordinator(now: firstOfMonth)

        await coordinator.refresh()

        let all = reports()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].periodKey, "2026-09")
        XCTAssertEqual(all[0].takeCount, 2)
        XCTAssertEqual(all[0].validDays, 2)
        XCTAssertEqual(all[0].observationStatus, "ok", "起草后立即回填观察")
        XCTAssertEqual(all[0].observationTitle, "转指稳住了")
        XCTAssertEqual(all[0].observationProviderModel, "百炼 qwen3-max")
        XCTAssertEqual(fakeService.snapshots.count, 1, "只为上月跑一次观察")
    }

    func testRefreshIsIdempotent() async {
        insertValidTake(onDay: "2026-09-03")
        let coordinator = makeCoordinator(now: firstOfMonth)

        await coordinator.refresh()
        await coordinator.refresh()
        await coordinator.refresh()

        XCTAssertEqual(reports().count, 1, "重复 refresh 不重复插库")
        XCTAssertEqual(fakeService.snapshots.count, 1, "已 ok 不重复出网")
    }

    func testMidMonthDraftsWhenPreviousMonthMissing() async {
        // 月中打开 App（用户 9 月才装）：库中尚无 8 月月报 → 补起草
        insertValidTake(onDay: "2026-08-12")
        insertValidTake(onDay: "2026-09-05")
        let coordinator = makeCoordinator(now: midMonth)

        await coordinator.refresh()

        let all = reports()
        XCTAssertEqual(all.map(\.periodKey), ["2026-08"], "只补上月，不顺手建当前月")
    }

    func testEmptyMonthIsNotDrafted() async {
        // 上月（2026-09）一条 take 都没有：不凭空造 0 数据月报（与周报「空周不生成」同口径）
        insertValidTake(onDay: "2026-10-05")
        let coordinator = makeCoordinator(now: firstOfMonth)

        await coordinator.refresh()

        XCTAssertTrue(reports().isEmpty, "空月不落库：S22 对该月显「这个月还没有月报」")
        XCTAssertTrue(fakeService.snapshots.isEmpty, "也不为它白跑一次 AI 调用")
    }

    func testExistingReportIsNotRecomputed() async {
        // 已有一份 8 月月报（统计被人工改过）：快照冻结，refresh 不重算
        context.insert(MonthlyReport(
            periodKey: "2026-08", year: 2026, month: 8, validDays: 99, takeCount: 99,
            observationTitle: "旧观察", observationStatus: "ok"
        ))
        insertValidTake(onDay: "2026-08-12")
        try? context.save()

        await makeCoordinator(now: firstOfMonth).refresh()

        let all = reports()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].validDays, 99, "已有月报不被重算覆盖")
        XCTAssertEqual(all[0].observationTitle, "旧观察")
        XCTAssertTrue(fakeService.snapshots.isEmpty, "已 ok 不再出网")
    }

    // MARK: 观察回填

    func testObservationFailureKeepsStatsAndDoesNotThrow() async {
        insertValidTake(onDay: "2026-09-03")
        fakeService.failure = ProviderChainFailure(attempts: [
            ProviderChainFailure.Attempt(providerId: "ark", providerDisplayName: "方舟", modelId: "m1", errorSummary: "401"),
        ])

        await makeCoordinator(now: firstOfMonth).refresh()

        let all = reports()
        XCTAssertEqual(all.count, 1, "统计照常落库")
        XCTAssertEqual(all[0].periodKey, "2026-09")
        XCTAssertEqual(all[0].takeCount, 1)
        XCTAssertEqual(all[0].observationStatus, "failed", "全链失败只降级状态")
        XCTAssertEqual(all[0].observationTitle, "")
        XCTAssertNil(all[0].observationProviderModel)
    }

    func testRetryObservationFlipsFailedToOk() async {
        insertValidTake(onDay: "2026-09-03")
        fakeService.failure = ProviderChainFailure(attempts: [])
        await makeCoordinator(now: firstOfMonth).refresh()
        XCTAssertEqual(reports()[0].observationStatus, "failed")

        fakeService.failure = nil
        let coordinator = makeCoordinator(now: firstOfMonth)
        await coordinator.retryObservation(for: "2026-09")

        XCTAssertEqual(reports()[0].observationStatus, "ok")
        XCTAssertEqual(reports()[0].observationTitle, "转指稳住了")
        XCTAssertEqual(fakeService.snapshots.count, 2, "首次 + 重试各一次")
    }

    func testRetryObservationForUnknownPeriodDoesNothing() async {
        let coordinator = makeCoordinator(now: firstOfMonth)
        await coordinator.retryObservation(for: "1999-01")
        XCTAssertTrue(reports().isEmpty)
        XCTAssertFalse(coordinator.isRetrying)
    }

    func testDecemberPreviousMonthIsPreviousYear() async {
        // 2027-01-01 → 起草 2026-12（跨年）
        insertValidTake(onDay: "2026-12-20")

        await makeCoordinator(now: date("2027-01-01 09:00:00")).refresh()

        XCTAssertEqual(reports().map(\.periodKey), ["2026-12"])
    }

    // MARK: 红线：只写 MonthlyReport

    func testRefreshDoesNotTouchTakesPlansSettingsPathStateOrNotes() async {
        insertValidTake(onDay: "2026-09-03")
        context.insert(DailyPlan(date: firstOfMonth, warmupCompletedAt: nil))
        context.insert(AppSettings(weeklyGoal: 5))
        context.insert(CoursePathState(currentBeyer: 43, currentHanon: 4, current599: 5, projected599Week: 20))
        try? context.save()

        let takesBefore = takes()
        let plansBefore = plans()
        let settingsBefore = settings()
        let pathsBefore = pathStates()

        await makeCoordinator(now: firstOfMonth).refresh()

        XCTAssertEqual(takes().count, takesBefore.count, "不回写 Take")
        XCTAssertEqual(takes().first?.durationSec, takesBefore.first?.durationSec)
        XCTAssertEqual(plans().count, plansBefore.count, "不回写 DailyPlan")
        XCTAssertEqual(plans().first?.warmupCompletedAt, plansBefore.first?.warmupCompletedAt)
        XCTAssertEqual(settings().first?.weeklyGoal, settingsBefore.first?.weeklyGoal, "不回写 AppSettings")
        XCTAssertEqual(pathStates().first?.currentBeyer, pathsBefore.first?.currentBeyer, "不回写 CoursePathState")
        XCTAssertEqual(pathStates().first?.current599, pathsBefore.first?.current599)
        XCTAssertTrue(notes().isEmpty, "笔记只在用户点按钮时写，协调器不写")
    }

    func testSnapshotUsesRealPathStateValues() async {
        insertValidTake(onDay: "2026-09-03")
        context.insert(CoursePathState(currentBeyer: 43, currentHanon: 4, current599: 5, projected599Week: 20))
        try? context.save()

        await makeCoordinator(now: firstOfMonth).refresh()

        let report = reports()[0]
        XCTAssertEqual(report.beyerCurrent, 43)
        XCTAssertEqual(report.hanonCurrent, 4)
        XCTAssertTrue(report.unlocked599)
        XCTAssertEqual(report.current599, 5)
        XCTAssertEqual(report.projected599Week, 20)
    }

    // MARK: 多缺口：停练一整月后回归，跳过空月补到更早的练习月

    func testMultipleGapMonthsSkipsEmptyAndCatchesUpPracticeMonth() async {
        // 9 月在练（当前月不落库）→ 10 月一整月停练、一次没开 App → 11 月 5 日回归
        insertValidTake(onDay: "2026-09-15")
        let coordinator = makeCoordinator(now: date("2026-11-05 10:00:00"))

        await coordinator.refresh()

        let all = reports()
        XCTAssertEqual(all.map(\.periodKey), ["2026-09"],
                       "紧邻上月 10 月是空月（0 take）应跳过，但必须补回真正有练习的 9 月，不能让其永久丢失")
        XCTAssertEqual(all[0].takeCount, 1)
        XCTAssertEqual(all[0].observationStatus, "ok")
        XCTAssertEqual(fakeService.snapshots.count, 1, "只为有练习的 9 月跑一次观察，不为空 10 月跑")
    }

    func testTwoAdjacentMissingPracticeMonthsBothCaughtUp() async {
        // 8、9 月都练了、都没落库，10 月 1 号才打开：两个月都应补齐（按从近到远）
        insertValidTake(onDay: "2026-08-10")
        insertValidTake(onDay: "2026-09-10")

        await makeCoordinator(now: date("2026-10-01 09:00:00")).refresh()

        XCTAssertEqual(reports().map(\.periodKey), ["2026-08", "2026-09"],
                       "两个相邻缺口练习月都补；幂等重跑不重复")
        XCTAssertEqual(fakeService.snapshots.count, 2)
    }
}

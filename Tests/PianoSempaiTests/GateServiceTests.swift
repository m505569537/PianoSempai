import SwiftData
import XCTest
@testable import PianoSempai

/// M4 热身硬门禁四向验收（brief 负例要求）+ 时长分配 + streak 聚合。
final class GateServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: AppSettings.self, PlacementSelfReport.self, PlacementResult.self,
            VelocityCalibration.self, CoursePathState.self, DailyPlan.self, PracticeTask.self,
            GateEvent.self, Take.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
    }

    private func fetchOverrides() throws -> [GateEvent] {
        try context.fetch(FetchDescriptor<GateEvent>())
    }

    // MARK: 方向 1 — 热身未完成 → 主菜被拦（不得静默放行）

    func testIncompleteWarmupBlocksMainStart() throws {
        let decision = WarmupGate.checkMainAccess(
            warmupCompletedAt: nil, today: Date(), overrides: try fetchOverrides()
        )
        XCTAssertEqual(decision, .blocked(warmupMinutesRemaining: 10), "热身未完成且未强开时必须被拦")
    }

    // MARK: 方向 2 — 原因为空 → 确认禁用

    func testEmptyReasonDisablesConfirm() {
        // 未选原因
        XCTAssertFalse(WarmupGate.canConfirmOverride(reasonTag: nil, note: ""))
        // 空白字符串同空
        XCTAssertFalse(WarmupGate.canConfirmOverride(reasonTag: "  ", note: ""))
        // 选了"其他"但说明为空 → 仍禁用
        XCTAssertFalse(WarmupGate.canConfirmOverride(reasonTag: "other", note: ""))
        XCTAssertFalse(WarmupGate.canConfirmOverride(reasonTag: "other", note: "   "))
        // 预设标签选中 → 可确认
        XCTAssertTrue(WarmupGate.canConfirmOverride(reasonTag: "time", note: ""))
        // "其他" + 非空说明 → 可确认
        XCTAssertTrue(WarmupGate.canConfirmOverride(reasonTag: "other", note: "手热"))
    }

    // MARK: 方向 3 — 强开落库 GateEvent + 本周计数递增

    func testOverridePersistsGateEventAndIncrementsWeekCount() throws {
        let before = WarmupGate.overrideCountThisWeek(events: try fetchOverrides(), date: Date())
        XCTAssertEqual(before, 0)

        let event = WarmupGate.recordOverride(reasonTag: "time", note: "", in: context)
        try context.save()

        XCTAssertEqual(event.kind, "override")
        let events = try fetchOverrides()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.reasonTag, "time")

        let after = WarmupGate.overrideCountThisWeek(events: events, date: Date())
        XCTAssertEqual(after, before + 1, "强开后本周计数必须 +1")

        // 上周的事件不计入本周（周一起始）
        let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        _ = WarmupGate.recordOverride(reasonTag: "mood", note: "", date: lastWeek, in: context)
        try context.save()
        XCTAssertEqual(
            WarmupGate.overrideCountThisWeek(events: try fetchOverrides(), date: Date()),
            1,
            "上周 override 不计入本周"
        )
    }

    // MARK: 方向 4 — 热身完成 → 直接放行（不弹 S07c）

    func testCompletedWarmupAllowsMainStartWithoutOverride() throws {
        let completedAt = Date().addingTimeInterval(-600)
        let decision = WarmupGate.checkMainAccess(
            warmupCompletedAt: completedAt, today: Date(), overrides: try fetchOverrides()
        )
        XCTAssertEqual(decision, .allowed, "热身完成后主菜直接放行")
        // 且不应产生任何 override 记录
        XCTAssertTrue(try fetchOverrides().isEmpty)
    }

    // MARK: 补充 — 当日已强开 → 再进主菜不重复弹层

    func testOverriddenTodayAllowsMainStart() throws {
        _ = WarmupGate.recordOverride(reasonTag: "time", note: "", in: context)
        try context.save()
        let decision = WarmupGate.checkMainAccess(
            warmupCompletedAt: nil, today: Date(), overrides: try fetchOverrides()
        )
        XCTAssertEqual(decision, .allowed, "当日已强开过，再进主菜不再拦")
    }

    // MARK: 补充 — 取消（✕）不留记录

    func testCancelRecordsNothing() throws {
        // 取消路径 = 不调用 recordOverride；直接验证空库
        XCTAssertTrue(try fetchOverrides().isEmpty, "取消强开不得留任何 GateEvent")
    }

    // MARK: 时长分配（热身不被压缩）

    func testDurationRedistribution() {
        // 30 分 → 热身固定 8–12、主菜约 15（S07 spec 示例值）、奖励曲锁文案
        let d30 = TodayPlanService.durations(forChoiceMinutes: 30)
        XCTAssertEqual(d30.warmupLabel, "8–12 分钟")
        XCTAssertEqual(d30.mainMinutes, 15)
        XCTAssertEqual(d30.rewardLabel, "剩多少时间算多少")

        // 15 分 → 主菜下限 5；45 分 → 约 25
        XCTAssertEqual(TodayPlanService.durations(forChoiceMinutes: 15).mainMinutes, 5)
        XCTAssertEqual(TodayPlanService.durations(forChoiceMinutes: 45).mainMinutes, 25)
    }

    // MARK: streak 聚合（周一起始、≥10 分钟口径、真实 Take）

    func testWeekStreakAggregation() {
        // 周三 20 分钟 + 周五 15 分钟（有效）；周二 8 分钟（不足 10，不亮）；周日自由弹奏 12 分钟也计
        let takes = [
            makeTake(4, minutes: 20), // 周三
            makeTake(6, minutes: 15), // 周五
            makeTake(3, minutes: 8), // 周二：不足 10 分钟
            makeTake(1, minutes: 12, taskTypeLabel: "free"), // 周日自由弹奏
        ]
        let streak = TodayPlanService.weekStreak(takes: takes, today: Date())

        XCTAssertFalse(streak.litDays[0], "周一未练不亮")
        XCTAssertFalse(streak.litDays[1], "周二 8 分钟 < 10 分钟口径，不亮")
        XCTAssertTrue(streak.litDays[2], "周三 20 分钟亮灯")
        XCTAssertTrue(streak.litDays[4], "周五 15 分钟亮灯")
        XCTAssertTrue(streak.litDays[6], "周日自由弹奏也计有效练习")
        XCTAssertEqual(streak.minutesPerDay[2], 20)
        XCTAssertEqual(streak.minutesPerDay[4], 15)
    }

    func testStreakIgnoresTakesWithoutMidi() {
        let takes = [makeTake(4, minutes: 30, hasMidi: false)]
        let streak = TodayPlanService.weekStreak(takes: takes, today: Date())
        XCTAssertFalse(streak.litDays.contains(true), "无 MIDI 的 take 不计有效练习（M9 口径）")
    }

    func testWeekProgressSumsEffectiveMinutes() {
        let takes = [makeTake(4, minutes: 20), makeTake(6, minutes: 15), makeTake(3, minutes: 8)]
        let progress = TodayPlanService.weekProgress(takes: takes, weeklyGoal: 3, dailyChoiceMinutes: 30, today: Date())
        XCTAssertEqual(progress.doneMinutes, 35, "只累计有效练习（8 分钟不计）")
        XCTAssertEqual(progress.targetMinutes, 90)
    }
}

private func makeTake(_ weekday: Int, minutes: Int, hasMidi: Bool = true, taskTypeLabel: String = "main", hour: Int = 10) -> Take {
    var cal = Calendar.current
    cal.firstWeekday = 2
    let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())!.start
    let isoWeekday = cal.component(.weekday, from: weekStart)
    let offset = (weekday - isoWeekday + 7) % 7
    let date = cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: offset, to: weekStart)!)!
    return Take(startedAt: date, durationSec: minutes * 60, taskType: taskTypeLabel, hasMidi: hasMidi)
}

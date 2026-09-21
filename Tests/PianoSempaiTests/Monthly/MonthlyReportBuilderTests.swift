import Foundation
import SwiftData
import XCTest

@testable import PianoSempai

/// M7.2 月报聚合（PRD M8 口径 + S22 首屏统计：有效练习/总时长、路线、热身与强开、节奏趋势）。
/// 数字全部来自真实 take/analysis/plan/gate/pathState：缺数据给 nil/0，不编造百分比（红线 1）；
/// Builder 只读输入，不回写任何课程/判分/计划状态（红线 3）。内存 ModelContainer，不碰磁盘。
@MainActor
final class MonthlyReportBuilderTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    /// 固定「现在」2026-09-23（周三）12:00 → 当月 2026-09（9/1 周二 ~ 9/30 周三，共 30 天）
    private var now: Date!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Take.self, TakeAnalysis.self, DailyPlan.self, GateEvent.self, CoursePathState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        now = date("2026-09-23 12:00:00")
    }

    override func tearDown() {
        container = nil
        context = nil
    }

    // MARK: 夹具

    /// "yyyy-MM-dd HH:mm:ss"（本地时区，与 MonthlyCalendar 同一套语义）
    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = MonthlyCalendar.calendar
        formatter.timeZone = MonthlyCalendar.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }

    private func makeTake(at startedAt: Date, durationSec: Int, hasMidi: Bool = true, isFreePlay: Bool = false) -> Take {
        Take(
            startedAt: startedAt,
            durationSec: durationSec,
            taskType: isFreePlay ? "free" : "main",
            hasMidi: hasMidi,
            isFreePlay: isFreePlay
        )
    }

    private func makeAnalysis(takeId: UUID, rhythmScore: Int?, analyzedAt: Date) -> TakeAnalysis {
        TakeAnalysis(takeId: takeId, analyzedAt: analyzedAt, engineVersion: "P2-scoring-1.0", rhythmScore: rhythmScore)
    }

    /// 在各「yyyy-MM-dd」各插一条有效 take（有 MIDI、900 秒），用于构造跨周场景
    private func insertValidTakes(onDays days: [String], durationSec: Int = 900) {
        for day in days {
            context.insert(makeTake(at: date("\(day) 10:00:00"), durationSec: durationSec))
        }
    }

    /// 落库后全量取回，按生产路径喂给 Builder（now 缺省 = 固定「现在」）
    private func build(now: Date? = nil) -> MonthlyReportSnapshot {
        try? context.save()
        let takes = (try? context.fetch(FetchDescriptor<Take>())) ?? []
        let analyses = (try? context.fetch(FetchDescriptor<TakeAnalysis>())) ?? []
        let plans = (try? context.fetch(FetchDescriptor<DailyPlan>())) ?? []
        let gates = (try? context.fetch(FetchDescriptor<GateEvent>())) ?? []
        let pathStates = (try? context.fetch(FetchDescriptor<CoursePathState>())) ?? []
        return MonthlyReportBuilder.build(
            now: now ?? self.now,
            takes: takes,
            analyses: analyses,
            plans: plans,
            gates: gates,
            pathState: pathStates.first
        )
    }

    // MARK: 有效练习口径（与周报同一口径：有 MIDI 且 ≥10 分钟）

    func testValidPracticeRequiresMidiAnd600Seconds() {
        context.insert(makeTake(at: date("2026-09-01 10:00:00"), durationSec: 1200, hasMidi: false)) // 无 MIDI
        context.insert(makeTake(at: date("2026-09-01 12:00:00"), durationSec: 599))                   // 差 1 秒
        context.insert(makeTake(at: date("2026-09-01 14:00:00"), durationSec: 600))                   // 正好 10 分钟
        context.insert(makeTake(at: date("2026-09-01 16:00:00"), durationSec: 700, isFreePlay: true)) // 自由弹奏也计
        let snapshot = build()
        XCTAssertEqual(snapshot.validDays, 1)
        XCTAssertEqual(snapshot.totalDurationSec, 600 + 700)
        XCTAssertEqual(snapshot.takeCount, 4, "takeCount 含无效，如实")
    }

    // MARK: validDays distinct

    func testValidDaysDistinctWithinDayAndAcrossDays() {
        context.insert(makeTake(at: date("2026-09-03 10:00:00"), durationSec: 900))
        context.insert(makeTake(at: date("2026-09-03 21:30:00"), durationSec: 900)) // 同一天第二条
        context.insert(makeTake(at: date("2026-09-04 09:00:00"), durationSec: 900)) // 跨天
        context.insert(makeTake(at: date("2026-09-05 09:00:00"), durationSec: 900, hasMidi: false)) // 无效不添天
        let snapshot = build()
        XCTAssertEqual(snapshot.validDays, 2, "同一天多条有效 take 只算 1 天；无效 take 不计天数")
    }

    // MARK: 总时长与 takeCount

    func testTotalDurationOnlySumsValidTakes() {
        context.insert(makeTake(at: date("2026-09-02 10:00:00"), durationSec: 900))
        context.insert(makeTake(at: date("2026-09-02 20:00:00"), durationSec: 1200, hasMidi: false))
        context.insert(makeTake(at: date("2026-09-03 10:00:00"), durationSec: 599))
        context.insert(makeTake(at: date("2026-09-04 10:00:00"), durationSec: 800))
        let snapshot = build()
        XCTAssertEqual(snapshot.totalDurationSec, 1700, "只累加有效（900 + 800）")
        XCTAssertEqual(snapshot.takeCount, 4, "区间内全部 take（含无效）")
    }

    // MARK: 平均周频

    func testAvgSessionsPerWeekAcrossFourWeeks() {
        // 4 个有练习的周（周一起始 8/31、9/7、9/14、9/21）共 10 次有效；
        // 当月覆盖周数按天枚举 = 5（9 月横跨 8/31、9/7、9/14、9/21、9/28 五个周一起始周）
        insertValidTakes(onDays: [
            "2026-09-01", "2026-09-02",
            "2026-09-08", "2026-09-09", "2026-09-10",
            "2026-09-15", "2026-09-16", "2026-09-17",
            "2026-09-22", "2026-09-23",
        ])
        let snapshot = build()
        XCTAssertEqual(snapshot.takeCount, 10)
        XCTAssertEqual(snapshot.avgSessionsPerWeek ?? -1, 2.0, accuracy: 1e-9, "10 次有效 / 5 个覆盖周 = 2.0")
    }

    func testAvgSessionsPerWeekKeepsRawDouble() {
        insertValidTakes(onDays: [
            "2026-09-01", "2026-09-08", "2026-09-09",
            "2026-09-15", "2026-09-22", "2026-09-23", "2026-09-24",
        ])
        let snapshot = build()
        XCTAssertEqual(snapshot.avgSessionsPerWeek ?? -1, 1.4, accuracy: 1e-9, "7 / 5，保留原始 Double，不预先取整")
    }

    func testAvgSessionsPerWeekEmptyMonthIsZeroNotNil() {
        let snapshot = build()
        XCTAssertEqual(snapshot.avgSessionsPerWeek ?? -1, 0.0, "无 take 月不崩：0 次 / 覆盖周兜底，结果 0")
        XCTAssertEqual(snapshot.validDays, 0)
        XCTAssertEqual(snapshot.takeCount, 0)
    }

    // MARK: 月界（左闭右开）

    func testMonthBoundaryLeftClosedRightOpen() {
        context.insert(makeTake(at: date("2026-08-31 23:59:59"), durationSec: 1800)) // 上月最后一刻（与 9/1 同一周）
        context.insert(makeTake(at: date("2026-09-01 00:00:00"), durationSec: 900))  // 本月 1 号 00:00，计入
        context.insert(makeTake(at: date("2026-10-01 00:00:00"), durationSec: 1800)) // 下月 1 号 00:00，不计
        let september = build()
        XCTAssertEqual(september.periodKey, "2026-09")
        XCTAssertEqual(september.takeCount, 1)
        XCTAssertEqual(september.validDays, 1)
        XCTAssertEqual(september.totalDurationSec, 900)

        // 换「现在」到界外那一刻，各自归其月
        XCTAssertEqual(build(now: date("2026-08-31 23:59:59")).takeCount, 1, "8/31 23:59:59 归 8 月")
        XCTAssertEqual(build(now: date("2026-08-31 23:59:59")).periodKey, "2026-08")
        XCTAssertEqual(build(now: date("2026-10-01 00:00:00")).takeCount, 1, "10/1 00:00 归 10 月")
        XCTAssertEqual(build(now: date("2026-10-01 00:00:00")).periodKey, "2026-10")
    }

    func testDecemberRollsOverToJanuary() {
        insertValidTakes(onDays: ["2026-12-31"])
        let snapshot = build(now: date("2026-12-31 20:00:00"))
        XCTAssertEqual(snapshot.periodKey, "2026-12")
        XCTAssertEqual(snapshot.year, 2026)
        XCTAssertEqual(snapshot.month, 12)
        XCTAssertEqual(build(now: date("2027-01-01 00:00:00")).takeCount, 0, "跨年后 12/31 的 take 不泄漏进 1 月")
    }

    // MARK: 热身完成率

    func testWarmupCompletionPctNilWhenNoPlans() {
        XCTAssertNil(build().warmupCompletionPct, "当月无 DailyPlan → nil，不填 0")
    }

    func testWarmupCompletionPctTwoOfThree() {
        context.insert(DailyPlan(date: date("2026-09-02 00:00:00"), warmupCompletedAt: date("2026-09-02 08:30:00")))
        context.insert(DailyPlan(date: date("2026-09-03 00:00:00"), warmupCompletedAt: date("2026-09-03 08:20:00")))
        context.insert(DailyPlan(date: date("2026-09-04 00:00:00"), warmupCompletedAt: nil))
        XCTAssertEqual(build().warmupCompletionPct, 67, "2/3 四舍五入 = 67")
    }

    func testWarmupCompletionPctAllCompleted() {
        context.insert(DailyPlan(date: date("2026-09-02 00:00:00"), warmupCompletedAt: date("2026-09-02 08:30:00")))
        context.insert(DailyPlan(date: date("2026-09-03 00:00:00"), warmupCompletedAt: date("2026-09-03 08:20:00")))
        XCTAssertEqual(build().warmupCompletionPct, 100)
    }

    func testWarmupCompletionPctNoneCompletedIsZeroNotNil() {
        // 有计划但都没完成 → 如实 0（与「无计划」的 nil 区分：有分母才算百分比）
        context.insert(DailyPlan(date: date("2026-09-05 00:00:00"), warmupCompletedAt: nil))
        context.insert(DailyPlan(date: date("2026-09-06 00:00:00"), warmupCompletedAt: nil))
        context.insert(DailyPlan(date: date("2026-09-07 00:00:00"), warmupCompletedAt: nil))
        XCTAssertEqual(build().warmupCompletionPct, 0)
    }

    func testWarmupIgnoresPlansOutsideMonth() {
        context.insert(DailyPlan(date: date("2026-08-31 00:00:00"), warmupCompletedAt: date("2026-08-31 08:00:00")))
        context.insert(DailyPlan(date: date("2026-10-01 00:00:00"), warmupCompletedAt: date("2026-10-01 08:00:00")))
        context.insert(DailyPlan(date: date("2026-09-05 00:00:00"), warmupCompletedAt: nil))
        context.insert(DailyPlan(date: date("2026-09-06 00:00:00"), warmupCompletedAt: date("2026-09-06 08:00:00")))
        XCTAssertEqual(build().warmupCompletionPct, 50, "分母只数当月 plan：1/2")
    }

    // MARK: 强开记录

    func testOverrideCountsAndReasonDistribution() {
        context.insert(GateEvent(date: date("2026-09-05 21:00:00"), kind: "override", reasonTag: "时间不够"))
        context.insert(GateEvent(date: date("2026-09-06 21:00:00"), kind: "override", reasonTag: "   "))          // 纯空格 → other
        context.insert(GateEvent(date: date("2026-09-07 21:00:00"), kind: "override", reasonTag: "other"))         // other
        context.insert(GateEvent(date: date("2026-09-08 21:00:00"), kind: "override", reasonTag: "热身曲太无聊"))
        context.insert(GateEvent(date: date("2026-09-09 21:00:00"), kind: "warmupBlocked", reasonTag: "时间不够")) // 非 override 不计
        context.insert(GateEvent(date: date("2026-08-31 21:00:00"), kind: "override", reasonTag: "时间不够"))       // 界外不计
        let snapshot = build()
        XCTAssertEqual(snapshot.overrideCount, 4)
        XCTAssertEqual(snapshot.overrideReasons, ["时间不够": 1, "other": 2, "热身曲太无聊": 1], "空/other 合并为 other")
    }

    func testOverrideEmptyWhenNoGates() {
        let snapshot = build()
        XCTAssertEqual(snapshot.overrideCount, 0)
        XCTAssertEqual(snapshot.overrideReasons, [:])
    }

    // MARK: 节奏趋势（月内按周分组）

    func testRhythmTrendWeeklyGroupingRoundingFirstLast() {
        // 第 1 周（周一 8/31）：9/1 与 9/3 → (80 + 90) / 2 = 85
        let w1a = makeTake(at: date("2026-09-01 10:00:00"), durationSec: 900)
        let w1b = makeTake(at: date("2026-09-03 10:00:00"), durationSec: 900)
        // 第 2 周（周一 9/7）：9/8 与 9/10 有分析、9/9 无 → (60 + 61) / 2 = 60.5 → 四舍五入 61
        let w2a = makeTake(at: date("2026-09-08 10:00:00"), durationSec: 900)
        let w2b = makeTake(at: date("2026-09-09 10:00:00"), durationSec: 900)
        let w2c = makeTake(at: date("2026-09-10 10:00:00"), durationSec: 900)
        // 第 3 周（周一 9/14）：只有 take 无 analysis → 该周 nil
        let w3 = makeTake(at: date("2026-09-15 10:00:00"), durationSec: 900)
        // 第 4 周（周一 9/21）：(70 + 74) / 2 = 72
        let w4a = makeTake(at: date("2026-09-22 10:00:00"), durationSec: 900)
        let w4b = makeTake(at: date("2026-09-24 10:00:00"), durationSec: 900)
        for take in [w1a, w1b, w2a, w2b, w2c, w3, w4a, w4b] { context.insert(take) }
        context.insert(makeAnalysis(takeId: w1a.entityId, rhythmScore: 80, analyzedAt: date("2026-09-01 11:00:00")))
        context.insert(makeAnalysis(takeId: w1b.entityId, rhythmScore: 90, analyzedAt: date("2026-09-03 11:00:00")))
        context.insert(makeAnalysis(takeId: w2a.entityId, rhythmScore: 60, analyzedAt: date("2026-09-08 11:00:00")))
        context.insert(makeAnalysis(takeId: w2c.entityId, rhythmScore: 61, analyzedAt: date("2026-09-10 11:00:00")))
        context.insert(makeAnalysis(takeId: w4a.entityId, rhythmScore: 70, analyzedAt: date("2026-09-22 11:00:00")))
        context.insert(makeAnalysis(takeId: w4b.entityId, rhythmScore: 74, analyzedAt: date("2026-09-24 11:00:00")))

        let snapshot = build()
        XCTAssertEqual(snapshot.weeklyRhythmScores, [85, 61, nil, 72], "按 weekStart 升序；无分析周给 nil；只平均已分析 take")
        XCTAssertEqual(snapshot.rhythmFirstWeekScore, 85)
        XCTAssertEqual(snapshot.rhythmLastWeekScore, 72)
    }

    func testRhythmTrendAllNilDoesNotCrash() {
        insertValidTakes(onDays: ["2026-09-02", "2026-09-09"]) // 两个周，均无 analysis
        context.insert(makeAnalysis(takeId: UUID(), rhythmScore: nil, analyzedAt: date("2026-09-02 12:00:00")))
        let snapshot = build()
        XCTAssertEqual(snapshot.weeklyRhythmScores, [nil, nil])
        XCTAssertNil(snapshot.rhythmFirstWeekScore)
        XCTAssertNil(snapshot.rhythmLastWeekScore)
    }

    func testRhythmTrendIgnoresInvalidAndOutOfMonthTakes() {
        let inMonthValid = makeTake(at: date("2026-09-01 10:00:00"), durationSec: 900)
        let inMonthInvalid = makeTake(at: date("2026-09-02 10:00:00"), durationSec: 900, hasMidi: false)
        let w2Valid = makeTake(at: date("2026-09-08 10:00:00"), durationSec: 900)
        let outOfMonth = makeTake(at: date("2026-08-20 10:00:00"), durationSec: 900)
        for take in [inMonthValid, inMonthInvalid, w2Valid, outOfMonth] { context.insert(take) }
        context.insert(makeAnalysis(takeId: inMonthValid.entityId, rhythmScore: 80, analyzedAt: date("2026-09-01 11:00:00")))
        context.insert(makeAnalysis(takeId: inMonthInvalid.entityId, rhythmScore: 99, analyzedAt: date("2026-09-02 11:00:00")))
        context.insert(makeAnalysis(takeId: w2Valid.entityId, rhythmScore: 70, analyzedAt: date("2026-09-08 11:00:00")))
        context.insert(makeAnalysis(takeId: outOfMonth.entityId, rhythmScore: 10, analyzedAt: date("2026-08-20 11:00:00")))

        let snapshot = build()
        XCTAssertEqual(snapshot.weeklyRhythmScores, [80, 70], "无效 take 与界外 take 的 analysis 不进任何一周")
        XCTAssertEqual(snapshot.takeCount, 3, "界外 take 不计入当月")
    }

    func testRhythmTrendLatestAnalysisWins() {
        let take = makeTake(at: date("2026-09-01 10:00:00"), durationSec: 900)
        context.insert(take)
        context.insert(makeAnalysis(takeId: take.entityId, rhythmScore: 50, analyzedAt: date("2026-09-01 11:00:00")))
        context.insert(makeAnalysis(takeId: take.entityId, rhythmScore: 90, analyzedAt: date("2026-09-01 15:00:00")))
        XCTAssertEqual(build().weeklyRhythmScores, [90], "同一 take 多份分析取 analyzedAt 最新")
    }

    // MARK: 教材路线

    func testRouteFromPathState() {
        context.insert(CoursePathState(currentBeyer: 43, currentHanon: 4, current599: 5, projected599Week: 20))
        let snapshot = build()
        XCTAssertEqual(snapshot.beyerCurrent, 43)
        XCTAssertEqual(snapshot.hanonCurrent, 4)
        XCTAssertEqual(snapshot.unlocked599, true, "current599 非 nil = 已解锁")
        XCTAssertEqual(snapshot.current599, 5, "599 当前首号原样进快照（S22 解锁行显「第 N 首」）")
        XCTAssertEqual(snapshot.projected599Week, 20)
    }

    func testRouteWithoutPathStateUsesSafeDefaults() {
        let snapshot = build()
        XCTAssertEqual(snapshot.beyerCurrent, 1)
        XCTAssertEqual(snapshot.hanonCurrent, 1)
        XCTAssertEqual(snapshot.unlocked599, false)
        XCTAssertNil(snapshot.current599, "未解锁不给 599 首号（不拿 1 冒充）")
        XCTAssertEqual(snapshot.projected599Week, 0, "无 pathState 的初始态安全默认，非编造进度")
    }

    // MARK: AI 观察占位与周期字段

    func testPeriodFieldsAndObservationPlaceholders() {
        insertValidTakes(onDays: ["2026-09-03", "2026-09-05"])
        context.insert(makeTake(at: date("2026-09-06 22:00:00"), durationSec: 1200, hasMidi: false)) // 无效也进 takeCount
        let snapshot = build()
        XCTAssertEqual(snapshot.periodKey, "2026-09")
        XCTAssertEqual(snapshot.year, 2026)
        XCTAssertEqual(snapshot.month, 9)
        XCTAssertEqual(snapshot.takeCount, 3)
        XCTAssertEqual(snapshot.refsTakeCount, 3, "引用 take 数 = 当月全部 take")
        XCTAssertEqual(snapshot.refsVideoCount, 0, "无视频批次，恒 0")
        XCTAssertEqual(snapshot.observationStatus, "pending")
        XCTAssertEqual(snapshot.observationTitle, "")
        XCTAssertEqual(snapshot.observationBody, "")
        XCTAssertNil(snapshot.observationProviderModel)
        XCTAssertEqual(snapshot.generatedAt, now)
    }
}

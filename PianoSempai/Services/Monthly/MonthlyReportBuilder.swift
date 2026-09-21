import Foundation

// M7.2 月报聚合（PRD M8 口径 + S22 首屏统计：有效练习/总时长、路线、热身与强开、节奏趋势）。
// 纯逻辑：只吃 Take/TakeAnalysis/DailyPlan/GateEvent/CoursePathState 快照，只读不回写
// （不碰课程/判分/计划状态，红线 3）；数字全部来自真实数据，缺数据给 nil/0，不编造（红线 1）。
// 本 Stage 不调用 AI：观察字段是占位（空正文 + pending），AI 起草在 b2。

enum MonthlyReportBuilder {
    /// 聚合「now 所属自然月」的月报快照。区间 = [当月 1 号 00:00, 下月 1 号 00:00)（本地时区）。
    /// - Parameters:
    ///   - now: 当前时间（决定所属月；月报每月 1 号生成上月时由调用方传入目标月内任意时刻）
    ///   - takes: 全部 Take（内部按月过滤）
    ///   - analyses: 全部 TakeAnalysis（按 takeId 索引 rhythmScore）
    ///   - plans: 全部 DailyPlan（按月过滤，算热身完成率）
    ///   - gates: 全部 GateEvent（按月过滤，算强开次数与原因分布）
    ///   - pathState: 路线状态单例快照（nil = 还没有路线状态，给初始态安全默认，非编造进度）
    static func build(
        now: Date,
        takes: [Take],
        analyses: [TakeAnalysis],
        plans: [DailyPlan],
        gates: [GateEvent],
        pathState: CoursePathState?
    ) -> MonthlyReportSnapshot {
        let monthStart = MonthlyCalendar.monthStart(for: now)
        let monthEnd = MonthlyCalendar.nextMonthStart(for: now)

        let inMonth = takes
            .filter { $0.startedAt >= monthStart && $0.startedAt < monthEnd }
            .sorted { $0.startedAt < $1.startedAt }
        // 有效练习口径与周报完全一致：有 MIDI 且 ≥10 分钟（任务练习与自由弹奏都计）
        let valid = inMonth.filter { $0.hasMidi && $0.durationSec >= WeeklyDigestBuilder.minimumDurationSec }

        let validDays = Set(valid.map { MonthlyCalendar.calendar.startOfDay(for: $0.startedAt) }).count
        let totalDurationSec = valid.reduce(0) { $0 + $1.durationSec }
        let takeCount = inMonth.count
        let weekCount = coveredWeekCount(monthStart: monthStart, monthEnd: monthEnd)
        let rhythm = rhythmTrend(of: valid, analyses: analyses)
        let overrides = overrides(gates: gates, from: monthStart, until: monthEnd)

        return MonthlyReportSnapshot(
            year: MonthlyCalendar.yearMonth(for: now).year,
            month: MonthlyCalendar.yearMonth(for: now).month,
            validDays: validDays,
            totalDurationSec: totalDurationSec,
            takeCount: takeCount,
            // 0 有效次月的比值如实为 0；周数兜底 1 只防除零，不改数字语义
            avgSessionsPerWeek: Double(valid.count) / Double(weekCount),
            beyerCurrent: pathState?.currentBeyer ?? 1,
            hanonCurrent: pathState?.currentHanon ?? 1,
            unlocked599: pathState?.current599 != nil,
            projected599Week: pathState?.projected599Week ?? 0,
            warmupCompletionPct: warmupCompletionPct(plans: plans, from: monthStart, until: monthEnd),
            overrideCount: overrides.count,
            overrideReasons: overrides.reasons,
            rhythmFirstWeekScore: rhythm.first,
            rhythmLastWeekScore: rhythm.last,
            weeklyRhythmScores: rhythm.weekly,
            observationTitle: "",
            observationBody: "",
            observationProviderModel: nil,
            refsTakeCount: takeCount,
            refsVideoCount: 0,
            observationStatus: "pending",
            generatedAt: now
        )
    }

    // MARK: - 区间与周数

    /// 当月覆盖周数：区间内每一天用 WeekCalendar.weekStart 归周后 distinct 周数（周一起始，与周报同口径）
    private static func coveredWeekCount(monthStart: Date, monthEnd: Date) -> Int {
        let weeks = Set(MonthlyCalendar.days(in: monthStart, until: monthEnd).map { WeekCalendar.weekStart(for: $0) })
        return max(weeks.count, 1) // 空区间（不可能出现）兜底 1，避免除零
    }

    // MARK: - 热身完成率

    /// 当月有 DailyPlan 时 = 热身完成天数 / 计划天数 * 100（四舍五入）；无计划 → nil（不填 0）
    private static func warmupCompletionPct(plans: [DailyPlan], from start: Date, until end: Date) -> Int? {
        let inMonth = plans.filter { $0.date >= start && $0.date < end }
        guard !inMonth.isEmpty else { return nil }
        let completed = inMonth.filter { $0.warmupCompletedAt != nil }.count
        return Int((Double(completed) * 100 / Double(inMonth.count)).rounded())
    }

    // MARK: - 强开记录

    /// 强开次数与原因分布。只统计 kind == "override"；reasonTag 去空格后为空或 "other" 统一键 "other"。
    /// 记录只用于用户自己观察，不影响任何解锁（S22 红线）。
    private static func overrides(gates: [GateEvent], from start: Date, until end: Date) -> (count: Int, reasons: [String: Int]) {
        let inMonth = gates.filter { $0.date >= start && $0.date < end && $0.kind == "override" }
        var reasons: [String: Int] = [:]
        for gate in inMonth {
            let tag = gate.reasonTag.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = (tag.isEmpty || tag == "other") ? "other" : tag
            reasons[key, default: 0] += 1
        }
        return (count: inMonth.count, reasons: reasons)
    }

    // MARK: - 节奏趋势

    /// 月内有效 take 按 weekStart 归周（升序），每周 rhythmScore 取该周已分析 take 的算术平均
    /// （Double 四舍五入成 Int；该周无分析 → nil）。全月无分析 → 空数组 + first/last 皆 nil。
    private static func rhythmTrend(of validTakes: [Take], analyses: [TakeAnalysis]) -> (weekly: [Int?], first: Int?, last: Int?) {
        let scoreByTakeId = rhythmScoreIndex(analyses: analyses)
        let weekStarts = Set(validTakes.map { WeekCalendar.weekStart(for: $0.startedAt) }).sorted()

        let weekly: [Int?] = weekStarts.map { weekStart in
            let scores = validTakes
                .filter { WeekCalendar.weekStart(for: $0.startedAt) == weekStart }
                .compactMap { scoreByTakeId[$0.entityId] }
            guard !scores.isEmpty else { return nil }
            return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
        }
        return (weekly: weekly, first: weekly.first { $0 != nil } ?? nil, last: weekly.last { $0 != nil } ?? nil)
    }

    /// takeId → rhythmScore 索引。同一 take 多份分析（多 engineVersion）取 analyzedAt 最新的一份。
    private static func rhythmScoreIndex(analyses: [TakeAnalysis]) -> [UUID: Int] {
        var latestAnalyzedAt: [UUID: Date] = [:]
        var index: [UUID: Int] = [:]
        for analysis in analyses {
            guard let score = analysis.rhythmScore else { continue }
            if let existing = latestAnalyzedAt[analysis.takeId], analysis.analyzedAt < existing { continue }
            latestAnalyzedAt[analysis.takeId] = analysis.analyzedAt
            index[analysis.takeId] = score
        }
        return index
    }
}

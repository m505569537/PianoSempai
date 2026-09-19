import Foundation
import SheetMusicCore
import SheetMusicLoader
import SwiftData

// 课程规则引擎（M3 P1 简化版）。
// 红线 1/写入权矩阵：课程状态只由 CourseEngine 写；任何 View/AI 不得直接改课程状态。
// 本文件是 P1 插入点规则表的唯一所在（brief：算法写死但集中一处，P2 替换）。
// 所有产出的数字都来自真实采集（视奏命中率/停顿/力度样本），规则为固定查表，不做随机。

enum CourseEngine {
    /// 规则版本号（写入 DailyPlan.generatedFromRulesVersion，便于追溯是哪版规则产出的计划）
    static let rulesVersion = "P1-rule-1.0"

    // MARK: - 规则表（写死，公开可查、非黑箱）

    /// 视奏命中率（两段平均）→ 拜厄插入条目 / 599 预计周数。
    /// 出处：brief §3「插入点先用规则表：自评+视奏命中率映射拜厄条目」；具体映射为 P1 开发期编排。
    static func beyerEntry(averageHitRate: Double, yearsExperience: String) -> Int {
        let yearsBonus = yearsExperience.contains("2") || yearsExperience.contains("3") || yearsExperience.contains("5")
        switch averageHitRate {
        case 0.8...: return yearsBonus ? 45 : 35
        case 0.6..<0.8: return yearsBonus ? 30 : 20
        case 0.3..<0.6: return yearsBonus ? 15 : 8
        default: return 1
        }
    }

    static func hanonEntry(averageHitRate: Double) -> Int {
        // 哈农前 20 条逐步解锁（PRD M3 路线结构）；插入点 P1 恒从第 1 条起
        1
    }

    static func projected599Weeks(averageHitRate: Double) -> Int {
        switch averageHitRate {
        case 0.8...: 8
        case 0.5..<0.8: 12
        default: 16
        }
    }

    // MARK: - 视奏评分（真实采集数据的确定性换算，展示时必须带「规则估算」标注）

    /// 音准维度 = 命中率 × 100
    static func accuracyScore(hitRates: [Double]) -> Int {
        guard !hitRates.isEmpty else { return 0 }
        return Int((hitRates.reduce(0, +) / Double(hitRates.count) * 100).rounded())
    }

    /// 连贯维度：停顿次数（相邻 played 音 >2s）→ 100 − 停顿×10，下限 0
    static func continuityScore(pauseCounts: [Int]) -> Int {
        let pauses = pauseCounts.reduce(0, +)
        return max(0, 100 - pauses * 10)
    }

    /// 综合参考（弱总分）：仅纳入本次真实算出的维度（P1 = 音准/连贯），
    /// 其余维度不编数字（红线 2），P2 完整判分补齐后重算。
    static func overallReferenceScore(hitRates: [Double], pauseCounts: [Int]) -> Int {
        let parts = [accuracyScore(hitRates: hitRates), continuityScore(pauseCounts: pauseCounts)]
        return Int((Double(parts.reduce(0, +)) / Double(parts.count)).rounded())
    }

    // MARK: - 落库（唯一写手）

    /// 生成 PlacementResult 并写 CoursePathState（不含 DailyPlan；周计划在 S05 CTA 时建）
    @discardableResult
    static func finalizePlacement(
        report: PlacementSelfReport,
        hitRates: [Double],
        expected: [Int],
        matched: [Int],
        pauseCounts: [Int],
        calibration: VelocityCalibration?,
        elapsedSeconds: Int,
        in context: ModelContext
    ) -> PlacementResult {
        let avg = hitRates.isEmpty ? 0 : hitRates.reduce(0, +) / Double(hitRates.count)
        let result = PlacementResult()
        result.selfReportId = report.entityId
        result.sightreadHitRates = hitRates
        result.sightreadExpected = expected
        result.sightreadMatched = matched
        result.pauseCounts = pauseCounts
        result.overallReferenceScore = overallReferenceScore(hitRates: hitRates, pauseCounts: pauseCounts)
        result.entryBeyer = beyerEntry(averageHitRate: avg, yearsExperience: report.yearsExperience)
        result.entryHanon = hanonEntry(averageHitRate: avg)
        result.projected599Weeks = projected599Weeks(averageHitRate: avg)
        result.elapsedSeconds = elapsedSeconds
        if let calibration {
            result.velocityCalibrationId = calibration.entityId
        }
        context.insert(result)

        // CoursePathState 单例替换
        let pathState = fetchOrCreatePathState(in: context)
        pathState.currentBeyer = result.entryBeyer
        pathState.currentHanon = result.entryHanon
        pathState.current599 = nil
        pathState.projected599Week = result.projected599Weeks
        pathState.weekNumber = 1
        pathState.placementResultId = result.entityId
        pathState.updatedAt = Date()
        return result
    }

    /// S05 CTA「生成我的第一周计划」：建第 1 周 DailyPlan（热身=哈农插入条目 / 主菜=拜厄插入条目 / 奖励曲空缺）
    static func generateFirstWeekPlan(result: PlacementResult, in context: ModelContext) -> DailyPlan {
        let warmup = PracticeTask()
        warmup.type = "warmup"
        warmup.book = "哈农"
        warmup.number = result.entryHanon
        warmup.status = "pending"
        context.insert(warmup)

        let main = PracticeTask()
        main.type = "main"
        main.book = "拜厄"
        main.number = result.entryBeyer
        main.status = "pending"
        context.insert(main)

        let plan = DailyPlan()
        plan.date = Calendar.current.startOfDay(for: Date())
        plan.durationChoice = 30
        plan.warmupTaskId = warmup.taskId
        plan.mainTaskId = main.taskId
        plan.generatedFromRulesVersion = rulesVersion
        context.insert(plan)
        return plan
    }

    // MARK: - 今日计划（每日首次进入生成；CourseEngine 唯一写手）

    /// 取当日 DailyPlan；不存在则从 CoursePathState 生成（热身=哈农当前条目 / 主菜=拜厄当前条目 / 奖励曲空缺）。
    /// 未定级（无 CoursePathState）时返回 nil —— 今日页走 S07b 空状态。
    static func todayPlan(today: Date = Date(), in context: ModelContext) -> DailyPlan? {
        let pathState = fetchOrCreatePathState(in: context)
        guard pathState.placementResultId != nil else { return nil }

        let dayStart = Calendar.current.startOfDay(for: today)
        let plans = (try? context.fetch(FetchDescriptor<DailyPlan>())) ?? []
        if let existing = plans.first(where: { Calendar.current.isDate($0.date, inSameDayAs: dayStart) }) {
            return existing
        }

        let warmup = PracticeTask()
        warmup.type = "warmup"
        warmup.book = "哈农"
        warmup.number = pathState.currentHanon
        context.insert(warmup)

        let main = PracticeTask()
        main.type = "main"
        main.book = "拜厄"
        main.number = pathState.currentBeyer
        context.insert(main)

        let plan = DailyPlan()
        plan.date = dayStart
        plan.durationChoice = 30
        plan.warmupTaskId = warmup.taskId
        plan.mainTaskId = main.taskId
        plan.generatedFromRulesVersion = rulesVersion
        context.insert(plan)
        return plan
    }

    /// 切换当日时长（15/30/45）：只改 DailyPlan.durationChoice，热身不被压缩（today.md）
    static func setDurationChoice(_ minutes: Int, for plan: DailyPlan) {
        guard [15, 30, 45].contains(minutes) else { return }
        plan.durationChoice = minutes
    }

    private static func fetchOrCreatePathState(in context: ModelContext) -> CoursePathState {
        let descriptor = FetchDescriptor<CoursePathState>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let state = CoursePathState()
        context.insert(state)
        return state
    }
}

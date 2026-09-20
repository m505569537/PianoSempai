import Foundation
import SheetMusicCore
import SheetMusicLoader
import SwiftData

// 课程规则引擎（M3 P1 简化版）。
// 红线 1/写入权矩阵：课程状态只由 CourseEngine 写；任何 View/AI 不得直接改课程状态。
// 本文件是 P1 插入点规则表的唯一所在（brief：算法写死但集中一处，P2 替换）。
// 所有产出的数字都来自真实采集（视奏命中率/停顿/力度样本），规则为固定查表，不做随机。

enum CourseEngine {

    /// P1 定级/计划生成规则版本（勿动；升版走显式决策）
    /// P2 过关判定规则版本（SPEC L162 留痕：过关时写入 Piece.passedRulesVersion）
    static let scoringRulesVersion = "P2-scoring-1.0"

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

    /// 曲库导入成功后的落库（library.md 导入契约：ScoreFile(canFollow) + Piece(book=导入, status=notStarted)）。
    /// 新建导入条目不属于课程状态推进（状态仍由本引擎维护），故集中在 CourseEngine。
    @discardableResult
    static func registerImportedScore(_ imported: LibraryImportService.Imported, in context: ModelContext) -> (ScoreFile, Piece?) {
        let file = ScoreFile(
            kind: imported.kind,
            fileURL: imported.relativePath,
            title: imported.title,
            canFollow: imported.canFollow
        )
        context.insert(file)

        var piece: Piece?
        if imported.canFollow {
            let newPiece = Piece(
                title: imported.title,
                book: "导入",
                status: "notStarted"
            )
            newPiece.sourceScoreId = file.entityId
            context.insert(newPiece)
            piece = newPiece
        }
        return (file, piece)
    }

    /// 目录条目（内置教材/示例曲）对应的 Piece 建档（M5b：take 关联 pieceId 的前提）。
    /// **只建行、不改状态**：status 恒为默认 notStarted，过关状态仍只由
    /// applyPassIfConsecutive 写（红线 2）。幂等：同 book+number 只建一次。
    static func ensurePiece(for entry: CatalogEntry, in context: ModelContext) -> Piece {
        let book = entry.book
        let number = entry.number
        let descriptor = FetchDescriptor<Piece>(
            predicate: #Predicate { $0.book == book && $0.number == number }
        )
        if let existing = try? context.fetch(descriptor).first { return existing }
        let piece = Piece(
            title: entry.title,
            book: entry.book,
            number: entry.number,
            status: "notStarted",
            referenceTempo: entry.referenceTempo
        )
        context.insert(piece)
        return piece
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

    // MARK: - 过关门禁（SPEC §7；课程引擎唯一写手，红线 2/4）

    /// 单项硬指标判定结果（S09/S13 以真实数值展示 + 「差多少」，§7 公开可查非黑箱）
    struct MetricResult: Equatable, Sendable {
        let name: String
        let actualDisplay: String
        let thresholdDisplay: String
        let passed: Bool
    }

    /// 单 take 过关判定（纯函数值类型；写 Piece.status 仍由 applyPassIfConsecutive 承担）
    struct PassEvaluation: Equatable, Sendable {
        /// 有参考谱 + 非自由弹奏 + confidence ≥ 0.6 + coversFullScope
        let canEvaluate: Bool
        let passesAllHardMetrics: Bool
        let metrics: [MetricResult]
        let reasons: [String]
    }

    /// 单 take 硬指标判定（纯函数；confidence 门禁阈值 0.6 集中在 ScoringStandards，§9）。
    /// 错音率分母 = 非 grace 参考音数（§6 口径互补）：漏音计罚、多弹不稀释比率（M4 gate B3）。
    static func evaluatePass(
        wrongPitchCount: Int,
        missingCount: Int,
        referenceNonGraceCount: Int,
        rhythmMedianMs: Double,
        tempoTargetHit: Bool,
        confidence: Double,
        coversFullScope: Bool,
        hasScore: Bool,
        isFreePlay: Bool,
        standards: ScoringStandards
    ) -> PassEvaluation {
        var reasons: [String] = []
        // 可评前提（§7）：有参考谱 + 非自由弹奏 + 高置信 + 覆盖完整
        guard hasScore, !isFreePlay else {
            return PassEvaluation(
                canEvaluate: false, passesAllHardMetrics: false, metrics: [],
                reasons: ["无参考谱/自由弹奏，不判定过关"]
            )
        }
        guard confidence >= ScoringStandards.confidenceGateThreshold else {
            reasons.append(String(format: "对齐置信度 %.2f 低于 %.2f，本次不计入过关（也不清零）", confidence, ScoringStandards.confidenceGateThreshold))
            return PassEvaluation(
                canEvaluate: false, passesAllHardMetrics: false, metrics: [],
                reasons: reasons
            )
        }
        guard coversFullScope else {
            reasons.append("未覆盖评分区间全部小节，本次不计入过关（也不清零）")
            return PassEvaluation(
                canEvaluate: false, passesAllHardMetrics: false, metrics: [],
                reasons: reasons
            )
        }
        // 硬指标（§7：错音率/节奏偏差中位/速度达标；弱总分不参与，红线 4）。
        // 错音率 = (错音 + 漏音) / 非 grace 参考音数（gate B3：漏音计罚、多弹不进分子分母）
        let rate = Double(wrongPitchCount + missingCount) / Double(max(1, referenceNonGraceCount))
        let ratePassed = rate <= standards.maxWrongNoteRate
        let rhythmPassed = rhythmMedianMs <= standards.maxRhythmMedianMs
        let metrics = [
            MetricResult(
                name: "错音率",
                actualDisplay: String(format: "%.1f%%", rate * 100),
                thresholdDisplay: String(format: "≤ %.0f%%", standards.maxWrongNoteRate * 100),
                passed: ratePassed
            ),
            MetricResult(
                name: "节奏偏差中位",
                actualDisplay: String(format: "%.0fms", rhythmMedianMs),
                thresholdDisplay: String(format: "≤ %.0fms", standards.maxRhythmMedianMs),
                passed: rhythmPassed
            ),
            MetricResult(
                name: "速度达标",
                actualDisplay: tempoTargetHit ? "已达标" : "未达标",
                thresholdDisplay: "≥ 参考速度 \(Int(standards.targetTempoRatio * 100))%",
                passed: tempoTargetHit
            ),
        ]
        let passesAll = ratePassed && rhythmPassed && tempoTargetHit
        if !ratePassed { reasons.append(String(format: "错音率 %.1f%% 超过 %.0f%%", rate * 100, standards.maxWrongNoteRate * 100)) }
        if !rhythmPassed { reasons.append(String(format: "节奏偏差中位 %.0fms 超过 %.0fms", rhythmMedianMs, standards.maxRhythmMedianMs)) }
        if !tempoTargetHit { reasons.append("速度未达标") }

        return PassEvaluation(
            canEvaluate: true, passesAllHardMetrics: passesAll,
            metrics: metrics, reasons: reasons
        )
    }

    /// 「差多少过关」（§7）：各硬指标当前值与阈值差（S09/S13 展示用；纯函数）。
    /// 错音率口径与 evaluatePass 一致（gate B3）。
    static func passGap(
        wrongPitchCount: Int, missingCount: Int, referenceNonGraceCount: Int,
        rhythmMedianMs: Double,
        standards: ScoringStandards
    ) -> [String] {
        var gaps: [String] = []
        let rate = Double(wrongPitchCount + missingCount) / Double(max(1, referenceNonGraceCount))
        let rateGap = rate - standards.maxWrongNoteRate
        if rateGap > 0 {
            gaps.append(String(format: "错音率还差 %.1f%%", rateGap * 100))
        }
        let rhythmGap = rhythmMedianMs - standards.maxRhythmMedianMs
        if rhythmGap > 0 {
            gaps.append(String(format: "节奏偏差还差 %.0fms", rhythmGap))
        }
        return gaps
    }

    /// 连续达标计数（纯函数；§7）：
    /// - 从最新往回数「可评且达标」的连续 take；
    /// - 可评但不达标 → 连续计数清零（返回 0）；
    /// - 不可评（低置信/无谱）→ 不参与计数也不清零（跳过）。
    static func consecutivePassStreak(eligibleTakes: [(eligible: Bool, passed: Bool)]) -> Int {
        var streak = 0
        for take in eligibleTakes.reversed() {
            guard take.eligible else { continue } // 不可评：跳过，不清零
            if take.passed {
                streak += 1
            } else {
                return 0 // 可评但不达标：清零
            }
        }
        return streak
    }

    /// 过关落库（唯一写手）：同一 piece 最近连续 2 次可评且达标 → Piece.status = passed，
    /// 并留痕 scoringRulesVersion（SPEC L162）。返回是否发生过关。
    /// 判定消费的 take 数据由调用方给（保持引擎纯度，测试注入）。
    @discardableResult
    static func applyPassIfConsecutive(
        piece: Piece,
        takesOldestFirst: [(eligible: Bool, passed: Bool)],
        in context: ModelContext
    ) -> Bool {
        let streak = consecutivePassStreak(eligibleTakes: takesOldestFirst)
        guard streak >= 2 else { return false }
        guard piece.status != "passed" else { return false }
        piece.status = "passed"
        piece.passedRulesVersion = Self.scoringRulesVersion
        return true
    }
}

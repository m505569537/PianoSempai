import Foundation
import Observation
import SwiftData

// M7.2 月报协调器（brief §2：PRD M8「每月 1 号生成上月」+ S22 观察回填）。
// 何时起草、何时出网、何时落库都在这里：App 启动 / 进后台都会调 refresh()，幂等。
// 写权边界（红线 3）：本类只写 MonthlyReport 的统计 + 观察字段；PracticeNote 只在用户
// 在 S22 点「把观察写进笔记」时写；绝不回写 Take/Piece/DailyPlan/AppSettings/CoursePathState。
// 依赖全部协议化 + now 可注入：单测用假观察服务 + 固定时间，不打网络、不读 Keychain。

// MARK: - 起草规则（纯函数，可单测）

enum MonthlyDraftRule {
    /// 上一个自然月的 1 号 00:00（起草目标月）
    static func previousMonthStart(now: Date) -> Date {
        MonthlyCalendar.calendar.date(byAdding: .month, value: -1, to: MonthlyCalendar.monthStart(for: now))
            ?? MonthlyCalendar.monthStart(for: now)
    }

    /// 是否需要为上月起草：每月 1 号，或库中尚无「紧邻上月」的月报（用户月中才装 App / 漏刷）。
    /// 仅决定「该不该看」，是否真的插库还要看库里有没有（已有 = 不重算，快照冻结语义）。
    static func shouldDraft(now: Date, hasPreviousReport: Bool) -> Bool {
        MonthlyCalendar.calendar.component(.day, from: now) == 1 || !hasPreviousReport
    }

    /// 起草时喂给 builder 的参照时刻：上月 15 号 12:00（该月内任意固定时刻；15 号任何月份都存在）
    static func referenceDate(monthStart: Date) -> Date {
        MonthlyCalendar.calendar.date(byAdding: DateComponents(day: 14, hour: 12), to: monthStart) ?? monthStart
    }
}

// MARK: - 协调器

@MainActor
@Observable
final class MonthlyReportCoordinator {
    private let context: ModelContext
    private let observationService: any MonthlyObservationGenerating
    private let providerSource: any MonthlyProviderSource
    private let runner: any MonthlyObservationRunning
    private let now: () -> Date

    /// S22 failed 卡「重试」进行中（视图读它：转圈 + 禁用按钮，防重复点）
    private(set) var isRetrying = false

    init(
        context: ModelContext,
        observationService: any MonthlyObservationGenerating = MonthlyObservationService(),
        providerSource: any MonthlyProviderSource,
        runner: any MonthlyObservationRunning,
        now: @escaping () -> Date = { Date() }
    ) {
        self.context = context
        self.observationService = observationService
        self.providerSource = providerSource
        self.runner = runner
        self.now = now
    }

    /// 线上实例（真实链 + 真实 Keychain + 真实时间）
    static func live(context: ModelContext) -> MonthlyReportCoordinator {
        MonthlyReportCoordinator(
            context: context,
            providerSource: SwiftDataMonthlyProviderSource(context: context),
            // runner 常驻：失败转移的「粘住上次成功模型」跨月保持，与 ProviderChainRuntime 同一思路
            runner: ProviderChainRunner(client: OpenAICompatClient(), keyStore: KeychainProviderKeyStore())
        )
    }

    // MARK: - 刷新（App 启动 / 每次进后台都会调；幂等）

    func refresh() async {
        let now = self.now()
        let reports = fetchReports()

        // 一次取数（遍历多个缺口月时复用，不每月重查）
        let takes = (try? context.fetch(FetchDescriptor<Take>())) ?? []
        guard let earliestTake = takes.min(by: { $0.startedAt < $1.startedAt }) else { return }
        let earliestMonthStart = MonthlyCalendar.monthStart(for: earliestTake.startedAt)

        // 从紧邻上月往回扫到「最早一条 take 所在月」，补齐所有缺失且有练习的月份。
        // 覆盖场景：用户连续一个月以上停练没开 App（如 9 月在练、10 月没开、11 月才回来）：
        // 只补紧邻上月（10 月，空）会让真正有练习的 9 月报告永久丢失。空月照常跳过。
        var candidate = MonthlyDraftRule.previousMonthStart(now: now)
        while candidate >= earliestMonthStart {
            let periodKey = MonthlyCalendar.periodKey(for: candidate)
            let alreadyHas = reports.contains { $0.periodKey == periodKey }

            if !alreadyHas {
                let referenceDate = MonthlyDraftRule.referenceDate(monthStart: candidate)
                let snapshot = buildSnapshot(now: referenceDate, takes: takes)
                // 空月不落库、不跑 AI（与 WeeklyDigestCoordinator「空周不生成」同一口径）
                if snapshot.takeCount > 0 {
                    let report = MonthlyReport(snapshot: snapshot)
                    context.insert(report)
                    try? context.save()
                    await fillObservation(report)
                }
            }

            guard let older = MonthlyCalendar.calendar.date(byAdding: .month, value: -1, to: candidate) else { break }
            candidate = older
        }
    }

    /// S22 failed 卡「重试」：重新生成观察回填同一行（统计不动）
    func retryObservation(for periodKey: String) async {
        guard !isRetrying else { return }
        guard let report = fetchReports().first(where: { $0.periodKey == periodKey }) else { return }
        isRetrying = true
        defer { isRetrying = false }
        await fillObservation(report)
    }

    // MARK: - 观察回填

    /// 已 ok 就不重复出网（省用户配额）；失败只降级状态，不删统计、不抛出致 refresh 崩。
    private func fillObservation(_ report: MonthlyReport) async {
        guard report.observationStatus != "ok" else { return }
        do {
            let observation = try await observationService.makeObservation(
                snapshot: report.snapshot,
                providers: providerSource.currentProviders(),
                runner: runner
            )
            report.observationTitle = observation.title
            report.observationBody = observation.body
            report.observationProviderModel = observation.providerModel
            report.observationStatus = "ok"
        } catch {
            // 全链失败（含一个服务商都没配）：统计保留，用户可在 S22 重试
            report.observationStatus = "failed"
        }
        try? context.save()
    }

    // MARK: - 取数（只读）

    private func fetchReports() -> [MonthlyReport] {
        (try? context.fetch(FetchDescriptor<MonthlyReport>(sortBy: [SortDescriptor(\.periodKey)]))) ?? []
    }

    private func buildSnapshot(now: Date, takes: [Take]? = nil) -> MonthlyReportSnapshot {
        let takes = takes ?? ((try? context.fetch(FetchDescriptor<Take>())) ?? [])
        let analyses = (try? context.fetch(FetchDescriptor<TakeAnalysis>())) ?? []
        let plans = (try? context.fetch(FetchDescriptor<DailyPlan>())) ?? []
        let gates = (try? context.fetch(FetchDescriptor<GateEvent>())) ?? []
        let pathState = (try? context.fetch(FetchDescriptor<CoursePathState>()))
        return MonthlyReportBuilder.build(
            now: now,
            takes: takes,
            analyses: analyses,
            plans: plans,
            gates: gates,
            pathState: pathState?.first
        )
    }
}

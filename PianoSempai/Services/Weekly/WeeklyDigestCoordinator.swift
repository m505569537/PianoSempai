import Foundation
import SwiftData
import UserNotifications

// M7.2 周报协调器（PRD 主动性 Q2=A：每周日晚一条合并通知，最多一条）。
// 何时算、何时排、何时落库都在这里；只写 PracticeNote（weeklyReport）与本地通知排期，
// 不碰课程/判分/计划状态（红线 3）。依赖全部协议化 + now 可注入：单测不打通知中心。

@MainActor
final class WeeklyDigestCoordinator {
    /// S23 开关页直接读授权状态 / 弹系统授权框用（与 refresh 同一个实例）
    let scheduler: any NotificationScheduling
    private let context: ModelContext
    private let now: () -> Date

    init(
        scheduler: any NotificationScheduling,
        context: ModelContext,
        now: @escaping () -> Date = { Date() }
    ) {
        self.scheduler = scheduler
        self.context = context
        self.now = now
    }

    /// 线上实例（真实通知中心 + 真实时间）
    static func live(context: ModelContext) -> WeeklyDigestCoordinator {
        WeeklyDigestCoordinator(scheduler: SystemNotificationScheduler(), context: context)
    }

    // MARK: - 刷新（App 启动 / 每次进后台都会调；幂等）

    func refresh() async {
        let settings = AppSettings.fetchOrCreate(in: context)
        let now = self.now()
        let identifier = WeeklyDigest.notificationIdentifier(weekKey: WeekCalendar.weekKey(for: now))

        // 用户全关：不排、移除已排的、不落库（PRD：全可关）
        guard settings.weeklyDigestEnabled else {
            scheduler.removePending(identifier)
            return
        }

        let takes = (try? context.fetch(FetchDescriptor<Take>())) ?? []
        let pieces = (try? context.fetch(FetchDescriptor<Piece>())) ?? []
        let goal = settings.weeklyGoal
        let digest = WeeklyDigestBuilder.build(takes: takes, pieces: pieces, goal: goal, now: now)
        let weekStart = WeekCalendar.weekStart(for: now)
        let fireComponents = WeekCalendar.sundayEveningComponents(from: weekStart)
        guard let fireDate = WeekCalendar.calendar.date(from: fireComponents) else { return }

        if now < fireDate {
            // 本周日 21:00 未到：排本周唯一一条（本周内每次 refresh 覆盖内容——
            // 周日练完 App 进后台会再刷，最终文案含周日练习）。
            // 未授权则静默跳过：首次 launch 不主动弹系统授权框（等用户进 S23 开关页交互）。
            guard await isSchedulable() else { return }
            try? await scheduler.upsert(
                identifier: identifier,
                title: DigestText.notificationTitle(digest),
                body: DigestText.notificationBody(digest),
                fireComponents: fireComponents
            )
        } else {
            // 通知时刻已过：不重发。已送达则从通知中心移除（避免下周日新旧两条并存）；
            // 没送达（手机关机等）周报也照常进 S19 时间线。
            scheduler.removePending(identifier)
            if await scheduler.deliveredIdentifier(identifier) {
                scheduler.removeDelivered(identifier)
            }
            persistOnce(digest)
        }

        // 跨周补漏：上一周的周报若还没落 S19（用户周日收到通知没点、周一才开 App），
        // 这里补上，并清掉通知中心里上周那条（去重由 persistOnce 按 weekKey 保证）。
        await catchUpPreviousWeek(takes: takes, pieces: pieces, goal: goal, currentWeekStart: weekStart)
    }

    /// 授权未决定 / 被拒 → 不排期（provisional 静默送达、ephemeral 限时送达都算可排）
    private func isSchedulable() async -> Bool {
        let status = await scheduler.authorizationStatus()
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    /// 补落上一周周报：参照日取本周一的前一天（上周日），build 会归到上一个周一起始。
    /// 覆盖场景：周日 21:00 通知后用户没开 App，本周（周一及以后）才打开。
    /// 仅当上一周确有 take 才落库——空周不生成「练了 0 次」的周报，避免凭空多记。
    private func catchUpPreviousWeek(takes: [Take], pieces: [Piece], goal: Int, currentWeekStart: Date) async {
        guard let previousSunday = WeekCalendar.calendar.date(byAdding: .day, value: -1, to: currentWeekStart) else { return }
        let previousDigest = WeeklyDigestBuilder.build(takes: takes, pieces: pieces, goal: goal, now: previousSunday)
        let previousIdentifier = WeeklyDigest.notificationIdentifier(weekKey: previousDigest.weekKey)
        // 通知清理照常（无论是否落库，都不该让上周通知残留/重复）
        scheduler.removePending(previousIdentifier)
        if await scheduler.deliveredIdentifier(previousIdentifier) {
            scheduler.removeDelivered(previousIdentifier)
        }
        guard previousDigest.takeCount > 0 else { return }
        persistOnce(previousDigest)
    }

    /// 按 weekKey 去重落库：同一周只写一条 weeklyReport（重复 refresh / 反复进后台不重复）
    private func persistOnce(_ digest: WeeklyDigest) {
        // 先把 weekKey 取到局部常量：直接写 digest.weekKey 会让 #Predicate 宏把
        // WeeklyDigest 误当成谓词根类型（KeyPath 推断撞车），取局部值可绕开。
        let weekKey = digest.weekKey
        let descriptor = FetchDescriptor<PracticeNote>(
            predicate: #Predicate<PracticeNote> { $0.kind == "weeklyReport" && $0.weekKey == weekKey }
        )
        if let existing = try? context.fetch(descriptor), !existing.isEmpty { return }
        context.insert(PracticeNote(
            kind: "weeklyReport",
            title: DigestText.weeklyReportNoteTitle(digest),
            body: DigestText.weeklyReportNoteBody(digest),
            weekKey: digest.weekKey,
            status: "open"
        ))
        try? context.save()
    }
}

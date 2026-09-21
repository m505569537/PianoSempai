import SwiftData
import SwiftUI

// MARK: - S20 档案（P1 简版：本周统计 + take 时间线（筛选 chips）+ 月报入口）
// 布局真值：docs/design-reference/screens/S20-archive/spec.md。
// 导航：本视图是 tab 页（AppFrameView 的 5 tab 之一），自身没有 NavigationStack；
//       take 详情沿用 sheet（TakeReportView），月报走 fullScreenCover（S22 无 tab，
//       fullScreenCover 天然隐藏 tab bar，与 AppFrameView「无 tab 页一律 fullScreenCover/sheet」一致）。

struct ArchiveView: View {
    @Query(sort: \Take.startedAt, order: .reverse) private var takes: [Take]
    @Query private var settingsList: [AppSettings]
    @Query(sort: \MonthlyReport.periodKey) private var monthlyReports: [MonthlyReport]

    enum Filter: String, CaseIterable {
        case all = "全部"
        case warmup = "热身"
        case main = "主菜"
        case reward = "奖励曲"
        case free = "自由弹奏"
    }

    @State private var filter: Filter = .all
    @State private var selected: Take?
    @State private var now = Date()
    /// 月报页（fullScreenCover；与 take 详情的 sheet 并存不冲突）
    @State private var showMonthlyReport = false
    /// 引用 chip 跳回来时的月份过滤（periodKey；nil = 不按月份过滤）
    @State private var monthFilter: String?

    private var settings: AppSettings? { settingsList.first }

    /// 最近一期月报（periodKey 最大；没有 = 还没生成过）
    private var latestReport: MonthlyReport? { monthlyReports.last }

    private var filtered: [Take] {
        ArchiveMonthFilter.apply(takes: takes, periodKey: monthFilter).filter { take in
            switch filter {
            case .all: return true
            case .warmup: return take.taskType == "warmup"
            case .main: return take.taskType == "main"
            case .reward: return take.taskType == "reward"
            case .free: return take.isFreePlay
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("档案")
                    .font(.displayLg)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.top, 8)

                weekStatsCard.padding(.top, 16)

                monthlyEntryCard.padding(.top, 12)

                if monthFilter != nil {
                    monthFilterRow.padding(.top, 12)
                }

                Text("Take 时间线")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.top, 20)

                filterChips.padding(.top, 10)

                if filtered.isEmpty {
                    Text(emptyText)
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                }
                ForEach(filtered) { take in
                    Button {
                        selected = take
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rowTitle(take))
                                    .font(.bodyMd)
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                Text("\(take.startedAt.formatted(date: .abbreviated, time: .shortened)) · ♩=\(take.tempoAvg) · \(take.durationSec / 60)分\(take.durationSec % 60)秒")
                                    .font(.labelSm)
                                    .foregroundStyle(Color.textMuted)
                                    .monospacedDigit()
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textMuted)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 56)
                    }
                    .buttonStyle(.plain)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
                    .padding(.top, 8)
                }

                // 趋势图：后续版本（brief P1 简版边界；月报入口已在上面提供，不再拿周报占位）
                Text("趋势图将在后续版本提供。")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
        .background(Color.canvas)
        .sheet(item: $selected) { take in
            TakeReportView(take: take)
        }
        .fullScreenCover(isPresented: $showMonthlyReport) {
            MonthlyReportView(initialPeriodKey: latestReport?.periodKey) { periodKey in
                monthFilter = periodKey
            }
        }
        .onAppear { now = Date() }
    }

    private var emptyText: String {
        if monthFilter != nil { return "这个月还没有 take。" }
        switch filter {
        case .all: return "还没有 take。练习室弹一段，这里会出现记录。"
        default: return "这个筛选下还没有 take。"
        }
    }

    // MARK: 月报入口卡

    private var monthlyEntryCard: some View {
        Button {
            showMonthlyReport = true
        } label: {
            NocturneCard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("月度报告")
                            .font(.titleMd)
                            .foregroundStyle(Color.textPrimary)
                        Text(monthlyEntrySubtitle)
                            .font(.labelSm)
                            .foregroundStyle(Color.textMuted)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开月度报告")
    }

    /// 入口副标题：有月报显「年月月报 + 观察简述」；没有则如实说当前月预览可看（不编一份）
    private var monthlyEntrySubtitle: String {
        guard let latestReport else {
            let (year, month) = MonthlyCalendar.yearMonth(for: now)
            return "\(year) 年 \(month) 月统计可先看；上月月报在每月 1 号生成"
        }
        let title = latestReport.observationStatus == "ok" && !latestReport.observationTitle.isEmpty
            ? latestReport.observationTitle
            : "统计已就绪"
        return "\(latestReport.year) 年 \(latestReport.month) 月月报 · \(title)"
    }

    // MARK: 月份过滤行（引用 chip 从 S22 跳回来时出现）

    private var monthFilterRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 11))
                .foregroundStyle(Color.amber)
            Text(monthFilterText)
                .font(.labelSm)
                .foregroundStyle(Color.amber)
            Spacer()
            Button {
                monthFilter = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消按月份过滤")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.amber.opacity(0.3), lineWidth: 1))
    }

    private var monthFilterText: String {
        guard let monthFilter, let monthStart = MonthlyCalendar.monthStart(periodKey: monthFilter) else {
            return "按月份过滤"
        }
        let (year, month) = MonthlyCalendar.yearMonth(for: monthStart)
        return "只看 \(year) 年 \(month) 月的 take"
    }

    private var weekStatsCard: some View {
        let progress = TodayPlanService.weekProgress(
            takes: takes, weeklyGoal: settings?.weeklyGoal ?? 3,
            dailyChoiceMinutes: 30, today: now
        )
        let streak = TodayPlanService.weekStreak(takes: takes, today: now)
        return NocturneCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("本周")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 16) {
                    stat("\(progress.doneMinutes) 分钟", "有效练习")
                    stat("\(streak.litDays.filter { $0 }.count) / 7", "streak 灯")
                    stat("\(takes.count)", "累计 take")
                }
                // 7 灯
                HStack(spacing: 0) {
                    let labels = ["一", "二", "三", "四", "五", "六", "日"]
                    ForEach(0..<7, id: \.self) { i in
                        VStack(spacing: 4) {
                            Circle()
                                .fill(streak.litDays[i] ? Color.amber : Color.clear)
                                .overlay(Circle().strokeBorder(
                                    streak.litDays[i] ? Color.amber : Color.borderInput, lineWidth: 1
                                ))
                                .frame(width: 10, height: 10)
                            Text(labels[i])
                                .font(.labelSm)
                                .foregroundStyle(Color.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.labelMono(15, weight: .medium))
                .foregroundStyle(Color.amber)
                .monospacedDigit()
            Text(label)
                .font(.labelSm)
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(Filter.allCases, id: \.self) { f in
                NocturneChip(title: f.rawValue, isSelected: filter == f) {
                    filter = f
                }
            }
            Spacer()
        }
    }

    private func rowTitle(_ take: Take) -> String {
        if take.isFreePlay { return take.title.isEmpty ? "自由弹奏" : take.title }
        let type = switch take.taskType {
        case "warmup": "热身"
        case "reward": "奖励曲"
        default: "主菜"
        }
        if let from = take.measureFrom, let to = take.measureTo {
            return "\(type) · 第\(from)–\(to)小节"
        }
        return type
    }
}

// MARK: - 月份过滤（纯逻辑，可单测）

/// S20 时间线的月份过滤：S22 观察卡的「引用 N 个 take」chip 点击后回档案，
/// 按该 periodKey 过滤 take。nil = 不过滤（档案默认全量视图）。
enum ArchiveMonthFilter {
    static func apply(takes: [Take], periodKey: String?) -> [Take] {
        guard let periodKey else { return takes }
        return takes.filter { MonthlyCalendar.periodKey(for: $0.startedAt) == periodKey }
    }
}

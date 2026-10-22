import SwiftData
import SwiftUI

// MARK: - S20 档案（对齐 Stitch 真值 S20：周翻页 + 三统计 + Neko 本周观察 + 6 周能力趋势 + take 时间线）
// 布局真值：docs/design-reference/screens/S20-archive/spec.md（revised S20.md，390pt tab 页）。
// 导航：本视图是 tab 页（AppFrameView 的 5 tab 之一），自身没有 NavigationStack，**不画 tab bar**；
//       take 详情沿用 sheet（TakeReportView），月报走 fullScreenCover（S22 无 tab），
//       问 Neko 走 fullScreenCover（ChatView freeform，天然隐藏 tab bar）。
// 诚实红线：
// - 三统计 / 本周观察 / 趋势的数字全部来自真实 take 与 TakeAnalysis 聚合
//   （WeeklyDigestBuilder + 自行按日 distinct），不编造；
// - 无判分分析或 weakTotal 为 nil 的 take 不画评分环、不显分，只给中性占位；
// - 6 周趋势不足 2 个有值周只显「再积累几周数据后显示趋势」，不补空周数值；
// - 弱总分是六维弱总分，不冒称「节奏稳定度」；不写真值示例的完成率 / ±120ms / 具体分值。

struct ArchiveView: View {
    @Query(sort: \Take.startedAt, order: .reverse) private var takes: [Take]
    @Query private var settingsList: [AppSettings]
    @Query(sort: \MonthlyReport.periodKey) private var monthlyReports: [MonthlyReport]
    @Query private var pieces: [Piece]
    @Query(sort: \TakeAnalysis.analyzedAt, order: .reverse) private var analyses: [TakeAnalysis]

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
    /// 周翻页锚点（落在目标周内的任意一天；默认本周，只做周粒度查询）
    @State private var weekAnchor = Date()
    /// 问 Neko（S18 自由问答；fullScreenCover 天然隐藏 tab bar）
    @State private var showNekoChat = false
    /// S17 导入 Zf 月度录像（fullScreenCover + NavigationStack：无 tab bar 的整页流程）
    @State private var showZFImport = false
    /// 导入成功后的单行 toast（不弹 modal）
    @State private var zfToast: String?
    @Environment(\.modelContext) private var context

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

    // MARK: 周窗口（翻页只推 7 天，下面所有周统计都以该周为窗口）

    private var weekStart: Date { WeekCalendar.weekStart(for: weekAnchor) }
    private var isCurrentWeek: Bool { WeekCalendar.weekKey(for: weekAnchor) == WeekCalendar.weekKey(for: now) }

    /// 周聚合（有效练习次数 / 时长 / take 数 / 目标 / 常练曲目；now 传锚点即按该周聚合）
    private var digest: WeeklyDigest {
        WeeklyDigestBuilder.build(
            takes: takes, pieces: pieces,
            goal: settings?.weeklyGoal ?? 3, now: weekAnchor
        )
    }

    /// 该周有有效练习（有 MIDI 且 ≥10 分钟）的不同日期数（digest.items 按日去重）
    private var validDayCount: Int {
        let calendar = WeekCalendar.calendar
        return Set(digest.items.map { calendar.startOfDay(for: $0.startedAt) }).count
    }

    /// 该周 7 灯（streak；锚点周）
    private var weekStreak: TodayPlanService.WeekStreak {
        TodayPlanService.weekStreak(takes: takes, today: weekAnchor)
    }

    /// 历史最长连续达标周（G8；全局统计，today 用真实 now，不随 weekAnchor 翻页变化；ADR-0007）
    private var goalStreak: TodayPlanService.WeeklyGoalStreak {
        TodayPlanService.weeklyGoalStreak(
            takes: takes, weeklyGoal: settings?.weeklyGoal ?? 3, today: now)
    }

    var body: some View {
        let lookup = ArchiveAnalysisLookup(analyses: analyses)
        let trend = trendPoints(lookup: lookup)

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 顶距 40：让开 AppFrameView 顶部连接胶囊（非今日/曲库页都显示）
                header.padding(.top, 40)

                weekPager.padding(.top, 12)

                weekStatBar.padding(.top, 12)

                weekStreakRow.padding(.top, 12)

                // G8：历史最长连续达标小字（全局历史最长，用真实 now；7 灯随翻页、此行不随——口径不同是有意的）
                goalStreakRow.padding(.top, 6)

                monthlyEntryCard.padding(.top, 12)

                // S17 入口恒显示：第一次导入时档案里还没有任何 take，不能按内容隐藏
                if ArchiveZFEntry.shouldShowEntry(takes: takes) {
                    zfImportEntry.padding(.top, 8)
                }

                if monthFilter != nil {
                    monthFilterRow.padding(.top, 12)
                }

                observationCard.padding(.top, 16)

                trendCard(points: trend).padding(.top, 16)

                timelineHeader.padding(.top, 20)

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
                        timelineRow(take, lookup: lookup)
                    }
                    .buttonStyle(ArchiveRowButtonStyle())
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            // 底部留白：让开问 Neko FAB 与 tab bar
            .padding(.bottom, 96)
        }
        .background(Color.canvas)
        .overlay(alignment: .bottomTrailing) {
            nekoFAB
        }
        .overlay(alignment: .bottom) {
            if let zfToast {
                zfToastBanner(zfToast)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: zfToast)
        .sheet(item: $selected) { take in
            TakeReportView(take: take)
        }
        .fullScreenCover(isPresented: $showMonthlyReport) {
            MonthlyReportView(initialPeriodKey: latestReport?.periodKey) { periodKey in
                monthFilter = periodKey
            }
        }
        .fullScreenCover(isPresented: $showNekoChat) {
            // S18 问 Neko：自由问答，不带 take 上下文（take 上下文由 S13 提供）
            ChatView(mode: .freeform, context: context)
        }
        .fullScreenCover(isPresented: $showZFImport) {
            // S17 无 tab 的整页流程：cover 天然隐藏 tab bar；内部 NavigationStack 保持 push 语义
            NavigationStack {
                S17ZFImportView { count in
                    showZFToast("已导入 \(count) 段到档案")
                }
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

    // MARK: A. 吸顶头（大标题 + 副标 + 日历钮＝月报入口）

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("档案")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(Color.textPrimary)
                Text("Archives")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textMuted)
                    .tracking(1.5)
                    .textCase(.uppercase)
            }
            Spacer(minLength: 0)
            Button {
                showMonthlyReport = true
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.amber)
                    .frame(width: 36, height: 36)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
            }
            .buttonStyle(ArchivePressScaleStyle())
            .accessibilityLabel("打开月度报告")
        }
    }

    // MARK: B. 周选择翻页器 + 三统计条 + 7 灯

    private var weekPager: some View {
        HStack(spacing: 6) {
            Button {
                pageWeek(-1)
            } label: {
                pagerIcon("chevron.left")
            }
            .buttonStyle(ArchivePressScaleStyle())
            .accessibilityLabel("上一周")

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.amber)
                    .frame(width: 6, height: 6)
                Text(weekRangeLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            Button {
                pageWeek(1)
            } label: {
                pagerIcon("chevron.right")
            }
            .buttonStyle(ArchivePressScaleStyle())
            .accessibilityLabel("下一周")
        }
    }

    private func pagerIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.textMuted)
            .frame(width: 28, height: 28)
            .background(Color.card, in: Circle())
            .overlay(Circle().strokeBorder(Color.border, lineWidth: 1))
    }

    private func pageWeek(_ delta: Int) {
        let calendar = WeekCalendar.calendar
        weekAnchor = calendar.date(byAdding: .day, value: 7 * delta, to: weekAnchor) ?? weekAnchor
    }

    private var weekRangeLabel: String {
        let calendar = WeekCalendar.calendar
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let range = "\(Self.monthDay(weekStart))–\(Self.monthDay(end))"
        // 只有锚点周就是当前周时才叫「本周」（翻到别的周如实只显区间）
        return isCurrentWeek ? "本周 (\(range))" : range
    }

    private var weekStatBar: some View {
        HStack(spacing: 0) {
            statCell(
                value: "\(validDayCount)", unit: " 天",
                label: "有效练习", valueColor: Color.textPrimary
            )
            statDivider
            statCell(
                value: totalDurationText, unit: "",
                label: "总时长", valueColor: Color.amber
            )
            statDivider
            statCell(
                value: "\(digest.takeCount)", unit: " 次",
                label: "完成 take", valueColor: Color.textPrimary
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.border)
            .frame(width: 1)
            .padding(.vertical, 4)
    }

    private func statCell(value: String, unit: String, label: String, valueColor: Color) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.labelMono(18, weight: .bold))
                    .foregroundStyle(valueColor)
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
                }
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    /// 总时长文案（真值「2 h 05 m」：整小时零分补零；不足 1 小时只说分钟）
    private var totalDurationText: String {
        let total = digest.totalDurationSec
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours) h \(String(format: "%02d", minutes)) m" }
        return "\(minutes) m"
    }

    /// 7 灯（原 weekStatsCard 的 streak 信息并到此处；随周翻页切换）
    private var weekStreakRow: some View {
        HStack(spacing: 0) {
            let streak = weekStreak
            let labels = ["一", "二", "三", "四", "五", "六", "日"]
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 4) {
                    Circle()
                        .fill(streak.litDays[i] ? Color.amber : Color.clear)
                        .overlay(
                            Circle().strokeBorder(
                                streak.litDays[i] ? Color.amber : Color.borderInput, lineWidth: 1
                            )
                        )
                        .frame(width: 10, height: 10)
                    Text(labels[i])
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
    }

    /// 历史最长连续达标小字（G8；与今日页同一纯函数，不另写算法）
    private var goalStreakRow: some View {
        Text("历史最长连续达标 \(goalStreak.longestWeeks) 周")
            .font(.labelSm)
            .foregroundStyle(Color.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
    }

    // MARK: 月报入口卡（真值日历钮已承载入口；本卡保留最新月报的真实信息，能力不丢）

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

    // MARK: S17 入口（导入 Zf 月度录像；一条入口，不改动现有列表行为）

    private var zfImportEntry: some View {
        Button {
            showZFImport = true
        } label: {
            NocturneCard {
                HStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.amber)
                        .frame(width: 28, height: 28)
                        .background(Color.canvas, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("导入 Zf 月度录像")
                            .font(.titleMd)
                            .foregroundStyle(Color.textPrimary)
                        Text("从相册挑选 Zf 拍的练琴视频，永久归档在本机")
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
        .accessibilityLabel("导入 Zf 月度录像")
    }

    /// 导入成功单行提示（不弹 modal；2.5 秒后自动消失）
    private func zfToastBanner(_ text: String) -> some View {
        Text(text)
            .font(.bodyMd)
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.cardElevated, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.amber.opacity(0.35), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.3), radius: 16, y: 4)
            .padding(.bottom, 88) // 让开问 Neko FAB 与 tab bar
            .allowsHitTesting(false)
    }

    private func showZFToast(_ text: String) {
        zfToast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if zfToast == text { zfToast = nil }
        }
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

    // MARK: C. Neko 本周观察卡（正文只写真实聚合）

    private var observationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.amber.opacity(0.2))
                    Image(systemName: "cat")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.amber)
                }
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(Color.amber.opacity(0.5), lineWidth: 1))

                Text("本周观察")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.textPrimary)

                Text("温和复盘")
                    .font(.labelMono(10))
                    .foregroundStyle(Color.amber)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.amber.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

                Spacer(minLength: 0)

                Text("周日 21:00 自动生成")
                    .font(.labelMono(10))
                    .foregroundStyle(Color.textMuted)
            }

            Text(observationText)
                .font(.bodySm)
                .foregroundStyle(Color.textPrimary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .modifier(ArchiveCardModifier(radius: 16))
    }

    /// 观察正文：只由 digest 真实字段拼装（次数 / 时长 / 常练曲目 / 周目标），
    /// 没有环比与逐小节数据源，故不写完成率、不写 ±ms 偏差。
    private var observationText: String {
        if digest.sessions == 0 {
            if digest.takeCount > 0 {
                return "本周还没有有效练习（有 MIDI 且满 10 分钟）；本周共录了 \(digest.takeCount) 条 take。"
            }
            return "本周还没有有效练习（有 MIDI 且满 10 分钟）。"
        }
        var lines: [String] = [
            "本周有效练习 \(digest.sessions) 次，共 \(DurationText.hoursMinutes(digest.totalDurationSec))"
        ]
        if let top = digest.topPieceTitle {
            lines.append("主要在练《\(top)》")
        }
        if digest.goalMet {
            lines.append("周目标（\(digest.goal) 次）已达成")
        } else {
            let remaining = max(digest.goal - digest.sessions, 1)
            lines.append("周目标（\(digest.goal) 次）还差 \(remaining) 次")
        }
        return lines.joined(separator: "；") + "。"
    }

    // MARK: D. 能力趋势卡（6 周 weakTotal 折线，诚实口径）

    /// 6 周趋势点：index 0 = 最早一周 … 5 = 锚点周；该周无判分分析不出点（不补空周数值）
    private func trendPoints(lookup: ArchiveAnalysisLookup) -> [ArchiveTrendPoint] {
        let calendar = WeekCalendar.calendar
        var points: [ArchiveTrendPoint] = []
        for back in stride(from: 5, through: 0, by: -1) {
            let index = 5 - back
            guard let anchor = calendar.date(byAdding: .day, value: -7 * back, to: weekAnchor) else { continue }
            let start = WeekCalendar.weekStart(for: anchor)
            let end = WeekCalendar.weekEnd(for: anchor)
            let values = takes
                .filter { $0.startedAt >= start && $0.startedAt < end }
                .compactMap { lookup.analysis(for: $0)?.weakTotal }
            guard !values.isEmpty else { continue }
            let average = Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
            points.append(ArchiveTrendPoint(index: index, value: average))
        }
        return points
    }

    /// 最新点相对「上一自然周」的差值；上一自然周无值 → nil（不显差值 pill）
    private func trendDelta(points: [ArchiveTrendPoint]) -> String? {
        guard let latest = points.last,
              let previous = points.last(where: { $0.index == latest.index - 1 }) else { return nil }
        let delta = latest.value - previous.value
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "−\(delta)" }
        return "0"
    }

    private func trendCard(points: [ArchiveTrendPoint]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("能力趋势")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.textPrimary)
                Text("· 弱总分")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.amber)
                Spacer(minLength: 0)
                if let latest = points.last {
                    Text("最新 \(latest.value)")
                        .font(.labelMono(11))
                        .foregroundStyle(Color.amber)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.amber.opacity(0.10), in: Capsule())
                    if let delta = trendDelta(points: points) {
                        Text(delta)
                            .font(.labelMono(11))
                            .foregroundStyle(Color.amber)
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.amber.opacity(0.10), in: Capsule())
                    }
                }
            }

            if points.count >= 2 {
                ArchiveTrendChart(points: points)
                    .frame(height: 96)
            } else {
                Text("再积累几周数据后显示趋势")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
            }

            // 手型趋势：依赖相机批次（blocked），只留占位，不画假数据
            HStack(spacing: 8) {
                Image(systemName: "video")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textMuted)
                Text("手型趋势：录像后展示")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                Spacer(minLength: 0)
                Text("暂无数据")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.canvas, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
            }
            .padding(.top, 4)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.border.opacity(0.6))
                    .frame(height: 1)
            }
        }
        .modifier(ArchiveCardModifier(radius: 16))
    }

    // MARK: E. Take 时间线（卡片行 + 评分环）

    private var timelineHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Take 时间线")
                .font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 0)
            Text("共 \(filtered.count) 条")
                .font(.labelSm)
                .foregroundStyle(Color.textMuted)
                .monospacedDigit()
        }
    }

    private func timelineRow(_ take: Take, lookup: ArchiveAnalysisLookup) -> some View {
        HStack(spacing: 12) {
            scoreBadge(take: take, lookup: lookup)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rowTitle(take))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    typeBadge(take)
                    if VideoUIFormatting.hasVideo(take) {
                        // 只有标记，不新增点击目标：整行仍进 Take 报告
                        Image(systemName: "video.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.amber.opacity(0.8))
                            .accessibilityLabel("有录像")
                    }
                }
                Text(metaText(take))
                    .font(.labelMono(11))
                    .foregroundStyle(Color.textMuted)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(Color.textMuted)
        }
        .padding(12)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 评分环：仅当该 take 有判分分析且 weakTotal 非 nil 时画；否则中性占位，不编分
    private func scoreBadge(take: Take, lookup: ArchiveAnalysisLookup) -> some View {
        let value = lookup.analysis(for: take)?.weakTotal
        return ZStack {
            if let value {
                Circle()
                    .stroke(Color.border, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(value) / 100)
                    .stroke(Color.amber, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(value)")
                    .font(.labelMono(11, weight: .bold))
                    .foregroundStyle(Color.amber)
                    .monospacedDigit()
            } else {
                Circle()
                    .strokeBorder(Color.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Text("—")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
        }
        .frame(width: 40, height: 40)
    }

    /// 类型 badge（真值配色：热身 #332D29/muted、主菜琥珀 15% 底 30% 边、奖励曲琥珀 20% 底 40% 边）
    private func typeBadge(_ take: Take) -> some View {
        let style = typeBadgeStyle(take)
        return Text(style.title)
            .font(.system(size: 10))
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(style.background, in: RoundedRectangle(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(style.border, lineWidth: 1))
    }

    private struct TypeBadgeStyle {
        let title: String
        let background: Color
        let foreground: Color
        let border: Color
    }

    private func typeBadgeStyle(_ take: Take) -> TypeBadgeStyle {
        if take.isFreePlay {
            return TypeBadgeStyle(
                title: "自由弹奏",
                background: Color.amber.opacity(0.10), foreground: Color.amber, border: Color.clear
            )
        }
        switch take.taskType {
        case "warmup":
            return TypeBadgeStyle(
                title: "热身",
                background: Color.border, foreground: Color.textMuted, border: Color.clear
            )
        case "reward":
            return TypeBadgeStyle(
                title: "奖励曲",
                background: Color.amber.opacity(0.20), foreground: Color.amber, border: Color.amber.opacity(0.4)
            )
        case "review":
            // Stage B §3d：复习 take 落自己口径，不掉进 default「主菜」
            return TypeBadgeStyle(
                title: "复习",
                background: Color.border, foreground: Color.textMuted, border: Color.clear
            )
        case "zfImport":
            // ADR-0012：Zf 月度录像不是「主菜」，单独 badge
            return TypeBadgeStyle(
                title: "Zf",
                background: Color.amber.opacity(0.10), foreground: Color.amber, border: Color.amber.opacity(0.3)
            )
        default:
            return TypeBadgeStyle(
                title: "主菜",
                background: Color.amber.opacity(0.15), foreground: Color.amber, border: Color.amber.opacity(0.3)
            )
        }
    }

    /// 元信息行：真实日期时间 · ♩=速度（为 0 省略）· 时长
    private func metaText(_ take: Take) -> String {
        var parts: [String] = [Self.timestampFormatter.string(from: take.startedAt)]
        if take.tempoAvg > 0 { parts.append("♩=\(take.tempoAvg)") }
        parts.append("\(take.durationSec / 60)分\(take.durationSec % 60)秒")
        return parts.joined(separator: " · ")
    }

    private func rowTitle(_ take: Take) -> String {
        // Zf 月度录像走自己的标题（Stage A 已写好「9/14 Zf 录像」；不落「主菜」）
        if let zfTitle = ArchiveZFEntry.rowTitle(for: take) { return zfTitle }
        // 曲目真实标题优先（真值时间线行显曲名，类型交给 badge）
        if let pieceId = take.pieceId,
           let title = pieces.first(where: { $0.entityId == pieceId })?.title,
           !title.isEmpty {
            return title
        }
        if take.isFreePlay { return take.title.isEmpty ? "自由弹奏" : take.title }
        let type = switch take.taskType {
        case "warmup": "热身"
        case "reward": "奖励曲"
        case "review": "复习" // Stage B §3d：复习标题正确（不落 default 主菜）
        default: "主菜"
        }
        if let from = take.measureFrom, let to = take.measureTo {
            return "\(type) · 第\(from)–\(to)小节"
        }
        return type
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

    // MARK: F. 问 Neko FAB（琥珀胶囊，悬浮于 tab bar 之上）

    private var nekoFAB: some View {
        Button {
            showNekoChat = true
        } label: {
            HStack(spacing: 6) {
                Text("问 Neko")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.canvas)
                Image(systemName: "cat")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.canvas)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.amber, in: Capsule())
            .shadow(color: Color.amber.opacity(0.2), radius: 12, y: 4)
        }
        .buttonStyle(ArchivePressScaleStyle())
        .padding(.trailing, 16)
        // 本视图自身已被 AppFrameView 的 tab bar safeAreaInset 顶上，bottom 12 即贴 tab 栏上方
        .padding(.bottom, 12)
        .accessibilityLabel("问 Neko")
    }

    // MARK: 日期格式（本地时区，跟随 WeekCalendar）

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = WeekCalendar.calendar
        formatter.timeZone = WeekCalendar.calendar.timeZone
        formatter.dateFormat = "M/d"
        return formatter
    }()

    private static func monthDay(_ date: Date) -> String {
        monthDayFormatter.string(from: date)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = WeekCalendar.calendar
        formatter.timeZone = WeekCalendar.calendar.timeZone
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()
}

// MARK: - take → 判分分析查找（与 TakeReportView.scoringAnalysis 同口径的私有等价实现）

/// 档案页只读查找：take.analysisId 命中 entityId 优先，否则同 takeId + 当前引擎版本
///（同 take 多条时取 analyzedAt 最新）。查不到 = 该 take 没有可显的判分结果。
private struct ArchiveAnalysisLookup {
    private let byEntityId: [UUID: TakeAnalysis]
    private let byTakeId: [UUID: TakeAnalysis]

    init(analyses: [TakeAnalysis]) {
        var byEntity: [UUID: TakeAnalysis] = [:]
        var byTake: [UUID: TakeAnalysis] = [:]
        for row in analyses {
            if byEntity[row.entityId] == nil { byEntity[row.entityId] = row }
            if row.engineVersion != ScoringOrchestrator.engineVersion { continue }
            if let existing = byTake[row.takeId], existing.analyzedAt >= row.analyzedAt { continue }
            byTake[row.takeId] = row
        }
        byEntityId = byEntity
        byTakeId = byTake
    }

    func analysis(for take: Take) -> TakeAnalysis? {
        if let id = take.analysisId, let row = byEntityId[id] { return row }
        return byTakeId[take.entityId]
    }
}

// MARK: - 6 周能力趋势折线（真值：高 96、虚线网格、面积渐变、线宽 2.5、最新点放大标数值）

/// 一个趋势点：index = 6 周窗口内的周序（0 = 最早周，5 = 锚点周）；value = 该周 weakTotal 均值
private struct ArchiveTrendPoint: Identifiable {
    let index: Int
    let value: Int

    var id: Int { index }
}

private struct ArchiveTrendChart: View {
    let points: [ArchiveTrendPoint]

    /// 6 周窗口（周序 0…5）
    private let weekCount = 6
    private let chartHeight: CGFloat = 96
    /// 绘图区上下留白：顶部给数值标签，底部给基线
    private let plotTop: CGFloat = 22
    private let plotBottom: CGFloat = 90
    /// 左右留白：首末点的圆点与标签不被裁掉
    private let plotInset: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let left = plotInset
            let right = max(width - plotInset, left + 1)
            ZStack {
                gridLines(left: left, right: right)
                if points.count >= 2 {
                    areaPath(left: left, right: right)
                    linePath(left: left, right: right)
                }
                ForEach(points) { point in
                    pointView(point, left: left, right: right)
                }
            }
        }
        .frame(height: chartHeight)
        .frame(maxWidth: .infinity)
    }

    private func x(for index: Int, left: CGFloat, right: CGFloat) -> CGFloat {
        left + CGFloat(index) / CGFloat(weekCount - 1) * (right - left)
    }

    /// 分值 0–100 映射到绘图区（weakTotal 是百分制弱总分）
    private func y(for value: Int) -> CGFloat {
        let clamped = min(max(value, 0), 100)
        return plotBottom - (plotBottom - plotTop) * CGFloat(clamped) / 100
    }

    private func gridLines(left: CGFloat, right: CGFloat) -> some View {
        ZStack {
            // 25 / 50 / 75 虚线网格（真值 dash 3-3）
            Path { path in
                for value in [25, 50, 75] {
                    let y = y(for: value)
                    path.move(to: CGPoint(x: left, y: y))
                    path.addLine(to: CGPoint(x: right, y: y))
                }
            }
            .stroke(Color.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            // 0 基线实线
            Path { path in
                path.move(to: CGPoint(x: left, y: plotBottom))
                path.addLine(to: CGPoint(x: right, y: plotBottom))
            }
            .stroke(Color.border, lineWidth: 1)
        }
    }

    private func areaPath(left: CGFloat, right: CGFloat) -> some View {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: x(for: first.index, left: left, right: right), y: plotBottom))
            for point in points {
                path.addLine(to: CGPoint(x: x(for: point.index, left: left, right: right), y: y(for: point.value)))
            }
            path.addLine(to: CGPoint(x: x(for: last.index, left: left, right: right), y: plotBottom))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [Color.amber.opacity(0.28), Color.amber.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func linePath(left: CGFloat, right: CGFloat) -> some View {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: CGPoint(x: x(for: first.index, left: left, right: right), y: y(for: first.value)))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: x(for: point.index, left: left, right: right), y: y(for: point.value)))
            }
        }
        .stroke(Color.amber, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }

    private func pointView(_ point: ArchiveTrendPoint, left: CGFloat, right: CGFloat) -> some View {
        let isLatest = point.id == points.last?.id
        return ZStack {
            Circle()
                .fill(isLatest ? Color.amber : Color.canvas)
                .overlay(
                    Circle().strokeBorder(
                        isLatest ? Color.textPrimary : Color.amber,
                        lineWidth: isLatest ? 1.5 : 2
                    )
                )
                .frame(width: isLatest ? 9 : 6, height: isLatest ? 9 : 6)
            Text("\(point.value)")
                .font(isLatest ? .system(size: 10, weight: .bold) : .labelMono(9))
                .foregroundStyle(isLatest ? Color.textPrimary : Color.textMuted)
                .monospacedDigit()
                .offset(y: isLatest ? -15 : -12)
        }
        .position(
            x: x(for: point.index, left: left, right: right),
            y: y(for: point.value)
        )
    }
}

// MARK: - 档案页私有组件

/// 档案卡容器（真值：card 底 + 1pt 发丝边；半径由分区给：观察/趋势 r16）
private struct ArchiveCardModifier: ViewModifier {
    var radius: CGFloat
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.border, lineWidth: 1))
    }
}

/// 时间线行：card 底 r12，按压时发丝边转琥珀 60%
private struct ArchiveRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(configuration.isPressed ? Color.amber.opacity(0.6) : Color.border, lineWidth: 1)
            )
    }
}

/// 按压缩放 0.95（真值：FAB / 日历钮 / 周翻页钮按压 scale 0.95）
private struct ArchivePressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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

// MARK: - S17 入口与 Zf 行口径（纯逻辑，可单测）

enum ArchiveZFEntry {

    /// 入口恒显示：第一次导入 Zf 录像时档案里还什么都没有，
    /// 若按 take 数/筛选结果隐藏，用户永远进不去（ADR-0012）。
    static func shouldShowEntry(takes: [Take]) -> Bool {
        true
    }

    /// zfImport take 的时间线标题；非 zf 返回 nil（走原有曲目/类型标题）
    static func rowTitle(for take: Take) -> String? {
        guard take.taskType == "zfImport" else { return nil }
        return take.title.isEmpty ? "Zf 录像" : take.title
    }
}

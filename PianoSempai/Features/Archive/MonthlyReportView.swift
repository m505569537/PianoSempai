import SwiftData
import SwiftUI

// MARK: - S22 月度报告详情（长滚动，无 tab；由 S20 档案以 fullScreenCover 进入）
// 布局真值：docs/design-reference/screens/S22-monthly-report/spec.md。
// 数据：历史月读库里的 MonthlyReport（快照冻结）；当前月用 MonthlyReportBuilder 实时 build 预览，不落库。
// 两个如实降级点（红线 1：不编造）：
// 1. 教材路线只显当前值——无月内起点历史、无拜厄/哈农总数分母，所以不画进度条、不显推进百分比；
//    599 未解锁是锁行（0.5 透明），只有真实预计周数才带「预计第 N 周解锁」。
// 2. 手型/侧拍：无视频模型（refsVideoCount 恒 0），手型趋势整段不渲染（不是渲染「0 条」），
//    观察卡只渲染「引用 N 个 take」chip。
// 写权边界（红线 3）：本视图只写 PracticeNote（且只在用户点「把观察写进笔记」时）；
// 观察生成/重试走 MonthlyReportCoordinator，只回写 MonthlyReport 的观察字段。

struct MonthlyReportView: View {
    /// 进入时定位的月份（"yyyy-MM"；nil = 当前月）
    let initialPeriodKey: String?
    /// 引用 chip 点击 → 回 S20 档案并按该月过滤 take（跨层路由由调用方决定怎么呈现）
    var onJumpToArchive: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \MonthlyReport.periodKey) private var reports: [MonthlyReport]
    @Query private var takes: [Take]
    @Query private var analyses: [TakeAnalysis]
    @Query private var plans: [DailyPlan]
    @Query private var gates: [GateEvent]
    @Query private var pathStates: [CoursePathState]

    @State private var selectedMonth: Date
    @State private var coordinator: MonthlyReportCoordinator?
    /// 「已写入」只做本视图态（不做跨会话去重，注释见 writeObservationToNote）
    @State private var wroteNote = false
    @State private var pdfURL: URL?
    @State private var exportError: String?

    init(initialPeriodKey: String? = nil, onJumpToArchive: ((String) -> Void)? = nil) {
        self.initialPeriodKey = initialPeriodKey
        self.onJumpToArchive = onJumpToArchive
        let fallback = MonthlyCalendar.monthStart(for: Date())
        _selectedMonth = State(initialValue: MonthlyCalendar.monthStart(periodKey: initialPeriodKey ?? "") ?? fallback)
    }

    // MARK: 派生数据

    private var today: Date { Date() }
    private var currentMonthStart: Date { MonthlyCalendar.monthStart(for: today) }

    /// 选中月的快照：当前月实时预览；历史月读库；无月报的历史月给 nil（空态）
    private var snapshot: MonthlyReportSnapshot? {
        let monthStart = MonthlyCalendar.monthStart(for: selectedMonth)
        if monthStart == currentMonthStart {
            return MonthlyReportBuilder.build(
                now: selectedMonth,
                takes: takes,
                analyses: analyses,
                plans: plans,
                gates: gates,
                pathState: pathStates.first
            )
        }
        return storedReport(monthStart)?.snapshot
    }

    private func storedReport(_ monthStart: Date) -> MonthlyReport? {
        let key = MonthlyCalendar.periodKey(for: monthStart)
        return reports.first { $0.periodKey == key }
    }

    private var months: (prev: Date, current: Date, next: Date) {
        MonthlyCalendar.monthStarts(around: selectedMonth)
    }

    /// 月份 pill 可点性：未来月置灰；历史月没有 MonthlyReport 置灰；当前月恒可看（预览）
    private func isMonthEnabled(_ monthStart: Date) -> Bool {
        if monthStart >= currentMonthStart { return monthStart == currentMonthStart }
        return storedReport(monthStart) != nil
    }

    /// 同年显「9 月」，跨年显「2026 年 12 月」（12→1 看不出跨年）
    private func monthLabel(_ monthStart: Date) -> String {
        let (year, month) = MonthlyCalendar.yearMonth(for: monthStart)
        let currentYear = MonthlyCalendar.yearMonth(for: currentMonthStart).year
        return MonthlyReportText.shortMonthLabel(year: year, month: month, sameYear: year == currentYear)
    }

    // MARK: 视图

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.top, 8)

                if let snapshot {
                    titleRow(snapshot).padding(.top, 4)
                    monthPills.padding(.top, 16)
                    statsCard(snapshot).padding(.top, 16)
                    routeCard(snapshot).padding(.top, 12)
                    warmupCard(snapshot).padding(.top, 12)
                    rhythmCard(snapshot).padding(.top, 12)
                    observationCard(snapshot).padding(.top, 12)
                    bottomButtons(snapshot).padding(.top, 20)
                    if let exportError {
                        Text(exportError)
                            .font(.labelSm)
                            .foregroundStyle(Color.danger)
                            .padding(.top, 10)
                    }
                } else {
                    titleRow(nil).padding(.top, 4)
                    emptyState.padding(.top, 48)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color.canvas)
        .preferredColorScheme(.dark)
        .task { coordinator = MonthlyReportCoordinator.live(context: context) }
        .sheet(isPresented: Binding(
            get: { pdfURL != nil },
            set: { if !$0 { pdfURL = nil } }
        )) {
            // S22「导出 PDF」走系统分享（复用 S26 导出的 ShareSheet，不另造）
            if let pdfURL {
                ShareSheet(items: [pdfURL])
            }
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.textBody)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("返回")
            Spacer()
        }
    }

    private func titleRow(_ snapshot: MonthlyReportSnapshot?) -> some View {
        let text: String
        if let snapshot {
            text = MonthlyReportText.headerTitle(year: snapshot.year, month: snapshot.month)
        } else {
            let (year, month) = MonthlyCalendar.yearMonth(for: selectedMonth)
            text = MonthlyReportText.headerTitle(year: year, month: month)
        }
        return Text(text)
            .font(.headlineLg)
            .foregroundStyle(Color.textPrimary)
    }

    private var monthPills: some View {
        HStack(spacing: 8) {
            monthPill(monthStart: months.prev, leading: "‹")
            monthPill(monthStart: months.current, leading: nil, isSelected: true)
            monthPill(monthStart: months.next, leading: nil, trailing: "›")
        }
    }

    private func monthPill(monthStart: Date, leading: String? = nil, trailing: String? = nil, isSelected: Bool = false) -> some View {
        let enabled = isMonthEnabled(monthStart)
        return Button {
            selectedMonth = monthStart
        } label: {
            HStack(spacing: 4) {
                if let leading { Text(leading).font(.labelMd) }
                Text(monthLabel(monthStart))
                    .font(.bodyMd)
                if let trailing { Text(trailing).font(.labelMd) }
            }
            .foregroundStyle(isSelected ? Color.amber : (enabled ? Color.textBody : Color.textMuted))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.card : Color.surface, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Color.amber : Color.border,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled || isSelected ? 1 : 0.5)
        .accessibilityLabel("\(monthLabel(monthStart))月报")
    }

    // MARK: 2x2 统计卡

    private func statsCard(_ snapshot: MonthlyReportSnapshot) -> some View {
        let cells = MonthlyReportText.statCells(snapshot)
        return NocturneCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    statCell(cells[0])
                    statCell(cells[1])
                }
                HStack(spacing: 12) {
                    statCell(cells[2])
                    statCell(cells[3])
                }
            }
        }
    }

    private func statCell(_ cell: MonthlyStatCell) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(cell.value)
                .font(.labelMono(19, weight: .medium))
                .foregroundStyle(Color.amber)
                .monospacedDigit()
            Text(cell.label)
                .font(.labelSm)
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 教材路线卡（只显当前值）

    private func routeCard(_ snapshot: MonthlyReportSnapshot) -> some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("教材路线")
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(MonthlyReportText.routeDeclaration)
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                }
                ForEach(MonthlyReportText.routeRows(snapshot), id: \.title) { row in
                    HStack {
                        Text(row.title)
                            .font(.bodyMd)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        if !row.detail.isEmpty {
                            Text(row.detail)
                                .font(.labelMono(13))
                                .foregroundStyle(row.isLocked ? Color.textMuted : Color.amber)
                                .monospacedDigit()
                        }
                    }
                    .opacity(row.isLocked ? 0.5 : 1)
                }
            }
        }
    }

    // MARK: 热身与门禁卡

    private func warmupCard(_ snapshot: MonthlyReportSnapshot) -> some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("热身与门禁")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)

                HStack {
                    Text("热身完成率")
                        .font(.bodyMd)
                        .foregroundStyle(Color.textBody)
                    Spacer()
                    Text(MonthlyReportText.warmupText(snapshot))
                        .font(.labelMono(14, weight: .medium))
                        .foregroundStyle(snapshot.warmupCompletionPct == nil ? Color.textMuted : Color.success)
                        .monospacedDigit()
                }

                HStack(alignment: .top, spacing: 10) {
                    if snapshot.overrideCount > 0 {
                        // 强开行 danger 左缘（S22 视觉规范）
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.danger)
                            .frame(width: 3)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(MonthlyReportText.overrideText(snapshot))
                            .font(.bodyMd)
                            .foregroundStyle(snapshot.overrideCount > 0 ? Color.danger : Color.textBody)
                        let chips = MonthlyReportText.overrideReasonChips(snapshot)
                        if !chips.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(chips, id: \.self) { chip in
                                    Text(chip)
                                        .font(.labelSm)
                                        .foregroundStyle(Color.textBody)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.surface, in: Capsule())
                                        .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
                                }
                            }
                        }
                    }
                }

                Text(MonthlyReportText.overrideFootnote)
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    // MARK: 节奏稳定度卡

    private func rhythmCard(_ snapshot: MonthlyReportSnapshot) -> some View {
        let rhythm = MonthlyReportText.rhythm(snapshot)
        // 周节奏点：nil 周（该周无分析）不出点——不补点、不插值（红线 1）
        let points = rhythmPoints(snapshot.weeklyRhythmScores)
        return NocturneCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("节奏稳定度 月度趋势")
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: 4)
                    // 差值徽章只在真能画出趋势（≥2 个真实点）时才显
                    if points.count >= 2, let first = points.first, let last = points.last {
                        rhythmDeltaBadge(first: first.value, last: last.value)
                    }
                }
                if points.count >= 2 {
                    rhythmTrendChart(points: points, weekCount: snapshot.weeklyRhythmScores.count)
                } else {
                    // 数据不足：沿用 .insufficient 口径（不画图、不编差值）
                    Text(MonthlyReportText.rhythmText(rhythm))
                        .font(.labelMono(15))
                        .foregroundStyle(rhythm == .insufficient ? Color.textMuted : Color.amber)
                        .monospacedDigit()
                }
            }
        }
    }

    /// 首末周分差徽章：「52 → 71 」+ 带符号差值（>=0 success，<0 danger，不强行绿色）
    private func rhythmDeltaBadge(first: Int, last: Int) -> some View {
        let delta = last - first
        return HStack(spacing: 4) {
            Text("\(first) → \(last) ")
                .font(.labelMono(12))
                .foregroundStyle(Color.amber)
                .monospacedDigit()
            Text(MonthlyReportText.signed(delta))
                .font(.labelMono(11, weight: .semibold))
                .foregroundStyle(delta >= 0 ? Color.success : Color.danger)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Color.amber.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.amber.opacity(0.25), lineWidth: 1))
    }

    /// 月度趋势图：点全部来自 weeklyRhythmScores，有几周画几周（nil 周在 X 轴留空位）。
    private func rhythmTrendChart(points: [RhythmPoint], weekCount: Int) -> some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let coordinates = rhythmCoordinates(points: points, weekCount: weekCount, size: proxy.size)
                ZStack {
                    // 三条横向参考线（竖向三等分）：只作视觉网格，不标刻度数字（避免假刻度）
                    Path { path in
                        let height = proxy.size.height
                        for y in [height / 6, height / 2, height * 5 / 6] {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        }
                    }
                    .stroke(Color.border, style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))

                    // 面积：折线顶点闭合到底部，琥珀纵向渐变（0.25 → 0）
                    Path { path in
                        guard let first = coordinates.first, let last = coordinates.last else { return }
                        path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                        path.addLines(coordinates)
                        path.addLine(to: CGPoint(x: last.x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [Color.amber.opacity(0.25), Color.amber.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))

                    // 折线：2.5px 琥珀，round 连接/端点
                    Path { path in
                        guard let first = coordinates.first else { return }
                        path.move(to: first)
                        path.addLines(coordinates)
                    }
                    .stroke(Color.amber, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    // 周点：非末周 r3.5（surface 填充 + 2px 琥珀描边）；末周 r4.5（琥珀填充 + 1.5px card 描边）
                    ForEach(Array(coordinates.enumerated()), id: \.offset) { index, point in
                        let isLast = index == coordinates.count - 1
                        Circle()
                            .fill(isLast ? Color.amber : Color.surface)
                            .overlay(Circle().stroke(isLast ? Color.card : Color.amber, lineWidth: isLast ? 1.5 : 2))
                            .frame(width: isLast ? 9 : 7, height: isLast ? 9 : 7)
                            .position(point)
                    }

                    // 数值标签：首周放点下，其余放点上（避免压线）；末周琥珀 semibold，其余 muted
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        let isLast = index == points.count - 1
                        Text("\(point.value)")
                            .font(.labelMono(isLast ? 10 : 9, weight: isLast ? .semibold : .regular))
                            .foregroundStyle(isLast ? Color.amber : Color.textMuted)
                            .monospacedDigit()
                            .position(
                                x: coordinates[index].x,
                                y: coordinates[index].y + (index == 0 ? 12 : -12)
                            )
                    }
                }
            }
            .frame(height: 104)

            rhythmWeekAxis(weekCount: weekCount)
        }
        .padding(10)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border.opacity(0.6), lineWidth: 1))
    }

    /// X 轴周标签行：首尾「第 N 周 (WN)」，中间只显「WN」；N 取真实周数（nil 周也占位）。
    private func rhythmWeekAxis(weekCount: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<max(weekCount, 1), id: \.self) { index in
                Text(rhythmWeekAxisLabel(index: index, count: weekCount))
                    .font(.labelMono(11))
                    .foregroundStyle(Color.textMuted)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 6)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.border.opacity(0.5))
                .frame(height: 1)
        }
    }

    private func rhythmWeekAxisLabel(index: Int, count: Int) -> String {
        let week = index + 1
        let short = "W\(week)"
        // 首尾用「第 X 周 (WX)」，中间只显「WX」
        return (index == 0 || index == count - 1) ? "第 \(week) 周 (\(short))" : short
    }

    /// 一个真实周节奏点（周下标 0-based + 该周周均分）
    private struct RhythmPoint {
        let weekIndex: Int
        let value: Int
    }

    /// 从 [Int?] 取点：nil 周（无分析）直接跳过，不补点、不插值。
    private func rhythmPoints(_ weeks: [Int?]) -> [RhythmPoint] {
        weeks.enumerated().compactMap { index, value in
            value.map { RhythmPoint(weekIndex: index, value: $0) }
        }
    }

    /// 折线坐标：x 按周等分（首尾各留少量边距），y 按这批点真实 min/max 归一化
    /// （全相等时取中线，上下都留余量画水平线；不写死 0–100）。
    private func rhythmCoordinates(points: [RhythmPoint], weekCount: Int, size: CGSize) -> [CGPoint] {
        let values = points.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let span = maxValue - minValue
        let topPad: CGFloat = 13    // 点上标签位
        let bottomPad: CGFloat = 15 // 首周标签在点下
        let sidePad: CGFloat = 12   // 首尾点各留少量左右边距
        let plotHeight = max(size.height - topPad - bottomPad, 1)
        let plotWidth = max(size.width - sidePad * 2, 1)
        let weeks = max(weekCount - 1, 1)
        return points.map { point in
            let x = sidePad + plotWidth * CGFloat(point.weekIndex) / CGFloat(weeks)
            let ratio: CGFloat = span == 0 ? 0.5 : CGFloat(point.value - minValue) / CGFloat(span)
            return CGPoint(x: x, y: topPad + plotHeight * (1 - ratio))
        }
    }

    // MARK: Neko 本月观察卡

    private func observationCard(_ snapshot: MonthlyReportSnapshot) -> some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "cat")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.amber)
                    Text("Neko 的本月观察")
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                }

                switch snapshot.observationStatus {
                case "ok":
                    if !snapshot.observationTitle.isEmpty {
                        Text(snapshot.observationTitle)
                            .font(.headlineSm)
                            .foregroundStyle(Color.textPrimary)
                    }
                    Text(snapshot.observationBody)
                        .font(.bodySm)
                        .leading(19, fontSize: 12)
                        .foregroundStyle(Color.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                    if let model = snapshot.observationProviderModel, !model.isEmpty {
                        // 命中服务商·模型原样回显（可溯）
                        Text(model)
                            .font(.labelSm)
                            .foregroundStyle(Color.textMuted)
                    }
                case "failed":
                    Text("本次观察生成失败（统计不受影响）。可以在「我的 · 服务商链」里检查 Key 与模型后重试。")
                        .font(.bodySm)
                        .foregroundStyle(Color.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        retryObservation(snapshot)
                    } label: {
                        HStack(spacing: 5) {
                            if coordinator?.isRetrying == true {
                                ProgressView().scaleEffect(0.8)
                            }
                            Text(coordinator?.isRetrying == true ? "重试中…" : "重试")
                        }
                    }
                    .buttonStyle(NoteActionButtonStyle())
                    .disabled(coordinator?.isRetrying == true)
                default:
                    // pending：后台协调器会回填，这里不是死按钮
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("观察生成中…")
                            .font(.bodySm)
                            .foregroundStyle(Color.textMuted)
                    }
                }

                // 引用 chip：只渲染有真实证据的那几条（侧拍恒 0 条 → 不渲染）
                HStack(spacing: 6) {
                    ForEach(MonthlyReportText.observationChips(snapshot), id: \.text) { chip in
                        observationChip(chip, periodKey: snapshot.periodKey)
                    }
                }
            }
        }
    }

    /// 引用 chip：take chip 可点 → 回 S20 档案按该月过滤；侧拍 chip（当前不产生）不可点——
    /// 没有侧拍列表页面，不给假入口。
    private func observationChip(_ chip: MonthlyReportText.ObservationChip, periodKey: String) -> some View {
        let label = {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 10))
                Text(chip.text)
                if chip.kind == .takes {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                }
            }
            .font(.labelSm)
            .foregroundStyle(Color.amber)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.amber.opacity(0.35), lineWidth: 1))
        }
        return Group {
            if chip.kind == .takes {
                Button {
                    onJumpToArchive?(periodKey)
                    dismiss()
                } label: { label() }
                .buttonStyle(.plain)
                .accessibilityLabel("查看 \(chip.text) 的练习记录")
            } else {
                label()
            }
        }
    }

    // MARK: 底部双按钮

    private func bottomButtons(_ snapshot: MonthlyReportSnapshot) -> some View {
        HStack(spacing: 12) {
            Button {
                exportPDF(snapshot)
            } label: {
                Text("导出 PDF")
            }
            .buttonStyle(SecondaryButtonStyle(cornerRadius: 12))

            Button {
                writeObservationToNote(snapshot)
            } label: {
                Text(wroteNote ? "已写入" : "把观察写进笔记")
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: canWriteNote(snapshot), cornerRadius: 12))
            .disabled(!canWriteNote(snapshot))
        }
    }

    private func canWriteNote(_ snapshot: MonthlyReportSnapshot) -> Bool {
        snapshot.observationStatus == "ok" && !wroteNote
    }

    // MARK: 空态

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 26))
                .foregroundStyle(Color.textMuted.opacity(0.6))
            Text(MonthlyReportText.emptyHistoryText)
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 动作

    private func retryObservation(_ snapshot: MonthlyReportSnapshot) {
        guard coordinator?.isRetrying != true else { return }
        Task { await coordinator?.retryObservation(for: snapshot.periodKey) }
    }

    /// 写进笔记：只此一处写 PracticeNote，且只在用户点按钮时发生（红线 3）。
    /// 去重只做本视图态（写过就置灰「已写入」）；不做跨会话去重——重复写只是多一条笔记，
    /// 不污染统计/课程状态，比悄悄吞掉用户的第二次点击更诚实。
    private func writeObservationToNote(_ snapshot: MonthlyReportSnapshot) {
        guard canWriteNote(snapshot) else { return }
        let title = snapshot.observationTitle.isEmpty
            ? MonthlyReportText.observationFallbackTitle
            : snapshot.observationTitle
        context.insert(PracticeNote(
            kind: "manual",
            title: title,
            // 正文带上月份出处：笔记列表里能看出这条观察属于哪个月（月份是真实统计，不是编的）
            body: "【\(snapshot.year) 年 \(snapshot.month) 月月报观察】\n\n\(snapshot.observationBody)",
            linkedTakeId: nil
        ))
        try? context.save()
        wroteNote = true
    }

    /// 生成 PDF → 写临时文件 → 系统分享。失败给行内错误（S22：静态汇总，失败不崩）。
    private func exportPDF(_ snapshot: MonthlyReportSnapshot) {
        exportError = nil
        let data = MonthlyReportPDF.makePDF(snapshot: snapshot)
        let name = "monthly-\(snapshot.periodKey).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            pdfURL = url
        } catch {
            exportError = "PDF 生成失败：\(error.localizedDescription)"
        }
    }
}

#Preview {
    MonthlyReportView()
        .preferredColorScheme(.dark)
}

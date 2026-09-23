import SwiftData
import SwiftUI

// MARK: - 今日 tab：S07b（未定级空状态）/ S07（已定级常态）自动切换

/// 练习室路由（fullScreenCover(item:) 需要 Identifiable）
struct PracticeTaskRoute: Identifiable {
    let id: String // warmup / main / reward
}

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    @Query(sort: \PlacementResult.createdAt, order: .reverse) private var placementResults: [PlacementResult]
    @Query private var dailyPlans: [DailyPlan]
    @Query private var tasks: [PracticeTask]
    @Query private var gateEvents: [GateEvent]
    @Query private var takes: [Take]

    let onBrowseLibrary: () -> Void

    @State private var plan: DailyPlan?
    @State private var now = Date()
    @State private var showOverrideModal = false
    @State private var practiceRoute: PracticeTaskRoute? // warmup / main / reward → S11
    /// 标题行内 MIDI 胶囊状态点呼吸（真值 animate-pulse）
    @State private var pillPulse = false
    @ObservedObject private var midi = MIDIHub.shared

    private var settings: AppSettings? { settingsList.first }
    private var hasPlacement: Bool { !placementResults.isEmpty }

    var body: some View {
        Group {
            if hasPlacement {
                normalState
            } else {
                S07bEmptyState(onStartPlacement: startPlacement, onBrowseLibrary: onBrowseLibrary)
            }
        }
        .background(Color.canvas)
        .task {
            now = Date()
            plan = CourseEngine.todayPlan(in: context)
        }
        .fullScreenCover(item: $practiceRoute) { route in
            PracticeRoomView(
                taskType: route.id,
                timeLimitSec: (plan?.durationChoice).map { $0 * 60 }
            )
        }
        .overlay {
            if showOverrideModal {
                S07cOverrideModal(
                    plan: plan,
                    allEvents: gateEvents,
                    onGoWarmup: {
                        showOverrideModal = false
                        practiceRoute = .init(id: "warmup")
                    },
                    onConfirmOverride: { reasonTag, note in
                        confirmOverride(reasonTag: reasonTag, note: note)
                    },
                    onCancel: { showOverrideModal = false }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: showOverrideModal)
    }

    // MARK: 去向

    private func startPlacement() {
        // 恢复 onboarding 流程（阶段已持久化；S07b 主按钮变"继续定级"）
        settings?.onboardingDismissed = false
    }

    private func confirmOverride(reasonTag: String, note: String) {
        guard let plan else { return }
        let event = WarmupGate.recordOverride(reasonTag: reasonTag, note: note, in: context)
        plan.gateOverrideId = event.entityId // 今日已强开标记（热身卡陈述用）
        showOverrideModal = false
        practiceRoute = .init(id: "main")
    }

    // MARK: - S07 常态

    private var normalState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerRow

                StreakRow(
                    streak: TodayPlanService.weekStreak(takes: takes, today: now),
                    weeklyGoal: settings?.weeklyGoal ?? 3,
                    today: now
                )
                .padding(.top, 16)

                durationPicker.padding(.top, 16)

                if let plan {
                    taskSection(plan: plan)
                        .padding(.top, 16)

                    startPracticeCTA(warmupDone: plan.warmupCompletedAt != nil)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func task(withId id: UUID?) -> PracticeTask? {
        guard let id else { return nil }
        return tasks.first { $0.taskId == id }
    }

    // MARK: Header（真值 §2：单行「今日」+ MIDI 状态胶囊；D1 已确认去掉问候语/日期）

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("今日")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .tracking(-0.5) // tracking-tight
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 8)
            midiStatusPill
        }
        .padding(.top, 8)
    }

    /// MIDI 状态胶囊（真值 px12/py6、8×8 圆点、12pt muted 文案）。
    /// 文案沿用 `MIDIDeviceLabel` 的诚实规则：模拟源永不冒充特伦斯 V70（红线 2）。
    private var midiStatusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(midi.isConnected ? Color.amber : Color.danger)
                .frame(width: 8, height: 8)
                .opacity(midi.isConnected && pillPulse ? 0.45 : 1)
            Text(midiStatusText)
                .font(.system(size: 12))
                .foregroundStyle(Color.textMuted)
                .tracking(0.3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pillPulse = true
            }
        }
    }

    /// 真值文案顺序为「已连接 · 特伦斯 V70」；`MIDIDeviceLabel.label(for:)` 是反序，
    /// 故只复用它的**状态判定**（同一诚实来源），本地组句。
    private var midiStatusText: String {
        switch MIDIDeviceLabel.state(isConnected: midi.isConnected, mode: midi.mode) {
        case .realConnected: "已连接 · 特伦斯 V70"
        case .simulatedConnected: "已连接 · 模拟输入"
        case .disconnected: "未连接"
        }
    }

    // MARK: 今日时长（15/30/45；热身不被压缩；真值 §4 卡内分段控件）

    private var durationPicker: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("今日时长")
                .font(.system(size: 14, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 8)

            HStack(spacing: 0) {
                ForEach([15, 30, 45], id: \.self) { minutes in
                    let selected = plan?.durationChoice == minutes
                    Button {
                        if let plan {
                            CourseEngine.setDurationChoice(minutes, for: plan)
                        }
                    } label: {
                        Text("\(minutes)")
                            .font(.system(size: 13, weight: selected ? .bold : .regular))
                            .foregroundStyle(selected ? Color.canvas : Color.textMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selected ? Color.amber : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.canvas, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
        }
        .padding(16)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.2), radius: 6, y: 2)
        // D3 已确认：真值尾注「余 42 分钟」无可信数据来源 → 不渲染，禁止写死 42。
    }

    // MARK: 今日任务（真值 §5）

    private func taskSection(plan: DailyPlan) -> some View {
        let durations = TodayPlanService.durations(forChoiceMinutes: plan.durationChoice)
        let warmupTask = task(withId: plan.warmupTaskId)
        let mainTask = task(withId: plan.mainTaskId)
        let warmupDone = plan.warmupCompletedAt != nil
        let overriddenToday = plan.gateOverrideId != nil
        // 真值标题归属：类别词进徽章，标题取旧标题去掉「类别 · 」前缀后的部分（不重复、不编造曲名）
        let warmupName = warmupTask.map { "\($0.book) \($0.number)" } ?? "热身任务"
        let mainName = mainTask.map { "\($0.book) \($0.number)" } ?? "主菜任务"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("今日任务")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .tracking(-0.3)
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: 8)
                Text("3 项")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMuted)
            }

            warmupCard(
                name: warmupName,
                subtitle: durations.warmupLabel,
                done: warmupDone,
                footnote: overriddenToday ? "今日已强开" : nil,
                action: warmupDone ? nil : { practiceRoute = .init(id: "warmup") }
            )

            mainCard(
                name: mainName,
                subtitle: "约 \(durations.mainMinutes) 分钟",
                action: { handleMainStart(warmupDone: warmupDone) }
            )

            rewardCard(
                title: durations.rewardLabel,
                subtitle: "今日未安排曲目，弹喜欢的就好",
                action: { practiceRoute = .init(id: "reward") } // 奖励曲无门禁、无完成条件（spec）
            )
        }
    }

    /// 任务卡统一卡面（真值 §5）：card 底 + 16 圆角 + 1pt border；
    /// 主菜卡（isPrimary）左缘 2pt 琥珀 + 中等投影，其余卡 1pt border + 轻投影。
    private func taskCardChrome<Content: View>(
        isPrimary: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(isPrimary ? 16 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .leading) {
                if isPrimary {
                    Rectangle()
                        .fill(Color.amber)
                        .frame(width: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
            .shadow(color: Color.black.opacity(isPrimary ? 0.35 : 0.2), radius: isPrimary ? 12 : 6, y: isPrimary ? 4 : 2)
    }

    /// 任务类别徽章（真值：10pt、4pt 圆角、px6/py2.5）
    private enum TaskLabelStyle {
        case amberOutline, amberSolid, mutedOutline
    }

    private func taskLabel(_ text: String, style: TaskLabelStyle) -> some View {
        let solid = style == .amberSolid
        let textColor: Color = solid ? Color.canvas : (style == .amberOutline ? Color.amber : Color.textMuted)
        let strokeColor: Color = solid ? Color.clear : (style == .amberOutline ? Color.amber.opacity(0.4) : Color.border)
        return Text(text)
            .font(.system(size: 10, weight: solid ? .semibold : (style == .amberOutline ? .medium : .regular)))
            .foregroundStyle(textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(solid ? Color.amber : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(strokeColor, lineWidth: 1))
    }

    /// 任务1 热身：已完成态 = emerald 勾圆（真值 §5.1）；待完成态真值未画，按同语言补齐（dim 圆）。
    @ViewBuilder
    private func warmupCard(
        name: String,
        subtitle: String,
        done: Bool,
        footnote: String?,
        action: (() -> Void)?
    ) -> some View {
        let card = taskCardChrome(isPrimary: false) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(done ? Color.s07DoneFill : Color.canvas)
                    Circle().strokeBorder(done ? Color.s07DoneStroke : Color.border, lineWidth: 1)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.s07DoneCheck)
                    } else {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        taskLabel("热身", style: .amberOutline)
                        Text(name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                            .strikethrough(done)
                            .opacity(done ? 0.75 : 1)
                    }
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
                    if let footnote {
                        // 真值无此脚注；强开当日保留陈述（不进常态视觉）
                        Text(footnote)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.amber)
                    }
                }

                Spacer(minLength: 8)

                if done {
                    Text("已完成")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(Color.textMuted)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.textMuted)
                }
            }
        }

        if let action {
            Button(action: action) { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }

    /// 任务2 主菜：进行中（当前焦点卡）：36pt 播放圆 + 实心标签 + chevron。
    @ViewBuilder
    private func mainCard(name: String, subtitle: String, action: @escaping () -> Void) -> some View {
        let card = taskCardChrome(isPrimary: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.amber.opacity(0.15))
                        Circle().strokeBorder(Color.amber.opacity(0.4), lineWidth: 1)
                        Image(systemName: "play.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.amber)
                            .offset(x: 1.5) // play.fill 视觉偏左，右移居中
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            taskLabel("主菜", style: .amberSolid)
                            Text(name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                        }
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textMuted)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.textMuted)
                }

                // D4：错误热点 info 条仅在有现成可信来源时渲染；当前无 → 不渲染（禁止写死 21 小节）
                if let measure = errorHotspotMeasure {
                    mainInfoBar(measure: measure)
                }
            }
        }

        Button(action: action) { card }
            .buttonStyle(.plain)
    }

    /// 任务3 奖励曲（可选）：深底音符圆 + muted 描边标签。
    @ViewBuilder
    private func rewardCard(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        let card = taskCardChrome(isPrimary: false) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.canvas)
                    Circle().strokeBorder(Color.border, lineWidth: 1)
                    Image(systemName: "music.note")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.textMuted)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        taskLabel("奖励曲", style: .mutedOutline)
                        Text(title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                    }
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.textMuted.opacity(0.6))
            }
        }

        Button(action: action) { card }
            .buttonStyle(.plain)
    }

    /// 主菜卡内嵌错误热点 info 条（真值 §5.2：深底 /70、12 圆角、info 图标 + 「上次错误集中在 X 小节」）
    private func mainInfoBar(measure: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 16))
                .foregroundStyle(Color.amber)
            (
                Text("上次错误集中在 ")
                    .foregroundStyle(Color.textMuted)
                + Text("\(measure) 小节")
                    .foregroundStyle(Color.textPrimary)
                    .fontWeight(.medium)
            )
            .font(.system(size: 12))
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.canvas.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
    }

    /// D4 单一接线点：错误热点小节号的唯一来源。
    /// 现成的可信来源是 `TakeAnalysis.hotspotMeasures`（per-take 判分结果），但 S07 没有
    /// 「主菜最近一次 take」的现成聚合；按 D4 不新建聚合 → 恒 nil，info 条不渲染。
    /// TODO(D4)：接入现成聚合后返回真实小节号，禁止写死 21。
    private var errorHotspotMeasure: Int? { nil }

    // MARK: 全宽 CTA「开始练习」（真值 §6）

    /// 与主菜卡同一门禁路径（`handleMainStart`），不新增第二套逻辑。
    private func startPracticeCTA(warmupDone: Bool) -> some View {
        Button {
            handleMainStart(warmupDone: warmupDone)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20))
                Text("开始练习")
                    .font(.system(size: 16, weight: .bold))
                    .tracking(0.5)
            }
            .foregroundStyle(Color.canvas)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(StartPracticeButtonStyle())
    }

    /// CTA 按压迫色（真值 #c29141）：屏内私有样式，不写入全局 token。
    private struct StartPracticeButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(
                    configuration.isPressed ? Color(hex: 0xc29141) : Color.amber,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .shadow(color: Color.amber.opacity(0.25), radius: 12, y: 4)
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    /// 热身硬门禁入口：未完成且未强开 → S07c（不静默放行，红线 6）
    private func handleMainStart(warmupDone: Bool) {
        let decision = WarmupGate.checkMainAccess(
            warmupCompletedAt: warmupDone ? Date() : nil,
            today: now,
            overrides: gateEvents
        )
        switch decision {
        case .allowed:
            practiceRoute = .init(id: "main")
        case .blocked:
            showOverrideModal = true
        }
    }

    // MARK: 周进度

    /// D2 已确认：S07 常态（真值 code.html 无此元素）从渲染中移除，代码保留待产品确认。
    /// TODO(D2)：S07b / 后续批次若要恢复，直接在 normalState 里重新挂载。
    private func weekProgressRow(plan: DailyPlan) -> some View {
        let progress = TodayPlanService.weekProgress(
            takes: takes, weeklyGoal: settings?.weeklyGoal ?? 3,
            dailyChoiceMinutes: plan.durationChoice, today: now
        )
        let fraction = progress.targetMinutes > 0
            ? min(1, Double(progress.doneMinutes) / Double(progress.targetMinutes)) : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("本周进度")
                    .font(.bodyMd)
                    .foregroundStyle(Color.textBody)
                Spacer()
                Text("\(progress.doneMinutes)m / \(progress.targetMinutes)m")
                    .font(.labelMd)
                    .foregroundStyle(Color.textPrimary)
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.borderInput)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.amber)
                        .frame(width: proxy.size.width * fraction, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - S07 屏内私有色（不写入 Assets / 不改全局 token）

fileprivate extension Color {
    /// hex → sRGB（S07 真值局部色专用）
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// 「已完成」emerald 底（真值 #022c22 @60%）
    static let s07DoneFill = Color(hex: 0x022c22, opacity: 0.6)
    /// 「已完成」emerald 边（真值 #10b981 @30%）
    static let s07DoneStroke = Color(hex: 0x10b981, opacity: 0.3)
    /// 「已完成」对勾（真值 #34d399）
    static let s07DoneCheck = Color(hex: 0x34d399)
}

// MARK: - 本周打卡卡（周一起始；真实 Take 聚合，无假点；真值 §3）

private struct StreakRow: View {
    let streak: TodayPlanService.WeekStreak
    /// 周目标次数（AppSettings.weeklyGoal 真实值）
    let weeklyGoal: Int
    /// 今天（圆内显示真实日号）
    let today: Date

    private let dayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 真值标题行右侧为「连续达标 N 周」：WeekStreak 无可信字段 → 不渲染（禁止编造 5 周）
            Text("本周 \(doneCount)/\(weeklyGoal) 次")
                .font(.system(size: 19, weight: .semibold, design: .serif))
                .tracking(-0.3)
                .foregroundStyle(Color.textPrimary)
            .padding(.bottom, 16)

            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    dayCell(i)
                }
            }
            .padding(.bottom, 12)

            HStack(spacing: 8) {
                Text("周目标 \(weeklyGoal) 次 · 本周还剩 \(remaining) 次")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
                Spacer(minLength: 8)
                Text("Focus Week")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.amber.opacity(0.8))
                    .tracking(1.2)
                    .textCase(.uppercase)
            }
            .padding(.top, 8)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.border.opacity(0.6))
                    .frame(height: 1)
            }
        }
        .padding(16)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.2), radius: 6, y: 2)
    }

    /// 本周已达标天数（litDays 真实聚合）
    private var doneCount: Int { streak.litDays.filter { $0 }.count }
    /// 本周还差几次达标（不为负）
    private var remaining: Int { max(0, weeklyGoal - doneCount) }
    /// 今天的真实日号
    private var todayDayNumber: Int { Calendar.current.component(.day, from: today) }

    /// 日单元 32×32：已完成（琥珀底+勾）/ 今天（琥珀环+日号）/ 未来（dim 点）/ 过去未达标（dim 空圆）
    @ViewBuilder
    private func dayCell(_ i: Int) -> some View {
        let lit = streak.litDays[i]
        let isToday = i == streak.todayIndex
        let isFuture = i > streak.todayIndex

        VStack(spacing: 8) {
            ZStack {
                if lit {
                    Circle().fill(Color.amber)
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.canvas)
                } else if isToday {
                    Circle().fill(Color.amber.opacity(0.10))
                        .overlay(Circle().strokeBorder(Color.amber, lineWidth: 2))
                    Text("\(todayDayNumber)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.amber)
                } else if isFuture {
                    Circle().fill(Color.canvas.opacity(0.4))
                        .overlay(Circle().strokeBorder(Color.border, lineWidth: 1))
                    Circle().fill(Color.border).frame(width: 6, height: 6)
                } else {
                    // 过去但未达标：真值未画该态；dim 空圆（不画成「未来」点，避免误导）
                    Circle().fill(Color.canvas.opacity(0.4))
                        .overlay(Circle().strokeBorder(Color.border, lineWidth: 1))
                }
            }
            .frame(width: 32, height: 32)

            Text(dayLabels[i])
                .font(.system(size: 12, weight: isToday ? .medium : .regular))
                .foregroundStyle(isToday ? Color.amber : Color.textMuted)
        }
        .frame(maxWidth: .infinity)
        .help(tooltip(i))
    }

    private func tooltip(_ i: Int) -> String {
        let minutes = streak.minutesPerDay[i]
        return minutes > 0 ? "\(minutes) 分钟" : "未练习"
    }
}

// MARK: - S07b 定级前空状态

private struct S07bEmptyState: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    let onStartPlacement: () -> Void
    let onBrowseLibrary: () -> Void

    private var settings: AppSettings? { settingsList.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("还没有你的练习计划")
                            .font(.displayLg)
                            .foregroundStyle(Color.textPrimary)
                    }
                    Spacer()
                }
                .padding(.top, 16)

                // 英雄线稿（同 S01 语言更小，96pt + 柔光圆环）
                ZStack {
                    Circle()
                        .fill(Color.amber.opacity(0.08))
                        .frame(width: 130, height: 130)
                    Image(systemName: "pianokeys")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.amber)
                        .frame(width: 96, height: 96)
                        .background(Color.card, in: Circle())
                        .overlay(Circle().strokeBorder(Color.border, lineWidth: 1))
                }
                .padding(.top, 28)

                Text("花 20 分钟做一次三段定级，Neko 会按你的真实水平排拜厄、哈农和 599。定级随时可以退出，进度会保留。")
                    .font(.bodyMd)
                    .leading(24, fontSize: 14)
                    .foregroundStyle(Color.textBody)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 20)

                // 三占位卡（值均为 "—"，不画假数据）
                HStack(spacing: 12) {
                    placeholderCard("本周\nstreak")
                    placeholderCard("本周\n时长")
                    placeholderCard("距599")
                }
                .padding(.top, 24)

                Text("定级内容：自评 1 分钟 + 视奏 2 段 + 力度校准 2 分钟。")
                    .font(.bodySm)
                    .foregroundStyle(Color.textBody)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 20)

                Button(action: onStartPlacement) {
                    Text(ctaLabel)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 24)

                Button(action: onBrowseLibrary) {
                    Text("我已经有基础，先自己逛逛曲库")
                }
                .buttonStyle(GhostButtonStyle())
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
    }

    /// 未完成续做 → "继续定级（还剩 X 分钟）"；X 由 placementStartedAt 诚实推算（20 分钟总长）
    private var ctaLabel: String {
        if settings?.onboardingStage == OnboardingStage.placement.rawValue,
           let startedAt = settings?.placementStartedAt {
            let elapsed = Int(Date().timeIntervalSince(startedAt) / 60)
            let remaining = max(1, 20 - elapsed)
            return "继续定级（还剩 \(remaining) 分钟）"
        }
        return "开始 20 分钟定级"
    }

    private func placeholderCard(_ label: String) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.labelSm)
                .leading(16, fontSize: 11)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textMuted)
                .lineSpacing(2)
            Text("—")
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
    }
}

// MARK: - S07c 热身强开确认（硬拦截弹层；不可点外部关闭）

struct S07cOverrideModal: View {
    let plan: DailyPlan?
    let allEvents: [GateEvent]
    let onGoWarmup: () -> Void
    let onConfirmOverride: (_ reasonTag: String, _ note: String) -> Void
    let onCancel: () -> Void

    enum ReasonTag: String, CaseIterable {
        case time = "time"
        case feelGood = "feel"
        case boring = "boring"
        case other = "other"
        var label: String {
            switch self {
            case .time: "时间不够，今天只弹主菜"
            case .feelGood: "手状态不错，跳过一次"
            case .boring: "热身曲太无聊"
            case .other: "其他（写一句）"
            }
        }
    }

    @State private var selected: ReasonTag?
    @State private var otherNote = ""

    /// "本周第 N 次"：本次强开将是第 N 次（现有次数 + 1），陈述不指责
    private var thisWeekCountAfterConfirm: Int {
        WarmupGate.overrideCountThisWeek(events: allEvents, date: Date()) + 1
    }

    var body: some View {
        ZStack {
            // scrim：今日页压暗（spec rgba(12,10,9,.55)）
            Color.scrim
                .ignoresSafeArea()
                .onTapGesture {} // 不可点外部关闭（必须做选择）

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: "lock")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.amber) // 锁图标琥珀（不是红色恐吓）
                    Text("热身还没完成")
                        .font(.headlineSm)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                Text("今天的热身还没完成。Neko 会把这次强开记在本周的 Neko 周报和月报里。")
                    .font(.bodySm)
                    .leading(19, fontSize: 12)
                    .foregroundStyle(Color.textBody)
                    .padding(.top, 10)

                Text("这次强开的原因（必选一个）：")
                    .font(.bodyMd)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.top, 16)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ReasonTag.allCases, id: \.rawValue) { tag in
                        reasonRow(tag)
                        if tag == .other, selected == .other {
                            TextField("写一句原因", text: $otherNote)
                                .font(.bodyMd)
                                .foregroundStyle(Color.textPrimary)
                                .padding(10)
                                .background(Color.card, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.borderInput, lineWidth: 1))
                        }
                    }
                }
                .padding(.top, 10)

                // 强开记录卡（琥珀 8% 底 + 琥珀左缘；≥3 次变体文案）
                HStack(alignment: .top, spacing: 8) {
                    Rectangle().fill(Color.amber).frame(width: 2)
                    Text(recordCardText)
                        .font(.bodySm)
                        .leading(18, fontSize: 12)
                        .foregroundStyle(Color.textBody)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .padding(.top, 16)

                // 双按钮堆叠：补完热身为建议主位（描边次按钮视觉），强开在下
                Button(action: onGoWarmup) {
                    Text("去补完热身")
                }
                .buttonStyle(SecondaryButtonStyle(cornerRadius: 8))
                .padding(.top, 16)

                Button {
                    if let selected {
                        onConfirmOverride(selected.rawValue, selected == .other ? otherNote : "")
                    }
                } label: {
                    Text("我确认强开，开始主菜")
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: canConfirm, cornerRadius: 8))
                .disabled(!canConfirm)
                .padding(.top, 8)
            }
            .padding(20)
            .background(Color.cardElevated, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.amber.opacity(0.18), lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }

    private var canConfirm: Bool {
        WarmupGate.canConfirmOverride(reasonTag: selected?.rawValue, note: otherNote)
    }

    private var recordCardText: String {
        let count = thisWeekCountAfterConfirm
        if count >= 3 {
            return "本周第 \(count) 次，周报会提醒你留意热身习惯。记录只给你自己看，不会影响任何解锁判定。"
        }
        return "本周第 \(count) 次。记录只给你自己看，不会影响任何解锁判定。"
    }

    private func reasonRow(_ tag: ReasonTag) -> some View {
        Button {
            selected = tag
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(selected == tag ? Color.amber : Color.borderInput, lineWidth: 1)
                        .frame(width: 16, height: 16)
                    Circle()
                        .fill(Color.amber)
                        .frame(width: 8, height: 8)
                        .opacity(selected == tag ? 1 : 0)
                }
                Text(tag.label)
                    .font(.bodyMd)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}


#Preview {
    TodayView(onBrowseLibrary: {})
        .modelContainer(for: [AppSettings.self, PlacementResult.self, DailyPlan.self, PracticeTask.self, GateEvent.self, Take.self, CoursePathState.self])
        .preferredColorScheme(.dark)
}

import SwiftData
import SwiftUI

// MARK: - 今日 tab：S07b（未定级空状态）/ S07（已定级常态）自动切换

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
    @State private var showPracticePlaceholder = false

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
        .fullScreenCover(isPresented: $showPracticePlaceholder) {
            PracticeRoomPlaceholder()
        }
        .overlay {
            if showOverrideModal {
                S07cOverrideModal(
                    plan: plan,
                    allEvents: gateEvents,
                    onGoWarmup: {
                        showOverrideModal = false
                        showPracticePlaceholder = true // 练习室 S11 在后续批次；占位承接
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
        showPracticePlaceholder = true
    }

    // MARK: - S07 常态

    private var normalState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                greetingBlock
                StreakRow(streak: TodayPlanService.weekStreak(takes: takes, today: now))
                    .padding(.top, 16)

                durationPicker.padding(.top, 20)

                if let plan {
                    let durations = TodayPlanService.durations(forChoiceMinutes: plan.durationChoice)
                    let warmupTask = task(withId: plan.warmupTaskId)
                    let mainTask = task(withId: plan.mainTaskId)
                    let warmupDone = plan.warmupCompletedAt != nil
                    let overriddenToday = plan.gateOverrideId != nil

                    taskCard(
                        kind: .warmup,
                        title: "热身 · \(durations.warmupLabel)",
                        subtitle: warmupTask.map { "\($0.book) \($0.number)" } ?? "热身任务",
                        state: warmupDone ? .completed : .ready,
                        footnote: overriddenToday ? "今日已强开" : nil,
                        action: warmupDone ? nil : { showPracticePlaceholder = true }
                    )
                    .padding(.top, 16)

                    taskCard(
                        kind: .main,
                        title: "主菜 · 约 \(durations.mainMinutes) 分钟",
                        subtitle: mainTask.map { "\($0.book) \($0.number)" } ?? "主菜任务",
                        state: .ready,
                        footnote: nil,
                        action: { handleMainStart(warmupDone: warmupDone) },
                        actionLabel: "开始"
                    )

                    taskCard(
                        kind: .reward,
                        title: "奖励曲 · \(durations.rewardLabel)",
                        subtitle: "今日未安排曲目，弹喜欢的就好",
                        state: .ready,
                        footnote: nil,
                        action: { showPracticePlaceholder = true } // 奖励曲无门禁、无完成条件（spec）
                    )

                    weekProgressRow(plan: plan).padding(.top, 20)
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

    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Text(greeting)
                    .font(.displayLg)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            Text(dateLine)
                .font(.headlineLg)
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.top, 8)
    }

    /// 问候时段（spec：20:30 后为"晚上好"）
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: now)
        let minute = Calendar.current.component(.minute, from: now)
        if hour > 20 || (hour == 20 && minute >= 30) { return "晚上好" }
        if hour >= 12 { return "下午好" }
        return "早上好"
    }

    private var dateLine: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter.string(from: now)
    }

    // MARK: 时长三选（15/30/45；热身不被压缩）

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今天练多久？")
                .font(.titleMd)
                .foregroundStyle(Color.textPrimary)
            HStack(spacing: 8) {
                ForEach([15, 30, 45], id: \.self) { minutes in
                    let selected = plan?.durationChoice == minutes
                    Button {
                        if let plan {
                            CourseEngine.setDurationChoice(minutes, for: plan)
                        }
                    } label: {
                        Text("\(minutes)分")
                            .font(.titleMd)
                            .foregroundStyle(selected ? Color.canvas : Color.textBody)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selected ? Color.amber : Color.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(selected ? Color.clear : Color.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 任务卡

    private enum TaskKind {
        case warmup, main, reward
        var barColor: Color {
            switch self {
            case .warmup: Color.success
            case .main: Color.amber
            case .reward: Color.compareB
            }
        }
    }

    private func taskCard(
        kind: TaskKind,
        title: String,
        subtitle: String,
        state: CardState,
        footnote: String?,
        action: (() -> Void)?,
        actionLabel: String = "开始"
    ) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(kind.barColor)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.titleMd)
                        .foregroundStyle(state == .completed ? Color.textMuted : Color.textPrimary)
                        .monospacedDigit()
                    if state == .completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.success)
                    }
                    Spacer()
                    if let footnote {
                        Text(footnote)
                            .font(.labelSm)
                            .foregroundStyle(Color.amber)
                    }
                }
                Text(subtitle)
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                if let action, state != .completed {
                    HStack {
                        Spacer()
                        Button(action: action) {
                            HStack(spacing: 4) {
                                Text(actionLabel)
                                Image(systemName: "arrow.right").font(.system(size: 12))
                            }
                            .font(.titleMd)
                            .foregroundStyle(Color.amber)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .overlay(Capsule().strokeBorder(Color.amber.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(14)
        }
        .opacity(state == .completed ? 0.55 : 1)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
    }

    private enum CardState { case ready, completed }

    /// 热身硬门禁入口：未完成且未强开 → S07c（不静默放行，红线 6）
    private func handleMainStart(warmupDone: Bool) {
        let decision = WarmupGate.checkMainAccess(
            warmupCompletedAt: warmupDone ? Date() : nil,
            today: now,
            overrides: gateEvents
        )
        switch decision {
        case .allowed:
            showPracticePlaceholder = true
        case .blocked:
            showOverrideModal = true
        }
    }

    // MARK: 周进度

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

// MARK: - streak 7 灯（周一起始；真实 Take 聚合，无假点）

private struct StreakRow: View {
    let streak: TodayPlanService.WeekStreak
    private let dayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本周 streak")
                .font(.bodyMd)
                .foregroundStyle(Color.textBody)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 5) {
                        Circle()
                            .fill(streak.litDays[i] ? Color.amber : Color.clear)
                            .overlay(Circle().strokeBorder(strokeColor(i), lineWidth: 1))
                            .frame(width: 10, height: 10)
                        Text(dayLabels[i])
                            .font(.labelSm)
                            .foregroundStyle(i == streak.todayIndex ? Color.textBody : Color.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .help(tooltip(i))
                }
            }
        }
    }

    private func strokeColor(_ i: Int) -> Color {
        if streak.litDays[i] { return Color.amber }
        // 未来天：muted 描边；今天及过去未练：borderInput 描边
        return i > streak.todayIndex ? Color.textMuted.opacity(0.4) : Color.borderInput
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

// MARK: - 练习室占位（S11 后续批次；门禁放行/奖励曲的承接去向）

struct PracticeRoomPlaceholder: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "pianokeys")
                .font(.system(size: 40))
                .foregroundStyle(Color.amber)
            Text("练习室")
                .font(.headlineLg)
                .foregroundStyle(Color.textPrimary)
            Text("S11 将在下一批次实装（谱面渲染 + 节拍器 + 循环）。此占位保证门禁与任务入口都有真实去向，不留假按钮。")
                .font(.bodySm)
                .leading(19, fontSize: 12)
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("返回") { dismiss() }
                .buttonStyle(SecondaryButtonStyle(cornerRadius: 8))
                .padding(.horizontal, 60)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    TodayView(onBrowseLibrary: {})
        .modelContainer(for: [AppSettings.self, PlacementResult.self, DailyPlan.self, PracticeTask.self, GateEvent.self, Take.self, CoursePathState.self])
        .preferredColorScheme(.dark)
}

import SwiftData
import SwiftUI

// MARK: - 今日 tab：S07b（未定级空状态）/ S07（已定级常态）自动切换

/// 练习室路由（fullScreenCover(item:) 需要 Identifiable）
struct PracticeTaskRoute: Identifiable {
    let id: String // warmup / main / reward / review
}

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    @Query(sort: \PlacementResult.createdAt, order: .reverse) private var placementResults: [PlacementResult]
    @Query private var dailyPlans: [DailyPlan]
    @Query private var tasks: [PracticeTask]
    @Query private var gateEvents: [GateEvent]
    @Query private var takes: [Take]
    /// Stage B §3：课程条目（复习卡数据源；真实 reviewing 条目存在才出卡，无假数据）
    @Query private var pieces: [Piece]

    let onBrowseLibrary: () -> Void

    @State private var plan: DailyPlan?
    @State private var now = Date()
    /// S07c 热身强开弹层：改由 AppFrameView 顶层 presenter 呈现（否则盖不住 tab bar / FAB）
    @EnvironmentObject private var overridePresenter: WarmupOverridePresenter
    @State private var practiceRoute: PracticeTaskRoute? // warmup / main / reward / review → S11
    /// Stage B §3c：复习卡选中的条目（进房直接带 reviewing piece 与其 bundled 坐标）
    @State private var reviewPiece: Piece?
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
                S07bEmptyState(midi: midi, now: now, onStartPlacement: startPlacement, onBrowseLibrary: onBrowseLibrary)
            }
        }
        .background(Color.canvas)
        .task {
            now = Date()
            plan = CourseEngine.todayPlan(in: context)
        }
        .fullScreenCover(item: $practiceRoute) { route in
            if route.id == "review" {
                // Stage B §3c：复习路由——直接带 reviewing piece（effectivePiece 即它），
                // 不走 task(for:)（避免落进 warmup/main 分支）；复习为轻量检查，
                // 不传时长（nil = 不自动到点，用户手动结束）。
                let coords = BundledScoreCoordinates.resolve(
                    book: reviewPiece?.book, number: reviewPiece?.number ?? 0
                )
                PracticeRoomView(
                    taskType: "review",
                    pieceTitle: reviewPiece?.title ?? "",
                    timeLimitSec: nil,
                    piece: reviewPiece,
                    bundledBook: coords?.book,
                    bundledNumber: coords?.number ?? 0
                )
            } else {
                let task = task(for: route)
                let coords = BundledScoreCoordinates.resolve(book: task?.book, number: task?.number ?? 0)
                PracticeRoomView(
                    taskType: route.id,
                    pieceTitle: task.map { "\($0.book) \($0.number)" } ?? "",
                    timeLimitSec: (plan?.durationChoice).map { $0 * 60 },
                    bundledBook: coords?.book,
                    bundledNumber: coords?.number ?? 0
                )
            }
        }
    }

    /// 路由 → 今日任务（Fix：book/number 不再在导航处丢失，谱坐标由此解析）
    private func task(for route: PracticeTaskRoute) -> PracticeTask? {
        guard let plan else { return nil }
        let id: UUID? = switch route.id {
        case "warmup": plan.warmupTaskId
        case "main": plan.mainTaskId
        default: nil
        }
        return task(withId: id)
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
        overridePresenter.dismiss()
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

                // Stage B §3b：复习卡（热身/主菜之间不插入——插在时长选择与今日任务之间，
                // 视觉上复用任务卡外壳）。仅当真实存在 reviewing 条目时出现，无假数据。
                if let reviewPiece = TodayReviewPicker.pick(pieces) {
                    reviewCard(piece: reviewPiece)
                        .padding(.top, 16)
                }

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
                action: onBrowseLibrary // 无奖励曲排期能力：诚实去向是曲库，不开空练习室
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

    /// Stage B §3b 复习卡：与热身/奖励曲同一任务卡外壳（isPrimary:false），无独立设计体系。
    /// 名称/副行只用真实 piece 数据；点击带 reviewing piece 进练习室（route id "review"）。
    @ViewBuilder
    private func reviewCard(piece: Piece) -> some View {
        let card = taskCardChrome(isPrimary: false) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.canvas)
                    Circle().strokeBorder(Color.border, lineWidth: 1)
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.textMuted)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        taskLabel("复习", style: .amberOutline)
                        Text("复习 · \(piece.title)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                    }
                    Text("防回生 · 轻弹一遍达标即可")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.textMuted)
            }
        }

        Button {
            reviewPiece = piece
            practiceRoute = PracticeTaskRoute(id: "review")
        } label: { card }
            .buttonStyle(.plain)
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
            // 提升到 AppFrameView 顶层呈现：整屏 scrim 需遮住 tab bar 与问 Neko FAB
            overridePresenter.present(.init(
                plan: plan,
                allEvents: gateEvents,
                onGoWarmup: {
                    overridePresenter.dismiss()
                    practiceRoute = .init(id: "warmup")
                },
                onConfirmOverride: { reasonTag, note in
                    confirmOverride(reasonTag: reasonTag, note: note)
                }
            ))
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
    /// S07b 头部 MIDI 胶囊底（真值 #1E2721）
    static let s07bPillBg = Color(hex: 0x1E2721)
    /// S07b 头部 MIDI 胶囊边（真值 #2B3E30）
    static let s07bPillBorder = Color(hex: 0x2B3E30)
    /// S07b 头部 MIDI 胶囊已连接点/文案（真值 #4ADE80；断连用全局 danger）
    static let s07bPillGreen = Color(hex: 0x4ADE80)
    /// S07c 强开主钮 pressed 底（真值 #C2913D；amber 与 amberDim 之间，token 无此色）
    static let s07cAmberPressed = Color(hex: 0xC2913D)
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
    /// 真实 MIDI 状态：头部绿色胶囊的唯一数据来源（文案仍整套走 `MIDIDeviceLabel`，红线 2）
    @ObservedObject var midi: MIDIHub
    /// 今天：问候语 + 日期标题的真实来源（不写死「9月18日 周五」）
    let now: Date
    let onStartPlacement: () -> Void
    let onBrowseLibrary: () -> Void
    /// 胶囊状态点呼吸（真值 animate-pulse）
    @State private var dotPulse = false

    private var settings: AppSettings? { settingsList.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 真值顺序：头部 → 插画 → 标题 → 正文 → 三占位卡 → 主按钮 → 幽灵按钮 → 底部说明卡
                header

                KeybedIllustration()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                Text("还没有你的练习计划")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .tracking(-0.3) // tracking-tight
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 20)

                Text("花 20 分钟做一次三段定级，Neko 会按你的真实水平排拜厄、哈农和 599。定级随时可以退出，进度会保留。")
                    .font(.system(size: 13))
                    .leading(21, fontSize: 13) // leading-relaxed
                    .foregroundStyle(Color.textMuted)
                    .frame(maxWidth: 320, alignment: .leading)
                    .padding(.top, 10)

                statsRow
                    .padding(.top, 24)

                Button(action: onStartPlacement) {
                    HStack(spacing: 8) {
                        Text(ctaLabel)
                        Image(systemName: "arrow.forward")
                            .font(.system(size: 18, weight: .bold))
                    }
                }
                .buttonStyle(PlacementPrimaryButtonStyle())
                .padding(.top, 24)

                Button(action: onBrowseLibrary) {
                    Text("我已经有基础，先自己逛逛曲库")
                }
                .buttonStyle(PlacementGhostButtonStyle())
                .padding(.top, 10)

                infoCard
                    .padding(.top, 16)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32) // 让开 AppFrameView 的 tab bar
        }
    }

    // MARK: 头部（真值 §2：问候语 + 真实日期 + 绿色 MIDI 胶囊）

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(0.6) // tracking-wide
                    .foregroundStyle(Color.textMuted)
                Text(dateTitle)
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .tracking(-0.5) // tracking-tight
                    .foregroundStyle(Color.textPrimary)
            }
            .layoutPriority(1) // 挤空间时先委屈胶囊，日期标题不被压

            midiPill
        }
        .padding(.top, 8)
    }

    /// 按真实小时分派（真值静态文案；时间取自 `now`）
    private var greeting: String {
        switch Calendar.current.component(.hour, from: now) {
        case 5..<11: "早上好"
        case 11..<17: "下午好"
        case 17..<23: "晚上好"
        default: "夜深了"
        }
    }

    /// 「M月d日 EEEE」（真值 9月18日 周五），zh-CN locale、由真实 `now` 组出，不写死日期
    private var dateTitle: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh-CN")
        let weekday = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: now) - 1]
        return "\(calendar.component(.month, from: now))月\(calendar.component(.day, from: now))日 \(weekday)"
    }

    /// MIDI 胶囊（真值绿色 pill；与 S07 常态的琥珀 pill 是两套，各自独立）。
    /// 文案整套复用 `MIDIDeviceLabel`：模拟源恒读「模拟输入」，永不冒充特伦斯 V70（红线 2）。
    private var midiPill: some View {
        let state = MIDIDeviceLabel.state(isConnected: midi.isConnected, mode: midi.mode)
        let tint: Color = midi.isConnected ? Color.s07bPillGreen : Color.danger
        return HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .opacity(dotPulse ? 0.45 : 1)
            Text(midi.isConnected ? MIDIDeviceLabel.label(for: state) : MIDIDeviceLabel.waitingText(for: state))
                .font(.system(size: 11, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.s07bPillBg, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.s07bPillBorder, lineWidth: 1))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                dotPulse = true
            }
        }
    }

    // MARK: 三占位卡（真值 §3.3：无真实数据来源，值恒「—」，禁止编造）

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard("本周 streak")
            statCard("本周时长")
            statCard("距 599")
        }
    }

    private func statCard(_ label: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7) // 单行放不下时缩字，不换行
            Text("—")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border.opacity(0.8), lineWidth: 1))
    }

    /// 未完成续做 → "继续定级（还剩 X 分钟）"；X 由 placementStartedAt 诚实推算（20 分钟总长）
    private var ctaLabel: String {
        if settings?.onboardingStage == OnboardingStage.placement.rawValue,
           let startedAt = settings?.placementStartedAt {
            let elapsed = Int(now.timeIntervalSince(startedAt) / 60)
            let remaining = max(1, 20 - elapsed)
            return "继续定级（还剩 \(remaining) 分钟）"
        }
        return "开始 20 分钟定级"
    }

    // MARK: 底部说明卡（真值 §3.5：移到按钮下方）

    private var infoCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "info")
                .font(.system(size: 16))
                .foregroundStyle(Color.amber)
            Text("定级内容：自评 1 分钟 + 视奏 2 段 + 力度校准 2 分钟。")
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border.opacity(0.6), lineWidth: 1))
    }

    // MARK: 屏内私有按钮样式（真值 §3.4：全局样式达不到 12 圆角 / #161311 15pt semibold）

    /// 主按钮：琥珀底 #D4A24E（pressed #C2913D）、12 圆角、py14、#161311 15pt semibold + 尾箭头
    private struct PlacementPrimaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 15, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(Color(hex: 0x161311))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(configuration.isPressed ? Color(hex: 0xC2913D) : Color.amber)
                )
                .shadow(color: Color.amber.opacity(0.25), radius: 12, y: 4)
                .scaleEffect(configuration.isPressed ? 0.99 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    /// 幽灵按钮：透明底 + 1pt #332D29、12 圆角、py10、13pt medium muted；
    /// pressed 描边转琥珀/40 + 卡面底 + 主文色
    private struct PlacementGhostButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(configuration.isPressed ? Color.textPrimary : Color.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(configuration.isPressed ? Color.card : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(configuration.isPressed ? Color.amber.opacity(0.4) : Color.border, lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.99 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    // MARK: 线稿插画（真值 160×112 SVG 的 SwiftUI 重绘：声波弧 + 节拍点 + 琴键床）

    private struct KeybedIllustration: View {
        var body: some View {
            ZStack {
                // 环境光：琥珀 5% 圆角矩形 + 柔光模糊（真值 rounded-full blur-2xl）
                RoundedRectangle(cornerRadius: 56, style: .continuous)
                    .fill(Color.amber.opacity(0.05))
                    .blur(radius: 20)
                    .frame(width: 160, height: 112)

                Canvas { context, _ in
                    // 三段声波弧（外→内：dash 0.25 / 0.4 / 0.6）
                    context.stroke(
                        arcOuter.strokedPath(StrokeStyle(lineWidth: 1.2, dash: [3, 3])),
                        with: .color(Color.amber.opacity(0.25))
                    )
                    context.stroke(arcMiddle, with: .color(Color.amber.opacity(0.4)), lineWidth: 1.2)
                    context.stroke(arcInner, with: .color(Color.amber.opacity(0.6)), lineWidth: 1.2)

                    // 节拍点 (80,38) r3 琥珀/70 + 虚线柄至 (80,65) 琥珀/50
                    context.fill(
                        Path(ellipseIn: CGRect(x: 77, y: 35, width: 6, height: 6)),
                        with: .color(Color.amber.opacity(0.7))
                    )
                    var stem = Path()
                    stem.move(to: CGPoint(x: 80, y: 41))
                    stem.addLine(to: CGPoint(x: 80, y: 65))
                    context.stroke(
                        stem.strokedPath(StrokeStyle(lineWidth: 1, dash: [2, 2])),
                        with: .color(Color.amber.opacity(0.5))
                    )

                    // 琴键床 (24,68) 112×34 r4：#262220 底 + #332D29 描边
                    let bedPath = Path(roundedRect: CGRect(x: 24, y: 68, width: 112, height: 34), cornerRadius: 4)
                    context.fill(bedPath, with: .color(Color.card))
                    context.stroke(bedPath, with: .color(Color.border), lineWidth: 1.2)

                    // 7 条白键分隔线（x = 38…122）
                    for x in [38.0, 52, 66, 80, 94, 108, 122] {
                        var divider = Path()
                        divider.move(to: CGPoint(x: x, y: 68))
                        divider.addLine(to: CGPoint(x: x, y: 102))
                        context.stroke(divider, with: .color(Color.border), lineWidth: 1)
                    }

                    // 黑键 8×20 r1.5（真值绘制序：33 / 47 → 高亮键 → 103 / 117）
                    for x in [33.0, 47] {
                        strokeBlackKey(x, in: &context)
                    }

                    // 中央高亮键 10×21 @x75：琥珀/20 底 + 1.2 琥珀描边 + 实心琥珀点
                    let highlight = Path(roundedRect: CGRect(x: 75, y: 68, width: 10, height: 21), cornerRadius: 1.5)
                    context.fill(highlight, with: .color(Color.amber.opacity(0.2)))
                    context.stroke(highlight, with: .color(Color.amber), lineWidth: 1.2)
                    context.fill(
                        Path(ellipseIn: CGRect(x: 78.5, y: 82.5, width: 3, height: 3)),
                        with: .color(Color.amber)
                    )

                    for x in [103.0, 117] {
                        strokeBlackKey(x, in: &context)
                    }

                    // 地平线 (28,102)→(132,102)：琥珀/70、1.5、圆头
                    var ground = Path()
                    ground.move(to: CGPoint(x: 28, y: 102))
                    ground.addLine(to: CGPoint(x: 132, y: 102))
                    context.stroke(
                        ground,
                        with: .color(Color.amber.opacity(0.7)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                }
                .frame(width: 160, height: 112)
            }
        }

        private func strokeBlackKey(_ x: CGFloat, in context: inout GraphicsContext) {
            let key = Path(roundedRect: CGRect(x: x, y: 68, width: 8, height: 20), cornerRadius: 1.5)
            context.fill(key, with: .color(Color.canvas)) // 真值 fill #1C1917
            context.stroke(key, with: .color(Color.border), lineWidth: 0.8)
        }

        /// 外弧（真值 path 1，dash 3/3）
        private var arcOuter: Path {
            var path = Path()
            path.move(to: CGPoint(x: 20, y: 78))
            path.addCurve(to: CGPoint(x: 80, y: 52), control1: CGPoint(x: 35, y: 60), control2: CGPoint(x: 55, y: 52))
            path.addCurve(to: CGPoint(x: 140, y: 78), control1: CGPoint(x: 105, y: 52), control2: CGPoint(x: 125, y: 60))
            return path
        }

        /// 中弧（真值 path 2）
        private var arcMiddle: Path {
            var path = Path()
            path.move(to: CGPoint(x: 35, y: 76))
            path.addCurve(to: CGPoint(x: 80, y: 58), control1: CGPoint(x: 48, y: 64), control2: CGPoint(x: 63, y: 58))
            path.addCurve(to: CGPoint(x: 125, y: 76), control1: CGPoint(x: 97, y: 58), control2: CGPoint(x: 112, y: 64))
            return path
        }

        /// 内弧（真值 path 3）
        private var arcInner: Path {
            var path = Path()
            path.move(to: CGPoint(x: 50, y: 75))
            path.addCurve(to: CGPoint(x: 80, y: 65), control1: CGPoint(x: 60, y: 68), control2: CGPoint(x: 70, y: 65))
            path.addCurve(to: CGPoint(x: 110, y: 75), control1: CGPoint(x: 90, y: 65), control2: CGPoint(x: 100, y: 68))
            return path
        }
    }
}

// MARK: - S07c 热身强开确认（硬拦截弹层；不可点外部关闭）
// 真值：docs/design-reference/screens/S07c-warmup-override/code.html（390×844）。
// 形态修订：旧「中央卡片 / 圆角 12 / px20」→ 真值为贴底 bottom sheet
// （满宽、仅顶部 28pt 圆角、#262220、36×4 手柄、向上投影、300ms 上滑入场）。
// 锁图标为红 #C97064（真值刻意用红，不是琥珀恐吓）；遮罩黑 60%；主钮在上、次钮在下。
// 硬拦截：点外部不关、无 ✕，唯一出口是「确认强开」或「去补完热身」。
// 背景层（真值 z-0 的简化今日页 + 3/8 进度环）是施工参考，不画：真实今日页就在 scrim 后面。

struct S07cOverrideModal: View {
    let plan: DailyPlan?
    let allEvents: [GateEvent]
    let onGoWarmup: () -> Void
    let onConfirmOverride: (_ reasonTag: String, _ note: String) -> Void
    /// 真值无 ✕、点外部不关（硬拦截），没有第三条退出路径；属性保留不删，当前无调用点
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

    /// 真值默认预选第一项（主按钮始终可点）；选「其他」时 canConfirm 仍要求写一句
    @State private var selected: ReasonTag? = .time
    @State private var otherNote = ""
    /// 入场动画（真值：fade + 上滑 ~24pt，300ms）。呈现处 .overlay 的 transition 不动，滑移在这层补
    @State private var appeared = false
    /// 下拉关闭：向下拖拽位移（>0 才跟手，不上推）。松手达阈值走 onCancel（取消、不留记录）
    @State private var dragOffset: CGFloat = 0

    /// "本周第 N 次"：本次强开将是第 N 次（现有次数 + 1），陈述不指责
    private var thisWeekCountAfterConfirm: Int {
        WarmupGate.overrideCountThisWeek(events: allEvents, date: Date()) + 1
    }

    var body: some View {
        ZStack {
            // scrim：黑 60%（真值 bg-black/60）。SwiftUI 无法对 overlay 背后的页面做
            // backdrop-blur（系统 material 是中性冷材质、与暖色屏冲突，见 NocturneBottomDrawer 注释），
            // 故只做纯压暗。点它不关（硬拦截：必须做选择）。
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {} // 不可点外部关闭（必须做选择）

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // Bottom sheet 卡：满宽、仅顶部两角 28pt 圆角、贴底
                VStack(spacing: 0) {
                    // §3.1 抓手：36×4 全圆角 #332D29，居中（仅视觉）
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.border)
                        .frame(width: 36, height: 4)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 16)

                    // §3.2 标题区：24pt 红/15 圆 + 16pt 红锁；19pt serif semibold，无 ✕
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.danger.opacity(0.15))
                                .frame(width: 24, height: 24)
                            Image(systemName: "lock")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.danger)
                        }
                        Text("热身还没完成")
                            .font(.system(size: 19, weight: .semibold, design: .serif))
                            .tracking(-0.5) // 真值 tracking-tight（-0.025em @19px）
                            .foregroundStyle(Color.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 8)

                    // §3.3 正文：13pt muted，leading-relaxed。诚实措辞：无真实热身进度来源，
                    // 不写死真值的「还差 5 分钟」（GateService 只有未开始的名义值）。
                    // TODO: 接真实热身剩余分钟后，恢复真值「今天的热身还差 N 分钟」
                    Text("今天的热身还没完成。热身是为了保护手，规则上不能直接进入主菜。你仍然可以手动强开，但这会被记录在月报里。")
                        .font(.system(size: 13))
                        .leading(21, fontSize: 13) // 真值 leading-relaxed（1.625）
                        .foregroundStyle(Color.textMuted)
                        .padding(.bottom, 16)

                    // §3.4 标签行：左必选说明 / 右留痕提示
                    HStack {
                        Text("强开原因（必选）")
                            .font(.labelMd)
                            .tracking(1.2) // 真值 tracking-wide（0.1em @12px）
                            .foregroundStyle(Color.textMuted)
                        Spacer(minLength: 8)
                        Text("记录于个人档案")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.amber.opacity(0.8))
                    }
                    .padding(.bottom, 10)

                    // §3.4 四行原因（整行热区，默认预选第一项）
                    VStack(spacing: 8) {
                        ForEach(ReasonTag.allCases, id: \.rawValue) { tag in
                            ReasonRow(tag: tag, isSelected: selected == tag) {
                                selected = tag
                            }
                            // 「其他」选中后展开单行输入（真值未画该态；保留现有真实行为与校验）
                            if tag == .other, selected == .other {
                                TextField("写一句原因", text: $otherNote)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.textPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color.canvas.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border.opacity(0.7), lineWidth: 1))
                            }
                        }
                    }
                    .padding(.bottom, 16)

                    // §3.5 留痕框：琥珀 10% 底 + 琥珀 28% 发丝边（无左缘竖条）；计数取真实值
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.amber)
                        Text(recordCardText)
                            .font(.system(size: 11.5))
                            .leading(19, fontSize: 11.5) // 真值 leading-relaxed
                            .foregroundStyle(Color.amber.opacity(0.95))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.amber.opacity(0.28), lineWidth: 1))
                    .padding(.bottom, 20)

                    // §3.6 按钮组：主钮在上、次钮在下（真值顺序）
                    VStack(spacing: 10) {
                        Button {
                            if let selected {
                                onConfirmOverride(selected.rawValue, selected == .other ? otherNote : "")
                            }
                        } label: {
                            Text("我确认强开，开始主菜")
                        }
                        .buttonStyle(S07cPrimaryButtonStyle(isEnabled: canConfirm))
                        .disabled(!canConfirm)

                        Button(action: onGoWarmup) {
                            Text("去补完热身")
                        }
                        .buttonStyle(S07cSecondaryButtonStyle())
                    }

                    // Home 指示条（真值：128×4 muted/25，居中）
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.textMuted.opacity(0.25))
                        .frame(width: 128, height: 4)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 28, bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0, topTrailingRadius: 28,
                        style: .continuous)
                    .fill(Color.card)
                    .shadow(color: Color.black.opacity(0.65), radius: 20, x: 0, y: -12)
                )
                // 真值 border-t 1pt #332D29：对同一个圆角形状直接描边。sheet 满宽贴屏幕底，
                // 左/右/底边落在屏幕物理边缘，整圈 strokeBorder 视觉上只剩顶部那一段，
                // 且沿 28pt 圆角弧线走（旧实现用 1pt 高矩形裁圆角 → 两端不贴角的悬空直线）。
                .overlay {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 28, bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0, topTrailingRadius: 28,
                        style: .continuous)
                        .strokeBorder(Color.border, lineWidth: 1)
                }
                // 下拉关闭（用户要求）：只响应向下拖，松手达阈值 = 取消（不留记录）；
                // 未达阈值回弹。minimumDistance 8 保证内部原因行/按钮的正常点按不被拦截。
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { v in
                            if v.translation.height > 0 { dragOffset = v.translation.height }
                        }
                        .onEnded { v in
                            if dragOffset > 100 || v.predictedEndTranslation.height > 140 {
                                withAnimation(.easeOut(duration: 0.25)) { onCancel() }
                            } else {
                                withAnimation(.easeOut(duration: 0.25)) { dragOffset = 0 }
                            }
                        }
                )
                .opacity(appeared ? 1 : 0)
                .offset(y: (appeared ? dragOffset : 24))
                .animation(.easeOut(duration: 0.3), value: appeared)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onAppear { appeared = true }
    }

    private var canConfirm: Bool {
        WarmupGate.canConfirmOverride(reasonTag: selected?.rawValue, note: otherNote)
    }

    /// §3.5 留痕文案（真实本周计数；≥3 次变体）
    private var recordCardText: String {
        let count = thisWeekCountAfterConfirm
        if count >= 3 {
            return "强开记录：本周第 \(count) 次 · 周报会提醒你留意热身习惯，不会影响任何解锁判定。"
        }
        return "强开记录：本周第 \(count) 次 · 将出现在周日 Neko 周报，不会影响任何解锁判定。"
    }
}

// MARK: - S07c 原因行 / 按钮（真值 §3.4 / §3.6）

/// 原因行（真值 §3.4）：整行热区；选中 py12 + 琥珀/40 边 + 主文字 medium，
/// 未选 py10 + #332D29/70 边 + muted；未选行 pressed 边框转实色（真值 hover:border-card-border）。
private struct ReasonRow: View {
    let tag: S07cOverrideModal.ReasonTag
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.s07cRowPressed) private var pressed

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(tag.label)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textMuted)
                Spacer(minLength: 8)
                radio
            }
            .padding(.horizontal, 14)
            .padding(.vertical, isSelected ? 12 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.canvas.opacity(0.8) : Color.canvas.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.amber.opacity(0.4) : Color.border.opacity(pressed ? 1 : 0.7), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(ReasonRowButtonStyle())
    }

    /// Radio（真值）：16×16；未选 1pt #332D29 圈，选中 2pt 琥珀圈 + 8pt 琥珀芯
    private var radio: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? Color.amber : Color.border, lineWidth: isSelected ? 2 : 1)
                .frame(width: 16, height: 16)
            if isSelected {
                Circle()
                    .fill(Color.amber)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

/// 原因行 pressed 态注入（S13b CheckboxRowButtonStyle 同款写法）
private struct ReasonRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.s07cRowPressed, configuration.isPressed)
    }
}

private struct S07cRowPressedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var s07cRowPressed: Bool {
        get { self[S07cRowPressedKey.self] }
        set { self[S07cRowPressedKey.self] = newValue }
    }
}

/// 主钮（真值 §3.6）：琥珀底 + #1C1917 14pt medium tracking-wide；pressed #C2913D + scale .99 + 琥珀柔影
private struct S07cPrimaryButtonStyle: ButtonStyle {
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .tracking(0.35) // 真值 tracking-wide（0.025em @14px）
            .foregroundStyle(isEnabled ? Color.canvas : Color.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(fill(isPressed: configuration.isPressed))
            )
            .shadow(color: Color.amber.opacity(0.1), radius: 12, x: 0, y: 4)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.99 : 1)
    }

    private func fill(isPressed: Bool) -> Color {
        guard isEnabled else { return Color.borderInput }
        return isPressed ? Color.s07cAmberPressed : Color.amber
    }
}

/// 次钮（真值 §3.6）：透明底 + 1pt #332D29 边 + 13.5pt medium muted；pressed 字转主色
private struct S07cSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Color.textPrimary : Color.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.clear)
            )
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
    }
}


#Preview {
    TodayView(onBrowseLibrary: {})
        .environmentObject(WarmupOverridePresenter())
        .modelContainer(for: [AppSettings.self, PlacementResult.self, DailyPlan.self, PracticeTask.self, GateEvent.self, Take.self, CoursePathState.self, Piece.self])
        .preferredColorScheme(.dark)
}

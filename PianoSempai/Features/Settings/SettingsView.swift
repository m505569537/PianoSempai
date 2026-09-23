import SwiftData
import SwiftUI

// MARK: - S23 我的（五组设置；无账号/登录/云同步/商店行——红线）
// 视觉对齐真值 /tmp/stitch-truth/revised/S23.md：页面大标题 + 个人状态卡 + 五组 inset-grouped
// （设备 / 课程与提醒 / AI 助教 Neko / 数据 / 关于），另保留真实合规的「乐谱来源与许可」组。
// 右值一律取真实字段，取不到显「—」；不写死周数/型号/日期/模型/容量/时刻。所有 sheet 跳转与写权逻辑不变。

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    @Query private var pathStates: [CoursePathState]
    @Query private var placementResults: [PlacementResult]
    @Query private var takes: [Take]
    @Query(sort: \AIProvider.sortOrder) private var providers: [AIProvider]
    /// 力度校准记录（按时间倒序；右值取最近一条的 createdAt，无记录显「—」）
    @Query(sort: \VelocityCalibration.createdAt, order: .reverse) private var calibrations: [VelocityCalibration]

    @ObservedObject private var hub = MIDIHub.shared
    @State private var keyStore = KeychainProviderKeyStore()

    @State private var showDiagnostics = false
    @State private var showCalibration = false
    @State private var showRetention = false
    @State private var showRoute = false
    @State private var showWeeklyGoal = false
    @State private var showAPIKey = false
    @State private var showExport = false
    @State private var showPrivacy = false
    @State private var showStorage = false
    @State private var showNotes = false
    @State private var showNotifications = false
    @State private var showAttribution = false
    /// 沙盒占用（Documents 递归求和；进入页面时算一次，避免每次 body 重算）
    @State private var storageText = "—"

    private var settings: AppSettings? { settingsList.first }
    private var pathState: CoursePathState? { pathStates.first }
    private var hasPlacement: Bool { !placementResults.isEmpty }

    /// S23 AI 行反映链路状态（「N 个服务商 · M 个可用」）；Key 有无以 Keychain 为准
    private var chainSummary: ProviderChainSummary {
        ProviderChainLogic.summarize(providers) { keyStore.hasKey(providerId: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { // 组与组间距 24
                Text("我的")
                    .font(.displayLg)
                    .foregroundStyle(Color.textPrimary)
                    .tracking(-0.5)

                avatarCard

                groupSection(title: "设备") {
                    row(
                        icon: "pianokeys",
                        tint: .amber,
                        title: "电钢琴",
                        value: deviceValue,
                        statusDot: hub.isConnected ? .connected : .muted
                    ) {
                        // 去连接 = 恢复 onboarding 的 S03 向导
                        settings?.onboardingDismissed = false
                        settings?.onboardingStage = OnboardingStage.midiWizard.rawValue
                        settings?.onboardingCompleted = false
                    }
                    hairline
                    row(
                        icon: "waveform.path.ecg",
                        title: "MIDI 诊断",
                        value: hub.isConnected && !hub.events.isEmpty ? "事件正常" : "—"
                    ) {
                        showDiagnostics = true
                    }
                    hairline
                    row(
                        icon: "slider.horizontal.3",
                        title: "力度校准",
                        value: lastCalibrationText,
                        valueMono: true
                    ) {
                        showCalibration = true
                    }
                    hairline
                    row(icon: "video", title: "视频保留", value: "每曲最近 8 条") {
                        showRetention = true
                    }
                }

                groupSection(title: "课程与提醒") {
                    row(icon: "map", title: "课程路线总览") { showRoute = true }
                    hairline
                    // 无真实时刻字段：只显开关态，不抄任何写死时刻
                    row(
                        icon: "bell",
                        title: "通知时间",
                        value: settings?.notificationConfigured == true ? "已开启" : "未开启"
                    ) {
                        showNotifications = true
                    }
                    hairline
                    row(
                        icon: "flag",
                        title: "周目标",
                        value: "\(settings?.weeklyGoal ?? 3) 次 × 30 分钟"
                    ) {
                        showWeeklyGoal = true
                    }
                }

                groupSection(title: "AI 助教 Neko", badge: "Plus") {
                    row(
                        icon: "key",
                        tint: .amber,
                        title: "AI 助教 · 服务商链",
                        value: chainSummary.settingsRowValue,
                        valueColor: chainSummary.available > 0 ? Color.textMuted : Color.amber,
                        pulse: chainSummary.available == 0 // 唯一会脉冲的设置行：链上还没有可用服务商
                    ) {
                        showAPIKey = true
                    }
                    hairline
                    // 无「默认模型」字段：按链上 sortOrder 取第一个启用服务商的首个模型，都没有显「—」
                    staticRow(
                        icon: "sparkles",
                        title: "默认模型",
                        value: firstEnabledProviderModel.map { "首选 \($0)" } ?? "—",
                        valueMono: true
                    )
                    hairline
                    row(icon: "books.vertical", title: "练琴笔记") { showNotes = true }
                }

                groupSection(title: "数据") {
                    row(icon: "square.and.arrow.up", title: "导出我的全部数据") { showExport = true }
                    hairline
                    // 恢复入口已在 ExportView 内（预览差异 → 确认 → 自动快照）：直接开同一页，不新增假页面
                    row(icon: "clock.arrow.circlepath", title: "从备份恢复") { showExport = true }
                    hairline
                    row(icon: "externaldrive", title: "存储占用", value: storageText, valueMono: true) {
                        showStorage = true
                    }
                }

                groupSection(title: "乐谱来源与许可") {
                    scoreSourcesCard
                }

                groupSection(title: "关于") {
                    row(icon: "hand.raised", title: "隐私与红线") { showPrivacy = true }
                    hairline
                    row(icon: "music.note", title: "示范音源署名") { showAttribution = true }
                    hairline
                    staticRow(icon: "info.circle", title: "版本", value: "v\(appVersion)", valueMono: true)
                }

                pageFooter
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Color.canvas)
        .onAppear(perform: measureStorage)
        .sheet(isPresented: $showDiagnostics) { MidiDiagnosticsView() }
        .sheet(isPresented: $showCalibration) { VelocityRecalibrationView() }
        .sheet(isPresented: $showRetention) { RetentionRuleSheet() }
        .sheet(isPresented: $showRoute) { RouteOverviewSheet() }
        .sheet(isPresented: $showWeeklyGoal) { WeeklyGoalSheet() }
        .sheet(isPresented: $showAPIKey) { ProviderChainSettingsView() }
        .sheet(isPresented: $showExport) { ExportView() }
        .sheet(isPresented: $showPrivacy) { PrivacyRedLinesView() }
        .sheet(isPresented: $showAttribution) { SoundFontAttributionSheet() }
        .sheet(isPresented: $showStorage) { StorageSheet() }
        .sheet(isPresented: $showNotes) { NotesView() }
        .sheet(isPresented: $showNotifications) {
            WeeklyDigestSheet()
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    // MARK: 个人状态卡（整卡可点 → 课程路线总览；右值全真实，未定级不写死第几周）

    private var avatarCard: some View {
        Button {
            showRoute = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.amber)
                    Text("猫")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(Color.canvas)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(profileMainLine)
                            .font(.titleMd)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        // 已定级才跟脉冲点；未定级不闪
                        if hasPlacement, pathState != nil {
                            PulseDot()
                        }
                    }
                    Text(profileSubLine)
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textMuted.opacity(0.7))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(SettingsRowButtonStyle())
    }

    private var profileMainLine: String {
        guard hasPlacement, let pathState else { return "自学钢琴 · 尚未定级" }
        return "自学钢琴 · 第 \(pathState.weekNumber) 周"
    }

    private var profileSubLine: String {
        guard hasPlacement, let pathState else { return "完成定级后生成路线" }
        return "路线：拜厄 \(pathState.currentBeyer) · 哈农 \(pathState.currentHanon) 并行"
    }

    // MARK: 右值真实字段

    /// 设备行右值：真实连接时用 hub 上报的源名（缺失回落「电钢琴」），绝不写死型号；未连接如实显「未连接」
    private var deviceValue: String {
        hub.isConnected ? "\(hub.connectedDeviceName ?? "电钢琴") · 已连接" : "未连接"
    }

    /// 最近一次力度校准日期（M月D日）；无记录显「—」
    private var lastCalibrationText: String {
        guard let latest = calibrations.first else { return "—" }
        return Self.monthDayFormatter.string(from: latest.createdAt)
    }

    /// 链上按 sortOrder 第一个启用服务商的首个非空模型 id（都没有 → nil → 显「—」）
    private var firstEnabledProviderModel: String? {
        for provider in providers where provider.enabled {
            if let model = provider.modelIds.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return model
            }
        }
        return nil
    }

    /// 沙盒占用：Documents 递归求和（与 StorageSheet.folderSize 同法）；算不出显「—」
    private func measureStorage() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let bytes = StorageSheet.folderSize(docs)
        storageText = bytes > 0 ? "约 " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : "—"
    }

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    // MARK: 乐谱来源与许可

    /// 随 app 分发的内置公版谱署名与许可（合规必需；纯静态文本，无跳转）
    private var scoreSourcesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("内置教材谱均为公有领域作品的电子版，随 app 一起分发；本 app 不声称拥有原作曲版权。")
                .font(.labelSm)
                .foregroundStyle(Color.textBody)
            sourceBlock(
                title: "拜厄《钢琴基本教程》Op.101",
                lines: [
                    "Ferdinand Beyer，1851 · 公有领域",
                    "数字谱源：hustcsz/mudata（MIT License）",
                    "github.com/hustcsz/mudata"
                ]
            )
            sourceBlock(
                title: "哈农《钢琴练指法》第一部分",
                lines: [
                    "Charles-Louis Hanon，1873 · 公有领域",
                    "排版：Mutopia Project（据 Schirmer 1900 版）· CC BY-SA 4.0",
                    "本 app 做 MIDI→MusicXML 转换，并将右手移调 +12",
                    "mutopiaproject.org · creativecommons.org/licenses/by-sa/4.0"
                ]
            )
            Text("车尔尼599 暂无内置谱，解锁前不可判分。")
                .font(.labelSm)
                .foregroundStyle(Color.textMuted)
        }
        .padding(.vertical, 14)
    }

    private func sourceBlock(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.labelMd)
                .foregroundStyle(Color.textPrimary)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    // MARK: 组样式

    /// 组标题 12pt medium muted/80 + tracking-wide（标题逐字；不做 uppercase——会把「Neko」改成「NEKO」）
    private func groupLabel(_ text: String, badge: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.labelMd)
                .foregroundStyle(Color.textMuted.opacity(0.8))
                .tracking(0.6)
            if let badge {
                Text(badge)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.amber)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 2))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private var hairline: some View {
        Rectangle().fill(Color.border.opacity(0.6)).frame(height: 1)
    }

    /// 组卡：card 底 / 1pt border / 圆角 16 / overflow-hidden
    private func groupCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
    }

    /// 一组 = 组标题（px2）+ 组卡，标题与卡间距 6
    private func groupSection(title: String, badge: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            groupLabel(title, badge: badge)
            groupCard { content() }
        }
    }

    /// 行按压底 white/3%（真值 active:bg-white/[0.03]）
    private struct SettingsRowButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(Color.white.opacity(configuration.isPressed ? 0.03 : 0))
        }
    }

    /// 琥珀脉冲点（6×6）：个人卡周数 / 服务商链无可用时
    private struct PulseDot: View {
        var color: Color = Color.amber
        var size: CGFloat = 6

        @State private var dimmed = false

        var body: some View {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .opacity(dimmed ? 0.3 : 1)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        dimmed = true
                    }
                }
        }
    }

    /// 图标盒风格：琥珀语义行（电钢琴、服务商链）/ 普通行
    private enum RowTint {
        case amber, plain
    }

    /// 行右状态点（8×8；连接态带辉光）
    private enum RowStatusDot {
        case connected, muted
    }

    private func iconBox(_ icon: String, tint: RowTint) -> some View {
        let isAmber = tint == .amber
        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isAmber ? Color.amber.opacity(0.1) : Color.white.opacity(0.05))
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isAmber ? Color.amber.opacity(0.2) : Color.white.opacity(0.1), lineWidth: 1)
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isAmber ? Color.amber : Color.textMuted)
        }
        .frame(width: 28, height: 28)
    }

    private func statusDotView(_ kind: RowStatusDot) -> some View {
        let color: Color = kind == .connected ? Color.success : Color.textMuted
        return Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: kind == .connected ? color.opacity(0.5) : .clear, radius: 3)
    }

    /// 行：28×28 圆角 8 图标盒 + 14pt medium 标题 + 右值/状态点 + chevron；行高约 48
    private func row(
        icon: String,
        tint: RowTint = .plain,
        title: String,
        value: String? = nil,
        valueMono: Bool = false,
        valueColor: Color = Color.textMuted,
        statusDot: RowStatusDot? = nil,
        pulse: Bool = false,
        showsChevron: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                iconBox(icon, tint: tint)
                Text(title)
                    .font(.bodyMd.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                if pulse {
                    PulseDot()
                }
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    if let statusDot {
                        statusDotView(statusDot)
                    }
                    if let value {
                        Text(value)
                            .font(valueMono ? .labelMono(12) : .bodySm)
                            .foregroundStyle(valueColor)
                            .lineLimit(1)
                    }
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.textMuted.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowButtonStyle())
    }

    /// 不可点行（本页无独立页的条目：不给假跳转，无 chevron）
    private func staticRow(
        icon: String,
        title: String,
        value: String? = nil,
        valueMono: Bool = false,
        valueColor: Color = Color.textMuted
    ) -> some View {
        HStack(spacing: 12) {
            iconBox(icon, tint: .plain)
            Text(title)
                .font(.bodyMd.weight(.medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let value {
                Text(value)
                    .font(valueMono ? .labelMono(12) : .bodySm)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
    }

    /// 末组外页脚（真值逐字）
    private var pageFooter: some View {
        Text("PianoSempai · 静夜琴房")
            .font(.system(size: 11, design: .serif))
            .foregroundStyle(Color.textMuted.opacity(0.7))
            .tracking(1.5)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 24)
    }
}

// MARK: - 课程路线总览（真实数据只读展示）

private struct RouteOverviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var pathStates: [CoursePathState]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if let state = pathStates.first {
                    routeRow("拜厄", "当前第 \(state.currentBeyer) 条")
                    routeRow("哈农", "当前第 \(state.currentHanon) 条")
                    routeRow("车尔尼 599", state.projected599Week > 0 ? "约 \(state.projected599Week) 周后解锁" : "未排期")
                    routeRow("周数", "第 \(state.weekNumber) 周")
                    Text("过关 = 连续 2 次 take 达到硬指标（错音率/节奏偏差/速度），由课程引擎判定（P2 完整接入）。")
                        .font(.labelSm)
                        .leading(16, fontSize: 11)
                        .foregroundStyle(Color.textMuted)
                } else {
                    Text("还没有路线。完成定级后这里显示拜厄/哈农/599 的插入点。")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                }
                Spacer()
            }
            .padding(20)
            .background(Color.canvas)
            .navigationTitle("课程路线总览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.amber)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }

    private func routeRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.bodyMd).foregroundStyle(Color.textBody)
            Spacer()
            Text(value).font(.titleMd).foregroundStyle(Color.amber).monospacedDigit()
        }
    }
}

// MARK: - 视频保留规则（真实规则可改；LRU N / never）

private struct RetentionRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]
    @Environment(\.modelContext) private var context

    @State private var mode = "lru8" // lru8 / never

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("视频按规则自动清理：每曲只保留最近的 take 录像；月度 Zf 录像永不清理。")
                    .font(.bodySm)
                    .leading(19, fontSize: 12)
                    .foregroundStyle(Color.textMuted)
                Button {
                    mode = "lru8"
                } label: {
                    radioRow("每曲最近 8 条（默认）", selected: mode == "lru8")
                }
                .buttonStyle(.plain)
                Button {
                    mode = "never"
                } label: {
                    radioRow("不自动清理", selected: mode == "never")
                }
                .buttonStyle(.plain)
                Text("P1 无视频捕获；规则在「录给 AI 看」批次（S15）生效。")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
                Spacer()
            }
            .padding(20)
            .background(Color.canvas)
            .navigationTitle("视频保留")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.amber)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }

    private func radioRow(_ label: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().strokeBorder(selected ? Color.amber : Color.borderInput, lineWidth: 1)
                    .frame(width: 16, height: 16)
                Circle().fill(Color.amber).frame(width: 8, height: 8).opacity(selected ? 1 : 0)
            }
            Text(label).font(.bodyMd).foregroundStyle(Color.textPrimary)
            Spacer()
        }
    }
}

// MARK: - 周目标（真实写 AppSettings.weeklyGoal）

private struct WeeklyGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]
    @Environment(\.modelContext) private var context
    @State private var goal = 3

    private var settings: AppSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("每周练几次？")
                    .font(.headlineLg)
                    .foregroundStyle(Color.textPrimary)
                Stepper("\(goal) 次", value: $goal, in: 1...7)
                    .font(.titleMd)
                    .tint(Color.amber)
                    .padding(.horizontal, 40)
                Text("弹性区间 3–5 次（PRD M9），不预设星期几；断练不扣任何东西。")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("保存") {
                    settings?.weeklyGoal = goal
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle(cornerRadius: 8))
                .padding(.horizontal, 60)
                Spacer()
            }
            .padding(.top, 32)
            .background(Color.canvas)
            .navigationTitle("周目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Color.amber)
                }
            }
            .onAppear { goal = settings?.weeklyGoal ?? 3 }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }
}

// MARK: - 存储占用（真实计算沙盒体积）

private struct StorageSheet: View {
    @State private var rows: [(String, Int64)] = []

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(rows, id: \.0) { row in
                    HStack {
                        Text(row.0).font(.bodyMd).foregroundStyle(Color.textBody)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: row.1, countStyle: .file))
                            .font(.labelMd)
                            .foregroundStyle(Color.textPrimary)
                            .monospacedDigit()
                    }
                }
                if rows.isEmpty {
                    Text("还没有占用。")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                }
                Text("视频清理规则见「设备 → 视频保留」。")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
                Spacer()
            }
            .padding(20)
            .background(Color.canvas)
            .navigationTitle("存储占用")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.amber)
                }
            }
            .onAppear(perform: measure)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }

    @Environment(\.dismiss) private var dismiss

    private func measure() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        rows = ["midi", "scores", "pdfs", "exports"].map { dir in
            let url = docs.appendingPathComponent(dir, isDirectory: true)
            return (dir, Self.folderSize(url))
        }.filter { $0.1 > 0 }
    }

    static func folderSize(_ url: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

// MARK: - 隐私与六条红线（静态页；PRD §3 原文摘录，逐字）

struct PrivacyRedLinesView: View {
    @Environment(\.dismiss) private var dismiss

    private let redLines = [
        "1. 课程只许挂靠成熟教材（拜厄/哈农/车尔尼），AI 无锚点自创教学体系=禁止。",
        "2. 分析没把握就明说（对齐低置信、手型没看清），禁止编造结论。",
        "3. AI 只有建议权；课程状态只由课程引擎消费硬数据写入。",
        "4. 视频镜头不常开；上传必经区间裁切+确认弹框+服务商明示（本次链路实际命中者）。",
        "5. 手型永远是助教：不进门禁，永久声明单摄死角。",
        "6. 产品性格：当坏人（热身不静默跳过、硬门禁）但语气温柔，不搞 guilt trip。",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("数据只存在这台手机上")
                        .font(.headlineLg)
                        .foregroundStyle(Color.textPrimary)
                        .padding(.top, 8)
                    Text("本应用没有服务器、没有账号。MIDI、笔记、录像只存本机；导出包不含 API Key；唯一网络出口是你在 AI 助教服务商链里主动发起的请求。")
                        .font(.bodySm)
                        .leading(19, fontSize: 12)
                        .foregroundStyle(Color.textBody)
                        .padding(.top, 6)

                    Text("六条核心红线")
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                        .padding(.top, 20)
                    ForEach(redLines, id: \.self) { line in
                        Text(line)
                            .font(.bodySm)
                            .leading(19, fontSize: 12)
                            .foregroundStyle(Color.textBody)
                            .padding(.top, 10)
                    }
                    Text("原文见 docs/PRD.md §3（开发真值）。")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
            .background(Color.canvas)
            .navigationTitle("隐私与红线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.amber)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

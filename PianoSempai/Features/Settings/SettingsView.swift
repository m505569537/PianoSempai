import SwiftData
import SwiftUI

// MARK: - S23 我的（五组设置；无账号/登录/云同步/商店行——红线）

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    @Query private var pathStates: [CoursePathState]
    @Query private var placementResults: [PlacementResult]
    @Query private var takes: [Take]

    @ObservedObject private var hub = MIDIHub.shared
    @State private var keyStore = KeychainAPIKeyStore()

    @State private var showDiagnostics = false
    @State private var showCalibration = false
    @State private var showRetention = false
    @State private var showRoute = false
    @State private var showWeeklyGoal = false
    @State private var showAPIKey = false
    @State private var showExport = false
    @State private var showPrivacy = false
    @State private var showStorage = false
    @State private var showNotesPlaceholder = false
    @State private var showNotifications = false

    private var settings: AppSettings? { settingsList.first }
    private var pathState: CoursePathState? { pathStates.first }
    private var hasPlacement: Bool { !placementResults.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("我的")
                    .font(.displayLg)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.top, 8)

                avatarCard.padding(.top, 16)

                groupLabel("设备")
                groupCard {
                    row(
                        icon: hub.isConnected ? "pianokeys" : "exclamationmark.circle",
                        title: hub.isConnected ? "特伦斯 V70 · 已连接" : "未连接 · 去连接",
                        valueColor: hub.isConnected ? Color.textBody : Color.danger
                    ) {
                        // 去连接 = 恢复 onboarding 的 S03 向导
                        settings?.onboardingDismissed = false
                        settings?.onboardingStage = OnboardingStage.midiWizard.rawValue
                        settings?.onboardingCompleted = false
                    }
                    hairline
                    row(icon: "waveform.path.ecg", title: "MIDI 诊断") { showDiagnostics = true }
                    hairline
                    row(icon: "slider.horizontal.3", title: "力度校准") { showCalibration = true }
                    hairline
                    row(icon: "video", title: "视频保留：每曲最近 8 条") { showRetention = true }
                }

                groupLabel("课程与提醒")
                groupCard {
                    row(icon: "map", title: "课程路线总览") { showRoute = true }
                    hairline
                    row(icon: "bell", title: "通知：周日 21:00 · 工作日 20:30") { showNotifications = true }
                    hairline
                    row(icon: "target", title: "周目标：\(settings?.weeklyGoal ?? 3) 次 × 30 分钟") { showWeeklyGoal = true }
                }

                groupLabel("AI 助教")
                groupCard {
                    row(
                        icon: "key",
                        title: "火山方舟 API Key",
                        value: keyStore.hasKey ? "已设置" : "未设置",
                        pulse: !keyStore.hasKey // 唯一会脉冲的设置行（spec）
                    ) {
                        showAPIKey = true
                    }
                    hairline
                    row(icon: "cpu", title: "文字/数据模型：doubao-seed-2.0-pro") { showAPIKey = true }
                    hairline
                    row(icon: "note.text", title: "练琴笔记") { showNotesPlaceholder = true }
                }

                groupLabel("数据")
                groupCard {
                    row(icon: "square.and.arrow.up", title: "导出我的全部数据") { showExport = true }
                    hairline
                    row(icon: "externaldrive", title: "存储占用") { showStorage = true }
                }

                groupLabel("关于")
                groupCard {
                    row(icon: "hand.raised", title: "隐私与六条红线") { showPrivacy = true }
                    hairline
                    staticRow(icon: "info.circle", title: "版本 v\(appVersion)")
                }

                Text("第 4 tab 恒为「档案」· 本页无账号/云同步/商店入口")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textMuted.opacity(0.7))
                    .padding(.top, 16)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
        .background(Color.canvas)
        .sheet(isPresented: $showDiagnostics) { MidiDiagnosticsView() }
        .sheet(isPresented: $showCalibration) { VelocityRecalibrationView() }
        .sheet(isPresented: $showRetention) { RetentionRuleSheet() }
        .sheet(isPresented: $showRoute) { RouteOverviewSheet() }
        .sheet(isPresented: $showWeeklyGoal) { WeeklyGoalSheet() }
        .sheet(isPresented: $showAPIKey) { APIKeySettingsView() }
        .sheet(isPresented: $showExport) { ExportView() }
        .sheet(isPresented: $showPrivacy) { PrivacyRedLinesView() }
        .sheet(isPresented: $showStorage) { StorageSheet() }
        .sheet(isPresented: $showNotesPlaceholder) {
            M6bPlaceholderSheet(title: "练琴笔记", note: "S19 本地笔记（手动/问题）在下一批次提供。")
        }
        .sheet(isPresented: $showNotifications) {
            M6bPlaceholderSheet(title: "通知", note: "周日 21:00 周报与工作日提醒属 M9 本地通知批次；本页先展示计划时段。")
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    // MARK: 头像卡

    private var avatarCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().strokeBorder(Color.amber, lineWidth: 1.5)
                            .frame(width: 52, height: 52)
                        Image(systemName: "cat")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.amber)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Neko 的学生")
                            .font(.titleMd)
                            .foregroundStyle(Color.textPrimary)
                        Text(routeLine)
                            .font(.bodySm)
                            .foregroundStyle(Color.textMuted)
                            .monospacedDigit()
                    }
                    Spacer()
                }
                HStack {
                    Spacer()
                    Text("课程路线总览")
                        .font(.labelMd)
                        .foregroundStyle(Color.amber)
                }
                .contentShape(Rectangle())
                .onTapGesture { showRoute = true }
            }
        }
    }

    private var routeLine: String {
        guard hasPlacement, let pathState else { return "尚未定级" }
        let goal = settings?.weeklyGoal ?? 3
        return "第 \(pathState.weekNumber) 周 · 拜厄\(pathState.currentBeyer) · 本周 \(goal)×30 分钟"
    }

    // MARK: 组样式

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.labelMd)
            .foregroundStyle(Color.textMuted)
            .padding(.top, 20)
    }

    private var hairline: some View {
        Rectangle().fill(Color.border).frame(height: 1)
    }

    private func groupCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 14)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
            .padding(.top, 8)
    }

    private func row(icon: String, title: String, value: String? = nil, valueColor: Color = Color.textMuted, pulse: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textBody)
                    .frame(width: 22)
                Text(title)
                    .font(.bodyMd)
                    .foregroundStyle(Color.textPrimary)
                if pulse {
                    Circle()
                        .fill(Color.amber)
                        .frame(width: 6, height: 6)
                        .opacity(breathing ? 0.3 : 1)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                                breathing = true
                            }
                        }
                }
                Spacer()
                if let value {
                    Text(value)
                        .font(.bodySm)
                        .foregroundStyle(valueColor)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMuted)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func staticRow(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.textBody)
                .frame(width: 22)
            Text(title)
                .font(.bodyMd)
                .foregroundStyle(Color.textBody)
            Spacer()
        }
        .frame(minHeight: 48)
    }

    @State private var breathing = false
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
        "4. 视频镜头不常开；上传必经区间裁切+确认弹框+服务商明示（火山方舟）。",
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
                    Text("本应用没有服务器、没有账号。MIDI、笔记、录像只存本机；导出包不含 API Key；唯一网络出口是你在 AI 助教里主动发起的火山方舟请求。")
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

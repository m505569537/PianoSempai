import SwiftData
import SwiftUI
import UserNotifications

// M7.2 · S23 通知开关页（替换 M6b 占位）：周日 21:00 周报，每周最多一条，全可关。
// 授权时机：只在用户开 toggle 且系统未决定时才弹系统授权框；launch 永不主动弹（协调器静默跳过）。
// 只写 AppSettings.weeklyDigestEnabled + 排期刷新，不碰课程状态（红线 3）。

struct WeeklyDigestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]

    @State private var coordinator: WeeklyDigestCoordinator?
    @State private var systemStatus: UNAuthorizationStatus = .notDetermined
    @State private var showDeniedHint = false

    private var settings: AppSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("每周最多一条：本周练了几次 + 下周一个小建议。")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 8)

                groupCard {
                    Toggle(isOn: toggleBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("周日 21:00 周报")
                                .font(.bodyMd)
                                .foregroundStyle(Color.textPrimary)
                            Text("本周练了几次 + 下周一个小建议")
                                .font(.labelSm)
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                    .tint(Color.amber)
                    .padding(.vertical, 8)
                    hairline
                    HStack {
                        Text("系统通知权限")
                            .font(.bodySm)
                            .foregroundStyle(Color.textBody)
                        Spacer()
                        Text(Self.statusText(systemStatus))
                            .font(.bodySm)
                            .foregroundStyle(systemStatus == .denied ? Color.amber : Color.textMuted)
                    }
                    .padding(.vertical, 12)
                    if showDeniedHint {
                        hairline
                        Text("系统设置中已关闭通知，可在 系统设置 > 通知 打开")
                            .font(.labelSm)
                            .foregroundStyle(Color.amber)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.top, 16)

                Text("数字只来自本机真实练习记录；周报同时存档到「练琴笔记 · 周报」。")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 12)

                Spacer()
            }
            .padding(.horizontal, 20)
            .background(Color.canvas)
            .navigationTitle("通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.amber)
                }
            }
            .task {
                // 兜底确保单例存在（正常路径 RootView 已建；此处幂等）
                _ = AppSettings.fetchOrCreate(in: context)
                coordinator = coordinator ?? WeeklyDigestCoordinator.live(context: context)
                await reloadStatus()
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }

    // MARK: 开关

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { settings?.weeklyDigestEnabled ?? false },
            set: { newValue in
                settings?.weeklyDigestEnabled = newValue
                showDeniedHint = false
                Task { await handleToggle(newValue) }
            }
        )
    }

    private func handleToggle(_ newValue: Bool) async {
        guard let coordinator else { return }
        if newValue {
            switch await coordinator.scheduler.authorizationStatus() {
            case .notDetermined:
                // 首次开启：弹一次系统授权框；被拒 → 回退关闭 + 行下说明（不重复弹框）
                let granted = (try? await coordinator.scheduler.requestAuthorization()) ?? false
                if !granted {
                    settings?.weeklyDigestEnabled = false
                    showDeniedHint = true
                }
            case .denied:
                settings?.weeklyDigestEnabled = false
                showDeniedHint = true
            case .authorized, .provisional, .ephemeral:
                break
            @unknown default:
                break
            }
        }
        await reloadStatus()
        // 排期立即生效 / 移除（关：撤掉 pending；开：按截至目前数据排本周唯一一条）
        await coordinator.refresh()
    }

    private func reloadStatus() async {
        guard let coordinator else { return }
        systemStatus = await coordinator.scheduler.authorizationStatus()
    }

    private static func statusText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "未询问"
        case .denied: return "已关闭"
        case .authorized: return "已允许"
        case .provisional: return "已允许（静默）"
        case .ephemeral: return "临时允许"
        @unknown default: return "未知"
        }
    }

    // MARK: 样式（与 SettingsView 组卡同款）

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
}

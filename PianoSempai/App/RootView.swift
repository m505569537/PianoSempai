import SwiftData
import SwiftUI

/// App 根视图：
/// - onboarding 完成 → S06 App Frame（5 tab）
/// - onboarding 未完成且未中途退出 → Onboarding 流程（S01–S05，全屏无 tab）
/// - 中途退出（onboardingDismissed）→ 框架；S07b「继续定级」在 M4 恢复流程
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settingsList: [AppSettings]

    /// M7.2 周报协调器：启动 + 每次进后台/失活刷新（排期本周唯一一条通知 / 落周报）。
    /// ModelContext 来自 modelContainer，生命周期与 App 一致。
    @State private var coordinator: WeeklyDigestCoordinator?

    var body: some View {
        Group {
            if let settings = settingsList.first {
                if settings.onboardingCompleted || settings.onboardingDismissed {
                    AppFrameView()
                } else {
                    OnboardingFlowView()
                }
            } else {
                // 首次启动：建单例设置（task 中写，避免视图更新期写库）
                Color.canvas
                    .ignoresSafeArea()
                    .task {
                        let settings = AppSettings.fetchOrCreate(in: context)
                        // DEBUG-only 视觉验收钩子：simctl launch 传 --ui.skipOnboarding 直接看今日页。
                        // 只改 onboarding 标志，绝不写课程状态（红线 1/3）。
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("--ui.skipOnboarding") {
                            settings.onboardingCompleted = true
                        }
                        #endif
                    }
            }
        }
        .background(Color.canvas)
        .task { await ensureCoordinator().refresh() }
        .onChange(of: scenePhase) { _, phase in
            // 周日练完进后台时会再刷一次：通知文案随之覆盖更新（含周日练习）
            guard phase == .background || phase == .inactive else { return }
            Task { await ensureCoordinator().refresh() }
        }
    }

    private func ensureCoordinator() -> WeeklyDigestCoordinator {
        if let coordinator { return coordinator }
        let created = WeeklyDigestCoordinator.live(context: context)
        coordinator = created
        return created
    }
}

import SwiftData
import SwiftUI

/// App 根视图：
/// - onboarding 完成 → S06 App Frame（5 tab）
/// - onboarding 未完成且未中途退出 → Onboarding 流程（S01–S05，全屏无 tab）
/// - 中途退出（onboardingDismissed）→ 框架；S07b「继续定级」在 M4 恢复流程
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]

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
                    .task { _ = AppSettings.fetchOrCreate(in: context) }
            }
        }
        .background(Color.canvas)
    }
}

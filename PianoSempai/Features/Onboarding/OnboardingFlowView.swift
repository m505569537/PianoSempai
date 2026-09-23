import SwiftData
import SwiftUI

// MARK: - Onboarding 流程路由（S01→S02→S03→S04→S05；全屏流程无 tab 栏）
// 未完成可退出续做（onboarding 域契约）：阶段持久化在 AppSettings.onboardingStage，
// S03 ✕ / S04 稍后评估 → 退出到框架（dismissed=true），M4 的 S07b「继续定级」负责恢复。

struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    @State private var stage: OnboardingStage = .welcome

    private var settings: AppSettings? { settingsList.first }

    var body: some View {
        Group {
            switch stage {
            case .welcome:
                S01WelcomeView(onStart: { advance(to: .permissions) })
            case .permissions:
                S02PermissionsView(onContinue: { advance(to: .midiWizard) })
            case .midiWizard:
                S03MidiWizardView(
                    // ‹ 返回：第 1 步回 S02 权限页（真值 §2 的「返回」在本流程没有上一步可退）
                    onBack: { advance(to: .permissions) },
                    onSkip: { dismissToFrame() },
                    onDone: { advance(to: .placement) }
                )
            case .placement:
                S04PlacementView(
                    onLater: { dismissToFrame() },
                    onFinished: { advance(to: .result) }
                )
            case .result:
                S05ResultView(
                    onGeneratePlan: { generatePlanAndFinish() },
                    onRetake: { advance(to: .placement) }
                )
            case .done:
                AppFrameView()
            }
        }
        .onAppear {
            if let saved = settings.flatMap({ OnboardingStage(rawValue: $0.onboardingStage) }) {
                stage = saved == .done ? .welcome : saved
            }
        }
    }

    private func advance(to newStage: OnboardingStage) {
        stage = newStage
        settings?.onboardingStage = newStage.rawValue
        // 进入定级时打点：S07b「继续定级（还剩 X 分钟）」的诚实估算依据
        if newStage == .placement, settings?.placementStartedAt == nil {
            settings?.placementStartedAt = Date()
        }
    }

    /// 退出流程回框架（进度已存；S07b 继续定级在 M4 接入）
    private func dismissToFrame() {
        settings?.onboardingDismissed = true
    }

    /// S05 CTA：CourseEngine 建第 1 周 DailyPlan + 完成 onboarding
    private func generatePlanAndFinish() {
        let descriptor = FetchDescriptor<PlacementResult>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        if let result = try? context.fetch(descriptor).first {
            _ = CourseEngine.generateFirstWeekPlan(result: result, in: context)
        }
        settings?.onboardingCompleted = true
        settings?.onboardingStage = OnboardingStage.done.rawValue
        stage = .done
    }
}

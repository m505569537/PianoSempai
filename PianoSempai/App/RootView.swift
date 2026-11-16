import SwiftData
import SwiftUI

/// PRD 65：app 退后台/锁屏 → 进行中的 take 正常收尾保存（MIDI 采集按 iOS 限制不硬抗）。
/// 练习室监听这个名字调 finishAndSave()；RootView 是唯一 post 点（scenePhase 只在根上读）。
extension Notification.Name {
    static let pianoSempaiAppDidEnterBackground = Notification.Name("pianoSempaiAppDidEnterBackground")
}

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

    /// DEBUG-only：--ui.practice <book>:<number> 直达练习室预览内置谱。
    /// 只用于开发期核对谱面渲染，不改课程状态、不落 take（Release 编译期剔除）。
    @State private var debugPracticeOpen = false

    /// M7.2 月报协调器：启动 + 每次进后台/失活刷新（每月 1 号为上月起草 + 回填观察）。
    /// 与周报协调器并存，各自 @State；月报失败只降级状态，不影响周报。
    @State private var monthlyCoordinator: MonthlyReportCoordinator?

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
            }
        }
        .background(Color.canvas)
        #if DEBUG
        .fullScreenCover(isPresented: $debugPracticeOpen) {
            if let entry = Self.debugPracticeEntry {
                PracticeRoomView(
                    taskType: "main",
                    pieceTitle: "\(entry.book) 第\(entry.number)条",
                    bundledBook: entry.book,
                    bundledNumber: entry.number
                )
            }
        }
        #endif
        .task {
            // DEBUG-only 视觉验收钩子：simctl launch 传 --ui.skipOnboarding 直接进主框架。
            // 挂在根视图（不挂首次启动分支——settings 一旦存在，那条分支永远不再走，钩子即失效）。
            // 只改 onboarding 标志，绝不写课程状态（红线 1/3）。
            #if DEBUG
            // --ui.simulated：调试期用模拟 MIDI 源（真机不在手边时看谱面/判分链路）
            if ProcessInfo.processInfo.arguments.contains("--ui.simulated") {
                MIDIHub.shared.switchSource(.simulated)
            }
            if Self.debugPracticeEntry != nil { debugPracticeOpen = true }
            if ProcessInfo.processInfo.arguments.contains("--ui.skipOnboarding") {
                let settings = settingsList.first ?? AppSettings.fetchOrCreate(in: context)
                if !settings.onboardingCompleted {
                    settings.onboardingCompleted = true
                }
                // 缺 save 会丢：autosave 不保证覆盖 task 内的修改，重启后仍在 onboarding。
                try? context.save()
            }
            #endif
            // Stage B §1 启动接线（ADR-0003）：先对账（既有已定级但无 Piece 行 → 一次性补建），
            // 再翻到期复习（passed → reviewing）——顺序必须 reconcile 在前，roll 才有东西可翻。
            // 两函数 Stage A 已实现且幂等；只在此单入口 roll（scenePhase onChange 不重复，无必要）。
            CourseEngine.reconcileIfNeeded(in: context)
            _ = CourseEngine.rollDueReviews(in: context)
            try? context.save()
            // 自动快照（2026-11-12）：练习数据只存本机、无 iCloud 同步，每周打一份
            // 不含视频的完整备份兜底（保留最近 3 份）。失败静默、下次启动重试，不打扰使用。
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            AutoSnapshot.runIfDue(baseDir: documents, context: context)
            await ensureCoordinator().refresh()
            await ensureMonthlyCoordinator().refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            // 周日练完进后台时会再刷一次：通知文案随之覆盖更新（含周日练习）
            guard phase == .background || phase == .inactive else { return }
            if phase == .background {
                // PRD：退后台 → 练习室把进行中的 take 正常收尾保存（练习室 onReceive 接）
                NotificationCenter.default.post(name: .pianoSempaiAppDidEnterBackground, object: nil)
            }
            Task { await ensureCoordinator().refresh() }
            Task { await ensureMonthlyCoordinator().refresh() }
        }
    }

    #if DEBUG
    /// 解析 `--ui.practice c599:1`（也接受教材中文名）。仅在 Debug 存在。
    static var debugPracticeEntry: (book: String, number: Int)? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--ui.practice"), args.indices.contains(i + 1) else { return nil }
        let parts = args[i + 1].split(separator: ":")
        guard parts.count == 2, let number = Int(parts[1]) else { return nil }
        let raw = String(parts[0])
        let book = raw == "c599" ? "车尔尼599" : raw
        guard BundledScore.hasBundled(book: book, number: number) else { return nil }
        return (book, number)
    }
    #endif

    private func ensureCoordinator() -> WeeklyDigestCoordinator {
        if let coordinator { return coordinator }
        let created = WeeklyDigestCoordinator.live(context: context)
        coordinator = created
        return created
    }

    private func ensureMonthlyCoordinator() -> MonthlyReportCoordinator {
        if let monthlyCoordinator { return monthlyCoordinator }
        let created = MonthlyReportCoordinator.live(context: context)
        monthlyCoordinator = created
        return created
    }
}

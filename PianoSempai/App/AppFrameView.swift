import SwiftUI

// S06 全局导航骨架：5 tab 写死（visual-system §9 第 1 条，永不出现商城/商店/榜单等替代词）
enum AppTab: CaseIterable, Identifiable {
    case today, library, practice, archive, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "今日"
        case .library: "曲库"
        case .practice: "练习室"
        case .archive: "档案" // 第 4 tab 恒为档案（验收负例；S06 spec 明令禁止商城/社区/榜单）
        case .settings: "我的"
        }
    }

    /// SF Symbol：日历 / 翻开的乐谱书 / 钢琴键盘 / 归档盒 / 头像（S06 视觉规范）
    var icon: String {
        switch self {
        case .today: "calendar"
        case .library: "book"
        case .practice: "pianokeys"
        case .archive: "archivebox"
        case .settings: "person.crop.circle"
        }
    }
}

/// S07c 热身强开弹层的顶层 presenter（S07c 呈现层级修复）。
/// 该弹层必须整屏遮住底部 tab bar 与「问 Neko」FAB（真值：整屏 scrim bg-black/60，
/// 底栏/FAB 被整块遮住）。tab bar 与 FAB 渲染在 AppFrameView 的
/// `.safeAreaInset(edge: .bottom)` 里，层级在任意子页（如 TodayView）之外、之上；
/// 若弹层仍挂在 TodayView 自身的 overlay 上，就只能盖住页内容、盖不住底栏（已截图实证）。
/// 故提升到 AppFrameView 顶层渲染：由本 presenter 持有配置，页面经环境对象触发呈现。
final class WarmupOverridePresenter: ObservableObject {
    struct Config {
        let plan: DailyPlan?
        let allEvents: [GateEvent]
        let onGoWarmup: () -> Void
        let onConfirmOverride: (_ reasonTag: String, _ note: String) -> Void
    }
    @Published private(set) var isPresented = false
    private(set) var config: Config?
    func present(_ config: Config) { self.config = config; isPresented = true }
    func dismiss() { isPresented = false }
}

/// S06 App Frame：5 tab + 问 Neko FAB + 顶部连接胶囊。
/// 无 tab 栏页面的路由机制：全屏流程/弹层一律走 fullScreenCover / sheet（系统天然隐藏
/// tab bar），框架不做自定义路由栈；onboarding（S01–S05）、练习室（S11）、报告（S13）
/// 等后续批次均从本框架以 fullScreenCover 呈现。
struct AppFrameView: View {
    @ObservedObject private var midi = MIDIHub.shared
    @Environment(\.modelContext) private var context
    @State private var tab: AppTab = AppFrameView.initialTab()
    /// 问 Neko FAB → S18 自由问答（fullScreenCover，天然隐藏 tab bar）
    @State private var showChat = false
    /// S07c 热身强开弹层：在顶层（tab bar / FAB 之上）呈现
    @StateObject private var overridePresenter = WarmupOverridePresenter()

    /// DEBUG 视觉验收：simctl launch 传 --ui.tab.library / --ui.tab.practice 直落对应 tab
    static func initialTab() -> AppTab {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui.tab.library") { return .library }
        if args.contains("--ui.tab.practice") { return .practice }
        if args.contains("--ui.tab.archive") { return .archive }
        if args.contains("--ui.tab.settings") { return .settings }
        #endif
        return .today
    }

    var body: some View {
        ZStack(alignment: .top) {
            // S07c presenter 注入环境：TodayView 经它触发顶层弹层（不在子页 overlay 里渲染）
            pageContent
                .environmentObject(overridePresenter)

            // 顶部连接胶囊（visual-system §6：右上线框胶囊）
            // D5（S07 视觉对齐）：今日页改用标题行内胶囊（TodayView §2.1）
            // D6（S08 视觉对齐）：曲库页 header 右侧是「导入 + 搜索」两枚圆钮（LibraryView §2），
            //   不放胶囊以免遮挡圆钮。故全局胶囊仅在今日、曲库两页之外显示。
            if tab != .today && tab != .library {
                HStack {
                    Spacer()
                    ConnectionPill(state: connectionState)
                        .padding(.trailing, 20)
                        .padding(.top, 6)
                }
            }
        }
        .background(Color.canvas)
        .fullScreenCover(isPresented: $showChat) {
            // S18 问 Neko：自由问答入口，不带任何练习数据（take 上下文由 S13 提供）
            ChatView(mode: .freeform, context: context)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                // 问 Neko FAB：独立悬浮于 tab 栏上方偏右（不进 5 tab）
                // S20/S08/S23 视觉对齐：FAB 仅 S07 今日 / S11 练习两屏有真值；档案 tab 由
                // ArchiveView 自带琥珀实色 FAB（S20 真值），曲库/我的无 FAB。
                // 故全局 FAB 只在今日、练习两 tab 渲染，避免档案页出现两个 FAB。
                if tab == .today || tab == .practice {
                    HStack {
                        Spacer()
                        NekoFAB { showChat = true }
                            .padding(.trailing, 20)
                            .padding(.bottom, 12)
                    }
                }
                TabBar(selected: $tab)
            }
            .background(Color.canvas.ignoresSafeArea(edges: .bottom))
        }
        // S07c 热身强开弹层：必须在 safeAreaInset 之后追加，才能盖住 tab bar 与 FAB
        // （modal 自带 bg-black/60 整屏 scrim + 贴底 sheet，视觉不改动）。
        .overlay {
            if overridePresenter.isPresented, let cfg = overridePresenter.config {
                S07cOverrideModal(
                    plan: cfg.plan,
                    allEvents: cfg.allEvents,
                    onGoWarmup: cfg.onGoWarmup,
                    onConfirmOverride: cfg.onConfirmOverride,
                    onCancel: { overridePresenter.dismiss() }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: overridePresenter.isPresented)
    }

    private var connectionState: ConnectionPillState {
        if midi.isConnected {
            // 文案锁定（visual-system §9 第 7 条）：真机连接 = "特伦斯 V70 已连接"。
            // 模拟源连接不冒充 V70（红线 2：无假数据），如实显示。
            return midi.mode == .simulated ? .simulatedConnected : .connected
        }
        return .disconnected
    }

    @ViewBuilder
    private var pageContent: some View {
        // 各 tab 内容页按批次实装；当前为框架占位（不含任何伪造数据）
        switch tab {
        case .today:
            TodayView(onBrowseLibrary: { tab = .library })
        case .library:
            LibraryView()
        case .practice:
            PracticeHubView(
                onBrowseLibrary: { tab = .library },
                onBrowseArchive: { tab = .archive }
            )
        case .archive:
            ArchiveView()
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - 连接胶囊

enum ConnectionPillState {
    /// 真机已连接（特伦斯 V70）
    case connected
    /// 模拟源已连接（不冒充 V70）
    case simulatedConnected
    case disconnected
}

private struct ConnectionPill: View {
    let state: ConnectionPillState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.labelMd)
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.canvas.opacity(0.85), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
    }

    private var dotColor: Color {
        switch state {
        case .connected, .simulatedConnected: Color.success
        case .disconnected: Color.danger
        }
    }

    private var label: String {
        switch state {
        case .connected: "特伦斯 V70 已连接"
        case .simulatedConnected: "模拟输入已连接"
        case .disconnected: "未连接"
        }
    }

    private var textColor: Color {
        switch state {
        case .connected, .simulatedConnected: Color.textBody
        case .disconnected: Color.textMuted
        }
    }
}

// MARK: - 问 Neko FAB

private struct NekoFAB: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "cat")
                    .font(.system(size: 18))
                Text("问 Neko")
                    .font(.titleMd)
            }
            .foregroundStyle(Color.amber)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.cardElevated, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.amber.opacity(0.18), lineWidth: 1))
            .shadow(color: Color.amber.opacity(0.15), radius: 12, y: 4) // 暖色底辉，不用冷色投影
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab Bar

private struct TabBar: View {
    @Binding var selected: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { t in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selected = t }
                } label: {
                    VStack(spacing: 3) {
                        // 激活态圆点：常驻占位避免切换时布局跳动
                        Circle()
                            .fill(selected == t ? Color.amber : .clear)
                            .frame(width: 4, height: 4)
                        Image(systemName: t.icon)
                            .font(.system(size: 24))
                            .foregroundStyle(selected == t ? Color.amber : Color.textMuted)
                        Text(t.title)
                            .font(.labelSm)
                            .foregroundStyle(selected == t ? Color.amber : Color.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(height: 56)
        .background(alignment: .top) {
            Rectangle().fill(Color.border).frame(height: 1) // 顶部 1px 发丝边
        }
        .background(Color.canvas.ignoresSafeArea(edges: .bottom))
    }
}

// MARK: - 通用小组件

/// 框架级 toast（P1 占位提示用，如 FAB）
struct ToastCapsule: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.bodyMd)
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.cardElevated, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.3), radius: 16, y: 4)
            .frame(maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
    }
}

/// M2 框架占位页：仅结构，不含伪造数据（红线 2）
struct TabPlaceholderPage: View {
    let title: String
    let note: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headlineLg)
                .foregroundStyle(Color.textPrimary)
            Text(note)
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AppFrameView()
        .preferredColorScheme(.dark)
}

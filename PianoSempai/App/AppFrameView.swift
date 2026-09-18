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

/// S06 App Frame：5 tab + 问 Neko FAB + 顶部连接胶囊。
/// 无 tab 栏页面的路由机制：全屏流程/弹层一律走 fullScreenCover / sheet（系统天然隐藏
/// tab bar），框架不做自定义路由栈；onboarding（S01–S05）、练习室（S11）、报告（S13）
/// 等后续批次均从本框架以 fullScreenCover 呈现。
struct AppFrameView: View {
    @ObservedObject private var midi = MIDIHub.shared
    @State private var tab: AppTab = .today
    @State private var nekoToastVisible = false

    var body: some View {
        ZStack(alignment: .top) {
            pageContent

            // 顶部连接胶囊（visual-system §6：右上线框胶囊）
            HStack {
                Spacer()
                ConnectionPill(state: connectionState)
                    .padding(.trailing, 20)
                    .padding(.top, 6)
            }

            if nekoToastVisible {
                ToastCapsule(text: "AI 助教将在后续版本开放")
            }
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                // 问 Neko FAB：独立悬浮于 tab 栏上方偏右（不进 5 tab）
                HStack {
                    Spacer()
                    NekoFAB { showNekoToast() }
                        .padding(.trailing, 20)
                        .padding(.bottom, 12)
                }
                TabBar(selected: $tab)
            }
            .background(Color.canvas.ignoresSafeArea(edges: .bottom))
        }
    }

    private var connectionState: ConnectionPillState {
        if midi.isConnected {
            // 文案锁定（visual-system §9 第 7 条）：真机连接 = "特伦斯 V70 已连接"。
            // 模拟源连接不冒充 V70（红线 2：无假数据），如实显示。
            return midi.mode == .simulated ? .simulatedConnected : .connected
        }
        return .disconnected
    }

    private var pageContent: some View {
        // 各 tab 内容页按批次实装；当前为框架占位（不含任何伪造数据）
        switch tab {
        case .today: TabPlaceholderPage(title: "今日", note: "今日任务 · 下一批次实装")
        case .library: TabPlaceholderPage(title: "曲库", note: "曲库 · 下一批次实装")
        case .practice: TabPlaceholderPage(title: "练习室", note: "练习室 · 下一批次实装")
        case .archive: TabPlaceholderPage(title: "档案", note: "练习档案 · 下一批次实装")
        case .settings: TabPlaceholderPage(title: "我的", note: "设置 · 下一批次实装")
        }
    }

    private func showNekoToast() {
        guard !nekoToastVisible else { return }
        withAnimation(.easeOut(duration: 0.2)) { nekoToastVisible = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.25)) { nekoToastVisible = false }
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

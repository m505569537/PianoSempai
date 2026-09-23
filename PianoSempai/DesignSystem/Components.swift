import SwiftUI

// 全局组件（visual-system §5 视觉规范；所有画布 spec 复用）。

// MARK: - 卡片

struct NocturneCard<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
    }
}

// MARK: - 按钮（visual-system §5：主/次/幽灵/危险）

/// 主按钮：琥珀填充 + 深色 bold 文字，高 50 全宽；pressed 亮到 amberBright；disabled 灰
struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled = true
    var cornerRadius: CGFloat = 12 // 底部固定 CTA 用 12；卡内用 8

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(isEnabled ? Color.canvas : Color.textMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(fill(isPressed: configuration.isPressed))
            )
    }

    private func fill(isPressed: Bool) -> Color {
        guard isEnabled else { return Color.borderInput }
        return isPressed ? Color.amberBright : Color.amber
    }
}

/// 次按钮：透明底 + 1px 琥珀 0.3 描边 + textBody；pressed 描边 0.7 + card 底
struct SecondaryButtonStyle: ButtonStyle {
    var isEnabled = true
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.titleMd)
            .foregroundStyle(isEnabled ? Color.textBody : Color.textMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(configuration.isPressed && isEnabled ? Color.card : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.amber.opacity(configuration.isPressed && isEnabled ? 0.7 : 0.3), lineWidth: 1)
            )
    }
}

/// 幽灵按钮：无底 textBody，pressed 变琥珀
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.titleMd)
            .foregroundStyle(configuration.isPressed ? Color.amber : Color.textBody)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Chip（筛选项/多选）

struct NocturneChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.bodyMd)
                .foregroundStyle(isSelected ? Color.canvas : Color.textBody)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? Color.amber : Color.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 卡内小动作按钮（次按钮的紧凑形态：描边胶囊，pressed 变琥珀）
// S19 笔记卡与 S22 月报观察卡（重试）共用
struct NoteActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.labelMd)
            .foregroundStyle(configuration.isPressed ? Color.amber : Color.textBody)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? Color.card : Color.clear, in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color.amber.opacity(configuration.isPressed ? 0.7 : 0.3), lineWidth: 1)
            )
    }
}

// MARK: - 三步指示器（S03 向导）

struct StepIndicator: View {
    /// 当前步（0-based）
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(dotColor(i))
                    .frame(width: 8, height: 8)
                    .shadow(color: i == current ? Color.amber.opacity(0.5) : .clear, radius: 4)
                if i < count - 1 {
                    Rectangle()
                        .fill(i < current ? Color.amber : Color.borderInput)
                        .frame(height: 2)
                }
            }
        }
    }

    private func dotColor(_ i: Int) -> Color {
        if i < current { return Color.amber }
        if i == current { return Color.amber }
        return Color.borderInput
    }
}

// MARK: - 暖色底部抽屉容器（S12/S13b 共用）
// 设计稿（visual-system §1 + S12「Sheet」）：暖色 scrim rgba(12,10,9,.6) 全屏压暗 +
// 顶部圆角 12 的 cardElevated 抽屉。系统 .sheet 默认压暗是中性冷材质（实测 rgb≈27,31,25 带绿味），
// 故用 presentationBackground(.clear) 去掉系统材质，自绘 scrim 与卡片。iOS 17+。

struct NocturneBottomDrawer<Content: View>: View {
    /// 点 scrim（抽屉外）是否关闭；默认关
    var dismissOnScrimTap: Bool = true
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            // 暖色压暗：铺满全屏；点它关闭抽屉（标准抽屉行为，也给用户一个明显的返回区）
            Color.scrim
                .ignoresSafeArea()
                .onTapGesture {
                    if dismissOnScrimTap { dismiss() }
                }

            // 抽屉卡：顶部圆角 12，底部贴边
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.cardElevated
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: 12, bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0, topTrailingRadius: 12,
                        style: .continuous))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationBackground(Color.clear)
    }
}

/// 抽屉顶部抓手条（S12/S13b 顶部 12pt，#3D3531 宽 36）
struct DrawerGrabHandle: View {
    var body: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.borderInput)
                .frame(width: 36, height: 4)
            Spacer()
        }
        .padding(.top, 12)
    }
}

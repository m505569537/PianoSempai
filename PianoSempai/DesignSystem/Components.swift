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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.titleMd)
            .foregroundStyle(isEnabled ? Color.textBody : Color.textMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isPressed && isEnabled ? Color.card : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
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

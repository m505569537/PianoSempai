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

/// S03 向导步骤条。真值 S03 code.html §2：
/// 已完成 = 16×16 圆（#262220 底 + 1pt 琥珀 40% 描边 + 11pt 对勾）；
/// 当前 = 10×10 实心琥珀点 + 16×16 扩散环（HTML `animate-ping`）；
/// 未到 = 8×8 #332D29 圆点。段间 20×1pt 发丝线（走过 = 琥珀 50%，未走 = #332D29）。
/// `titles` 为 nil 时退化为纯圆点形态（无标签步骤条）。
struct StepIndicator: View {
    /// 当前步（0-based）
    let current: Int
    let count: Int
    var titles: [String]? = nil

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                HStack(spacing: 6) {
                    marker(i)
                    if let titles, i < titles.count {
                        Text(titles[i])
                            .font(.labelSm)
                            .foregroundStyle(labelColor(i))
                    }
                }
                if i < count - 1 {
                    Rectangle()
                        .fill(i < current ? Color.amber.opacity(0.5) : Color.border)
                        .frame(width: 20, height: 1)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(_ i: Int) -> some View {
        switch i {
        case ..<current:
            ZStack {
                Circle().fill(Color.card)
                Circle().strokeBorder(Color.amber.opacity(0.4), lineWidth: 1)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.amber)
            }
            .frame(width: 16, height: 16)
        case current:
            CurrentStepDot()
        default:
            Circle()
                .fill(Color.border)
                .frame(width: 8, height: 8)
        }
    }

    private func labelColor(_ i: Int) -> Color {
        if i == current { return Color.amber }
        if i > current { return Color.textMuted.opacity(0.6) }
        return Color.textMuted
    }
}

/// 当前步圆点：10×10 实心琥珀 + 16×16 扩散环（真值 `animate-ping`，1.2s 一圈）
private struct CurrentStepDot: View {
    @State private var ping = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.amber.opacity(0.4), lineWidth: 1)
                .frame(width: 16, height: 16)
                .scaleEffect(ping ? 1.9 : 1)
                .opacity(ping ? 0 : 0.75)
            Circle()
                .fill(Color.amber)
                .frame(width: 10, height: 10)
        }
        .frame(width: 16, height: 16)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                ping = true
            }
        }
    }
}

// MARK: - 暖色底部抽屉容器（S12/S13b 共用）
// 设计稿（S13b code.html 三层遮罩 §z-10/z-20）：scrim 黑 60% + 2pt 背景模糊全屏压暗，
// 顶部两角圆角 28 的 #262220 抽屉，顶边 1pt #332D29，投影 0 -10px 40px rgba(0,0,0,.65)。
// 系统 .sheet 默认压暗是中性冷材质（实测 rgb≈27,31,25 带绿味），
// 故用 presentationBackground(.clear) 去掉系统材质，自绘 scrim 与卡片。iOS 17+。

struct NocturneBottomDrawer<Content: View>: View {
    /// 点 scrim（抽屉外）是否关闭；默认关
    var dismissOnScrimTap: Bool = true
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            // 压暗层（真值 z-10）：黑 60%。SwiftUI 没有 backdrop-filter，
            // .blur 只能糊本层（纯色层 → 视觉上等价于纯压暗），背景模糊要 UIVisualEffectView 才能做到。
            // 点它关闭抽屉（标准抽屉行为，也给用户一个明显的返回区）。
            Color.black.opacity(0.6)
                .blur(radius: 2)
                .ignoresSafeArea()
                .onTapGesture {
                    if dismissOnScrimTap { dismiss() }
                }

            // 抽屉卡：仅顶部两角圆角 28，底部贴边
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 28, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: 28,
                    style: .continuous)
                .fill(Color.card)
                .shadow(color: Color.black.opacity(0.65), radius: 20, x: 0, y: -10)
            )
            // 真值 border-t：1pt #332D29。用同一圆角形状裁切，线只落在顶部两角之间
            //（等同 CSS 对 rounded-t 元素画 border-top），不绕到贴边的左右/底边。
            .overlay(alignment: .top) {
                Color.border
                    .frame(height: 1)
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: 28, bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0, topTrailingRadius: 28,
                        style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationBackground(Color.clear)
    }
}

/// 抽屉顶部抓手条（S12/S13b 真值：居中 40×4pt 全圆角，#463F3A；条下留 10pt）
struct DrawerGrabHandle: View {
    var body: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.drawerHandle)
                .frame(width: 40, height: 4)
            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

// MARK: - 抽屉字面量色（DesignSystem token 未覆盖的真值 hex，仅本文件使用）

fileprivate extension Color {
    /// 抽屉抓手条 / home 指示条 #463F3A（S12/S13b 真值；token 无此色）
    static let drawerHandle = Color(red: 0x46 / 255, green: 0x3F / 255, blue: 0x3A / 255)
}

import SwiftUI

// MARK: - S12 段落循环设置（底部抽屉；校验走 LoopService，非法区间拒绝开始）
// 真值：docs/design-reference/screens/S12-loop-settings/code.html（id e326117680544db8897517772be93a57）。
// 结构：抓手 + 标题行 / 滚动三卡（选择小节 · 循环方式 · 每遍之间）/ 吸底双钮 1:2。
// 呈现保持 NocturneBottomDrawer（底部抽屉）：真值的整屏 vs 抽屉形态「待产品确认」，本屏不改外层。

struct S12LoopSettingsSheet: View {
    @ObservedObject var session: PracticeSession
    let totalMeasures: Int
    /// 真实曲名（PracticeRoomView.displayTitle）；空 = 无真实来源，右注只显小节数（不补占位）
    var pieceTitle: String = ""
    /// 当前曲目最近一次判分的错误热点小节（0-based；无数据 = 空数组 → chip 禁用）
    var hotspotMeasures: [Int] = []
    @Environment(\.dismiss) private var dismiss

    @State private var start: Int = 1
    @State private var end: Int = 8
    @State private var mode: LoopMode = .loop
    @State private var gapSec: Int = 3
    @State private var countIn: Bool = true
    @State private var initialized = false
    /// 快捷 chips 单选态（真值 §5.3：错误热点 / 当前段 / 全曲 / 手动，互斥）
    @State private var quick: QuickPick = .current

    private var rangeValid: Bool {
        LoopService.isValid(start: start, end: end, totalMeasures: totalMeasures)
    }

    var body: some View {
        NocturneBottomDrawer {
            DrawerGrabHandle()

            header
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 16) {
                    measureCard
                    modeCard
                    gapCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .padding(.bottom, 24)
            }
            // 真值页面底 surface #161311（三张卡之下的画布）
            .background(Color.s12Surface)
            // 顶部环境光（真值 §3）：320×192 圆，primary/5，blur-3xl，-top96 居中
            .overlay(alignment: .top) { ambientGlow }
            .clipped()

            footer
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            start = session.loopConfig.startMeasure
            end = session.loopConfig.endMeasure
            mode = session.loopConfig.mode
            gapSec = session.loopConfig.gapSec
            countIn = session.loopConfig.countIn
            // 打开即当前段（真值 §5.3 默认激活项），值与 loopConfig 一致
            quick = .current
        }
    }

    // MARK: 整体部件

    /// 顶部环境光（真值 §3）：320×192 圆，primary/5 = #F3BE67/5，blur-3xl，-top96 水平居中
    private var ambientGlow: some View {
        Circle()
            .fill(Color.s12Ambient)
            .frame(width: 320, height: 192)
            .blur(radius: 48)
            .offset(y: -96)
            .allowsHitTesting(false)
    }

    /// 标题行（真值 §4）：repeat 20pt primary + 「段落循环」serif 20 + 32×32 圆关闭钮
    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "repeat")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.s12Primary)
            Text("段落循环")
                .font(.headlineSm)
                .foregroundStyle(Color.s12OnSurface)
            Spacer(minLength: 12)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.s12OnSurfaceVariant)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(S12CloseButtonStyle())
        }
    }

    /// 吸底双钮（真值 §8）：取消 flex-1 / 开始 flex-[2]，即 1:2
    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.s12OutlineVariant25)
                .frame(height: 1)

            GeometryReader { proxy in
                let unit = max(0, (proxy.size.width - 8) / 3)
                HStack(spacing: 8) {
                    Button { dismiss() } label: {
                        Text("取消")
                            .font(.bodyMd)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.s12OnSurface)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(S12CancelButtonStyle())
                    .frame(width: unit)

                    Button { applyAndStart() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .medium))
                            Text(rangeValid ? "开始循环练习" : "区间无效")
                                .font(.bodyMd)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(Color.s12OnPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(S12StartButtonStyle(isEnabled: rangeValid))
                    .disabled(!rangeValid)
                    .frame(width: unit * 2)
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color.s12FooterBg)
    }

    // MARK: 卡1 选择小节

    /// 卡 1 右注文案（纯函数，可单测）：有真实曲名带「曲目：」，空串只显小节数（诚实，不补占位）
    static func rightCaption(pieceTitle: String, totalMeasures: Int) -> String {
        let total = max(1, totalMeasures)
        if pieceTitle.isEmpty { return "共 \(total) 小节" }
        return "曲目：\(pieceTitle) · 共 \(total) 小节"
    }

    private var measureCard: some View {
        s12Card {
            HStack(alignment: .firstTextBaseline) {
                Text("选择小节")
                    .font(.titleMd)
                    .foregroundStyle(Color.s12OnSurface)
                Spacer(minLength: 8)
                // 右侧标注只用真实数据：真实曲名（有则带）+ 总小节数（不写死条数）
                Text(Self.rightCaption(pieceTitle: pieceTitle, totalMeasures: totalMeasures))
                    .font(.labelSm)
                    .foregroundStyle(Color.s12OnSurfaceVariant)
            }

            HStack(spacing: 8) {
                measureCell("起点小节", value: $start, min: 1, max: end - 1)
                measureCell("终点小节", value: $end, min: start + 1, max: max(1, totalMeasures))
            }
            .padding(.top, 16)

            measureStrip.padding(.top, 16)

            quickChips.padding(.top, 12)
        }
    }

    /// 起/终点步进格（真值 §5.1）：2 列 gap8；格底 surface-container-low、圆角 4、p8
    private func measureCell(_ label: String, value: Binding<Int>, min minValue: Int, max maxValue: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.labelSm)
                .foregroundStyle(Color.s12OnSurfaceVariant)
            HStack(spacing: 4) {
                stepButton("minus", enabled: value.wrappedValue > minValue) {
                    value.wrappedValue = max(minValue, value.wrappedValue - 1)
                    quick = .manual
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(value.wrappedValue)")
                        .font(.headlineSm)
                        .foregroundStyle(Color.s12OnSurface)
                        .monospacedDigit()
                    Text("小节")
                        .font(.labelSm)
                        .foregroundStyle(Color.s12OnSurfaceVariant)
                }
                Spacer(minLength: 0)
                stepButton("plus", enabled: value.wrappedValue < maxValue) {
                    value.wrappedValue = min(maxValue, value.wrappedValue + 1)
                    quick = .manual
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.s12ContainerLow, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.s12OutlineVariant30, lineWidth: 1)
        )
    }

    /// 微型时间线（真值 §5.2）：totalMeasures 等分列、列等高；选中段 primary-container。
    /// 不画假波形高度，也不画 21 号错误圆点（无真实逐小节热点来源）。
    private var measureStrip: some View {
        let total = max(1, totalMeasures)
        let selectedCount = max(0, end - start + 1)
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("第 1 小节")
                    .font(.labelSm)
                    .foregroundStyle(Color.s12Annotation)
                Spacer(minLength: 4)
                Text(rangeValid ? "\(start)–\(end) 选中 (\(selectedCount)小节)" : "区间无效")
                    .font(.labelSm)
                    .foregroundStyle(rangeValid ? Color.s12PrimaryContainer : Color.s12Error)
                Spacer(minLength: 4)
                Text("第 \(total) 小节")
                    .font(.labelSm)
                    .foregroundStyle(Color.s12Annotation)
            }

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(1...total, id: \.self) { m in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(m >= start && m <= end ? Color.s12PrimaryContainer : Color.s12ContainerHighest60)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                }
            }
            .padding(4)
            // 列底对齐（真值 items-end）：20pt 等高柱贴在条带底部
            .frame(height: 32, alignment: .bottom)
            .background(Color.s12ContainerLowest, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.s12OutlineVariant25, lineWidth: 1)
            )
        }
    }

    /// 快捷 chips（真值 §5.3）：单选互斥。错误热点仅在能解析出合法区间时可用（数据由外部传入）
    private var quickChips: some View {
        HStack(spacing: 4) {
            ForEach(QuickPick.allCases, id: \.self) { pick in
                quickChip(pick)
            }
        }
    }

    private func quickChip(_ pick: QuickPick) -> some View {
        let selected = quick == pick
        // 是否可用由实例数据决定：错误热点看传入的 hotspotMeasures 能否解析出合法区间（G2），
        // 其余 chips 恒有真实来源。无数据保持 opacity 0.4 + disabled（不造假徽标/圆点）
        let enabled: Bool = {
            guard pick == .hotspot else { return true }
            return LoopService.hotspotRange(hotspotMeasures: hotspotMeasures, totalMeasures: totalMeasures) != nil
        }()
        return Button {
            quick = pick
            applyQuick(pick)
        } label: {
            HStack(spacing: 4) {
                if let icon = pick.icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(pick.title)
                    .font(.labelMd)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selected ? Color.s12Primary : Color.s12OnSurfaceVariant)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                selected ? Color.s12PrimaryContainer15 : Color.s12ContainerLow,
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(selected ? Color.s12PrimaryContainer : Color.s12OutlineVariant40, lineWidth: 1)
            )
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// 快捷 chips 的真实行为：全曲 / 当前段 / 错误热点（有数据时）有据可依；手动只标记用户驱动
    private func applyQuick(_ pick: QuickPick) {
        let total = max(1, totalMeasures)
        // 总小节不足 2 时不存在合法区间，保持现值（CTA 会诚实禁用）
        guard total >= 2 else { return }
        let seeded: (start: Int, end: Int)
        switch pick {
        case .all:
            seeded = (1, total)
        case .current:
            seeded = (session.loopConfig.startMeasure, session.loopConfig.endMeasure)
        case .hotspot:
            // 无数据（解析不出区间）不动现值；chip 本身已被禁用，这里是双保险
            guard let range = LoopService.hotspotRange(hotspotMeasures: hotspotMeasures, totalMeasures: total) else { return }
            seeded = (range.start, range.end)
        case .manual:
            return
        }
        let clamped = LoopService.clamped(start: seeded.start, end: seeded.end, totalMeasures: total)
        start = clamped.start
        end = clamped.end
    }

    // MARK: 卡2 循环方式

    private var modeCard: some View {
        s12Card {
            Text("循环方式")
                .font(.titleMd)
                .foregroundStyle(Color.s12OnSurface)

            VStack(spacing: 4) {
                modeRow(.loop, title: "逐遍循环（默认）", note: "原速稳定练习")
                modeRow(.adaptiveUp, title: "每遍提速 +5 BPM", note: "渐进肌肉记忆")
                modeRow(.adaptiveDown, title: "崩了自动 −5 BPM 重来", note: "智能降级缓冲")
            }
            .padding(.top, 8)

            // 常驻提示（真值 §6）：不随选项折叠；adaptiveDown 的行为仍在 LoopService
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.s12Primary)
                Text("连崩 2 遍自动暂停，Neko 会建议降速或分手")
                    .font(.bodySm)
                    .foregroundStyle(Color.s12OnSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.s12OutlineVariant20)
                    .frame(height: 1)
            }
        }
    }

    private func modeRow(_ tag: LoopMode, title: String, note: String) -> some View {
        let selected = mode == tag
        return Button { mode = tag } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(selected ? Color.s12Primary : Color.s12OutlineVariant80, lineWidth: 1)
                        .frame(width: 16, height: 16)
                    Circle()
                        .fill(Color.s12Primary)
                        .frame(width: 8, height: 8)
                        .opacity(selected ? 1 : 0)
                }
                Text(title)
                    .font(.bodyMd)
                    .fontWeight(selected ? .medium : .regular)
                    .foregroundStyle(selected ? Color.s12OnSurface : Color.s12OnSurfaceVariant)
                Spacer(minLength: 8)
                Text(note)
                    .font(.labelSm)
                    .foregroundStyle(Color.s12Outline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? Color.s12ContainerLow : Color.s12ContainerLow60,
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(selected ? Color.s12PrimaryContainer60 : Color.s12OutlineVariant30, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 卡3 每遍之间

    private var gapCard: some View {
        s12Card {
            Text("每遍之间")
                .font(.titleMd)
                .foregroundStyle(Color.s12OnSurface)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.s12Outline)
                    Text("间隔准备时间")
                        .font(.bodyMd)
                        .foregroundStyle(Color.s12OnSurface)
                    Spacer(minLength: 8)
                    gapStepper
                }
                .padding(.top, 8)
                .padding(.bottom, 8)

                Rectangle()
                    .fill(Color.s12OutlineVariant20)
                    .frame(height: 1)

                HStack(spacing: 8) {
                    Image(systemName: "metronome")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.s12Outline)
                    Text("节拍器预备拍 1 小节")
                        .font(.bodyMd)
                        .foregroundStyle(Color.s12OnSurface)
                    Spacer(minLength: 8)
                    countInToggle
                }
                .padding(.top, 8)
            }
            .padding(.top, 8)
        }
    }

    /// 间隔秒数步进器（真值 §7.1）：值 14pt medium，min-w56 居中
    private var gapStepper: some View {
        HStack(spacing: 4) {
            stepButton("minus", enabled: gapSec > 1) { gapSec = max(1, gapSec - 1) }
            Text("\(gapSec) 秒")
                .font(.bodyMd)
                .fontWeight(.medium)
                .foregroundStyle(Color.s12OnSurface)
                .monospacedDigit()
                .frame(minWidth: 56)
            stepButton("plus", enabled: gapSec < 10) { gapSec = min(10, gapSec + 1) }
        }
        .padding(4)
        .background(Color.s12ContainerLow, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.s12OutlineVariant30, lineWidth: 1)
        )
    }

    /// 节拍器预备拍开关（真值 §7.2）：48×24 全圆角，ON primary-container，旋钮 #100E0C + 6pt primary 点
    private var countInToggle: some View {
        Button { countIn.toggle() } label: {
            ZStack(alignment: countIn ? .trailing : .leading) {
                Capsule()
                    .fill(countIn ? Color.s12PrimaryContainer : Color.s12ContainerHighest60)
                Circle()
                    .fill(Color.s12ContainerLowest)
                    .frame(width: 20, height: 20)
                    .padding(2)
                    .overlay(
                        Circle()
                            .fill(Color.s12Primary)
                            .frame(width: 6, height: 6)
                    )
            }
            .frame(width: 48, height: 24)
            .animation(.easeInOut(duration: 0.16), value: countIn)
        }
        .buttonStyle(.plain)
        .accessibilityValue(countIn ? "开" : "关")
    }

    // MARK: 共用小件

    /// −/＋ 钮（真值 §5.1/§7.1）：28×28、圆角 2、surface-container-high 底、1pt outline-variant/20、字形 16pt
    private func stepButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.s12OnSurface)
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
        .buttonStyle(S12StepButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    /// 卡片外壳（真值 §5/§6/§7）：surface-container 底、圆角 8、1pt outline-variant/30、p16、顶边内高光
    private func s12Card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.s12Container, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.s12OutlineVariant30, lineWidth: 1)
        )
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [.clear, .white.opacity(0.05), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .allowsHitTesting(false)
        }
    }

    private func applyAndStart() {
        guard rangeValid else { return }
        session.loopConfig = LoopConfig(
            startMeasure: start,
            endMeasure: end,
            mode: mode,
            gapSec: gapSec,
            countIn: countIn
        )
        // TODO(P2)：错误计数接 M5 完整对齐判分；当前按简单匹配错音口径（brief 授权）
        dismiss()
    }
}

// MARK: - 快捷 chips 单选枚举（真值 §5.3 顺序：错误热点 / 当前段 / 全曲 / 手动）

private enum QuickPick: String, CaseIterable {
    case hotspot, current, all, manual

    var title: String {
        switch self {
        case .hotspot: return "错误热点"
        case .current: return "当前段"
        case .all: return "全曲"
        case .manual: return "手动"
        }
    }

    /// 错误热点的 filled error 图标（真值 §5.3）
    var icon: String? {
        switch self {
        case .hotspot: return "exclamationmark.circle.fill"
        default: return nil
        }
    }

    // G2：chip 是否可用不再写死在枚举里（原来 hasRealSource 恒 false for .hotspot），
    // 改由视图层按传入的 hotspotMeasures 计算（见 quickChip）。
}

// MARK: - 底部双钮样式（真值 §8）

/// 取消钮：透明底 + 1pt outline-variant/60，按下填 surface-container
private struct S12CancelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Color.s12Container : Color.clear,
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.s12OutlineVariant60, lineWidth: 1)
            )
    }
}

/// 开始钮：primary-container 底，按下变 primary；禁用时整体淡出（真值未画禁用态）
private struct S12StartButtonStyle: ButtonStyle {
    var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(configuration.isPressed && isEnabled ? Color.s12Primary : Color.s12PrimaryContainer)
            )
    }
}

/// 关闭钮：32×32 圆热区，按下填 surface-container（真值 hover 态）
private struct S12CloseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Color.s12Container : Color.clear,
                in: Circle()
            )
    }
}

/// −/＋ 钮：surface-container-high 底，按下变 surface-bright（真值 hover 态）+ 1pt outline-variant/20
private struct S12StepButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Color.s12SurfaceBright : Color.s12ContainerHigh,
                in: RoundedRectangle(cornerRadius: 2, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Color.s12OutlineVariant20, lineWidth: 1)
            )
    }
}

// MARK: - S12 真值字面量色（Stitch config 的 Material3 token；全局 DesignSystem token 未覆盖，仅本文件使用）

fileprivate extension Color {
    /// hex → sRGB（S12 真值局部色专用）
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    // 表面族（truth surface-*）
    /// surface #161311 页面底 / 滚动画布（真值 config background、surface）
    static let s12Surface = Color(hex: 0x161311)
    /// surface-container #221F1D 三张卡底
    static let s12Container = Color(hex: 0x221F1D)
    /// surface-container-low #1E1B19 步进格 / 单选行底 / chip 底
    static let s12ContainerLow = Color(hex: 0x1E1B19)
    /// surface-container-low/60 未选中单选行底
    static let s12ContainerLow60 = Color(hex: 0x1E1B19, opacity: 0.6)
    /// surface-container-lowest #100E0C 时间线条带底、开关旋钮
    static let s12ContainerLowest = Color(hex: 0x100E0C)
    /// surface-container-high #2D2927 −/＋ 钮底
    static let s12ContainerHigh = Color(hex: 0x2D2927)
    /// surface-bright #3C3836 −/＋ 钮按下底（真值 hover 态）
    static let s12SurfaceBright = Color(hex: 0x3C3836)
    /// surface-container-highest/60 时间线未选列、开关 OFF 轨
    static let s12ContainerHighest60 = Color(hex: 0x383432, opacity: 0.6)
    /// footer 底 surface-container-low/95（真值另有 backdrop-blur-md，静态吸底无内容可糊）
    static let s12FooterBg = Color(hex: 0x1E1B19, opacity: 0.95)
    /// 顶部环境光 primary/5
    static let s12Ambient = Color(hex: 0xF3BE67, opacity: 0.05)

    // 主色族
    /// primary #F3BE67 标题图标、单选选中、chip 激活字、pets 图标、开关中心点
    static let s12Primary = Color(hex: 0xF3BE67)
    /// primary-container #D4A24E 时间线选中列、选中边框/60、开关 ON、主 CTA、选中 chip 描边
    static let s12PrimaryContainer = Color(hex: 0xD4A24E)
    /// primary-container/15 选中 chip 底
    static let s12PrimaryContainer15 = Color(hex: 0xD4A24E, opacity: 0.15)
    /// primary-container/60 选中单选行边框
    static let s12PrimaryContainer60 = Color(hex: 0xD4A24E, opacity: 0.6)
    /// on-primary #432C00 主 CTA 字色
    static let s12OnPrimary = Color(hex: 0x432C00)

    // 文字族
    /// on-surface #E9E1DD 主文字、取消钮
    static let s12OnSurface = Color(hex: 0xE9E1DD)
    /// on-surface-variant #D3C4B2 次级文字、close 图标
    static let s12OnSurfaceVariant = Color(hex: 0xD3C4B2)
    /// on-surface-variant/70 时间线标注行两端
    static let s12Annotation = Color(hex: 0xD3C4B2, opacity: 0.7)
    /// outline #9C8F7E 说明 / 右注 / 卡3 图标
    static let s12Outline = Color(hex: 0x9C8F7E)

    // 边框族（outline-variant #4F4537 各透明度）
    /// outline-variant/20 −/＋ 钮描边、卡内分隔线、常驻提示顶线
    static let s12OutlineVariant20 = Color(hex: 0x4F4537, opacity: 0.2)
    /// outline-variant/25 时间线条带描边、footer 顶线
    static let s12OutlineVariant25 = Color(hex: 0x4F4537, opacity: 0.25)
    /// outline-variant/30 卡片描边、步进格描边
    static let s12OutlineVariant30 = Color(hex: 0x4F4537, opacity: 0.3)
    /// outline-variant/40 未选中 chip 描边
    static let s12OutlineVariant40 = Color(hex: 0x4F4537, opacity: 0.4)
    /// outline-variant/60 取消钮描边
    static let s12OutlineVariant60 = Color(hex: 0x4F4537, opacity: 0.6)
    /// outline-variant/80 未选中 radio 环
    static let s12OutlineVariant80 = Color(hex: 0x4F4537, opacity: 0.8)

    // 错误族（仅「错误热点」禁用 chip 图标与区间无效文案；无热点数据，不画 21 号假圆点）
    /// error #FFB4AB
    static let s12Error = Color(hex: 0xFFB4AB)
}

import SwiftUI

// MARK: - S01 欢迎（全屏流程，无 tab；文案逐字按 S01 spec）

/// 真值 code.html 里有、但共享 DesignSystem 还没有对应 token 的色值。
/// 只在本文件使用，不污染 Color+Nocturne / Assets.xcassets。
fileprivate extension Color {
    /// 主琥珀 #D4A24E 的亮变体（真值 primary）：特性卡图标
    static let s01AmberLight = Color(red: 0xF3 / 255, green: 0xBE / 255, blue: 0x67 / 255)
    /// surface-container #221F1D：特性卡底
    static let s01CardFill = Color(red: 0x22 / 255, green: 0x1F / 255, blue: 0x1D / 255)
    /// outline-variant #4F4537：特性卡描边 + mono 注记
    static let s01OutlineVariant = Color(red: 0x4F / 255, green: 0x45 / 255, blue: 0x37 / 255)
    /// surface-container-high #2D2927：图标盒底
    static let s01IconBox = Color(red: 0x2D / 255, green: 0x29 / 255, blue: 0x27 / 255)
    /// surface-container-lowest #100E0C：CTA 文字
    static let s01OnPrimary = Color(red: 0x10 / 255, green: 0x0E / 255, blue: 0x0C / 255)
    /// on-surface #E9E1DD：特性卡主行
    static let s01OnSurface = Color(red: 0xE9 / 255, green: 0xE1 / 255, blue: 0xDD / 255)
}

struct S01WelcomeView: View {
    let onStart: () -> Void
    @State private var breathing = false

    var body: some View {
        ZStack {
            // §1 环境光层：非交互，垫在内容之下
            ambientBackdrop
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()
                    .frame(maxHeight: .infinity)

                // §2 徽标：96pt 外发光容器，内嵌 ~80pt 琥珀线稿（猫脸轮廓 + 钢琴黑白键，纯描边）
                ZStack {
                    Circle()
                        .fill(Color.amber.opacity(0.10))
                        .blur(radius: 6)
                    WelcomeBadge()
                        .frame(width: 80, height: 80)
                        .shadow(color: Color.amber.opacity(0.35), radius: 8, y: 4)
                }
                .frame(width: 96, height: 96)
                .opacity(breathing ? 1.0 : 0.85)
                .onAppear {
                    withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                        breathing = true
                    }
                }

                Text("PianoSempai")
                    .font(.displayLg)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.top, 16)

                Text("你的钢琴前辈，住在手机里")
                    .font(.bodyLg)
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 6)

                VStack {
                    // §3 三张独立特性卡（取代原分组盒 + 分隔线）
                    // 真值 px-1：卡片相对 20pt 屏幕边距再各缩 4
                    VStack(spacing: 8) {
                        featureCard(icon: "waveform", text: "只听 MIDI，不乱猜", note: "SIGNAL")
                        featureCard(icon: "book", text: "课程锚定拜厄·哈农·车尔尼", note: "OPUS")
                        featureCard(icon: "lock", text: "数据只在你手机里", note: "LOCAL")
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.top, 32)
                .padding(.horizontal, 20)

                Spacer()
                    .frame(maxHeight: .infinity)

                // §4 CTA
                Button(action: onStart) {
                    HStack(spacing: 8) {
                        Text("开始")
                            .font(.system(size: 17, weight: .bold))
                            .kerning(1.7) // +0.1em @17pt
                        Image(systemName: "arrow.right")
                            .font(.system(size: 20, weight: .bold))
                    }
                }
                .buttonStyle(WelcomeCTAButtonStyle())
                .padding(.horizontal, 20)

                // §5 免责声明 + 版本行
                Text("继续即表示同意：视频只在你主动录制时工作，\n手型建议永不决定过关")
                    .font(.system(size: 11))
                    .leading(18, fontSize: 11)
                    .foregroundStyle(Color.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

                Text("v\(appVersion) · 纯自用，无账号，无服务器")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 8)
            }
        }
        // 真值 bg-surface #161311（Assets 里 #161311 是 surface token，canvas 是 #1C1917）
        .background(Color.surface)
    }

    // MARK: - §1 环境光

    /// 琥珀晕 + 顶部辉光。真值的状态栏 / 灵动岛 / home indicator 是网页模拟的 OS chrome，
    /// iOS 上由系统提供，这里一律不画。
    private var ambientBackdrop: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // 全屏琥珀晕：中心 (50%, 32%)，~70% 半径处衰减到透明
                RadialGradient(
                    colors: [Color.amber.opacity(0.12), Color.amber.opacity(0)],
                    center: UnitPoint(x: 0.5, y: 0.32),
                    startRadius: 0,
                    endRadius: Self.bloomEndRadius(in: geo.size)
                )
                // 顶部辉光：288pt 圆、水平居中、顶 −64pt、10% 琥珀、64pt 模糊
                Circle()
                    .fill(Color.amber.opacity(0.10))
                    .frame(width: 288, height: 288)
                    .blur(radius: 64)
                    .offset(y: -64)
            }
        }
        .allowsHitTesting(false)
    }

    /// CSS radial-gradient 默认半径是最远角距离，70% 处已衰减到透明
    private static func bloomEndRadius(in size: CGSize) -> CGFloat {
        let dx = size.width * 0.5
        let dy = size.height * 0.68
        return (dx * dx + dy * dy).squareRoot() * 0.7
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    // MARK: - §3 特性卡

    /// 单张特性卡：纯展示，无点击、无按压态
    private func featureCard(icon: String, text: String, note: String) -> some View {
        HStack(spacing: 14) {
            // 32×32 图标盒：r2、#2D2927 底、琥珀 20% 描边
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.s01IconBox)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.amber.opacity(0.20), lineWidth: 1)
                )
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 19))
                        .foregroundStyle(Color.s01AmberLight)
                }

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.s01OnSurface)

            Spacer(minLength: 8)

            Text(note)
                .font(.labelMono(11))
                .kerning(0.55) // +0.05em @11pt
                .foregroundStyle(Color.s01OutlineVariant)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(cardBackground)
    }

    /// 卡片底：#221F1D/60 填充、r4、#4F4537/30 1pt 描边、顶部 1pt 白色高光
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.s01CardFill.opacity(0.60))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.s01OutlineVariant.opacity(0.30), lineWidth: 1)
            }
    }
}

/// §4 CTA 专用样式：#D4A24E 底 / #100E0C 字 / r8 / 琥珀投影 / 按压 0.985。
/// 只服务本屏，共享 PrimaryButtonStyle 不改动。
private struct WelcomeCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.s01OnPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.amber, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: Color.amber.opacity(0.22), radius: 24, y: 4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.175), value: configuration.isPressed)
    }
}

/// 徽标：圆内猫耳 + 琴键条（纯描边琥珀，线宽按 80pt 渲染等比调过，外轮廓 ≈1.4pt）
private struct WelcomeBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.amber, lineWidth: 1.4)
            // 猫耳
            EarShape()
                .stroke(Color.amber, lineWidth: 1.4)
                .padding(5)
            // 内嵌钢琴键：三黑键两白键分隔
            VStack(spacing: 0) {
                Spacer()
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        Rectangle()
                            .strokeBorder(Color.amber, lineWidth: 0.8)
                            .frame(width: 6.2, height: 16)
                            .overlay(alignment: .topTrailing) {
                                if [1, 3, 5].contains(i) {
                                    Rectangle()
                                        .fill(Color.amber)
                                        .frame(width: 3, height: 9)
                                        .offset(x: -1.5)
                                }
                            }
                    }
                }
                .padding(.bottom, 11)
            }
        }
    }

    private struct EarShape: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            let w = rect.width
            p.move(to: CGPoint(x: w * 0.12, y: rect.height * 0.32))
            p.addLine(to: CGPoint(x: w * 0.10, y: rect.height * 0.02))
            p.addLine(to: CGPoint(x: w * 0.34, y: rect.height * 0.14))
            p.move(to: CGPoint(x: w * 0.88, y: rect.height * 0.32))
            p.addLine(to: CGPoint(x: w * 0.90, y: rect.height * 0.02))
            p.addLine(to: CGPoint(x: w * 0.66, y: rect.height * 0.14))
            return p
        }
    }
}

#Preview {
    S01WelcomeView(onStart: {})
}

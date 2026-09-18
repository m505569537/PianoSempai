import SwiftUI

// MARK: - S01 欢迎（全屏流程，无 tab；文案逐字按 S01 spec）

struct S01WelcomeView: View {
    let onStart: () -> Void
    @State private var breathing = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(maxHeight: .infinity)

            // 琥珀线稿徽标：猫脸轮廓内嵌钢琴黑白键（描边，不填充）
            WelcomeBadge()
                .frame(width: 130, height: 130)
                .opacity(breathing ? 1.0 : 0.85)
                .shadow(color: Color.amber.opacity(0.2), radius: 30)
                .onAppear {
                    withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                        breathing = true
                    }
                }

            Text("PianoSempai")
                .font(.displayLg)
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 28)

            Text("你的钢琴前辈，住在手机里")
                .font(.bodyLg)
                .foregroundStyle(Color.textMuted)
                .padding(.top, 6)

            VStack(spacing: 0) {
                featureRow(icon: "waveform", text: "只听 MIDI，不乱猜", note: "SIGNAL")
                Divider().overlay(Color.border)
                featureRow(icon: "book", text: "课程锚定拜厄·哈农·车尔尼", note: "OPUS")
                Divider().overlay(Color.border)
                featureRow(icon: "iphone.gen2", text: "数据只在你手机里", note: "LOCAL")
            }
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 8))
            .padding(.top, 36)
            .padding(.horizontal, 20)

            Spacer()
                .frame(maxHeight: .infinity)

            Button(action: onStart) {
                HStack(spacing: 6) {
                    Text("开始")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 20)

            Text("继续即表示同意：视频只在你主动录制时工作，\n手型建议永不决定过关")
                .font(.system(size: 11))
                .leading(16, fontSize: 11)
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
        .background(Color.canvas)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private func featureRow(icon: String, text: String, note: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(Color.amber)
                .frame(width: 32)
            Text(text)
                .font(.bodyMd)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(note)
                .font(.labelSm)
                .kerning(0.8)
                .foregroundStyle(Color.textMuted)
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
    }
}

/// 徽标：圆内猫耳 + 琴键条（纯描边琥珀）
private struct WelcomeBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.amber, lineWidth: 2)
            // 猫耳
            EarShape()
                .stroke(Color.amber, lineWidth: 2)
                .padding(8)
            // 内嵌钢琴键：三黑键两白键分隔
            VStack(spacing: 0) {
                Spacer()
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        Rectangle()
                            .strokeBorder(Color.amber, lineWidth: 1)
                            .frame(width: 10, height: 26)
                            .overlay(alignment: .topTrailing) {
                                if [1, 3, 5].contains(i) {
                                    Rectangle()
                                        .fill(Color.amber)
                                        .frame(width: 5, height: 15)
                                        .offset(x: -2.5)
                                }
                            }
                    }
                }
                .padding(.bottom, 18)
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

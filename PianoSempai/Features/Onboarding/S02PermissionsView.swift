import CoreBluetooth
import SwiftUI
import UserNotifications

// MARK: - 权限管理（真实系统授权；相机/麦克风只展示不请求）

@MainActor
final class PermissionCenter: ObservableObject {
    enum BluetoothState {
        case unknown, granted, denied, disabled
    }

    enum NotificationState {
        case unknown, granted, denied
    }

    @Published var bluetooth: BluetoothState = .unknown
    @Published var notification: NotificationState = .unknown

    /// CBCentralManagerDelegate 非 MainActor，桥接跳回主线程
    private let bridge = BluetoothDelegateBridge()
    private var central: CBCentralManager?

    init() {
        bridge.onState = { [weak self] state in
            Task { @MainActor in
                self?.bluetooth = state
            }
        }
        refresh()
    }

    /// 请求蓝牙授权（创建 CBCentralManager 即触发系统弹窗）
    func requestBluetooth() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: bridge, queue: nil)
    }

    /// 请求通知授权
    func requestNotification() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.notification = granted ? .granted : .denied
            }
        }
    }

    /// 读取当前状态（不触发弹窗）
    func refresh() {
        switch CBManager.authorization {
        case .allowedAlways: bluetooth = .granted
        case .denied, .restricted: bluetooth = .denied
        case .notDetermined: bluetooth = .unknown
        @unknown default: bluetooth = .unknown
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral: self.notification = .granted
                case .denied: self.notification = .denied
                case .notDetermined: self.notification = .unknown
                @unknown default: self.notification = .unknown
                }
            }
        }
    }
}

final class BluetoothDelegateBridge: NSObject, CBCentralManagerDelegate {
    var onState: ((PermissionCenter.BluetoothState) -> Void)?

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: onState?(.granted)
        case .poweredOff: onState?(.disabled)
        case .unauthorized: onState?(.denied)
        case .unknown, .resetting: break
        default: break
        }
    }
}

// MARK: - S02 屏内私有色（真值 §5 中未进全局 token 的内联色；不写 Assets、不动全局 token）

fileprivate extension Color {
    /// hex → sRGB（S02 真值局部色专用）
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// 安全说明卡底（真值 #201D1A）
    static let s02SafetyBg = Color(hex: 0x201D1A)
    /// 安全说明卡描边（真值 #2D2825）
    static let s02SafetyBorder = Color(hex: 0x2D2825)
    /// 次按钮底：稍后再说 / 允许通知（真值 #2E2926）
    static let s02ButtonFill = Color(hex: 0x2E2926)
    /// 「稍后再说」描边（真值 #3A332F；不用琥珀描边）
    static let s02ButtonBorder = Color(hex: 0x3A332F)
    /// CTA 按压态（真值 amberHover #C2913E）
    static let s02CTAHover = Color(hex: 0xC2913E)
}

// MARK: - S02 屏内私有枚举 / 样式

/// 语义 chip 着色（真值 §3）：琥珀 chip 描边 25%，绿色仅表示蓝牙已授权、描边 30%
fileprivate enum S02ChipTone {
    case amber, green

    var text: Color {
        switch self {
        case .amber: Color.amber
        case .green: Color.success
        }
    }

    var background: Color {
        switch self {
        case .amber: Color.amber.opacity(0.15)
        case .green: Color.success.opacity(0.15)
        }
    }

    var border: Color {
        switch self {
        case .amber: Color.amber.opacity(0.25)
        case .green: Color.success.opacity(0.30)
        }
    }
}

/// 图标盒配色（真值 §3）：卡 1 琥珀 15%/30%；卡 2、卡 3 用 #332D29 单色
fileprivate enum S02IconTint {
    case accent, neutral

    var glyph: Color { Color.amber }

    var background: Color {
        switch self {
        case .accent: Color.amber.opacity(0.15)
        case .neutral: Color.border
        }
    }

    var border: Color {
        switch self {
        case .accent: Color.amber.opacity(0.30)
        case .neutral: Color.border
        }
    }
}

/// 卡内操作按钮的三种真值样式（真值 §3）
fileprivate enum S02CardActionStyle {
    /// 去授权：琥珀填充 + 深色 semibold，无描边
    case grant
    /// 稍后再说：#2E2926 底 + #9C948B 字 + #3A332F 描边
    case later
    /// 允许通知：#2E2926 底 + #F5F2ED 字 + #332D29 描边，按压描边转琥珀 40%
    case notify

    var fill: Color {
        switch self {
        case .grant: Color.amber
        case .later, .notify: Color.s02ButtonFill
        }
    }

    var text: Color {
        switch self {
        case .grant: Color.canvas
        case .later: Color.textMuted
        case .notify: Color.textPrimary
        }
    }

    var weight: Font.Weight {
        switch self {
        case .grant: .semibold
        case .later, .notify: .medium
        }
    }

    var hPadding: CGFloat {
        switch self {
        case .grant: 14
        case .later, .notify: 12
        }
    }

    /// 常态描边（nil = 不描边）
    var border: Color? {
        switch self {
        case .grant: nil
        case .later: Color.s02ButtonBorder
        case .notify: Color.border
        }
    }

    /// 按压态描边（nil = 不随按压变化）
    var pressedBorder: Color? {
        switch self {
        case .notify: Color.amber.opacity(0.4)
        case .grant, .later: nil
        }
    }

    /// 当前应画的描边色
    func stroke(isPressed: Bool) -> Color {
        if isPressed, let pressed = pressedBorder { return pressed }
        return border ?? .clear
    }
}

/// 按压态环境键：ButtonStyle 把 isPressed 写进来，供按钮label 换描边色
fileprivate struct S02ActionPressedKey: EnvironmentKey {
    static let defaultValue = false
}

fileprivate extension EnvironmentValues {
    var s02ActionPressed: Bool {
        get { self[S02ActionPressedKey.self] }
        set { self[S02ActionPressedKey.self] = newValue }
    }
}

/// 卡内操作按钮：视觉 13pt / 圆角 8 / py6；真值视觉高约 26pt，
/// 用透明 ZStack 把热区补到 ≥44pt（真值 §3 卡 1 注释要求）。
/// `action == nil` 时只画样式不挂交互（相机卡：本屏从不请求相机/麦克风）。
fileprivate struct S02CardActionButton: View {
    let title: String
    let style: S02CardActionStyle
    var action: (() -> Void)?

    @Environment(\.s02ActionPressed) private var isPressed

    var body: some View {
        if let action {
            Button(action: action) {
                ZStack {
                    Color.clear
                    pill
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(S02CardActionButtonStyle())
        } else {
            pill
        }
    }

    private var pill: some View {
        Text(title)
            .font(.system(size: 13, weight: style.weight))
            .foregroundStyle(style.text)
            .padding(.horizontal, style.hPadding)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(style.fill))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style.stroke(isPressed: isPressed), lineWidth: 1)
            )
    }
}

/// 卡内按钮：pressed 缩放 .95，并把按压态注入环境
fileprivate struct S02CardActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.s02ActionPressed, configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 底部 CTA（真值 §4）：全宽 h48 / 圆角 12 / 琥珀底 / #1C1917 15pt bold + 16pt 箭头；
/// 按压 #C2913E + scale .98。蓝牙未决时不禁用（真值 §6：进 S03 后再引导）。
fileprivate struct S02CTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.canvas)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isPressed ? Color.s02CTAHover : Color.amber)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - S02 权限页（文案逐字按 S02 spec；视觉按 S02-permissions/code.html）
// 平台现实覆盖真值两处：① 蓝牙卡说明不写死琴型号（CoreMIDI 源名才是真实数据）；
// ② 安全卡不点名服务商，保持「你配置的 AI 服务商」。
// 真值里的状态栏 9:41 / 返回 chevron / Home Indicator 是网页模拟的 OS chrome，iOS 上一律不画
// （返回由 OnboardingFlowView 拥有）。

struct S02PermissionsView: View {
    @StateObject private var permissions = PermissionCenter()
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("给 Neko 准备耳朵和眼睛")
                        .font(.system(size: 23, weight: .bold, design: .serif))
                        .lineSpacing(8) // 行高 1.375（单行时不生效，防换行塌行距）
                        .foregroundStyle(Color.textPrimary)
                    Text("所有权限都可以之后在「我的」里改。")
                        .font(.system(size: 13))
                        .leading(21, fontSize: 13)
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)

                // 蓝牙卡（必需，真实授权）
                permissionCard(
                    icon: "dot.radiowaves.left.and.right", iconTint: .accent,
                    title: "蓝牙（MIDI）",
                    body: "接收你的电钢琴的琴键、力度和踏板信号。这是判分的唯一依据。",
                    chip: bluetoothChipText, chipTone: bluetoothChipTone,
                    trailing: AnyView(bluetoothTrailing)
                )
                // 相机与麦克风卡（按需，不主动请求；红线 4 落点）
                permissionCard(
                    icon: "camera", iconTint: .neutral,
                    title: "相机与麦克风（按需）",
                    body: "只有你主动点「录给 AI 看」时才会启动。日常练习全程不录像、不录音。",
                    chip: "仅在主动录制时", chipTone: .amber,
                    trailing: AnyView(cameraTrailing)
                )
                // 通知卡
                permissionCard(
                    icon: "bell", iconTint: .neutral,
                    title: "提醒",
                    body: "每周日 21:00 收一条观察与下周建议，工作日 20:30 可选提醒。",
                    chip: "可关闭", chipTone: .amber,
                    trailing: AnyView(notificationTrailing)
                )

                safetyCard
            }
            .padding(.horizontal, 20)

            Button(action: onContinue) {
                HStack(spacing: 6) {
                    Text("继续：连接电钢琴")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .buttonStyle(S02CTAButtonStyle())
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color.canvas)
    }

    // MARK: 子组件

    private var bluetoothChipText: String {
        switch permissions.bluetooth {
        case .granted: "已授权"
        case .denied: "未授权"
        case .disabled: "蓝牙已关"
        case .unknown: "必需"
        }
    }

    /// 只有 .granted 才染绿，其余诚实用琥珀（旧实现两个分支都返回 success）
    private var bluetoothChipTone: S02ChipTone {
        permissions.bluetooth == .granted ? .green : .amber
    }

    /// 授权后 checkmark 替按钮（蓝牙 / 通知同一件）
    private var grantedCheck: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.success)
    }

    @ViewBuilder
    private var bluetoothTrailing: some View {
        if permissions.bluetooth == .granted {
            grantedCheck
        } else {
            S02CardActionButton(title: "去授权", style: .grant) {
                permissions.requestBluetooth()
            }
        }
    }

    /// 相机卡只展示不请求：按钮同真值样式渲染，但不挂交互（点了也没有权限可授）
    private var cameraTrailing: some View {
        S02CardActionButton(title: "稍后再说", style: .later)
    }

    @ViewBuilder
    private var notificationTrailing: some View {
        if permissions.notification == .granted {
            grantedCheck
        } else {
            S02CardActionButton(title: "允许通知", style: .notify) {
                permissions.requestNotification()
            }
        }
    }

    /// 语义 chip（真值 §3）：11pt medium / ls +0.025em / px8 py2 / 圆角 6 / 1pt 描边 / 15% 底
    private func statusChip(text: String, tone: S02ChipTone) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .tracking(0.275) // 0.025em × 11pt
            .foregroundStyle(tone.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(tone.background))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(tone.border, lineWidth: 1))
    }

    /// 权限卡（真值 §3）：#262220 底 / #332D29 1pt 描边 / 圆角 16 / p16，卡间距 14
    private func permissionCard(
        icon: String,
        iconTint: S02IconTint,
        title: String,
        body: String,
        chip: String,
        chipTone: S02ChipTone,
        trailing: AnyView
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(iconTint.glyph)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 12).fill(iconTint.background))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(iconTint.border, lineWidth: 1)
                    )
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(.bottom, 10)

            Text(body)
                .font(.system(size: 13))
                .leading(21, fontSize: 13)
                .foregroundStyle(Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            Rectangle()
                .fill(Color.border.opacity(0.6))
                .frame(height: 1)

            HStack {
                statusChip(text: chip, tone: chipTone)
                Spacer()
                trailing
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
        .padding(.top, 14)
    }

    /// 安全说明卡（真值 §4）：#201D1A 底 / #2D2825 描边 / 圆角 12 / p12。
    /// 文案保持中立，不点名具体服务商（真值里的「火山方舟」是平台现实要覆盖的第二处）。
    private var safetyCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield")
                .font(.system(size: 16))
                .foregroundStyle(Color.amber.opacity(0.9))
            Text("本应用没有服务器。MIDI 与笔记只存本机；视频片段只有你确认裁切后才会发送到你配置的 AI 服务商分析。")
                .font(.system(size: 11.5))
                .leading(18.7, fontSize: 11.5)
                .foregroundStyle(Color.textMuted.opacity(0.9))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.s02SafetyBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.s02SafetyBorder, lineWidth: 1))
        .padding(.top, 16)
    }
}

#Preview {
    S02PermissionsView(onContinue: {})
}

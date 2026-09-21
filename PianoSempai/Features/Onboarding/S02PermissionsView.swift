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

// MARK: - S02 权限页（文案逐字按 S02 spec）

struct S02PermissionsView: View {
    @StateObject private var permissions = PermissionCenter()
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("给 Neko 准备耳朵和眼睛")
                        .font(.headlineLg)
                        .foregroundStyle(Color.textPrimary)
                    Text("所有权限都可以之后在「我的」里改。")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)

                // 蓝牙卡（必需，真实授权）
                permissionCard(
                    icon: "dot.radiowaves.left.and.right", iconColor: Color.amber,
                    title: "蓝牙（MIDI）",
                    body: "接收特伦斯 V70 的琴键、力度和踏板信号。这是判分的唯一依据。",
                    chip: bluetoothChipText, chipColor: bluetoothChipColor,
                    trailing: AnyView(bluetoothTrailing)
                )
                // 相机与麦克风卡（按需，不主动请求；红线 4 落点）
                permissionCard(
                    icon: "camera", iconColor: Color.textBody,
                    title: "相机与麦克风（按需）",
                    body: "只有你主动点「录给 AI 看」时才会启动。日常练习全程不录像、不录音。",
                    chip: "仅在主动录制时", chipColor: Color.amber,
                    trailing: AnyView(laterButton)
                )
                // 通知卡
                permissionCard(
                    icon: "bell", iconColor: Color.amber,
                    title: "提醒",
                    body: "每周日 21:00 收一条观察与下周建议，工作日 20:30 可选提醒。",
                    chip: "可关闭", chipColor: Color.amber,
                    trailing: AnyView(notificationTrailing)
                )

                // 安全卡（说明数据去向：服务商链）
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "shield")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.amber)
                    Text("本应用没有服务器。MIDI 与笔记只存本机；视频片段只有你确认裁切后才会发送到你配置的 AI 服务商分析。")
                        .font(.bodySm)
                        .leading(18, fontSize: 12)
                        .foregroundStyle(Color.textBody)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 6))
                .padding(.top, 16)
            }
            .padding(.horizontal, 20)

            Button(action: onContinue) {
                Text("继续：连接电钢琴")
            }
            .buttonStyle(PrimaryButtonStyle())
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

    private var bluetoothChipColor: Color {
        permissions.bluetooth == .granted ? Color.success : Color.success
    }

    @ViewBuilder
    private var bluetoothTrailing: some View {
        if permissions.bluetooth == .granted {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.success)
        } else {
            Button("去授权") {
                permissions.requestBluetooth()
            }
            .font(.bodyMd)
            .foregroundStyle(Color.canvas)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.amber, in: Capsule())
        }
    }

    private var laterButton: some View {
        Text("稍后再说")
            .font(.bodyMd)
            .foregroundStyle(Color.textBody)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(Color.amber.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private var notificationTrailing: some View {
        if permissions.notification == .granted {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.success)
        } else {
            Button("允许通知") {
                permissions.requestNotification()
            }
            .font(.bodyMd)
            .foregroundStyle(Color.textBody)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(Color.amber.opacity(0.3), lineWidth: 1))
        }
    }

    private func statusChip(text: String, color: Color) -> some View {
        Text(text)
            .font(.labelSm)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
    }

    private func permissionCard(icon: String, iconColor: Color, title: String, body: String, chip: String, chipColor: Color, trailing: AnyView) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
                    .frame(width: 40, height: 40)
                    .background(Color.cardElevated, in: Circle())
                Text(title)
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
            }
            Text(body)
                .font(.bodySm)
                .leading(18, fontSize: 12)
                .foregroundStyle(Color.textBody)
                .padding(.top, 10)
            HStack {
                statusChip(text: chip, color: chipColor)
                Spacer()
                trailing
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
        .padding(.top, 12)
    }
}

#Preview {
    S02PermissionsView(onContinue: {})
}

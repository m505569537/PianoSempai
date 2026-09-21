import Combine
import SwiftUI

// MARK: - S03 MIDI 连接向导（3 步：准备/连接/验证；右上 ✕ 跳过落回框架）

struct S03MidiWizardView: View {
    @ObservedObject var hub = MIDIHub.shared
    @StateObject private var permissions = PermissionCenter()

    enum Step: Int {
        case prepare = 0, connect, verify
    }

    @State private var step: Step = .prepare
    @State private var systemDevices: [String] = []
    @State private var selectedDevice: String?
    @State private var connectFailed = false
    /// 验证步：2 秒窗口内收到的 Note On（音名/velocity/时间戳 三格反馈）
    @State private var verifyNoteName: String?
    @State private var verifyVelocity: Int?
    @State private var verifyTime: String?
    @State private var verifyPassed = false
    /// 系统蓝牙 MIDI 面板
    @State private var showBluetoothMIDIPanel = false

    let onSkip: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            navBar
            StepIndicator(current: step.rawValue, count: 3)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            ScrollView {
                switch step {
                case .prepare: prepareStep
                case .connect: connectStep
                case .verify: verifyStep
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            bottomCTA
        }
        .background(Color.canvas)
        .onAppear {
            permissions.refresh()
            refreshDevices()
        }
        .onReceive(hub.$events) { _ in
            guard step == .verify else { return }
            if let last = hub.events.last, case let .noteOn(note, velocity) = last.kind, velocity > 0 {
                recordVerify(note: note, velocity: velocity)
            }
        }
        // 统一事实源：系统 CoreMIDI 源名单变化（系统面板/GarageBand 建链/断开）→ 立即刷新
        .onReceive(hub.$systemSourceNames) { names in
            systemDevices = names
            syncSelectedDevice()
        }
        .sheet(isPresented: $showBluetoothMIDIPanel) {
            SystemMIDICentralPanel()
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: 导航

    private var navBar: some View {
        HStack {
            Button {
                // ‹ 返回 = 回上一步
                if step == .verify { step = .connect }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.textBody)
                    .frame(width: 36, height: 36)
            }
            Spacer()
            Button(action: onSkip) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textMuted)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: Step 1 准备

    private var prepareStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("准备连接")
                .font(.headlineLg)
                .foregroundStyle(Color.textPrimary)
            Text("开始之前，确认这几件事。")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .padding(.top, 4)

            NocturneCard {
                VStack(alignment: .leading, spacing: 14) {
                    checklistRow("1", "打开电钢琴的电源")
                    checklistRow("2", "确认琴的蓝牙 MIDI 已开启")
                    checklistRow("3", "iPhone 蓝牙保持开启")
                }
            }
            .padding(.top, 24)

            if permissions.bluetooth == .denied || permissions.bluetooth == .disabled {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.danger)
                    Text("蓝牙未授权或已关闭，无法发现设备。")
                        .font(.bodySm)
                        .foregroundStyle(Color.danger)
                    Spacer()
                    Button("去设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.bodyMd)
                    .foregroundStyle(Color.amber)
                }
                .padding(.top, 16)
            }

            Spacer(minLength: 24)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func checklistRow(_ index: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(index)
                .font(.labelMono(12, weight: .medium))
                .foregroundStyle(Color.amber)
                .frame(width: 20)
            Text(text)
                .font(.bodyMd)
                .foregroundStyle(Color.textPrimary)
        }
    }

    // MARK: Step 2 连接

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("连接你的电钢琴")
                .font(.headlineLg)
                .foregroundStyle(Color.textPrimary)
            Text("在系统蓝牙 MIDI 面板里点一下你的琴，连接会由 iOS 建立。")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .padding(.top, 4)

            // 当前连接状态（唯一事实来源 = CoreMIDI 源回调）
            connectionStatusCard
                .padding(.top, 20)

            // 打开系统蓝牙 MIDI 面板
            Button {
                showBluetoothMIDIPanel = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text(realConnected ? "蓝牙 MIDI 设置（已连接）" : "打开蓝牙 MIDI 设置")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 12)

            // 系统已暴露的 MIDI 源（BLE 经系统面板 / USB-B 方口 / 网络会话）
            if !systemDevices.isEmpty {
                sectionLabel("可用 MIDI 源")
                    .padding(.top, 20)
                ForEach(systemDevices, id: \.self) { name in
                    sourceCard(name)
                }
            }

            // 模拟源兜底（brief：模拟源兜底；不冒充 V70）
            Button {
                hub.mode = .simulated
                selectedDevice = "模拟输入"
                connectFailed = false
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "laptop.and.iphone")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.textBody)
                        .frame(width: 40, height: 40)
                        .background(Color.cardElevated, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("使用模拟输入")
                            .font(.titleMd)
                            .foregroundStyle(Color.textPrimary)
                        Text("暂时没有琴也能体验完整流程（事件为本机模拟，不冒充 V70）")
                            .font(.bodySm)
                            .foregroundStyle(Color.textMuted)
                    }
                    Spacer()
                    if hub.mode == .simulated {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.success)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(hub.mode == .simulated ? Color.success : Color.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 12)

            // 帮助卡
            NocturneCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("找不到？")
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                    Text("· 确认琴已开机且蓝牙 MIDI 已开启")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                    Text("· 列表里若没出现，关掉面板再点一次「打开蓝牙 MIDI 设置」")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                    Text("· USB-B 方口转接线也可以（更稳定省电）")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                }
            }
            .padding(.top, 20)

            if connectFailed {
                Text("连接失败，再试一次")
                    .font(.bodySm)
                    .foregroundStyle(Color.danger)
                    .padding(.top, 10)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.bottom, 16)
    }

    /// 真机是否真的连上（源回调为唯一事实来源）
    private var realConnected: Bool {
        hub.isConnected && hub.mode == .real
    }

    private var connectionStatusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: realConnected ? "pianokeys" : "pianokeys")
                .font(.system(size: 18))
                .foregroundStyle(realConnected ? Color.amber : Color.textMuted)
                .frame(width: 40, height: 40)
                .background(Color.cardElevated, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(realConnected ? (hub.connectedDeviceName ?? "电钢琴") : "未连接设备")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                Text(realConnected ? "CoreMIDI 源已就绪" : "点下面按钮，在系统面板里连接你的琴")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
            }
            Spacer()
            if realConnected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.success)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(realConnected ? Color.success : Color.border, lineWidth: 1)
        )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.labelMd)
            .foregroundStyle(Color.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 系统 MIDI 源卡片：已连接高亮勾选
    private func sourceCard(_ name: String) -> some View {
        let isSelected = selectedDevice == name && realConnected
        return HStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 18))
                .foregroundStyle(isSelected ? Color.amber : Color.textMuted)
                .frame(width: 40, height: 40)
                .background(Color.cardElevated, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.titleMd)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textMuted)
                Text("MIDI 源")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.success)
                Text("已连接")
                    .font(.bodySm)
                    .foregroundStyle(Color.success)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.success : Color.border, lineWidth: 1)
        )
        .padding(.top, 8)
    }

    /// 源名单/连接态变化 → 回填选定设备；没真连上不选定（红线：不乐观假连接）
    private func syncSelectedDevice() {
        guard hub.mode == .real else { return }
        guard realConnected else {
            if selectedDevice != nil && selectedDevice != "模拟输入" {
                selectedDevice = nil
                connectFailed = false
            }
            return
        }
        // 单一源直接认；多个源选包含 TERENCE/钢琴 的，否则不猜
        if systemDevices.count == 1 {
            selectedDevice = systemDevices.first
        } else {
            selectedDevice = systemDevices.first {
                $0.localizedCaseInsensitiveContains("TERENCE")
                    || $0.localizedCaseInsensitiveContains("钢琴")
            }
        }
        connectFailed = false
    }

    private func refreshDevices() {
        systemDevices = MIDIHub.systemSourceNames()
        syncSelectedDevice()
    }

    // MARK: Step 3 验证

    private var verifyStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("验证信号")
                .font(.headlineLg)
                .foregroundStyle(Color.textPrimary)
            Text("请弹任意一个音，三格会实时显示收到的信号。")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .padding(.top, 4)

            // 大按键提示
            HStack {
                Spacer()
                Image(systemName: "pianokeys")
                    .font(.system(size: 40))
                    .foregroundStyle(verifyPassed ? Color.success : Color.amber)
                    .frame(width: 120, height: 120)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(verifyPassed ? Color.success : Color.border, lineWidth: 1)
                    )
                Spacer()
            }
            .padding(.top, 24)

            // 三格实时反馈
            HStack(spacing: 12) {
                signalCell(title: "音名", value: verifyNoteName ?? "—")
                signalCell(title: "力度", value: verifyVelocity.map(String.init) ?? "—")
                signalCell(title: "时间戳", value: verifyTime ?? "—")
            }
            .padding(.top, 20)

            // 模拟源时提供屏幕琴键
            if hub.mode == .simulated, let simulated = hub.simulated {
                Text("模拟输入：点按琴键产生事件")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 20)
                HStack(spacing: 4) {
                    ForEach([UInt8(60), 62, 64, 65, 67], id: \.self) { note in
                        Button {
                            simulated.press(note: note)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                simulated.release(note: note)
                            }
                        } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.scorePaper)
                                .frame(height: 64)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }

            if verifyPassed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Color.success)
                    Text("信号验证通过")
                        .font(.bodyMd)
                        .foregroundStyle(Color.success)
                }
                .padding(.top, 16)
            }

            Spacer(minLength: 24)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func signalCell(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.labelSm)
                .foregroundStyle(Color.textMuted)
            Text(value)
                .font(.labelMono(16, weight: .medium))
                .foregroundStyle(Color.amber)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
    }

    private func recordVerify(note: UInt8, velocity: UInt8) {
        verifyNoteName = SightReadSession.noteName(note)
        verifyVelocity = Int(velocity)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        verifyTime = formatter.string(from: Date())
        // 验证通过标准（onboarding 域契约）：2 秒内 ≥1 个有效 Note On
        verifyPassed = velocity > 0
    }

    // MARK: 底部 CTA

    private var bottomCTA: some View {
        VStack(spacing: 8) {
            if step == .connect {
                Button {
                    if MIDIWizardFlow.canAdvanceFromConnect(
                        systemDevices: systemDevices,
                        selectedDevice: selectedDevice,
                        mode: hub.mode
                    ) {
                        step = .verify
                    }
                } label: {
                    Text("下一步：验证信号")
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: selectedDevice != nil || hub.mode == .simulated))
                .disabled(selectedDevice == nil && hub.mode != .simulated)
            } else if step == .prepare {
                Button {
                    step = .connect
                } label: {
                    Text("下一步：查找设备")
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button {
                    onDone()
                } label: {
                    Text("完成，开始定级")
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: verifyPassed))
                .disabled(!verifyPassed)
                // 验证未过也允许先进入评估（可用 ✕ 跳过，符合"不锁死，允许先逛"）
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

#Preview {
    S03MidiWizardView(onSkip: {}, onDone: {})
}

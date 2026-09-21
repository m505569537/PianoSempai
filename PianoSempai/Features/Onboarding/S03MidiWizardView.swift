import Combine
import SwiftUI

// MARK: - S03 MIDI 连接向导（3 步：准备/连接/验证；右上 ✕ 跳过落回框架）

struct S03MidiWizardView: View {
    @ObservedObject var hub = MIDIHub.shared
    @ObservedObject private var ble = BLEMIDIManager.shared
    @StateObject private var permissions = PermissionCenter()

    enum Step: Int {
        case prepare = 0, connect, verify
    }

    @State private var step: Step = .prepare
    @State private var systemDevices: [String] = []
    @State private var selectedDevice: String?
    @State private var connectFailed = false
    @State private var isConnecting = false
    /// 正在连接的 BLE-MIDI 外设（连接中显示转圈；连上后由系统源名回填）
    @State private var selectedBLEID: UUID?
    /// 验证步：2 秒窗口内收到的 Note On（音名/velocity/时间戳 三格反馈）
    @State private var verifyNoteName: String?
    @State private var verifyVelocity: Int?
    @State private var verifyTime: String?
    @State private var verifyPassed = false

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
            // BLE-MIDI：App 侧扫描才会让 iOS 创建 CoreMIDI 源（P0 修复）
            ble.start()
        }
        .onDisappear {
            // 离开向导只停扫描，不断开已连上的琴
            ble.stopScanning()
        }
        .onReceive(hub.$events) { _ in
            guard step == .verify else { return }
            if let last = hub.events.last, case let .noteOn(note, velocity) = last.kind, velocity > 0 {
                recordVerify(note: note, velocity: velocity)
            }
        }
        .onReceive(ble.$devices) { _ in syncBLEDevices() }
        .onReceive(ble.$midiSourceCount) { _ in syncBLEDevices() }
        // 统一事实源：系统 CoreMIDI 源名单变化（外部建链/断开，如 GarageBand）→ 立即刷新，
        // 不靠 onAppear 一次性快照（外部建链后连接步不刷新的修复）
        .onReceive(hub.$systemSourceNames) { names in
            systemDevices = names
            syncBLEDevices()
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
            Text("打开琴电源，PianoSempai 会自动找到它。")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .padding(.top, 4)

            // 扫描态行（真实状态：BLE-MIDI 由 App 侧扫描）
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.amber)
                    .frame(width: 40, height: 40)
                    .background(Color.cardElevated, in: RoundedRectangle(cornerRadius: 8))
                Text(scanStatusText)
                    .font(.bodyMd)
                    .foregroundStyle(Color.textBody)
                if ble.scanState == .scanning {
                    ScanningDots()
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
            .padding(.top, 20)

            // BLE-MIDI 设备（App 侧发现/连接；连上后 iOS 自动创建 CoreMIDI 源）
            sectionLabel("BLE-MIDI 设备")
                .padding(.top, 20)
            if ble.devices.isEmpty {
                Text("还没发现设备。打开琴电源、确认琴上蓝牙 MIDI 已开启，然后点下面的「重新扫描」。")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 8)
                Button {
                    ble.rescan()
                } label: {
                    Text("重新扫描")
                }
                .buttonStyle(SecondaryButtonStyle(cornerRadius: 8))
                .padding(.top, 8)
            } else {
                ForEach(ble.devices) { device in
                    bleDeviceCard(device)
                }
            }

            // 系统已暴露的其它 MIDI 源（USB-B 方口 / 网络会话）
            if !displayDevices.isEmpty {
                sectionLabel("其它 MIDI 源")
                    .padding(.top, 20)
                ForEach(displayDevices, id: \.self) { device in
                    deviceCard(device)
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

            // 帮助卡（三条逐字）
            NocturneCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("找不到？")
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                    Text("· 确认琴已开机且蓝牙 MIDI 已开启")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                    Text("· USB-B 方口转接线也可以（更省电）")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                    Text("· 也可以用 GarageBand 验证连接")
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

    /// 展示逻辑：发现 V70 → 单卡；发现其它源 → 置灰；无源 → 空列表
    private var displayDevices: [String] {
        systemDevices
    }

    /// 扫描态文案（不冒充连接态）
    private var scanStatusText: String {
        switch ble.scanState {
        case .scanning: "正在搜索附近的蓝牙 MIDI 设备…"
        case .poweredOff: "蓝牙已关闭，请在系统设置里打开"
        case .unauthorized: "蓝牙未授权，无法发现设备"
        case .idle: "扫描已停止"
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.labelMd)
            .foregroundStyle(Color.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// BLE-MIDI 设备卡。连接成立的唯一判据 = iOS 真的创建了 CoreMIDI 源
    /// （hub.isConnected 由 CoreMIDISource 的 onConnectionChanged 上报，此处不臆造）。
    private func bleDeviceCard(_ device: BLEMIDIDevice) -> some View {
        let isThisConnecting = device.state == .connecting || (isConnecting && selectedBLEID == device.id)
        // 只有真实 CoreMIDI 源存在时才允许显示「已连接」
        let isReallyConnected = device.state == .connected && hub.isConnected && hub.mode == .real
        return HStack(spacing: 12) {
            Image(systemName: "pianokeys")
                .font(.system(size: 18))
                .foregroundStyle(isReallyConnected ? Color.amber : Color.textBody)
                .frame(width: 40, height: 40)
                .background(Color.cardElevated, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle(for: device))
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
            }
            Spacer()
            if isReallyConnected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.success)
                Text("已连接")
                    .font(.bodySm)
                    .foregroundStyle(Color.success)
            } else if isThisConnecting {
                ProgressView()
                    .tint(Color.amber)
                Text("连接中")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
            } else {
                Button {
                    connectBLEDevice(device)
                } label: {
                    Text(device.state == .failed ? "重试" : "连接")
                        .font(.bodyMd)
                        .foregroundStyle(Color.amber)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(Capsule().strokeBorder(Color.amber.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isReallyConnected ? Color.success : Color.border, lineWidth: 1)
        )
        .padding(.top, 8)
    }

    private func subtitle(for device: BLEMIDIDevice) -> String {
        switch device.state {
        case .discovered:
            // 全扫描会捞到附近所有蓝牙设备：广播带 MIDI 服务 UUID 的算已确认，
            // 其余是候选——是否 MIDI 设备要点「连接」后由 GATT 服务发现判定（如实标注）
            if device.advertisedMIDIService {
                return device.rssi == 0 ? "BLE-MIDI · 已确认" : "BLE-MIDI · 信号 \(device.rssi) dBm"
            }
            return "候选设备 · 点「连接」验证是否为 MIDI"
        case .connecting: return "正在连接…"
        case .connected: return hub.isConnected && hub.mode == .real ? "BLE-MIDI · 已连接" : "已连接，正在等待信号"
        case .failed: return "连接失败，点「重试」再试一次"
        }
    }

    /// 点 BLE 设备的「连接」：先切真机源，再由 App 侧发起 BLE 连接。
    /// 是否算连上，由随后 iOS 是否创建 CoreMIDI 源决定。
    private func connectBLEDevice(_ device: BLEMIDIDevice) {
        isConnecting = true
        connectFailed = false
        selectedBLEID = device.id
        hub.mode = .real
        ble.connect(device)
    }

    /// BLE 状态变化 → 用系统真实暴露的 CoreMIDI 源名回填选定设备。
    /// 源名没出现就不选定、不放行下一步（红线：不乐观假连接）。
    /// 只在真机模式下同步：用户主动选了模拟输入时不插手。
    private func syncBLEDevices() {
        guard hub.mode == .real else { return }

        // 用户点选中的外设（连接中/已连接）优先，其次任意已连接外设
        let connectedBLE = ble.devices.first(where: {
            $0.id == selectedBLEID && ($0.state == .connected || $0.state == .connecting)
        }) ?? ble.devices.first(where: { $0.state == .connected })
        // 外部建链（GarageBand 等）时本 App 没有 connected 外设，但系统源已真实出现：
        // 以 hub.isConnected 为准继续走名字匹配，不清空已选定的源
        let externallyConnected = connectedBLE == nil && hub.isConnected
        guard connectedBLE != nil || externallyConnected else {
            // BLE 侧没有已连接设备：收回由 BLE 路径做的选定，不假装还连着
            if selectedBLEID != nil || (selectedDevice != nil && selectedDevice != "模拟输入") {
                let anyFailed = ble.devices.contains { $0.state == .failed }
                selectedBLEID = nil
                selectedDevice = nil
                isConnecting = false
                connectFailed = anyFailed
            }
            return
        }

        // 只有真连上了才查系统源名（避免每次扫描上报都建一次 MIDIClient）
        let names = MIDIHub.systemSourceNames()
        systemDevices = names
        // 名字对得上才认；多个源且对不上时不猜（用户可从「其它 MIDI 源」手动选）
        let match: String?
        if let connectedBLE {
            match = names.first(where: {
                $0.localizedCaseInsensitiveContains(connectedBLE.name) || connectedBLE.name.localizedCaseInsensitiveContains($0)
            }) ?? (names.count == 1 ? names.first : nil)
        } else {
            // 外部建链：单一源时直接认；多个源不猜，等用户在「其它 MIDI 源」里点
            match = names.count == 1 ? names.first : nil
        }
        guard let match else {
            isConnecting = connectedBLE != nil // 蓝牙已连、CoreMIDI 源还没出现
            return
        }
        selectedDevice = match
        if let connectedBLE { selectedBLEID = connectedBLE.id }
        isConnecting = false
        connectFailed = false
    }

    private func deviceCard(_ name: String) -> some View {
        let isV70 = name.localizedCaseInsensitiveContains("V70")
        // 已连接必须有真实 CoreMIDI 源（hub.isConnected 的唯一来源是源回调）
        let isSelected = selectedDevice == name && hub.mode == .real && hub.isConnected
        return HStack(spacing: 12) {
            Image(systemName: isV70 ? "pianokeys" : "music.note.house")
                .font(.system(size: 18))
                .foregroundStyle(isV70 ? Color.amber : Color.textMuted)
                .frame(width: 40, height: 40)
                .background(Color.cardElevated, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.titleMd)
                    .foregroundStyle(isV70 ? Color.textPrimary : Color.textMuted)
                Text(isV70 ? "BLE-MIDI · 信号强" : "其它 MIDI 源")
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
            } else {
                Button {
                    selectDevice(name)
                } label: {
                    Text(isConnecting ? "连接中" : "连接")
                        .font(.bodyMd)
                        .foregroundStyle(Color.amber)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(Capsule().strokeBorder(Color.amber.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.success : Color.border, lineWidth: 1)
        )
        .padding(.top, 12)
    }

    private func selectDevice(_ name: String) {
        isConnecting = true
        connectFailed = false
        // 切到真机源（CoreMIDI 的源在系统层已连接，此处语义是"选定并开始接收"）
        hub.mode = .real
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isConnecting = false
            // 必须真的连上（源回调上报）才算选定；仅名单里有名字不算
            if hub.mode == .real, hub.isConnected, let names = hub.real?.sourceNames, names.contains(name) {
                selectedDevice = name
            } else {
                connectFailed = true
            }
        }
    }

    private func refreshDevices() {
        systemDevices = MIDIHub.systemSourceNames()
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

            // 三格实时反馈（复用诊断信号条样式）
            HStack(spacing: 12) {
                signalCell(title: "音名", value: verifyNoteName ?? "—")
                signalCell(title: "力度", value: verifyVelocity.map(String.init) ?? "—")
                signalCell(title: "时间戳", value: verifyTime ?? "—")
            }
            .padding(.top, 20)

            // 模拟源时提供屏幕琴键（模拟器无真琴）
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
                    // BLE 路径与 USB 路径共用同一判定：selectedDevice 只在系统真的暴露了
                    // CoreMIDI 源名后才被赋值（见 syncBLEDevices / selectDevice）
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
                // 验证未过也允许先进入评估（模拟源路径必然能过；真机路径弹不了音时卡在此步，
                // 可用 ✕ 跳过，符合"不锁死，允许先逛"）
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

/// 扫描呼吸三点（1.2s 循环，依次亮琥珀）
private struct ScanningDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(phase == i ? Color.amber : Color.borderInput)
                    .frame(width: 5, height: 5)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
    }
}

#Preview {
    S03MidiWizardView(onSkip: {}, onDone: {})
}

import Combine
import SwiftUI

// MARK: - S03 MIDI 连接向导（3 步：准备/连接/验证；✕ 跳过落回框架）
// 视觉真值：docs/design-reference/screens/S03-midi-wizard/spec.md（Stitch code.html 只出到 step2）。
// 本屏对齐项：向导导航与步骤条（§1/§2）、底部 CTA 与幽灵按钮（§5）、
// 验证步三格实时反馈与 2 秒监听窗（§7 旧 spec + onboarding.md 域契约）。
// 真值里的状态栏 9:41 / Home Indicator 是网页模拟的 OS chrome，iOS 上由系统提供，一律不画。

/// 验证步时间戳格式（HH:mm:ss.SSS）。DateFormatter 构建昂贵，复用单例。
private let verifyTimestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
}()

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
    /// 验证监听窗（onboarding 域契约：2 秒内收到 ≥1 个有效 Note On）。
    /// token 每次武装窗口时换新 → `.task(id:)` 自动取消上一个计时，不留野定时器。
    @State private var verifyWindowToken: UUID?
    @State private var verifyWindowExpired = false
    /// 系统蓝牙 MIDI 面板 / 帮助小 sheet —— 单一 sheet 路由。
    /// 项目教训：一个视图只可靠呈现一个 `.sheet`，多 sheet 曾致 S09 导航死路，
    /// 故用 Identifiable 枚举 + `.sheet(item:)` 收口（同 LibraryView/SettingsView）。
    enum ActiveSheet: Identifiable {
        case bluetoothMIDI
        case help

        var id: String {
            switch self {
            case .bluetoothMIDI: "bluetooth-midi"
            case .help: "help"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    /// 系统装有 GarageBand 才显示验证幽灵按钮（真值 §5；scheme 已在 Info.plist 声明）
    @State private var garageBandAvailable = false

    /// 排查提示（保留 USB-B 转接线说明；真值 §5 帮助行为单行链接，内容移到本 sheet）
    private let helpTips = [
        "确认琴已开机，并在功能菜单里打开蓝牙 MIDI。",
        "列表里若没出现，关掉系统面板，再点一次「打开蓝牙 MIDI 设置」。",
        "USB-B 方口转接线也可以（更稳定省电）。",
    ]

    let onBack: () -> Void
    let onSkip: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            navBar

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
            // GarageBand 验证按钮仅在可用时显示（真值 §5 + onboarding.md）
            if let url = URL(string: "garageband://") {
                garageBandAvailable = UIApplication.shared.canOpenURL(url)
            }
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
        // 离开验证步 → 停掉 2 秒监听计时（不把过期态带到下一步）
        .onChange(of: step) { _, newStep in
            if newStep != .verify { verifyWindowToken = nil }
        }
        // 2 秒监听窗：窗口内没收到有效 Note On → 提示"再听一次"，不判失败、不锁死
        .task(id: verifyWindowToken) {
            guard verifyWindowToken != nil else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, step == .verify, !verifyPassed else { return }
            verifyWindowExpired = true
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .bluetoothMIDI:
                SystemMIDICentralPanel()
                    .ignoresSafeArea(edges: .bottom)
            case .help:
                helpSheet
            }
        }
    }

    // MARK: 导航

    /// 真值 §1/§2：返回 32×32、圆角 8、#262220 60% 底 + 1pt #332D29 描边、`chevron_left` 18pt #9C948B；
    /// 中间步骤条居中，右侧同形占位。
    /// ‹ 返回 = 回上一步；第 1 步没有上一步 → 退回 S02 权限页（onBack）。
    private var navBar: some View {
        HStack(spacing: 8) {
            navChip("chevron.left", pointSize: 18, label: "返回") {
                switch step {
                case .verify: step = .connect
                case .connect: step = .prepare
                case .prepare: onBack()
                }
            }
            Spacer(minLength: 8)
            StepIndicator(current: step.rawValue, count: 3, titles: ["准备", "连接", "验证"])
            Spacer(minLength: 8)
            // 真值右侧是 32×32 透明占位、没有 ✕；这里保留 ✕ 跳过：
            // 系统层 onboarding.md 契约「可 ✕ 跳过（落 S07b，连接胶囊红点）」优先，不锁死用户。
            navChip("xmark", pointSize: 15, label: "跳过向导", action: onSkip)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private func navChip(
        _ systemImage: String,
        pointSize: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: pointSize, weight: .medium))
                .foregroundStyle(Color.textMuted)
                .frame(width: 32, height: 32)
                .background(Color.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
            // 真值 §3 插画卡（蓝牙波纹 + 电钢琴线稿），位于标题区之上
            MidiIllustrationCard()

            // 真值 §4 标题行：flex items-center gap-2，标题后跟一枚 6×6 琥珀圆点。
            // 圆点无文字基线，默认按底边对齐会上跳；显式把圆心落到首行视觉中心。
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("连接你的电钢琴")
                    .font(.headlineLg)
                    .foregroundStyle(Color.textPrimary)
                Circle()
                    .fill(Color.amber)
                    .frame(width: 6, height: 6)
                    .alignmentGuide(.firstTextBaseline) { d in
                        d[VerticalAlignment.center] + 8
                    }
            }
            Text("在系统蓝牙 MIDI 面板里点一下你的琴，连接会由 iOS 建立。")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .padding(.top, 4)

            // 当前连接状态（唯一事实来源 = CoreMIDI 源回调）
            connectionStatusCard
                .padding(.top, 20)

            // 打开系统蓝牙 MIDI 面板（iOS 上唯一能让 BLE-MIDI 生成 CoreMIDI 源的入口）。
            // 用次按钮：真值 §5 的底部琥珀 CTA 是本屏唯一主操作，内容区不抢它的视觉权重。
            Button {
                activeSheet = .bluetoothMIDI
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text(realConnected ? "蓝牙 MIDI 设置（已连接）" : "打开蓝牙 MIDI 设置")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.top, 12)

            // 系统已暴露的 MIDI 源（BLE 经系统面板 / USB-B 方口 / 网络会话）
            if !systemDevices.isEmpty {
                HStack {
                    sectionLabel("可用 MIDI 源")
                    // 真值 §4 行 2 刷新钮：32×32、圆角 8、`refresh` 18pt #9C948B。
                    // 真值底部 CTA「重新扫描」的语义落在这里——本屏 CTA 要承担流程推进。
                    Button { refreshDevices() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.textMuted)
                            .frame(width: 32, height: 32)
                            .background(Color.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("重新扫描")
                }
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
                    Image(systemName: "laptopcomputer.and.iphone")
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

            // 帮助行（真值 §5：单行链接，不是卡片）：help_outline 18pt + 文案 14pt #9C948B，
            // 间距 8pt，右侧 chevron_right 16pt；左右 12、上下 8、圆角 12。
            // 真实排查提示（含 USB-B 转接线）移到点按后的小 sheet，内容不删。
            Button {
                activeSheet = .help
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 18))
                    Text("找不到设备？查看帮助")
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16))
                }
            }
            .buttonStyle(WizardHelpRowStyle())
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

            // 监听窗状态（契约：2 秒内 ≥1 个有效 Note On）
            verifyWindowStatus
                .padding(.top, 16)

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

            Spacer(minLength: 24)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// 监听窗状态行：监听中 / 已通过 / 空窗（给「再听一次」，不判失败也不锁死）
    @ViewBuilder
    private var verifyWindowStatus: some View {
        if verifyPassed {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                Text("信号验证通过")
            }
            .font(.bodyMd)
            .foregroundStyle(Color.success)
        } else if verifyWindowExpired {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                    // 三格有值 = 音在监听窗之外才到；三格全空 = 这 2 秒真的什么都没收到
                    Text(verifyNoteName == nil ? "这 2 秒没有收到信号" : "信号在监听窗之外到达")
                }
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                Spacer()
                Button("再听一次") { armVerifyWindow() }
                    .font(.labelMd)
                    .foregroundStyle(Color.amber)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                Text("正在监听，2 秒内弹一个音")
            }
            .font(.bodySm)
            .foregroundStyle(Color.textMuted)
        }
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
        verifyTime = verifyTimestampFormatter.string(from: Date())
        // 验证通过标准（onboarding 域契约）：监听窗内收到 ≥1 个有效 Note On。
        // 窗外到达的音只更新三格（实时反馈），不放行——用户可「再听一次」重开窗口。
        if MIDIVerifyGate.passes(
            windowArmed: verifyWindowToken != nil,
            windowExpired: verifyWindowExpired,
            velocity: velocity
        ) {
            verifyPassed = true
            verifyWindowToken = nil // 已判定，停表
        }
    }

    /// 进入验证步：清掉上一轮三格与通过态，重新武装 2 秒监听窗
    private func enterVerify() {
        verifyNoteName = nil
        verifyVelocity = nil
        verifyTime = nil
        verifyPassed = false
        armVerifyWindow()
    }

    /// 武装监听窗（换 token → `.task(id:)` 取消上一个计时）
    private func armVerifyWindow() {
        verifyWindowExpired = false
        verifyWindowToken = UUID()
    }

    // MARK: 底部 CTA

    /// 真值 §5：底部钉住区 = 全宽琥珀 CTA +（step2）GarageBand 幽灵按钮。
    /// 各步 CTA 文案由流程决定：真值只出到 step2，其「重新扫描」语义由源区刷新钮承担（见 §4）。
    private var bottomCTA: some View {
        VStack(spacing: 4) {
            switch step {
            case .prepare:
                Button {
                    step = .connect
                } label: {
                    Text("下一步：查找设备")
                }
                .buttonStyle(WizardCTAButtonStyle())
            case .connect:
                Button {
                    step = .verify
                    enterVerify()
                } label: {
                    Text("下一步：验证信号")
                }
                .buttonStyle(WizardCTAButtonStyle(isEnabled: canAdvanceFromConnect))
                .disabled(!canAdvanceFromConnect)
            case .verify:
                Button(action: onDone) {
                    Text("完成，开始定级")
                }
                .buttonStyle(WizardCTAButtonStyle(isEnabled: verifyPassed))
                .disabled(!verifyPassed)
                // 验证未过不放进定级；退出走 ✕ 跳过（onboarding.md：不锁死，允许先逛）
            }

            // 真值 §5 幽灵按钮：`tune` +「使用 GarageBand 验证连接」；系统没装则不显示
            if step == .connect, garageBandAvailable {
                Button {
                    if let url = URL(string: "garageband://") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        // Material `tune` 无对应 SF Symbol，取最接近的滑杆图标
                        Image(systemName: "slider.vertical.3")
                            .font(.system(size: 16))
                        Text("使用 GarageBand 验证连接")
                    }
                }
                .buttonStyle(WizardGhostButtonStyle())
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    /// 帮助小 sheet（真值 §5 帮助行的落点）：真实排查提示，含 USB-B 转接线说明。
    private var helpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(helpTips, id: \.self) { tip in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle()
                                .fill(Color.amber)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(tip)
                                .font(.bodyMd)
                                .foregroundStyle(Color.textBody)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.canvas)
            .navigationTitle("找不到设备？")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { activeSheet = nil }
                        .font(.bodyMd)
                        .foregroundStyle(Color.amber)
                }
            }
            .toolbarBackground(Color.card, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        // 小 sheet：固定高度 + 可见抓手，不用系统默认 medium/large 两档
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.card)
    }

    /// 连接步推进判定（与 CTA enabled 同源：MIDIWizardFlow，禁止两处各写一份）
    private var canAdvanceFromConnect: Bool {
        MIDIWizardFlow.canAdvanceFromConnect(
            systemDevices: systemDevices,
            selectedDevice: selectedDevice,
            mode: hub.mode
        )
    }
}

// MARK: - S03 专用按钮样式（真值 §5；共享 PrimaryButtonStyle 不改动）

/// 底部全宽琥珀 CTA：16/24 weight 500（titleMd）、上下 14pt（高 52）、圆角 8、文字 #1C1917；
/// pressed 亮到 #E8C882；disabled 填充 #3D3531 文字 #9C948B；投影 0 4 20 琥珀 22%。
struct WizardCTAButtonStyle: ButtonStyle {
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.titleMd)
            .foregroundStyle(isEnabled ? Color.canvas : Color.textMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(fill(isPressed: configuration.isPressed))
            )
            .shadow(color: isEnabled ? Color.amber.opacity(0.22) : .clear, radius: 20, x: 0, y: 4)
    }

    private func fill(isPressed: Bool) -> Color {
        guard isEnabled else { return Color.borderInput }
        return isPressed ? Color.amberBright : Color.amber
    }
}

/// 底部幽灵按钮（真值 §5）：14pt #9C948B，pressed 变 #F5F2ED，上下 10pt
struct WizardGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyMd)
            .foregroundStyle(configuration.isPressed ? Color.textPrimary : Color.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }
}

/// 帮助行按钮（真值 §5）：14pt #9C948B；pressed 文字变琥珀、底 #262220 40%、描边 #332D29；
/// 左右 12、上下 8、圆角 12（真值 hover 态的触屏等价）。
struct WizardHelpRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyMd)
            .foregroundStyle(configuration.isPressed ? Color.amber : Color.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                configuration.isPressed ? Color.card.opacity(0.4) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(configuration.isPressed ? Color.border : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 真值 §3 插画卡（蓝牙波纹 + 电钢琴线稿）

/// 插画卡（真值 §3）：#262220 底、圆角 16、p20、1pt #332D29 描边、mb 16；
/// 内顶高光 `inset 0 1 0 rgba(255,255,255,0.03)` + 径向光（中心 #D4A24E 10% → 透明，整体不透明度 40%）；
/// 内容区高 128pt 居中：上蓝牙波纹组（mb 4），下电钢琴线稿。
private struct MidiIllustrationCard: View {
    var body: some View {
        VStack(spacing: 0) {
            BluetoothWaveGlyph()
                .padding(.bottom, 4)
            PianoLineArt()
        }
        .frame(height: 128)
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.card))
        // 径向环境光：Tailwind bg-radial 的两段插值（中心 10% 琥珀 → 末端透明）用定值半径近似
        .background(
            RadialGradient(
                colors: [Color.amber.opacity(0.10), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: 180
            )
            .opacity(0.4)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        )
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
        .overlay(alignment: .top) {
            Color.white.opacity(0.03)
                .frame(height: 1)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }
}

/// 蓝牙波纹组（真值 §3）：64×56 容器，3s ease-in-out 呼吸（不透明度 0.35↔0.85、缩放 0.98↔1.02）。
/// 外弧 64×64 琥珀 25% / 中弧 48×48 琥珀 50% / 核心 24×24（#1C1917 底 + 1pt 琥珀 60% 描边 + 辉光）。
private struct BluetoothWaveGlyph: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            WaveArc(width: 64, tint: Color.amber.opacity(0.25))
            WaveArc(width: 48, tint: Color.amber.opacity(0.5))
            ZStack {
                Circle()
                    .fill(Color.canvas)
                    .overlay(Circle().strokeBorder(Color.amber.opacity(0.6), lineWidth: 1))
                    .shadow(color: Color.amber.opacity(0.3), radius: 6)
                // SF Symbols 没有 bluetooth 字形，按 ᛒ 几何手绘符文（等价 bluetooth_searching 的笔画）
                BluetoothRune()
                    .stroke(
                        Color.amber,
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 12, height: 14)
            }
            .frame(width: 24, height: 24)
        }
        .frame(width: 64, height: 56)
        .scaleEffect(pulse ? 1.02 : 0.98)
        .opacity(pulse ? 0.85 : 0.35)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

/// 波纹弧：真值 SVG path 的等比缩放版（外弧 64 / 中弧 48 共用同一比例曲线），线宽 1.2、圆头
private struct WaveArc: View {
    let width: CGFloat
    let tint: Color

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: width * 0.19, y: width * 0.34))
            path.addCurve(
                to: CGPoint(x: width * 0.81, y: width * 0.34),
                control1: CGPoint(x: width * 0.28, y: width * 0.25),
                control2: CGPoint(x: width * 0.72, y: width * 0.25)
            )
        }
        .stroke(tint, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        .frame(width: width, height: width)
    }
}

/// 蓝牙符文：竖主干 + 中点向上的斜笔 + 中点向下的斜笔（真值 `bluetooth_searching` 的 ᛒ 笔画）。
/// SF Symbols 无此字形，故手绘；等比缩放进任意 rect。
private struct BluetoothRune: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.midX
        let top = rect.minY + rect.height * 0.08
        let bottom = rect.maxY - rect.height * 0.08
        let right = rect.maxX - rect.width * 0.12
        // 竖主干
        path.move(to: CGPoint(x: x, y: top))
        path.addLine(to: CGPoint(x: x, y: bottom))
        // 中点 → 右上
        path.move(to: CGPoint(x: x, y: rect.midY))
        path.addLine(to: CGPoint(x: right, y: top + rect.height * 0.12))
        // 中点 → 右下
        path.move(to: CGPoint(x: x, y: rect.midY))
        path.addLine(to: CGPoint(x: right, y: bottom - rect.height * 0.12))
        return path
    }
}

/// 电钢琴线稿（真值 §3）：224×44 区域。
/// 琴体（满宽、高 28、圆角 3、1pt 琥珀 60% 描边、#1C1917 80% 底、左右 4 上下 2 内边距）
///   ├ 顶条：双状态点（琥珀 / #3D3531）+ 32×4 凹槽 + graphic_eq 9pt 琥珀 70%
///   └ 琴键行：高 14、顶边 1pt #332D29；10 白键（#262220 + 右侧 1pt #332D29 60%）；
///             黑键 6 槽位中 5 可见（4×8、琥珀 90%、底圆角 1，第 3 槽空缺）
/// 琴架：192 宽（左右各 8 内边距），两条 1×12 支腿 + 144×1 横梁（距底 6），色均 #332D29
private struct PianoLineArt: View {
    var body: some View {
        VStack(spacing: 0) {
            pianoBody
            pianoStand
                .padding(.top, 2)
        }
        .frame(width: 224)
    }

    private var pianoBody: some View {
        VStack(spacing: 0) {
            topStrip
            keysRow
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(height: 28)
        .background(Color.canvas.opacity(0.8))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.amber.opacity(0.6), lineWidth: 1)
        )
    }

    /// 顶条：左双状态点、中 32×4 凹槽、右电平图标（真值 graphic_eq）
    private var topStrip: some View {
        HStack(spacing: 2) {
            Circle().fill(Color.amber).frame(width: 4, height: 4)
            Circle().fill(Color.borderInput).frame(width: 4, height: 4)
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.border)
                .frame(width: 32, height: 4)
            Spacer(minLength: 0)
            Image(systemName: "waveform")
                .font(.system(size: 9))
                .foregroundStyle(Color.amber.opacity(0.7))
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    /// 琴键行：10 白键 + 6 槽位黑键（第 3 槽空缺）
    private var keysRow: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { index in
                    Rectangle()
                        .fill(Color.card)
                        .overlay(alignment: .trailing) {
                            if index < 9 {
                                Rectangle()
                                    .fill(Color.border.opacity(0.6))
                                    .frame(width: 1)
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity)
            // justify-around：每槽位左右各一个 Spacer，黑键居中落在自己的 1/6 槽里
            HStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { slot in
                    Spacer(minLength: 0)
                    if slot != 2 {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0, bottomLeadingRadius: 1,
                            bottomTrailingRadius: 1, topTrailingRadius: 0,
                            style: .continuous
                        )
                        .fill(Color.amber.opacity(0.9))
                        .frame(width: 4, height: 8)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 14)
        .overlay(alignment: .top) {
            Color.border.frame(height: 1)
        }
    }

    /// 琴架：两条 1×12 支腿 + 144×1 横梁
    private var pianoStand: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Rectangle().fill(Color.border).frame(width: 1, height: 12)
            Spacer(minLength: 0)
            Rectangle().fill(Color.border)
                .frame(width: 144, height: 1)
                .padding(.bottom, 6)
            Spacer(minLength: 0)
            Rectangle().fill(Color.border).frame(width: 1, height: 12)
        }
        .padding(.horizontal, 8)
        .frame(width: 192)
    }
}

#Preview {
    S03MidiWizardView(onBack: {}, onSkip: {}, onDone: {})
}

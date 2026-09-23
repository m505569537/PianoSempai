import Combine
import SwiftData
import SwiftUI

// MARK: - S24 MIDI 诊断（实时信号本机显示；无"上传诊断"按钮——红线）

// 视觉对齐真值 /tmp/stitch-truth/revised/S24.md：四卡结构（连接 / 实时信号 / 提示 / 常见排查）。
// 数据链路不变：所有数值由 MIDIHub 实时驱动——
// 不写死设备名/键数/延迟/事件数/假音高与 hostTime，模拟源永不显示 ONLINE（红线）。

struct MidiDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var hub = MIDIHub.shared
    @State private var showRecalibration = false
    @State private var showBluetoothMIDIPanel = false
    @State private var lastEventAt = Date()
    @State private var now = Date()
    @State private var expandedNoSignal = false
    @State private var expandedStutter = false

    private var lastEvent: MIDIEvent? { hub.events.last }
    /// 音高/力度读数取最后一个 noteOn（踏板事件不顶替音高）
    private var lastNoteOn: MIDIEvent? {
        hub.events.last(where: { event in
            if case .noteOn = event.kind { return true }
            return false
        })
    }
    /// 延音踏板取最后一个 CC64 事件（0–127 连续值）
    private var lastSustain: MIDIEvent? {
        hub.events.last(where: { event in
            if case .sustainPedal = event.kind { return true }
            return false
        })
    }

    /// 3 秒无事件 → 无信号态（沿用现有口径；now 由 1s 心跳推进，保证该态会自己翻过来）
    private var hasRecentEvent: Bool { now.timeIntervalSince(lastEventAt) <= 3 }

    /// 真机源且真实连接才配 ONLINE（红线：模拟源永不冒充真机）
    private var realConnected: Bool { hub.isConnected && hub.mode == .real }

    /// 连接态头条文案：真机源用 hub 真实设备名（缺失回落「电钢琴」），绝不写死型号
    private var headlineText: String {
        if hub.isConnected {
            return "\(hub.connectedDeviceName ?? "电钢琴")已连接"
        }
        return "电钢琴未连接"
    }

    /// 传输协议：hub 无 USB/BLE 区分能力，真机源统一如实显 CoreMIDI，不写死 BLE-MIDI
    private var protocolText: String {
        hub.mode == .simulated ? "模拟" : "CoreMIDI"
    }

    private let readingColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.top, 12)
                    connectionCard.padding(.top, 14)
                    signalCard.padding(.top, 14)
                    hintCard.padding(.top, 14)
                    troubleshootingCard.padding(.top, 14)
                    footnote.padding(.top, 16)
                }
                .padding(.horizontal, 16)
            }
            .background(Color.canvas)
            .navigationBarHidden(true)
            .sheet(isPresented: $showRecalibration) {
                VelocityRecalibrationView()
            }
            .sheet(isPresented: $showBluetoothMIDIPanel) {
                SystemMIDICentralPanel()
                    .ignoresSafeArea(edges: .bottom)
            }
            .onReceive(hub.$events) { _ in
                lastEventAt = Date()
                now = Date()
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
                now = tick
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: 导航头（serif 21pt 大标题 + 真实连接指示）

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("MIDI 诊断")
                .font(.system(size: 21, weight: .semibold, design: .serif))
                .foregroundStyle(Color.textPrimary)

            Spacer(minLength: 8)

            if realConnected {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.success)
                        .frame(width: 8, height: 8)
                    Text("ONLINE")
                        .font(.labelMono(11, weight: .medium))
                        .foregroundStyle(Color.success)
                }
            } else if hub.mode == .simulated {
                // 模拟源如实标注，绝不显示 ONLINE
                Text("模拟输入")
                    .font(.labelSm)
                    .foregroundStyle(Color.amber)
            }
        }
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.border.opacity(0.4))
                .frame(height: 1)
        }
    }

    // MARK: 连接卡

    private var connectionCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    if realConnected {
                        ConnectionPulseDot()
                    } else {
                        Circle()
                            .fill(Color.textMuted)
                            .frame(width: 10, height: 10)
                    }
                    Text(headlineText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(hub.isConnected ? Color.textPrimary : Color.textMuted)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 14)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.border.opacity(0.7))
                        .frame(height: 1)
                }

                LazyVGrid(columns: readingColumns, spacing: 10) {
                    readingCell(label: "传输协议", value: protocolText, valueColor: Color.textPrimary)
                    // 无真实往返延迟测量源：如实显「—」，不写「12ms 优」也不加徽章
                    readingCell(label: "传输延迟", value: "—", valueColor: Color.textMuted)
                    readingCell(
                        label: "最后事件",
                        value: hasRecentEvent ? "刚刚" : "无信号",
                        valueColor: hasRecentEvent ? Color.amber : Color.textMuted
                    )
                    readingCell(label: "事件总数", value: "\(hub.events.count)", valueColor: Color.textPrimary)
                }
                .padding(.top, 14)

                Rectangle()
                    .fill(Color.border.opacity(0.7))
                    .frame(height: 1)
                    .padding(.top, 14)

                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        showBluetoothMIDIPanel = true
                    } label: {
                        Text("蓝牙 MIDI 设置")
                    }
                    .buttonStyle(SecondaryButtonStyle(cornerRadius: 12))
                    .padding(.top, 14)

                    // 系统源名单为 hub 真实上报（外部建链/断开自动刷新）
                    if !hub.systemSourceNames.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(hub.systemSourceNames, id: \.self) { name in
                                Text(name)
                                    .font(.labelMd)
                                    .foregroundStyle(Color.textBody)
                            }
                        }
                    }

                    Text("蓝牙 MIDI 连接由 iOS 建立后才会出现 CoreMIDI 源；系统设置里的「已连接」不算，App 内私有连接也不会建源。")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
    }

    private func readingCell(label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.labelSm)
                .foregroundStyle(Color.textMuted)
            Text(value)
                .font(.labelMono(13.5, weight: .medium))
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.canvas.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.border.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: 实时信号卡

    private var signalCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("实时信号")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.textPrimary)
                    Text("CH 1")
                        .font(.labelMono(10, weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(Color.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.border, in: RoundedRectangle(cornerRadius: 2))

                    Spacer(minLength: 8)

                    listeningPill
                }
                .padding(.bottom, 12)

                VStack(alignment: .leading, spacing: 12) {
                    pitchRow
                    velocityRow
                    pedalRow
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(Color.border.opacity(0.6))
                        .frame(height: 1)
                    HStack(spacing: 6) {
                        Image(systemName: "schedule")
                            .font(.system(size: 13))
                        Text("时间戳 hostTime")
                            .font(.system(size: 11))
                        Spacer(minLength: 8)
                        // hostTime 沿用现有真实换算（ms），不抄真值示例的整数
                        Text(lastEvent.map { String(format: "%.3f ms", hostTimeMs(of: $0)) } ?? "—")
                            .font(.labelMono(11))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 10)
                }
                .padding(.top, 12)
            }
        }
    }

    /// mach 域纳秒 → ms（沿用现有换算口径）
    private func hostTimeMs(of event: MIDIEvent) -> Double {
        Double(event.timeNanos % 1_000_000_000_000) / 1_000_000
    }

    private var listeningPill: some View {
        HStack(spacing: 6) {
            BreathingDot(color: Color.success, size: 6)
            Text("正在监听")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.success)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.success.opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.success.opacity(0.3), lineWidth: 1))
    }

    private var pitchRow: some View {
        signalBarRow(
            label: "音高",
            // 无 noteOn 事件显「—」；有则显真实音名 · MIDI 号
            value: lastNoteOn.map { event in
                if case let .noteOn(note, _) = event.kind {
                    return "\(SightReadSession.noteName(note)) · \(note)"
                }
                return "—"
            } ?? "—",
            hasValue: lastNoteOn != nil,
            valueColor: Color.textPrimary,
            barColor: Color.amber,
            // 条宽按真实音高在 MIDI 0–127 映射，不写死 48%
            fraction: lastNoteOn.map { event in
                if case let .noteOn(note, _) = event.kind {
                    return Double(note) / 127
                }
                return 0
            } ?? 0
        )
    }

    private var velocityRow: some View {
        signalBarRow(
            label: "力度",
            value: lastNoteOn.map { event in
                if case let .noteOn(_, velocity) = event.kind {
                    return "\(velocity) / 127"
                }
                return "—"
            } ?? "—",
            hasValue: lastNoteOn != nil,
            valueColor: Color.amber,
            barColor: Color.amber,
            fraction: lastNoteOn.map { event in
                if case let .noteOn(_, velocity) = event.kind {
                    return Double(velocity) / 127
                }
                return 0
            } ?? 0
        )
    }

    private var pedalRow: some View {
        signalBarRow(
            label: "踏板",
            // CC64 连续值 0–127：>63 踩下，否则松开
            value: lastSustain.map { event in
                if case let .sustainPedal(value) = event.kind {
                    return "CC64 \(value) · \(value > 63 ? "踩下" : "松开")"
                }
                return "—"
            } ?? "—",
            hasValue: lastSustain != nil,
            valueColor: Color.success,
            barColor: Color.success,
            fraction: lastSustain.map { event in
                if case let .sustainPedal(value) = event.kind {
                    return Double(value) / 127
                }
                return 0
            } ?? 0
        )
    }

    private func signalBarRow(
        label: String,
        value: String,
        hasValue: Bool,
        valueColor: Color,
        barColor: Color,
        fraction: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMuted)
                Spacer(minLength: 8)
                Text(value)
                    .font(.labelMono(13, weight: .semibold))
                    .foregroundStyle(hasValue ? valueColor : Color.textMuted)
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.border)
                        .frame(height: 6)
                    Capsule()
                        .fill(barColor)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1), height: 6)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.border.opacity(0.4), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: fraction)
    }

    // MARK: 提示卡

    private var hintCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(Color.amber)
                    Text("随便弹几个音、踩一下踏板，四个数值都应该跟着动。力度不准可回到上一级做 2 分钟个人校准。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.textPrimary.opacity(0.9))
                        .leading(20, fontSize: 12.5)
                }

                Button {
                    showRecalibration = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tune")
                            .font(.system(size: 16))
                        Text("重新校准力度")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.amber)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.amber.opacity(0.5), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 常见排查指引卡

    private var troubleshootingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("常见排查指引")
                .font(.system(size: 11.5, weight: .semibold, design: .serif))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Color.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 0) {
                // 1「蓝牙搜不到设备」→ 打开系统 MIDI 面板（真实动作）
                troubleshootingRow(icon: "dot.radiowaves.left.and.right", title: "蓝牙搜不到设备") {
                    showBluetoothMIDIPanel = true
                }

                troubleshootingExpandableRow(
                    icon: "speaker.slash",
                    title: "有声音但没有信号",
                    detail: "在蓝牙 MIDI 面板里确认已连接。力度不动：在琴上检查力度感应开关。",
                    isExpanded: expandedNoSignal
                ) {
                    withAnimation(.easeOut(duration: 0.18)) { expandedNoSignal.toggle() }
                }

                troubleshootingExpandableRow(
                    icon: "speedometer",
                    title: "声音断续或拖拍",
                    detail: "断连频繁：靠近一点或用 USB-B 方口。",
                    isExpanded: expandedStutter
                ) {
                    withAnimation(.easeOut(duration: 0.18)) { expandedStutter.toggle() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.border, lineWidth: 1)
        )
        .clipped()
    }

    private func troubleshootingRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowContent(icon: icon, title: title, isExpanded: nil)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func troubleshootingExpandableRow(
        icon: String,
        title: String,
        detail: String,
        isExpanded: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                rowContent(icon: icon, title: title, isExpanded: isExpanded)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                if isExpanded {
                    Text(detail)
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowContent(icon: String, title: String, isExpanded: Bool?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.textMuted)
            Text(title)
                .font(.system(size: 13.5))
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .rotationEffect(.degrees(isExpanded == true ? 90 : 0))
        }
    }

    // MARK: 脚注

    private var footnote: some View {
        HStack(spacing: 6) {
            Image(systemName: "shield")
                .font(.system(size: 14))
            Text("诊断信息不会上传，仅用于本机排查")
                .font(.system(size: 11.5))
        }
        .foregroundStyle(Color.textMuted)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }

    // MARK: 真值卡片容器（card 底 / 1px 发丝边 / r16）

    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.border, lineWidth: 1)
            )
    }
}

// MARK: - 连接脉冲点（真值 animate-ping：外层扩散 + 内层实点）

private struct ConnectionPulseDot: View {
    @State private var ping = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.success.opacity(0.75))
                .frame(width: 10, height: 10)
                .scaleEffect(ping ? 2.2 : 1)
                .opacity(ping ? 0 : 1)
            Circle()
                .fill(Color.success)
                .frame(width: 10, height: 10)
        }
        .frame(width: 10, height: 10)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                ping = true
            }
        }
    }
}

// MARK: - 监听呼吸点（2s：opacity 1→0.4、scale 1→0.85）

private struct BreathingDot: View {
    var color: Color
    var size: CGFloat
    @State private var phase = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(phase ? 0.4 : 1)
            .scaleEffect(phase ? 0.85 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    phase = true
                }
            }
    }
}

// MARK: - 力度重校（S24 入口；新建校准盖新时间戳，旧记录留追溯）

struct VelocityRecalibrationView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var hub = MIDIHub.shared

    enum Phase: Int, CaseIterable {
        case pp = 0, mf, ff
        var label: String {
            switch self {
            case .pp: "最弱"
            case .mf: "舒适"
            case .ff: "最强"
            }
        }
    }

    @State private var phase: Phase = .pp
    @State private var samples: [Phase: [Int]] = [:]
    @State private var simulatedVelocity: Double = 64

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("力度重校（\(phase.label)）")
                        .font(.headlineLg)
                        .foregroundStyle(Color.textPrimary)
                        .padding(.top, 8)
                    Text("在琴上用「\(phase.label)」的力度弹几个音。新校准会盖时间戳生效，旧曲线保留追溯。")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 4)

                    ForEach(Phase.allCases, id: \.rawValue) { p in
                        let count = samples[p]?.count ?? 0
                        HStack {
                            Image(systemName: count >= 3 ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(count >= 3 ? Color.success : Color.textMuted)
                            Text(p.label)
                                .font(.titleMd)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text("已收 \(count) 音")
                                .font(.labelMono(12))
                                .foregroundStyle(Color.textMuted)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 10)
                    }
                    .padding(.top, 8)

                    if hub.mode == .simulated, let simulated = hub.simulated {
                        Text("模拟力度：\(Int(simulatedVelocity))")
                            .font(.labelMd)
                            .foregroundStyle(Color.textMuted)
                            .monospacedDigit()
                            .padding(.top, 12)
                        Slider(value: $simulatedVelocity, in: 1...127, step: 1)
                            .tint(Color.amber)
                        HStack(spacing: 8) {
                            ForEach([UInt8(60), 64, 67], id: \.self) { note in
                                Button {
                                    simulated.press(note: note, velocity: UInt8(simulatedVelocity))
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        simulated.release(note: note)
                                    }
                                } label: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.scorePaper)
                                        .frame(height: 44)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        advanceOrFinish()
                    } label: {
                        Text(phase == .ff ? "完成重校" : "下一档")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
            .background(Color.canvas)
            .navigationTitle("力度校准")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Color.amber)
                }
            }
            .onAppear {
                hub.onEvent = { event in
                    if case let .noteOn(_, velocity) = event.kind, velocity > 0 {
                        samples[phase, default: []].append(Int(velocity))
                    }
                }
            }
            .onDisappear { hub.onEvent = nil }
        }
        .preferredColorScheme(.dark)
    }

    private func advanceOrFinish() {
        if phase == .ff {
            persist()
            dismiss()
        } else {
            phase = Phase(rawValue: phase.rawValue + 1) ?? .ff
        }
    }

    private func persist() {
        let calibration = VelocityCalibration() // 新记录 = 盖新时间戳（测试锁定）
        let pp = (samples[.pp] ?? []).sorted()
        let mf = (samples[.mf] ?? []).sorted()
        let ff = (samples[.ff] ?? []).sorted()
        calibration.ppSamples = pp.count
        calibration.mfSamples = mf.count
        calibration.ffSamples = ff.count
        calibration.ppVelocity = pp.isEmpty ? 0 : pp[pp.count / 2]
        calibration.mfVelocity = mf.isEmpty ? 0 : mf[mf.count / 2]
        calibration.ffVelocity = ff.isEmpty ? 0 : ff[ff.count / 2]
        calibration.deviceName = hub.mode == .simulated ? "模拟输入" : (hub.real?.sourceNames.first ?? "未知设备")
        context.insert(calibration)
    }
}

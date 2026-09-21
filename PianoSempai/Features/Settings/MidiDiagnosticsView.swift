import SwiftData
import SwiftUI

// MARK: - S24 MIDI 诊断（实时信号本机显示；无"上传诊断"按钮——红线）

struct MidiDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var hub = MIDIHub.shared
    @State private var showRecalibration = false
    @State private var showBluetoothMIDIPanel = false
    @State private var lastEventAt = Date()

    private var lastEvent: MIDIEvent? { hub.events.last }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    deviceCard.padding(.top, 12)
                    bluetoothCard.padding(.top, 12)
                    signalCard.padding(.top, 12)

                    Button {
                        showRecalibration = true
                    } label: {
                        Text("重新校准力度（2 分钟）")
                    }
                    .buttonStyle(SecondaryButtonStyle(cornerRadius: 8))
                    .padding(.top, 16)

                    NocturneCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("排错")
                                .font(.titleMd)
                                .foregroundStyle(Color.textPrimary)
                            Text("· 断连频繁：靠近一点或用 USB-B 方口")
                                .font(.bodySm).foregroundStyle(Color.textMuted)
                            Text("· 没信号：在蓝牙 MIDI 面板里确认已连接")
                                .font(.bodySm).foregroundStyle(Color.textMuted)
                            Text("· 力度不动：在琴上检查力度感应开关")
                                .font(.bodySm).foregroundStyle(Color.textMuted)
                        }
                    }
                    .padding(.top, 16)

                    Text("诊断信息不会上传。")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
            .background(Color.canvas)
            .navigationTitle("MIDI 诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.amber)
                }
            }
            .sheet(isPresented: $showRecalibration) {
                VelocityRecalibrationView()
            }
            .sheet(isPresented: $showBluetoothMIDIPanel) {
                SystemMIDICentralPanel()
                    .ignoresSafeArea(edges: .bottom)
            }
            .onReceive(hub.$events) { _ in
                lastEventAt = Date()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: 蓝牙 MIDI 连接卡（系统面板）

    private var realConnected: Bool {
        hub.isConnected && hub.mode == .real
    }

    private var bluetoothCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.amber)
                    Text("蓝牙 MIDI")
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(realConnected ? "已连接" : "未连接")
                        .font(.labelSm)
                        .foregroundStyle(realConnected ? Color.success : Color.textMuted)
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(realConnected ? Color.success : Color.danger)
                        .frame(width: 7, height: 7)
                    if realConnected {
                        Text("\(hub.connectedDeviceName ?? "电钢琴") · CoreMIDI 源已就绪")
                            .font(.bodyMd)
                            .foregroundStyle(Color.textBody)
                    } else {
                        Text("点「蓝牙 MIDI 设置」，在系统面板里点一下你的琴")
                            .font(.bodyMd)
                            .foregroundStyle(Color.textMuted)
                    }
                }

                if !hub.systemSourceNames.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(hub.systemSourceNames, id: \.self) { name in
                            HStack(spacing: 8) {
                                Text(name)
                                    .font(.labelMd)
                                    .foregroundStyle(Color.textBody)
                                Spacer()
                            }
                        }
                    }
                }

                Button {
                    showBluetoothMIDIPanel = true
                } label: {
                    Text("蓝牙 MIDI 设置")
                }
                .buttonStyle(SecondaryButtonStyle(cornerRadius: 8))
                .padding(.top, 2)

                Text("蓝牙 MIDI 连接由 iOS 建立后才会出现 CoreMIDI 源；系统设置里的「已连接」不算，App 内私有连接也不会建源。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    private var deviceCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(hub.isConnected ? Color.success : Color.danger)
                        .frame(width: 7, height: 7)
                    // 三态文案唯一来源（红线：模拟源永不显示 V70，绝不冒充真机连接）
                    Text(hub.isConnected
                         ? MIDIDeviceLabel.label(for: MIDIDeviceLabel.state(isConnected: true, mode: hub.mode))
                         : MIDIDeviceLabel.waitingText(for: MIDIDeviceLabel.state(isConnected: false, mode: hub.mode)))
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    if hub.mode == .simulated {
                        Text("模拟输入")
                            .font(.labelSm)
                            .foregroundStyle(Color.amber)
                    }
                }
                if let name = hub.connectedDeviceName {
                    Text("事件源：\(name)")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                }
                HStack(spacing: 14) {
                    Text("事件 \(hub.events.count)")
                    Text("hostTime \(String(format: "%.1f", hostTimeMs)) ms")
                    Text(Date.now.timeIntervalSince(lastEventAt) > 3 ? "还没收到信号" : "刚刚")
                }
                .font(.labelSm)
                .foregroundStyle(Color.textMuted)
                .monospacedDigit()
            }
        }
    }

    private var hostTimeMs: Double {
        guard let last = lastEvent else { return 0 }
        return Double(last.timeNanos % 1_000_000_000_000) / 1_000_000
    }

    private var signalCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("实时信号（弹一个音试试）")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)

                if let last = lastEvent, case let .noteOn(note, velocity) = last.kind {
                    signalRow(label: "音高", text: "\(SightReadSession.noteName(note)) · MIDI \(note)", fraction: 1)
                    signalRow(label: "力度", text: "\(velocity) / 127", fraction: Double(velocity) / 127)
                } else {
                    signalRow(label: "音高", text: "—", fraction: 0)
                    signalRow(label: "力度", text: "—", fraction: 0)
                }
                pedalRow
                HStack {
                    Text("hostTime")
                        .font(.labelMd)
                        .foregroundStyle(Color.textBody)
                    Spacer()
                    Text(lastEvent.map { String(format: "%.3f ms", Double($0.timeNanos % 1_000_000_000_000) / 1_000_000) } ?? "—")
                        .font(.labelMono(12))
                        .foregroundStyle(Color.textMuted)
                        .monospacedDigit()
                }
            }
        }
    }

    private func signalRow(label: String, text: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.labelMd).foregroundStyle(Color.textBody)
                Spacer()
                Text(text).font(.labelMono(12, weight: .medium)).foregroundStyle(Color.amber).monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.borderInput).frame(height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(Color.amber)
                        .frame(width: proxy.size.width * fraction, height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    private var pedalRow: some View {
        HStack {
            Text("踏板")
                .font(.labelMd)
                .foregroundStyle(Color.textBody)
            Spacer()
            if let last = lastEvent, case let .sustainPedal(value) = last.kind {
                Text("CC64 = \(value)（\(value > 63 ? "踩下" : "松开")）")
                    .font(.labelMono(12, weight: .medium))
                    .foregroundStyle(value > 63 ? Color.amber : Color.textMuted)
            } else {
                Text("CC64 = —")
                    .font(.labelMono(12))
                    .foregroundStyle(Color.textMuted)
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

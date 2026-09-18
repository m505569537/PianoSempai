import SwiftUI

/// M1 Spike B 验收视图：模拟源开关 + 屏幕琴键 + 结构化事件流打印。
/// 正式 S24 MIDI 诊断页在后续批次按 spec 实装；本视图仅 spike 证据。
struct MIDISpikeView: View {
    @StateObject private var hub = MIDIHub()

    private var keys: [UInt8] {
        [60, 62, 64, 65, 67, 69, 71, 72] // C4 D4 E4 F4 G4 A4 B4 C5
    }

    var body: some View {
        VStack(spacing: 16) {
            Picker("源", selection: $hub.mode) {
                ForEach(MIDIHub.Mode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

            Text(hub.isConnected ? "已连接：\(hub.connectedDeviceName ?? "")" : "未连接")
                .font(.labelMd)
                .foregroundStyle(hub.isConnected ? Color.success : Color.danger)

            if let simulated = hub.simulated {
                // 屏幕琴键（模拟源）
                HStack(spacing: 4) {
                    ForEach(keys, id: \.self) { note in
                        PianoKeyButton(note: note) { pressed in
                            if pressed {
                                simulated.press(note: note)
                            } else {
                                simulated.release(note: note)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                Button("自动回放音阶") {
                    simulated.autoReplayScale()
                }
                .font(.titleMd)
                .foregroundStyle(Color.amber)
            } else {
                Text("真机源：等待系统 MIDI 设备（模拟器无 BLE 设备）")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
            }

            // 结构化事件流
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(hub.events.reversed()) { event in
                        Text(event.structuredDescription)
                            .font(.labelMono(10))
                            .foregroundStyle(event.isSuspicious ? Color.danger : Color.textBody)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 24)
        .background(Color.canvas)
        .task {
            // spike 验收辅助：进入页面自动回放一段，事件流直接可见（无需手动点按）
            hub.simulated?.autoReplayScale()
        }
    }
}

/// 简单琴键按钮：按下/抬起走 press/release（onChanged 会连发，用状态只在沿上触发）
private struct PianoKeyButton: View {
    let note: UInt8
    let onPress: (Bool) -> Void
    @State private var isPressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(isPressed ? Color.amberBright : Color.scorePaper)
            .frame(width: 36, height: 96)
            .overlay(alignment: .bottom) {
                Text("\(note)")
                    .font(.labelMono(9))
                    .foregroundStyle(Color.scoreInk)
                    .padding(.bottom, 6)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        onPress(true)
                    }
                    .onEnded { _ in
                        guard isPressed else { return }
                        isPressed = false
                        onPress(false)
                    }
            )
    }
}

#Preview {
    MIDISpikeView()
}

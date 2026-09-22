import SwiftData
import SwiftUI

// MARK: - S14 自由弹奏（不打分沙盒；进入即采 MIDI；卷帘 + 一句话 + 保存/丢弃）

struct FreePlayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var hub = MIDIHub.shared
    @StateObject private var session = PracticeSession(isFreePlay: true)
    @State private var metronome = MetronomeService()
    @State private var metronomeOn = false
    @State private var noteText = ""
    @State private var discardConfirm = false
    @State private var saved = false

    var onSaved: () -> Void // 保存后跳档案

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // 钢琴卷帘（简单条形视图；无键盘对错着色）
            PianoRollView(notes: session.playedNotes)
                .frame(height: UIScreen.main.bounds.height * 0.30)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
                .overlay(alignment: .center) {
                    if session.playedNotes.isEmpty {
                        Text("随便弹，不打分 · 音符只记录在本机")
                            .font(.bodySm)
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .padding(.top, 12)

            HStack(spacing: 16) {
                Text("本次时长 \(format(sec: Int(session.startedAt.map { Date().timeIntervalSince($0) } ?? 0)))")
                    .font(.labelMd)
                    .foregroundStyle(Color.textBody)
                    .monospacedDigit()
                Text("音符 \(session.playedNotes.count)")
                    .font(.labelMd)
                    .foregroundStyle(Color.textBody)
                    .monospacedDigit()
                Spacer()
                // 录制中：红点呼吸 + 仅 MIDI（强调不是视频，红线 4）
                Circle()
                    .fill(Color.danger)
                    .frame(width: 8, height: 8)
                    .opacity(breathing ? 0.3 : 1)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                            breathing = true
                        }
                    }
                Text("录制中（仅 MIDI）")
                    .font(.labelMd)
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.top, 12)

            Text("这次弹了什么？")
                .font(.bodyMd)
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 20)
            TextField("例如：瞎弹了一段菊次郎的夏天", text: $noteText, axis: .vertical)
                .font(.bodyMd)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(3, reservesSpace: true)
                .padding(10)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.borderInput, lineWidth: 1))
                .padding(.top, 8)

            HStack {
                Button {
                    metronomeOn.toggle()
                    if metronomeOn {
                        metronome.start(bpm: 80, countInBars: 0)
                    } else {
                        metronome.stop()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "metronome")
                        Text("节拍器")
                    }
                    .font(.bodyMd)
                    .foregroundStyle(metronomeOn ? Color.canvas : Color.textBody)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(metronomeOn ? Color.amber : Color.clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(metronomeOn ? Color.clear : Color.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                Button("丢弃") { discardConfirm = true }
                    .font(.bodyMd)
                    .foregroundStyle(Color.danger)
            }
            .padding(.top, 16)

            Button {
                saveTake()
            } label: {
                Text("结束并保存")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .background(Color.canvas)
        .preferredColorScheme(.dark)
        .onAppear {
            // 进入即采 MIDI（spec：不需要先点录音）
            session.start(metronome: metronome, countIn: false, metronomeOn: metronomeOn)
        }
        .onReceive(hub.$events) { _ in
            guard let last = hub.events.last, last.id != lastHandledEventID else { return }
            lastHandledEventID = last.id
            session.handle(last)
        }
        .confirmationDialog("丢弃后这次弹奏不可恢复。确定丢弃？", isPresented: $discardConfirm, titleVisibility: .visible) {
            Button("丢弃", role: .destructive) {
                metronome.stop()
                dismiss() // 不落库即丢弃（默认焦点在取消）
            }
            Button("继续弹", role: .cancel) {}
        }
    }

    @State private var breathing = false
    @State private var lastHandledEventID: UUID?

    private var header: some View {
        HStack {
            Button { exitConfirmFlow() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.textBody)
                    .frame(width: 36, height: 36)
            }
            Text("自由弹奏")
                .font(.headlineSm)
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
        .padding(.top, 8)
    }

    private func exitConfirmFlow() {
        // 弹过音的退出 = 丢弃语义（破坏性，走危险确认）
        if session.playedNotes.isEmpty {
            metronome.stop()
            dismiss()
        } else {
            discardConfirm = true
        }
    }

    private func saveTake() {
        metronome.stop()
        let summary = session.finish()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let title = noteText.isEmpty ? "自由弹奏 · \(formatter.string(from: Date()))" : noteText
        _ = PracticeSession.persist(
            summary,
            taskType: "free",
            isFreePlay: true,
            startedAt: session.startedAt ?? Date(),
            interruptions: session.interruptionStarts,
            title: title,
            in: context
        )
        saved = true
        dismiss()
        onSaved()
    }

    private func format(sec: Int) -> String {
        String(format: "%d:%02d", sec / 60, sec % 60)
    }
}

/// 卷帘：playedNotes → 横向琥珀条形（pitch → y，时间 → x）；无对错着色（spec）
struct PianoRollView: View {
    let notes: [(pitch: UInt8, sec: Double)]

    var body: some View {
        ScrollViewReader { _ in
            ScrollView([.horizontal]) {
                Canvas { context, size in
                    guard let first = notes.first else { return }
                    let pxPerSec: CGFloat = 60
                    let highest = notes.map(\.pitch).max() ?? 72
                    let lowest = notes.map(\.pitch).min() ?? 60
                    let span = max(12, Int(highest) - Int(lowest) + 3)
                    let rowHeight = size.height / CGFloat(span)
                    for note in notes {
                        let x = CGFloat(note.sec - first.sec) * pxPerSec
                        let y = size.height - (CGFloat(note.pitch - lowest + 1) * rowHeight)
                        let rect = CGRect(x: x, y: y, width: 14, height: max(4, rowHeight - 2))
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: 4),
                            with: .color(Color.amber.opacity(0.85))
                        )
                    }
                }
                .frame(width: max(320, CGFloat((notes.last?.sec ?? 0) * 60) + 40))
            }
            .defaultScrollAnchor(.trailing)
        }
    }
}

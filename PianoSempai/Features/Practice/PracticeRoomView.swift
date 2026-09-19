import SheetMusicCore
import SheetMusicLoader
import SheetMusicUI
import SwiftData
import SwiftUI

// MARK: - S11 全屏练习室（+S11b 断连覆盖态；S12 循环 sheet；M6a 版）
// 零打断（spec）：错音/慢全程无 Alert；断连 → S11b 覆盖态；时间到自动保存。

struct PracticeRoomView: View {
    let taskType: String // warmup / main / reward
    var scoreFile: ScoreFile?
    var pieceTitle: String = ""
    var timeLimitSec: Int? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var hub = MIDIHub.shared
    @StateObject private var session = PracticeSession()
    @State private var metronome = MetronomeService()

    @State private var loadedScore: Score?
    @State private var loadError: String?
    @State private var metronomeOn = false
    @State private var showLoopSheet = false
    @State private var showTempoPanel = false
    @State private var finishedSummary: TakeSummary?
    @State private var exitConfirm = false
    @State private var nekoToast = false
    @State private var lastHandledEventID: UUID?
    @State private var showMarkSheet = false

    private var totalMeasures: Int { loadedScore.map(ScoreExpectedPitches.measureCount) ?? 0 }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                scoreArea
                nextMeasureLabel.padding(.top, 6)
                progressLine.padding(.top, 10)
                controlRow.padding(.top, 16)
                if showTempoPanel {
                    tempoPanel.padding(.top, 8)
                }
                playButton.padding(.top, 18)
                finishButton.padding(.top, 14)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .background(Color.canvas)

            if !hub.isConnected {
                S11bDisconnectedOverlay(
                    onReconnect: reconnect,
                    onExit: { finishAndSave() }
                )
            }

            if let toast = session.toast {
                Text(toast)
                    .font(.bodyMd)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.cardElevated.opacity(0.92), in: Capsule())
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        session.toast = nil
                    }
            }

            if nekoToast {
                ToastCapsule(text: "AI 助教将在后续版本开放")
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showLoopSheet) {
            S12LoopSettingsSheet(session: session, totalMeasures: totalMeasures)
        }
        .sheet(isPresented: $showMarkSheet) {
            S13bMarkSheet(
                scoreName: displayTitle,
                measure: session.followState.measureIndex + 1
            ) { type, note in
                context.insert(ScoreErrorMark(
                    scoreName: displayTitle,
                    measure: session.followState.measureIndex + 1,
                    type: type,
                    note: note
                ))
                session.addMark() // 时间点标签
            }
        }
        .fullScreenCover(item: $finishedSummary) { summary in
            M6aTakeSavedView(summary: summary, onDone: { dismiss() })
        }
        .onAppear(perform: load)
        .onReceive(hub.$events) { _ in
            // 只处理未消费过的新事件（订阅/复现会重放当前数组）
            guard let last = hub.events.last, last.id != lastHandledEventID else { return }
            lastHandledEventID = last.id
            session.handle(last)
        }
        .onChange(of: hub.isConnected) { _, connected in
            session.setConnected(connected)
        }
        .onChange(of: session.timeUp) { _, up in
            if up {
                metronome.stop()
                finishAndSave() // 时间到自动保存（不截断语义：此刻收尾存 take）
            }
        }
        .confirmationDialog("退出练习？已弹的部分会保存为 take。", isPresented: $exitConfirm, titleVisibility: .visible) {
            Button("结束并保存") { finishAndSave() }
            Button("继续练习", role: .cancel) {}
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                if session.phase == .performing {
                    exitConfirm = true
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.textBody)
                    .frame(width: 36, height: 36)
            }
            Text(displayTitle)
                .font(.headlineSm)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer()
            Text("♩=\(session.tempoState.bpm)")
                .font(.labelMono(14, weight: .medium))
                .foregroundStyle(Color.amber)
                .monospacedDigit()
            Button {
                nekoToast = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    nekoToast = false
                }
            } label: {
                Image(systemName: "cat")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.amber)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.top, 8)
    }

    private var displayTitle: String {
        if !pieceTitle.isEmpty { return pieceTitle }
        return scoreFile?.title ?? "练习"
    }

    // MARK: 谱区（真实引擎渲染）

    private var scoreArea: some View {
        Group {
            if let loadedScore {
                ScrollView {
                    ScoreView(
                        score: loadedScore,
                        options: ScoreViewOptions(wrapToViewWidth: true),
                        playbackCursor: cursor,
                        playbackCursorColor: Color.amber.opacity(0.25),
                        availableWidth: UIScreen.main.bounds.width - 64,
                    )
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: UIScreen.main.bounds.height * 0.42)
                .background(Color.scorePaper, in: RoundedRectangle(cornerRadius: 8))
            } else if let loadError {
                Text(loadError)
                    .font(.bodySm)
                    .foregroundStyle(Color.danger)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(Color.scorePaper, in: RoundedRectangle(cornerRadius: 8))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(Color.scorePaper, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.top, 10)
    }

    /// 光标映射：跟随引擎的小节索引 → ScoreCursor（拍级光标落在当前小节）
    private var cursor: ScoreCursor? {
        session.phase == .performing || session.phase == .counting
            ? .beat(measureIndex: session.followState.measureIndex, tickInMeasure: 0)
            : nil
    }

    private var nextMeasureLabel: some View {
        Text(session.isFreePlay
            ? "自由跟弹 · 不判分"
            : "下一小节：\(session.followState.measureIndex + 1)")
            .font(.labelMd)
            .foregroundStyle(Color.textMuted)
            .monospacedDigit()
    }

    private var progressLine: some View {
        let elapsed = session.startedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        let limit = timeLimitSec ?? 0
        let fraction = limit > 0 ? min(1, Double(elapsed) / Double(limit)) : 0
        return VStack(spacing: 4) {
            HStack {
                Text("── 当前走句进度 ──")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
                Spacer()
                Text("\(format(elapsed))\(limit > 0 ? " / \(format(limit))" : "")")
                    .font(.labelMono(11))
                    .foregroundStyle(Color.textBody)
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.borderInput).frame(height: 2)
                    RoundedRectangle(cornerRadius: 1).fill(Color.amber)
                        .frame(width: proxy.size.width * fraction, height: 2)
                }
            }
            .frame(height: 2)
        }
    }

    private func format(_ sec: Int) -> String {
        String(format: "%d:%02d", sec / 60, sec % 60)
    }

    // MARK: 四控件

    private var controlRow: some View {
        HStack(spacing: 8) {
            controlCard(icon: "metronome", label: "节拍器", value: metronomeOn ? "ON" : "OFF", highlighted: metronomeOn) {
                toggleMetronome()
            }
            controlCard(icon: "tuningfork", label: "♩=", value: "\(session.tempoState.bpm)", highlighted: false) {
                withAnimation { showTempoPanel.toggle() }
            }
            controlCard(icon: "arrow.triangle.2.circlepath", label: "循环", value: "\(session.loopConfig.startMeasure)–\(session.loopConfig.endMeasure)", highlighted: false) {
                showLoopSheet = true
            }
            controlCard(icon: "flag", label: "标记", value: session.marks.isEmpty ? "" : "\(session.marks.count)", highlighted: false) {
                showMarkSheet = true // S13b：疑似谱错标记（时间点标签随提交一并记录）
            }
        }
    }

    private func controlCard(icon: String, label: String, value: String, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                Text(label)
                    .font(.labelSm)
                Text(value)
                    .font(.labelMono(11, weight: .medium))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundStyle(highlighted ? Color.canvas : Color.textBody)
            .background(highlighted ? Color.amber : Color.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(highlighted ? Color.clear : Color.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var tempoPanel: some View {
        HStack(spacing: 16) {
            Text("♩= 步进（40–\(session.tempoState.referenceBpm)）")
                .font(.labelSm)
                .foregroundStyle(Color.textMuted)
            Button { session.changeTempo(by: -1) } label: {
                Image(systemName: "minus").frame(width: 36, height: 32)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            Button { session.changeTempo(by: 1) } label: {
                Image(systemName: "plus").frame(width: 36, height: 32)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: 播放 / 结束

    private var playButton: some View {
        Button {
            togglePlay()
        } label: {
            Image(systemName: playIcon)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.canvas)
                .frame(width: 64, height: 64)
                .background(playDisabled ? Color.borderInput : Color.amber, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(playDisabled)
        .frame(maxWidth: .infinity)
    }

    private var playIcon: String {
        session.phase == .performing || session.phase == .counting ? "stop.fill" : "play.fill"
    }

    private var playDisabled: Bool {
        !hub.isConnected && session.phase != .idle // S11b：播放/结束禁用变灰（spec）
    }

    private func togglePlay() {
        if session.phase == .idle || session.phase == .finished {
            metronome.onCountInFinished = { session.beginPerforming() }
            session.start(metronome: metronome, countIn: true)
            if metronomeOn, session.phase == .performing {
                metronome.start(bpm: session.tempoState.bpm, countInBars: 0)
            }
        } else {
            finishAndSave() // ■ 停止 = 结算
        }
    }

    private func toggleMetronome() {
        metronomeOn.toggle()
        if metronomeOn, session.phase == .performing {
            metronome.start(bpm: session.tempoState.bpm, countInBars: 0)
        } else {
            metronome.stop()
        }
    }

    private var finishButton: some View {
        Button {
            finishAndSave()
        } label: {
            Text("结束并生成报告")
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(playDisabled && session.phase != .performing)
    }

    // MARK: 收尾

    private func finishAndSave() {
        metronome.stop()
        guard session.phase == .performing || session.phase == .counting || session.timeUp else {
            dismiss()
            return
        }
        let summary = session.finish()
        _ = PracticeSession.persist(
            summary,
            taskType: taskType,
            isFreePlay: session.isFreePlay,
            startedAt: session.startedAt ?? Date(),
            interruptions: session.interruptionStarts,
            title: "",
            in: context
        )
        finishedSummary = summary
    }

    private func reconnect() {
        // 真机源：重枚举系统设备；模拟源：直接恢复连接态（S11b 验收路径）
        if hub.mode == .real {
            _ = MIDIHub.systemSourceNames()
            hub.switchSource(.real)
        } else {
            hub.simulated?.reconnect()
        }
    }

    // MARK: 加载

    private func load() {
        session.timeLimitSec = timeLimitSec
        let url: URL?
        if let scoreFile, let resolved = SandboxPaths.resolve(scoreFile.fileURL) {
            url = resolved
        } else {
            url = Bundle.main.url(forResource: "SpikeSample32", withExtension: "musicxml")
        }
        guard let url else {
            loadError = "找不到可练习的谱面文件"
            return
        }
        do {
            let score = try ScoreLoader.loadScore(contentsOf: url)
            loadedScore = score
            let expected = ScoreExpectedPitches.extract(score: score)
            session.configure(
                scoreName: displayTitle,
                expectedPerMeasure: expected,
                startBPM: 72
            )
        } catch {
            loadError = "谱面解析失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - S11b 断连覆盖态（横幅 + 遮罩卡；控件置灰由父层 playDisabled 控制）

struct S11bDisconnectedOverlay: View {
    let onReconnect: () -> Void
    let onExit: () -> Void
    @State private var showDistanceHint = false

    var body: some View {
        VStack(spacing: 0) {
            // 顶部全宽 danger 横幅
            VStack(spacing: 4) {
                HStack {
                    Circle().fill(Color.danger).frame(width: 7, height: 7)
                    Text("MIDI 已断开 · 判分已暂停")
                        .font(.bodyMd)
                        .foregroundStyle(Color.danger)
                    Spacer()
                    Button(action: onReconnect) {
                        Text("重新连接")
                            .font(.bodySm)
                            .foregroundStyle(Color.danger)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .overlay(Capsule().strokeBorder(Color.danger, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Text("重连后从断点继续，不丢音符")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showDistanceHint {
                    Text("也可以检查：琴是否休眠 / 蓝牙距离")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(Color.danger.opacity(0.14))
            .task {
                try? await Task.sleep(for: .seconds(10))
                showDistanceHint = true // 10 秒未重连追加提示（不弹 Alert）
            }

            Spacer()

            // 谱区遮罩卡（谱面隐约可见，不销毁已录 MIDI）
            VStack(spacing: 10) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.textMuted)
                Text("等待特伦斯 V70 重新连接…")
                    .font(.bodyMd)
                    .foregroundStyle(Color.textBody)
                Text("MIDI 诊断页将在「我的」批次提供")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
            .padding(28)
            .background(Color.canvas.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 40)

            Spacer()

            Button("不保存退出", action: onExit)
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .padding(.bottom, 16)
        }
        .background(Color.scrim.opacity(0.3).ignoresSafeArea())
    }
}

// MARK: - M6a take 保存占位（S13 全量报告 M6b；此处只展示真实统计）

struct M6aTakeSavedView: View {
    @Environment(\.dismiss) private var dismiss
    let summary: TakeSummary
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(Color.success)
            Text("Take 已保存")
                .font(.headlineLg)
                .foregroundStyle(Color.textPrimary)
            Text("自动保存的原始 MIDI 与统计如下；S13 全量报告在下一批次提供。")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            NocturneCard {
                VStack(alignment: .leading, spacing: 8) {
                    summaryRow("时长", "\(summary.durationSec / 60)分\(summary.durationSec % 60)秒")
                    summaryRow("音符数", "\(summary.noteCount)")
                    summaryRow("错音数（简单匹配）", "\(summary.wrongNotes.count)")
                    summaryRow("速度", "♩=\(summary.tempoAvg)")
                    summaryRow("踏板事件", "\(summary.pedalEventCount)")
                    summaryRow("MIDI 事件", "\(summary.midiEventCount)")
                    if !summary.marks.isEmpty {
                        summaryRow("标记点", "\(summary.marks.count) 处")
                    }
                }
            }
            .padding(.horizontal, 20)

            Button("完成", action: onDone)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .preferredColorScheme(.dark)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.bodyMd).foregroundStyle(Color.textBody)
            Spacer()
            Text(value).font(.labelMd).foregroundStyle(Color.textPrimary).monospacedDigit()
        }
    }
}

extension TakeSummary: Identifiable {
    public var id: Int { midiEventCount * 1_000_003 + durationSec + marks.count }
}

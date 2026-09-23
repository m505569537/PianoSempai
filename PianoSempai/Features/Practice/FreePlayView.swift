import SwiftData
import SwiftUI

// MARK: - S14 自由弹奏（不打分沙盒；进入即采 MIDI；卷帘 + 一句话 + 保存/丢弃）
//
// 视觉真值：stitch-truth/revised/S14.md（screen aa01a2dd37b3408a9c4f840957b7150e，390pt 竖版，1px = 1pt）。
// 本期只重做视觉与卷帘呈现：MIDI 采集 / 计时 / 保存（自由 take）/ 丢弃确认 / 节拍器逻辑全部沿用原实现，
// 不动 PracticeSession、Models 与其它文件。

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
    @State private var showTakes = false
    @FocusState private var noteFocused: Bool
    @State private var breathing = false
    @State private var lastHandledEventID: UUID?

    var onSaved: () -> Void // 保存后跳档案

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            cardStack
                .padding(.top, 16)

            Spacer(minLength: 0)

            footer
        }
        .padding(.horizontal, 20)
        .background(Color.canvas)
        .preferredColorScheme(.dark)
        // 历史录音：直接复用现有 take 列表（TakesListView 无参），不新建筛选视图
        .sheet(isPresented: $showTakes) {
            TakesListView()
        }
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

    // MARK: - A. 顶部导航（返回 40×40 / serif 标题 / 历史录音胶囊）

    private var header: some View {
        HStack(spacing: 0) {
            Button { exitConfirmFlow() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 24, weight: .medium))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(S14BackButtonStyle())

            Spacer(minLength: 0)

            Text("自由弹奏")
                .font(.headlineSm) // serif 20pt
                .foregroundStyle(Color.textPrimary)

            Spacer(minLength: 0)

            Button { showTakes = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16))
                    Text("历史录音")
                }
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    /// 返回钮：真值 40×40 圆钮，默认 muted，按下转琥珀 + scale .95
    private struct S14BackButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(configuration.isPressed ? Color.amber : Color.textMuted)
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    /// 底部操作钮按压反馈（真值 active:scale .98 / .97；iOS 无 hover，只留按压）
    private struct S14PressButtonStyle: ButtonStyle {
        var pressedScale: CGFloat = 0.98

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? pressedScale : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    // MARK: - 主体三卡（区块间距 16pt）

    private var cardStack: some View {
        VStack(spacing: 16) {
            rollCard
            metricsCard
            noteCard
        }
    }

    // MARK: - B. 卡① 卷帘

    private var rollCard: some View {
        VStack(spacing: 0) {
            rollCanvas

            // 安抚文案（逐字保留）：空态时即占位，弹起来后仍作为「不打分 / 仅本机」的常驻提示
            Text("随便弹，不打分 · 音符只记录在本机")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
    }

    /// 画布：满宽高 184pt、r12、底 #181513 90%、1pt #332D29 60%、p12、overflow hidden
    private var rollCanvas: some View {
        VStack(spacing: 0) {
            PianoRollView(notes: session.playedNotes, startedAt: session.startedAt)
                .frame(height: RollLayout.rollHeight)
            rollInfoRow
        }
        .padding(RollLayout.canvasPadding)
        .frame(height: RollLayout.canvasHeight)
        .background(Color.s14RollCanvas, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.border.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 画布底部信息行：顶 1pt #332D29 40% + pt8 + 10pt mono
    private var rollInfoRow: some View {
        HStack(spacing: 6) {
            if let last = session.playedNotes.last {
                Circle()
                    .fill(Color.amber)
                    .frame(width: 6, height: 6)
                // playedNotes 只有 (pitch, sec)，没有 velocity / 和弦属性——
                // 只显真实拿得到的最近音名，绝不写「力度 74 · C4 挂留」
                Text(SightReadSession.noteName(last.pitch))
                    .font(.labelMono(10))
                    .foregroundStyle(Color.textMuted)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            // MIDI 没有采样率概念，不写「44.1kHz」；无连接时显真实状态
            Text(midiStatusText)
                .font(.labelMono(10))
                .foregroundStyle(Color.s14Faint)
                .monospacedDigit()
        }
        .frame(height: 13)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Color.border.opacity(0.4)
                .frame(height: 1)
        }
    }

    private var midiStatusText: String {
        guard hub.isConnected else { return "MIDI 未连接" }
        return hub.mode == .simulated ? "模拟 MIDI IN" : "MIDI IN"
    }

    // MARK: - C. 卡② 计量条（单卡三段 + 竖分隔线）

    private var metricsCard: some View {
        HStack(spacing: 12) {
            metricGroup(title: "本次时长", value: format(sec: session.elapsedSec), valueColor: Color.textPrimary)

            Spacer(minLength: 0)
            metricDivider
            Spacer(minLength: 0)

            metricGroup(title: "音符", value: "\(session.playedNotes.count)", valueColor: Color.amber)

            Spacer(minLength: 0)
            metricDivider
            Spacer(minLength: 0)

            HStack(spacing: 6) {
                recordingDot
                Text("录制中（仅 MIDI）")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
        .onAppear {
            // 录制红点 2s 呼吸（真值 pulse-red 2s：opacity 1→.4、scale 1→.85 + 发光）
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }

    private func metricGroup(title: String, value: String, valueColor: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color.textMuted)
            Text(value)
                .font(.labelMono(14, weight: .semibold))
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
    }

    private var metricDivider: some View {
        Color.border
            .frame(width: 1, height: 12)
    }

    private var recordingDot: some View {
        Circle()
            .fill(Color.s14RecRed)
            .frame(width: 8, height: 8)
            .scaleEffect(breathing ? 0.85 : 1)
            .opacity(breathing ? 0.4 : 1)
            .shadow(color: Color.s14RecRed.opacity(0.7), radius: 6)
    }

    // MARK: - D. 卡③ 这次弹了什么（单行备忘）

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("这次弹了什么")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .tracking(0.5)
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: 8)
                Text("随想随记")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
            }

            Text("系统不会猜曲名。你可以随手记一句")
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)

            noteField
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
    }

    /// 单行输入：底 #1C1917、1pt #332D29、r12、px14 py10、12pt、聚焦边 amber 70%
    private var noteField: some View {
        TextField("", text: $noteText)
            .font(.bodySm)
            .foregroundStyle(Color.textPrimary)
            .focused($noteFocused)
            // placeholder 自绘才能上真值的 #655F58；覆盖层在 padding 之前，与输入文字左对齐
            .overlay(alignment: .leading) {
                if noteText.isEmpty {
                    Text("例如：瞎弹了一段菊次郎的夏天")
                        .font(.bodySm)
                        .foregroundStyle(Color.s14Faint)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.canvas, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(noteFocused ? Color.amber.opacity(0.7) : Color.border, lineWidth: 1)
            )
            .overlay(alignment: .trailing) {
                Image(systemName: "square.and.pencil") // edit_note 语义
                    .font(.system(size: 16))
                    .foregroundStyle(Color.s14Faint)
                    .padding(.trailing, 12)
                    .allowsHitTesting(false)
            }
    }

    // MARK: - E. 底部操作区（同一行三件）

    private var footer: some View {
        WeightedRowBox(weights: [1, 1.4, 1], gap: 12) {
            metronomeButton
            saveButton
            discardButton
        }
        .padding(.top, 12)
    }

    /// 节拍器 flex-1：r12、透明底、1pt #332D29；开启时琥珀底深字
    private var metronomeButton: some View {
        Button {
            metronomeOn.toggle()
            if metronomeOn {
                metronome.start(bpm: 80, countInBars: 0)
            } else {
                metronome.stop()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "metronome")
                    .font(.system(size: 18))
                    .foregroundStyle(metronomeOn ? Color.canvas : Color.amber)
                Text("节拍器")
                    .font(.labelMd)
                    .foregroundStyle(metronomeOn ? Color.canvas : Color.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(metronomeOn ? Color.amber : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(metronomeOn ? Color.clear : Color.border, lineWidth: 1)
            )
        }
        .buttonStyle(S14PressButtonStyle(pressedScale: 0.98))
    }

    /// 结束并保存 flex-1.4：全圆角胶囊、2pt 琥珀描边、琥珀弱底、琥珀字
    private var saveButton: some View {
        Button {
            saveTake()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "stop.circle")
                    .font(.system(size: 19))
                Text("结束并保存")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .tracking(0.5)
            }
            .foregroundStyle(Color.amber)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.amber.opacity(0.1), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.amber, lineWidth: 2))
            .shadow(color: Color.amber.opacity(0.18), radius: 16)
        }
        .buttonStyle(S14PressButtonStyle(pressedScale: 0.97))
    }

    /// 丢弃 flex-1：r12、透明底。保留 danger 红（破坏性语义，真值只在 hover 才转主色）
    private var discardButton: some View {
        Button { discardConfirm = true } label: {
            Text("丢弃")
                .font(.labelMd)
                .foregroundStyle(Color.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
        }
        .buttonStyle(S14PressButtonStyle(pressedScale: 0.98))
    }

    // MARK: - 逻辑（与原实现一致，未改）

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

// MARK: - 卷帘（固定视窗、从右向左流动；全部来自真实 playedNotes）

/// 卷帘画布内部几何（真值：画布 184pt / p12 / 24pt 网格行高 / 底部信息行）
private enum RollLayout {
    /// 画布外高（真值 h-184）
    static let canvasHeight: CGFloat = 184
    /// 画布内边距（真值 p-3）
    static let canvasPadding: CGFloat = 12
    /// 底部信息行高（1pt 发丝线 + pt8 + 10pt 行）
    static let infoRowHeight: CGFloat = 21
    /// 卷帘绘图区高 = 画布内高 - 信息行
    static var rollHeight: CGFloat { canvasHeight - canvasPadding * 2 - infoRowHeight }
    /// 横向网格线行高（真值 .piano-roll-grid 24px）
    static let gridRow: CGFloat = 24
    /// 固定视窗时长：把最近这么多秒映射进画布宽度
    static let windowSec: Double = 8
    /// 音符块淡出时长（越早触发越淡）
    static let fadeSec: Double = 3
    /// 音符块高（真值 5–6pt）
    static let noteHeight: CGFloat = 5.5
    /// playedNotes 只有 onset 没有时长 → 固定窄宽。
    /// 真值示例里的 50–110pt 宽是写死的演示数据，不套用。
    static let onsetWidth: CGFloat = 14
    /// 音高轴至少跨一个八度，避免只弹一个音时塌成一行
    static let minPitchSpan = 12
    /// 左侧音高标签最多几个
    static let maxPitchLabels = 5
}

/// 卷帘：真实 playedNotes → 固定视窗、从右向左流动的琥珀音符块（pitch → 纵向行，sec → 横向时间）。
/// 不做横向滚动：播放头钉在右侧，新音符从右侧进入、随时间左移、超出左边界被裁掉。
struct PianoRollView: View {
    let notes: [(pitch: UInt8, sec: Double)]
    let startedAt: Date?

    var body: some View {
        let axis = PitchAxis(notes: notes, height: RollLayout.rollHeight)

        ZStack(alignment: .topLeading) {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    drawGrid(in: context, size: size)
                    if let axis {
                        let now = timeline.date.timeIntervalSince(startedAt ?? timeline.date)
                        for note in notes where (0...RollLayout.windowSec).contains(now - note.sec) {
                            drawNote(note, in: context, size: size, axis: axis, now: now)
                        }
                    }
                    drawPlayhead(in: context, size: size)
                }
            }

            // 左侧音高辅助列：9pt mono #655F58，标签取真实出现过的音高（一个音都没弹时不显）
            if let axis {
                ForEach(0..<axis.ticks.count, id: \.self) { index in
                    Text(axis.ticks[index].name)
                        .font(.labelMono(9))
                        .foregroundStyle(Color.s14Faint)
                        .offset(x: 6, y: axis.ticks[index].y - 4.5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 横向网格线：1pt rgba(51,45,41,.45)，24pt 行高
    private func drawGrid(in context: GraphicsContext, size: CGSize) {
        let rows = Int((size.height / RollLayout.gridRow).rounded(.down))
        for row in 1...max(1, rows) {
            let y = CGFloat(row) * RollLayout.gridRow
            guard y < size.height else { break }
            context.fill(
                Path(CGRect(x: 0, y: y - 0.5, width: size.width, height: 1)),
                with: .color(Color.s14Grid)
            )
        }
    }

    /// 音符块：琥珀横向渐变圆角条（左淡右亮，右端即播放方向），最近触发的最亮 + 发光
    private func drawNote(
        _ note: (pitch: UInt8, sec: Double),
        in context: GraphicsContext,
        size: CGSize,
        axis: PitchAxis,
        now: Double
    ) {
        let age = max(0, now - note.sec)
        let fresh = max(0, 1 - age / RollLayout.fadeSec)
        let pxPerSec = size.width / RollLayout.windowSec
        let height = RollLayout.noteHeight
        let rect = CGRect(
            x: size.width - age * pxPerSec - RollLayout.onsetWidth,
            y: min(
                max(0, axis.rowCenter(note.pitch, height: size.height) - height / 2),
                max(0, size.height - height)
            ),
            width: RollLayout.onsetWidth,
            height: height
        )
        let radius = height / 2

        // 最近触发的发光（真值 0 0 8/12px rgba(212,162,78,.3~.6)）
        if fresh > 0.4 {
            context.fill(
                Path(roundedRect: rect.insetBy(dx: -2.5, dy: -1.5), cornerRadius: radius + 1.5),
                with: .color(Color.amber.opacity(0.18 * fresh))
            )
        }

        context.fill(
            Path(roundedRect: rect, cornerRadius: radius),
            with: .linearGradient(
                Gradient(colors: [
                    Color.amber.opacity(0.10 + 0.50 * fresh),
                    (fresh > 0.6 ? Color.s14NoteBright : Color.amber).opacity(0.55 + 0.45 * fresh),
                    Color.amber.opacity(0.80 + 0.20 * fresh)
                ]),
                startPoint: CGPoint(x: rect.minX, y: rect.midY),
                endPoint: CGPoint(x: rect.maxX, y: rect.midY)
            )
        )
    }

    /// 播放头：右侧 1pt 竖线，纵向渐变 透明 → amber 40% → 透明
    private func drawPlayhead(in context: GraphicsContext, size: CGSize) {
        let x = size.width - 0.5
        context.fill(
            Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.amber.opacity(0), location: 0),
                    .init(color: Color.amber.opacity(0.4), location: 0.5),
                    .init(color: Color.amber.opacity(0), location: 1)
                ]),
                startPoint: CGPoint(x: x, y: 0),
                endPoint: CGPoint(x: x, y: size.height)
            )
        )
    }
}

/// 音高轴：只从真实 playedNotes 取音高（禁止写死 C5/G4/C4/F3/C3）。
/// 取最低/最高 + 中间等分的真实音高做标签，标签 y 落在该音高真实所在的行上。
private struct PitchAxis {
    let lowest: Int
    let span: Int
    let ticks: [Tick]

    /// 一个音高标签：音名 + 该音高真实所在行的中心 y
    struct Tick {
        let name: String
        let y: CGFloat
    }

    init?(notes: [(pitch: UInt8, sec: Double)], height: CGFloat) {
        guard let minPitch = notes.map(\.pitch).min(),
              let maxPitch = notes.map(\.pitch).max() else { return nil }

        let low = Int(minPitch)
        let high = Int(maxPitch)
        let range = max(1, high - low + 1)
        let span = max(RollLayout.minPitchSpan, range)
        let lowestPitch = low - (span - range) / 2
        let rowHeight = height / CGFloat(span)

        self.lowest = lowestPitch
        self.span = span
        self.ticks = Self.pick(Set(notes.map(\.pitch)).sorted(), limit: RollLayout.maxPitchLabels).map { pitch in
            Tick(
                name: SightReadSession.noteName(pitch),
                y: height - (CGFloat(Int(pitch) - lowestPitch) + 0.5) * rowHeight
            )
        }
    }

    /// 音高 → 行中心 y（高音在上）
    func rowCenter(_ pitch: UInt8, height: CGFloat) -> CGFloat {
        height - (CGFloat(Int(pitch) - lowest) + 0.5) * (height / CGFloat(span))
    }

    /// 从真实音高里挑代表：最低/最高 + 中间等分（最多 limit 个，去重）
    private static func pick(_ sorted: [UInt8], limit: Int) -> [UInt8] {
        guard sorted.count > limit, limit > 1 else { return sorted }
        var picked: [UInt8] = []
        for index in 0..<limit {
            let position = Int((Double(index) * Double(sorted.count - 1) / Double(limit - 1)).rounded())
            let pitch = sorted[position]
            if picked.last != pitch { picked.append(pitch) }
        }
        return picked
    }
}

// MARK: - 权重横排（真值底部三操作：flex-1 / flex-[1.4] / flex-1）

/// SwiftUI 没有 flex-grow，用一个最小 Layout 把行内剩余宽度按权重切给子视图。
private struct WeightedRow: Layout {
    var gap: CGFloat = 12
    var weights: [CGFloat]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        CGSize(
            width: columnWidths(proposal: proposal, subviews: subviews).reduce(0, +),
            height: subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let columns = columnWidths(proposal: ProposedViewSize(bounds.size), subviews: subviews)
        var x = bounds.minX
        for index in subviews.indices {
            let width = index < columns.count ? columns[index] : 0
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + gap
        }
    }

    private func columnWidths(proposal: ProposedViewSize, subviews: Subviews) -> [CGFloat] {
        guard !weights.isEmpty, !subviews.isEmpty else { return [] }
        let total = weights.reduce(0, +)
        guard total > 0, let available = proposal.width else {
            return subviews.map { $0.sizeThatFits(.unspecified).width }
        }
        let usable = max(0, available - gap * CGFloat(subviews.count - 1))
        return subviews.indices.map { usable * weights[min($0, weights.count - 1)] / total }
    }
}

/// WeightedRow 的 View 包装（Layout 的 callAsFunction 只接内容闭包，权重经本类传入）
private struct WeightedRowBox<Content: View>: View {
    private let layout: WeightedRow
    private let content: Content

    init(weights: [CGFloat], gap: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.layout = WeightedRow(gap: gap, weights: weights)
        self.content = content()
    }

    var body: some View {
        layout { content }
    }
}

// MARK: - S14 真值字面量色（DesignSystem token 未覆盖的真值 hex，仅本文件使用）

fileprivate extension Color {
    /// hex → sRGB（S14 真值局部色专用）
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// 卷帘画布底 #181513（真值 90% 不透明）
    static let s14RollCanvas = Color(hex: 0x181513, opacity: 0.9)
    /// 录制红点 #E5484D（真值呼吸点；Color.danger 是 #C97064，不同，故用字面量）
    static let s14RecRed = Color(hex: 0xE5484D)
    /// 最近触发音符块中段亮色 #F5E1B5
    static let s14NoteBright = Color(hex: 0xF5E1B5)
    /// 卷帘横向网格线 rgba(51,45,41,.45)
    static let s14Grid = Color(hex: 0x332D29, opacity: 0.45)
    /// 弱文字 #655F58（音高标签 / placeholder / MIDI IN）
    static let s14Faint = Color(hex: 0x655F58)
}

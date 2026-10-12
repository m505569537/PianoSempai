import SheetMusicCore
import SheetMusicLoader
import SheetMusicUI
import SwiftData
import SwiftUI

// MARK: - S11 全屏练习室（+S11b 断连态；S12 循环 sheet；M6a 版）
// +Stage B-2：示范卡（B4）/ 光标仲裁（B5）/ onDisappear teardown（B6）/
//  performing 中拒绝示范（B7）/ 断连仍可听的「示范播放中」pill（B8）。
// +S11 Stage B（对齐 Stitch 真值 65f044723e6a4fb8aba32ec46412075e）：
//  三段式顶栏（Neko+MIDI pill / serif 标题 / 关闭即结算）/ 纸张卡 / 五格合一控件坞 /
//  56pt 暂停·继续圆钮（session.pause()/resume()，暂停时间不计入 take）。
// +S11b Stage（对齐 Stitch 真值 d141b071ee7343a1b086da9995c5c891，以 code.html 为准）：
//  断连三段式顶栏（返回 / serif 真实数据标题 / 未连接脉冲胶囊 + smart_toy）＋ 实底重连横幅 ＋
//  只盖谱纸卡的 #1C1917/75 模糊遮罩（不再全屏压暗：顶栏重连钮与底部诊断卡必须保持可点）＋
//  五格控件坞就地禁用（保持原色）＋ 全宽禁用主钮 ＋ MIDI 诊断卡。
//  诚实范围：真值断连坞的「预备拍/双手」两格 App 没有对应功能，不造假控件——沿用五格坞禁用。
// 零打断（spec）：错音/慢全程无 Alert；时间到自动保存。

struct PracticeRoomView: View {
    let taskType: String // warmup / main / reward
    var scoreFile: ScoreFile?
    var pieceTitle: String = ""
    var timeLimitSec: Int? = nil
    /// 显式示例曲入口（M5a：数据标记；M5b：三态谱加载 + 示例曲文案）
    var isSampleEntry: Bool = false
    /// 所属曲目（M5b：落 take.pieceId + 触发分析/过关判定；内置教材由 CourseEngine 建档）
    var piece: Piece? = nil
    /// 参考速度（分析用；0 = 回落 piece.referenceTempo）
    var referenceTempo: Int = 0
    /// 内置公版谱坐标（拜厄/哈农）：与 scoreFile 二选一，走 BundledScore 定位
    var bundledBook: String? = nil
    var bundledNumber: Int = 0
    /// G3 Stage B 矫正进房 / P12+C5 曲库专项循环：进房即锁定的 hotspot 循环区间（0-based，同 TakeAnalysis 口径）。
    /// nil = 普通进房不锁定；[] = 整曲级（区间回退整曲 1…total）。
    /// 写入口径见 lockedLoopRange(initialHotspots:totalMeasures:)。
    var initialHotspots: [Int]? = nil
    /// G3 Stage B 矫正进房：初始速度比（CorrectionEngine.initialTempoRatio；nil = 默认 72）。
    var initialTempoRatio: Double? = nil
    /// G3 Stage B 矫正进房：对应处方（练完一遍即完成回写用；非矫正进房 nil）。
    var correction: CorrectionPrescription? = nil
    /// G5 Stage B 铺路进房：对应铺路卡（练完一遍回写完成用；非铺路进房 nil）。
    var paving: RewardPavingCard? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var hub = MIDIHub.shared
    @StateObject private var session = PracticeSession()
    @State private var metronome = MetronomeService()
    /// 整曲示范播放（Stage A 服务）：控制坞第 5 格 / B5 光标 / B6 teardown / B8 pill。
    /// 与主圆钮（▶ 开始 / ⏸ 暂停·继续判分）完全无关，两套语义不混。
    @State private var demo = DemoPlaybackService()

    @State private var loadedScore: Score?
    @State private var loadError: String?
    /// 每行小节数（0=自动；全局显示偏好，谱面滚动视图据此重排）。
    @AppStorage(ScoreDisplayPrefs.measuresPerLineKey) private var measuresPerLine = 0
    @State private var metronomeOn = false
    @State private var showLoopSheet = false
    @State private var finishedSummary: TakeSummary?
    @State private var exitConfirm = false
    @State private var showNekoChat = false
    @State private var lastHandledEventID: UUID?
    @State private var showMarkSheet = false
    /// 「识别中」翠绿呼吸点（真值 §6.2）：1.2s opacity 1↔0.35 往复。
    @State private var recognitionPulse = false
    /// S11b：「未连接」胶囊圆点脉冲（真值 §3）：2s opacity 0.9↔0.45、scale 1↔1.15 往复。
    @State private var disconnectedPulse = false
    /// S11b 诊断卡入口（真值 §7）：弹出已存在的 S24 MidiDiagnosticsView。
    @State private var showMidiDiagnostics = false
    /// S11b 顶栏 hover（真值 §3：返回 hover→main、smart_toy hover→琥珀）。
    /// iPhone 触摸下不触发；仅 iPad/触控板指针环境生效。
    @State private var hoverBack = false
    @State private var hoverNeko = false
    /// Stage B §2a：今日/聚合入口外部不传 piece 的懒解析结果（load() 里落值）。
    /// 曲库详情页已传 piece 时不参与，行为不变。
    @State private var resolvedPiece: Piece?
    /// take 归属用条目：外部显式传入优先，否则用懒解析结果。
    private var effectivePiece: Piece? { piece ?? resolvedPiece }

    private var totalMeasures: Int { loadedScore.map(ScoreExpectedPitches.measureCount) ?? 0 }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                // S11b：断连是另一套版面（真值 §2：横幅 / 遮罩谱卡 / 禁用控件 / 诊断卡），
                // 与连接态共用同一张纸张谱卡，不搞两套谱面实现。
                if hub.isConnected {
                    header
                    connectedColumn
                } else {
                    disconnectedHeader
                    disconnectedColumn
                }
            }
            .background(Color.canvas)

            // B8：「示范播放中」pill —— MIDI 断连不停示范（S11b 只暂停判分）。
            // 断连遮罩只盖谱纸卡（不再全屏压暗），这个指示照旧压在最上层、实底 + 琥珀描边保证可读。
            if demo.state == .playing {
                VStack(spacing: 0) {
                    demoPill
                    Spacer(minLength: 0)
                }
                .padding(.top, 56)
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
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showLoopSheet) {
            S12LoopSettingsSheet(
                session: session,
                totalMeasures: totalMeasures,
                // P13：卡 1 右注带真实曲名；「练习」是无名时的占位回退，映射回空串
                // （sheet 侧空串只显小节数，不冒充具体曲名）
                pieceTitle: displayTitle == "练习" ? "" : displayTitle,
                // G2：当前曲目最近一次判分的错误热点（0-based）；sheet 惰性构建，每次打开现取最新。
                // 无曲目/无判分数据 → 空数组，「错误热点」chip 保持禁用。
                hotspotMeasures: LoopService.latestHotspotMeasures(
                    pieceId: effectivePiece?.entityId,
                    takes: (try? context.fetch(FetchDescriptor<Take>())) ?? [],
                    analyses: (try? context.fetch(FetchDescriptor<TakeAnalysis>())) ?? []
                )
            )
        }
        .sheet(isPresented: $showMidiDiagnostics) {
            // S11b 诊断卡入口（真值 §7）：S24 诊断页本身已存在，断连态同样可用。
            MidiDiagnosticsView()
        }
        .sheet(isPresented: $showMarkSheet) {
            S13bMarkSheet(
                scoreName: displayTitle,
                measure: session.followState.measureIndex + 1
            ) { type, note, includeWithNeko in
                context.insert(ScoreErrorMark(
                    scoreName: displayTitle,
                    measure: session.followState.measureIndex + 1,
                    type: type,
                    note: note,
                    includeWithNeko: includeWithNeko
                ))
                session.addMark() // 时间点标签
            }
        }
        .fullScreenCover(item: $finishedSummary) { summary in
            M6aTakeSavedView(summary: summary, onDone: { dismiss() })
        }
        .fullScreenCover(isPresented: $showNekoChat) {
            // 练习中自由问答（不带未保存的实时数据，避免假数据）
            ChatView(mode: .freeform, context: context)
        }
        .onAppear(perform: load)
        // B6：节拍器与示范音都必须收尾。左上返回也走这里——不留后台音频图。
        //（teardown 必须显式调：deinit 到不了 @MainActor 的 DemoPlaybackService.teardown()）
        .onDisappear { metronome.stop(); demo.teardown() }
        .onReceive(hub.$events) { _ in
            // 只处理未消费过的新事件（订阅/复现会重放当前数组）
            guard let last = hub.events.last, last.id != lastHandledEventID else { return }
            lastHandledEventID = last.id
            session.handle(last)
        }
        .onChange(of: hub.isConnected) { _, connected in
            session.setConnected(connected)
        }
        .onChange(of: session.tempoState.bpm) { _, _ in
            // 任何途径改了房间 BPM（步进/自适应），示范也实时跟随。
            syncDemoSettings()
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

    // MARK: 内容列（连接态 / 断连态各一套版面，共用谱卡）

    /// 连接态内容列（S11 Stage B，不变）：纸张卡（弹性高度）｜下一小节｜进度｜五格坞｜56pt 圆钮。
    /// 保持上一批已验收的 20pt 左右留白。
    private var connectedColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            scoreArea
            nextMeasureLabel.padding(.top, 6)
            progressLine.padding(.top, 10)
            controlDock.padding(.top, 16)
            playRow.padding(.top, 18)
        }
        .padding(.horizontal, 20)
    }

    /// 断连态内容列（真值 §2 顺序）：重连横幅 → 带遮罩的谱纸卡（弹性）→ 禁用五格坞 →
    /// 全宽禁用主钮 → MIDI 诊断卡。px12 与顶栏对齐；谱卡吃掉剩余高度，底部留 12pt 呼吸
    /// （外层未 ignoresSafeArea，home indicator 安全区由系统让位）。
    private var disconnectedColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            reconnectBanner
                .padding(.top, 8)
            // scoreArea 自带 .padding(.top, 10)，正好当真值 gap10 用，不重复加。
            scoreArea
            // 五格坞就地禁用：保持原色，只剥夺交互（真值 §6.1 明确不用 opacity .4）。
            controlDock
                .disabled(true)
                .padding(.top, 10)
            disconnectedPlayButton
                .padding(.top, 8)
            diagnosticsCard
                .padding(.top, 10)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    // MARK: 头部（S11 Stage B：真值 §3 三段式）

    /// 三段式顶栏：左 Neko 幽灵钮 + MIDI pill｜中 serif 标题 + 真实数据副行｜右关闭钮。
    /// 容器：dark #1C1917 ~95% + backdrop blur，底边 1pt white/5 发丝线，内容 px14、垂直居中。
    private var header: some View {
        HStack(spacing: 8) {
            nekoPill
            midiPill
            Spacer(minLength: 8)
            headerTitle
            Spacer(minLength: 8)
            // TODO: equalizer (mix) — pending product
            closeButton
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .background(Color.canvas.opacity(0.95))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
        }
    }

    /// 问 Neko 幽灵钮（真值：全圆角、bg white/5、1pt white/10 边、琥珀猫形 + serif 11pt）。
    /// 行为不变：打开练习中自由问答（不带未保存的实时数据，避免假数据）。
    private var nekoPill: some View {
        Button {
            showNekoChat = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cat")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.amber)
                Text("问 Neko")
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(Color.textPrimary.opacity(0.9))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// MIDI 已连接 pill：纯状态展示（是否进 S24 诊断待产品确认，故不做成按钮、不留死按钮）。
    private var midiPill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.amber)
                .frame(width: 6, height: 6)
            Text("MIDI 已连接")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.amber.opacity(0.9))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.amber.opacity(0.25), lineWidth: 1))
    }

    /// 中：serif 14pt semibold 曲名（tracking wide）+ 10pt muted 真实数据副行。
    private var headerTitle: some View {
        VStack(spacing: 1) {
            Text(displayTitle)
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .tracking(0.5)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Text(headerSubtitle)
                .font(.system(size: 10))
                .foregroundStyle(Color.textMuted)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    /// 副行只用真实数据：循环区间（loopConfig 已按总小节数钳制）+ 房间 BPM +（有目标遍数时）遍数进度。
    /// 谱还没加载好时区间谈不上，只给 BPM——不编造小节号。
    private var headerSubtitle: String {
        Self.headerSubtitleText(
            scoreLoaded: loadedScore != nil,
            startMeasure: session.loopConfig.startMeasure,
            endMeasure: session.loopConfig.endMeasure,
            completedLoopCount: session.completedLoopCount,
            targetLoopCount: session.loopConfig.targetLoopCount,
            bpm: session.tempoState.bpm
        )
    }

    /// 顶栏副行文案（纯函数，可单测；视图只喂真实数据）：
    /// 谱已加载才给「区间」，BPM 恒在；仅当 targetLoopCount > 0 时追加「完成/目标 遍」。
    /// 无目标遍数 → 不出现「遍」字，文案与加此功能前逐字一致。
    static func headerSubtitleText(
        scoreLoaded: Bool,
        startMeasure: Int,
        endMeasure: Int,
        completedLoopCount: Int,
        targetLoopCount: Int,
        bpm: Int
    ) -> String {
        var parts: [String] = []
        if scoreLoaded {
            parts.append("\(startMeasure)–\(endMeasure) 小节")
        }
        parts.append("♩=\(bpm)")
        if let progress = loopProgressText(completedLoopCount: completedLoopCount, targetLoopCount: targetLoopCount) {
            parts.append("\(progress) 遍")
        }
        return parts.joined(separator: " · ")
    }

    /// 遍数进度文案（纯函数，可单测）：「完成/目标」，如 "3/5"。
    /// targetLoopCount <= 0 = 无目标 → nil，顶栏与循环格 badge 都不显示（不造假进度）。
    static func loopProgressText(completedLoopCount: Int, targetLoopCount: Int) -> String? {
        guard targetLoopCount > 0 else { return nil }
        return "\(completedLoopCount)/\(targetLoopCount)"
    }

    /// 进房即锁定的循环区间（纯函数，可单测；G3 矫正进房与 P12/C5 曲库「只练错误热点」/
    /// 「针对问题小节发起专项循环」共用同一条写入口径）。
    /// initialHotspots = nil → nil：普通进房不锁区间，loopConfig 保持默认（1–8，无谱时再诚实收窄）。
    /// 非空 → CorrectionEngine.initialLoopRange 包围盒 + 钳制（0-based hotspot → 1-based 区间，
    /// 空数组 = 整曲级 1…total，同 ADR-0005 决策二）。
    /// 钳制结果不合法（start ≥ end，只有 totalMeasures < 2 时出现）→ nil：
    /// 不把 (1,1) 这种空区间写进 loopConfig（谱面只有 1 小节时谈不上循环，诚实不锁）。
    static func lockedLoopRange(initialHotspots: [Int]?, totalMeasures: Int) -> (start: Int, end: Int)? {
        guard let hotspots = initialHotspots else { return nil }
        let range = CorrectionEngine.initialLoopRange(hotspots: hotspots, totalMeasures: totalMeasures)
        return range.start < range.end ? range : nil
    }

    /// 右：关闭钮（真值：28pt 圆、bg white/4、18pt muted X）。
    /// 演奏中（含预备拍 / 暂停）先弹退出确认——「结束并保存」即结算与报告入口
    /// （替代已移除的独立「结束并生成报告」按钮）；其余态直接 dismiss。
    private var closeButton: some View {
        Button {
            switch session.phase {
            case .performing, .counting, .paused:
                exitConfirm = true
            case .idle, .finished:
                dismiss()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.textMuted)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.04), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var displayTitle: String {
        if !pieceTitle.isEmpty { return pieceTitle }
        return scoreFile?.title ?? "练习"
    }

    /// 已进入练习室后的「等待重连」文案（谱纸卡遮罩居中卡用）。
    /// 红线 2：模拟源永不冒充真机 V70。`MIDIDeviceLabel.waitingText(.disconnected)` 恒返回 V70，
    /// 故这里按当前 mode 分派到对应标签态，仍整套复用 MIDIDeviceLabel 的文案来源（不硬编码设备名）。
    private var waitingText: String {
        let state: MIDIDeviceLabel.State = hub.mode == .simulated ? .simulatedConnected : .disconnected
        return MIDIDeviceLabel.waitingText(for: state)
    }

    /// 断连三段式顶栏（真值 §3）：左返回｜中 serif 标题（真实数据）＋ Take 副行｜
    /// 右「未连接」脉冲胶囊 ＋ smart_toy。容器 px12、pt16/pb8，底边 1pt #332D29/60 发丝线。
    /// 断连时整套替换正常 header（只有一套顶栏，不做半透明横幅叠层）。
    private var disconnectedHeader: some View {
        HStack(spacing: 8) {
            disconnectedBackButton
            Spacer(minLength: 8)
            disconnectedHeaderTitle
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                disconnectedCapsule
                disconnectedNekoButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.s11CardBorder.opacity(0.6))
                .frame(height: 1)
        }
    }

    /// 左：36×36 圆角 8 返回钮。glyph 用 chevron.left（SF Symbols 没有 arrow_back_ios_new），
    /// 字号按 36pt 热区的视觉重量取 17pt；hover→main。行为不变：走退出确认（exitConfirm）。
    private var disconnectedBackButton: some View {
        Button {
            exitConfirm = true
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(hoverBack ? Color.textPrimary : Color.textMuted)
                .frame(width: 36, height: 36)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hoverBack = $0 }
    }

    /// 中：serif 14pt medium 单行居中截断（max 190）＋ 10pt muted 副行。
    /// 标题只用真实数据：曲名 ＋（有谱才有的）循环区间 ＋ 房间 BPM；不编造小节号。
    private var disconnectedHeaderTitle: some View {
        VStack(spacing: 1) {
            Text(disconnectedHeaderTitleText)
                .font(.system(size: 14, weight: .medium, design: .serif))
                .tracking(-0.2) // tracking-tight
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
            Text(PracticeStatusSubtitle.text(phase: session.phase))
                .font(.system(size: 10))
                .foregroundStyle(Color.textMuted)
                .tracking(0.8) // tracking-wider
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 190)
    }

    /// 断连顶栏标题（真值 §3：「拜厄 45 · 17–24小节 · ♩=60」）：谱未加载好时不给区间。
    private var disconnectedHeaderTitleText: String {
        var parts = [displayTitle]
        if loadedScore != nil {
            parts.append("\(session.loopConfig.startMeasure)–\(session.loopConfig.endMeasure)小节")
        }
        parts.append("♩=\(session.tempoState.bpm)")
        return parts.joined(separator: " · ")
    }

    /// 右：「未连接」胶囊（真值 §3）——bg #3A2522/80、1pt #C97064/50 边、全圆角；
    /// 1.5pt 圆点 2s 脉冲（opacity 0.9↔0.45、scale 1↔1.15）＋ 11pt medium #E8A59E 文案。
    private var disconnectedCapsule: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.danger) // #C97064
                .frame(width: 6, height: 6)
                .scaleEffect(disconnectedPulse ? 1.15 : 1)
                .opacity(disconnectedPulse ? 0.45 : 0.9)
            Text("未连接")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.s11DangerText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Color.s11DangerContainer.opacity(0.8), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.danger.opacity(0.5), lineWidth: 1))
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                disconnectedPulse = true
            }
        }
    }

    /// 右：smart_toy 位（32×32 圆角 8，19pt muted，hover→琥珀）。语义不变：问 Neko。
    /// SF Symbols 无 smart_toy 对应字形，沿用 App 既有的 Neko 猫形 glyph。
    private var disconnectedNekoButton: some View {
        Button {
            showNekoChat = true
        } label: {
            Image(systemName: "cat")
                .font(.system(size: 16))
                .foregroundStyle(hoverNeko ? Color.amber : Color.textMuted)
                .frame(width: 32, height: 32)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hoverNeko = $0 }
    }

    // MARK: S11b 断连态组件（真值 d141b071ee7343a1b086da9995c5c891）

    /// ② 重连横幅（真值 §4）：实底 #3A2522 ＋ 1pt #C97064/40 边、圆角 12、p12；
    /// 右下 #C97064/10 柔光斑（pointer-events-none，不挡重连钮）。主行 gap8：28×28 图标盒 ＋
    /// 13pt 标题 ＋ 实底 #C97064 全圆角「重新连接」（白字 11pt ＋ refresh）→ 既有 reconnect()。
    private var reconnectBanner: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash") // 真值 bluetooth_disabled；SF Symbols 无对应字形
                    .font(.system(size: 18))
                    .foregroundStyle(Color.s11DangerText)
                    .frame(width: 28, height: 28)
                    .background(Color.danger.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                Text("MIDI 已断开 · 判分已暂停")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .tracking(0.3) // tracking-wide
                Spacer(minLength: 8)
                Button(action: reconnect) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("重新连接")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.danger, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Text("已弹奏的内容保留在本次 take，重连后从断点继续，不丢音符。")
                .font(.system(size: 11))
                .foregroundStyle(Color.s11DangerText.opacity(0.9))
                .lineSpacing(3) // leading-relaxed
                .padding(.top, 6)
                .padding(.leading, 36) // 与主行标题文字左对齐（28 图标盒 + gap8）
        }
        .padding(12)
        .background(Color.s11DangerContainer, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.danger.opacity(0.4), lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            // 环境光斑（真值：-right24 -bottom24、96×96、#C97064/10、blur-xl）
            Circle()
                .fill(Color.danger.opacity(0.1))
                .frame(width: 96, height: 96)
                .blur(radius: 24)
                .offset(x: 24, y: 24)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12)) // overflow-hidden：光斑不出容器
    }

    /// ③ 全宽禁用主钮（真值 §6.2，替代 S11 的 56pt 圆钮）：py12、圆角 12、bg #262220、
    /// 1pt #332D29 边；14pt serif muted 文案 ＋ 18pt lock 图标，gap8；.disabled(true)。
    private var disconnectedPlayButton: some View {
        // 断连态无可执行动作：不 fabricate 任何「强制开始/结束」入口，只做禁用展示。
        Button(action: {}) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill") // 真值 lock_clock；SF Symbols 无对应字形
                    .font(.system(size: 18, weight: .medium))
                Text("练习已暂停 (等待设备)")
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .tracking(0.5)
            }
            .foregroundStyle(Color.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.s11CardBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(true)
    }

    /// ④ 诊断提示卡（真值 §7）：bg #262220、1pt #332D29 边、圆角 12、p12，两端对齐。
    /// 左：16pt 琥珀 info ＋ 排查文案；右：12pt 琥珀文字钮 → S24 MidiDiagnosticsView（断连可用）。
    private var diagnosticsCard: some View {
        HStack(spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.amber)
                    .padding(.top, 2)
                Text("提示：检查蓝牙是否被其他设备占用；USB 线可直接插上替代蓝牙。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
                    .lineSpacing(3)
            }
            Button {
                showMidiDiagnostics = true
            } label: {
                Text("打开 MIDI 诊断 →")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.amber)
                    .fixedSize()
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.s11CardBorder, lineWidth: 1))
    }

    /// ② 谱纸卡遮罩（真值 §5.3）：只盖谱纸卡（不是全屏）——#1C1917/75 ＋ 细背景模糊，
    /// 圆角贴合纸卡 16；居中 48pt 圆徽（#262220 ＋ 琥珀/40 边 ＋ 24pt 琥珀 pause）＋
    /// serif 主文（设备名走 MIDIDeviceLabel，不硬编码 V70）＋ 11pt muted 副文。
    /// 断点行只用真实数据：session.followState.measureIndex（无谱时不显示，不编造小节号）。
    private var disconnectedScoreMask: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.card)
                    .frame(width: 48, height: 48)
                Circle()
                    .strokeBorder(Color.amber.opacity(0.4), lineWidth: 1)
                    .frame(width: 48, height: 48)
                Image(systemName: "pause.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.amber)
            }
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            Text(waitingText)
                .font(.system(size: 14, weight: .medium, design: .serif))
                .foregroundStyle(Color.textPrimary)
                .tracking(0.3)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            Text("保持琴盖开启并靠近手机")
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            if loadedScore != nil {
                Text("断点：第 \(session.followState.measureIndex + 1) 小节 · 已保留")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.amber)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 两层背景：material 沉到最底层去模糊谱面，75% 暗色盖在它上面压暗
        // （chain 顺序反了会让实色挡在 material 之前、把可模糊的内容吃掉）。
        .background(Color.canvas.opacity(0.75))
        .background(.ultraThinMaterial)
        // 圆角贴合纸卡 16：遮罩铺满纸卡矩形Bounds，必须裁掉四角才不冒尖。
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // 纯展示层：不接触摸，谱面在遮罩下仍可滚动查看（断点在哪一眼能看到）。
        .allowsHitTesting(false)
    }

    // MARK: 谱区（真实引擎渲染）

    private var scoreArea: some View {
        Group {
            if let loadedScore {
                PracticeScoreScrollView(
                    score: loadedScore,
                    measuresPerLine: measuresPerLine,
                    cursor: cursor,
                )
                // 弹性高度：谱区填满底部控件以上的全部可用空间（问题5），
                // 不再写死屏高 0.42；外层 VStack 的 Spacer 让位给这里。
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                Text(loadError)
                    .font(.bodySm)
                    .foregroundStyle(Color.danger)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(12)
        // S11 Stage B 纸张卡（真值 §4）：#FBF8F2 / 圆角 16 / 1pt #EBE4D5 / 强阴影。
        // 高度沿用上一批已验收的弹性（maxHeight .infinity），不写死真值的 min480/max520。
        // 颗粒层按 brief 可选项省略；真实 cursor/自动滚动原样不动（不编造小节框坐标）。
        .background(Color.s11Paper, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.s11PaperBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
        // S11b：断连时只把遮罩盖在这张纸卡上（真值 §5.3），不动顶栏/控件/诊断卡的热区。
        // Fix：遮罩是「谱」的 overlay——无谱时（ProgressView / 真实 loadError）绝不盖住。
        .overlay {
            if !hub.isConnected, loadedScore != nil {
                disconnectedScoreMask
            }
        }
        .padding(.top, 10)
        .overlay(alignment: .topTrailing) {
            if loadedScore != nil {
                // 断连态谱卡被遮罩「冻结」，右上角布局菜单一并禁用（保持原色、不响应）。
                layoutMenu
                    .disabled(!hub.isConnected)
                    .padding(10)
            }
        }
    }

    /// 每行小节数选择（问题4）。右上角轻量 Menu，不占控制卡名额；当前档显示在文字里。
    private var layoutMenu: some View {
        Menu {
            ForEach(ScoreDisplayPrefs.choices, id: \.self) { choice in
                Button {
                    measuresPerLine = choice
                } label: {
                    HStack {
                        Text(ScoreDisplayPrefs.label(for: choice))
                        if choice == measuresPerLine {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.split.3x1")
                Text(ScoreDisplayPrefs.label(for: measuresPerLine))
            }
            .font(.labelSm)
            .foregroundStyle(Color.textBody)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.cardElevated.opacity(0.88), in: Capsule())
        }
    }

    /// 光标仲裁（B5，优先级从高到低）：
    /// 1. 示范正在播放 → 引擎的 `.item(ScoreItemID)` 级光标（和弦级，比跟弹光标更细）；
    /// 2. 否则练习 performing/counting → 维持原 `.beat(...)`（拍级，落在当前小节）；
    /// 3. 否则 nil。
    /// 示范 paused 时不再跟踪 demo 光标（只在 playing 时跟），避免谱面停在一个误导光标上。
    private var cursor: ScoreCursor? {
        if demo.state == .playing, let demoCursor = demo.currentCursor {
            return demoCursor
        }
        if session.phase == .performing || session.phase == .counting {
            return .beat(measureIndex: session.followState.measureIndex, tickInMeasure: 0)
        }
        return nil
    }

    /// 示范 HUD 用光标：播放与暂停都保留（暂停时仍显示停在第几小节）；其余态为 nil。
    /// 注意与 `cursor`（只在 playing 时跟、用于谱面光标/滚动）区分——这里是给文案读的。
    private var demoHudCursor: ScoreCursor? {
        (demo.state == .playing || demo.state == .paused) ? demo.currentCursor : nil
    }

    private var nextMeasureLabel: some View {
        if let demoHudCursor {
            // 示范中：跟随示范光标所在小节（1-based）。
            return Text("下一小节：\(demoHudCursor.measureIndex + 1)")
                .font(.labelMd)
                .foregroundStyle(Color.textMuted)
                .monospacedDigit()
        }
        return Text(session.isFreePlay
            ? "自由跟弹 · 不判分"
            : "下一小节：\(session.followState.measureIndex + 1)")
            .font(.labelMd)
            .foregroundStyle(Color.textMuted)
            .monospacedDigit()
    }

    private var progressLine: some View {
        let elapsed: Int
        let fraction: Double
        if demoHudCursor != nil {
            // 示范中：时间=示范已播放秒；进度条按示范总时长填充。
            elapsed = max(0, Int(demo.currentTimeSeconds))
            let total = demo.totalTimeSeconds
            fraction = total > 0 ? min(1, demo.currentTimeSeconds / total) : 0
        } else {
            elapsed = session.elapsedSec
            let limit = timeLimitSec ?? 0
            fraction = limit > 0 ? min(1, Double(elapsed) / Double(limit)) : 0
        }
        let limit = timeLimitSec ?? 0
        return VStack(spacing: 4) {
            HStack {
                Text("── 当前走句进度 ──")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
                Spacer()
                Text("\(format(elapsed))\(demoHudCursor == nil && limit > 0 ? " / \(format(limit))" : "")")
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

    // MARK: 控件坞（S11 Stage B：真值 §6.1 —— 五个功能合成同一个坞）

    /// 一个坞、五格（真值 grid-cols-5）：节拍器 / 速度（内嵌 −＋ 步进）/ 循环 / 标记 / 示范。
    /// 五个既有功能一个不少，逐个仍走原路径（就地开关 / 开 S12 / 开 S13b / toggleDemo）。
    private var controlDock: some View {
        HStack(spacing: 5) {
            dockCell(
                icon: "metronome",
                label: "节拍器",
                value: metronomeOn ? "ON" : "OFF",
                valueColor: metronomeOn ? Color.amber : Color.textMuted,
                highlighted: metronomeOn,
                dot: metronomeOn,
                action: toggleMetronome
            )
            // P5：预备拍控件格（坞内第 2 格，紧邻节拍器）。逻辑已有（LoopConfig.countIn +
            // MetronomeService.countInBars），只差 UI  expose。
            dockCell(
                icon: "hourglass",
                label: "预备拍",
                value: session.loopConfig.countIn ? "ON" : "OFF",
                valueColor: session.loopConfig.countIn ? Color.amber : Color.textMuted,
                highlighted: session.loopConfig.countIn,
                action: { session.loopConfig.countIn.toggle() }
            )
            tempoCell
            dockCell(
                icon: "repeat",
                label: "循环",
                value: session.loopConfig.cellLabel(totalMeasures: totalMeasures) ?? "",
                valueColor: loopActive ? Color.amber : Color.textMuted,
                highlighted: loopActive,
                // 目标遍数 badge（P1）：仅 target>0 时显示「完成/目标」，如 3/5；无目标不占位
                badge: Self.loopProgressText(
                    completedLoopCount: session.completedLoopCount,
                    targetLoopCount: session.loopConfig.targetLoopCount
                ),
                action: { if loadedScore != nil { showLoopSheet = true } } // S12：段落循环设置（需有谱）
            )
            dockCell(
                icon: "flag",
                label: "标记",
                value: session.marks.isEmpty ? "" : "\(session.marks.count)",
                valueColor: Color.textMuted,
                highlighted: false,
                action: { showMarkSheet = true } // S13b：疑似谱错标记（时间点标签随提交一并记录）
            )
            dockCell(
                icon: "speaker.wave.2",
                label: "示范",
                value: demoCardValue,
                valueColor: demo.state == .playing ? Color.amber : Color.textMuted,
                highlighted: demo.state == .playing,
                action: toggleDemo
            )
        }
        .padding(6)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.s11DockBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
    }

    /// 坞内一格（真值：圆角 12；未激活 bg white/3 + 1pt white/5；激活 bg amber/10 + 1pt amber/70）。
    /// 普通按钮 + contentShape 保证整格可点；按压缩放交给 buttonStyle 默认按下反馈。
    /// badge：标题行右侧的小进度标（循环格的「完成/目标」遍数），nil = 不显示——其余四格不传。
    private func dockCell(
        icon: String,
        label: String,
        value: String,
        valueColor: Color = Color.textMuted,
        highlighted: Bool,
        dot: Bool = false,
        badge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .overlay(alignment: .topTrailing) {
                        if dot {
                            // 真值 §6.1：节拍器开启时图标右上角 1.5pt 琥珀小圆点
                            Circle()
                                .fill(Color.amber)
                                .frame(width: 6, height: 6)
                                .offset(x: 5, y: -5)
                        }
                    }
                // 标题行：label +（有目标遍数时）badge。badge 用 labelSm/textMuted 既有 token，不引新色
                HStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 11, weight: highlighted ? .semibold : .medium))
                    if let badge {
                        Text(badge)
                            .font(.labelSm)
                            .monospacedDigit()
                            .foregroundStyle(Color.textMuted)
                    }
                }
                Text(value)
                    .font(.labelMono(8.5, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(valueColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(highlighted ? Color.amber : Color.textBody)
            .background(
                highlighted ? Color.amber.opacity(0.10) : Color.white.opacity(0.03),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12).strokeBorder(
                    highlighted ? Color.amber.opacity(0.7) : Color.white.opacity(0.05),
                    lineWidth: 1
                )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// 速度格（真值 §6.1 #1：非按钮，内嵌 −/值/＋ 三段步进器）。
    /// 取代旧 tempoPanel 弹层：步进直接改房间 BPM，示范经 onChange(tempoState.bpm) 实时跟随。
    private var tempoCell: some View {
        VStack(spacing: 3) {
            Text("速度")
                .font(.system(size: 10))
                .foregroundStyle(Color.textMuted)
            HStack(spacing: 3) {
                tempoStepButton(symbol: "minus") { session.changeTempo(by: -1) }
                Text("\(session.tempoState.bpm)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .monospacedDigit()
                    .frame(minWidth: 13)
                    .minimumScaleFactor(0.7)
                tempoStepButton(symbol: "plus") { session.changeTempo(by: 1) }
            }
            Text("♩ 拍/分")
                .font(.system(size: 8.5))
                .foregroundStyle(Color.textMuted.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
    }

    /// 速度格内的 20pt 步进钮（真值：圆角 4、bg white/5）。
    private func tempoStepButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.textMuted)
                .frame(width: 20, height: 20)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 循环格激活态：区间真实合法（loopConfig 已按总小节数钳制；无谱时谈不上循环）。
    /// 说明：当前引擎里循环恒定开启（ScoreFollowEngine loopEnabled: true），没有独立开关，
    /// 故以「区间是否有效」作为这一格的 amber 依据，不编造开关态。
    private var loopActive: Bool {
        guard totalMeasures > 0 else { return false }
        return LoopService.isValid(
            start: session.loopConfig.startMeasure,
            end: session.loopConfig.endMeasure,
            totalMeasures: totalMeasures
        )
    }

    // MARK: 主圆钮（暂停 / 继续）+ 识别指示（S11 Stage B）

    /// 56pt 琥珀圆钮（真值 §6.2，旧 64）+ 琥珀投影；「识别中」挂在右侧（right8）。
    private var playRow: some View {
        playButton
            .overlay(alignment: .trailing) {
                if isRecognizing {
                    recognitionIndicator
                        .padding(.trailing, 8)
                }
            }
    }

    private var playButton: some View {
        Button {
            togglePlay()
        } label: {
            Image(systemName: playIcon)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color.canvas)
                .frame(width: 56, height: 56)
                .background(playDisabled ? Color.borderInput : Color.amber, in: Circle())
                // 真值：0 8px 24px amber/40；禁用态不发光
                .shadow(color: playDisabled ? .clear : Color.amber.opacity(0.4), radius: 12, y: 8)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(playDisabled)
        .frame(maxWidth: .infinity)
    }

    /// 图标/语义按 phase（真值 §6.2 + Stage A pause/resume）：
    /// - idle/finished：play.fill → 起跑（含预备拍）；
    /// - performing：pause.fill → session.pause() 并停节拍器（停表不停会话）；
    /// - paused：play.fill → session.resume()，节拍器按房间开关原地续起（无预备拍）；
    /// - counting：维持原 ■（停止即结算）——预备拍期间不暂停，避免卡在 onCountInFinished。
    private var playIcon: String {
        switch session.phase {
        case .performing: "pause.fill"
        case .counting: "stop.fill"
        case .idle, .paused, .finished: "play.fill"
        }
    }

    private var playDisabled: Bool {
        !hub.isConnected && session.phase != .idle // S11b：播放/结束禁用变灰（spec）
    }

    private func togglePlay() {
        switch session.phase {
        case .idle, .finished:
            metronome.onCountInFinished = { session.beginPerforming() }
            session.start(metronome: metronome, countIn: true, metronomeOn: metronomeOn)
            if metronomeOn, session.phase == .performing {
                // 预备拍关着：这里补一次无预备拍的 start
                metronome.start(bpm: session.tempoState.bpm, countInBars: 0)
            }
        case .performing:
            // Stage A：用户暂停（不是结算）。停心跳与判分，节拍器一并停；elapsedSec 不计这段。
            session.pause()
            metronome.stop()
        case .paused:
            // 继续：心跳重启，节拍器按房间开关原地续起（无预备拍，不重新计数）。
            session.resume()
            if metronomeOn {
                metronome.start(bpm: session.tempoState.bpm, countInBars: 0)
            }
        case .counting:
            // 预备拍期间不可暂停：维持原「停止即结算」出口，不会把会话卡死。
            finishAndSave()
        }
    }

    /// 识别指示（真值 §6.2）：只在「真的在判分」时出现 —— performing 且 MIDI 已连接。
    /// 暂停（.paused）/断连都不亮，不冒充"在听"。
    private var isRecognizing: Bool {
        session.phase == .performing && hub.isConnected
    }

    private var recognitionIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.s11Recognizing)
                .frame(width: 6, height: 6)
                .opacity(recognitionPulse ? 0.35 : 1)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        recognitionPulse = true
                    }
                }
            Text("识别中")
                .font(.system(size: 10))
                .foregroundStyle(Color.textMuted)
        }
        .transition(.opacity)
    }

    private func toggleMetronome() {
        metronomeOn.toggle()
        // 阶段语义在 PracticeSession.toggleMetronome（可单测）：开关管住含预备拍在内的
        // 全部节拍器声音，且绝不会把 phase 留在 .counting。
        session.toggleMetronome(on: metronomeOn, metronome: metronome)
        // 让示范也跟随房间的节拍器设定（demo 是独立音源，不主动同步就不会跟）。
        syncDemoSettings()
    }

    /// 把练习室的节拍器开关 / BPM 同步给示范音源。
    /// DemoPlaybackService 是独立于练习室判分的音源，默认节拍器关、速度=参考值，
    /// 不会自己读房间状态，所以必须显式推：节拍器跟 `metronomeOn`，速度跟 `session.tempoState.bpm`。
    /// 播放前调一次保证开播即正确；切换节拍器 / 调速时调，可在示范播放中 live 生效。
    private func syncDemoSettings() {
        demo.setMetronome(metronomeOn)
        demo.setTempo(session.tempoState.bpm)
    }

    // MARK: 示范（坞内第 5 格 / B7 拒绝 / B8 指示）

    /// 「示范」格值 —— playing 给已播放秒 mm:ss，paused 给 ▮▮，其余 OFF。
    private var demoCardValue: String {
        switch demo.state {
        case .playing: format(max(0, Int(demo.currentTimeSeconds)))
        case .paused: "▮▮"
        default: "OFF" // .stopped / .exporting
        }
    }

    /// 示范播放开关（与主圆钮的「开始 / 暂停·继续判分演奏」是两套语义，互不干预）。
    /// B7：练习进行中一律拒绝——只 toast、零 Alert、零打断，且示范音绝不写进正在录的 take。
    private func toggleDemo() {
        if session.phase == .performing || session.phase == .counting {
            session.toast = "先停一下当前练习，再听示范"
            return
        }
        guard demo.availability == .ready else {
            session.toast = "未内置音源，暂无法听示范"
            return
        }
        guard let score = loadedScore else { return } // 谱还没加载好：静默不动作（不强解包）
        switch demo.state {
        case .playing: demo.pauseOrStop() // 暂停（保留位置，再按继续）
        case .paused:
            syncDemoSettings()
            demo.resume(score: score)
        default:
            // 开播前先把房间的节拍器开关/BPM 推给示范音源，再 prepare+播放（保证开播即跟随）。
            syncDemoSettings()
            // 未 prepare 过就先 prepare（音源 gate 已在上面挡过），再整曲播放
            try? demo.prepare(score: score)
            demo.playWhole(score: score)
        }
    }

    /// B8：「示范播放中」pill —— 断连时示范仍可听，故指示照旧压在谱卡遮罩之上；
    /// amber 描边 + 实底保证被压暗时仍读得清；不吃点击（不挡谱面操作）。
    private var demoPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .semibold))
            Text("示范播放中")
                .font(.labelMd)
        }
        .foregroundStyle(Color.amber)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.cardElevated.opacity(0.92), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.amber.opacity(0.6), lineWidth: 1))
        .allowsHitTesting(false)
    }

    // MARK: 收尾

    /// 结算入口：X → 退出确认对话框的「结束并保存」（Stage B 起它取代独立「结束并生成报告」按钮），
    /// 以及时间到自动保存。`.paused` 也算数——finish() 自己按活跃时间结算（暂停段不计入）。
    private func finishAndSave() {
        metronome.stop()
        guard session.phase == .performing || session.phase == .counting || session.phase == .paused
            || session.timeUp
        else {
            dismiss()
            return
        }
        let summary = session.finish()
        let take = PracticeSession.persist(
            summary,
            taskType: taskType,
            isFreePlay: session.isFreePlay,
            startedAt: session.startedAt ?? Date(),
            interruptions: session.interruptionStarts,
            title: pieceTitle, // P2 修复：落真实标题（今日/聚合传「教材 第N条」；不再存空串）
            // M5b：take 挂到曲目与谱，才有分析/过关的归属（SPEC §10）
            pieceId: effectivePiece?.entityId,
            scoreFileId: scoreFile?.entityId,
            in: context
        )
        // 先落库再分析：pieceTakeHistory 要能查到这条新 take（连续计数口径）
        try? context.save()
        // G3 Stage B：矫正进房练完即标记完成（完成口径不看达标率，ADR-0005 决策四；markCompleted 幂等）。
        // 矫正进房照常 triggerAnalysis，其 analyzeAndStore 会走处方接线（通过→resolve，不过→未结去重不重建）。
        if let correction {
            CorrectionPrescriptionStore.markCompleted(correction, in: context)
        }
        // G5 Stage B：铺路进房练完一遍即标记完成（ADR-0006 决策六，不看达标；markPavingCompleted 幂等）。
        // 铺路非门禁：只写卡完成态，不碰 Piece.status / 过关 / streak；锁区间由 initialHotspots 机制承担。
        if let paving {
            RewardPavingStore.markPavingCompleted(paving, in: context)
        }
        finishedSummary = summary
        triggerAnalysis(for: take)
    }

    /// 分析编排（SPEC §10）：在 persist 成功后触发，**不**塞进 persist（保持其纯落库）。
    /// 读盘 + 载谱是同步 IO，丢到 Task 里做，避免卡保存后的 UI；
    /// 失败不吞（ScoringOrchestrator 返回 error outcome），也不影响 take 已落库与连续计数。
    private func triggerAnalysis(for take: Take) {
        let tempo = referenceTempo > 0 ? referenceTempo : (effectivePiece?.referenceTempo ?? 0)
        Task { @MainActor in
            _ = ScoringOrchestrator.run(
                for: take,
                scoreFile: scoreFile,
                piece: effectivePiece,
                measureFrom: nil,
                measureTo: nil,
                referenceTempo: tempo,
                standards: ScoringStandards.standards(forBook: effectivePiece?.book ?? ""),
                bundledBook: bundledBook,
                bundledNumber: bundledNumber,
                in: context
            )
        }
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
        // P3 修复：初始连接态同步——PracticeSession 初始 isConnected=true 与 MIDIHub 初始 false
        // 不同步；进场第一拍就按真实 hub 状态对齐（此后仍由 onChange(hub.isConnected) 跟随）。
        session.setConnected(hub.isConnected)
        // Stage B §2a：今日/聚合入口未传 piece → 按 bundled 坐标懒解析归属条目
        //（解析落 @State，take 落库/分析统一走 effectivePiece）。
        if piece == nil, let b = bundledBook {
            resolvedPiece = CourseEngine.resolveRoomPiece(book: b, number: bundledNumber, in: context)
        }
        // 谱可用性四态决策（ScoreAvailability；bundledScore = 内置公版谱）
        let availability = ScoreAvailability.resolve(
            scoreFile: scoreFile,
            isSampleEntry: isSampleEntry,
            bundledBook: bundledBook,
            bundledNumber: bundledNumber
        )
        let url: URL?
        switch availability {
        case .realScore(let sf):
            url = SandboxPaths.resolve(sf.fileURL)
        case .samplePiece:
            url = Bundle.main.url(forResource: "SpikeSample32", withExtension: "musicxml")
        case .bundledScore(let book, let number):
            url = BundledScore.url(book: book, number: number)
        case .unavailable:
            // 内置教材条目无谱（车尔尼599）：不再静默加载任何别的谱冒充（SPEC §10）
            loadError = "暂无参考谱。可用「示例曲」或导入的乐谱练习；本次可自由弹奏（不判分）。"
            return
        }
        guard let url else {
            loadError = "找不到可练习的谱面文件"
            return
        }
        do {
            let score = try ScoreLoader.loadScore(contentsOf: url)
            loadedScore = score
            let expected = ScoreExpectedPitches.extract(score: score)
            // G3 Stage B：矫正进房初始速度 = 参考速 × 最保守速度比（CorrectionEngine.initialTempoRatio）；
            // 无参考速回落 72（与默认口径一致）。configure 前算好，直接走 startBPM，不改 session 公开面。
            let startBPM: Int
            if let ratio = initialTempoRatio {
                let ref = referenceTempo > 0 ? referenceTempo : (effectivePiece?.referenceTempo ?? 0)
                let base = ref > 0 ? ref : 72
                startBPM = Int((Double(base) * ratio).rounded())
            } else {
                startBPM = 72
            }
            session.configure(
                scoreName: displayTitle,
                expectedPerMeasure: expected,
                startBPM: startBPM
            )
            // G3 Stage B / P12+C5：进房即锁定 hotspot 循环区间（此时 expected 已有，总小节数可锚定）。
            // 直接改 startMeasure/endMeasure → didSet→reconfigureRegion（phase 仍 .idle，正确）。
            // 取不到合法区间（无 initialHotspots / 总小节不足）→ 不动 loopConfig，保持默认。
            if let range = PracticeRoomView.lockedLoopRange(initialHotspots: initialHotspots, totalMeasures: expected.count) {
                session.loopConfig.startMeasure = range.start
                session.loopConfig.endMeasure = range.end
            }
        } catch {
            loadError = "谱面解析失败：\(error.localizedDescription)"
        }
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

// MARK: - S11 真值字面色（DesignSystem token 未覆盖到的真值 hex，仅本文件使用）

fileprivate extension Color {
    /// 纸张 #FBF8F2（真值 §4）。注意 `Color.scorePaper` 是 #F5F0E6，与真值不同，故用字面量。
    static let s11Paper = Color(red: 0xFB / 255, green: 0xF8 / 255, blue: 0xF2 / 255)
    /// 纸卡 1pt 描边 #EBE4D5（真值 §4）
    static let s11PaperBorder = Color(red: 0xEB / 255, green: 0xE4 / 255, blue: 0xD5 / 255)
    /// 控件坞 1pt 描边 #3C3530（真值 §6.1）
    static let s11DockBorder = Color(red: 0x3C / 255, green: 0x35 / 255, blue: 0x30 / 255)
    /// 「识别中」翠绿 #34D399（真值 §6.2）
    static let s11Recognizing = Color(red: 0x34 / 255, green: 0xD3 / 255, blue: 0x99 / 255)
    /// S11b 卡片/控件 1pt 描边 #332D29（真值 §3/§6/§7）。
    /// `Color.borderInput` 是 #333531，与真值微差，故用字面量。
    static let s11CardBorder = Color(red: 0x33 / 255, green: 0x2D / 255, blue: 0x29 / 255)
    /// S11b danger 容器底 #3A2522（真值 §3 胶囊 /80、§4 横幅实底）
    static let s11DangerContainer = Color(red: 0x3A / 255, green: 0x25 / 255, blue: 0x22 / 255)
    /// S11b danger 浅色文字 #E8A59E（真值 §3 胶囊字、§4 横幅图标与副行）
    static let s11DangerText = Color(red: 0xE8 / 255, green: 0xA5 / 255, blue: 0x9E / 255)
    // 其余 S11b 色板与 DesignSystem token 一致，直接复用：
    // #1C1917→Color.canvas、#262220→Color.card、#C97064→Color.danger、
    // #D4A24E→Color.amber、#F5F2ED→Color.textPrimary、#9C948B→Color.textMuted。
}

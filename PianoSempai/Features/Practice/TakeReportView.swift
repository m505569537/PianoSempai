import Foundation
import SheetMusicCore
import SheetMusicLoader
import SwiftData
import SwiftUI

// MARK: - S13 Take 报告（P1 真实统计 + P2 M5b 六维真实渲染；只读，不写课程状态）
// 数据源：P1 统计走 TakeAnalysisService（时长/音符数/错音率等）；
// P2 六维/热力/置信/过关进度走 TakeReportPresentation（读 TakeAnalysis 派生缓存）。
// 判分只读分析，课程状态只由 CourseEngine 写（红线 2/3）。
//
// S13c 听音（只读延伸）：B9 错音行「只听这小节的期望音」+ B10「只听我弹的」，
// 两者共用同一个 TakePlaybackService（同一进程不要两套音频图并发播）；
// 播放是纯回放，不写 take、不写课程状态（报告页只读铁律）。

struct TakeReportView: View {
    let take: Take
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var errorMarks: [ScoreErrorMark]
    @Query(sort: \TakeAnalysis.analyzedAt, order: .reverse) private var analyses: [TakeAnalysis]
    @Query private var pieces: [Piece]
    @Query private var scoreFiles: [ScoreFile]
    @State private var showMarkSheet = false
    @State private var showPractice = false
    /// S13「问 Neko 这一段」→ S18 对话（带本次 take + 判分上下文）
    @State private var showChat = false
    /// S13c 回放服务：B9 期望音预览与 B10「只听我弹的」共用（onDisappear 统一 teardown）
    @State private var takePlayer = TakePlaybackService()
    /// 本次 take 的原始演奏音符（与 ScoringOrchestrator 同一解析口径）；nil = 无 MIDI/空 take → 禁用
    @State private var takeNotes: [PlayedNote]?
    /// 「只听我弹的」正在播（按钮两态：播放 / 停止）
    @State private var isTakePlaying = false
    /// 播放代次：每次新播放 +1，用于作废上一轮的 isReady 轮询 / 结束复位（连点不串台）
    @State private var playbackGeneration = 0
    /// B9 参考谱期望音缓存（0-based 小节 → 音高集合）；懒解析一次，不每次重载谱
    @State private var expectedPerMeasure: [[UInt8]]?
    @State private var didLoadExpectedPerMeasure = false
    @State private var didPreloadTakeNotes = false

    private var analysis: P1TakeAnalysis {
        TakeAnalysisService.analyze(take: take, errorMarks: errorMarks)
    }

    /// 该 take 的最新分析行（take.analysisId 回填值优先；旧 take 无 → nil）
    private var scoringAnalysis: TakeAnalysis? {
        if let id = take.analysisId, let row = analyses.first(where: { $0.entityId == id }) { return row }
        return analyses.first { $0.takeId == take.entityId && $0.engineVersion == ScoringOrchestrator.engineVersion }
    }

    /// 该 take 所属曲目（P1 take 无 pieceId → nil，阈值回落入门）
    private var piece: Piece? {
        guard let id = take.pieceId else { return nil }
        return pieces.first { $0.entityId == id }
    }

    /// 再练一遍用的谱文件（按 take.scoreFileId 回查；示例曲无 ScoreFile 行 → nil）
    private var practiceScoreFile: ScoreFile? {
        guard let id = take.scoreFileId else { return nil }
        return scoreFiles.first { $0.entityId == id && $0.canFollow }
    }

    /// 分级阈值（§9：拜厄/哈农/示例/导入 = 入门；599 = 进阶）
    private var standards: ScoringStandards {
        ScoringStandards.standards(forBook: piece?.book ?? "")
    }

    /// 该曲目当前连续达标次数（只读统计，CourseEngine 仍是唯一写手）
    private var consecutivePasses: Int {
        guard let id = take.pieceId else { return 0 }
        return CourseEngine.consecutivePassStreak(
            eligibleTakes: ScoringOrchestrator.pieceTakeHistory(pieceId: id, in: context)
        )
    }

    private var report: P2TakeReport {
        TakeReportPresentation.build(
            analysis: scoringAnalysis, standards: standards, consecutivePasses: consecutivePasses
        )
    }

    private var title: String {
        if take.isFreePlay { return take.title.isEmpty ? "自由弹奏" : take.title }
        if let from = take.measureFrom, let to = take.measureTo {
            return "练习 · 第\(from)–\(to)小节"
        }
        return "练习 take"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                wrongNoteCard.padding(.top, 16)
                wrongListCard.padding(.top, 12)
                lowConfidenceBanner.padding(.top, 12)
                scoringCard.padding(.top, 12)
                hotspotCard.padding(.top, 12)
                passProgressCard.padding(.top, 12)
                confidenceCard.padding(.top, 12)
                actions.padding(.top, 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.canvas)
        // 提前预热「我弹的」：点按钮时大概率已 ready，直接出声
        .onAppear { preloadTakeNotesIfNeeded() }
        // 与其它全屏页一致：返回不留音频图（左上返回同样走这里）
        .onDisappear { takePlayer.teardown() }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.textBody)
                    .frame(width: 44, height: 44)
            }
        }
        .sheet(isPresented: $showMarkSheet) {
            S13bMarkSheet(
                scoreName: title,
                measure: analysis.wrongNotes.first?.measure ?? 1
            ) { type, note in
                submitMark(type: type, note: note)
            }
        }
        .fullScreenCover(isPresented: $showPractice) {
            // 再练一遍：沿用同曲目/同一份谱 + 示例曲标记（不退回拿样例谱冒充）
            PracticeRoomView(
                taskType: take.taskType.isEmpty ? "main" : take.taskType,
                scoreFile: practiceScoreFile,
                pieceTitle: piece?.title ?? title,
                isSampleEntry: piece?.book == "示例",
                piece: piece,
                referenceTempo: piece?.referenceTempo ?? take.tempoAvg
            )
        }
        .fullScreenCover(isPresented: $showChat) {
            // S18 问 Neko 这一段：带本次 take 与判分结果，同一 take 多次进来接着聊
            ChatView(
                mode: .take(take, analysis: scoringAnalysis, pieceTitle: piece?.title),
                context: context
            )
        }
    }

    private func submitMark(type: String, note: String) {
        let measure = analysis.wrongNotes.first?.measure ?? 1
        // 同小节重复提交合并计数（spec）
        if let existing = errorMarks.first(where: { $0.scoreName == title && $0.measure == measure }) {
            existing.occurrenceCount += 1
            existing.type = type
            if !note.isEmpty { existing.note = note }
        } else {
            context.insert(ScoreErrorMark(scoreName: title, measure: measure, type: type, note: note))
        }
    }

    // MARK: S13c 听音（B9 期望音 / B10 我弹的；只播放，不写任何数据）

    /// 随 app 分发的 MuseScore_General.sf2（找不到 → 服务侧安全 no-op，不崩、不弹 Alert）
    private var soundfontURL: URL? {
        BundledSoundfontResolver.bundledURL()
    }

    /// 这条 take 有没有期望音可听（只判参考谱在不在，不解析谱面）。
    /// 无参考谱（无真实谱且无内置公版谱）→ 错音行的菜单项不显示。
    private var canPreviewExpected: Bool {
        ScoringOrchestrator.referenceScoreURL(
            scoreFile: practiceScoreFile,
            bundledBook: piece?.book,
            bundledNumber: piece?.number ?? 0
        ) != nil
    }

    /// B9：只听错音那一小节的期望音（同一 onset / 同长的柱式和弦）。
    /// 无参考谱、该小节无音或越界 → 静默 return（零打断）。
    private func playExpected(for wrong: WrongNoteRecord) {
        guard let table = expectedPerMeasureTable() else { return }
        // 外层 index 是 0-based 小节；wrong.measure 是 1-based 展示值
        let index = wrong.measure - 1
        guard index >= 0, index < table.count else { return }
        let pitches = table[index]
        guard !pitches.isEmpty else { return }
        let chord = pitches.map {
            PlayedNote(pitch: $0, onsetSec: 0, endSec: 0.6, velocity: 96, isSuspicious: false)
        }
        // 期望音预览不是 take 播放态：按钮文案回「只听我弹的」，并切掉可能正在播的 take
        isTakePlaying = false
        takePlayer.stop()
        takePlayer.prepareTake(notes: chord, soundfontURL: soundfontURL)
        startPlaybackWhenReady()
    }

    /// 参考谱期望音（0-based 小节 → 音高集合）。懒解析并缓存，同一小节反复点只载一次谱。
    private func expectedPerMeasureTable() -> [[UInt8]]? {
        if didLoadExpectedPerMeasure { return expectedPerMeasure }
        didLoadExpectedPerMeasure = true
        guard let url = ScoringOrchestrator.referenceScoreURL(
            scoreFile: practiceScoreFile,
            bundledBook: piece?.book,
            bundledNumber: piece?.number ?? 0
        ), let score = try? ScoreLoader.loadScore(contentsOf: url) else {
            expectedPerMeasure = nil
            return nil
        }
        let table = ScoreExpectedPitches.extract(score: score)
        expectedPerMeasure = table.isEmpty ? nil : table
        return expectedPerMeasure
    }

    /// B10：.onAppear 预热「我弹的」——原始事件解析成演奏音符（判分同口径）后预装载序列。
    /// 读盘是同步 IO，丢进 Task；MIDI 缺失/空 take → takeNotes 留 nil（按钮禁用），静默。
    private func preloadTakeNotesIfNeeded() {
        guard !didPreloadTakeNotes else { return }
        didPreloadTakeNotes = true
        let midiPath = take.midiFileURL
        let interruptions = take.interruptionRanges
        let duration = Double(take.durationSec)
        Task { @MainActor in
            guard let url = SandboxPaths.resolve(midiPath) else { return }
            let events = (try? TakeStore.readEvents(from: url)) ?? []
            guard !events.isEmpty else { return }
            let parsed = MidiTakeParser.parse(
                events: events,
                interruptionRanges: interruptions,
                streamEndSec: duration
            )
            guard !parsed.notes.isEmpty else { return }
            takeNotes = parsed.notes
            takePlayer.prepareTake(notes: parsed.notes, soundfontURL: soundfontURL)
        }
    }

    /// 底部次按钮两态：播「我弹的」/ 停止。无音符时按钮已禁用，这里不再兜底。
    private func toggleTakePlayback() {
        guard let notes = takeNotes else { return }
        if isTakePlaying {
            takePlayer.stop()
            isTakePlaying = false
            return
        }
        isTakePlaying = true
        takePlayer.stop() // 先切掉可能正在播的期望音预览
        takePlayer.prepareTake(notes: notes, soundfontURL: soundfontURL)
        let generation = startPlaybackWhenReady()
        watchTakePlaybackEnd(generation: generation)
    }

    /// prepareTake 后音源可能还在后台解析（isReady == false，此时 play() 被安全 no-op）：
    /// 轮询 isReady 最多 ~2s，ready 即播；超时静默放弃，不弹任何提示。
    /// - Returns: 本次播放的代次（供结束复位的 Task 判过期）
    @discardableResult
    private func startPlaybackWhenReady() -> Int {
        playbackGeneration += 1
        let generation = playbackGeneration
        Task { @MainActor in
            var tries = 0
            while !takePlayer.isReady, tries < 20 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                tries += 1
            }
            // 期间又起了新的播放 → 这一轮已过期，交给新的那次
            guard playbackGeneration == generation, takePlayer.isReady else { return }
            takePlayer.play()
        }
        return generation
    }

    /// 播放结束复位按钮（服务无结束回调）：以真实 isAtEnd 为准，take 时长只是上限保护。
    private func watchTakePlaybackEnd(generation: Int) {
        let deadline = Date().addingTimeInterval(max(1, Double(take.durationSec)) + 1.5)
        Task { @MainActor in
            while !takePlayer.isAtEnd, Date() < deadline {
                if playbackGeneration != generation { return } // 已被新播放/手动停止作废
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            // 用户已手动停止 / 已换别的播放 → 不复活按钮状态
            guard isTakePlaying, playbackGeneration == generation else { return }
            isTakePlaying = false
            takePlayer.stop()
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Take 报告 · \(title)")
                .font(.headlineLg)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            let dateText = take.startedAt.formatted(date: .abbreviated, time: .omitted)
            Text("\(dateText) \(take.startedAt.formatted(date: .omitted, time: .shortened)) · ♩=\(take.tempoAvg) · 时长 \(take.durationSec / 60)分\(take.durationSec % 60)秒")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .monospacedDigit()
        }
        .padding(.top, 8)
        .padding(.leading, 44)
    }

    // MARK: 错音率卡（真实统计；剔除规则可见）

    private var wrongNoteCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 10) {
                statRow("时长", "\(take.durationSec / 60)分\(take.durationSec % 60)秒")
                statRow("音符数", "\(analysis.noteCount)")
                HStack(alignment: .firstTextBaseline) {
                    Text("错音数")
                        .font(.labelMd)
                        .foregroundStyle(Color.textBody)
                    Spacer()
                    if analysis.exclusionApplied {
                        // S13b 展示：被标小节从分子扣除（引擎规则）
                        Text("\(analysis.wrongNotes.count - analysis.effectiveWrongCount) 处已标谱错剔除")
                            .font(.labelSm)
                            .foregroundStyle(Color.amber)
                    }
                    Text("\(analysis.effectiveWrongCount)")
                        .font(.titleMd)
                        .foregroundStyle(analysis.effectiveWrongCount > 0 ? Color.danger : Color.success)
                        .monospacedDigit()
                }
                if let rate = analysis.wrongNoteRate {
                    statRow("错音率", String(format: "%.1f%%", rate * 100))
                } else {
                    statRow("错音率", "没有音符，不计算")
                }
                statRow("速度", "♩=\(analysis.tempoAvg)")
                statRow("踏板事件（CC64）", "\(analysis.pedalEventCount)")
                statRow("MIDI 事件", "\(analysis.midiEventCount)")
                if !take.interruptionRanges.isEmpty {
                    statRow("断连续录", "\(take.interruptionRanges.count) 次（断点已标）")
                }
            }
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.labelMd).foregroundStyle(Color.textBody)
            Spacer()
            Text(value).font(.labelMd).foregroundStyle(Color.textPrimary).monospacedDigit()
        }
    }

    // MARK: 错音清单（有明细才展示；被标行显示谱错标签）

    @ViewBuilder
    private var wrongListCard: some View {
        if analysis.hasDetail {
            NocturneCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("错音清单")
                            .font(.titleMd)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("长按错音可听期望音/标谱错")
                            .font(.labelSm)
                            .foregroundStyle(Color.textMuted)
                    }
                    ForEach(analysis.wrongNotes, id: \.self) { wrong in
                        let marked = analysis.excludedMeasures.contains(wrong.measure)
                        let canPreview = canPreviewExpected
                        WrongNoteRow(wrong: wrong, marked: marked)
                            .contextMenu {
                                if canPreview {
                                    Button {
                                        playExpected(for: wrong)
                                    } label: {
                                        Label("只听这小节期望音", systemImage: "music.note")
                                    }
                                }
                                Button {
                                    showMarkSheet = true
                                } label: {
                                    Label("标记疑似谱面错误", systemImage: "flag")
                                }
                            }
                    }
                    Text("匹配口径：P1 简单匹配（音序贪心），非对齐算法。")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
    }

    // MARK: 低置信琥珀条（判分仅供参考，本次不计入过关）

    @ViewBuilder
    private var lowConfidenceBanner: some View {
        if report.state == .scored, !report.canEvaluate {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("没对上，判分仅供参考，本次不计入过关")
                        .font(.labelMd)
                        .foregroundStyle(Color.amber)
                    if let first = report.reasons.first {
                        Text(first)
                            .font(.labelSm)
                            .foregroundStyle(Color.textMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.amber.opacity(0.35), lineWidth: 1))
        }
    }

    // MARK: P2 六维判分（真实分；算不出 = 数据不足，禁止编分）

    @ViewBuilder
    private var scoringCard: some View {
        switch report.state {
        case .noAnalysis:
            NocturneCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("完整判分")
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                    Text("这条 take 还没有分析数据（旧 take，或分析还没跑）。")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                    Text("分析由原始 MIDI 加谱面重算、可随时重建；本页先给真实统计，不编分。")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                }
            }
        case .statistics:
            NocturneCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("完整判分")
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                    Text(report.reasons.first ?? "无参考谱，不判定对错/过关")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                    Text("不出对错分、不计过关；上面的时长/音符数等统计仍然真实。")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                }
            }
        case .scored:
            NocturneCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("六维判分")
                            .font(.titleMd)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("弱总分 \(report.weakTotal.map { "\($0)" } ?? "—")")
                            .font(.labelMd)
                            .foregroundStyle(Color.amber)
                            .monospacedDigit()
                    }
                    Text("弱总分仅供进步曲线，不作过关依据")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textMuted)
                    ForEach(report.dimensions, id: \.name) { row in
                        dimensionRow(row)
                    }
                    Divider().overlay(Color.borderInput)
                    HStack(spacing: 18) {
                        countChip("错音", report.wrongCount)
                        countChip("漏音", report.missingCount)
                        countChip("多弹", report.extraCount)
                        Spacer(minLength: 0)
                    }
                    HStack {
                        Text("节奏偏差中位")
                            .font(.labelMd)
                            .foregroundStyle(Color.textBody)
                        Spacer()
                        Text("\(Int(report.rhythmMedianMs.rounded()))ms · \(report.rhythmTendency)")
                            .font(.labelMd)
                            .foregroundStyle(report.rhythmTendency == "数据不足" ? Color.textMuted : Color.textPrimary)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("速度达标（参考速度 \(Int(standards.targetTempoRatio * 100))%）")
                            .font(.labelMd)
                            .foregroundStyle(Color.textBody)
                        Spacer()
                        if report.avgBPM > 0 {
                            Text("♩=\(Int(report.avgBPM.rounded())) · \(report.tempoTargetHit ? "已达标" : "未达标")")
                                .font(.labelMd)
                                .foregroundStyle(report.tempoTargetHit ? Color.success : Color.textMuted)
                                .monospacedDigit()
                        } else {
                            Text("速度维算不出")
                                .font(.labelMd)
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                }
            }
        }
    }

    private func dimensionRow(_ row: DimensionRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(row.name)
                .font(.labelMd)
                .foregroundStyle(Color.textBody)
            Spacer()
            if let score = row.score {
                Text("\(score)")
                    .font(.titleMd)
                    .foregroundStyle(scoreColor(score))
                    .monospacedDigit()
            } else {
                Text("\(row.displayScore) · \(row.note)")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: return Color.success
        case 60..<80: return Color.amber
        default: return Color.danger
        }
    }

    private func countChip(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.labelSm)
                .foregroundStyle(Color.textMuted)
            Text("\(value)")
                .font(.labelMd)
                .foregroundStyle(value > 0 ? Color.textPrimary : Color.textMuted)
                .monospacedDigit()
        }
    }

    // MARK: 问题定位与热度（简表：按小节列问题密度，不引图表库）

    @ViewBuilder
    private var hotspotCard: some View {
        if !report.measureHeat.isEmpty || !report.problems.isEmpty {
            NocturneCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("问题定位与热度")
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                    if !report.measureHeat.isEmpty {
                        ForEach(report.measureHeat, id: \.measure) { item in
                            HStack(spacing: 8) {
                                Text("第\(item.measure)小节")
                                    .font(.labelMono(12, weight: .medium))
                                    .foregroundStyle(Color.amber)
                                    .frame(width: 74, alignment: .leading)
                                GeometryReader { proxy in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 1).fill(Color.borderInput).frame(height: 4)
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.amber.opacity(0.85))
                                            .frame(width: proxy.size.width * min(1, max(0, item.heat)), height: 4)
                                    }
                                }
                                .frame(height: 4)
                                Text("\(Int((item.heat * 100).rounded()))%")
                                    .font(.labelSm)
                                    .foregroundStyle(Color.textMuted)
                                    .monospacedDigit()
                            }
                        }
                    }
                    if !report.problems.isEmpty {
                        ForEach(report.problems.prefix(12), id: \.self) { problem in
                            HStack(spacing: 6) {
                                if let measure = problem.measure {
                                    Text("第\(measure)小节·第\(beatText(problem.beatInMeasure))拍")
                                        .font(.labelMono(12))
                                        .foregroundStyle(Color.amber)
                                } else {
                                    Text("谱面无此音")
                                        .font(.labelMono(12))
                                        .foregroundStyle(Color.amber)
                                }
                                Text(problem.kind.rawValue)
                                    .font(.labelSm)
                                    .foregroundStyle(problem.kind == .extra ? Color.textBody : Color.danger)
                                Text(problem.pitchText)
                                    .font(.labelSm)
                                    .foregroundStyle(Color.textMuted)
                                Spacer(minLength: 0)
                            }
                        }
                        if report.problems.count > 12 {
                            Text("…共 \(report.problems.count) 处，完整明细见逐音对齐数据。")
                                .font(.labelSm)
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                }
            }
        }
    }

    private func beatText(_ beatInMeasure: Double?) -> String {
        guard let beatInMeasure else { return "—" }
        return String(format: "%g", beatInMeasure + 1)
    }

    // MARK: 过关进度（硬指标实际值/阈值/差多少 + 连续 N/2）

    @ViewBuilder
    private var passProgressCard: some View {
        if report.state == .scored {
            NocturneCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("过关进度")
                            .font(.titleMd)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("连续达标 \(report.consecutivePasses)/\(report.requiredConsecutivePasses)")
                            .font(.labelMd)
                            .foregroundStyle(Color.amber)
                            .monospacedDigit()
                    }
                    if report.canEvaluate {
                        ForEach(report.passMetrics, id: \.name) { metric in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(metric.name)
                                        .font(.labelMd)
                                        .foregroundStyle(Color.textBody)
                                    Spacer()
                                    Text("\(metric.actualDisplay)（阈值 \(metric.thresholdDisplay)）")
                                        .font(.labelSm)
                                        .foregroundStyle(Color.textPrimary)
                                        .monospacedDigit()
                                    Image(systemName: metric.passed ? "checkmark.circle.fill" : "xmark.circle")
                                        .font(.system(size: 13))
                                        .foregroundStyle(metric.passed ? Color.success : Color.danger)
                                }
                            }
                        }
                        if report.passGaps.isEmpty, report.passesHardMetrics {
                            Text(report.consecutivePasses >= report.requiredConsecutivePasses
                                 ? "连续 2 遍达标，已拿下。"
                                 : "这遍达标，再稳一遍就过。")
                                .font(.bodySm)
                                .foregroundStyle(Color.success)
                        } else if !report.passGaps.isEmpty {
                            Text("差多少：\(report.passGaps.joined(separator: "；"))")
                                .font(.bodySm)
                                .foregroundStyle(Color.textBody)
                        }
                        Text("由规则引擎判定 · Neko 不能改结果")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textMuted)
                    } else {
                        Text("本次不计入过关（也不清零连续计数）")
                            .font(.bodySm)
                            .foregroundStyle(Color.textBody)
                        ForEach(report.reasons.prefix(3), id: \.self) { reason in
                            Text("· \(reason)")
                                .font(.labelSm)
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                }
            }
        }
    }

    // MARK: 置信度与数据卡（真实对齐置信度 + 0.6 门禁刻度）

    private var confidenceCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("对齐置信度")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                if report.state == .scored {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%.2f", report.confidence))
                            .font(.titleMd)
                            .foregroundStyle(report.confidence >= ScoringStandards.confidenceGateThreshold ? Color.success : Color.amber)
                            .monospacedDigit()
                        Spacer()
                        Text("门禁阈值 \(String(format: "%.1f", ScoringStandards.confidenceGateThreshold))")
                            .font(.labelSm)
                            .foregroundStyle(Color.textMuted)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.borderInput).frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(report.confidence >= ScoringStandards.confidenceGateThreshold ? Color.success : Color.amber)
                                .frame(width: proxy.size.width * min(1, max(0, report.confidence)), height: 4)
                            Rectangle()
                                .fill(Color.textMuted)
                                .frame(width: 1, height: 10)
                                .padding(.leading, proxy.size.width * ScoringStandards.confidenceGateThreshold)
                        }
                    }
                    .frame(height: 10)
                    Text("竖线是门禁刻度：低于它不计入过关（也不清零）。")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                } else {
                    Text(report.state == .statistics
                         ? "统计级结果，无对齐置信度（无参考谱/自由弹奏）。"
                         : "还没有分析数据，无对齐置信度。")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                }
                Text("踏板 CC64 已记录 \(analysis.pedalEventCount) 次（判分参与）")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                Text("MIDI 原始事件已存本机（只追加）")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    // MARK: 底部动作

    private var actions: some View {
        VStack(spacing: 8) {
            // B10「只听我弹的」：原样回放本次演奏（保真实时序，不做量化对齐）
            Button {
                toggleTakePlayback()
            } label: {
                Text(isTakePlaying ? "停止 ■" : "只听我弹的")
            }
            .buttonStyle(SecondaryButtonStyle(cornerRadius: 8))
            .disabled(takeNotes == nil)
            Button {
                showPractice = true
            } label: {
                Text(take.tempoAvg > 0 ? "再练一遍 ♩=\(take.tempoAvg)" : "再练一遍")
            }
            .buttonStyle(SecondaryButtonStyle(cornerRadius: 8))
            Button {
                showChat = true
            } label: {
                Text("问 Neko 这一段")
                    .font(.titleMd)
                    .foregroundStyle(Color.amber)
            }
            .buttonStyle(.plain)
        }
    }
}

/// 错音行（小节号琥珀 mono + 被标行谱错标签）
struct WrongNoteRow: View {
    let wrong: WrongNoteRecord
    let marked: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("第\(wrong.measure)小节")
                .font(.labelMono(12, weight: .medium))
                .foregroundStyle(Color.amber)
                .frame(width: 76, alignment: .leading)
                .monospacedDigit()
            if marked {
                Text("疑似谱错 · 已标记")
                    .font(.labelSm)
                    .foregroundStyle(Color.amber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(Color.amber.opacity(0.4), lineWidth: 1))
            } else {
                Text("多弹/错音 \(SightReadSession.noteName(wrong.actualPitch))（\(wrong.actualPitch)）")
                    .font(.bodySm)
                    .foregroundStyle(Color.textBody)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Take 列表（hub「最近 take」与档案共用）

struct TakesListView: View {
    @Query(sort: \Take.startedAt, order: .reverse) private var takes: [Take]
    @State private var selected: Take?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if takes.isEmpty {
                        Text("还没有 take。去练习室弹一段，这里会出现记录。")
                            .font(.bodySm)
                            .foregroundStyle(Color.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                    ForEach(takes.prefix(50)) { take in
                        Button {
                            selected = take
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(rowTitle(take))
                                        .font(.bodyMd)
                                        .foregroundStyle(Color.textPrimary)
                                        .lineLimit(1)
                                    Text("\(take.startedAt.formatted(date: .abbreviated, time: .shortened)) · ♩=\(take.tempoAvg) · \(take.durationSec / 60)分\(take.durationSec % 60)秒")
                                        .font(.labelSm)
                                        .foregroundStyle(Color.textMuted)
                                        .monospacedDigit()
                                }
                                Spacer()
                                if !take.interruptionRanges.isEmpty {
                                    Image(systemName: "wifi.slash")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.textMuted)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.textMuted)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 56)
                        }
                        .buttonStyle(.plain)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color.canvas)
            .navigationTitle("Take 记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.amber)
                }
            }
            .sheet(item: $selected) { take in
                TakeReportView(take: take)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func rowTitle(_ take: Take) -> String {
        if take.isFreePlay { return take.title.isEmpty ? "自由弹奏" : take.title }
        let type = switch take.taskType {
        case "warmup": "热身"
        case "reward": "奖励曲"
        default: "主菜"
        }
        if let from = take.measureFrom, let to = take.measureTo {
            return "\(type) · 第\(from)–\(to)小节"
        }
        return type
    }
}

// MARK: - Take 列表（hub「最近 take」与档案共用）

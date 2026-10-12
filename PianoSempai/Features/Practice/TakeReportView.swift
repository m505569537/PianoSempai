import Foundation
import SheetMusicCore
import SheetMusicLoader
import SwiftData
import SwiftUI

// MARK: - S13 Take 报告（对齐 Stitch 真值 screen e7be79a0929b42a590cfad9b41bdc02f）
// 数据源：P1 统计走 TakeAnalysisService（时长/音符数/错音率等）；
// P2 六维/热力/节奏点/置信/过关进度走 TakeReportPresentation（读 TakeAnalysis 派生缓存）。
// 判分只读分析，课程状态只由 CourseEngine 写（红线 2/3）。
//
// S13c 听音（只读延伸）：错音行「只听这小节的期望音」+「只听我弹的」，
// 两者共用同一个 TakePlaybackService（同一进程不要两套音频图并发播）；
// 播放是纯回放，不写 take、不写课程状态（报告页只读铁律）。
//
// 诚实红线（视觉对齐真值时一条都没放松）：
// - 大分值＝report.weakTotal；nil 显「数据不足」，不放假分；脚注保留「不作过关依据」。
// - 雷达六维只用真实维度分：音准/读谱同源 pitchScore（沿用 S05 诚实模式）；
//   力度(dynamicsScore)不进雷达（真值雷达没有这一轴），只驱动卡⑤。
// - nil 轴只画标签、无顶点；数据多边形只连非 nil 真实顶点（参考 S05ResultView 写法）。
// - 热力格只画 take.measureFrom...measureTo 真实区间；格内数字＝该小节真实问题音数
//   （report.problems 按小节统计），不编。
// - 节奏折线只画真实 deltaMs 点；不足 2 点整卡显「数据不足」，不画空图、不编点。
// - 不渲染「OP.101」（Piece 无 opus 字段，backlog L6）；
//   不写真值示例句（十六分音符 / 60 BPM 起步 / 右手旋律层突出良好 / 写死 ±50）。
// - 关停折叠交互（真值只给展开态），不画无功能的假箭头。
// - 已上线能力不因改版丢失：P1 原始统计、六维口径说明、过关硬指标/连续 N/2、
//   对齐置信刻度、S13b 谱错标记、期望音试听、只听我弹的、问 Neko 全部保留。

struct TakeReportView: View {
    let take: Take
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var errorMarks: [ScoreErrorMark]
    @Query(sort: \TakeAnalysis.analyzedAt, order: .reverse) private var analyses: [TakeAnalysis]
    @Query private var pieces: [Piece]
    @Query private var scoreFiles: [ScoreFile]
    /// 同曲目 take 序位（「第 N 遍」）与上一遍弱总分用；按 startedAt 升序
    @Query(sort: \Take.startedAt, order: .forward) private var allTakes: [Take]
    @State private var showMarkSheet = false
    @State private var showPractice = false
    @State private var showCompare = false
    /// S13「问 Neko 这一段」→ S18 对话（带本次 take + 判分上下文）
    @State private var showChat = false
    /// 标记谱错的小节（长按明细行进 S13b；真实小节，不用 first 兜底编）
    @State private var markSheetMeasure = 1
    /// S13c 回放服务：期望音预览与「只听我弹的」共用（onDisappear 统一 teardown）
    @State private var takePlayer = TakePlaybackService()
    /// 本次 take 的原始演奏音符（与 ScoringOrchestrator 同一解析口径）；nil = 无 MIDI/空 take → 禁用
    @State private var takeNotes: [PlayedNote]?
    /// 「只听我弹的」正在播（按钮两态：播放 / 停止）
    @State private var isTakePlaying = false
    /// 播放代次：每次新播放 +1，用于作废上一轮的 isReady 轮询 / 结束复位（连点不串台）
    @State private var playbackGeneration = 0
    /// 错音行期望音缓存（0-based 小节 → 音高集合）；懒解析一次，不每次重载谱
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

    // MARK: 真实派生数据（全部来自持久化字段，算不出就不渲染）

    /// 同曲目全部 take（按 startedAt 升序）；无归属（自由弹奏/P1 take）→ 空
    private var pieceTakes: [Take] {
        guard let id = take.pieceId else { return [] }
        return allTakes.filter { $0.pieceId == id }.sorted { $0.startedAt < $1.startedAt }
    }

    /// 本 take 在同曲中的序位（1-based）；无归属 → nil（右侧不显序位）
    private var takeOrdinal: Int? {
        guard let index = pieceTakes.firstIndex(where: { $0.entityId == take.entityId }) else { return nil }
        return index + 1
    }

    /// 同曲上一条 take 的弱总分（「较上一遍提升」用）；取不到 → nil，不渲染 badge
    private var previousWeakTotal: Int? {
        guard let index = pieceTakes.firstIndex(where: { $0.entityId == take.entityId }), index > 0 else { return nil }
        let previous = pieceTakes[index - 1]
        return analyses.first { $0.takeId == previous.entityId && $0.weakTotal != nil }?.weakTotal
    }

    /// 上一遍的逐小节热度（C4 双条「上一遍」用）。口径同 previousWeakTotal：同曲目上一条 take 的
    /// 分析行，只读它自己那一行 decode 出来的 measureHeat——两遍各自单 take 单行，只并排比较，
    /// 不做任何跨 take 聚合/平均，也不改存储。无上一遍 / 上一遍没落热度 → 空（不画双条）。
    private var previousMeasureHeat: [MeasureHeat] {
        guard let index = pieceTakes.firstIndex(where: { $0.entityId == take.entityId }), index > 0 else { return [] }
        let previous = pieceTakes[index - 1]
        guard let row = analyses.first(where: { $0.takeId == previous.entityId && !$0.measureHeatJSON.isEmpty }) else { return [] }
        return TakeReportPresentation.decodeHeat(row.measureHeatJSON)
    }

    /// 相对时间（真实 startedAt 现算；不用真值写死的「刚刚」）
    private var relativeTimeText: String {
        let interval = Date.now.timeIntervalSince(take.startedAt)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        return "\(Int(interval / 86400)) 天前"
    }

    /// 「较上一遍提升 +N 分」：两侧 weakTotal 都真实存在才渲染；差值为负时如实说「低」
    private var improvementText: String? {
        guard let previous = previousWeakTotal, let current = report.weakTotal else { return nil }
        let delta = current - previous
        if delta == 0 { return nil }
        return delta > 0 ? "较上一遍提升 +\(delta) 分" : "较上一遍低 \(abs(delta)) 分"
    }

    /// 卡①任务标签（真实 take.taskType 派生）
    private var taskTypeLabel: String {
        switch take.taskType {
        case "warmup": "热身"
        case "reward": "奖励曲"
        case "review": "复习" // Stage B §3d
        default: "主课练习" // main / 空
        }
    }

    /// 卡①标题：曲目真实名（piece.title → take.title → 自由弹奏）
    private var overviewTitle: String {
        piece?.title ?? (take.title.isEmpty ? "自由弹奏" : take.title)
    }

    /// 卡①标题后缀：真实小节范围；无范围不拼（不编小节号）
    private var overviewMeasureSuffix: String? {
        guard let from = take.measureFrom, let to = take.measureTo else { return nil }
        return " · 第\(from)–\(to)小节"
    }

    /// 问题音总数（真实 wrong+missing+extra）
    private var problemTotal: Int {
        report.wrongCount + report.missingCount + report.extraCount
    }

    /// 真实小节区间（measureFrom...measureTo；反向/缺失 → nil，不画热力图）。
    /// 校验与详情页共用一处（PracticeHeatGrid.range）。
    private var measureRange: ClosedRange<Int>? {
        PracticeHeatGrid.range(from: take.measureFrom, to: take.measureTo)
    }

    /// 小节 → 真实问题音数（report.problems 按小节统计；无法定位的行不计入任何格）
    private var problemCountByMeasure: [Int: Int] {
        var counts: [Int: Int] = [:]
        for problem in report.problems {
            guard let measure = problem.measure else { continue }
            counts[measure, default: 0] += 1
        }
        return counts
    }

    /// 小节 → 热度（report.measureHeat，0...1；无该小节 = 0）。查表实现与详情页共用一处。
    private var heatByMeasure: [Int: Double] {
        report.measureHeat.heatByMeasure
    }

    /// 最热小节（真实 heat 最大者；并列取较小小节）；无数据 → nil
    private var hottestMeasure: Int? {
        report.measureHeat
            .sorted { $0.heat == $1.heat ? $0.measure < $1.measure : $0.heat > $1.heat }
            .first?.measure
    }

    /// 六维轴分（0...1）。真值顺序（顶点顺时针）：音准/节奏/连续性/速度/读谱/双手协同。
    /// 音准与读谱同源 pitchScore（恒等，沿用 S05 诚实模式）；力度不进雷达。
    private var radarAxisScores: [Double?] {
        let pitch = dimensionScore(named: "音高")
        let rhythm = dimensionScore(named: "节奏")
        let tempo = dimensionScore(named: "速度稳定性")
        let continuity = dimensionScore(named: "连续性")
        let hands = dimensionScore(named: "双手协同")
        let normalize: (Int?) -> Double? = { $0.map { Double($0) / 100 } }
        return [normalize(pitch), normalize(rhythm), normalize(continuity), normalize(tempo), normalize(pitch), normalize(hands)]
    }

    /// 从真实六维行取分（统计级/无分析态 dimensions 为空 → nil）
    private func dimensionScore(named name: String) -> Int? {
        report.dimensions.first { $0.name == name }?.score
    }

    /// 力度维（真值雷达没有这一轴 → 只驱动卡⑤）
    private var dynamicsScore: Int? {
        dimensionScore(named: "力度")
    }

    /// 雷达下注记：nil 维度的真实原因（已上线信息，不随雷达改版丢掉）。
    /// 全部六维都有分时返回 nil → 不渲染。
    private var nilDimensionNote: String? {
        guard report.state == .scored else { return nil }
        let missing = report.dimensions.filter { $0.score == nil }
        guard !missing.isEmpty else { return nil }
        let items = missing.map { "\($0.name)（\($0.note)）" }.joined(separator: "、")
        return "音准与读谱同源同一音准分；本次未评分：\(items)。"
    }

    /// 再练一遍的起速度（真实：曲目参考速度优先，回退本次 take 均速；0 = 不显）
    private var practiceTempo: Int {
        let reference = piece?.referenceTempo ?? 0
        return reference > 0 ? reference : take.tempoAvg
    }

    private var practiceButtonTitle: String {
        practiceTempo > 0 ? "再练一遍 ♩=\(practiceTempo)" : "再练一遍"
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    overviewCard          // ① 总览（分值 + 雷达）
                    lowConfidenceBanner   // 低置信琥珀条（真实 canEvaluate=false）
                    problemsCard          // ② 错音与漏音（热力 + 明细）
                    rhythmCard            // ③ 节奏（偏差折线）
                    tempoCard             // ④ 速度与连续性
                    dynamicsCard          // ⑤ 力度
                    passProgressCard      // 过关进度（硬指标/连续 N/2，已上线能力）
                    statisticsCard        // P1 原始统计（已上线能力）
                    confidenceCard        // 对齐置信度 + 「只听我弹的」
                    confidenceFootnote    // 置信度脚注
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color.canvas)
        // 底部固定栏（渐变 + 顶边发丝线 + blur）；safeAreaInset 自动给滚动区留出空间
        .safeAreaInset(edge: .bottom) { bottomBar }
        // 提前预热「我弹的」：点按钮时大概率已 ready，直接出声
        .onAppear { preloadTakeNotesIfNeeded() }
        // 与其它全屏页一致：返回不留音频图（左上关闭同样走这里）
        .onDisappear { takePlayer.teardown() }
        .sheet(isPresented: $showMarkSheet) {
            S13bMarkSheet(
                scoreName: title,
                measure: markSheetMeasure
            ) { type, note, _ in
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
        .fullScreenCover(isPresented: $showCompare) {
            S21CompareView(takeA: take)
        }
    }

    private func submitMark(type: String, note: String) {
        let measure = markSheetMeasure
        // 同小节重复提交合并计数（spec）
        if let existing = errorMarks.first(where: { $0.scoreName == title && $0.measure == measure }) {
            existing.occurrenceCount += 1
            existing.type = type
            if !note.isEmpty { existing.note = note }
        } else {
            context.insert(ScoreErrorMark(scoreName: title, measure: measure, type: type, note: note))
        }
    }

    // MARK: S13c 听音（期望音 / 我弹的；只播放，不写任何数据）

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

    /// 只听某一小节的期望音（同一 onset / 同长的柱式和弦）。
    /// 无参考谱、该小节无音或越界 → 静默 return（零打断）。
    private func playExpected(measure: Int) {
        guard let table = expectedPerMeasureTable() else { return }
        // 外层 index 是 0-based 小节；展示值 1-based
        let index = measure - 1
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

    /// .onAppear 预热「我弹的」——原始事件解析成演奏音符（判分同口径）后预装载序列。
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

    // MARK: 顶部导航（真值 §2：✕ 关闭 + serif 标题 + 右侧序位 + S21 对比入口）

    private var navBar: some View {
        ZStack {
            Text("Take 报告")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .tracking(0.4) // 真值 tracking-wide
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            HStack(spacing: 8) {
                closeButton
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if take.pieceId != nil {
                        Button {
                            showCompare = true
                        } label: {
                            Text("对比")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.amber)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.amber.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    ordinalLabel
                }
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.border.opacity(0.4)) // 真值 #332D29 40%
                .frame(height: 1)
        }
    }

    /// 关闭钮（真值 32×32pt 圆形；Material close 22px ≈ SF xmark 18pt 光学重量）。
    /// 行为不变：关闭报告（不是返回箭头）。
    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.textMuted)
                .frame(width: 32, height: 32)
                .background(Color.card, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    /// 右侧「第 N 遍 · <相对时间>」；无归属曲目时不显序位（不编遍数）
    private var ordinalLabel: some View {
        Group {
            if let ordinal = takeOrdinal {
                Text("第 \(ordinal) 遍 · \(relativeTimeText)")
            } else {
                Text(relativeTimeText)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.textMuted)
    }

    // MARK: 卡① 总览（分值 + 雷达）

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            overviewMetaRow
            Rectangle()
                .fill(Color.border.opacity(0.6)) // 真值 #332D29 60%
                .frame(height: 1)
                .padding(.vertical, 14)
            HStack(alignment: .top, spacing: 8) {
                scoreColumn
                    .frame(width: 150, alignment: .leading)
                Spacer(minLength: 0)
                radar
            }
            if let note = nilDimensionNote {
                // 已上线能力：nil 维度的真实原因不能随雷达改版丢掉
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            HStack {
                Spacer(minLength: 0)
                nekoButton
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
        // 真值装饰光：128×128pt 琥珀 5% 圆 + blur；overlay 不参与布局，出界部分被圆角裁掉
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.amber.opacity(0.05))
                .frame(width: 128, height: 128)
                .blur(radius: 20)
                .offset(x: 40, y: -40)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// 上行：任务标签 + 标题（含真实小节范围后缀）｜右列速度与时长
    private var overviewMetaRow: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(taskTypeLabel)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.6) // 真值 tracking-wider
                    .foregroundStyle(Color.amber)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.amber.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4).strokeBorder(Color.amber.opacity(0.2), lineWidth: 1)
                    )
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(overviewTitle)
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .tracking(-0.2)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let suffix = overviewMeasureSuffix {
                        Text(suffix)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if take.tempoAvg > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer") // 真值 Material speed
                            .font(.system(size: 14))
                            .foregroundStyle(Color.amber)
                        Text("♩=\(take.tempoAvg)")
                            .font(.labelMono(12))
                            .foregroundStyle(Color.textMuted)
                    }
                }
                Text("时长 \(take.durationSec / 60)分\(take.durationSec % 60)秒")
                    .font(.labelMono(11))
                    .foregroundStyle(Color.s13Subtle)
            }
        }
    }

    /// 左列：综合参考分（nil → 数据不足，不放假分）+ 脚注 + 提升 badge
    private var scoreColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("综合参考")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textMuted)
                .padding(.bottom, 4)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let weakTotal = report.weakTotal {
                    Text("\(weakTotal)")
                        .font(.system(size: 48, weight: .bold, design: .serif))
                        .tracking(-1) // 真值 tracking-tighter
                        .foregroundStyle(Color.amber)
                    Text("/ 100")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                } else {
                    // 没有真实弱总分（统计级/无分析）→ 显数据不足，不编分
                    Text("数据不足")
                        .font(.system(size: 20, weight: .medium, design: .serif))
                        .foregroundStyle(Color.textMuted)
                }
            }
            Text("进步参考分（不作过关依据）")
                .font(.system(size: 11))
                .foregroundStyle(Color.s13Subtle)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
            if let improvement = improvementText {
                let isGain = improvement.hasPrefix("较上一遍提升")
                HStack(spacing: 4) {
                    Image(systemName: isGain ? "arrow.up" : "arrow.down")
                        .font(.system(size: 12))
                    Text(improvement)
                }
                .font(.system(size: 10))
                .foregroundStyle(isGain ? Color.amber : Color.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.amber.opacity(0.2), lineWidth: 1)
                )
                .fixedSize()
                .padding(.top, 10)
            }
        }
    }

    /// 「问 Neko 这一段」（已上线功能，真值无此钮；琥珀小钮，逻辑不变）
    private var nekoButton: some View {        Button {
            showChat = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cat")
                    .font(.system(size: 13))
                Text("问 Neko 这一段")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.amber)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.amber.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(S13PressScaleButtonStyle(scale: 0.95))
    }

    /// 六维雷达（真值 145×145；三环六边形 + 六轴；nil 轴只画标签）
    private var radar: some View {
        let scores = radarAxisScores
        // 只连非 nil 真实顶点（参考 S05ResultView 诚实写法）
        let points: [CGPoint] = scores.enumerated().compactMap { index, score in
            score.map { S13RadarGeometry.vertex(index, radius: CGFloat($0) * S13RadarGeometry.outerRadius) }
        }
        return ZStack {
            // 三环：内环虚线、中环实线 #332D29、外环 #3F3732
            S13Hexagon(radius: S13RadarGeometry.innerRadius)
                .stroke(Color.border, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            S13Hexagon(radius: S13RadarGeometry.middleRadius)
                .stroke(Color.border, lineWidth: 1)
            S13Hexagon(radius: S13RadarGeometry.outerRadius)
                .stroke(Color.s13RingOuter, lineWidth: 1)
            S13RadarSpokes()
                .stroke(Color.border, lineWidth: 1)

            // 数据多边形：amber 22% 填充 + 1.8pt 描边；只连真实顶点
            S13RadarPolygon(points: points)
                .fill(Color.amber.opacity(0.22))
            S13RadarPolygon(points: points)
                .stroke(Color.amber, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
            ForEach(points.indices, id: \.self) { index in
                Circle()
                    .fill(Color.amber)
                    .frame(width: 4.4, height: 4.4) // 真值 r 2.2
                    .position(points[index])
            }

            // 轴标签：nil 轴同样画标签（无顶点、无数值）
            ForEach(0..<S13RadarAxis.names.count, id: \.self) { index in
                radarLabel(index)
            }
        }
        .frame(width: S13RadarGeometry.canvas.width, height: S13RadarGeometry.canvas.height)
    }

    /// 轴标签（真值 8.5px → 9pt 保可读；muted）
    private func radarLabel(_ index: Int) -> some View {
        let anchor = S13RadarAxis.anchors[index]
        return Text(S13RadarAxis.names[index])
            .font(.system(size: 9))
            .foregroundStyle(Color.textMuted)
            .frame(width: 44, alignment: S13RadarAxis.alignments[index])
            .position(anchor)
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

    // MARK: 卡② 错音与漏音（热力格 + 明细 + 只练错误热点）

    private var problemsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader("错音与漏音", badge: "\(problemTotal) 处")
                // 分类计数（真实 wrong/missing/extra；长按入口说明）
                Text("错音 \(report.wrongCount) · 漏音 \(report.missingCount) · 多弹 \(report.extraCount)　长按明细行可听期望音 / 标记谱错")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 8)
                heatSection
                    .padding(.top, 12)
                // C4：双条 + 关键 delta（这一遍 vs 上一遍；无上一遍则不画）
                heatDeltaSection
                    .padding(.top, 12)
                problemsDetail
                problemsAction
            }
        }
    }

    /// 热力图：只画真实小节区间；格内数字＝该小节真实问题音数
    /// 格子本体与档位阈值走共享件 PracticeHeatCell / PracticeHeatTier（详情页同一处，不复制第二份）。
    @ViewBuilder
    private var heatSection: some View {
        if let range = measureRange, !report.measureHeat.isEmpty {
            // 只按需取出前 N 格（区间可能很长，不整体物化）
            let shown = PracticeHeatGrid.shownMeasures(range, limit: PracticeHeatGrid.reportCellLimit)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("小节分布 (\(range.lowerBound) - \(range.upperBound))")
                        .font(.labelMono(10))
                        .foregroundStyle(Color.s13Subtle)
                    Spacer(minLength: 8)
                    if let hottest = hottestMeasure {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.s13AmberDeep)
                                .frame(width: 8, height: 8)
                            Text("重点集中于 \(hottest) 小节")
                                .font(.labelMono(10))
                                .foregroundStyle(Color.s13Subtle)
                        }
                    }
                }
                LazyVGrid(
                    columns: PracticeHeatGrid.items,
                    spacing: 6
                ) {
                    ForEach(shown, id: \.self) { measure in
                        PracticeHeatCell(
                            measure: measure,
                            heat: heatByMeasure[measure] ?? 0,
                            problemCount: problemCountByMeasure[measure] ?? 0
                        )
                    }
                }
                .padding(6)
                .background(Color.s13HeatWell, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border.opacity(0.6), lineWidth: 1)
                )
                if let note = PracticeHeatGrid.truncationText(total: range.count, shown: shown.count) {
                    // 区间异常长时只画前 N 格，并如实说明，不悄悄截断
                    Text(note)
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                }
            }
        } else if let range = measureRange {
            // 有区间但没有任何热度数据（无逐音对齐）→ 显问题清单即可，不画空图
            Text("第\(range.lowerBound)–\(range.upperBound)小节没有可统计的问题热度。")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
        } else {
            Text("本次 take 没有小节区间（自由弹奏），不画热力图。")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
        }
    }

    // MARK: C4 错音热力双条 + 关键 delta（这一遍 vs 上一遍）

    /// 双条 + 关键 delta：小节数轴并排两条（上＝上一遍、下＝这一遍）+ |delta| 前 3。
    /// 上一遍取同曲目上一条 take 自己那条分析行（口径同 previousWeakTotal）：
    /// 两遍各自单 take 单行，只并排比较，不跨 take 聚合、不改存储、不平均。
    /// 无上一遍 → 不画双条，显「暂无上一遍对比」（首遍练习如实说，不放假对比）。
    @ViewBuilder
    private var heatDeltaSection: some View {
        if let range = measureRange, !report.measureHeat.isEmpty {
            let bars = PracticeHeatBar.bars(
                previous: previousMeasureHeat,
                current: report.measureHeat,
                measures: PracticeHeatGrid.shownMeasures(range, limit: PracticeHeatGrid.reportCellLimit)
            )
            if previousMeasureHeat.isEmpty {
                Text(PracticeHeatText.noPreviousPass)
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
            } else if bars.isEmpty {
                Text(PracticeHeatText.noSharedMeasures)
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
            } else {
                let deltas = PracticeHeatDelta.list(
                    previous: previousMeasureHeat,
                    current: report.measureHeat
                )
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("较上一遍")
                            .font(.labelMono(10))
                            .foregroundStyle(Color.s13Subtle)
                        Spacer(minLength: 8)
                        // 双条方向说明（上条＝上一遍、下条＝这一遍；颜色深浅同热力三档）
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 8))
                            Text("上一遍")
                            Image(systemName: "arrow.down")
                                .font(.system(size: 8))
                            Text("这一遍")
                        }
                        .font(.labelMono(10))
                        .foregroundStyle(Color.s13Subtle)
                    }
                    LazyVGrid(
                        columns: PracticeHeatGrid.items,
                        spacing: 6
                    ) {
                        ForEach(bars) { bar in
                            heatDeltaColumn(bar)
                        }
                    }
                    .padding(6)
                    .background(Color.s13HeatWell, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border.opacity(0.6), lineWidth: 1)
                    )
                    // 关键 delta：|delta| 最大的前 3 个小节（正=这一遍更热=问题更多）
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(deltas) { delta in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(delta.deltaPercent > 0 ? Color.s13Danger : Color.amber)
                                    .frame(width: 5, height: 5)
                                Text(delta.text)
                                    .font(.labelSm)
                                    .foregroundStyle(Color.textPrimary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    /// 双条的一列：上条＝上一遍、下条＝这一遍，底部小节标号与热力格对齐
    private func heatDeltaColumn(_ bar: PracticeHeatBar) -> some View {
        VStack(spacing: 2) {
            heatDeltaBar(heat: bar.previousHeat)
            heatDeltaBar(heat: bar.currentHeat)
            Text("\(bar.measure)")
                .font(.labelMono(10))
                .foregroundStyle(Color.textMuted)
        }
    }

    /// 单条热度（颜色深浅映射 heat，档位与热力格同一处：PracticeHeatTier）
    private func heatDeltaBar(heat: Double) -> some View {
        let tier = PracticeHeatTier.tier(heat: heat)
        return RoundedRectangle(cornerRadius: 3)
            .fill(tier.fill)
            .frame(height: 10)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(tier.border, lineWidth: 1))
    }

    /// 明细行（真实 report.problems；数量不限，不截断）
    @ViewBuilder
    private var problemsDetail: some View {
        if !report.problems.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(Color.border.opacity(0.5))
                    .frame(height: 1)
                    .padding(.top, 12)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(report.problems.indices, id: \.self) { index in
                        problemRow(report.problems[index])
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    private func problemRow(_ problem: ProblemNote) -> some View {
        let marked = problem.measure.map { analysis.excludedMeasures.contains($0) } ?? false
        return HStack(spacing: 8) {
            Circle()
                .fill(problem.kind == .wrongPitch ? Color.s13Danger : Color.amber)
                .frame(width: 6, height: 6)
            Group {
                if let measure = problem.measure {
                    Text("第\(measure)小节·第\(beatText(problem.beatInMeasure))拍")
                } else {
                    // 多弹音谱面无对应参考位置 → 如实说，不编小节
                    Text("谱面无此音")
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.textPrimary)
            if marked {
                // S13b：该小节已被标疑似谱错（真实 errorMarks）
                Text("疑似谱错")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.amber)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(Capsule().strokeBorder(Color.amber.opacity(0.4), lineWidth: 1))
            }
            Spacer(minLength: 8)
            Text(problem.detailText)
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            if let measure = problem.measure {
                if canPreviewExpected {
                    Button {
                        playExpected(measure: measure)
                    } label: {
                        Label("只听这小节期望音", systemImage: "music.note")
                    }
                }
                Button {
                    markSheetMeasure = measure
                    showMarkSheet = true
                } label: {
                    Label("标记疑似谱面错误", systemImage: "flag")
                }
            }
        }
    }

    /// 「只练错误热点」（接再练一遍；无 practiceScoreFile 时禁用）
    @ViewBuilder
    private var problemsAction: some View {
        if problemTotal > 0 {
            HStack {
                Spacer(minLength: 0)
                Button {
                    showPractice = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill") // 真值 Material my_location
                            .font(.system(size: 14))
                        Text("只练错误热点")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.amber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Color.amber.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(S13PressScaleButtonStyle(scale: 0.95))
                .disabled(practiceScoreFile == nil)
                .opacity(practiceScoreFile == nil ? 0.5 : 1)
            }
            .padding(.top, 12)
        }
    }

    // MARK: 卡③ 节奏（真实逐音偏差折线）

    private var rhythmCard: some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader("节奏")
                if report.rhythmPoints.count < 2 {
                    // 不足 2 个点不画空图、不编点
                    Text("可计时匹配不足，节奏曲线数据不足")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 14)
                } else {
                    rhythmChart
                        .padding(.top, 14)
                    // 已上线能力：偏差中位与抢/拖倾向（真实 rhythmMedianMs / rhythmTendency）
                    Text("偏差中位 \(Int(report.rhythmMedianMs.rounded()))ms · \(report.rhythmTendency)")
                        .font(.labelMono(11))
                        .foregroundStyle(report.rhythmTendency == "数据不足" ? Color.textMuted : Color.textPrimary)
                        .padding(.top, 8)
                    rhythmHint
                        .padding(.top, 8)
                }
            }
        }
    }

    private var rhythmChart: some View {
        let points = report.rhythmPoints
        let window = standards.tolerance.timingWindowMs
        let geometry = S13RhythmChartGeometry(
            points: points,
            yMax: S13RhythmChartGeometry.yMax(points: points, windowMs: window),
            windowMs: window
        )
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("拍子偏差 (ms)")
                    .font(.labelMono(10))
                    .foregroundStyle(Color.textMuted)
                Spacer(minLength: 8)
                // 容限用真实 timingWindowMs（不写死 ±50）
                Text("容限区间 ±\(Int(window.rounded()))ms")
                    .font(.labelMono(10))
                    .foregroundStyle(Color.s13Subtle)
            }
            GeometryReader { proxy in
                let layout = geometry.layout(size: proxy.size)
                ZStack {
                    // 容限带（±真实 window）
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.amber.opacity(0.10),
                                    Color.amber.opacity(0.03),
                                    Color.amber.opacity(0.10),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: layout.width, height: geometry.bandHeight(layout.height))
                        .position(x: layout.width / 2, y: layout.height / 2)
                    // 上下容限虚线
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geometry.y(geometry.windowMs, height: layout.height)))
                        path.addLine(to: CGPoint(x: layout.width, y: geometry.y(geometry.windowMs, height: layout.height)))
                        path.move(to: CGPoint(x: 0, y: geometry.y(-geometry.windowMs, height: layout.height)))
                        path.addLine(to: CGPoint(x: layout.width, y: geometry.y(-geometry.windowMs, height: layout.height)))
                    }
                    .stroke(Color.border, style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
                    // 0 轴
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geometry.y(0, height: layout.height)))
                        path.addLine(to: CGPoint(x: layout.width, y: geometry.y(0, height: layout.height)))
                    }
                    .stroke(Color.s13AxisZero, lineWidth: 1)
                    // 折线（平滑）
                    S13RhythmPath(points: layout.coordinates)
                        .stroke(Color.amber, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    // 数据点
                    ForEach(layout.coordinates.indices, id: \.self) { index in
                        Circle()
                            .fill(Color.amber)
                            .frame(width: 4, height: 4) // 真值 r2
                            .position(layout.coordinates[index])
                    }
                    // 尖峰：|deltaMs| 最大的真实点
                    if let spike = layout.spikeIndex {
                        Circle()
                            .fill(Color.s13AmberDeep)
                            .frame(width: 8, height: 8) // 真值 r4
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 1))
                            .position(layout.coordinates[spike])
                        spikeBubble(geometry: geometry, layout: layout, index: spike)
                    }
                }
            }
            .frame(height: 96)
            .padding(8)
            .background(Color.s13ChartWell, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border.opacity(0.6), lineWidth: 1)
            )
            // X 刻度：真实小节号；无法定位的显「?」（不编小节）
            HStack(spacing: 0) {
                ForEach(points.indices, id: \.self) { index in
                    let isSpike = geometry.spikeIndex == index
                    Text(points[index].measure.map { "\($0)" } ?? "?")
                        .font(.labelMono(9, weight: isSpike ? .bold : .regular))
                        .foregroundStyle(isSpike ? Color.amber : Color.s13Subtle)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    /// 尖峰气泡：真实带符号 ms + 真实抢/拖倾向
    private func spikeBubble(
        geometry: S13RhythmChartGeometry, layout: S13RhythmChartGeometry.Layout, index: Int
    ) -> some View {
        let point = geometry.points[index]
        let signed = String(format: "%+.0fms", point.deltaMs)
        let spike = layout.coordinates[index]
        let above = point.deltaMs > 0
        return Text("\(signed) · \(report.rhythmTendency)")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.s13AmberDeep, in: RoundedRectangle(cornerRadius: 6))
            .fixedSize()
            .position(
                x: min(max(spike.x, 60), max(60, layout.width - 60)),
                y: above ? max(10, spike.y - 16) : min(layout.height - 10, spike.y + 16)
            )
    }

    /// 教学提示：诚实通用文案（不写真值示例句）
    private var rhythmHint: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lightbulb") // 真值 Material lightbulb
                .font(.system(size: 15))
                .foregroundStyle(Color.amber)
            Text(rhythmHintText)
                .font(.system(size: 12))
                .foregroundStyle(Color.textMuted)
        }
    }

    private var rhythmHintText: String {
        let window = standards.tolerance.timingWindowMs
        guard let peak = report.rhythmPoints.max(by: {
            abs($0.deltaMs) < abs($1.deltaMs)
        }) else {
            return "可计时匹配不足，节奏曲线数据不足"
        }
        guard abs(peak.deltaMs) > window else { return "节奏稳定，偏差都在容限内" }
        if let measure = peak.measure {
            return "最大偏差出现在第 \(measure) 小节，建议先用更慢速度把这一段对齐"
        }
        return "最大偏差超出容限，建议先用更慢速度把这一段对齐"
    }

    // MARK: 卡④ 速度与连续性

    private var tempoCard: some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader("速度与连续性")
                HStack(spacing: 12) {
                    avgTempoSubcard
                    interruptionSubcard
                }
                .padding(.top, 14)
            }
        }
    }

    /// 左：实际均速（目标＝真实 referenceTempo；无目标不显「/目标」）
    private var avgTempoSubcard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("实际均速")
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)
            if report.avgBPM > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("♩=\(Int(report.avgBPM.rounded()))")
                        .font(.labelMono(18, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    let target = piece?.referenceTempo ?? 0
                    if target > 0 {
                        Text("/ 目标 \(target)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.s13Subtle)
                    }
                }
                if let deviation = tempoDeviationText {
                    HStack(spacing: 4) {
                        Image(systemName: report.avgBPM >= Double(piece?.referenceTempo ?? 0) ? "arrow.up" : "arrow.down")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.amber)
                        Text(deviation)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.amber)
                    }
                }
                // 已上线能力：速度维达标判定（真实 tempoTargetHit + 参考速度比例）
                Text("参考速度 \(Int(standards.targetTempoRatio * 100))% · \(report.tempoTargetHit ? "已达标" : "未达标")")
                    .font(.system(size: 10))
                    .foregroundStyle(report.tempoTargetHit ? Color.success : Color.s13Danger)
            } else {
                Text("速度算不出")
                    .font(.labelMono(18, weight: .bold))
                    .foregroundStyle(Color.textMuted)
            }
        }
        .modifier(S13SubcardStyle())
    }

    /// 真实偏差百分比（avgBPM vs referenceTempo）；无目标或无速度 → nil
    private var tempoDeviationText: String? {
        let target = piece?.referenceTempo ?? 0
        guard target > 0, report.avgBPM > 0 else { return nil }
        let percent = Int(((report.avgBPM - Double(target)) / Double(target) * 100).rounded())
        if percent == 0 { return nil }
        return percent > 0 ? "高于原速 \(percent)%" : "低于原速 \(abs(percent))%"
    }

    /// 右：停顿次数（真实 interruptionRanges.count；断连按秒记录，映射不了小节就不编）
    private var interruptionSubcard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("停顿次数")
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(take.interruptionRanges.count)")
                    .font(.labelMono(18, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text("次")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMuted)
            }
            Text(take.interruptionRanges.isEmpty ? "无中断记录" : "断连按秒记录，未映射小节")
                .font(.system(size: 10))
                .foregroundStyle(take.interruptionRanges.isEmpty ? Color.s13Subtle : Color.s13Danger)
                .lineLimit(1)
        }
        .modifier(S13SubcardStyle())
    }

    // MARK: 卡⑤ 力度（dynamicsScore；真值那句无来源的定性句已删）

    private var dynamicsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader("力度")
                HStack(spacing: 8) {
                    Image(systemName: "waveform") // 真值 Material graphic_eq
                        .font(.system(size: 16))
                        .foregroundStyle(Color.amber)
                    Group {
                        if let score = dynamicsScore {
                            HStack(spacing: 0) {
                                Text("力度均匀度 ")
                                Text("\(score)")
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                Text("/100")
                            }
                        } else {
                            // 力度维 nil → 样本不足，不编分（真值那句无数据来源的定性句已删）
                            Text("力度样本不足，暂不评分")
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMuted)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.canvas.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border.opacity(0.4), lineWidth: 1)
                )
                .padding(.top, 12)
            }
        }
    }

    // MARK: 过关进度（硬指标实际值/阈值 + 连续 N/2；与 gate 同源，不得删数据）

    @ViewBuilder
    private var passProgressCard: some View {
        if report.state == .scored {
            card {
                VStack(alignment: .leading, spacing: 10) {
                    cardHeader(
                        "过关进度",
                        trailing: "连续达标 \(report.consecutivePasses)/\(report.requiredConsecutivePasses)"
                    )
                    if report.canEvaluate {
                        ForEach(report.passMetrics, id: \.name) { metric in
                            HStack {
                                Text(metric.name)
                                    .font(.labelMd)
                                    .foregroundStyle(Color.textBody)
                                Spacer(minLength: 8)
                                Text("\(metric.actualDisplay)（阈值 \(metric.thresholdDisplay)）")
                                    .font(.labelSm)
                                    .foregroundStyle(Color.textPrimary)
                                    .monospacedDigit()
                                Image(systemName: metric.passed ? "checkmark.circle.fill" : "xmark.circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(metric.passed ? Color.success : Color.danger)
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

    // MARK: P1 原始统计（真实 take 统计 + S13b 谱错剔除可见）

    private var statisticsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                cardHeader("原始统计")
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
                if analysis.hasDetail {
                    // P1 简单匹配口径的错音明细数（与卡② 逐音对齐口径不同，都如实给）
                    statRow("P1 匹配错音明细", "\(analysis.wrongNotes.count) 处")
                }
                Text("匹配口径：P1 简单匹配（音序贪心），非对齐算法；对错判定以逐音对齐（卡②）为准。")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
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

    // MARK: 对齐置信度（真实值 + 0.6 门禁刻度）+ 「只听我弹的」

    private var confidenceCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                cardHeader("对齐置信度")
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
                // B10「只听我弹的」：原样回放本次演奏（保真实时序，不做量化对齐）
                Button {
                    toggleTakePlayback()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isTakePlaying ? "stop.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 13))
                        Text(isTakePlaying ? "停止播放" : "只听我弹的")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(takeNotes == nil ? Color.textMuted : Color.textBody)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(takeNotes == nil ? Color.clear : Color.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(takeNotes == nil)
            }
        }
    }

    /// 置信度脚注（真值逐字文案只在高置信态用；其余态显真实状态）
    private var confidenceFootnote: some View {
        HStack(spacing: 6) {
            Image(systemName: "shield") // 真值 Material verified_user
                .font(.system(size: 13))
                .foregroundStyle(Color.amber)
            Text(confidenceFootnoteText)
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var confidenceFootnoteText: String {
        switch report.state {
        case .noAnalysis:
            return "还没有分析数据，无对齐置信度"
        case .statistics:
            return "统计级结果，无对齐置信度（无参考谱/自由弹奏）"
        case .scored:
            if report.confidence >= ScoringStandards.confidenceGateThreshold {
                return "对齐置信度高 · 踏板已计入判分"
            }
            return "对齐置信度 \(String(format: "%.2f", report.confidence))，低于门禁 · 踏板已计入判分"
        }
    }

    private func beatText(_ beatInMeasure: Double?) -> String {
        guard let beatInMeasure else { return "—" }
        return String(format: "%g", beatInMeasure + 1)
    }

    // MARK: 底部固定栏（真值 §9：主钮 h48 r12 + 次钮 h40 r12）

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Button {
                showPractice = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.trianglehead.clockwise") // 真值 Material replay (fill)
                        .font(.system(size: 15))
                    Text(practiceButtonTitle)
                }
                .font(.system(size: 15, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Color.canvas)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.amber, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.amber.opacity(0.25), radius: 16, y: 4)
            }
            .buttonStyle(S13PressScaleButtonStyle(scale: 0.98))
            Button {
                dismiss()
            } label: {
                Text("返回今日")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1)
                    )
            }
            .buttonStyle(S13PressScaleButtonStyle(scale: 0.98))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                // SwiftUI 没有 backdrop-filter；.ultraThinMaterial 近似真值 backdrop-blur-sm
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [Color.clear, Color.canvas.opacity(0.95), Color.canvas],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.border.opacity(0.3)) // 真值 #332D29 30%
                    .frame(height: 1)
            }
        }
    }

    // 热力格数量上限已随格子一起抽到共享件（PracticeHeatGrid.reportCellLimit，详情页同源）。
}

// MARK: - 分区卡容器（真值：bg #262220 / r16 / 1pt 边 #332D29 / p16 / 卡间距 14）

private extension TakeReportView {
    func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
    }

    /// 分区卡头（真值：6×14 琥珀竖条 + serif 15 bold；右侧计数 badge 或 trailing 文案）
    func cardHeader(_ title: String, badge: String? = nil, trailing: String? = nil) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.amber)
                .frame(width: 6, height: 14)
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .serif))
                .tracking(0.4) // 真值 tracking-wide
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 8)
            if let badge {
                Text(badge)
                    .font(.labelMono(12, weight: .semibold))
                    .foregroundStyle(Color.s13Danger)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.s13AmberDeep.opacity(0.15), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.s13AmberDeep.opacity(0.3), lineWidth: 1))
            }
            if let trailing {
                Text(trailing)
                    .font(.labelMd)
                    .foregroundStyle(Color.amber)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - 雷达（真值 viewBox 160×160 → 145×145 容器，直接用容器单位绘制）

/// 145×145 画布、中心 (72.5,72.5)、半径 23/35/46（真值三环）
private enum S13RadarGeometry {
    static let canvas = CGSize(width: 145, height: 145)
    static let center = CGPoint(x: 72.5, y: 72.5)
    static let innerRadius: CGFloat = 23
    static let middleRadius: CGFloat = 35
    static let outerRadius: CGFloat = 46

    /// 第 index 个轴的顶点：index 0 = 顶部，顺时针每 60°
    static func vertex(_ index: Int, radius: CGFloat) -> CGPoint {
        let radians = Angle.degrees(-90 + 60 * Double(index)).radians
        return CGPoint(
            x: center.x + radius * CGFloat(cos(radians)),
            y: center.y + radius * CGFloat(sin(radians))
        )
    }
}

/// 六轴名称（真值顺序，顶点顺时针）与标签锚点/对齐
private enum S13RadarAxis {
    static let names = ["音准", "节奏", "连续性", "速度", "读谱", "双手协同"]
    static let anchors: [CGPoint] = [
        CGPoint(x: 72.5, y: 17.5),  // 音准 顶
        CGPoint(x: 117, y: 49.5),   // 节奏 右上
        CGPoint(x: 117, y: 95.5),   // 连续性 右下
        CGPoint(x: 72.5, y: 127.5), // 速度 底
        CGPoint(x: 28, y: 95.5),    // 读谱 左下
        CGPoint(x: 28, y: 49.5),    // 双手协同 左上
    ]
    static let alignments: [Alignment] = [.center, .leading, .leading, .center, .trailing, .trailing]
}

/// 正六边形网格圈
private struct S13Hexagon: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<6 {
            let vertex = S13RadarGeometry.vertex(index, radius: radius)
            if index == 0 {
                path.move(to: vertex)
            } else {
                path.addLine(to: vertex)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// 6 条轴线：中心 → 外圈顶点
private struct S13RadarSpokes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<6 {
            path.move(to: S13RadarGeometry.center)
            path.addLine(to: S13RadarGeometry.vertex(index, radius: S13RadarGeometry.outerRadius))
        }
        return path
    }
}

/// 数据多边形：按给定顶点顺序闭合（nil 轴被跳过 → 只连真实顶点；无顶点 → 空路径）
private struct S13RadarPolygon: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

// 热力格三档已随格子一起抽到共享件（PracticeHeatTier，详情页同源）。

// MARK: - 节奏折线几何（纯函数：给定数据与画布尺寸算像素坐标）

private struct S13RhythmChartGeometry {
    let points: [RhythmPoint]
    /// 竖向半幅（ms）：至少覆盖真实容限，保证容限线一定画得下
    let yMax: Double
    let windowMs: Double
    private let inset: CGFloat = 8

    struct Layout {
        /// 画布尺寸（GeometryReader 实测）
        let canvas: CGSize
        /// 每个数据点的像素坐标（与 points 同序）
        let coordinates: [CGPoint]
        /// |deltaMs| 最大的真实点下标
        let spikeIndex: Int?

        var width: CGFloat { canvas.width }
        var height: CGFloat { canvas.height }
    }

    init(points: [RhythmPoint], yMax: Double, windowMs: Double) {
        self.points = points
        self.yMax = max(yMax, 1)
        self.windowMs = windowMs
    }

    static func yMax(points: [RhythmPoint], windowMs: Double) -> Double {
        let peak = points.map { abs($0.deltaMs) }.max() ?? 0
        return max(windowMs, peak) * 1.25
    }

    /// |deltaMs| 最大的点（真实尖峰）；并列取靠前的
    var spikeIndex: Int? {
        points.indices.max(by: { abs(points[$0].deltaMs) < abs(points[$1].deltaMs) })
    }

    /// deltaMs → y（0 在垂直中点；上正下负）
    func y(_ deltaMs: Double, height: CGFloat) -> CGFloat {
        height / 2 - CGFloat(deltaMs / yMax) * (height / 2 - 4)
    }

    /// 容限带高度（真实 ±windowMs）
    func bandHeight(_ height: CGFloat) -> CGFloat {
        CGFloat(windowMs / yMax) * (height - 8)
    }

    func layout(size: CGSize) -> Layout {
        let step = points.count > 1 ? (size.width - inset * 2) / CGFloat(points.count - 1) : 0
        let coordinates = points.indices.map { index in
            CGPoint(x: inset + step * CGFloat(index), y: y(points[index].deltaMs, height: size.height))
        }
        return Layout(canvas: size, coordinates: coordinates, spikeIndex: spikeIndex)
    }
}

/// 平滑折线（相邻点取中点做二次曲线，接近真值 Q/T 平滑）
private struct S13RhythmPath: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let middle = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: middle, control: previous)
            path.addQuadCurve(to: current, control: middle)
        }
        return path
    }
}

// MARK: - 按钮样式 / 子卡样式

/// 按压缩放（真值 active:scale）
private struct S13PressScaleButtonStyle: ButtonStyle {
    var scale: Double = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 卡④子卡（真值：底 #1C1917 70% / r12 / 1pt 边 #332D29 50% / p12）
private struct S13SubcardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.canvas.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border.opacity(0.5), lineWidth: 1))
    }
}

// 本页字面量色（s13* hex）已随热力格一起抽到共享件 PracticeHeatCell.swift（详情页同源）。

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
        case "review": "复习" // Stage B §3d
        default: "主菜"
        }
        if let from = take.measureFrom, let to = take.measureTo {
            return "\(type) · 第\(from)–\(to)小节"
        }
        return type
    }
}

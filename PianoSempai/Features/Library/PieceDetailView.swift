import SheetMusicCore
import SheetMusicLoader
import SwiftData
import SwiftUI

// MARK: - S09 曲目详情（硬标准真值/选段/最近 take；判分由 CourseEngine 唯一写手）

// MARK: - 练习 CTA 纯决策（M5b 延伸；与 CourseEngine 决策同风格：UI 只呈现，逻辑可测）
//
// 两项决策：主按钮文案 + 是否可点。
// - `.unavailable`（内置教材条目但无谱：车尔尼599）优先于锁定文案：不提供判分入口，
//   但允许自由弹奏（不打分、不推进路线；不拿别的谱冒充，红线 2 / SPEC §10）。
// - 锁定只禁掉可判分的练习入口（拜厄/哈农未到达的条目），导入曲与示例曲不受影响。
enum PracticeCTA {

    static func title(availability: ScoreAvailability, isLocked: Bool) -> String {
        switch availability {
        case .unavailable: return "自由弹奏（不判分）"
        case .samplePiece: return isLocked ? "路线到达后解锁" : "开始练习（示例曲）"
        case .realScore, .bundledScore: return isLocked ? "路线到达后解锁" : "开始练习"
        }
    }

    static func isEnabled(availability: ScoreAvailability, isLocked: Bool) -> Bool {
        if case .unavailable = availability { return true }
        return !isLocked
    }
}

/// 主按钮去向（fullScreenCover(item:) 需要 Identifiable；单一路由收口，不叠多个 cover）
enum PracticeRoute: Identifiable {
    /// 判分练习：S11 练习室（建档 + 评分）
    case practice
    /// 无谱条目（车尔尼599）：S14 自由弹奏沙盒（不建档、不判分）
    case freePlay

    var id: String {
        switch self {
        case .practice: "practice"
        case .freePlay: "freePlay"
        }
    }
}

/// S09 卡片（真值 §3.3）：bg `#262220`、1pt 边 `#332D29`、圆角 **16**、内边距 16、轻投影。
/// 共享 `NocturneCard` 固定 8pt 圆角且被 S07/S08/S13 等多屏复用，不为本屏改全局组件，
/// 故在本文件内加一个 16pt 变体。`Color.card` / `Color.border` 正是这两个 hex（见 Color+Nocturne）。
fileprivate struct S09Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.2), radius: 6, y: 2)
    }
}

struct PieceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var errorMarks: [ScoreErrorMark]
    @Query private var allPieces: [Piece]
    @Query private var takes: [Take]
    /// 判分结果行（S13 同源查询）：最近 take 的「分值」只从这里取真值，不现算
    @Query(sort: \TakeAnalysis.analyzedAt, order: .reverse) private var analyses: [TakeAnalysis]

    /// 内置教材条目（与导入 Piece 二选一）
    var entry: CatalogEntry?
    var piece: Piece?

    @Query private var scoreFiles: [ScoreFile]
    @State private var rangeStart = 1
    @State private var rangeEnd = 8
    /// 主按钮去向（单一路由：practice → S11 练习室 / freePlay → S14 自由弹奏 / demo → 试听全曲）
    @State private var practiceRoute: PracticeRoute?
    /// 点「开始练习」时建档/取到的 Piece（传给练习室，落 take 的 pieceId）
    @State private var resolvedPiece: Piece?
    /// 最近 take 行点开的 S13 报告（与 ArchiveView/NotesView 同一 sheet(item:) 口径）
    @State private var selectedTake: Take?

    private var title: String {
        if let entry { return entry.title }
        return piece?.title ?? ""
    }

    private var referenceTempo: Int {
        entry?.referenceTempo ?? piece?.referenceTempo ?? 0
    }

    private var statusText: String {
        if let entry {
            let state = CourseEngine.catalogStatus(book: entry.book, number: entry.number, pathState: CoursePathState())
            return state == .practicing ? "练习中" : state == .locked ? "未开始" : "未开始"
        }
        return piece.map { p in
            switch p.status {
            case "practicing": "练习中"
            case "passed": "已拿下"
            default: "未开始"
            }
        } ?? ""
    }

    private var scoreName: String {
        entry?.title ?? piece?.title ?? ""
    }

    /// 锁定条目：详情可看（S07b 契约），练习 CTA 禁用并引导
    private var isLocked: Bool {
        guard let entry else { return false }
        return CourseEngine.catalogStatus(book: entry.book, number: entry.number, pathState: CoursePathState()) == .locked
    }

    /// 导入曲目关联的可跟弹谱文件（内置教材暂无谱文件）
    private var linkedScoreFile: ScoreFile? {
        guard let piece, let sourceId = piece.sourceScoreId else { return nil }
        return scoreFiles.first { $0.entityId == sourceId && $0.canFollow }
    }

    /// 谱可用性四态（M5a 纯决策）：realScore / samplePiece / bundledScore / unavailable。
    /// unavailable = 内置教材条目但无谱（车尔尼599）：不冒充样例谱（SPEC §10）。
    private var availability: ScoreAvailability {
        ScoreAvailability.resolve(
            scoreFile: linkedScoreFile,
            isSampleEntry: entry?.isSample ?? false,
            bundledBook: entry?.book,
            bundledNumber: entry?.number ?? 0
        )
    }

    /// 内置公版谱坐标（仅 .bundledScore 有值；传给练习室走 BundledScore 定位）
    private var bundledBook: String? {
        if case let .bundledScore(book, _) = availability { return book }
        return nil
    }

    private var bundledNumber: Int {
        if case let .bundledScore(_, number) = availability { return number }
        return 0
    }

    /// 已建档的 Piece（导入曲直接用；目录条目按 book+number 只读查找，找不到 = 还没练过）
    private var existingPiece: Piece? {
        if let piece { return piece }
        guard let entry else { return nil }
        return allPieces.first { $0.book == entry.book && $0.number == entry.number }
    }

    /// 点「开始练习」时才建档（幂等；只建行，状态仍只由 CourseEngine 写，红线 2）
    private func resolvePracticePiece() -> Piece? {
        if let existingPiece { return existingPiece }
        guard let entry else { return nil }
        return CourseEngine.ensurePiece(for: entry, in: context)
    }

    private var recentTakes: [Take] {
        guard let id = existingPiece?.entityId else { return [] }
        return takes.filter { $0.pieceId == id }.sorted { $0.startedAt > $1.startedAt }
    }

    /// 最近 take 卡展示的 3 条（真实列表的前 3 条）
    private var recentTakeList: [Take] { Array(recentTakes.prefix(3)) }

    /// 该 take 的判分行（与 S13 TakeReportView 同一查询口径）：
    /// `take.analysisId` 回填值优先；旧 take 没回填时回落到 takeId + 当前引擎版本。
    /// 没有分析行 = 还没判分（或引擎版本不同），调用方显式显示「—」，禁止编分（红线 1）。
    private func analysis(for take: Take) -> TakeAnalysis? {
        if let id = take.analysisId, let row = analyses.first(where: { $0.entityId == id }) { return row }
        return analyses.first { $0.takeId == take.entityId && $0.engineVersion == ScoringOrchestrator.engineVersion }
    }

    /// 最近 take 的「分值」文案：真实 weakTotal；分析缺失或 weakTotal 为 nil 都显示「—」
    private func takeScoreText(_ take: Take) -> String {
        guard let weak = analysis(for: take)?.weakTotal else { return "—" }
        return "\(weak)"
    }

    /// 是否有真实分值（决定用琥珀强调色还是 muted 的「—」）
    private func hasTakeScore(_ take: Take) -> Bool {
        analysis(for: take)?.weakTotal != nil
    }

    /// 分级阈值（§9：入门/进阶/高级；内置教材与导入曲按 book 映射）
    private var standards: ScoringStandards {
        ScoringStandards.standards(forBook: entry?.book ?? piece?.book ?? "")
    }

    /// 练习室加载的谱：真实谱用之；示例曲走 Bundle 样例（isSampleEntry）；
    /// 内置公版谱走 bundledBook/Number（无 ScoreFile 行）；无谱 = nil
    private var scoreFileForPractice: ScoreFile? {
        if case let .realScore(file) = availability { return file }
        return nil
    }

    private var practiceCTATitle: String {
        PracticeCTA.title(availability: availability, isLocked: isLocked)
    }

    /// 主按钮可点性：锁定的可判分条目禁用；无谱条目仍可点（进去只是自由弹奏）
    private var practiceCTAEnabled: Bool {
        PracticeCTA.isEnabled(availability: availability, isLocked: isLocked)
    }

    /// 无谱条目（车尔尼599）：走 S14 自由弹奏沙盒——不建 Piece、不判分
    private var isFreePlayEntry: Bool {
        if case .unavailable = availability { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 浮动返回键占位（44×44 热区）：hero 卡从导航行下方开始，不被返回键压住
                    Color.clear.frame(height: 44)
                    heroCard.padding(.top, 4)
                    sampleNoteCard.padding(.top, 12)
                    passStandardCard.padding(.top, 12)
                    noScoreCard.padding(.top, 12)
                    rangeCard.padding(.top, 12)
                    recentTakesCard.padding(.top, 12)

                    // 错误热点练习：TakeAnalysis.hotspotMeasures/measureHeat 已真实落库，
                    // 但「预选热点小节进练习室」这条路还没接（练习室无热点入参）→ 保持禁用，不放假入口
                    Button {
                    } label: {
                        HStack {
                            Text("只练错误热点")
                                .font(.titleMd)
                            Spacer()
                            Text("P2 完整判分后提供")
                                .font(.labelSm)
                                .foregroundStyle(Color.textMuted)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                    }
                    .buttonStyle(SecondaryButtonStyle(isEnabled: false, cornerRadius: 8))
                    .disabled(true)
                    .padding(.top, 8)

                    Button {
                        if isFreePlayEntry {
                            practiceRoute = .freePlay // 不建档、不判分：只进自由弹奏沙盒
                        } else {
                            resolvedPiece = resolvePracticePiece()
                            practiceRoute = .practice
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(practiceCTATitle)
                            if practiceCTAEnabled {
                                Image(systemName: "arrow.right")
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: practiceCTAEnabled, cornerRadius: 12))
                    .disabled(!practiceCTAEnabled)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
            .background(Color.canvas)
            .overlay(alignment: .topLeading) {
                backButton
            }
            .fullScreenCover(item: $practiceRoute) { route in
                switch route {
                case .practice:
                    PracticeRoomView(
                        taskType: "main",
                        scoreFile: scoreFileForPractice,
                        pieceTitle: title,
                        isSampleEntry: entry?.isSample ?? false,
                        piece: resolvedPiece,
                        referenceTempo: referenceTempo,
                        bundledBook: bundledBook,
                        bundledNumber: bundledNumber
                    )
                case .freePlay:
                    // S14 自由弹奏（不打分沙盒）：599 无谱条目的唯一入口。保存后只关掉详情页。
                    FreePlayView(onSaved: { dismiss() })
                }
            }
            .sheet(item: $selectedTake) { take in
                TakeReportView(take: take)
            }
        }
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.textBody)
                .frame(width: 44, height: 44)
        }
    }

    /// Hero 卡（真值 §3.4）：衬线标题 + 状态 pill + meta 区（参考速度、疑似谱错）。
    /// meta 只列真实数据：参考速度来自 entry/piece，疑似谱错来自 ScoreErrorMark 聚合。
    /// 真值里的「当前进度 17–24 小节」没有建模来源（选段起止是用户选择、不是进度）→ 不渲染。
    private var heroCard: some View {
        S09Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text(title)
                        .font(.system(size: 23, weight: .bold, design: .serif))
                        .tracking(-0.3)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    statusPill
                }
                Text(heroSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 6)
                heroMeta.padding(.top, 14)
            }
        }
    }

    /// 曲目来源副标题（真实字段：内置教材 book / 导入曲 book）
    private var heroSubtitle: String {
        if let entry { return "训练教材 · \(entry.book)" }
        guard let piece else { return "" }
        return piece.book.isEmpty ? "曲库曲目" : "曲库曲目 · \(piece.book)"
    }

    /// 状态 pill 三态配色。真值 §3.4 只给了「练习中」= 实琥珀底 + #1C1917 字；
    /// 「已拿下」来自 piece.status（CourseEngine 真实写手）→ 琥珀描边态；
    /// 「未开始」→ 中性态。不引入真值里没有来源的绿色「已拿下」chip。
    private var statusPillStyle: (fill: Color, border: Color, text: Color) {
        switch statusText {
        case "练习中": return (Color.amber, .clear, Color.canvas)
        case "已拿下": return (.clear, Color.amber.opacity(0.45), Color.amber)
        default: return (Color.surface, Color.border, Color.textMuted)
        }
    }

    /// 状态 pill（真值 §3.4）：px8/py2、全圆角、11pt medium、tracking-wider
    private var statusPill: some View {
        let style = statusPillStyle
        return Text(statusText)
            .font(.system(size: 11, weight: .medium))
            .tracking(0.5)
            .foregroundStyle(style.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(style.fill))
            .overlay(Capsule().strokeBorder(style.border, lineWidth: 1))
    }

    /// Hero meta 区：顶部分隔线 + 参考速度 + 疑似谱错（都是真实聚合值）
    private var heroMeta: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.border.opacity(0.7)
                .frame(height: 1)
            HStack(spacing: 6) {
                Image(systemName: "metronome")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textMuted)
                Text("参考速度")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMuted)
                Text("♩=\(referenceTempo)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .monospacedDigit()
            }
            if !errorLine.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "flag")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.amber)
                    Text(errorLine)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.amber.opacity(0.9))
                }
            }
        }
    }

    /// 示例曲标注（演示用途，不冒充教材条目，SPEC §10）
    @ViewBuilder
    private var sampleNoteCard: some View {
        if entry?.isSample == true {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("示例曲 · 演示用")
                        .font(.labelMd)
                        .foregroundStyle(Color.amber)
                    Text("SpikeSample32 是内置演示谱，不是拜厄/哈农/599 的任何一条；可以完整跟弹并判分。")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.amber.opacity(0.35), lineWidth: 1))
        }
    }

    /// 疑似谱错计数（真实 ScoreErrorMark 聚合；无标记返回空串，meta 区整行不渲染）
    private var errorLine: String {
        let marks = errorMarks.filter { $0.scoreName == scoreName }
        guard !marks.isEmpty else { return "" }
        let total = marks.reduce(0) { $0 + $1.occurrenceCount }
        return "疑似谱面错误 \(total) 处"
    }

    /// 无谱诚实态（M5b）：内置教材条目没有谱文件时明确说明，不拿样例谱冒充
    @ViewBuilder
    private var noScoreCard: some View {
        if case .unavailable = availability {
            S09Card {
                VStack(alignment: .leading, spacing: 4) {
                    Text("暂无参考谱")
                        .font(.labelMd)
                        .foregroundStyle(Color.textBody)
                    Text("开放后可判分过关。现在可以自由弹奏、录制（不判分），或用曲库里的「示例曲」体验完整判分。")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
    }

    /// 过关标准卡（阈值来自 ScoringStandards 真值，S09/S13 与 gate 同源）
    // TODO: backlog — technical-goal metadata / OP tag / measure-heat grid
    // 真值 §3.5「技术目标」卡（音阶跑动/右手转指/均匀力度 chips + OP.101 tag）与
    // §3.6「段落与循环」八格已练/热点格：本屏均无建模来源（Piece/CatalogEntry 没有这些字段），
    // 不编造占位；过关标准暂时留在这张卡里（阈值是真的）。等元数据建模后再按真值拆卡。
    private var passStandardCard: some View {
        S09Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("过关标准（硬指标，连续 2 遍达标）")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                standardRow("错音率", String(format: "≤ %.0f%%", standards.maxWrongNoteRate * 100))
                standardRow("节奏偏差中位数", String(format: "≤ %.0fms", standards.maxRhythmMedianMs))
                standardRow(
                    "速度",
                    "≥ 参考速度 \(Int(standards.targetTempoRatio * 100))%（♩=\(Int((Double(referenceTempo) * standards.targetTempoRatio).rounded()))）"
                )
                if case .unavailable = availability {
                    Text("暂无参考谱，开放后可判分过关。")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                }
                Text("由规则引擎判定 · Neko 不能改结果")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    private func standardRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.labelMd).foregroundStyle(Color.textBody)
            Spacer()
            Text(value).font(.labelMd).foregroundStyle(Color.textPrimary).monospacedDigit()
        }
    }

    /// 选段卡：起/止步进器（越界钳制；长按连改走系统重复手势——P1 单击步进）
    private var rangeCard: some View {
        S09Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("选段")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 24) {
                    measureStepper(label: "起", value: $rangeStart, lowerBound: 1, upperBound: rangeEnd - 1)
                    measureStepper(label: "止", value: $rangeEnd, lowerBound: rangeStart + 1, upperBound: 32)
                }
                Text("开始练习将练第 \(rangeStart)–\(rangeEnd) 小节（共 \(rangeEnd - rangeStart + 1) 小节）")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                    .monospacedDigit()
            }
        }
    }

    private func measureStepper(label: String, value: Binding<Int>, lowerBound: Int, upperBound: Int) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.bodyMd)
                .foregroundStyle(Color.textBody)
            Text("\(value.wrappedValue)")
                .font(.labelMono(16, weight: .medium))
                .foregroundStyle(Color.amber)
                .monospacedDigit()
                .frame(minWidth: 30)
            Button {
                value.wrappedValue = max(lowerBound, value.wrappedValue - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(value.wrappedValue <= lowerBound ? Color.textMuted.opacity(0.4) : Color.textBody)
                    .frame(width: 30, height: 30)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(value.wrappedValue <= lowerBound)
            Button {
                value.wrappedValue = min(upperBound, value.wrappedValue + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(value.wrappedValue >= upperBound ? Color.textMuted.opacity(0.4) : Color.textBody)
                    .frame(width: 30, height: 30)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(value.wrappedValue >= upperBound)
        }
    }

    /// 最近 take（≤3；真实 take.pieceId 关联，没有就诚实空态）。
    /// 分值走真实 TakeAnalysis.weakTotal（与 S13 同一查询口径）；没判分就显示「—」。
    private var recentTakesCard: some View {
        S09Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("最近 Take")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    if !recentTakes.isEmpty {
                        Text("共 \(recentTakes.count) 次记录")
                            .font(.labelSm)
                            .foregroundStyle(Color.textMuted)
                            .monospacedDigit()
                    }
                }
                .padding(.bottom, 8)
                if recentTakes.isEmpty {
                    // P1/P2 都如实显示：没练过就是没练过，不借假数据占位（红线 2）
                    Text("还没有 take。练过之后，这里显示最近 3 次。")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 4)
                } else {
                    // 行路由：点行开 S13 Take 报告（.sheet(item:)，与 ArchiveView/NotesView/TakeReportView 一致）；
                    // 本视图唯一 sheet（fullScreenCover 走 practiceRoute，不叠加第二个 sheet 路由）
                    ForEach(recentTakeList, id: \.entityId) { take in
                        Button {
                            selectedTake = take
                        } label: {
                            recentTakeRow(take, isFirst: take.entityId == recentTakeList.first?.entityId)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// 真值 §3.7 行：左时间 13pt + 副行速度/时长；右分值 15pt 琥珀等宽 + 「分值」标注
    private func recentTakeRow(_ take: Take, isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isFirst {
                Color.border.opacity(0.6)
                    .frame(height: 1)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(take.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                    Text("♩=\(take.tempoAvg) · \(take.durationSec / 60)分\(take.durationSec % 60)秒")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.textMuted)
                        .monospacedDigit()
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(takeScoreText(take))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(hasTakeScore(take) ? Color.amber : Color.textMuted)
                    Text("分值")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 1)
                }
                // 可点暗示（L8）：整行已可点开 Take 报告，chevron 与行内 muted 标注同风格
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textMuted)
                    .padding(.leading, 4)
            }
            .frame(minHeight: 44)
            .padding(.vertical, 10)
        }
    }
}

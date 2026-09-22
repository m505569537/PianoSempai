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

struct PieceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var errorMarks: [ScoreErrorMark]
    @Query private var allPieces: [Piece]
    @Query private var takes: [Take]

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
                    header
                    sampleNoteCard.padding(.top, 12)
                    passStandardCard.padding(.top, 16)
                    noScoreCard.padding(.top, 12)
                    rangeCard.padding(.top, 12)
                    recentTakesCard.padding(.top, 12)

                    // P2 占位：完整判分（TakeAnalysis.measureHeat）落地后提供
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.headlineLg)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(statusText)
                    .font(.labelSm)
                    .foregroundStyle(Color.amber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(Capsule().strokeBorder(Color.amber.opacity(0.4), lineWidth: 1))
            }
            .padding(.leading, 44)
            Text("参考速度 ♩=\(referenceTempo) \(errorLine)")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .monospacedDigit()
                .padding(.leading, 44)
        }
        .padding(.top, 12)
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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.amber.opacity(0.35), lineWidth: 1))
        }
    }

    /// 疑似谱错计数（真实 ScoreErrorMark 聚合；无标记不显示）
    private var errorLine: String {
        let marks = errorMarks.filter { $0.scoreName == scoreName }
        guard !marks.isEmpty else { return "" }
        let total = marks.reduce(0) { $0 + $1.occurrenceCount }
        return "· 疑似谱面错误 \(total) 处 ⚠"
    }

    /// 无谱诚实态（M5b）：内置教材条目没有谱文件时明确说明，不拿样例谱冒充
    @ViewBuilder
    private var noScoreCard: some View {
        if case .unavailable = availability {
            VStack(alignment: .leading, spacing: 4) {
                Text("暂无参考谱")
                    .font(.labelMd)
                    .foregroundStyle(Color.textBody)
                Text("开放后可判分过关。现在可以自由弹奏、录制（不判分），或用曲库里的「示例曲」体验完整判分。")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// 过关标准卡（阈值来自 ScoringStandards 真值，S09/S13 与 gate 同源）
    private var passStandardCard: some View {
        NocturneCard {
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
        NocturneCard {
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

    /// 最近 take（≤3；真实 take.pieceId 关联，没有就诚实空态）
    private var recentTakesCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("最近 Take")
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                }
                if recentTakes.isEmpty {
                    // P1/P2 都如实显示：没练过就是没练过，不借假数据占位（红线 2）
                    Text("还没有 take。练过之后，这里显示最近 3 次。")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                } else {
                    ForEach(recentTakes.prefix(3), id: \.entityId) { take in
                        HStack(alignment: .firstTextBaseline) {
                            Text(take.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.labelMd)
                                .foregroundStyle(Color.textBody)
                            Spacer()
                            Text("♩=\(take.tempoAvg) · \(take.durationSec / 60)分\(take.durationSec % 60)秒")
                                .font(.labelSm)
                                .foregroundStyle(Color.textMuted)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}

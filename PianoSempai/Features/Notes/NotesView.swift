import SwiftData
import SwiftUI

// MARK: - S19 练琴笔记（时间线：课后随手记 + Neko 周报 + 待处理问题；笔记可关联 take）
// 布局真值：docs/design-reference/screens/S19-notes/code.html（Stitch 修订稿，非 spec.md）：
// 页底 #161311、卡 #221F1D r8、chips/FAB r12（该稿 rounded-full=12pt，非胶囊）、
// badge 头部行右侧 r2、FAB 底 40 / 右 16。
//
// 呈现：S23「练琴笔记」行以 sheet 进入，内含 NavigationStack；返回 = dismiss（‹ 返回）。
// 导航：新建/编辑走 push（NoteEditView → TakePickerView 同栈），关联 take 走本视图唯一的
//       sheet（TakeReportView 自带 dismiss 语义，不能 push；一视图一 sheet 教训）。
// 红线：只写 PracticeNote，不碰课程/判分/设置状态；weeklyReport 只读（自动生成与
//       「写进下周计划」属 M7.2，本 Stage 不渲染该入口，避免死按钮）；
//       真值里没有诚实来源的细节（如问题卡的「标记于练琴中」）一律不画。

/// 真值 code.html 里有、但共享 DesignSystem 还没有对应 token 的色值。
/// 只在本文件使用，不污染 Color+Nocturne / Assets.xcassets（与 S01 同一约定）。
fileprivate extension Color {
    /// surface-container #221F1D：笔记卡底 / 未选 chip 底
    static let s19CardFill = Color(red: 0x22 / 255, green: 0x1F / 255, blue: 0x1D / 255)
    /// outline-variant #4F4537：卡片 / chip / 关联钮描边
    static let s19OutlineVariant = Color(red: 0x4F / 255, green: 0x45 / 255, blue: 0x37 / 255)
    /// on-primary-container #563900：选中 chip 文字 / FAB 铅笔图标
    static let s19OnPrimaryContainer = Color(red: 0x56 / 255, green: 0x39 / 255, blue: 0x00 / 255)
    /// primary #F3BE67：「课后」badge 字、待处理圆点与文字
    static let s19Primary = Color(red: 0xF3 / 255, green: 0xBE / 255, blue: 0x67 / 255)
    /// outline #9C8F7E：未选 chip 文字
    static let s19Outline = Color(red: 0x9C / 255, green: 0x8F / 255, blue: 0x7E / 255)
    /// on-surface #E9E1DD：卡标题
    static let s19OnSurface = Color(red: 0xE9 / 255, green: 0xE1 / 255, blue: 0xDD / 255)
    /// on-surface-variant #D3C4B2：正文（90%）/ 关联 take 钮 / 卡内动作钮文字
    static let s19OnSurfaceVariant = Color(red: 0xD3 / 255, green: 0xC4 / 255, blue: 0xB2 / 255)
    /// surface-container-high #2D2927：关联 take 钮底
    static let s19SurfaceContainerHigh = Color(red: 0x2D / 255, green: 0x29 / 255, blue: 0x27 / 255)
    /// secondary-fixed-dim #EAC085：「Neko 周报」badge 字（暖金）
    static let s19SecondaryFixedDim = Color(red: 0xEA / 255, green: 0xC0 / 255, blue: 0x85 / 255)
    /// error #FFB4AB：「问题」badge 字与描边
    static let s19Error = Color(red: 0xFF / 255, green: 0xB4 / 255, blue: 0xAB / 255)
}

struct NotesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \PracticeNote.createdAt, order: .reverse) private var notes: [PracticeNote]
    @Query(sort: \Take.startedAt, order: .reverse) private var takes: [Take]
    @Query private var pieces: [Piece]

    @State private var chip: NotesChip = .all
    @State private var searchText = ""
    @State private var isSearching = false
    /// 关联 take → S13 报告（本视图唯一的 sheet）
    @State private var reportTake: Take?
    /// 新建/编辑（push；NoteEditTarget 为空 = 新建）
    @State private var editTarget: NoteEditTarget?

    /// 当前筛选 + 检索后的时间线（规则全在 NotesFilter，视图不内置过滤逻辑）
    private var visibleNotes: [PracticeNote] {
        NotesFilter.apply(notes: notes, chip: chip, query: searchText, takeTitles: takeTitles)
    }

    /// 检索用：只给被引用的 take 建标题索引（spec：take 关联也可检索）
    private var takeTitles: [UUID: String] {
        let linked = Set(notes.compactMap(\.linkedTakeId))
        return takes
            .filter { linked.contains($0.entityId) }
            .reduce(into: [UUID: String]()) { map, take in
                map[take.entityId] = takeShortLabel(take, pieces: pieces)
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    searchField
                    chipsRow
                    timeline
                }
            }
            .background(Color.surface) // 真值页底 #161311（非 canvas #1C1917）
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .bottomTrailing) { fab }
            .tint(Color.amber)
            .navigationDestination(item: $editTarget) { target in
                NoteEditView(target: target)
            }
            .sheet(item: $reportTake) { take in
                TakeReportView(take: take)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .medium))
                            Text("返回")
                        }
                        .foregroundStyle(Color.amber)
                    }
                    .accessibilityLabel("返回")
                }
                ToolbarItem(placement: .principal) {
                    Text("练琴笔记")
                        .font(.headlineSm)
                        .foregroundStyle(Color.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            isSearching.toggle()
                            if !isSearching { searchText = "" }
                        }
                    } label: {
                        Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(isSearching ? Color.amber : Color.textBody)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(isSearching ? "收起搜索" : "搜索笔记")
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: 搜索（可展开输入；标题/正文/take 关联本地检索）

    @ViewBuilder
    private var searchField: some View {
        if isSearching {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textMuted)
                TextField("搜索标题或正文", text: $searchText)
                    .font(.bodyMd)
                    .foregroundStyle(Color.textPrimary)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空搜索词")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderInput, lineWidth: 1))
            .padding(.top, 4)
            .padding(.horizontal, 20)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: 筛选 chips（真值顺序，单选；本屏样式，不动共享 NocturneChip）

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(NotesChip.allCases) { option in
                    NoteFilterChip(title: option.title, isSelected: chip == option) {
                        chip = option
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .padding(.top, 4)
    }

    // MARK: 时间线

    private var timeline: some View {
        LazyVStack(spacing: 16) {
            if visibleNotes.isEmpty {
                emptyState
            }
            ForEach(visibleNotes) { note in
                noteCard(note)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 96) // 让 FAB 不压住最后一张卡
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 26))
                .foregroundStyle(Color.textMuted.opacity(0.6))
            Text(NotesFilter.emptyText(chip: chip, query: searchText))
                .font(.bodySm)
                .leading(19, fontSize: 12)
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 48)
    }

    // MARK: 笔记卡

    private func noteCard(_ note: PracticeNote) -> some View {
        let kind = note.noteKind
        let resolved = note.isResolvedIssue
        return VStack(alignment: .leading, spacing: 8) {
            // 1. 头部行：左真实 createdAt，右类型 badge
            HStack {
                Text(Self.cardDateFormatter.string(from: note.createdAt))
                    .font(.bodySm)
                    .tracking(0.6) // tracking-wide
                    .foregroundStyle(Color.textMuted)
                Spacer(minLength: 8)
                kindBadge(kind)
            }
            // 2. 标题：serif 20pt medium，真实 displayTitle
            Text(note.displayTitle)
                .font(.headlineSm)
                .foregroundStyle(resolved ? Color.textMuted : Color.s19OnSurface)
                .strikethrough(resolved, color: Color.textMuted)
                .lineLimit(2)
                .padding(.top, 2)
            // 3. 正文：14pt / 行高 22，#D3C4B2 90%
            if !note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note.body)
                    .font(.bodyMd)
                    .leading(22, fontSize: 14)
                    .foregroundStyle(resolved ? Color.textMuted : Color.s19OnSurfaceVariant.opacity(0.9))
                    .strikethrough(resolved, color: Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 4. 底部行（按类型：关联 take / 周报生成时间 / 待处理标记）
            noteFooter(note)
            cardActions(note)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.s19CardFill, in: RoundedRectangle(cornerRadius: 8))
        // 边框恒为 outline-variant 20%；未处理问题卡沿用 danger 描边（已处理回归中性）
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    kind == .issue && !resolved ? Color.danger.opacity(0.45) : Color.s19OutlineVariant.opacity(0.2),
                    lineWidth: 1
                )
        )
        .opacity(resolved ? 0.75 : 1)
    }

    /// 卡头日期（真值「M/d EEEE」，如 9/18 周五）
    private static let cardDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("M/d EEEE")
        return formatter
    }()

    /// 类型 badge（真值 §4：头部行右侧，r2 小方块，非胶囊）。
    /// 前置图标取 Material Symbols 的 SF Symbols 对应：auto_awesome → sparkles、error_outline → exclamationmark。
    private func kindBadge(_ kind: NoteKind) -> some View {
        let fill: Color = switch kind {
        case .manual: Color.amber.opacity(0.15)
        case .weeklyReport: Color.sheetTop // #383432
        case .issue: Color.danger.opacity(0.2)
        }
        let border: Color = switch kind {
        case .manual: Color.amber.opacity(0.3)
        case .weeklyReport: Color.s19OutlineVariant.opacity(0.4)
        case .issue: Color.s19Error.opacity(0.3)
        }
        let text: Color = switch kind {
        case .manual: Color.s19Primary
        case .weeklyReport: Color.s19SecondaryFixedDim
        case .issue: Color.s19Error
        }
        let icon: String? = switch kind {
        case .manual: nil
        case .weeklyReport: "sparkles"
        case .issue: "exclamationmark"
        }
        return HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12))
            }
            Text(kind.cardLabel)
        }
        .font(.labelSm)
        .foregroundStyle(text)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(fill, in: RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(border, lineWidth: 1))
    }

    // MARK: 卡内底部行（只画有真实数据来源的行）

    @ViewBuilder
    private func noteFooter(_ note: PracticeNote) -> some View {
        switch note.noteKind {
        case .manual:
            linkedTakeRow(note)
        case .weeklyReport:
            weeklyMetaRow
                .padding(.top, 4)
        case .issue:
            // 已处理问题不显示「待处理」标记：划线归档态由卡面承担
            if note.isResolvedIssue {
                EmptyView()
            } else {
                issueOpenMarker
                    .padding(.top, 4)
            }
        }
    }

    /// 关联 take 钮：可点 → 跳 S13 报告；take 已删除则如实禁用并标注（唯一允许的非可点态）。
    /// 没有 linkedTakeId 时整行省略，不造假入口。
    @ViewBuilder
    private func linkedTakeRow(_ note: PracticeNote) -> some View {
        if let takeId = note.linkedTakeId {
            if let take = takes.first(where: { $0.entityId == takeId }) {
                Button {
                    reportTake = take
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform") // graphic_eq 对应
                            .font(.system(size: 14))
                            .foregroundStyle(Color.amber)
                        Text("关联 take：\(takeShortLabel(take, pieces: pieces)) · \(ChatContextText.stamp(take.startedAt))")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .opacity(0.7)
                    }
                    .font(.labelSm)
                    .foregroundStyle(Color.s19OnSurfaceVariant)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.s19SurfaceContainerHigh, in: RoundedRectangle(cornerRadius: 2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(Color.s19OutlineVariant.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 14))
                    Text("关联的练习已删除")
                }
                .font(.labelSm)
                .foregroundStyle(Color.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.s19SurfaceContainerHigh, in: RoundedRectangle(cornerRadius: 2))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.s19OutlineVariant.opacity(0.3), lineWidth: 1)
                )
                .accessibilityLabel("关联的练习已删除，无法跳转")
                .padding(.top, 4)
            }
        }
    }

    /// 周报底部元信息：clock +「周日 21:00 自动生成」。
    /// 这句话诚实：weeklyReport 笔记确由周报协调器在周日 21:00 生成（WeeklyDigestCoordinator）。
    private var weeklyMetaRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 13))
            Text("周日 21:00 自动生成")
                .font(.bodySm)
        }
        .foregroundStyle(Color.textMuted)
    }

    /// 未处理问题底部标记：6pt 琥珀点 +「待处理」。
    /// 真值同行右侧的「标记于练琴中」不渲染 —— App 当前不记录笔记来源，无诚实数据可写。
    private var issueOpenMarker: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.s19Primary)
                .frame(width: 6, height: 6)
            Text("待处理")
                .tracking(0.9) // tracking-wide
        }
        .font(.labelSm)
        .foregroundStyle(Color.s19Primary)
    }

    /// 卡内动作：manual 可编辑；issue 可标记已处理/重新打开；weeklyReport 只读无入口
    @ViewBuilder
    private func cardActions(_ note: PracticeNote) -> some View {
        switch note.noteKind {
        case .manual:
            Button {
                editTarget = NoteEditTarget(note: note)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                    Text("编辑")
                }
            }
            .buttonStyle(NoteCardActionStyle())
        case .issue:
            Button {
                toggleResolved(note)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: note.isResolvedIssue ? "arrow.uturn.backward" : "checkmark")
                        .font(.system(size: 11))
                    Text(note.isResolvedIssue ? "重新打开" : "标记已处理")
                }
            }
            .buttonStyle(NoteCardActionStyle())
        case .weeklyReport:
            // 周报由 Neko 生成：不可编辑/不可删除；「写进下周计划」等 M7.2 规则引擎，本 Stage 不渲染
            EmptyView()
        }
    }

    /// 问题卡状态切换：划线归档，不删除（S19 真值逻辑沿用）
    private func toggleResolved(_ note: PracticeNote) {
        note.status = note.isResolvedIssue ? NoteStatus.open.rawValue : NoteStatus.resolved.rawValue
        try? context.save()
    }

    // MARK: 新建 FAB（真值 §3.5：56×56、r12、#D4A24E 底、#563900 铅笔、辉光 0/8/24、按压 0.9）

    private var fab: some View {
        Button {
            editTarget = NoteEditTarget()
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.s19OnPrimaryContainer)
                .frame(width: 56, height: 56)
                .background(Color.amber, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.amber.opacity(0.35), radius: 12, x: 0, y: 8)
        }
        .buttonStyle(NotePressStyle(pressedScale: 0.9))
        .padding(.trailing, 16)
        .padding(.bottom, 40)
        .accessibilityLabel("新建笔记")
    }
}

// MARK: - 本屏专用小组件（不进 DesignSystem：仅 S19 真值形态）

/// 筛选 chip（真值 §3.3：r12 圆角、px14/py6、12pt medium、chip 间距 4）。
/// 选中 = #D4A24E 底 + #563900 深棕字 + 琥珀辉光 0/0/12，按压 opacity 0.9；
/// 未选 = #221F1D 底 + outline-variant 30% 描边 + #9C8F7E 字。
private struct NoteFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.labelMd)
                .foregroundStyle(isSelected ? Color.s19OnPrimaryContainer : Color.s19Outline)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.amber : Color.s19CardFill,
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isSelected ? Color.clear : Color.s19OutlineVariant.opacity(0.3),
                            lineWidth: 1
                        )
                )
                .shadow(color: isSelected ? Color.amber.opacity(0.2) : .clear, radius: 6)
        }
        .buttonStyle(NotePressStyle(pressedOpacity: 0.9))
    }
}

/// 卡内动作钮（真值未给形态：按本屏视觉语言复刻——r8 描边小钮，pressed 琥珀化）。
/// 共享 NoteActionButtonStyle 是胶囊形且被 S22 月报卡共用，不在本屏改动范围。
private struct NoteCardActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.labelMd)
            .foregroundStyle(configuration.isPressed ? Color.amber : Color.s19OnSurfaceVariant)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                configuration.isPressed ? Color.s19SurfaceContainerHigh : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.amber.opacity(configuration.isPressed ? 0.6 : 0.3), lineWidth: 1)
            )
    }
}

/// 按压反馈（真值：选中 chip opacity 0.9 / FAB scale 0.9）
private struct NotePressStyle: ButtonStyle {
    var pressedOpacity: Double = 1
    var pressedScale: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// take 短标签：复用 S18 的 practiceTitle（pieceTitle → take.title → 小节区间 → 中性描述），不另造一套
func takeShortLabel(_ take: Take, pieces: [Piece]) -> String {
    let pieceTitle = take.pieceId.flatMap { id in pieces.first { $0.entityId == id }?.title }
    return ChatContextText.practiceTitle(take: take, pieceTitle: pieceTitle)
}

// MARK: - 预览夹具（内存容器 + 四种类型各一条，含一条已处理问题与一条关联 take）

#if DEBUG
private enum NotesPreviewContainer {
    @MainActor
    static func make() -> ModelContainer {
        let container = try! ModelContainer(
            for: PracticeNote.self, Take.self, TakeAnalysis.self, ScoreErrorMark.self, Piece.self, ScoreFile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let now = Date()

        let piece = Piece(title: "拜厄 45", book: "拜厄", number: 45, totalMeasures: 32)
        context.insert(piece)
        let take = Take(
            startedAt: now.addingTimeInterval(-3600),
            durationSec: 612,
            taskType: "main",
            hasMidi: true,
            measureFrom: 21,
            measureTo: 24,
            tempoAvg: 60,
            noteCount: 180,
            title: "拜厄45 · 转指"
        )
        take.pieceId = piece.entityId
        context.insert(take)

        context.insert(PracticeNote(
            kind: NoteKind.manual.rawValue,
            title: "拜厄45 · 21小节转指",
            body: "今天 60 速度单手 4 遍后，转指卡顿明显少了，手腕提前带过去是有用的。",
            linkedTakeId: take.entityId,
            createdAt: now.addingTimeInterval(-1800)
        ))
        context.insert(PracticeNote(
            kind: NoteKind.weeklyReport.rawValue,
            title: "第 3 周观察",
            body: "热身完成率从 60% 到 100%；21 小节偏差中位数从 48ms 降到 22ms。下周建议保持单手慢速。",
            createdAt: now.addingTimeInterval(-86400 * 2)
        ))
        context.insert(PracticeNote(
            kind: NoteKind.issue.rawValue,
            title: "黑键移动时手腕紧",
            body: "下次试试坐高一点，先单手找位置。",
            status: NoteStatus.open.rawValue,
            createdAt: now.addingTimeInterval(-86400 * 4)
        ))
        context.insert(PracticeNote(
            kind: NoteKind.issue.rawValue,
            title: "左手独立性不足",
            body: "已用慢速分手练习改善，转指前不再顿。",
            status: NoteStatus.resolved.rawValue,
            createdAt: now.addingTimeInterval(-86400 * 6)
        ))
        return container
    }
}
#endif

#Preview {
    NotesView()
        .modelContainer(NotesPreviewContainer.make())
}

import SwiftData
import SwiftUI

// MARK: - S19 练琴笔记（时间线：课后随手记 + Neko 周报 + 待处理问题；笔记可关联 take）
// 布局真值：docs/design-reference/screens/S19-notes/spec.md。
//
// 呈现：S23「练琴笔记」行以 sheet 进入，内含 NavigationStack；返回 = dismiss（‹ 返回）。
// 导航：新建/编辑走 push（NoteEditView → TakePickerView 同栈），关联 take 走本视图唯一的
//       sheet（TakeReportView 自带 dismiss 语义，不能 push；一视图一 sheet 教训）。
// 红线：只写 PracticeNote，不碰课程/判分/设置状态；weeklyReport 只读（自动生成与
//       「写进下周计划」属 M7.2，本 Stage 不渲染该入口，避免死按钮）。

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
                    chipsRow.padding(.top, 12)
                    timeline
                }
                .padding(.horizontal, 20)
            }
            .background(Color.canvas)
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
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: 筛选 chips（spec 顺序，单选）

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotesChip.allCases) { option in
                    NocturneChip(title: option.title, isSelected: chip == option) {
                        chip = option
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: 时间线

    private var timeline: some View {
        LazyVStack(spacing: 12) {
            if visibleNotes.isEmpty {
                emptyState
            }
            ForEach(visibleNotes) { note in
                noteCard(note)
            }
        }
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
            HStack(spacing: 6) {
                kindTag(kind)
                Text(note.displayTitle)
                    .font(.titleMd)
                    .foregroundStyle(resolved ? Color.textMuted : Color.textPrimary)
                    .strikethrough(resolved, color: Color.textMuted)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text(ChatContextText.stamp(note.createdAt))
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
                    .monospacedDigit()
            }
            if !note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note.body)
                    .font(.bodySm)
                    .leading(19, fontSize: 12)
                    .foregroundStyle(resolved ? Color.textMuted : Color.textBody)
                    .strikethrough(resolved, color: Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            takeChip(note)
            cardActions(note)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
        // NocturneCard 边框色固定；issue 卡按 spec 用 danger 描边，故本地复刻同款卡片容器
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(kind == .issue ? Color.danger.opacity(0.45) : Color.border, lineWidth: 1)
        )
        .opacity(resolved ? 0.75 : 1)
    }

    /// 类型标签（S19 spec：课后=琥珀 / 周报=蓝灰 / 问题=danger 描边）。
    /// 蓝灰档取 textBody 冷灰：色板 compareB 专供双 take 对比，不挪用。
    private func kindTag(_ kind: NoteKind) -> some View {
        let color: Color = switch kind {
        case .manual: Color.amber
        case .weeklyReport: Color.textBody
        case .issue: Color.danger
        }
        return Text(kind.cardLabel)
            .font(.labelSm)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(kind == .issue ? Color.clear : color.opacity(0.15), in: Capsule())
            .overlay(
                Capsule().strokeBorder(kind == .issue ? color.opacity(0.45) : Color.clear, lineWidth: 1)
            )
    }

    /// 关联 take chip：可点 → 跳 S13 报告；take 已删除则如实禁用并标注（唯一允许的非可点态）
    @ViewBuilder
    private func takeChip(_ note: PracticeNote) -> some View {
        if let takeId = note.linkedTakeId {
            if let take = takes.first(where: { $0.entityId == takeId }) {
                Button {
                    reportTake = take
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "music.note")
                            .font(.system(size: 10))
                        Text("关联 take · \(takeShortLabel(take, pieces: pieces)) · \(ChatContextText.stamp(take.startedAt))")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .font(.labelSm)
                    .foregroundStyle(Color.amber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.amber.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "music.note.slash")
                        .font(.system(size: 10))
                    Text("关联的练习已删除")
                }
                .font(.labelSm)
                .foregroundStyle(Color.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
                .padding(.top, 2)
                .accessibilityLabel("关联的练习已删除，无法跳转")
            }
        }
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
            .buttonStyle(NoteActionButtonStyle())
            .padding(.top, 2)
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
            .buttonStyle(NoteActionButtonStyle())
            .padding(.top, 2)
        case .weeklyReport:
            // 周报由 Neko 生成：不可编辑/不可删除；「写进下周计划」等 M7.2 规则引擎，本 Stage 不渲染
            EmptyView()
        }
    }

    /// 问题卡状态切换：划线归档，不删除（S19 spec）
    private func toggleResolved(_ note: PracticeNote) {
        note.status = note.isResolvedIssue ? NoteStatus.open.rawValue : NoteStatus.resolved.rawValue
        try? context.save()
    }

    // MARK: 新建 FAB（spec：56pt 琥珀圆 + 深铅笔图标，右下 20pt）

    private var fab: some View {
        Button {
            editTarget = NoteEditTarget()
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.canvas)
                .frame(width: 56, height: 56)
                .background(Color.amber, in: Circle())
                .shadow(color: Color.amber.opacity(0.25), radius: 12, y: 4) // 暖色辉，与 NekoFAB 同语言
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .accessibilityLabel("新建笔记")
    }
}

/// 卡内小动作按钮（次按钮的紧凑形态：描边胶囊，pressed 变琥珀）
private struct NoteActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.labelMd)
            .foregroundStyle(configuration.isPressed ? Color.amber : Color.textBody)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? Color.card : Color.clear, in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color.amber.opacity(configuration.isPressed ? 0.7 : 0.3), lineWidth: 1)
            )
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

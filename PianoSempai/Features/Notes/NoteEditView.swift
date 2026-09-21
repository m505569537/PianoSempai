import SwiftData
import SwiftUI

// MARK: - S19 笔记编辑（新建/编辑 manual 与 issue；weeklyReport 只读，不经此页）
// 呈现：NotesView 内 NavigationStack push（返回即回列表，不做第二层 sheet）。
// 保存：真实写 SwiftData；删除走确认弹窗（归档不删除，这里是真删，S19 spec 交互态）。

/// push 目标（值快照：noteId 为空 = 新建）。
/// 用快照而非持有 @Model 对象跨栈：删除后不再触碰已删对象的属性。
struct NoteEditTarget: Hashable {
    var noteId: UUID?
    var kind: NoteKind
    var title: String
    var body: String
    var linkedTakeId: UUID?

    init(noteId: UUID? = nil, kind: NoteKind = .manual, title: String = "", body: String = "", linkedTakeId: UUID? = nil) {
        self.noteId = noteId
        self.kind = kind
        self.title = title
        self.body = body
        self.linkedTakeId = linkedTakeId
    }

    init(note: PracticeNote) {
        self.init(
            noteId: note.entityId,
            kind: note.noteKind,
            title: note.title,
            body: note.body,
            linkedTakeId: note.linkedTakeId
        )
    }
}

struct NoteEditView: View {
    let target: NoteEditTarget
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \PracticeNote.createdAt, order: .reverse) private var notes: [PracticeNote]
    @Query(sort: \Take.startedAt, order: .reverse) private var takes: [Take]
    @Query private var pieces: [Piece]

    @State private var kind: NoteKind
    @State private var title: String
    @State private var bodyText: String
    @State private var linkedTakeId: UUID?
    @State private var showDeleteConfirm = false

    init(target: NoteEditTarget) {
        self.target = target
        // 周报只读：即使真被传进来也不按周报类型编辑（spec：周报卡不可编辑）
        _kind = State(initialValue: target.kind == .weeklyReport ? .manual : target.kind)
        _title = State(initialValue: target.title)
        _bodyText = State(initialValue: target.body)
        _linkedTakeId = State(initialValue: target.linkedTakeId)
    }

    private var draft: NoteDraft {
        NoteDraft(kind: kind, title: title, body: bodyText, linkedTakeId: linkedTakeId)
    }

    /// 被编辑的真实对象（新建或对象已不在库里 → nil；按 id 回查，不跨栈持有模型对象）
    private var existing: PracticeNote? {
        guard let id = target.noteId else { return nil }
        return notes.first { $0.entityId == id }
    }

    private var linkedTake: Take? {
        guard let id = linkedTakeId else { return nil }
        return takes.first { $0.entityId == id }
    }

    /// title 与 body 不能同时为空；周报对象不许改写（红线：AI 生成内容只读）
    private var canSave: Bool {
        draft.canSave && !(existing?.noteKind == .weeklyReport)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                kindSection
                titleSection
                bodySection
                takeSection
                if existing != nil {
                    deleteSection
                }
                footnote
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color.canvas)
        .scrollDismissesKeyboard(.interactively)
        .tint(Color.amber)
        .navigationTitle(target.noteId == nil ? "新笔记" : "编辑笔记")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { dismiss() }
                    .foregroundStyle(Color.textBody)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { save() }
                    .foregroundStyle(canSave ? Color.amber : Color.textMuted)
                    .disabled(!canSave)
            }
        }
        .confirmationDialog("删除这条笔记？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { delete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后不可恢复。")
        }
        .preferredColorScheme(.dark)
    }

    // MARK: 类型（默认课后；周报由 Neko 生成，不在这里创建）

    private var kindSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("类型")
            HStack(spacing: 8) {
                ForEach([NoteKind.manual, .issue], id: \.self) { option in
                    NocturneChip(title: option.cardLabel, isSelected: kind == option) {
                        kind = option
                    }
                }
            }
            Text(
                kind == .issue
                    ? "问题会单独出现在「问题」筛选里；处理完可标记已处理，划线归档不删除。"
                    : "课后随手记：弹完把感受记下来，可关联这次 take。"
            )
            .font(.labelSm)
            .leading(16, fontSize: 11)
            .foregroundStyle(Color.textMuted)
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("标题")
            TextField("可留空，保存时用正文首句", text: $title)
                .font(.titleMd)
                .foregroundStyle(Color.textPrimary)
                .tint(Color.amber)
                .padding(12)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderInput, lineWidth: 1))
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("正文")
            TextField("这次弹琴的感觉、卡住的地方、下次想试的办法…", text: $bodyText, axis: .vertical)
                .font(.bodyMd)
                .foregroundStyle(Color.textPrimary)
                .tint(Color.amber)
                .lineLimit(3...10)
                .frame(minHeight: 132, alignment: .topLeading)
                .padding(12)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderInput, lineWidth: 1))
        }
    }

    // MARK: 关联 take（选填；选择器为同栈 push 子页）

    private var takeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("关联 take（选填）")
            NavigationLink {
                TakePickerView(selectedTakeId: $linkedTakeId)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textBody)
                        .frame(width: 20)
                    if let linkedTake {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(takeShortLabel(linkedTake, pieces: pieces))
                                .font(.bodyMd)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                            Text("\(ChatContextText.stamp(linkedTake.startedAt)) · ♩=\(linkedTake.tempoAvg)")
                                .font(.labelSm)
                                .foregroundStyle(Color.textMuted)
                                .monospacedDigit()
                        }
                    } else {
                        Text("不关联")
                            .font(.bodyMd)
                            .foregroundStyle(Color.textMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
                }
                .padding(12)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            if takes.isEmpty {
                Text("还没有 take。去练习室弹一段，就能把笔记关联到具体那次练习。")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    private var deleteSection: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            Text("删除这条笔记")
                .font(.bodyMd)
                .foregroundStyle(Color.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.danger.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var footnote: some View {
        Text("笔记只存在这台手机上，不参与判分、不改课程状态。")
            .font(.labelSm)
            .foregroundStyle(Color.textMuted)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.labelMd)
            .foregroundStyle(Color.textMuted)
    }

    // MARK: 落库

    private func save() {
        let draft = draft
        guard draft.canSave else { return }
        if let note = existing {
            note.kind = draft.kind.rawValue
            note.title = draft.resolvedTitle
            note.body = draft.trimmedBody
            note.linkedTakeId = draft.linkedTakeId
        } else {
            context.insert(
                PracticeNote(
                    kind: draft.kind.rawValue,
                    title: draft.resolvedTitle,
                    body: draft.trimmedBody,
                    linkedTakeId: draft.linkedTakeId
                )
            )
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        if let note = existing {
            context.delete(note)
            try? context.save()
        }
        dismiss()
    }
}

// MARK: - take 选择器（同栈 push 子页；选中即关联，可清空）

struct TakePickerView: View {
    @Binding var selectedTakeId: UUID?
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Take.startedAt, order: .reverse) private var takes: [Take]
    @Query private var pieces: [Piece]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("把笔记关联到具体那次练习，之后从笔记一键跳回去看报告。")
                    .font(.bodySm)
                    .leading(19, fontSize: 12)
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 8)

                optionRow(
                    title: "不关联",
                    detail: "这条笔记不指向具体练习",
                    selected: selectedTakeId == nil
                ) {
                    select(nil)
                }
                .padding(.top, 4)

                ForEach(takes.prefix(50)) { take in
                    optionRow(
                        title: takeShortLabel(take, pieces: pieces),
                        detail: "\(ChatContextText.stamp(take.startedAt)) · ♩=\(take.tempoAvg) · \(take.durationSec / 60)分\(take.durationSec % 60)秒",
                        selected: selectedTakeId == take.entityId
                    ) {
                        select(take.entityId)
                    }
                }

                if takes.isEmpty {
                    Text("还没有 take。去练习室弹一段，这里就会出现。")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.canvas)
        .tint(Color.amber)
        .navigationTitle("选择 take")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    private func optionRow(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(selected ? Color.amber : Color.borderInput, lineWidth: 1)
                        .frame(width: 16, height: 16)
                    Circle()
                        .fill(Color.amber)
                        .frame(width: 8, height: 8)
                        .opacity(selected ? 1 : 0)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.bodyMd)
                        .foregroundStyle(selected ? Color.amber : Color.textPrimary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func select(_ id: UUID?) {
        selectedTakeId = id
        dismiss()
    }
}

// MARK: - 预览夹具（内存容器 + 一条待编辑笔记 + 两条 take）

#if DEBUG
private enum NoteEditPreviewContainer {
    @MainActor
    static func make() -> ModelContainer {
        let container = try! ModelContainer(
            for: PracticeNote.self, Take.self, TakeAnalysis.self, ScoreErrorMark.self, Piece.self, ScoreFile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let now = Date()

        let piece = Piece(title: "拜厄 45", book: "拜厄", number: 45)
        context.insert(piece)
        let take = Take(
            startedAt: now.addingTimeInterval(-7200),
            durationSec: 480,
            taskType: "main",
            hasMidi: true,
            measureFrom: 21,
            measureTo: 24,
            tempoAvg: 60,
            title: "拜厄45 · 转指"
        )
        take.pieceId = piece.entityId
        context.insert(take)
        context.insert(Take(
            startedAt: now.addingTimeInterval(-86400),
            durationSec: 300,
            taskType: "warmup",
            hasMidi: true,
            tempoAvg: 72,
            title: "热身"
        ))
        context.insert(PracticeNote(
            kind: NoteKind.manual.rawValue,
            title: "拜厄45 · 21小节转指",
            body: "今天 60 速度单手 4 遍后，转指卡顿明显少了。",
            createdAt: now.addingTimeInterval(-3600)
        ))
        return container
    }
}
#endif

#Preview {
    NavigationStack {
        NoteEditView(target: NoteEditTarget(noteId: nil, kind: .manual))
    }
    .modelContainer(NoteEditPreviewContainer.make())
}

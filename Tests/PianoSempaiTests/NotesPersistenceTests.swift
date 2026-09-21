import Foundation
import SwiftData
import XCTest

@testable import PianoSempai

/// M7.1 Stage B3 · S19 练琴笔记持久化验收（内存 ModelContainer，不碰磁盘）：
/// 新建 manual/issue 落库、@Query 同款排序与过滤可见、issue 划线归档不删除、
/// 删除确认后真删、linkedTakeId 往返、编辑保存与标题兜底。
@MainActor
final class NotesPersistenceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PracticeNote.self, Take.self, Piece.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
    }

    private let base = Date(timeIntervalSince1970: 1_760_000_000)

    private func makeNote(
        kind: String,
        title: String = "",
        body: String = "",
        status: String = "open",
        linkedTakeId: UUID? = nil,
        offset: Int
    ) -> PracticeNote {
        PracticeNote(
            kind: kind,
            title: title,
            body: body,
            linkedTakeId: linkedTakeId,
            status: status,
            createdAt: base.addingTimeInterval(-Double(offset) * 60)
        )
    }

    /// 与 NotesView 的 @Query 同口径：createdAt 倒序
    private func fetchNotes() throws -> [PracticeNote] {
        try context.fetch(
            FetchDescriptor<PracticeNote>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        )
    }

    // MARK: - 落库与读取

    func testInsertManualAndIssuePersist() throws {
        context.insert(makeNote(kind: "manual", title: "拜厄45 · 转指", body: "手腕提前带过去", offset: 0))
        context.insert(makeNote(kind: "issue", title: "手腕紧", body: "坐高一点", offset: 1))
        try context.save()

        let notes = try fetchNotes()
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes.first?.kind, "manual") // 倒序：新的在前
        XCTAssertEqual(notes.map(\.kind), ["manual", "issue"])
    }

    func testFetchedNotesFeedFilterAndSearch() throws {
        context.insert(makeNote(kind: "manual", title: "拜厄45 · 转指", body: "手腕提前带过去", offset: 0))
        context.insert(makeNote(kind: "weeklyReport", title: "第 3 周观察", body: "热身完成率 100%", offset: 1))
        context.insert(makeNote(kind: "issue", title: "手腕紧", body: "坐高一点", offset: 2))
        context.insert(makeNote(kind: "issue", title: "旧问题", body: "已改善", status: "resolved", offset: 3))
        try context.save()

        let notes = try fetchNotes()
        XCTAssertEqual(NotesFilter.apply(notes: notes, chip: .issue).count, 2)
        XCTAssertEqual(NotesFilter.apply(notes: notes, chip: .issue, includeResolvedIssues: false).count, 1)
        XCTAssertEqual(NotesFilter.apply(notes: notes, chip: .all, query: "热身").count, 1)
        XCTAssertEqual(NotesFilter.apply(notes: notes, chip: .manual).count, 1)
    }

    // MARK: - issue 归档（划线不删除）

    func testResolvedIssueIsArchivedNotDeleted() throws {
        let issue = makeNote(kind: "issue", title: "手腕紧", body: "坐高一点", offset: 0)
        context.insert(issue)
        try context.save()

        issue.status = NoteStatus.resolved.rawValue
        try context.save()

        let notes = try fetchNotes()
        XCTAssertEqual(notes.count, 1) // 还在，没被删
        XCTAssertTrue(notes[0].isResolvedIssue)
        XCTAssertEqual(notes[0].title, "手腕紧") // 内容不改写
        XCTAssertEqual(NotesFilter.apply(notes: notes, chip: .issue).count, 1)

        issue.status = NoteStatus.open.rawValue
        try context.save()
        XCTAssertFalse(try fetchNotes()[0].isResolvedIssue)
    }

    // MARK: - 删除（确认后真删）

    func testDeleteRemovesNote() throws {
        let keep = makeNote(kind: "manual", title: "留着", body: "", offset: 0)
        let drop = makeNote(kind: "manual", title: "删掉", body: "", offset: 1)
        context.insert(keep)
        context.insert(drop)
        try context.save()

        context.delete(drop)
        try context.save()

        let notes = try fetchNotes()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].title, "留着")
    }

    // MARK: - 关联 take

    func testLinkedTakeIdRoundTrips() throws {
        let take = Take(startedAt: base, durationSec: 600, taskType: "main", hasMidi: true, measureFrom: 21, measureTo: 24, tempoAvg: 60)
        context.insert(take)
        let note = makeNote(kind: "manual", title: "转指", body: "", linkedTakeId: take.entityId, offset: 0)
        context.insert(note)
        try context.save()

        let stored = try XCTUnwrap(try fetchNotes().first)
        XCTAssertEqual(stored.linkedTakeId, take.entityId)

        // 视图层按 id 回查 take（关联 chip 的跳转目标）
        let descriptor = FetchDescriptor<Take>()
        let takes = try context.fetch(descriptor)
        XCTAssertEqual(takes.first { $0.entityId == stored.linkedTakeId }?.tempoAvg, 60)
    }

    func testLinkedTakeIdClearsWhenUnlinked() throws {
        let note = makeNote(kind: "manual", title: "转指", body: "", linkedTakeId: UUID(), offset: 0)
        context.insert(note)
        try context.save()

        note.linkedTakeId = nil
        try context.save()
        XCTAssertNil(try fetchNotes().first?.linkedTakeId)
    }

    // MARK: - 编辑路径（按 id 回查后更新；标题兜底落库）

    /// 与 NoteEditView.existing 同口径：按 entityId 从库里回查真实对象
    private func storedNote(withId id: UUID) throws -> PracticeNote? {
        try fetchNotes().first { $0.entityId == id }
    }

    func testEditUpdatesExistingNoteInPlace() throws {
        let note = makeNote(kind: "manual", title: "旧标题", body: "旧正文", offset: 0)
        context.insert(note)
        try context.save()
        let noteId = note.entityId

        // 模拟 NoteEditView.save：按 id 回查真实对象再改写
        let existing = try storedNote(withId: noteId)
        let draft = NoteDraft(kind: .issue, title: "新标题", body: "  新正文  ", linkedTakeId: nil)
        XCTAssertTrue(draft.canSave)
        existing?.kind = draft.kind.rawValue
        existing?.title = draft.resolvedTitle
        existing?.body = draft.trimmedBody
        try context.save()

        let stored = try XCTUnwrap(try fetchNotes().first)
        XCTAssertEqual(stored.entityId, noteId) // 原地更新，不新增行
        XCTAssertEqual(stored.kind, "issue")
        XCTAssertEqual(stored.title, "新标题")
        XCTAssertEqual(stored.body, "新正文")
    }

    func testSavedTitleFallsBackToBodyFirstSentence() throws {
        let draft = NoteDraft(kind: .manual, title: "   ", body: "转指卡顿少了。手腕提前带过去\n第二行")
        context.insert(PracticeNote(kind: draft.kind.rawValue, title: draft.resolvedTitle, body: draft.trimmedBody))
        try context.save()

        let stored = try XCTUnwrap(try fetchNotes().first)
        XCTAssertEqual(stored.title, "转指卡顿少了")
        XCTAssertEqual(stored.body, "转指卡顿少了。手腕提前带过去\n第二行")
        XCTAssertFalse(stored.displayTitle.isEmpty)
    }

    func testDeletedNoteCannotBeEditedAgain() throws {
        let note = makeNote(kind: "manual", title: "临时", body: "", offset: 0)
        context.insert(note)
        try context.save()
        let noteId = note.entityId

        context.delete(note)
        try context.save()

        // 删除后按 id 回查应为空（视图保存时据此走新建分支，不崩）
        XCTAssertNil(try storedNote(withId: noteId))
        XCTAssertTrue(try fetchNotes().isEmpty)
    }
}

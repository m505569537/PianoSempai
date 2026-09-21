import Foundation
import SwiftData
import XCTest

@testable import PianoSempai

/// M7.1 Stage B3 · S19 练琴笔记纯逻辑验收：筛选 chips、本地检索（标题/正文/take 关联）、
/// resolved 归档规则、空态文案，以及编辑草稿的保存校验与标题兜底。
/// 不碰 SwiftUI、不建容器：只对纯函数与值类型断言。
final class NotesFilterTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_760_000_000)
    private let takeId = UUID()

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

    /// 固定夹具：两种 manual + 一条周报 + open/resolved 各一条 issue（offset 越小越新）
    private func fixture() -> [PracticeNote] {
        [
            makeNote(kind: "issue", title: "黑键移动时手腕紧", body: "下次试试坐高一点", status: "open", offset: 0),
            makeNote(kind: "manual", title: "拜厄45 · 21小节转指", body: "手腕提前带过去是有用的", linkedTakeId: takeId, offset: 1),
            makeNote(kind: "weeklyReport", title: "第 3 周观察", body: "热身完成率从 60% 到 100%", offset: 2),
            makeNote(kind: "issue", title: "左手独立性不足", body: "已用慢速分手练习改善", status: "resolved", offset: 3),
            makeNote(kind: "manual", title: "HANON 第一首", body: "先慢后快，注意抬指", offset: 4),
        ]
    }

    private func titles(_ notes: [PracticeNote]) -> [String] {
        notes.map(\.title)
    }

    // MARK: - 筛选 chips（spec 顺序：全部 / 我的记录 / Neko 周报 / 问题）

    func testAllChipKeepsEveryKind() {
        let result = NotesFilter.apply(notes: fixture(), chip: .all)
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(Set(result.map(\.kind)), ["manual", "weeklyReport", "issue"])
    }

    func testManualChipKeepsOnlyManual() {
        let result = NotesFilter.apply(notes: fixture(), chip: .manual)
        XCTAssertEqual(titles(result), ["拜厄45 · 21小节转指", "HANON 第一首"])
    }

    func testWeeklyReportChipKeepsOnlyWeeklyReport() {
        let result = NotesFilter.apply(notes: fixture(), chip: .weeklyReport)
        XCTAssertEqual(titles(result), ["第 3 周观察"])
    }

    func testIssueChipKeepsOpenAndResolvedByDefault() {
        let result = NotesFilter.apply(notes: fixture(), chip: .issue)
        XCTAssertEqual(titles(result), ["黑键移动时手腕紧", "左手独立性不足"])
    }

    func testIssueChipCanHideResolved() {
        let result = NotesFilter.apply(notes: fixture(), chip: .issue, includeResolvedIssues: false)
        XCTAssertEqual(titles(result), ["黑键移动时手腕紧"])
    }

    func testAllChipHidesResolvedIssuesWhenFlagOff() {
        let result = NotesFilter.apply(notes: fixture(), chip: .all, includeResolvedIssues: false)
        XCTAssertEqual(result.count, 4)
        XCTAssertFalse(result.contains { $0.isResolvedIssue })
    }

    func testChipFilterDoesNotTouchOtherKindsWhenHidingResolved() {
        let result = NotesFilter.apply(notes: fixture(), chip: .manual, includeResolvedIssues: false)
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - 本地检索（spec：标题/正文/take 关联）

    func testSearchMatchesTitle() {
        let result = NotesFilter.apply(notes: fixture(), chip: .all, query: "转指")
        XCTAssertEqual(titles(result), ["拜厄45 · 21小节转指"])
    }

    func testSearchMatchesBody() {
        let result = NotesFilter.apply(notes: fixture(), chip: .all, query: "坐高")
        XCTAssertEqual(titles(result), ["黑键移动时手腕紧"])
    }

    func testSearchMatchesLinkedTakeTitle() {
        // 「转指卡」只出现在被关联 take 的标题里：证明 take 关联参与检索（spec）
        let result = NotesFilter.apply(
            notes: fixture(),
            chip: .all,
            query: "转指卡",
            takeTitles: [takeId: "主菜 · 第21–24小节 转指卡"]
        )
        XCTAssertEqual(titles(result), ["拜厄45 · 21小节转指"])
    }

    func testSearchMatchesLinkedTakeTitleOnlyForLinkedNote() {
        // 未被任何笔记引用的 take 标题不该把别的笔记带出来
        let result = NotesFilter.apply(
            notes: fixture(),
            chip: .all,
            query: "转指卡",
            takeTitles: [UUID(): "无关 take 转指卡"]
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testSearchIsCaseInsensitive() {
        let result = NotesFilter.apply(notes: fixture(), chip: .all, query: "hanon")
        XCTAssertEqual(titles(result), ["HANON 第一首"])
    }

    func testSearchTokensAreAnded() {
        // 两个词分散在不同笔记：AND 语义下应无命中
        let none = NotesFilter.apply(notes: fixture(), chip: .all, query: "转指 抬指")
        XCTAssertTrue(none.isEmpty)

        let both = NotesFilter.apply(notes: fixture(), chip: .all, query: "转指 手腕")
        XCTAssertEqual(titles(both), ["拜厄45 · 21小节转指"])
    }

    func testSearchIgnoresExtraWhitespace() {
        let result = NotesFilter.apply(notes: fixture(), chip: .all, query: "   转指   ")
        XCTAssertEqual(titles(result), ["拜厄45 · 21小节转指"])
    }

    func testEmptyQueryReturnsEverything() {
        XCTAssertEqual(NotesFilter.apply(notes: fixture(), chip: .all, query: "").count, 5)
        XCTAssertEqual(NotesFilter.apply(notes: fixture(), chip: .all, query: "   ").count, 5)
    }

    func testSearchCombinedWithChip() {
        let result = NotesFilter.apply(notes: fixture(), chip: .issue, query: "手腕")
        XCTAssertEqual(titles(result), ["黑键移动时手腕紧"])
    }

    func testSearchNoHitReturnsEmpty() {
        XCTAssertTrue(NotesFilter.apply(notes: fixture(), chip: .all, query: "不存在的词").isEmpty)
    }

    // MARK: - 顺序 / 边界

    func testOrderPreservedFromInput() {
        let notes = fixture()
        let result = NotesFilter.apply(notes: notes, chip: .all)
        XCTAssertEqual(result.map(\.entityId), notes.map(\.entityId))
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(NotesFilter.apply(notes: [], chip: .all).isEmpty)
        XCTAssertTrue(NotesFilter.apply(notes: [], chip: .issue, query: "x").isEmpty)
    }

    func testUnknownKindFallsBackToManual() {
        let note = PracticeNote(kind: "mysteryKind", title: "怪类型", body: "")
        XCTAssertEqual(note.noteKind, .manual)
        let all = NotesFilter.apply(notes: [note], chip: .all)
        XCTAssertEqual(all.count, 1) // 不静默隐藏数据
        XCTAssertEqual(NotesFilter.apply(notes: [note], chip: .manual).count, 1)
    }

    func testSearchTokensHelper() {
        XCTAssertEqual(NotesFilter.searchTokens("  Foo   bar "), ["foo", "bar"])
        XCTAssertTrue(NotesFilter.searchTokens("   ").isEmpty)
    }

    // MARK: - 空态文案

    func testEmptyTextPerChip() {
        XCTAssertEqual(NotesFilter.emptyText(chip: .all, query: ""), NotesChip.all.emptyText)
        XCTAssertEqual(NotesFilter.emptyText(chip: .manual, query: ""), NotesChip.manual.emptyText)
        XCTAssertEqual(NotesFilter.emptyText(chip: .weeklyReport, query: ""), NotesChip.weeklyReport.emptyText)
        XCTAssertEqual(NotesFilter.emptyText(chip: .issue, query: ""), NotesChip.issue.emptyText)
    }

    func testEmptyTextPrefersSearchNoHit() {
        XCTAssertTrue(NotesFilter.emptyText(chip: .all, query: "转指").contains("转指"))
        XCTAssertFalse(NotesFilter.emptyText(chip: .issue, query: "").contains("转指"))
    }

    func testChipTitlesFollowSpecOrder() {
        XCTAssertEqual(NotesChip.allCases.map(\.title), ["全部", "我的记录", "Neko 周报", "问题"])
    }

    // MARK: - 卡面展示规则

    func testDisplayTitleFallsBackToKindPlaceholder() {
        let manual = makeNote(kind: "manual", title: "   ", body: "正文", offset: 0)
        XCTAssertEqual(manual.displayTitle, "课后笔记")
        XCTAssertEqual(makeNote(kind: "weeklyReport", title: "", offset: 1).displayTitle, "Neko 周报")
        XCTAssertEqual(makeNote(kind: "issue", title: "", offset: 2).displayTitle, "问题笔记")
        XCTAssertEqual(makeNote(kind: "manual", title: "真标题", offset: 3).displayTitle, "真标题")
    }

    func testWeeklyReportIsReadOnlyKind() {
        XCTAssertTrue(NoteKind.weeklyReport.isReadOnly)
        XCTAssertFalse(NoteKind.manual.isReadOnly)
        XCTAssertFalse(NoteKind.issue.isReadOnly)
    }

    // MARK: - 编辑草稿（保存校验 + 标题兜底）

    func testCanSaveRequiresTitleOrBody() {
        XCTAssertFalse(NoteDraft(kind: .manual, title: "", body: "").canSave)
        XCTAssertFalse(NoteDraft(kind: .manual, title: "   ", body: "\n ").canSave)
        XCTAssertTrue(NoteDraft(kind: .manual, title: "标题", body: "").canSave)
        XCTAssertTrue(NoteDraft(kind: .manual, title: "", body: "正文").canSave)
        XCTAssertTrue(NoteDraft(kind: .issue, title: "标题", body: "正文").canSave)
    }

    func testResolvedTitleKeepsExplicitTitle() {
        let draft = NoteDraft(kind: .manual, title: "  拜厄45  ", body: "正文")
        XCTAssertEqual(draft.resolvedTitle, "拜厄45")
    }

    func testResolvedTitleFallsBackToFirstSentenceOfBody() {
        XCTAssertEqual(NoteDraft(kind: .manual, title: "", body: "转指卡顿少了。手腕提前带过去").resolvedTitle, "转指卡顿少了")
        XCTAssertEqual(NoteDraft(kind: .manual, title: "", body: "第一行\n第二行").resolvedTitle, "第一行")
        XCTAssertEqual(NoteDraft(kind: .issue, title: "", body: "坐高一点，试试").resolvedTitle, "坐高一点，试试")
    }

    func testResolvedTitleTruncatesLongBody() {
        let long = String(repeating: "啊", count: 40)
        let title = NoteDraft(kind: .manual, title: "", body: long).resolvedTitle
        XCTAssertTrue(title.hasSuffix("…"))
        XCTAssertEqual(title.count, NoteDraft.maxFallbackLength + 1)
    }

    func testFallbackTitleForEmptyBodyIsUntitled() {
        XCTAssertEqual(NoteDraft.fallbackTitle(fromBody: ""), NoteDraft.untitledTitle)
        XCTAssertEqual(NoteDraft.fallbackTitle(fromBody: "   \n  "), NoteDraft.untitledTitle)
        XCTAssertEqual(NoteDraft.fallbackTitle(fromBody: "。！"), NoteDraft.untitledTitle)
    }

    func testDraftTrimsBodyForStorage() {
        let draft = NoteDraft(kind: .manual, title: "标题", body: "  正文\n ")
        XCTAssertEqual(draft.trimmedBody, "正文")
        XCTAssertEqual(draft.trimmedTitle, "标题")
    }
}

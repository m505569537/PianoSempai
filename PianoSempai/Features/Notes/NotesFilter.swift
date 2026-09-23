import Foundation
import SwiftData

// MARK: - S19 练琴笔记 · 纯逻辑（筛选/检索/草稿规则）
// 视图只调这里的函数，不内置过滤规则；本文件不依赖 SwiftUI，可完整单测。
// 数据形状见 docs/design-system/data-model.md §2 Note；布局真值见 S19-notes/spec.md。

/// 笔记类型（data-model §2 Note.kind：manual / weeklyReport / issue）。
/// 库里存裸字符串；未知值回落 manual —— 数据不丢、不静默隐藏（红线 2：如实呈现）。
enum NoteKind: String, CaseIterable {
    case manual
    case weeklyReport
    case issue

    /// 卡片类型标签（S19 真值 code.html §4：课后=琥珀 / Neko 周报=暖金 / 问题=红）。
    /// 纯展示：只被笔记卡 badge 与编辑页类型 chip 读取，不参与筛选/判等。
    var cardLabel: String {
        switch self {
        case .manual: "课后"
        case .weeklyReport: "Neko 周报"
        case .issue: "问题"
        }
    }

    /// 筛选 chip 标题（spec 顺序：全部 / 我的记录 / Neko 周报 / 问题）
    var chipTitle: String {
        switch self {
        case .manual: "我的记录"
        case .weeklyReport: "Neko 周报"
        case .issue: "问题"
        }
    }

    /// 空标题占位（不留空白标题行）
    var placeholderTitle: String {
        switch self {
        case .manual: "课后笔记"
        case .weeklyReport: "Neko 周报"
        case .issue: "问题笔记"
        }
    }

    /// weeklyReport 由 AI 生成、本 Stage 起只读（自动生成属 M7.2）
    var isReadOnly: Bool { self == .weeklyReport }
}

/// 笔记状态（issue 用：open 待处理 / resolved 已处理；归档不删除）
enum NoteStatus: String {
    case open
    case resolved
}

extension PracticeNote {
    /// 库里 kind 字符串 → 语义类型（未知值回落 manual）
    var noteKind: NoteKind { NoteKind(rawValue: kind) ?? .manual }

    /// 已处理的问题（划线归档，仍在时间线，不删除）
    var isResolvedIssue: Bool { noteKind == .issue && status == NoteStatus.resolved.rawValue }

    /// 卡面标题：空标题用类型占位，不留空白
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? noteKind.placeholderTitle : trimmed
    }
}

/// S19 筛选 chips（spec 顺序，单选）
enum NotesChip: String, CaseIterable, Identifiable {
    case all
    case manual
    case weeklyReport
    case issue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .manual: NoteKind.manual.chipTitle
        case .weeklyReport: NoteKind.weeklyReport.chipTitle
        case .issue: NoteKind.issue.chipTitle
        }
    }

    /// 该筛选下无内容时的空态文案（不造假数据）
    var emptyText: String {
        switch self {
        case .all: "还没有笔记。练完随手记一条，Neko 的周报也会出现在这里。"
        case .manual: "还没有课后记录，练完随手记一条吧。"
        case .weeklyReport: "还没有周报。周报每周日 21:00 自动生成。"
        case .issue: "还没有待处理问题。弹琴卡住的地方记下来，下次盯着练。"
        }
    }
}

enum NotesFilter {

    /// 时间线过滤：筛选 chip + 本地检索（S19 spec「搜索：标题/正文/take 关联本地检索」）。
    /// - 保持入参顺序：调用方传 @Query 已按 createdAt 倒序的结果
    /// - 检索词按空白分词，每个词都要命中（AND），大小写不敏感
    /// - `includeResolvedIssues = false` 时已处理问题在所有筛选下一律不显示；
    ///   默认 `true` —— resolved 划线归档仍占时间线一行（归档不删除，S19 spec）
    static func apply(
        notes: [PracticeNote],
        chip: NotesChip,
        query: String = "",
        includeResolvedIssues: Bool = true,
        takeTitles: [UUID: String] = [:]
    ) -> [PracticeNote] {
        let tokens = searchTokens(query)
        return notes.filter { note in
            matchesChip(note, chip: chip, includeResolvedIssues: includeResolvedIssues)
                && matchesQuery(note, tokens: tokens, takeTitles: takeTitles)
        }
    }

    /// chip 单选规则；`all` 含全部类型
    static func matchesChip(_ note: PracticeNote, chip: NotesChip, includeResolvedIssues: Bool = true) -> Bool {
        switch chip {
        case .all:
            return includeResolvedIssues || !note.isResolvedIssue
        case .manual:
            return note.noteKind == .manual
        case .weeklyReport:
            return note.noteKind == .weeklyReport
        case .issue:
            return note.noteKind == .issue && (includeResolvedIssues || !note.isResolvedIssue)
        }
    }

    /// 检索命中：标题 / 正文 / 关联 take 标题（spec 明确 take 关联可检索）
    static func matchesQuery(_ note: PracticeNote, tokens: [String], takeTitles: [UUID: String] = [:]) -> Bool {
        guard !tokens.isEmpty else { return true }
        let takeTitle = note.linkedTakeId.flatMap { takeTitles[$0] } ?? ""
        let haystack = [note.title, note.body, takeTitle]
            .joined(separator: " ")
            .lowercased()
        return tokens.allSatisfy { haystack.contains($0) }
    }

    /// 检索词按空白分词（空词丢弃）；空查询 → 空数组 = 不过滤
    static func searchTokens(_ query: String) -> [String] {
        query
            .split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased() }
    }

    /// 空态文案：检索无命中优先说「没有匹配」，否则说该筛选的引导语
    static func emptyText(chip: NotesChip, query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return "没有匹配「\(trimmed)」的笔记。换个词，或点 🔍 收起搜索。"
        }
        return chip.emptyText
    }
}

/// 编辑页草稿（纯值类型：新建/编辑共用）。
/// 保存校验与标题兜底都在这里，视图只读取结果 —— 规则可单测。
struct NoteDraft {
    var kind: NoteKind
    var title: String
    var body: String
    var linkedTakeId: UUID?

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedBody: String { body.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// title 与 body 不能同时为空（S19 spec：否则保存禁用）
    var canSave: Bool { !trimmedTitle.isEmpty || !trimmedBody.isEmpty }

    /// 落库标题：显式标题优先；空标题用正文首句兜底，再不行「未命名笔记」
    var resolvedTitle: String {
        trimmedTitle.isEmpty ? Self.fallbackTitle(fromBody: trimmedBody) : trimmedTitle
    }

    static let untitledTitle = "未命名笔记"
    static let maxFallbackLength = 20

    /// 正文首句（首行 + 首个句读），超长截断加省略号；整句空白 → 「未命名笔记」
    static func fallbackTitle(fromBody body: String) -> String {
        let firstLine = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        // 显式逐字取首句：正文以句读开头时首句算空 → 兜底「未命名笔记」
        var firstSentence = ""
        for character in firstLine {
            if sentenceBreaks.contains(character) { break }
            firstSentence.append(character)
        }
        let trimmed = firstSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return untitledTitle }
        if trimmed.count <= maxFallbackLength { return trimmed }
        return "\(trimmed.prefix(maxFallbackLength))…"
    }

    private static let sentenceBreaks: Set<Character> = ["。", "！", "？", "!", "?", ".", ";", "；"]
}

import Foundation

// M7.2 周报聚合（PRD M9 出勤口径 + 主动性 Q2=A）。
// 纯逻辑：只吃 Take/Piece 快照，数字全部来自真实 take；0 数据周如实显示，不编造。

/// 一周的本地产物（通知文案与 S19 周报笔记的唯一数据源）
struct WeeklyDigest: Equatable {
    var weekKey: String
    var weekStart: Date
    /// 有效练习次数（有 MIDI 且 ≥10 分钟；任务与自由弹奏都计）
    var sessions: Int
    /// 有效练习总时长（秒；无效 take 不计时长）
    var totalDurationSec: Int
    /// 本周全部 take 数（有效 + 无效，供周报正文如实说明）
    var takeCount: Int
    var goal: Int
    var goalMet: Bool
    /// 本周练习次数最多的曲目真实标题（并列取最近一次；查不到 = nil，不编造）
    var topPieceTitle: String?
    /// 有效 take 明细（周报正文的「练习明细」区；按时间升序）
    var items: [WeeklyDigestItem]

    /// 本地通知 identifier：一周一条（同周多次 upsert 先 remove 再 add）
    static func notificationIdentifier(weekKey: String) -> String {
        "weekly-digest.\(weekKey)"
    }
}

/// 周报明细行（日期 + 真实标题 + 时长；标题缺失时不编造，用类型兜底词）
struct WeeklyDigestItem: Equatable {
    var startedAt: Date
    var label: String
    var durationSec: Int
}

enum WeeklyDigestBuilder {
    /// M9 有效练习口径：有 MIDI、≥10 分钟的会话（任务练习与自由弹奏都计）
    static let minimumDurationSec = 600

    /// 聚合 [weekStart, weekEnd) 区间内的 take。
    /// - Parameters:
    ///   - takes: 全部 Take（内部按本周过滤）
    ///   - pieces: 全部 Piece（仅用于查真实标题）
    ///   - goal: 用户周目标（AppSettings.weeklyGoal）
    ///   - now: 当前时间（决定所属周）
    static func build(takes: [Take], pieces: [Piece], goal: Int, now: Date) -> WeeklyDigest {
        let weekStart = WeekCalendar.weekStart(for: now)
        let weekEnd = WeekCalendar.weekEnd(for: now)

        let inWeek = takes.filter { $0.startedAt >= weekStart && $0.startedAt < weekEnd }
        let valid = inWeek
            .filter { $0.hasMidi && $0.durationSec >= minimumDurationSec }
            .sorted { $0.startedAt < $1.startedAt }

        let totalDurationSec = valid.reduce(0) { $0 + $1.durationSec }
        let topPieceTitle = topPiece(of: valid, pieces: pieces)

        return WeeklyDigest(
            weekKey: WeekCalendar.weekKey(for: now),
            weekStart: weekStart,
            sessions: valid.count,
            totalDurationSec: totalDurationSec,
            takeCount: inWeek.count,
            goal: goal,
            goalMet: valid.count >= goal,
            topPieceTitle: topPieceTitle,
            items: valid.map { take in
                WeeklyDigestItem(
                    startedAt: take.startedAt,
                    label: Self.label(for: take, pieces: pieces),
                    durationSec: take.durationSec
                )
            }
        )
    }

    /// 有效 take 中 pieceId 出现最多者；并列取该曲目最近一次练习。
    /// pieceId 为 nil 或查不到真实标题 → 跳过（不编造）。
    private static func topPiece(of validTakes: [Take], pieces: [Piece]) -> String? {
        var counts: [UUID: Int] = [:]
        var latest: [UUID: Date] = [:]
        for take in validTakes {
            guard let pieceId = take.pieceId else { continue }
            counts[pieceId, default: 0] += 1
            if let existing = latest[pieceId] {
                if take.startedAt > existing { latest[pieceId] = take.startedAt }
            } else {
                latest[pieceId] = take.startedAt
            }
        }
        let best = counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return (latest[lhs.key] ?? .distantPast) < (latest[rhs.key] ?? .distantPast)
        }
        guard let best else { return nil }
        return pieces.first { $0.entityId == best.key }.flatMap { piece in
            piece.title.isEmpty ? nil : piece.title
        }
    }

    /// 明细行标题：曲目真实标题 > take 自带标题 > 类型兜底词（都取不到才用兜底，不发明内容）
    private static func label(for take: Take, pieces: [Piece]) -> String {
        if let pieceId = take.pieceId,
           let title = pieces.first(where: { $0.entityId == pieceId })?.title,
           !title.isEmpty {
            return title
        }
        if !take.title.isEmpty { return take.title }
        return take.isFreePlay ? "自由弹奏" : "练习"
    }
}

// MARK: - 文案（所有数字来自 digest 真实值；缺数据不写该行）

enum DigestText {
    /// 通知标题（永不空）
    static func notificationTitle(_ digest: WeeklyDigest) -> String {
        "本周练了 \(digest.sessions) 次"
    }

    /// 通知正文：时长行 + 目标行/建议行，用「，」连接；0 次无时长行
    static func notificationBody(_ digest: WeeklyDigest) -> String {
        var lines: [String] = []
        if let duration = durationLine(digest) { lines.append(duration) }
        lines.append(goalLine(digest))
        lines.append(adviceLine(digest))
        return lines.joined(separator: "，")
    }

    /// 周报笔记标题（S19 时间线展示；永不空）
    static func weeklyReportNoteTitle(_ digest: WeeklyDigest) -> String {
        notificationTitle(digest)
    }

    /// 周报笔记正文：通知全文 + 统计区间 + 口径说明 + 有效练习明细（比通知完整）
    static func weeklyReportNoteBody(_ digest: WeeklyDigest) -> String {
        var lines: [String] = [notificationBody(digest), ""]
        lines.append("统计区间：\(Self.monthDay(digest.weekStart)) 至 \(Self.monthDay(Self.sunday(of: digest.weekStart)))（周一起始）")
        if digest.sessions == 0 {
            lines.append("本周没有有效练习（有 MIDI 且 ≥10 分钟）；本周共 \(digest.takeCount) 条 take。")
        } else {
            lines.append("有效练习 \(digest.sessions) 次（有 MIDI 且 ≥10 分钟）；本周共 \(digest.takeCount) 条 take。")
            lines.append("")
            lines.append("练习明细：")
            for item in digest.items {
                lines.append("· \(Self.monthDay(item.startedAt))（\(Self.weekdayLabel(item.startedAt))）\(item.label) · \(item.durationSec / 60) 分钟")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: 分行组装

    /// 「共 H 小时 M 分」；<1 小时只说分钟；0 次无此行
    /// （时长文案统一走 DurationText，周报与月报同一套格式）
    private static func durationLine(_ digest: WeeklyDigest) -> String? {
        guard digest.sessions > 0, digest.totalDurationSec > 0 else { return nil }
        return "共 " + DurationText.hoursMinutes(digest.totalDurationSec)
    }

    private static func goalLine(_ digest: WeeklyDigest) -> String {
        if digest.goalMet {
            return "周目标 \(digest.goal) 次达成 ✓"
        }
        // !goalMet 时 sessions < goal，差值恒 ≥1；max 兜底仅防 goal 被改成 0 的极端配置出现负号
        let remaining = max(digest.goal - digest.sessions, 1)
        return "距离周目标还差 \(remaining) 次，10 分钟也算数"
    }

    /// 建议行：一条，只基于本周事实，不发明数字、不碰课程状态
    private static func adviceLine(_ digest: WeeklyDigest) -> String {
        if digest.sessions == 0 {
            return "下周回来从复习池旧条目开始，不用从头补"
        }
        if !digest.goalMet {
            return "下周争取练满 \(digest.goal) 次"
        }
        if let topPieceTitle = digest.topPieceTitle {
            return "下周可以继续练《\(topPieceTitle)》"
        }
        return "下周保持这个节奏"
    }

    // MARK: - 日期短签（与 ChatContextText 同风格的本地时区格式化）

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = WeekCalendar.calendar
        formatter.timeZone = WeekCalendar.calendar.timeZone
        formatter.dateFormat = "MM-dd"
        return formatter
    }()

    private static let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    static func monthDay(_ date: Date) -> String {
        monthDayFormatter.string(from: date)
    }

    static func weekdayLabel(_ date: Date) -> String {
        let weekday = WeekCalendar.calendar.component(.weekday, from: date) // 1=周日 … 7=周六
        return weekdaySymbols[weekday - 1]
    }

    static func sunday(of weekStart: Date) -> Date {
        WeekCalendar.calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
    }
}

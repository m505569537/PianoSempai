import Foundation
import SwiftData

// 热身硬门禁（红线 6：当坏人，但语气温柔）。
// 纯逻辑 + SwiftData 写入，独立于 SwiftUI，可单测（brief M4 验收）。
// 规则（today.md 门禁规则）：
// - 热身未完成 → 主菜「开始」被拦，走 S07c；
// - 强开须选原因（"其他"须补一句非空说明），写 GateEvent(kind=override, reasonTag, note, date, weekIndex)；
// - 本周第 N 次计数仅作陈述展示，绝不影响解锁判定（红线 3 边界，文案显式）；
// - 当日已强开过 → 再次进主菜不再弹层；
// - 取消（✕）→ 不留任何记录。

enum WarmupGate {

    enum Decision: Equatable {
        /// 可直接开始（热身已完成 / 当日已强开）
        case allowed
        /// 被拦：需走 S07c（附带今日剩余建议分钟，仅文案用）
        case blocked(warmupMinutesRemaining: Int?)
    }

    // MARK: - 判定（纯函数）

    /// 主菜能否开始。warmupCompletedAt 为热身完成时间；overrides 为已落库的全部 override 事件。
    static func checkMainAccess(
        warmupCompletedAt: Date?,
        today: Date,
        calendar: Calendar = .current,
        overrides: [GateEvent],
        warmupElapsedMin: Int? = nil
    ) -> Decision {
        if warmupCompletedAt != nil { return .allowed }
        // 当日已强开过 → 放行，不再弹层
        if overrides.contains(where: { isSameDay($0.date, today, calendar: calendar) }) {
            return .allowed
        }
        let remaining: Int? = warmupElapsedMin.map { max(0, 10 - $0) } ?? 10
        return .blocked(warmupMinutesRemaining: remaining)
    }

    /// S07c 文案用：热身建议 8–12 分钟，未开始时按 10 分钟口径陈述（纯文案，非判分）
    private static var warmupMinutesRemaining: Int? { 10 }

    // MARK: - 原因校验（S07c：必选一个；"其他"必填一句）

    /// 确认按钮是否可用：必须选了原因标签；选"其他"时说明文字非空（去首尾空白）。
    static func canConfirmOverride(reasonTag: String?, note: String) -> Bool {
        guard let reasonTag, !reasonTag.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if reasonTag == "other" {
            return !note.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    // MARK: - 落库（唯一写手语义：门禁事件只由本服务写）

    @discardableResult
    static func recordOverride(
        reasonTag: String,
        note: String,
        date: Date = Date(),
        calendar: Calendar = .current,
        in context: ModelContext
    ) -> GateEvent {
        let event = GateEvent()
        event.kind = "override"
        event.reasonTag = reasonTag
        event.note = note
        event.date = date
        event.weekIndex = weekIndex(of: date, calendar: calendar)
        context.insert(event)
        return event
    }

    // MARK: - 计数（陈述用，不进门禁）

    /// 本周（周一起始）override 次数
    static func overrideCountThisWeek(
        events: [GateEvent],
        date: Date,
        calendar: Calendar = .current
    ) -> Int {
        let week = weekIndex(of: date, calendar: calendar)
        return events.filter { $0.kind == "override" && $0.weekIndex == week }.count
    }

    // MARK: - 周索引（周一起始）

    static func weekIndex(of date: Date, calendar: Calendar) -> Int {
        var cal = calendar
        cal.firstWeekday = 2 // 周一
        let week = cal.dateInterval(of: .weekOfYear, for: date)
        return week?.start.daysSinceEpoch ?? 0
    }

    static func isSameDay(_ a: Date, _ b: Date, calendar: Calendar) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }
}

private extension Date {
    var daysSinceEpoch: Int {
        Int(timeIntervalSince1970) / 86_400
    }
}

import Foundation

// M7.2 周历（PRD M9：周一起始；周报/本地通知的区间与排期都以此为准）。
// 纯逻辑、无 SwiftUI/UIKit 依赖，可完整单测。

enum WeekCalendar {
    /// iso8601 周历：周一起始、当前时区（与用户感知的「本周」一致）
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        calendar.firstWeekday = 2 // 周一（PRD M9）
        return calendar
    }()

    private static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = WeekCalendar.calendar
        formatter.timeZone = WeekCalendar.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// 该日所在周的周一 00:00:00（本地时区）
    static func weekStart(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// 该日所在周的结束时刻 = 下周一 00:00:00（区间 [weekStart, weekEnd)）
    static func weekEnd(for date: Date) -> Date {
        nextWeekStart(for: date)
    }

    /// 该日所在周的下周一 00:00:00
    static func nextWeekStart(for date: Date) -> Date {
        calendar.date(byAdding: .day, value: 7, to: weekStart(for: date)) ?? weekStart(for: date)
    }

    /// 稳定去重标识：weekStart 的 "yyyy-MM-dd"（本地时区，避免 UTC 偏移挪天）
    static func weekKey(for date: Date) -> String {
        keyFormatter.string(from: weekStart(for: date))
    }

    /// 周报通知时刻：本周日（weekStart+6 天）hour:00 的 DateComponents（含 weekday=1）。
    /// 用组件而非绝对日期排期：跨夏令时也钉在本地 21:00。
    static func sundayEveningComponents(from weekStart: Date, hour: Int = 21) -> DateComponents {
        let sunday = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        var components = calendar.dateComponents([.year, .month, .day, .weekday], from: sunday)
        components.hour = hour
        components.minute = 0
        return components
    }
}

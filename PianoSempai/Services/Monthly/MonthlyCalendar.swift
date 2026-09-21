import Foundation

// M7.2 月历（PRD M8：月报每月 1 号生成上月；月界口径以本文件为准）。
// 纯逻辑、无 SwiftUI/UIKit 依赖，可完整单测。

enum MonthlyCalendar {
    /// 公历、当前时区、周一起始（与 WeekCalendar 的周界同一套本地时区语义，月内归周才无缝）
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2 // 周一（PRD M9）
        return calendar
    }()

    /// 该时刻所在月的 1 号 00:00:00（本地时区）
    static func monthStart(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    /// 下个月 1 号 00:00:00（月报区间右端；区间取 [monthStart, nextMonthStart) 左闭右开）
    static func nextMonthStart(for date: Date) -> Date {
        calendar.date(byAdding: .month, value: 1, to: monthStart(for: date)) ?? monthStart(for: date)
    }

    /// 周期键 "yyyy-MM"（零填充；周报按 weekKey 去重，月报按 periodKey 去重，一个月一条）
    static func periodKey(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

    static func periodKey(for date: Date) -> String {
        let (year, month) = yearMonth(for: date)
        return periodKey(year: year, month: month)
    }

    /// 该时刻所属自然年/月（用于 periodKey 与快照字段）
    static func yearMonth(for date: Date) -> (year: Int, month: Int) {
        let components = calendar.dateComponents([.year, .month], from: date)
        return (components.year ?? 0, components.month ?? 0)
    }

    /// 月份切换用（S22 首屏「‹ 8月 [9月] 10月 ›」三段 pill）：当前月与前后月 1 号
    static func monthStarts(around date: Date) -> (prev: Date, current: Date, next: Date) {
        let current = monthStart(for: date)
        let prev = calendar.date(byAdding: .month, value: -1, to: current) ?? current
        return (prev: prev, current: current, next: nextMonthStart(for: date))
    }

    /// 区间 [start, end) 内每一天的 startOfDay（本地时区，升序）；空区间给空数组。
    /// 月报的「当月覆盖周数」等按天枚举的口径都走这里。
    static func days(in start: Date, until end: Date) -> [Date] {
        guard start < end else { return [] }
        var days: [Date] = []
        var day = calendar.startOfDay(for: start)
        while day < end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }
}

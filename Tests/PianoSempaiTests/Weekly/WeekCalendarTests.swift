import XCTest
@testable import PianoSempai

/// M7.2 周历边界（PRD M9：周一起始）。纯逻辑，无 SwiftUI/UIKit。
final class WeekCalendarTests: XCTestCase {

    private let calendar = WeekCalendar.calendar

    private func date(_ ymd: String, _ hms: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: "\(ymd) \(hms)")!
    }

    private func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    // MARK: weekStart 边界

    func testMondayEarlyMorningBelongsToSameDay() {
        // 周一 00:30 → 当天周一 00:00
        let monday = date("2026-09-21", "00:30:00")
        XCTAssertEqual(stamp(WeekCalendar.weekStart(for: monday)), "2026-09-21 00:00:00")
    }

    func testSundayLateNightBelongsToThisWeeksMonday() {
        // 周日 23:50 → 本周一（不是下周一）
        let sunday = date("2026-09-27", "23:50:00")
        XCTAssertEqual(stamp(WeekCalendar.weekStart(for: sunday)), "2026-09-21 00:00:00")
    }

    func testSundayLastMinuteStillThisWeek() {
        let sunday = date("2026-09-27", "23:59:59")
        XCTAssertEqual(stamp(WeekCalendar.weekStart(for: sunday)), "2026-09-21 00:00:00")
    }

    func testNextMondayBelongsToNextWeek() {
        let nextMonday = date("2026-09-28", "00:00:00")
        XCTAssertEqual(stamp(WeekCalendar.weekStart(for: nextMonday)), "2026-09-28 00:00:00")
    }

    func testWeekStartCrossesMonth() {
        // 2026-11-01 是周日 → 周一是上月 10-26
        let sunday = date("2026-11-01", "10:00:00")
        XCTAssertEqual(stamp(WeekCalendar.weekStart(for: sunday)), "2026-10-26 00:00:00")
    }

    func testWeekStartCrossesYear() {
        // 2027-01-01 是周五 → ISO 周一起始是上一年 12-28
        let newYear = date("2027-01-01", "12:00:00")
        XCTAssertEqual(stamp(WeekCalendar.weekStart(for: newYear)), "2026-12-28 00:00:00")
    }

    // MARK: weekEnd / nextWeekStart

    func testWeekEndIsNextMondayMidnight() {
        let wednesday = date("2026-09-23", "12:00:00")
        XCTAssertEqual(stamp(WeekCalendar.weekEnd(for: wednesday)), "2026-09-28 00:00:00")
        XCTAssertEqual(stamp(WeekCalendar.nextWeekStart(for: wednesday)), "2026-09-28 00:00:00")
    }

    func testWeekIntervalCoversWholeWeek() {
        let friday = date("2026-09-25", "09:00:00")
        let start = WeekCalendar.weekStart(for: friday)
        let end = WeekCalendar.weekEnd(for: friday)
        XCTAssertLessThan(start, friday)
        XCTAssertLessThan(friday, end)
        XCTAssertEqual(end.timeIntervalSince(start), 7 * 24 * 3600)
    }

    // MARK: weekKey

    func testWeekKeyIsWeekStartDate() {
        XCTAssertEqual(WeekCalendar.weekKey(for: date("2026-09-27", "23:50:00")), "2026-09-21")
        XCTAssertEqual(WeekCalendar.weekKey(for: date("2026-09-21", "00:30:00")), "2026-09-21")
        XCTAssertEqual(WeekCalendar.weekKey(for: date("2026-09-28", "00:00:00")), "2026-09-28")
    }

    func testWeekKeyStableAcrossYearBoundary() {
        // 跨年周：key 跟着 weekStart（2026-12-28），不跳到 2027
        XCTAssertEqual(WeekCalendar.weekKey(for: date("2027-01-01", "12:00:00")), "2026-12-28")
        XCTAssertEqual(WeekCalendar.weekKey(for: date("2027-01-03", "12:00:00")), "2026-12-28")
    }

    // MARK: 周日 21:00 组件

    func testSundayEveningComponentsAreSunday21() {
        let weekStart = date("2026-09-21", "00:00:00")
        let components = WeekCalendar.sundayEveningComponents(from: weekStart)
        XCTAssertEqual(components.weekday, 1, "周日")
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 27)
        XCTAssertEqual(components.hour, 21)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(stamp(calendar.date(from: components)!), "2026-09-27 21:00:00")
    }

    func testSundayEveningComponentsCustomHour() {
        let weekStart = date("2026-09-21", "00:00:00")
        let components = WeekCalendar.sundayEveningComponents(from: weekStart, hour: 20)
        XCTAssertEqual(components.hour, 20)
        XCTAssertEqual(stamp(calendar.date(from: components)!), "2026-09-27 20:00:00")
    }

    func testSundayEveningComponentsAcrossYearBoundary() {
        let weekStart = date("2026-12-28", "00:00:00")
        let components = WeekCalendar.sundayEveningComponents(from: weekStart)
        XCTAssertEqual(components.year, 2027)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 3)
        XCTAssertEqual(stamp(calendar.date(from: components)!), "2027-01-03 21:00:00")
    }
}

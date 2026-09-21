import Foundation
import XCTest

@testable import PianoSempai

/// M7.2 月历（PRD M8 月界口径）：月首/月末/跨月跨年、periodKey 零填充、月份切换三天、按天枚举。
@MainActor
final class MonthlyCalendarTests: XCTestCase {

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = MonthlyCalendar.calendar
        formatter.timeZone = MonthlyCalendar.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }

    /// "yyyy-MM-dd HH:mm:ss"（本地时区，断言可读）
    private func text(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = MonthlyCalendar.calendar
        formatter.timeZone = MonthlyCalendar.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    // MARK: - 月首

    func testMonthStartIsFirstDayMidnight() {
        XCTAssertEqual(text(MonthlyCalendar.monthStart(for: date("2026-09-15 14:32:07"))), "2026-09-01 00:00:00")
    }

    func testMonthStartOnFirstDayIsStable() {
        XCTAssertEqual(text(MonthlyCalendar.monthStart(for: date("2026-09-01 00:00:00"))), "2026-09-01 00:00:00")
    }

    func testMonthStartOnLastDayOfMonth() {
        // 1/31 → 仍归 1 月（月末不串月）
        XCTAssertEqual(text(MonthlyCalendar.monthStart(for: date("2026-01-31 23:59:59"))), "2026-01-01 00:00:00")
        // 12/31 → 仍归 12 月（跨年边界前一个月）
        XCTAssertEqual(text(MonthlyCalendar.monthStart(for: date("2026-12-31 23:59:59"))), "2026-12-01 00:00:00")
    }

    func testFebruary() {
        XCTAssertEqual(text(MonthlyCalendar.monthStart(for: date("2026-02-14 09:00:00"))), "2026-02-01 00:00:00")
        // 平年 2 月 28 天：2/28 仍是 2 月，下个月 3/1
        XCTAssertEqual(text(MonthlyCalendar.monthStart(for: date("2026-02-28 23:00:00"))), "2026-02-01 00:00:00")
        XCTAssertEqual(text(MonthlyCalendar.nextMonthStart(for: date("2026-02-28 23:00:00"))), "2026-03-01 00:00:00")
    }

    // MARK: - 下个月 / 跨月跨年

    func testNextMonthStartWithinYear() {
        XCTAssertEqual(text(MonthlyCalendar.nextMonthStart(for: date("2026-08-20 10:00:00"))), "2026-09-01 00:00:00")
    }

    func testNextMonthStartCrossesYear() {
        XCTAssertEqual(text(MonthlyCalendar.nextMonthStart(for: date("2026-12-15 10:00:00"))), "2027-01-01 00:00:00")
    }

    func testMonthBoundaryIsLeftClosedRightOpen() {
        // 月报区间 [monthStart, nextMonthStart)：上月最后一刻不计入、本月 1 号 00:00 计入
        let monthStart = MonthlyCalendar.monthStart(for: date("2026-09-15 12:00:00"))
        let monthEnd = MonthlyCalendar.nextMonthStart(for: date("2026-09-15 12:00:00"))
        XCTAssertFalse(date("2026-08-31 23:59:59") >= monthStart && date("2026-08-31 23:59:59") < monthEnd)
        XCTAssertTrue(date("2026-09-01 00:00:00") >= monthStart && date("2026-09-01 00:00:00") < monthEnd)
        XCTAssertFalse(date("2026-10-01 00:00:00") >= monthStart && date("2026-10-01 00:00:00") < monthEnd)
    }

    // MARK: - periodKey

    func testPeriodKeyZeroPadded() {
        XCTAssertEqual(MonthlyCalendar.periodKey(year: 2026, month: 3), "2026-03")
        XCTAssertEqual(MonthlyCalendar.periodKey(year: 2026, month: 9), "2026-09")
        XCTAssertEqual(MonthlyCalendar.periodKey(year: 2026, month: 12), "2026-12")
    }

    func testPeriodKeyForDate() {
        XCTAssertEqual(MonthlyCalendar.periodKey(for: date("2026-03-01 00:00:00")), "2026-03")
        XCTAssertEqual(MonthlyCalendar.periodKey(for: date("2026-01-31 23:59:59")), "2026-01")
        XCTAssertEqual(MonthlyCalendar.periodKey(for: date("2026-12-31 23:59:59")), "2026-12")
    }

    func testYearMonth() {
        let (year, month) = MonthlyCalendar.yearMonth(for: date("2026-09-15 08:00:00"))
        XCTAssertEqual(year, 2026)
        XCTAssertEqual(month, 9)
    }

    // MARK: - 月份切换

    func testMonthStartsAround() {
        let starts = MonthlyCalendar.monthStarts(around: date("2026-09-15 12:00:00"))
        XCTAssertEqual(text(starts.prev), "2026-08-01 00:00:00")
        XCTAssertEqual(text(starts.current), "2026-09-01 00:00:00")
        XCTAssertEqual(text(starts.next), "2026-10-01 00:00:00")
    }

    func testMonthStartsAroundCrossesYear() {
        let starts = MonthlyCalendar.monthStarts(around: date("2027-01-05 12:00:00"))
        XCTAssertEqual(text(starts.prev), "2026-12-01 00:00:00")
        XCTAssertEqual(text(starts.current), "2027-01-01 00:00:00")
        XCTAssertEqual(text(starts.next), "2027-02-01 00:00:00")
    }

    // MARK: - 按天枚举

    func testDaysEnumeratesWholeMonth() {
        // 2026-09 有 30 天；末日是 9/30，不含 10/1
        let days = MonthlyCalendar.days(
            in: MonthlyCalendar.monthStart(for: date("2026-09-15 12:00:00")),
            until: MonthlyCalendar.nextMonthStart(for: date("2026-09-15 12:00:00"))
        )
        XCTAssertEqual(days.count, 30)
        XCTAssertEqual(text(days.first!), "2026-09-01 00:00:00")
        XCTAssertEqual(text(days.last!), "2026-09-30 00:00:00")
    }

    func testDaysEnumeratesFebruaryLeapAndCommonYear() {
        let feb2026 = MonthlyCalendar.days(
            in: MonthlyCalendar.monthStart(for: date("2026-02-10 12:00:00")),
            until: MonthlyCalendar.nextMonthStart(for: date("2026-02-10 12:00:00"))
        )
        XCTAssertEqual(feb2026.count, 28) // 2026 平年

        let feb2028 = MonthlyCalendar.days(
            in: MonthlyCalendar.monthStart(for: date("2028-02-10 12:00:00")),
            until: MonthlyCalendar.nextMonthStart(for: date("2028-02-10 12:00:00"))
        )
        XCTAssertEqual(feb2028.count, 29) // 2028 闰年
    }

    func testDaysEmptyInterval() {
        let start = MonthlyCalendar.monthStart(for: date("2026-09-15 12:00:00"))
        XCTAssertTrue(MonthlyCalendar.days(in: start, until: start).isEmpty)
    }
}

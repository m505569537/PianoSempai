import Foundation
import XCTest

@testable import PianoSempai

/// S20 时间线的月份过滤（S22 观察卡「引用 N 个 take」chip 点击 → 回档案按该月过滤）。
/// 口径与月报一致：periodKey 由 take.startedAt 归自然月（MonthlyCalendar.periodKey）。
final class ArchiveMonthFilterTests: XCTestCase {

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = MonthlyCalendar.calendar
        formatter.timeZone = MonthlyCalendar.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }

    private func makeTake(at text: String) -> Take {
        Take(startedAt: date(text), durationSec: 900, taskType: "main", hasMidi: true)
    }

    func testNilPeriodKeyKeepsAllTakes() {
        let takes = [makeTake(at: "2026-08-20 10:00:00"), makeTake(at: "2026-09-03 10:00:00")]
        XCTAssertEqual(ArchiveMonthFilter.apply(takes: takes, periodKey: nil).count, 2)
    }

    func testFiltersToRequestedMonth() {
        let takes = [
            makeTake(at: "2026-08-20 10:00:00"),
            makeTake(at: "2026-09-03 10:00:00"),
            makeTake(at: "2026-09-30 23:59:59"),
            makeTake(at: "2026-10-01 00:00:00"), // 10/1 00:00 归 10 月（左闭右开，与月报同口径）
        ]
        let filtered = ArchiveMonthFilter.apply(takes: takes, periodKey: "2026-09")
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered.map { MonthlyCalendar.periodKey(for: $0.startedAt) }, ["2026-09", "2026-09"])
    }

    func testUnknownPeriodKeyYieldsEmpty() {
        let takes = [makeTake(at: "2026-09-03 10:00:00")]
        XCTAssertTrue(ArchiveMonthFilter.apply(takes: takes, periodKey: "1999-01").isEmpty)
    }

    func testMalformedPeriodKeyYieldsEmpty() {
        let takes = [makeTake(at: "2026-09-03 10:00:00")]
        XCTAssertTrue(ArchiveMonthFilter.apply(takes: takes, periodKey: "坏数据").isEmpty)
    }
}

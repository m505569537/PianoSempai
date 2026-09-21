import Foundation
import XCTest

@testable import PianoSempai

/// 时长文案（周报与月报共用）：整小时省略 0 分、不足 1 小时只说分钟。
final class DurationTextTests: XCTestCase {

    func testHoursAndMinutes() {
        XCTAssertEqual(DurationText.hoursMinutes(30_720), "8 小时 32 分")
        XCTAssertEqual(DurationText.hoursMinutes(3661), "1 小时 1 分")
    }

    func testWholeHourDropsZeroMinutes() {
        XCTAssertEqual(DurationText.hoursMinutes(7200), "2 小时")
        XCTAssertEqual(DurationText.hoursMinutes(3600), "1 小时")
    }

    func testUnderOneHourOnlyMinutes() {
        XCTAssertEqual(DurationText.hoursMinutes(2700), "45 分")
        XCTAssertEqual(DurationText.hoursMinutes(59), "0 分", "不足 1 分如实 0 分，不省略成空串")
    }

    func testZeroAndNegativeAreSafe() {
        XCTAssertEqual(DurationText.hoursMinutes(0), "0 分")
        XCTAssertEqual(DurationText.hoursMinutes(-5), "0 分", "坏数据不显示负时长")
    }

    func testWeeklyDigestStillPrefixesGong() {
        // 复用后周报文案不变：仍是「共 H 小时 M 分」
        let digest = WeeklyDigestBuilder.build(
            takes: [
                Take(startedAt: date("2026-09-21 10:00:00"), durationSec: 30_720, taskType: "main", hasMidi: true),
            ],
            pieces: [],
            goal: 3,
            now: date("2026-09-21 20:00:00")
        )
        XCTAssertTrue(DigestText.weeklyReportNoteBody(digest).contains("共 8 小时 32 分"))
    }

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = WeekCalendar.calendar
        formatter.timeZone = WeekCalendar.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }
}

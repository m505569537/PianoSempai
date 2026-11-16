import XCTest
@testable import PianoSempai

/// 自动快照纯逻辑（2026-11-12）：到期判定 / 文件命名排序 / 滚动清理边界。
/// 真正写盘与 SwiftData 快照不在此测（走 ExportService 既有覆盖 + 真机验证）。
final class AutoSnapshotTests: XCTestCase {

    private func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: iso)!
    }

    // MARK: - 到期判定

    func testIsDueWithoutHistoryIsTrue() {
        XCTAssertTrue(AutoSnapshot.isDue(lastRunAt: nil, now: date("2026-11-12 10:00:00")),
                      "首次安装应立刻备份一次")
    }

    func testIsDueWithinIntervalIsFalse() {
        let now = date("2026-11-12 10:00:00")
        XCTAssertFalse(AutoSnapshot.isDue(lastRunAt: now.addingTimeInterval(-6 * 24 * 3600), now: now))
    }

    func testIsDueExactlyAtIntervalIsTrue() {
        let now = date("2026-11-12 10:00:00")
        XCTAssertTrue(AutoSnapshot.isDue(
            lastRunAt: now.addingTimeInterval(-AutoSnapshot.interval), now: now
        ), "恰好满一周即到期（边界含等于）")
    }

    func testIsDueBeyondIntervalIsTrue() {
        let now = date("2026-11-12 10:00:00")
        XCTAssertTrue(AutoSnapshot.isDue(lastRunAt: now.addingTimeInterval(-8 * 24 * 3600), now: now))
    }

    // MARK: - 文件命名

    func testFileNameHasPrefixAndSortableStamp() {
        let name = AutoSnapshot.fileName(
            now: date("2026-11-12 15:30:05"),
            timeZone: TimeZone(identifier: "Asia/Shanghai")!
        )
        XCTAssertEqual(name, "auto-snapshot-20261112-153005.zip")
        XCTAssertTrue(name.hasPrefix(AutoSnapshot.filePrefix))
    }

    func testFileNameLexicographicOrderMatchesChronologicalOrder() {
        let tz = TimeZone(identifier: "Asia/Shanghai")!
        let earlier = AutoSnapshot.fileName(now: date("2026-11-05 09:00:00"), timeZone: tz)
        let later = AutoSnapshot.fileName(now: date("2026-11-12 09:00:00"), timeZone: tz)
        XCTAssertLessThan(earlier, later, "字典序必须等于时间序（清理依赖这一点）")
    }

    // MARK: - 滚动清理

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/exports").appendingPathComponent(name)
    }

    func testPruneKeepsNewestAndDeletesOlder() {
        let urls = [
            url("auto-snapshot-20260101-100000.zip"),
            url("auto-snapshot-20260201-100000.zip"),
            url("auto-snapshot-20260301-100000.zip"),
            url("auto-snapshot-20260401-100000.zip"),
        ]
        let deleted = AutoSnapshot.urlsToPrune(urls, keep: 2).map(\.lastPathComponent)
        XCTAssertEqual(deleted.sorted(), [
            "auto-snapshot-20260101-100000.zip",
            "auto-snapshot-20260201-100000.zip",
        ])
    }

    func testPruneKeepsAllWhenUnderLimit() {
        let urls = [url("auto-snapshot-20260101-100000.zip")]
        XCTAssertTrue(AutoSnapshot.urlsToPrune(urls, keep: 3).isEmpty)
    }

    func testPruneNeverTouchesManualExports() {
        let urls = [
            url("pianosempai-export-20260101-100000-abc.zip"),
            url("auto-snapshot-20260101-100000.zip"),
            url("auto-snapshot-20260201-100000.zip"),
            url("auto-snapshot-20260301-100000.zip"),
            url("auto-snapshot-20260401-100000.zip"),
            url("pre-restore-snapshot-pianosempai-export-20260101.zip"),
        ]
        let deleted = AutoSnapshot.urlsToPrune(urls, keep: 2).map(\.lastPathComponent)
        XCTAssertEqual(deleted.sorted(), [
            "auto-snapshot-20260101-100000.zip",
            "auto-snapshot-20260201-100000.zip",
        ], "手动导出与恢复前快照永不被自动清理误删")
    }

    func testPruneWithZeroKeepDeletesAllOwn() {
        let urls = [
            url("auto-snapshot-20260101-100000.zip"),
            url("auto-snapshot-20260201-100000.zip"),
        ]
        XCTAssertEqual(AutoSnapshot.urlsToPrune(urls, keep: 0).count, 2)
    }
}

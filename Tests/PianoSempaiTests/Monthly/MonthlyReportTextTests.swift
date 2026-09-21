import Foundation
import XCTest

@testable import PianoSempai

/// M7.2 月报文案层（S22 首屏：统计 2x2、教材路线、热身与门禁、节奏稳定度、观察引用 chip）。
/// 重点守两个如实降级点（红线 1：不编造）：
//   1. 教材路线只显当前值——不产出任何推进箭头/百分比/进度条；
//   2. 侧拍 chip 不渲染（refsVideoCount 恒 0），手型趋势整段由视图隐藏。
final class MonthlyReportTextTests: XCTestCase {

    // MARK: 统计卡

    func testStatCellsUseRealValues() {
        let snapshot = MonthlyReportSnapshot(
            year: 2026, month: 9, validDays: 14, totalDurationSec: 30_720, takeCount: 47,
            avgSessionsPerWeek: 3.2
        )
        let cells = MonthlyReportText.statCells(snapshot)
        XCTAssertEqual(cells.map(\.value), ["14 天", "8 小时 32 分", "47 take", "3.2次"])
        XCTAssertEqual(cells.map(\.label), ["有效练习", "总时长", "完成", "平均周频"])
    }

    func testStatCellsWholeHourDropsZeroMinutes() {
        let snapshot = MonthlyReportSnapshot(year: 2026, month: 9, totalDurationSec: 7200)
        XCTAssertEqual(MonthlyReportText.statCells(snapshot)[1].value, "2 小时")
        let half = MonthlyReportSnapshot(year: 2026, month: 9, totalDurationSec: 2700)
        XCTAssertEqual(MonthlyReportText.statCells(half)[1].value, "45 分")
        let zero = MonthlyReportSnapshot(year: 2026, month: 9, totalDurationSec: 0)
        XCTAssertEqual(MonthlyReportText.statCells(zero)[1].value, "0 分")
    }

    func testSessionsPerWeekNilShowsDashNotZero() {
        XCTAssertEqual(MonthlyReportText.sessionsPerWeekText(nil), "—", "nil 不补 0")
        XCTAssertEqual(MonthlyReportText.sessionsPerWeekText(2.0), "2.0次")
        XCTAssertEqual(MonthlyReportText.sessionsPerWeekText(1.44), "1.4次")
    }

    // MARK: 教材路线：只显当前值

    func testRouteRowsShowCurrentValuesOnly() {
        let snapshot = MonthlyReportSnapshot(
            year: 2026, month: 9, beyerCurrent: 48, hanonCurrent: 4, unlocked599: true, current599: 5
        )
        let rows = MonthlyReportText.routeRows(snapshot)
        XCTAssertEqual(rows.map(\.title), ["拜厄", "哈农", "车尔尼599"])
        XCTAssertEqual(rows.map(\.detail), ["当前 48", "当前 4", "已开始 第 5 首"])
        XCTAssertEqual(rows.map(\.isLocked), [false, false, false])
        for row in rows {
            XCTAssertFalse(row.detail.contains("→"), "不编推进箭头：\(row.detail)")
            XCTAssertFalse(row.detail.contains("%"), "不编进度百分比：\(row.detail)")
        }
    }

    func testRoute599LockedWithoutProjectedWeek() {
        let snapshot = MonthlyReportSnapshot(year: 2026, month: 9, unlocked599: false, projected599Week: 0)
        let row = MonthlyReportText.routeRows(snapshot)[2]
        XCTAssertEqual(row.title, "车尔尼599 🔒")
        XCTAssertEqual(row.detail, "", "没有预计周数就不编月份")
        XCTAssertTrue(row.isLocked, "锁行按 spec 整体 0.5 透明")
    }

    func testRoute599LockedWithProjectedWeek() {
        let snapshot = MonthlyReportSnapshot(year: 2026, month: 9, unlocked599: false, projected599Week: 11)
        XCTAssertEqual(MonthlyReportText.routeRows(snapshot)[2].detail, "预计第 11 周解锁")
    }

    func testRoute599UnlockedWithoutCurrentNumberDoesNotInventOne() {
        // 脏数据：unlocked599 = true 但 current599 缺 → 不拿 1 冒充
        let snapshot = MonthlyReportSnapshot(year: 2026, month: 9, unlocked599: true, current599: nil)
        XCTAssertEqual(MonthlyReportText.routeRows(snapshot)[2].detail, "已开始")
    }

    func testRouteWithoutPathStateUsesSafeDefaults() {
        let snapshot = MonthlyReportSnapshot(year: 2026, month: 9)
        XCTAssertEqual(MonthlyReportText.routeRows(snapshot).map(\.detail), ["当前 1", "当前 1", ""])
    }

    // MARK: 热身与门禁

    func testWarmupText() {
        XCTAssertEqual(MonthlyReportText.warmupText(MonthlyReportSnapshot(year: 2026, month: 9, warmupCompletionPct: 79)), "79%")
        XCTAssertEqual(MonthlyReportText.warmupText(MonthlyReportSnapshot(year: 2026, month: 9, warmupCompletionPct: nil)), MonthlyReportText.warmupNoPlanText)
        XCTAssertEqual(MonthlyReportText.warmupText(MonthlyReportSnapshot(year: 2026, month: 9, warmupCompletionPct: 0)), "0%", "有计划但 0 完成如实 0（与「无计划」区分）")
    }

    func testOverrideTextAndReasonChips() {
        let none = MonthlyReportSnapshot(year: 2026, month: 9, overrideCount: 0)
        XCTAssertEqual(MonthlyReportText.overrideText(none), MonthlyReportText.noOverrideText)
        XCTAssertTrue(MonthlyReportText.overrideReasonChips(none).isEmpty)

        let some = MonthlyReportSnapshot(
            year: 2026, month: 9, overrideCount: 4,
            overrideReasons: ["时间不够": 2, "other": 1, "热身曲太无聊": 1]
        )
        XCTAssertEqual(MonthlyReportText.overrideText(some), "强开主菜 4 次")
        XCTAssertEqual(
            MonthlyReportText.overrideReasonChips(some),
            ["时间不够×2", "other" == "other" ? "其他×1" : "", "热身曲太无聊×1"],
            "真实标签保留、other 显「其他」、按次数降序"
        )
    }

    // MARK: 节奏稳定度

    func testRhythmInsufficientWhenAllNil() {
        let snapshot = MonthlyReportSnapshot(
            year: 2026, month: 9, rhythmFirstWeekScore: nil, rhythmLastWeekScore: nil,
            weeklyRhythmScores: [nil, nil]
        )
        XCTAssertEqual(MonthlyReportText.rhythm(snapshot), .insufficient)
        XCTAssertEqual(MonthlyReportText.rhythmText(.insufficient), MonthlyReportText.rhythmInsufficientText)
    }

    func testRhythmTrendUsesFirstAndLastNonNil() {
        let snapshot = MonthlyReportSnapshot(
            year: 2026, month: 9, rhythmFirstWeekScore: 85, rhythmLastWeekScore: 72,
            weeklyRhythmScores: [85, 61, nil, 72]
        )
        XCTAssertEqual(MonthlyReportText.rhythm(snapshot), .trend(weeks: 4, first: 85, last: 72, delta: -13))
        XCTAssertEqual(MonthlyReportText.rhythmText(MonthlyReportText.rhythm(snapshot)), "4 周 85→72（-13）")
    }

    func testRhythmDeltaIsSigned() {
        XCTAssertEqual(MonthlyReportText.signed(19), "+19")
        XCTAssertEqual(MonthlyReportText.signed(-3), "-3")
        XCTAssertEqual(MonthlyReportText.signed(0), "+0", "持平显 +0，不是缺数据")
    }

    // MARK: 观察引用 chip（红线 2）

    func testObservationChipsOnlyRenderRealEvidence() {
        let withTakes = MonthlyReportSnapshot(year: 2026, month: 9, refsTakeCount: 47, refsVideoCount: 0)
        let chips = MonthlyReportText.observationChips(withTakes)
        XCTAssertEqual(chips.map(\.text), ["引用 47 个 take"])
        XCTAssertEqual(chips.map(\.kind), [.takes])

        // 无视频批次：侧拍 chip 不渲染（不是渲染「引用 0 条侧拍」）
        let noTakes = MonthlyReportSnapshot(year: 2026, month: 9, refsTakeCount: 0, refsVideoCount: 0)
        XCTAssertTrue(MonthlyReportText.observationChips(noTakes).isEmpty)

        // 视频数 >0 时才出现侧拍 chip（当前模型恒 0，此断言锁死降级契约）
        let withVideos = MonthlyReportSnapshot(year: 2026, month: 9, refsTakeCount: 47, refsVideoCount: 6)
        XCTAssertEqual(
            MonthlyReportText.observationChips(withVideos).map(\.text),
            ["引用 47 个 take", "引用 6 条侧拍"]
        )
    }

    // MARK: 标题与固定文案

    func testHeaderTitleAndMonthLabel() {
        XCTAssertEqual(MonthlyReportText.headerTitle(year: 2026, month: 9), "2026 年 9 月 · 月度报告")
        XCTAssertEqual(MonthlyReportText.shortMonthLabel(year: 2026, month: 9, sameYear: true), "9 月")
        XCTAssertEqual(MonthlyReportText.shortMonthLabel(year: 2025, month: 12, sameYear: false), "2025 年 12 月")
    }

    func testLockedDeclarationsArePresent() {
        XCTAssertEqual(MonthlyReportText.routeDeclaration, "解锁只由硬数据规则判定")
        XCTAssertEqual(MonthlyReportText.overrideFootnote, "记录只用于你自己观察，不影响解锁。")
    }
}

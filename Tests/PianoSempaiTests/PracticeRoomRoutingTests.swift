import XCTest
@testable import PianoSempai

/// Today → 练习室路由纯决策（Fix 批次 2026-09-30）：谱坐标解析 / 循环格诚实文案 /
/// 断连顶栏副行按真实 phase。纯函数断言，不依赖视图 / SwiftData。
final class PracticeRoomRoutingTests: XCTestCase {

    // MARK: BundledScoreCoordinates.resolve

    func testResolveBeyerBounds() {
        XCTAssertEqual(BundledScoreCoordinates.resolve(book: "拜厄", number: 1),
                       BundledScoreCoordinates(book: "拜厄", number: 1))
        XCTAssertEqual(BundledScoreCoordinates.resolve(book: "拜厄", number: 106),
                       BundledScoreCoordinates(book: "拜厄", number: 106))
        XCTAssertNil(BundledScoreCoordinates.resolve(book: "拜厄", number: 107))
    }

    func testResolveHanonBounds() {
        XCTAssertEqual(BundledScoreCoordinates.resolve(book: "哈农", number: 20),
                       BundledScoreCoordinates(book: "哈农", number: 20))
        XCTAssertNil(BundledScoreCoordinates.resolve(book: "哈农", number: 21))
    }

    func testResolveNonBundledBookIsNil() {
        XCTAssertNil(BundledScoreCoordinates.resolve(book: "车尔尼599", number: 1))
    }

    func testResolveNilOrEmptyBookIsNil() {
        XCTAssertNil(BundledScoreCoordinates.resolve(book: nil, number: 1))
        XCTAssertNil(BundledScoreCoordinates.resolve(book: "", number: 1))
    }

    // MARK: LoopConfig.cellLabel(totalMeasures:)

    func testCellLabelNoScoreIsNil() {
        // 无谱（totalMeasures 0）：不给区间文案，也不给假默认 1–8
        XCTAssertNil(LoopConfig().cellLabel(totalMeasures: 0))
    }

    func testCellLabelValidRange() {
        // 有效区间：起–止小节（en dash U+2013）
        XCTAssertEqual(LoopConfig().cellLabel(totalMeasures: 8), "1–8小节")
    }

    func testCellLabelRangeExceedingScoreIsNil() {
        // 默认 1…8 但曲目只有 6 小节：区间无效 → nil（不显示越界假数据）
        XCTAssertNil(LoopConfig().cellLabel(totalMeasures: 6))
    }

    // MARK: PracticeStatusSubtitle.text

    func testSubtitleIdle() {
        XCTAssertEqual(PracticeStatusSubtitle.text(phase: .idle), "待开始")
    }

    func testSubtitleActiveTake() {
        XCTAssertEqual(PracticeStatusSubtitle.text(phase: .counting), "Take · 练习进行中")
        XCTAssertEqual(PracticeStatusSubtitle.text(phase: .performing), "Take · 练习进行中")
        XCTAssertEqual(PracticeStatusSubtitle.text(phase: .paused), "Take · 练习进行中")
    }

    func testSubtitleFinished() {
        XCTAssertEqual(PracticeStatusSubtitle.text(phase: .finished), "已结束")
    }
}

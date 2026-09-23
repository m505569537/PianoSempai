import XCTest
@testable import PianoSempai
import SheetMusicCore
import SheetMusicLoader

/// ScoreLineBreaker 测试（问题4：每行小节数可选）。
/// 用真实内置谱（拜厄1，自带强制换行）做转换，锁三件事：
/// - 自动档清掉所有原稿 lineBreak/pageBreak；
/// - 手动 N 档只在「每 N 小节后、且非最后一小节」注入 lineBreak；
/// - breakIndices 纯决策的步进口径。
final class ScoreLineBreakerTests: XCTestCase {

    private func bundledScore() throws -> Score {
        guard let url = BundledScore.url(book: "拜厄", number: 1) else {
            throw XCTSkip("测试宿主 Bundle 缺内置谱，跳过")
        }
        return try ScoreLoader.loadScore(contentsOf: url)
    }

    private func staff0Measures(_ score: Score) -> [Measure] {
        score.parts[0].staves[0].measures
    }

    func testBreakIndicesStride() {
        // 每 2 小节：在 1,3,5... 后换（0-based），不含最后一小节
        XCTAssertEqual(ScoreLineBreaker.breakIndices(measureCount: 8, perLine: 2), [1, 3, 5])
        // 每 4 小节
        XCTAssertEqual(ScoreLineBreaker.breakIndices(measureCount: 9, perLine: 4), [3, 7])
        // 刚好整除：最后一小节本身不注（through: count-2）
        XCTAssertEqual(ScoreLineBreaker.breakIndices(measureCount: 8, perLine: 4), [3])
        // 自动/非法档 → 空
        XCTAssertEqual(ScoreLineBreaker.breakIndices(measureCount: 8, perLine: 0), [])
        XCTAssertEqual(ScoreLineBreaker.breakIndices(measureCount: 8, perLine: 1), [])
    }

    func testAutoClearsAllOriginalBreaks() throws {
        let score = try bundledScore()
        let result = ScoreLineBreaker.apply(to: score, measuresPerLine: 0)
        let measures = staff0Measures(result)
        XCTAssertFalse(measures.isEmpty)
        XCTAssertTrue(measures.allSatisfy { !$0.lineBreak }, "自动档应清掉所有 lineBreak")
        XCTAssertTrue(measures.allSatisfy { !$0.pageBreak }, "自动档应清掉所有 pageBreak")
    }

    func testFixedNInjectsOnlyAtMultiples() throws {
        let score = try bundledScore()
        let count = staff0Measures(score).count
        let result = ScoreLineBreaker.apply(to: score, measuresPerLine: 2)
        let measures = staff0Measures(result)

        let expected = Set(ScoreLineBreaker.breakIndices(measureCount: count, perLine: 2))
        for (idx, m) in measures.enumerated() {
            if expected.contains(idx) {
                XCTAssertTrue(m.lineBreak, "第 \(idx) 小节后应换行")
            } else {
                XCTAssertFalse(m.lineBreak, "第 \(idx) 小节后不应换行")
            }
            XCTAssertFalse(m.pageBreak)
        }
    }

    func testMeasureCountPreserved() throws {
        let score = try bundledScore()
        let before = staff0Measures(score).count
        let result = ScoreLineBreaker.apply(to: score, measuresPerLine: 4)
        XCTAssertEqual(staff0Measures(result).count, before, "转换不得增减小节")
    }
}

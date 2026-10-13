import XCTest
@testable import PianoSempai
import SheetMusicCore
import SheetMusicLoader
import SheetMusicLayout
import SheetMusicLayoutApple

/// 固定档「每行 N 小节」字号拟合（真机验收 2026-10-13：8/行档在密谱上被宽度
/// 提前折行、档位失效）。用真实内置谱锁三件事：
/// - 拜厄1（简单谱）：2/4/8 档都能找到「每行恰 N 小节」的字号，且 ≤ 基础 28；
/// - 哈农1（每小节 8 个十六分音符的密谱）：4 档可行字号明显小于拜厄（密度效应），
///   8 档需微缩字号（实测 ~6）也能整齐放下，不回退；
/// - breaksRespected 判定本身：缺行/空行/多行都算不满足。
/// （可行字号实测值随宽度假设 330pt；引擎 pin 2a3a6f7，数值漂移即警）
final class ScoreLineFitTests: XCTestCase {

    private func bundledScore(book: String, number: Int) throws -> Score {
        guard let url = BundledScore.url(book: book, number: number) else {
            throw XCTSkip("测试宿主 Bundle 缺内置谱，跳过")
        }
        return try ScoreLoader.loadScore(contentsOf: url)
    }

    private func fit(_ score: Score, perLine: Int, width: CGFloat = 330) -> (size: CGFloat, document: LayoutDocument) {
        _ = SheetMusicLayoutApple.install
        return ScoreLineBreaker.fittingStaffSize(
            score: ScoreLineBreaker.apply(to: score, measuresPerLine: perLine),
            perLine: perLine,
            availableWidth: width
        ) { size in
            var o = ScoreViewOptions(wrapToViewWidth: true, breakPolicy: .honor)
            o.staffSize = size
            return o
        }
    }

    func testBeyer1AllChoicesFit() throws {
        let score = try bundledScore(book: "拜厄", number: 1)
        for perLine in [2, 4, 8] {
            let result = fit(score, perLine: perLine)
            XCTAssertTrue(
                ScoreLineBreaker.breaksRespected(result.document, perLine: perLine),
                "拜厄1 perLine=\(perLine) 应有满足解（size=\(result.size)）")
            XCTAssertLessThanOrEqual(result.size, 28, "拟合字号不应超过基础字号")
        }
        // 字号随 N 单调递减（更挤 = 更小）
        let r2 = fit(score, perLine: 2)
        let r4 = fit(score, perLine: 4)
        let r8 = fit(score, perLine: 8)
        XCTAssertLessThan(r4.size, r2.size)
        XCTAssertLessThan(r8.size, r4.size)
    }

    func testHanon1DenseScoreStillFits() throws {
        let score = try bundledScore(book: "哈农", number: 1)
        // 4 档在可读字号内放下
        let r4 = fit(score, perLine: 4)
        XCTAssertTrue(ScoreLineBreaker.breaksRespected(r4.document, perLine: 4))
        XCTAssertLessThanOrEqual(r4.size, 12, "哈农密谱 4/行需明显缩字号（实测 11.0）")
        // 8 档：微缩也能整齐放下（实测 6.0），不静默回退
        let r8 = fit(score, perLine: 8)
        XCTAssertTrue(ScoreLineBreaker.breaksRespected(r8.document, perLine: 8))
        XCTAssertGreaterThanOrEqual(r8.size, 5.5, "拟合字号不低于下限")
    }
}

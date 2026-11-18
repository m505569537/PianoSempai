import SwiftData
import XCTest
@testable import PianoSempai

/// 曲库「book-number → status」汇总的回归测试。
///
/// 背景（2026-11-18 真机崩溃）：导入曲的 `book` 固定为「导入」、`number` 恒为 0，
/// 同一本书导入第二首时两个 key 完全相同。原实现用
/// `Dictionary(uniqueKeysWithValues:)`，重复键会命中
/// `_NativeDictionary.merge(trappingOnDuplicates:)` 触发 EXC_BREAKPOINT，
/// 表现为「导入乐谱之后一进曲库就闪退」。
final class LibraryPieceStatusMapTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: AppSettings.self, PlacementResult.self, CoursePathState.self,
            Piece.self, ScoreFile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    private func makePiece(book: String, number: Int, status: String = "notStarted") -> Piece {
        let piece = Piece(title: "\(book) \(number)", book: book, number: number, status: status)
        context.insert(piece)
        return piece
    }

    /// 崩溃复现：两首导入曲（同 book、同 number）不得触发断言。
    func testDuplicateBookNumberDoesNotCrash() {
        let a = makePiece(book: "导入", number: 0)
        let b = makePiece(book: "导入", number: 0)

        let map = LibraryView.pieceStatusMap(from: [a, b])

        XCTAssertEqual(map.count, 1, "同一个 book-number 只应产出一个键")
        XCTAssertEqual(map["导入-0"], "notStarted")
    }

    /// 重复键要保留「进度更靠前」的状态，不能被后导入的未开始项盖回去。
    func testDuplicateKeepsMostAdvancedStatus() {
        let passed = makePiece(book: "导入", number: 0, status: "passed")
        let fresh = makePiece(book: "导入", number: 0, status: "notStarted")

        XCTAssertEqual(LibraryView.pieceStatusMap(from: [passed, fresh])["导入-0"], "passed")
        XCTAssertEqual(LibraryView.pieceStatusMap(from: [fresh, passed])["导入-0"], "passed",
                       "与数组顺序无关")
    }

    /// 正常路径不受影响：不同 book-number 各出一项。
    func testDistinctPiecesMapIndependently() {
        let beyer = makePiece(book: "拜厄", number: 45, status: "practicing")
        let hanon = makePiece(book: "哈农", number: 3, status: "passed")

        let map = LibraryView.pieceStatusMap(from: [beyer, hanon])

        XCTAssertEqual(map, ["拜厄-45": "practicing", "哈农-3": "passed"])
    }

    /// 未知状态按最低处理：已有 practicing 时不被未知值覆盖。
    func testUnknownStatusDoesNotOverrideKnown() {
        let known = makePiece(book: "拜厄", number: 1, status: "practicing")
        let unknown = makePiece(book: "拜厄", number: 1, status: "whatever")

        XCTAssertEqual(LibraryView.pieceStatusMap(from: [known, unknown])["拜厄-1"], "practicing")
    }
}

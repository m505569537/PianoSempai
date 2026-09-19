import SheetMusicLoader
import SwiftData
import XCTest
@testable import PianoSempai

/// 曲库批次双向验收（Hermes M5 指令）：
/// ① 锁定方向：前置未满足 → locked；满足 → 解锁；② 导入成功入沙盒 / 失败路径不吞错。
final class LibraryServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var baseDir: URL!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: AppSettings.self, PlacementResult.self, CoursePathState.self,
            Piece.self, ScoreFile.self,
            configurations: config
        )
        context = ModelContext(container)
        baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("libtest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: baseDir)
        container = nil
        context = nil
    }

    // MARK: 锁定逻辑（双向）

    private func pathState(beyer: Int, hanon: Int, projected599: Int) -> CoursePathState {
        CoursePathState(currentBeyer: beyer, currentHanon: hanon, projected599Week: projected599)
    }

    func testLockedPieceStaysLockedWhenPrerequisitesUnmet() {
        let state = pathState(beyer: 45, hanon: 1, projected599: 8)
        // 路线未到达的拜厄条目 → locked
        XCTAssertEqual(CourseEngine.catalogStatus(book: "拜厄", number: 46, pathState: state), .locked)
        XCTAssertEqual(CourseEngine.catalogStatus(book: "拜厄", number: 100, pathState: state), .locked)
        // 哈农同理
        XCTAssertEqual(CourseEngine.catalogStatus(book: "哈农", number: 2, pathState: state), .locked)
        // 599 P1 恒锁定
        XCTAssertEqual(CourseEngine.catalogStatus(book: "车尔尼599", number: 1, pathState: state), .locked)
    }

    func testPieceBecomesAvailableWhenPrerequisitesMet() {
        let state = pathState(beyer: 45, hanon: 1, projected599: 8)
        // 当前条目 → practicing；已过条目 → notStarted
        XCTAssertEqual(CourseEngine.catalogStatus(book: "拜厄", number: 45, pathState: state), .practicing)
        XCTAssertEqual(CourseEngine.catalogStatus(book: "拜厄", number: 44, pathState: state), .notStarted)

        // 路线推进到 46（前置满足）→ 原本 locked 的 46 变为可练（@Model 类：改属性即可）
        state.currentBeyer = 46
        XCTAssertEqual(CourseEngine.catalogStatus(book: "拜厄", number: 46, pathState: state), .practicing)
        XCTAssertEqual(CourseEngine.catalogStatus(book: "拜厄", number: 45, pathState: state), .notStarted)

        // 599 的"约 N 周后"取真实推算值
        XCTAssertEqual(CourseEngine.projected599WeeksLabel(pathState: state), 8)
        XCTAssertNil(CourseEngine.projected599WeeksLabel(pathState: pathState(beyer: 45, hanon: 1, projected599: 0)), "未定级不显示周数")
    }

    func testBuiltinCatalogLoads() {
        let entries = CatalogLoader.loadBuiltin()
        XCTAssertGreaterThanOrEqual(entries.count, 130, "拜厄 106 + 哈农 20 + 599 占位")
        XCTAssertTrue(entries.contains(CatalogEntry(book: "拜厄", number: 45, referenceTempo: 76)))
        XCTAssertTrue(entries.contains { $0.book == "车尔尼599" && $0.number == 1 })
    }

    // MARK: 导入（成功 → 沙盒；失败 → 明确错误码）

    private func bundleMusicXML() throws -> URL {
        // 测试宿主是 app，Bundle.main 即 app bundle
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "SpikeSample32", withExtension: "musicxml")
                ?? Bundle(for: Self.self).url(forResource: "SpikeSample32", withExtension: "musicxml"),
            "内置样例谱缺失"
        )
        // 拷到临时目录当"用户文件"
        let temp = baseDir.appendingPathComponent("user-\(UUID().uuidString).musicxml")
        try FileManager.default.copyItem(at: url, to: temp)
        return temp
    }

    func testImportMusicXMLSuccessCopiesIntoSandbox() throws {
        let source = try bundleMusicXML()
        let result = LibraryImportService.importScore(from: source, into: baseDir)

        let imported = try result.get()
        XCTAssertEqual(imported.kind, "musicxml")
        XCTAssertEqual(imported.canFollow, true)
        XCTAssertTrue(imported.relativePath.hasPrefix("scores/"))

        // 文件确实落在沙盒 scores/
        let sandboxURL = baseDir.appendingPathComponent(imported.relativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandboxURL.path))

        // 拷贝后真实解析一致（可跟弹）
        let score = try ScoreLoader.loadScore(contentsOf: sandboxURL)
        XCTAssertGreaterThanOrEqual(score.parts.first?.staves.first?.measures.count ?? 0, 32)
    }

    func testImportCorruptScoreFailsWithoutSideEffects() throws {
        // 构造一个伪 .musicxml（内容是垃圾）
        let bad = baseDir.appendingPathComponent("user-bad.musicxml")
        try Data("<not-a-score>".utf8).write(to: bad)

        let result = LibraryImportService.importScore(from: bad, into: baseDir)

        guard case let .failure(error) = result else {
            return XCTFail("坏文件必须导入失败")
        }
        XCTAssertEqual(error.code, .parseFailed)
        XCTAssertFalse(error.detail.isEmpty, "S08b 要展示具体错误详情（不吞错）")

        // 失败文件绝不入曲库：scores/ 目录不应存在该文件
        let scoresDir = baseDir.appendingPathComponent("scores")
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: scoresDir.path)) ?? []
        XCTAssertTrue(contents.isEmpty, "解析失败的文件不得拷入沙盒")
    }

    func testImportUnsupportedExtensionFails() throws {
        let txt = baseDir.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: txt)
        let result = LibraryImportService.importScore(from: txt, into: baseDir)
        guard case let .failure(error) = result else { return XCTFail(".txt 必须被拒") }
        XCTAssertEqual(error.code, .unsupportedFormat)
    }

    func testImportPDFCopiesToPdfsWithoutParsing() throws {
        // 最小合法 PDF（%PDF- 头即可，我们不解析内容）
        let pdf = baseDir.appendingPathComponent("user-sheet.pdf")
        try Data("%PDF-1.4\n".utf8).write(to: pdf)
        let result = LibraryImportService.importScore(from: pdf, into: baseDir)

        let imported = try result.get()
        XCTAssertEqual(imported.kind, "pdf")
        XCTAssertEqual(imported.canFollow, false, "PDF 不能跟弹")
        XCTAssertTrue(imported.relativePath.hasPrefix("pdfs/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: baseDir.appendingPathComponent(imported.relativePath).path))
    }

    func testImportCopyFailureReportedNotSwallowed() throws {
        // 源文件不存在 → 拷贝阶段失败（PARSE 也不会过——文件读不了）。用 .pdf 跳过解析直达 copy。
        let missing = baseDir.appendingPathComponent("ghost-\(UUID().uuidString).pdf")
        let result = LibraryImportService.importScore(from: missing, into: baseDir)
        guard case let .failure(error) = result else { return XCTFail("源缺失必须失败") }
        XCTAssertEqual(error.code, .copyFailed, "拷贝错误要有明确错误码，不静默")
    }

    func testImportDedupesSameNameFiles() throws {
        let source = try bundleMusicXML()
        _ = try LibraryImportService.importScore(from: source, into: baseDir).get()
        let second = try LibraryImportService.importScore(from: source, into: baseDir).get()
        XCTAssertNotEqual(second.relativePath, "scores/user.musicxml")
        // 两个文件都在
        XCTAssertTrue(FileManager.default.fileExists(atPath: baseDir.appendingPathComponent(second.relativePath).path))
    }
}

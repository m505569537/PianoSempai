import XCTest
import SheetMusicCore
import SheetMusicLoader
@testable import PianoSempai

/// 内置公版谱接线（拜厄 106 + 哈农 20）：资源名纯映射 + 谱可用性四态 + 参考谱 URL 决策。
/// 逻辑测试不依赖宿主是否打包了 .musicxml（Bundle 查找可能为 nil，断言只验决策不验存在）。
final class BundledScoreTests: XCTestCase {

    // MARK: A BundledScore.resourceName 纯映射

    func testResourceNameMapping() {
        // 拜厄：1…106 → beyer_01…beyer_106（磁盘实际命名 %02d 补零）
        XCTAssertEqual(BundledScore.resourceName(book: "拜厄", number: 1), "beyer_01")
        XCTAssertEqual(BundledScore.resourceName(book: "拜厄", number: 9), "beyer_09")
        XCTAssertEqual(BundledScore.resourceName(book: "拜厄", number: 10), "beyer_10")
        XCTAssertEqual(BundledScore.resourceName(book: "拜厄", number: 106), "beyer_106")
        // 哈农：1…20 → hanon_01…hanon_20
        XCTAssertEqual(BundledScore.resourceName(book: "哈农", number: 1), "hanon_01")
        XCTAssertEqual(BundledScore.resourceName(book: "哈农", number: 20), "hanon_20")
    }

    func testResourceNameNilForOutOfRangeAndOtherBooks() {
        XCTAssertNil(BundledScore.resourceName(book: "拜厄", number: 0), "0 条不存在")
        XCTAssertNil(BundledScore.resourceName(book: "拜厄", number: 107), "超出 106 条")
        XCTAssertNil(BundledScore.resourceName(book: "哈农", number: 21), "超出 20 条")
        // 车尔尼599 / 示例曲：没有内置谱，诚实 nil（不冒充）
        XCTAssertNil(BundledScore.resourceName(book: "车尔尼599", number: 1))
        XCTAssertNil(BundledScore.resourceName(book: "车尔尼599", number: 10))
        XCTAssertNil(BundledScore.resourceName(book: "示例", number: 0))
        XCTAssertNil(BundledScore.resourceName(book: "导入", number: 1))
    }

    func testHasBundledMirrorsResourceName() {
        XCTAssertTrue(BundledScore.hasBundled(book: "拜厄", number: 1))
        XCTAssertTrue(BundledScore.hasBundled(book: "哈农", number: 20))
        XCTAssertFalse(BundledScore.hasBundled(book: "拜厄", number: 107))
        XCTAssertFalse(BundledScore.hasBundled(book: "车尔尼599", number: 1))
        XCTAssertFalse(BundledScore.hasBundled(book: "示例", number: 0))
    }

    /// 目录里每条拜厄/哈农都应有内置谱；599 与示例曲没有（与磁盘资源一一对应）
    func testEveryCatalogEntryHasExpectedBundledCoverage() throws {
        let entries = CatalogLoader.loadBuiltin()
        XCTAssertEqual(entries.filter { $0.book == "拜厄" }.count, 106)
        XCTAssertEqual(entries.filter { $0.book == "哈农" }.count, 20)
        for entry in entries {
            let expected: Bool
            switch entry.book {
            case "拜厄": expected = (1...106).contains(entry.number)
            case "哈农": expected = (1...20).contains(entry.number)
            default: expected = false // 车尔尼599 / 示例
            }
            XCTAssertEqual(
                BundledScore.hasBundled(book: entry.book, number: entry.number), expected,
                "\(entry.book) 第\(entry.number)条 的内置谱覆盖与预期不符"
            )
        }
    }

    // MARK: B ScoreAvailability.resolve 四态

    func testResolveBundledScoreForBeyerAndHanon() {
        XCTAssertEqual(
            ScoreAvailability.resolve(scoreFile: nil, isSampleEntry: false, bundledBook: "拜厄", bundledNumber: 1),
            .bundledScore(book: "拜厄", number: 1)
        )
        XCTAssertEqual(
            ScoreAvailability.resolve(scoreFile: nil, isSampleEntry: false, bundledBook: "哈农", bundledNumber: 20),
            .bundledScore(book: "哈农", number: 20)
        )
    }

    func testResolvePriorityRealScoreBeatsBundled() {
        let sf = ScoreFile(kind: "musicxml", fileURL: "scores/a.musicxml", title: "A", canFollow: true)
        XCTAssertEqual(
            ScoreAvailability.resolve(scoreFile: sf, isSampleEntry: false, bundledBook: "拜厄", bundledNumber: 1),
            .realScore(sf)
        )
    }

    func testResolvePrioritySampleBeatsBundled() {
        // 示例曲 book="示例" 永不打中内置谱；即便误传拜厄坐标，示例标记仍优先
        XCTAssertEqual(
            ScoreAvailability.resolve(scoreFile: nil, isSampleEntry: true, bundledBook: "拜厄", bundledNumber: 1),
            .samplePiece
        )
        XCTAssertEqual(
            ScoreAvailability.resolve(scoreFile: nil, isSampleEntry: true, bundledBook: "示例", bundledNumber: 0),
            .samplePiece
        )
    }

    func testResolveUnavailableFor599AndOutOfRange() {
        // 车尔尼599：无内置谱 → 不可用（不判分，保持原行为）
        XCTAssertEqual(
            ScoreAvailability.resolve(scoreFile: nil, isSampleEntry: false, bundledBook: "车尔尼599", bundledNumber: 1),
            .unavailable
        )
        XCTAssertEqual(
            ScoreAvailability.resolve(scoreFile: nil, isSampleEntry: false, bundledBook: "拜厄", bundledNumber: 107),
            .unavailable
        )
        // 不传 bundledBook（导入曲路径）→ 仍不可用
        XCTAssertEqual(ScoreAvailability.resolve(scoreFile: nil, isSampleEntry: false), .unavailable)
    }

    /// 既有三态断言不受新默认参数影响
    func testResolveExistingThreeStatesStillHold() {
        let sf = ScoreFile(kind: "musicxml", fileURL: "scores/a.musicxml", title: "A", canFollow: true)
        XCTAssertEqual(ScoreAvailability.resolve(scoreFile: sf, isSampleEntry: false), .realScore(sf))
        XCTAssertEqual(ScoreAvailability.resolve(scoreFile: nil, isSampleEntry: true), .samplePiece)
        XCTAssertEqual(ScoreAvailability.resolve(scoreFile: nil, isSampleEntry: false), .unavailable)
        XCTAssertEqual(ScoreAvailability.resolve(scoreFile: sf, isSampleEntry: true), .realScore(sf))
    }

    // MARK: C 参考谱 URL 决策（纯 helper；注入 resolver，不依赖宿主资源）

    private func docsURL(_ relativePath: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(relativePath)
    }

    func testReferenceScoreURLPrefersScoreFileThenBundledThenNil() throws {
        // 真实文件落 Documents（SandboxPaths 只解析存在的相对路径）
        let rel = "scores/\(UUID().uuidString).musicxml"
        let url = docsURL(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("<x/>".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let sf = ScoreFile(kind: "musicxml", fileURL: rel, title: "T", canFollow: true)

        // (a) 有 scoreFile → 它的 URL 赢（即便同时给了内置谱坐标）
        XCTAssertEqual(
            ScoringOrchestrator.referenceScoreURL(scoreFile: sf, bundledBook: "拜厄", bundledNumber: 1), url
        )
        // (b) 无 scoreFile + 内置谱坐标 → 解析内置谱（注入假 resolver，验分支不验资源）
        XCTAssertEqual(
            ScoringOrchestrator.referenceScoreURL(
                scoreFile: nil, bundledBook: "拜厄", bundledNumber: 7,
                bundledResolver: { book, number in URL(fileURLWithPath: "/tmp/\(book)-\(number).musicxml") }
            ),
            URL(fileURLWithPath: "/tmp/拜厄-7.musicxml")
        )
        // (c) 都没有 → nil（自由弹奏 / 599 / 越界：无参考谱，统计级）
        XCTAssertNil(ScoringOrchestrator.referenceScoreURL(
            scoreFile: nil, bundledBook: nil, bundledNumber: 0,
            bundledResolver: { _, _ in URL(fileURLWithPath: "/tmp/should-not-be-used") }
        ))
        XCTAssertNil(ScoringOrchestrator.referenceScoreURL(
            scoreFile: nil, bundledBook: "车尔尼599", bundledNumber: 3,
            bundledResolver: { _, _ in URL(fileURLWithPath: "/tmp/should-not-be-used") }
        ))
        XCTAssertNil(ScoringOrchestrator.referenceScoreURL(
            scoreFile: nil, bundledBook: "拜厄", bundledNumber: 107,
            bundledResolver: { _, _ in URL(fileURLWithPath: "/tmp/should-not-be-used") }
        ))
        XCTAssertNil(ScoringOrchestrator.referenceScoreURL(
            scoreFile: nil, bundledBook: "示例", bundledNumber: 0,
            bundledResolver: { _, _ in URL(fileURLWithPath: "/tmp/should-not-be-used") }
        ))
    }

    func testReferenceScoreURLDoesNotFallBackWhenScoreFileMissingOnDisk() {
        // scoreFile 在但沙盒文件丢了 → nil，不拿另一份谱冒充评分（§10）
        let sf = ScoreFile(kind: "musicxml", fileURL: "scores/gone-\(UUID().uuidString).musicxml",
                           title: "T", canFollow: true)
        XCTAssertNil(ScoringOrchestrator.referenceScoreURL(
            scoreFile: sf, bundledBook: "拜厄", bundledNumber: 1,
            bundledResolver: { _, _ in URL(fileURLWithPath: "/tmp/beyer") }
        ))
    }

    /// 默认 resolver 即 Bundle 查找：资源真在宿主里时应非 nil（不在也不影响上面的决策断言）
    func testDefaultBundledResolverUsesBundleLookup() {
        let resolved = ScoringOrchestrator.referenceScoreURL(
            scoreFile: nil, bundledBook: "拜厄", bundledNumber: 1
        )
        XCTAssertEqual(resolved, BundledScore.url(book: "拜厄", number: 1))
        if let resolved {
            XCTAssertEqual(resolved.lastPathComponent, "beyer_01.musicxml")
        }
    }

    // MARK: D 内置谱真能解析（验收：进练习室渲染谱，不是报错）

    private func locateBundled(_ book: String, _ number: Int) throws -> URL? {
        guard let name = BundledScore.resourceName(book: book, number: number) else { return nil }
        // 测试宿主是 app，Bundle.main 即 app bundle
        return Bundle.main.url(forResource: name, withExtension: "musicxml")
    }

    func testBundledScoresParseThroughScoreLoader() throws {
        // 首/尾各取一条：解析失败 = 进练习室会报「谱面解析失败」
        for (book, number) in [("拜厄", 1), ("拜厄", 2), ("拜厄", 106), ("哈农", 1), ("哈农", 20)] {
            let name = try XCTUnwrap(BundledScore.resourceName(book: book, number: number))
            guard let url = try locateBundled(book, number) else {
                XCTFail("宿主 app bundle 缺少 \(name).musicxml（app target sources 应随包分发）")
                continue
            }
            let score = try ScoreLoader.loadScore(contentsOf: url)
            XCTAssertGreaterThan(ScoreExpectedPitches.measureCount(score: score), 0, "\(name) 应至少有 1 小节")
            XCTAssertFalse(ScoreExpectedPitches.extract(score: score).isEmpty, "\(name) 应能提出跟弹参考音")
        }
    }

    /// 评分侧同一份谱也要能提出参考音（ScoringOrchestrator 走的提取器）
    func testBundledScoreYieldsReferenceNotes() throws {
        guard let url = try locateBundled("拜厄", 1) else {
            throw XCTSkip("宿主 app bundle 未打包 beyer_01.musicxml")
        }
        let score = try ScoreLoader.loadScore(contentsOf: url)
        let extracted = ScoreReferenceNotes.extract(score: score, measureRange: nil)
        XCTAssertFalse(extracted.notes.isEmpty, "内置谱应能提出参考音（否则只能统计级，不可判分）")
    }
}

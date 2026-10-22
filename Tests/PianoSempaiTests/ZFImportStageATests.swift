import SwiftData
import XCTest
@testable import PianoSempai

// V7 Stage A 验收（ADR-0012）：Zf 月度录像导入的「规划 + 落盘 + 落库 + 保留」核心层。
// 全程假相册元数据 / 临时文件：不碰真实 PhotoKit、不请求权限、不联网。

private func makeZFContainer() throws -> ModelContainer {
    try ModelContainer(
        for: AppSettings.self, Take.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zf-import-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@discardableResult
private func writeSourceVideo(in directory: URL, bytes: Int = 256) throws -> URL {
    let url = directory.appendingPathComponent("source-\(UUID().uuidString).mov")
    try Data(repeating: 0x5A, count: bytes).write(to: url)
    return url
}

private func localDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

private func metadata(identifier: String,
                      creationDate: Date? = Date(timeIntervalSince1970: 1_790_000_000),
                      durationSec: Double = 252,
                      pixelWidth: Int = 1920,
                      pixelHeight: Int = 1080) -> ZFAssetMetadata {
    ZFAssetMetadata(
        assetIdentifier: identifier,
        creationDate: creationDate,
        durationSec: durationSec,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight
    )
}

private func candidate(identifier: String,
                       creationDate: Date? = Date(timeIntervalSince1970: 1_790_000_000),
                       byteSize: Int64 = 1024) -> ZFImportCandidate {
    ZFImportCandidate(
        id: identifier,
        metadata: metadata(identifier: identifier, creationDate: creationDate),
        byteSize: byteSize
    )
}

// MARK: - ① 归月与预检（纯函数）

final class ZFImportPlannerTests: XCTestCase {

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    func testMonthKeyUsesYearMonthAndNilDateIsNil() {
        let calendar = utcCalendar
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 12))!
        XCTAssertEqual(ZFImportPlanner.monthKey(for: date, calendar: calendar), "2026-09")
        XCTAssertEqual(ZFImportPlanner.monthKey(for: Date(timeIntervalSince1970: 0), calendar: calendar),
                       "1970-01")
        XCTAssertNil(ZFImportPlanner.monthKey(for: nil, calendar: calendar), "不猜日期：nil 归月必须 nil")
    }

    func testMissingCreationDateIsBlocked() {
        let item = candidate(identifier: "no-date", creationDate: nil)
        let reasons = ZFImportPlanner.blockReasons(
            candidates: [item],
            existingAssetIdentifiers: [],
            availableBytes: .max
        )
        XCTAssertEqual(reasons["no-date"], .missingCreationDate)
    }

    func testTooLargeBlocksAboveTwoGigabytesButBoundaryPasses() {
        let tooLarge = candidate(identifier: "big", byteSize: ZFImportPlanner.maxFileBytes + 1)
        let boundary = candidate(identifier: "edge", byteSize: ZFImportPlanner.maxFileBytes)
        let reasons = ZFImportPlanner.blockReasons(
            candidates: [tooLarge, boundary],
            existingAssetIdentifiers: [],
            availableBytes: .max
        )
        XCTAssertEqual(reasons["big"], .tooLarge(bytes: ZFImportPlanner.maxFileBytes + 1))
        XCTAssertNil(reasons["edge"], "恰好 2 GB 允许导入")
    }

    func testAlreadyImportedIsBlocked() {
        let item = candidate(identifier: "done")
        let reasons = ZFImportPlanner.blockReasons(
            candidates: [item],
            existingAssetIdentifiers: ["done"],
            availableBytes: .max
        )
        XCTAssertEqual(reasons["done"], .alreadyImported)
    }

    func testInsufficientSpaceAggregatesSelectedBytes() {
        let first = candidate(identifier: "a", byteSize: 200)
        let second = candidate(identifier: "b", byteSize: 100)
        let reasons = ZFImportPlanner.blockReasons(
            candidates: [first, second],
            existingAssetIdentifiers: [],
            availableBytes: 150
        )
        XCTAssertEqual(reasons["a"], .insufficientSpace(needed: 300, available: 150))
        XCTAssertEqual(reasons["b"], .insufficientSpace(needed: 300, available: 150))
    }

    func testInsufficientSpaceIgnoresCandidatesWithOtherBlocks() {
        let missingDate = candidate(identifier: "no-date", creationDate: nil, byteSize: 900)
        let fine = candidate(identifier: "fine", byteSize: 100)
        let reasons = ZFImportPlanner.blockReasons(
            candidates: [missingDate, fine],
            existingAssetIdentifiers: [],
            availableBytes: 500
        )
        XCTAssertEqual(reasons["no-date"], .missingCreationDate, "先有原因者保持原原因")
        XCTAssertNil(reasons["fine"], "无日期候选的字节不计入所需空间")
    }

    func testTotalBytesSumsOnlyProvidedCandidates() {
        let selected = [candidate(identifier: "a", byteSize: 10),
                        candidate(identifier: "b", byteSize: 32)]
        XCTAssertEqual(ZFImportPlanner.totalBytes(selected), 42)
        XCTAssertEqual(ZFImportPlanner.totalBytes([]), 0)
    }
}

// MARK: - ② 归档路径

final class ZFImportDestinationTests: XCTestCase {

    func testDestinationUsesZFFolderYearMonthAndShortHash() throws {
        let date = localDate(year: 2026, month: 9, day: 14)
        let url = try VideoStore.zfDestinationURL(assetIdentifier: "asset-A", creationDate: date)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let relative = try XCTUnwrap(VideoStore.relativePath(for: url))
        let parts = relative.split(separator: "/")
        XCTAssertEqual(parts.count, 5, "videos/zf/yyyy/MM/<hash>.mov")
        XCTAssertEqual(String(parts[0]), "videos")
        XCTAssertEqual(String(parts[1]), "zf")
        XCTAssertEqual(String(parts[2]), "2026")
        XCTAssertEqual(String(parts[3]), "09")

        let filename = String(parts[4])
        XCTAssertTrue(filename.hasSuffix(".mov"))
        let hash = String(filename.dropLast(4))
        XCTAssertEqual(hash.count, 16, "短哈希固定 16 位")
        XCTAssertTrue(hash.allSatisfy(\.isHexDigit))
    }

    func testDestinationIsDeterministicAndDistinctPerIdentifier() throws {
        let date = localDate(year: 2026, month: 9, day: 14)
        let first = try VideoStore.zfDestinationURL(assetIdentifier: "asset-A", creationDate: date)
        let second = try VideoStore.zfDestinationURL(assetIdentifier: "asset-A", creationDate: date)
        let other = try VideoStore.zfDestinationURL(assetIdentifier: "asset-B", creationDate: date)
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
        }

        XCTAssertEqual(first.standardizedFileURL, second.standardizedFileURL, "同一资产恒同一路径")
        XCTAssertNotEqual(first.lastPathComponent, other.lastPathComponent, "不同资产不同文件")
    }
}

// MARK: - ③ 导入落盘落库 + 回滚

@MainActor
final class ZFImportServiceTests: XCTestCase {

    func testImportWritesTakeFieldsAndFileAndRemovesTemp() async throws {
        let context = ModelContext(try makeZFContainer())
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pieceId = UUID()
        let date = localDate(year: 2026, month: 9, day: 14)
        let item = candidate(identifier: "asset-success", creationDate: date, byteSize: 256)
        let source = try writeSourceVideo(in: tempDirectory, bytes: 256)

        let takes = try await ZFImportService.importCandidates(
            [item],
            pieceId: pieceId,
            sourceURLs: [item.id: source],
            in: context,
            isCancelled: { false },
            progress: nil
        )

        let take = try XCTUnwrap(takes.first)
        XCTAssertEqual(takes.count, 1)
        XCTAssertEqual(take.taskType, "zfImport")
        XCTAssertFalse(take.hasMidi)
        XCTAssertFalse(take.isFreePlay)
        XCTAssertFalse(take.isPassEligible)
        XCTAssertFalse(take.isRecordingSession)
        XCTAssertEqual(take.sourceAssetIdentifier, "asset-success")
        XCTAssertEqual(take.pieceId, pieceId)
        XCTAssertEqual(take.videoDurationSec, 252)
        XCTAssertEqual(take.durationSec, 252)
        XCTAssertEqual(take.title, "9/14 Zf 录像")
        XCTAssertNil(take.endedAt)
        XCTAssertEqual(take.startedAt.timeIntervalSince1970,
                       date.timeIntervalSince1970, accuracy: 0.001)

        let relativePath = try XCTUnwrap(take.videoFileURL)
        XCTAssertTrue(relativePath.hasPrefix("videos/zf/"), "Zf 归档与普通录像目录分开")
        let destination = try XCTUnwrap(VideoStore.absoluteURL(for: relativePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path), "归档文件已落盘")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path), "校验通过后临时文件删除")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Take>()).count, 1)

        try? FileManager.default.removeItem(at: destination)
    }

    func testImportWithNilPieceIsAllowed() async throws {
        let context = ModelContext(try makeZFContainer())
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let item = candidate(identifier: "asset-no-piece", creationDate: localDate(year: 2026, month: 9, day: 1))
        let source = try writeSourceVideo(in: tempDirectory)

        let takes = try await ZFImportService.importCandidates(
            [item],
            pieceId: nil,
            sourceURLs: [item.id: source],
            in: context,
            isCancelled: { false },
            progress: nil
        )

        let take = try XCTUnwrap(takes.first)
        XCTAssertNil(take.pieceId, "可跳过曲目：纯表演存档")
        if let path = take.videoFileURL, let url = VideoStore.absoluteURL(for: path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testCopyFailureRollsBackEarlierFilesAndTakes() async throws {
        let context = ModelContext(try makeZFContainer())
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let date = localDate(year: 2026, month: 9, day: 14)
        let first = candidate(identifier: "asset-ok", creationDate: date)
        let broken = candidate(identifier: "asset-broken", creationDate: date)
        let firstSource = try writeSourceVideo(in: tempDirectory)
        let missingSource = tempDirectory.appendingPathComponent("does-not-exist.mov")

        let firstDestination = try VideoStore.zfDestinationURL(
            assetIdentifier: first.id, creationDate: date
        )
        let brokenDestination = try VideoStore.zfDestinationURL(
            assetIdentifier: broken.id, creationDate: date
        )
        defer {
            try? FileManager.default.removeItem(at: firstDestination.deletingLastPathComponent())
        }

        do {
            _ = try await ZFImportService.importCandidates(
                [first, broken],
                pieceId: nil,
                sourceURLs: [first.id: firstSource, broken.id: missingSource],
                in: context,
                isCancelled: { false },
                progress: nil
            )
            XCTFail("第二条复制失败必须抛错")
        } catch {
            // 预期的复制失败（NSCocoaErrorDomain）
        }

        XCTAssertEqual(try context.fetch(FetchDescriptor<Take>()).count, 0, "回滚后不留 Take 行")
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstDestination.path),
                       "回滚后不留已复制文件")
        XCTAssertFalse(FileManager.default.fileExists(atPath: brokenDestination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstSource.path),
                       "第一条的临时文件已清理")
    }

    func testDuplicateImportIsNoOp() async throws {
        let context = ModelContext(try makeZFContainer())
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let item = candidate(identifier: "asset-dup", creationDate: localDate(year: 2026, month: 9, day: 7))
        let firstSource = try writeSourceVideo(in: tempDirectory)

        let firstBatch = try await ZFImportService.importCandidates(
            [item],
            pieceId: nil,
            sourceURLs: [item.id: firstSource],
            in: context,
            isCancelled: { false },
            progress: nil
        )
        XCTAssertEqual(firstBatch.count, 1)

        let secondSource = try writeSourceVideo(in: tempDirectory)
        let secondBatch = try await ZFImportService.importCandidates(
            [item],
            pieceId: nil,
            sourceURLs: [item.id: secondSource],
            in: context,
            isCancelled: { false },
            progress: nil
        )

        XCTAssertTrue(secondBatch.isEmpty, "已导入的资产不建第二条 Take")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Take>()).count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondSource.path),
                      "被跳过的候选不删除临时文件（由调用方处置）")

        if let path = firstBatch.first?.videoFileURL, let url = VideoStore.absoluteURL(for: path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testCancellationBeforeFirstItemThrowsAndWritesNothing() async throws {
        let context = ModelContext(try makeZFContainer())
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let date = localDate(year: 2026, month: 9, day: 21)
        let item = candidate(identifier: "asset-cancel", creationDate: date)
        let source = try writeSourceVideo(in: tempDirectory)
        let destination = try VideoStore.zfDestinationURL(
            assetIdentifier: item.id, creationDate: date
        )
        defer {
            try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
        }

        do {
            _ = try await ZFImportService.importCandidates(
                [item],
                pieceId: nil,
                sourceURLs: [item.id: source],
                in: context,
                isCancelled: { true },
                progress: nil
            )
            XCTFail("取消必须抛 .cancelled")
        } catch let error as PhotoLibraryError {
            XCTAssertEqual(error, .cancelled)
        }

        XCTAssertEqual(try context.fetch(FetchDescriptor<Take>()).count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path),
                      "取消发生在复制前，临时文件保留给调用方清理")
    }

    func testProgressReportsCompletedAndTotal() async throws {
        let context = ModelContext(try makeZFContainer())
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let date = localDate(year: 2026, month: 9, day: 1)
        let items = [candidate(identifier: "p1", creationDate: date),
                     candidate(identifier: "p2", creationDate: date)]
        var sources: [String: URL] = [:]
        for item in items {
            sources[item.id] = try writeSourceVideo(in: tempDirectory)
        }
        var updates: [(Int, Int)] = []

        let takes = try await ZFImportService.importCandidates(
            items,
            pieceId: nil,
            sourceURLs: sources,
            in: context,
            isCancelled: { false },
            progress: { completed, total in updates.append((completed, total)) }
        )

        XCTAssertEqual(takes.count, 2)
        XCTAssertEqual(updates.map(\.0), [1, 2])
        XCTAssertEqual(updates.map(\.1), [2, 2])

        for take in takes {
            if let path = take.videoFileURL, let url = VideoStore.absoluteURL(for: path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

// MARK: - ④ 保留规则：Zf 永久

@MainActor
final class ZFRetentionTests: XCTestCase {

    func testZFImportTakeSurvivesRetentionWhileOldNormalTakesAreEvicted() throws {
        let context = ModelContext(try makeZFContainer())
        let pieceId = UUID()
        let base = Date(timeIntervalSince1970: 1_790_000_000)

        let zfTake = Take(
            startedAt: base,
            taskType: "zfImport",
            pieceId: pieceId,
            videoFileURL: "videos/zf/2026/09/0000000000000001.mov"
        )
        context.insert(zfTake)

        var normalTakes: [Take] = []
        for index in 0..<10 {
            let take = Take(
                startedAt: base.addingTimeInterval(TimeInterval(3600 * (index + 1))),
                taskType: "main",
                pieceId: pieceId,
                videoFileURL: "videos/2026/09/video-\(index).mov"
            )
            context.insert(take)
            normalTakes.append(take)
        }
        try context.save()

        try VideoAttachmentStore.enforceRetention(pieceId: pieceId, in: context)

        XCTAssertEqual(zfTake.videoFileURL, "videos/zf/2026/09/0000000000000001.mov",
                       "Zf 月度录像永不清理")
        let survivingNormals = normalTakes.filter { $0.videoFileURL != nil }
        XCTAssertEqual(survivingNormals.count, 8, "普通 take 仍按每曲 8 条保留")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Take>()).count, 11,
                       "淘汰只清视频字段，不删 Take 行")
        XCTAssertNil(normalTakes[0].videoFileURL, "最旧的两条普通 take 出局")
        XCTAssertNil(normalTakes[1].videoFileURL)
    }
}

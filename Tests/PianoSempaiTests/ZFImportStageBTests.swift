import SwiftData
import UIKit
import XCTest
@testable import PianoSempai

// V7 Stage B 验收（ADR-0012 / S17）：候选聚合与选择、预检、导入进度/取消、档案入口。
// 全程假相册 / 假导入服务：不请求真实权限、不碰 PhotoKit、不联网、不写真实视频。

private func makeS17Container() throws -> ModelContainer {
    try ModelContainer(
        for: Take.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

private func s17Date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

private func s17Metadata(identifier: String,
                         creationDate: Date?,
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

private func s17Candidate(identifier: String,
                          date: Date?,
                          bytes: Int64) -> ZFImportCandidate {
    ZFImportCandidate(
        id: identifier,
        metadata: s17Metadata(identifier: identifier, creationDate: date),
        byteSize: bytes
    )
}

// MARK: - 假依赖

private final class FakePhotoLibrary: PhotoLibraryAccessing {
    var access: PhotoLibraryAccess
    var metadataById: [String: ZFAssetMetadata]
    var recent: [ZFAssetMetadata]
    var exportError: PhotoLibraryError?

    init(access: PhotoLibraryAccess = .full,
         metadataById: [String: ZFAssetMetadata] = [:],
         recent: [ZFAssetMetadata] = []) {
        self.access = access
        self.metadataById = metadataById
        self.recent = recent
    }

    func requestReadAccess() async -> Bool { access != .denied }

    func accessLevel() -> PhotoLibraryAccess { access }

    func metadata(forIdentifiers ids: [String]) async -> [String: ZFAssetMetadata] {
        metadataById.filter { ids.contains($0.key) }
    }

    func recentVideos(limit: Int) async -> [ZFAssetMetadata] {
        Array(recent.prefix(limit))
    }

    func thumbnail(forIdentifier id: String, maxPixelSize: CGFloat) async -> UIImage? { nil }

    func exportOriginal(identifier: String,
                        to directory: URL,
                        progress: (@Sendable (Double) -> Void)?) async throws -> URL {
        if let exportError { throw exportError }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(identifier).mov")
        try Data(repeating: 0x5A, count: 64).write(to: url)
        progress?(1.0)
        return url
    }
}

/// 一直等到取消旗标被置位才抛 .cancelled（验证取消路径真的传到 Stage A）
@MainActor
private final class FakeRunner: S17ImportRunning {
    private(set) var didObserveCancellation = false

    func importCandidates(_ candidates: [ZFImportCandidate],
                          pieceId: UUID?,
                          sourceURLs: [String: URL],
                          in context: ModelContext,
                          isCancelled: @escaping () -> Bool,
                          progress: (@MainActor (Int, Int) -> Void)?) async throws -> [Take] {
        while !isCancelled() {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        didObserveCancellation = true
        throw PhotoLibraryError.cancelled
    }
}

// MARK: - ① 月份聚合 / 汇总文案 / 进度文案（纯函数）

final class S17FormattingTests: XCTestCase {

    func testDominantMonthPickedByLargestSelectedBytes() {
        let sep1 = s17Candidate(identifier: "sep-1", date: s17Date(2026, 9, 1), bytes: 600)
        let sep2 = s17Candidate(identifier: "sep-2", date: s17Date(2026, 9, 7), bytes: 300)
        let oct = s17Candidate(identifier: "oct-1", date: s17Date(2026, 10, 2), bytes: 1_200)

        XCTAssertEqual(
            S17MonthGrouping.dominantMonthKey(candidates: [sep1, sep2, oct], selectedIds: []),
            "2026-10",
            "字节最多的月份为主导月"
        )
        XCTAssertEqual(
            S17MonthGrouping.dominantMonthKey(
                candidates: [sep1, sep2, oct],
                selectedIds: [sep1.id, sep2.id]
            ),
            "2026-09",
            "有勾选时只按勾选聚合（未选中的 10 月不参与）"
        )

        let summaries = S17MonthGrouping.summaries(candidates: [sep1, sep2, oct], selectedIds: [])
        XCTAssertEqual(summaries.map(\.monthKey), ["2026-10", "2026-09"])
        XCTAssertEqual(summaries.first?.candidateCount, 1)
        XCTAssertEqual(summaries.first?.totalBytes, 1_200)
    }

    func testMonthSectionsAreCappedAtThree() {
        let candidates = [
            s17Candidate(identifier: "m1", date: s17Date(2026, 7, 1), bytes: 100),
            s17Candidate(identifier: "m2", date: s17Date(2026, 8, 1), bytes: 200),
            s17Candidate(identifier: "m3", date: s17Date(2026, 9, 1), bytes: 300),
            s17Candidate(identifier: "m4", date: s17Date(2026, 10, 1), bytes: 400)
        ]
        let summaries = S17MonthGrouping.summaries(candidates: candidates, selectedIds: [])
        XCTAssertEqual(summaries.count, 3, "最多 3 个月卡")
        XCTAssertEqual(summaries.map(\.monthKey), ["2026-10", "2026-09", "2026-08"])
    }

    func testSelectionSummaryFormatting() {
        XCTAssertEqual(
            S17Formatting.selectionSummary(
                count: 3,
                totalDurationSec: 12 * 60 + 40,
                totalBytes: 1_800_000_000
            ),
            "已选 3 段 · 共 12分40秒 · 约 1.8 GB"
        )
        XCTAssertEqual(S17Formatting.byteSize(24_000_000_000), "24 GB", "整 GB 不补 .0")
        XCTAssertEqual(S17Formatting.byteSize(580_000_000), "580 MB")
        XCTAssertEqual(S17Formatting.monthTitle("2026-09"), "2026 年 9 月")
    }

    func testImportProgressText() {
        XCTAssertEqual(
            S17Formatting.importProgress(completed: 2, total: 3),
            "正在导入 2/3"
        )
        XCTAssertEqual(
            S17Formatting.importProgress(completed: 0, total: 3),
            "正在导入 0/3"
        )
    }
}

// MARK: - ② 勾选 / 预检（纯状态）

final class S17SelectionTests: XCTestCase {

    func testToggleUpdatesSelectionAndCTACount() {
        var selection = S17ImportSelection()
        XCTAssertFalse(selection.isImportEnabled(reasons: [:]))

        selection.toggle("a", reasons: [:])
        XCTAssertTrue(selection.contains("a"))
        XCTAssertEqual(selection.count, 1)
        XCTAssertEqual(S17Formatting.importCTA(count: selection.count), "导入所选 1 段")
        XCTAssertTrue(selection.isImportEnabled(reasons: [:]))

        selection.toggle("a", reasons: [:])
        XCTAssertFalse(selection.contains("a"))
        XCTAssertEqual(selection.count, 0)
        XCTAssertEqual(S17Formatting.importCTA(count: 0), "导入所选 0 段")
    }

    func testBlockedCandidateCannotBeSelectedAndReasonSurfaces() {
        var selection = S17ImportSelection()
        let reasons: [String: ZFImportBlockReason] = [
            "imported": .alreadyImported,
            "big": .tooLarge(bytes: ZFImportPlanner.maxFileBytes + 1),
            "no-date": .missingCreationDate,
            "no-space": .insufficientSpace(needed: 3_000, available: 1_000)
        ]

        selection.toggle("imported", reasons: reasons)
        selection.toggle("big", reasons: reasons)
        selection.toggle("no-date", reasons: reasons)
        XCTAssertEqual(selection.count, 0, "阻塞项一律选不中")

        XCTAssertEqual(S17Formatting.blockReasonText(.alreadyImported), "已导入")
        XCTAssertEqual(S17Formatting.blockReasonText(.tooLarge(bytes: 0)), "超过 2 GB")
        XCTAssertEqual(S17Formatting.blockReasonText(.missingCreationDate), "读不到拍摄日期")
        XCTAssertEqual(S17Formatting.blockReasonText(.insufficientSpace(needed: 1, available: 0)), "剩余空间不足")
        XCTAssertTrue(
            S17Formatting.blockDetailText(.insufficientSpace(needed: 3_000_000_000, available: 1_000_000_000))
                .contains("需要 3 GB")
        )
    }

    func testCTAEnabledOnlyWhenNonEmptyAndUnblocked() {
        XCTAssertFalse(S17ImportSelection().isImportEnabled(reasons: [:]), "0 选中不可导入")

        let allClear = S17ImportSelection(selected: ["a", "b"])
        XCTAssertTrue(allClear.isImportEnabled(reasons: [:]))

        let mixed = S17ImportSelection(selected: ["a", "b"])
        XCTAssertFalse(
            mixed.isImportEnabled(reasons: ["b": .insufficientSpace(needed: 10, available: 5)]),
            "任一选中项阻塞即不可导入"
        )
    }

    func testLimitedPermissionMapsToPickerFallback() {
        let limited = S17LibraryMode.from(FakePhotoLibrary(access: .limited).accessLevel())
        XCTAssertEqual(limited, .limited)
        XCTAssertTrue(limited.showsPicker, "limited 走 PhotosPicker，不伪造候选列表")
        XCTAssertFalse(limited.showsRecentList)

        let full = S17LibraryMode.from(FakePhotoLibrary(access: .full).accessLevel())
        XCTAssertTrue(full.showsRecentList)
        XCTAssertFalse(full.showsPicker)

        let denied = S17LibraryMode.from(FakePhotoLibrary(access: .denied).accessLevel())
        XCTAssertTrue(denied.showsSettingsButton)
        XCTAssertFalse(denied.showsPicker)
    }
}

// MARK: - ③ 导入取消（假服务）

@MainActor
final class S17ImportFlowTests: XCTestCase {

    func testCancelReturnsToIdleAndSignalsRunner() async throws {
        let context = ModelContext(try makeS17Container())
        let runner = FakeRunner()
        let model = S17ImportModel(library: FakePhotoLibrary(), runner: runner)
        let item = s17Candidate(identifier: "asset-cancel", date: s17Date(2026, 9, 14), bytes: 10)

        let task = Task {
            await model.importCandidates(
                [item],
                sourceURLs: [item.id: URL(fileURLWithPath: "/tmp/s17-cancel.mov")],
                pieceId: nil,
                in: context
            )
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(model.phase, .importing(completed: 0, total: 1))

        model.cancelImport()
        let result = await task.value

        XCTAssertNil(result, "取消不返回成功条数")
        XCTAssertEqual(model.phase, .idle, "取消后回到 idle")
        XCTAssertEqual(model.notice, "已取消，未导入任何视频")
        XCTAssertTrue(runner.didObserveCancellation, "取消旗标传到了导入服务（Stage A 回滚）")
    }
}

// MARK: - ④ 档案入口与 Zf 行

final class ArchiveZFEntryTests: XCTestCase {

    func testEntryAlwaysVisibleAndZfTakeRowTitle() {
        XCTAssertTrue(ArchiveZFEntry.shouldShowEntry(takes: []), "没有 take 时入口也必须可见")

        let zfTake = Take(
            taskType: "zfImport",
            isPassEligible: false,
            title: "9/14 Zf 录像",
            videoFileURL: "videos/zf/2026/09/0123456789abcdef.mov"
        )
        XCTAssertEqual(ArchiveZFEntry.rowTitle(for: zfTake), "9/14 Zf 录像")
        XCTAssertTrue(VideoUIFormatting.hasVideo(zfTake), "有录像 → 时间线行显示 video badge")

        let untitled = Take(taskType: "zfImport")
        XCTAssertEqual(ArchiveZFEntry.rowTitle(for: untitled), "Zf 录像")

        let normal = Take(taskType: "main")
        XCTAssertNil(ArchiveZFEntry.rowTitle(for: normal), "普通 take 走原有标题逻辑")
    }
}

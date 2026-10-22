import SwiftData
import XCTest
@testable import PianoSempai

// M8b Stage A 核心层验收：视频文件布局 / 模型默认值 / 保留规则 / 附件挂载。
// 相机与相册不参与单测：AVFoundationVideoRecorder 与 PhotoLibraryWriter 需真机与系统授权。
// 测试只碰 Documents/videos（单测串行执行），不触碰相机、麦克风、相册。

private func makeVideoContainer() throws -> ModelContainer {
    try ModelContainer(
        for: AppSettings.self, Take.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

private func documentsDirectory() -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
}

private func videosDirectory() -> URL {
    documentsDirectory().appendingPathComponent("videos", isDirectory: true)
}

/// 在 Documents/videos/yyyy/MM/ 下造一个真实文件（调用方负责删除）
@discardableResult
private func writeDummyVideo(bytes: Int = 32) throws -> URL {
    let url = try VideoStore.makeFileURL()
    try Data(count: bytes).write(to: url)
    return url
}

// MARK: - ① 文件布局

final class VideoStoreFileTests: XCTestCase {

    func testMakeFileURLUsesVideosYearMonthAndCreatesDirectory() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let url = try VideoStore.makeFileURL(now: date)
        defer { try? FileManager.default.removeItem(at: url) }

        let calendar = Calendar.current
        let relative = try XCTUnwrap(VideoStore.relativePath(for: url))
        let parts = relative.split(separator: "/")
        XCTAssertEqual(parts.count, 4, "videos/yyyy/MM/video-<uuid>.mov")
        XCTAssertEqual(String(parts[0]), "videos")
        XCTAssertEqual(String(parts[1]), String(calendar.component(.year, from: date)))
        XCTAssertEqual(String(parts[2]), String(calendar.component(.month, from: date)))
        XCTAssertTrue(parts[3].hasPrefix("video-"))
        XCTAssertTrue(parts[3].hasSuffix(".mov"))

        var isDirectory: ObjCBool = false
        let parent = url.deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue, "makeFileURL 必须创建 yyyy/MM 目录")
    }

    func testRelativePathAndAbsoluteURLRoundTrip() throws {
        let url = try writeDummyVideo()
        defer { try? FileManager.default.removeItem(at: url) }

        let relative = try XCTUnwrap(VideoStore.relativePath(for: url))
        let restored = try XCTUnwrap(VideoStore.absoluteURL(for: relative))
        XCTAssertEqual(restored.standardizedFileURL.path, url.standardizedFileURL.path)
    }

    func testAbsoluteURLRejectsTraversalAndAbsolutePaths() {
        XCTAssertNil(VideoStore.absoluteURL(for: "videos/../../etc/passwd"), ".. 穿越必须拒绝")
        XCTAssertNil(VideoStore.absoluteURL(for: "../Documents"))
        XCTAssertNil(VideoStore.absoluteURL(for: "/etc/passwd"), "绝对路径必须拒绝")
        XCTAssertNil(VideoStore.absoluteURL(for: ""))
        XCTAssertNil(VideoStore.relativePath(for: URL(fileURLWithPath: "/etc/passwd")),
                     "Documents 外的 URL 没有相对路径")
    }

    func testDeleteMissingFileDoesNotThrow() {
        XCTAssertNoThrow(try VideoStore.delete(relativePath: "videos/1999/01/video-missing.mov"))
        XCTAssertNoThrow(try VideoStore.delete(relativePath: "../escape.mov"), "非法路径静默忽略")
    }

    func testDeleteRemovesExistingFile() throws {
        let url = try writeDummyVideo()
        let relative = try XCTUnwrap(VideoStore.relativePath(for: url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        try VideoStore.delete(relativePath: relative)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testTotalBytesSumsNestedFilesAndIsZeroWhenDirectoryAbsent() throws {
        let fm = FileManager.default
        // 测试独占 Documents/videos
        try? fm.removeItem(at: videosDirectory())
        XCTAssertEqual(VideoStore.totalBytes(), 0, "目录不存在 = 0")

        let file = try writeDummyVideo(bytes: 100)
        let nestedDirectory = videosDirectory().appendingPathComponent("nested", isDirectory: true)
        try fm.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        let nested = nestedDirectory.appendingPathComponent("extra.mov")
        try Data(count: 50).write(to: nested)
        defer {
            try? fm.removeItem(at: file)
            try? fm.removeItem(at: nested)
            try? fm.removeItem(at: nestedDirectory)
        }

        XCTAssertEqual(VideoStore.totalBytes(), 150, "递归累加所有视频字节")
    }
}

// MARK: - ② 模型默认值

final class VideoModelDefaultTests: XCTestCase {

    func testNewTakeHasNoVideoAttachment() {
        let take = Take()
        XCTAssertNil(take.videoFileURL)
        XCTAssertEqual(take.videoDurationSec, 0)
        XCTAssertEqual(take.videoStartedAtOffset, 0)
    }

    func testAppSettingsDefaultsToLRU8() {
        XCTAssertEqual(AppSettings().videoRetentionMode, "lru8")
    }
}

// MARK: - ③ 挂载与保留规则

final class VideoAttachmentStoreTests: XCTestCase {

    /// 造一条已落库的 take，并挂上真实视频文件
    @MainActor
    private func insertTake(in context: ModelContext, startedAt: Date, pieceId: UUID?,
                            midiFileURL: String = "") throws -> (take: Take, fileURL: URL) {
        let take = Take(startedAt: startedAt, midiFileURL: midiFileURL, pieceId: pieceId)
        let fileURL = try writeDummyVideo()
        take.videoFileURL = try XCTUnwrap(VideoStore.relativePath(for: fileURL))
        take.videoDurationSec = 10
        context.insert(take)
        return (take, fileURL)
    }

    @MainActor
    func testAttachWritesFieldsAndKeepsFile() throws {
        let container = try makeVideoContainer()
        let context = ModelContext(container)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let take = Take(startedAt: start)
        context.insert(take)
        try context.save()

        let fileURL = try writeDummyVideo(bytes: 64)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let relative = try XCTUnwrap(VideoStore.relativePath(for: fileURL))

        let result = VideoRecordingResult(
            relativePath: relative,
            durationSec: 42,
            startedAt: start.addingTimeInterval(1.5)
        )
        try VideoAttachmentStore.attach(result: result, to: take, in: context)

        XCTAssertEqual(take.videoFileURL, relative)
        XCTAssertEqual(take.videoDurationSec, 42)
        XCTAssertEqual(take.videoStartedAtOffset, 1.5, accuracy: 0.0001)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "attach 不删文件")

        // 落库可见
        let reFetched = try context.fetch(FetchDescriptor<Take>())
        XCTAssertEqual(reFetched.count, 1)
        XCTAssertEqual(reFetched.first?.videoFileURL, relative)
    }

    @MainActor
    func testRetentionEvictsOldestBeyondEightPerPiece() throws {
        let container = try makeVideoContainer()
        let context = ModelContext(container)
        context.insert(AppSettings())
        let pieceId = UUID()
        var takes: [Take] = []
        var files: [URL] = []
        defer { files.forEach { try? FileManager.default.removeItem(at: $0) } }

        for index in 0..<9 {
            let startedAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 60)
            let inserted = try insertTake(
                in: context,
                startedAt: startedAt,
                pieceId: pieceId,
                midiFileURL: "midi/2026/10/take-\(index).midi.jsonl"
            )
            inserted.take.videoStartedAtOffset = 0.25
            takes.append(inserted.take)
            files.append(inserted.fileURL)
        }
        try context.save()

        try VideoAttachmentStore.enforceRetention(pieceId: pieceId, in: context)

        let oldest = takes[0]
        XCTAssertNil(oldest.videoFileURL, "每曲保留最近 8 条，最旧出局")
        XCTAssertEqual(oldest.videoDurationSec, 0)
        XCTAssertEqual(oldest.videoStartedAtOffset, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files[0].path), "淘汰删视频文件")
        XCTAssertEqual(oldest.midiFileURL, "midi/2026/10/take-0.midi.jsonl", "MIDI 路径不受影响")

        for index in 1..<9 {
            XCTAssertNotNil(takes[index].videoFileURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: files[index].path))
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<Take>()).count, 9, "take 行永不删除")
    }

    @MainActor
    func testRetentionGroupsPerPiece() throws {
        let container = try makeVideoContainer()
        let context = ModelContext(container)
        context.insert(AppSettings())
        let pieceA = UUID()
        let pieceB = UUID()
        var takes: [Take] = []
        var files: [URL] = []
        defer { files.forEach { try? FileManager.default.removeItem(at: $0) } }

        for index in 0..<9 {
            let startedAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 60)
            let inserted = try insertTake(
                in: context,
                startedAt: startedAt,
                pieceId: index < 5 ? pieceA : pieceB
            )
            takes.append(inserted.take)
            files.append(inserted.fileURL)
        }
        try context.save()

        try VideoAttachmentStore.enforceRetention(pieceId: pieceA, in: context)

        XCTAssertEqual(takes.filter { $0.videoFileURL != nil }.count, 9,
                       "5 + 4 均未超过每曲 8 条上限")
        for fileURL in files {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        }
    }

    @MainActor
    func testRetentionNeverModeKeepsEverything() throws {
        let container = try makeVideoContainer()
        let context = ModelContext(container)
        let settings = AppSettings(videoRetentionMode: "never")
        context.insert(settings)
        let pieceId = UUID()
        var takes: [Take] = []
        var files: [URL] = []
        defer { files.forEach { try? FileManager.default.removeItem(at: $0) } }

        for index in 0..<9 {
            let startedAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 60)
            let inserted = try insertTake(in: context, startedAt: startedAt, pieceId: pieceId)
            takes.append(inserted.take)
            files.append(inserted.fileURL)
        }
        try context.save()

        try VideoAttachmentStore.enforceRetention(pieceId: pieceId, in: context)

        XCTAssertEqual(takes.filter { $0.videoFileURL != nil }.count, 9, "never 模式零清理")
        for fileURL in files {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        }
    }

    @MainActor
    func testTakesWithoutVideoAreNeverCandidates() throws {
        let container = try makeVideoContainer()
        let context = ModelContext(container)
        context.insert(AppSettings())
        let pieceId = UUID()
        var videoTakes: [Take] = []
        var files: [URL] = []
        defer { files.forEach { try? FileManager.default.removeItem(at: $0) } }

        for index in 0..<8 {
            let startedAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 60)
            let inserted = try insertTake(in: context, startedAt: startedAt, pieceId: pieceId)
            videoTakes.append(inserted.take)
            files.append(inserted.fileURL)
        }

        var silentTakes: [Take] = []
        for index in 0..<5 {
            let take = Take(
                startedAt: Date(timeIntervalSince1970: 1_700_100_000 + Double(index) * 60),
                pieceId: pieceId
            )
            context.insert(take)
            silentTakes.append(take)
        }
        try context.save()

        try VideoAttachmentStore.enforceRetention(pieceId: pieceId, in: context)

        XCTAssertEqual(videoTakes.filter { $0.videoFileURL != nil }.count, 8,
                       "无视频 take 不占配额（13 条中 8 条有视频 → 零淘汰）")
        for take in silentTakes {
            XCTAssertNil(take.videoFileURL)
            XCTAssertEqual(take.videoDurationSec, 0)
            XCTAssertEqual(take.videoStartedAtOffset, 0)
        }
    }

    @MainActor
    func testDeleteVideoClearsOnlyTargetTake() throws {
        let container = try makeVideoContainer()
        let context = ModelContext(container)
        let pieceId = UUID()
        let first = try insertTake(in: context, startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                   pieceId: pieceId)
        let second = try insertTake(in: context, startedAt: Date(timeIntervalSince1970: 1_700_000_600),
                                    pieceId: pieceId)
        defer {
            try? FileManager.default.removeItem(at: first.fileURL)
            try? FileManager.default.removeItem(at: second.fileURL)
        }
        try context.save()

        let keptPath = try XCTUnwrap(second.take.videoFileURL)
        try VideoAttachmentStore.deleteVideo(for: first.take, in: context)

        XCTAssertNil(first.take.videoFileURL)
        XCTAssertEqual(first.take.videoDurationSec, 0)
        XCTAssertEqual(first.take.videoStartedAtOffset, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.fileURL.path))

        XCTAssertEqual(second.take.videoFileURL, keptPath)
        XCTAssertEqual(second.take.videoDurationSec, 10)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.fileURL.path))
    }
}

// MARK: - ④ 录像状态机契约（假实现，不碰相机）

final class VideoRecordingStateMachineTests: XCTestCase {

    private final class FakeRecorder: VideoRecording {
        private(set) var calls: [String] = []
        private(set) var state: VideoRecordingState = .idle
        var onStateChange: ((VideoRecordingState) -> Void)?
        var result: VideoRecordingResult?

        func start(now: Date) async throws {
            calls.append("start")
            state = .preparing
            onStateChange?(state)
            state = .recording(startedAt: now)
            onStateChange?(state)
        }

        func stop() async -> VideoRecordingResult? {
            calls.append("stop")
            state = .idle
            onStateChange?(state)
            return result
        }
    }

    func testStartThenStopOrdersStatesAndReturnsResult() async throws {
        let recorder = FakeRecorder()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let expected = VideoRecordingResult(
            relativePath: "videos/2026/10/video-x.mov",
            durationSec: 12,
            startedAt: startedAt
        )
        recorder.result = expected

        var observed: [VideoRecordingState] = []
        recorder.onStateChange = { observed.append($0) }

        try await recorder.start(now: startedAt)
        XCTAssertEqual(recorder.state, .recording(startedAt: startedAt))
        let result = await recorder.stop()

        XCTAssertEqual(recorder.calls, ["start", "stop"], "同起同停的顺序")
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(result, expected)
        XCTAssertEqual(observed, [.preparing, .recording(startedAt: startedAt), .idle])
    }
}

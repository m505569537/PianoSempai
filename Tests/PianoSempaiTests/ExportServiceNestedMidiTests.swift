import SwiftData
import XCTest
@testable import PianoSempai

/// 导出/恢复必须覆盖嵌套 MIDI（真机布局 midi/yyyy/MM/take-<uuid>.midi.jsonl，见 TakeStore.makeFileURL）。
/// 回归：旧 sandboxEntries 非递归 + restore 只收扁平文件（parts.count==2）→ take MIDI 从不进包、恢复丢失。
/// 不依赖网络/真机/Keychain：临时目录 + 注入 baseDir 的现有导出入口。
final class ExportServiceNestedMidiTests: XCTestCase {

    // MARK: 导出：嵌套 midi + 扁平 scores 都进包

    @MainActor
    func testExportIncludesNestedMidiAndFlatScores() throws {
        let container = try ModelContainer(
            for: AppSettings.self, Take.self, ScoreFile.self, ScoreErrorMark.self,
            GateEvent.self, CoursePathState.self, PlacementResult.self, VelocityCalibration.self,
            DailyPlan.self, PracticeTask.self, Piece.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-nested-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }

        // 嵌套 MIDI（midi/2026/9/…，3 层）
        let midiDir = baseDir.appendingPathComponent("midi/2026/9", isDirectory: true)
        try FileManager.default.createDirectory(at: midiDir, withIntermediateDirectories: true)
        let midiContent = Data("{\"t\":1,\"k\":\"on\",\"c\":0,\"n\":60,\"v\":80,\"suspicious\":false}\n".utf8)
        try midiContent.write(to: midiDir.appendingPathComponent("deep.midi.jsonl"))

        // 扁平 scores
        let scoresDir = baseDir.appendingPathComponent("scores", isDirectory: true)
        try FileManager.default.createDirectory(at: scoresDir, withIntermediateDirectories: true)
        let scoreContent = Data("fake-mscz".utf8)
        try scoreContent.write(to: scoresDir.appendingPathComponent("flat.mscz"))

        let zipURL = try ExportService.buildExport(baseDir: baseDir, includeVideos: false, context: context)
        let paths = try ExportService.entryPaths(of: zipURL)

        // 嵌套 midi 与扁平 scores 都进包（路径保留相对子目录结构）
        XCTAssertTrue(paths.contains("midi/2026/9/deep.midi.jsonl"), "嵌套 MIDI 必须进包")
        XCTAssertTrue(paths.contains("scores/flat.mscz"), "扁平 scores 必须进包")

        // 条目 data 与原文件一致
        let midiData = try XCTUnwrap(ExportService.entryData(of: zipURL, path: "midi/2026/9/deep.midi.jsonl"))
        XCTAssertEqual(midiData, midiContent)
        let scoreData = try XCTUnwrap(ExportService.entryData(of: zipURL, path: "scores/flat.mscz"))
        XCTAssertEqual(scoreData, scoreContent)
    }

    // MARK: 恢复：两文件都写回原相对路径、内容一致（round-trip）

    @MainActor
    func testRestoreWritesNestedMidiAndFlatScoresToOriginalPaths() throws {
        let container = try ModelContainer(
            for: AppSettings.self, Take.self, GateEvent.self, Piece.self, ScoreFile.self,
            ScoreErrorMark.self, DailyPlan.self, PracticeTask.self, PlacementResult.self,
            VelocityCalibration.self, CoursePathState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        // 源盘：构造嵌套 midi + 扁平 scores 后导出
        let sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-nested-src-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sourceDir) }

        let midiDir = sourceDir.appendingPathComponent("midi/2026/9", isDirectory: true)
        try FileManager.default.createDirectory(at: midiDir, withIntermediateDirectories: true)
        let midiContent = Data("{\"t\":9,\"k\":\"off\",\"c\":0,\"n\":60,\"v\":0,\"suspicious\":false}\n".utf8)
        try midiContent.write(to: midiDir.appendingPathComponent("deep.midi.jsonl"))

        let scoresDir = sourceDir.appendingPathComponent("scores", isDirectory: true)
        try FileManager.default.createDirectory(at: scoresDir, withIntermediateDirectories: true)
        let scoreContent = Data("fake-mscz-roundtrip".utf8)
        try scoreContent.write(to: scoresDir.appendingPathComponent("flat.mscz"))

        let zipURL = try ExportService.buildExport(baseDir: sourceDir, includeVideos: false, context: context)

        // 恢复到全新 baseDir（模拟换新机）
        let restoreDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-nested-dst-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: restoreDir) }

        _ = try ExportService.restore(from: zipURL, into: restoreDir, in: context)

        // 嵌套 MIDI 写回原相对路径、内容一致
        let restoredMidi = restoreDir.appendingPathComponent("midi/2026/9/deep.midi.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredMidi.path), "嵌套 MIDI 写回原路径")
        XCTAssertEqual(try Data(contentsOf: restoredMidi), midiContent)

        // 扁平 scores 写回原相对路径、内容一致
        let restoredScore = restoreDir.appendingPathComponent("scores/flat.mscz")
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredScore.path), "扁平 scores 写回原路径")
        XCTAssertEqual(try Data(contentsOf: restoredScore), scoreContent)
    }
}

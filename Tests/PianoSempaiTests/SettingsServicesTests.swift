import SwiftData
import XCTest
@testable import PianoSempai

/// M7 验收（Hermes）：掩码不暴露完整值、zip 含预期数据且断言无 Key/凭据条目、
/// 保留规则 LRU 3/8/never、重校力度盖时间戳。
/// 每服务商 Key 往返（providerId 隔离）见 ProviderKeyStoreTests——旧单 key 协议
/// APIKeyStore 已在 M7.1 Stage B（S25 服务商链）删除。
final class SettingsServicesTests: XCTestCase {

    // MARK: ① 掩码永不暴露完整值

    func testMaskingNeverRevealsFullValue() {
        let key = "ak-2026-deadbeef3F9A"
        let masked = APIKeyMasking.mask(key)
        XCTAssertNotEqual(masked, key, "掩码永远不能等于原值")
        XCTAssertTrue(masked.contains("•"))
        XCTAssertTrue(masked.hasSuffix("3F9A"), "掩码只露末 4 位")
        XCTAssertFalse(masked.contains("ak-2026"), "前缀不得出现在默认掩码")

        // 显态也不整串裸露（防旁观：前 2 + 后 4）
        let visible = APIKeyMasking.mask(key, visible: true)
        XCTAssertNotEqual(visible, key)
        XCTAssertFalse(visible.contains("deadbeef"), "显态中段仍是圆点")

        // 短值全掩码
        XCTAssertEqual(APIKeyMasking.mask("abc"), "•••")
        XCTAssertEqual(APIKeyMasking.mask("•", visible: true), "•")
    }

    // MARK: ② zip 含预期数据 + 无 Key/凭据条目

    @MainActor
    func testExportZipContainsExpectedDataAndNoCredentials() throws {
        let container = try ModelContainer(
            for: AppSettings.self, Take.self, ScoreFile.self, ScoreErrorMark.self,
            GateEvent.self, CoursePathState.self, PlacementResult.self, VelocityCalibration.self,
            DailyPlan.self, PracticeTask.self, Piece.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let take = Take(durationSec: 134, taskType: "main", hasMidi: true, midiFileURL: "midi/take-x.jsonl",
                        tempoAvg: 72, noteCount: 132, wrongNoteCount: 2, midiEventCount: 1284)
        context.insert(take)
        context.insert(ScoreErrorMark(scoreName: "样例", measure: 21, type: "note"))
        try context.save()

        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir.appendingPathComponent("scores"), withIntermediateDirectories: true)
        try Data("fake-musicxml".utf8).write(to: baseDir.appendingPathComponent("scores/score1.musicxml"))

        let zipURL = try ExportService.buildExport(baseDir: baseDir, includeVideos: false, context: context)
        let paths = try ExportService.entryPaths(of: zipURL)

        // 预期内容：元数据 + 乐谱文件
        XCTAssertTrue(paths.contains("data/metadata.json"))
        XCTAssertTrue(paths.contains("scores/score1.musicxml"), "乐谱文件应进包")

        // 元数据内容正确
        let metaData = try XCTUnwrap(ExportService.entryData(of: zipURL, path: "data/metadata.json"))
        let metadata = try JSONDecoder.iso.decode(ExportService.ExportMetadata.self, from: metaData)
        XCTAssertEqual(metadata.takes.count, 1)
        XCTAssertEqual(metadata.takes.first?.midiEventCount, 1284)
        XCTAssertEqual(metadata.errorMarks.count, 1)

        // 断言无任何 Key/凭据条目（路径与元数据文本双重检查）
        for path in paths {
            let lowered = path.lowercased()
            XCTAssertFalse(lowered.contains("apikey"), "导出包不得含 key 条目：\(path)")
            XCTAssertFalse(lowered.contains("secret"), "导出包不得含 secret 条目：\(path)")
            XCTAssertFalse(lowered.hasSuffix(".key"))
        }
        let metaText = String(data: metaData, encoding: .utf8) ?? ""
        XCTAssertFalse(metaText.lowercased().contains("apikey"), "元数据 JSON 不得含 apiKey 字段")
        XCTAssertFalse(metaText.contains("sk-"), "元数据不得含常见密钥前缀")

        try? FileManager.default.removeItem(at: baseDir)
    }

    @MainActor
    func testRestoreRoundTripRebuildsTablesAndFiles() throws {
        let container = try ModelContainer(
            for: AppSettings.self, Take.self, GateEvent.self, Piece.self, ScoreFile.self,
            ScoreErrorMark.self, DailyPlan.self, PracticeTask.self, PlacementResult.self,
            VelocityCalibration.self, CoursePathState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir.appendingPathComponent("pdfs"), withIntermediateDirectories: true)
        try Data("%PDF-fake".utf8).write(to: baseDir.appendingPathComponent("pdfs/a.pdf"))

        let take = Take(durationSec: 60, taskType: "main", hasMidi: true, midiFileURL: "midi/t.jsonl", tempoAvg: 70, noteCount: 50)
        context.insert(take)
        context.insert(GateEvent(kind: "override", reasonTag: "time", weekIndex: 1))
        context.insert(ScoreErrorMark(scoreName: "s", measure: 9, type: "note"))
        try context.save()

        let zipURL = try ExportService.buildExport(baseDir: baseDir, includeVideos: false, context: context)

        // 清空库（模拟换新机）
        for row in try context.fetch(FetchDescriptor<Take>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<GateEvent>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<ScoreErrorMark>()) { context.delete(row) }
        try FileManager.default.removeItem(at: baseDir.appendingPathComponent("pdfs"))
        try context.save()

        // 恢复前快照（S26：自动先在本机生成恢复前快照）
        let snapshotURL = try ExportService.makePreRestoreSnapshot(baseDir: baseDir, context: context)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path), "恢复前快照必须存在")
        XCTAssertTrue(snapshotURL.lastPathComponent.hasPrefix("pre-restore-snapshot-"))

        // 恢复
        let preview = try ExportService.previewRestore(from: zipURL)
        XCTAssertEqual(preview.takes, 1)
        let report = try ExportService.restore(from: zipURL, into: baseDir, in: context)
        try context.save()

        XCTAssertEqual(report.restoredTakes, 1)
        XCTAssertEqual(report.restoredGateEvents, 1)
        XCTAssertEqual(report.restoredMarks, 1)
        XCTAssertEqual(report.restoredFiles, 1, "实际写回的沙盒文件：pdfs/a.pdf（midi 文件未在盘上，仅 DB 条目）")

        XCTAssertEqual(try context.fetch(FetchDescriptor<Take>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GateEvent>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScoreErrorMark>()).count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: baseDir.appendingPathComponent("pdfs/a.pdf").path), "pdf 文件写回沙盒")

        try? FileManager.default.removeItem(at: baseDir)
    }

    // MARK: ③ 视频保留 LRU 3/8/never

    private func videoItems(_ count: Int) -> [VideoRetentionService.VideoItem] {
        (0..<count).map { i in
            VideoRetentionService.VideoItem(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + i * 3600)),
                isPermanent: false
            )
        }
    }

    func testRetentionLRU3() {
        let items = videoItems(10)
        let evicted = VideoRetentionService.evictionCandidates(items, rule: .lru(keepPerSource: 3))
        XCTAssertEqual(evicted.count, 7, "保留最近 3 条，最旧 7 条出局")
        // 出局的是最旧的（按时间升序前 7 个）
        let sorted = items.sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(Set(evicted), Set(sorted.prefix(7).map(\.id)))
    }

    func testRetentionLRU8() {
        let evicted = VideoRetentionService.evictionCandidates(videoItems(10), rule: .lru(keepPerSource: 8))
        XCTAssertEqual(evicted.count, 2, "默认每曲最近 8 条")
        // permanent 永不清理
        var items = videoItems(10)
        let permanentID = items[0].id
        items[0] = VideoRetentionService.VideoItem(id: permanentID, createdAt: items[0].createdAt, isPermanent: true)
        let evicted2 = VideoRetentionService.evictionCandidates(items, rule: .lru(keepPerSource: 3))
        XCTAssertFalse(evicted2.contains(permanentID), "月度录像永不自动清理")
    }

    func testRetentionNever() {
        let evicted = VideoRetentionService.evictionCandidates(videoItems(10), rule: .never)
        XCTAssertTrue(evicted.isEmpty, "never 模式零清理")
    }

    // MARK: ④ 重校力度盖时间戳

    @MainActor
    func testRecalibrationOverwriteStampsNewTime() throws {
        let container = try ModelContainer(
            for: VelocityCalibration.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let first = VelocityCalibration(ppVelocity: 30, mfVelocity: 64, ffVelocity: 100,
                                        ppSamples: 3, mfSamples: 3, ffSamples: 3,
                                        deviceName: "模拟输入", createdAt: Date(timeIntervalSinceNow: -86400))
        context.insert(first)
        try context.save()

        // 重校：新建一条（时间戳=now），旧记录保留供追溯
        let second = VelocityCalibration(ppVelocity: 35, mfVelocity: 70, ffVelocity: 108,
                                         ppSamples: 4, mfSamples: 4, ffSamples: 4,
                                         deviceName: "特伦斯 V70", createdAt: Date())
        context.insert(second)
        try context.save()

        let all = try context.fetch(FetchDescriptor<VelocityCalibration>())
        XCTAssertEqual(all.count, 2)
        let latest = all.sorted { $0.createdAt > $1.createdAt }.first
        XCTAssertEqual(latest?.ppVelocity, 35, "最新校准是重校产物")
        XCTAssertGreaterThan(latest!.createdAt, first.createdAt, "重校必须盖新时间戳")
        XCTAssertTrue(latest!.isCalibrated)
    }
}

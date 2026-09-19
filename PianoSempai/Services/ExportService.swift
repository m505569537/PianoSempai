import Foundation
import SwiftData
import ZIPFoundation

// 导出/恢复（S26；红线：Key 永不入包；zip 开放格式；无账号绑定）。
// 可测：baseDir 注入。导出 = 元数据 JSON + 沙盒文件（midi/scores/pdfs，视频可选）。
// 恢复（整库）：写回文件 + 用 JSON 替换对应表数据。
// zip 读写用 ZIPFoundation（MIT，pin 0.9.20；Hermes M7 指令替换自研解析器）。

enum ExportService {

    /// 导出包内的一个条目（内存形态，写入时经 ZIPFoundation 落盘）
    struct ExportEntry: Equatable {
        let path: String
        let data: Data
    }

    enum RestoreError: Error {
        case malformedMetadata
    }

    // MARK: 元数据（独立 Codable 结构，永不包含凭据字段）

    struct ExportMetadata: Codable, Equatable {
        let formatVersion: Int
        let exportedAt: Date
        let settings: SettingsDTO
        let pathState: PathStateDTO?
        let placementResults: [PlacementResultDTO]
        let calibrations: [CalibrationDTO]
        let dailyPlans: [DailyPlanDTO]
        let tasks: [TaskDTO]
        let takes: [TakeDTO]
        let gateEvents: [GateEventDTO]
        let pieces: [PieceDTO]
        let scoreFiles: [ScoreFileDTO]
        let errorMarks: [ErrorMarkDTO]
    }

    struct SettingsDTO: Codable, Equatable {
        let weeklyGoal: Int
        let notificationConfigured: Bool
        let createdAt: Date
        // 注意：永远没有 apiKey 字段（凭据只在 Keychain）
    }

    struct PathStateDTO: Codable, Equatable {
        let currentBeyer: Int
        let currentHanon: Int
        let current599: Int?
        let projected599Week: Int
        let weekNumber: Int
    }

    struct PlacementResultDTO: Codable, Equatable {
        let sightreadHitRates: [Double]
        let overallReferenceScore: Int
        let entryBeyer: Int
        let entryHanon: Int
        let projected599Weeks: Int
        let createdAt: Date
    }

    struct CalibrationDTO: Codable, Equatable {
        let pp: Int
        let mf: Int
        let ff: Int
        let ppSamples: Int
        let mfSamples: Int
        let ffSamples: Int
        let deviceName: String
        let createdAt: Date
    }

    struct DailyPlanDTO: Codable, Equatable {
        let date: Date
        let durationChoice: Int
        let warmupCompleted: Bool
        let rulesVersion: String
    }

    struct TaskDTO: Codable, Equatable {
        let type: String
        let book: String
        let number: Int
        let status: String
    }

    struct TakeDTO: Codable, Equatable {
        let startedAt: Date
        let durationSec: Int
        let taskType: String
        let isFreePlay: Bool
        let midiFileURL: String
        let measureFrom: Int?
        let measureTo: Int?
        let tempoAvg: Int
        let noteCount: Int
        let wrongNoteCount: Int
        let pedalEventCount: Int
        let midiEventCount: Int
        let interruptionRanges: [Int]
        let title: String
    }

    struct GateEventDTO: Codable, Equatable {
        let date: Date
        let kind: String
        let reasonTag: String
        let note: String
        let weekIndex: Int
    }

    struct PieceDTO: Codable, Equatable {
        let title: String
        let book: String
        let number: Int
        let status: String
        let referenceTempo: Int
    }

    struct ScoreFileDTO: Codable, Equatable {
        let kind: String
        let fileURL: String
        let title: String
        let canFollow: Bool
        let importedAt: Date
    }

    struct ErrorMarkDTO: Codable, Equatable {
        let scoreName: String
        let measure: Int
        let type: String
        let note: String
        let occurrenceCount: Int
    }

    enum ExportError: Error, Equatable {
        case nothingToExport
    }

    // MARK: 收集

    static func collectMetadata(context: ModelContext) -> ExportMetadata {
        func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
            (try? context.fetch(FetchDescriptor<T>())) ?? []
        }
        let pathState = fetch(CoursePathState.self).first

        return ExportMetadata(
            formatVersion: 1,
            exportedAt: Date(),
            settings: SettingsDTO(
                weeklyGoal: fetch(AppSettings.self).first?.weeklyGoal ?? 3,
                notificationConfigured: fetch(AppSettings.self).first?.notificationConfigured ?? false,
                createdAt: fetch(AppSettings.self).first?.createdAt ?? Date()
            ),
            pathState: pathState.map {
                PathStateDTO(currentBeyer: $0.currentBeyer, currentHanon: $0.currentHanon,
                             current599: $0.current599, projected599Week: $0.projected599Week,
                             weekNumber: $0.weekNumber)
            },
            placementResults: fetch(PlacementResult.self).map {
                PlacementResultDTO(sightreadHitRates: $0.sightreadHitRates,
                                   overallReferenceScore: $0.overallReferenceScore,
                                   entryBeyer: $0.entryBeyer, entryHanon: $0.entryHanon,
                                   projected599Weeks: $0.projected599Weeks, createdAt: $0.createdAt)
            },
            calibrations: fetch(VelocityCalibration.self).map {
                CalibrationDTO(pp: $0.ppVelocity, mf: $0.mfVelocity, ff: $0.ffVelocity,
                               ppSamples: $0.ppSamples, mfSamples: $0.mfSamples, ffSamples: $0.ffSamples,
                               deviceName: $0.deviceName, createdAt: $0.createdAt)
            },
            dailyPlans: fetch(DailyPlan.self).map {
                DailyPlanDTO(date: $0.date, durationChoice: $0.durationChoice,
                             warmupCompleted: $0.warmupCompletedAt != nil,
                             rulesVersion: $0.generatedFromRulesVersion)
            },
            tasks: fetch(PracticeTask.self).map {
                TaskDTO(type: $0.type, book: $0.book, number: $0.number, status: $0.status)
            },
            takes: fetch(Take.self).map {
                TakeDTO(startedAt: $0.startedAt, durationSec: $0.durationSec, taskType: $0.taskType,
                        isFreePlay: $0.isFreePlay, midiFileURL: $0.midiFileURL,
                        measureFrom: $0.measureFrom, measureTo: $0.measureTo,
                        tempoAvg: $0.tempoAvg, noteCount: $0.noteCount, wrongNoteCount: $0.wrongNoteCount,
                        pedalEventCount: $0.pedalEventCount, midiEventCount: $0.midiEventCount,
                        interruptionRanges: $0.interruptionRanges, title: $0.title)
            },
            gateEvents: fetch(GateEvent.self).map {
                GateEventDTO(date: $0.date, kind: $0.kind, reasonTag: $0.reasonTag,
                             note: $0.note, weekIndex: $0.weekIndex)
            },
            pieces: fetch(Piece.self).map {
                PieceDTO(title: $0.title, book: $0.book, number: $0.number,
                         status: $0.status, referenceTempo: $0.referenceTempo)
            },
            scoreFiles: fetch(ScoreFile.self).map {
                ScoreFileDTO(kind: $0.kind, fileURL: $0.fileURL, title: $0.title,
                             canFollow: $0.canFollow, importedAt: $0.importedAt)
            },
            errorMarks: fetch(ScoreErrorMark.self).map {
                ErrorMarkDTO(scoreName: $0.scoreName, measure: $0.measure, type: $0.type,
                             note: $0.note, occurrenceCount: $0.occurrenceCount)
            }
        )
    }

    // MARK: 打包

    /// 构建 zip（到 baseDir/exports/）。includeVideos=true 但无视频文件时如实只包含现有内容。
    static func buildExport(baseDir: URL, includeVideos: Bool, context: ModelContext, fileManager: FileManager = .default) throws -> URL {
        let metadata = collectMetadata(context: context)
        let metaData = try JSONEncoder.iso.encode(metadata)

        var entries: [ExportEntry] = [
            ExportEntry(path: "data/metadata.json", data: metaData),
        ]

        // 沙盒文件（midi/scores/pdfs；视频可选）
        for (dir, prefix) in [("midi", "midi"), ("scores", "scores"), ("pdfs", "pdfs")] {
            entries.append(contentsOf: sandboxEntries(baseDir: baseDir, subdirectory: dir, zipPrefix: prefix, fileManager: fileManager))
        }
        if includeVideos {
            entries.append(contentsOf: sandboxEntries(baseDir: baseDir, subdirectory: "video", zipPrefix: "video", fileManager: fileManager))
        }

        let exportsDir = baseDir.appendingPathComponent("exports", isDirectory: true)
        try fileManager.createDirectory(at: exportsDir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        // 同秒多次导出/快照不冲突（快照紧跟导出时同秒）
        let unique = UUID().uuidString.prefix(6)
        let url = exportsDir.appendingPathComponent("pianosempai-export-\(formatter.string(from: Date()))-\(unique).zip")
        let archive = try Archive(url: url, accessMode: .create)
        for entry in entries {
            let data = entry.data
            try archive.addEntry(with: entry.path, type: .file, uncompressedSize: Int64(data.count), bufferSize: 64 * 1024) { position, bufferSize in
                Data(data.dropFirst(Int(position)).prefix(Int(bufferSize)))
            }
        }
        return url
    }

    /// 测试/UI 检查用：列出 zip 内的条目路径（不暴露数据）
    static func entryPaths(of url: URL) throws -> [String] {
        let archive = try Archive(url: url, accessMode: .read)
        return archive.map(\.path)
    }

    /// 读取指定条目内容
    static func entryData(of url: URL, path: String) throws -> Data? {
        let archive = try Archive(url: url, accessMode: .read)
        guard let entry = archive.first(where: { $0.path == path }) else { return nil }
        var data = Data()
        _ = try archive.extract(entry, bufferSize: 64 * 1024) { chunk in
            data.append(chunk)
        }
        return data
    }

    // MARK: 恢复预览 + 快照（S26 交互态：先看差异计数 → 二次确认 → 自动恢复前快照）

    struct RestorePreview: Equatable {
        let takes: Int
        let gateEvents: Int
        let pieces: Int
        let scoreFiles: Int
        let marks: Int
        let files: Int
        let totalRows: Int
    }

    static func previewRestore(from url: URL) throws -> RestorePreview {
        let entries = try archiveEntries(from: url)
        guard let metaEntry = entries.first(where: { $0.path == "data/metadata.json" }) else {
            throw Archive.ArchiveError.unreadableArchive
        }
        let metadata = try JSONDecoder.iso.decode(ExportMetadata.self, from: metaEntry.data)
        let files = entries.filter { $0.path != "data/metadata.json" }.count
        let preview = RestorePreview(
            takes: metadata.takes.count,
            gateEvents: metadata.gateEvents.count,
            pieces: metadata.pieces.count,
            scoreFiles: metadata.scoreFiles.count,
            marks: metadata.errorMarks.count,
            files: files,
            totalRows: metadata.takes.count + metadata.gateEvents.count + metadata.pieces.count
                + metadata.scoreFiles.count + metadata.errorMarks.count
                + metadata.placementResults.count + metadata.calibrations.count
                + metadata.dailyPlans.count + metadata.tasks.count
        )
        return preview
    }

    /// 恢复前快照：当前库 + 沙盒文件先打包一份（S26"自动先在本机生成恢复前快照"）
    @discardableResult
    static func makePreRestoreSnapshot(baseDir: URL, context: ModelContext, fileManager: FileManager = .default) throws -> URL {
        let url = try buildExport(baseDir: baseDir, includeVideos: true, context: context, fileManager: fileManager)
        let renamed = url.deletingLastPathComponent().appendingPathComponent("pre-restore-snapshot-\(url.lastPathComponent)")
        if fileManager.fileExists(atPath: renamed.path) {
            try fileManager.removeItem(at: renamed)
        }
        try fileManager.moveItem(at: url, to: renamed)
        return renamed
    }

    /// ZIPFoundation 条目读取（内部辅助）
    private static func archiveEntries(from url: URL) throws -> [(path: String, data: Data)] {
        let archive = try Archive(url: url, accessMode: .read)
        var result: [(path: String, data: Data)] = []
        for entry in archive {
            var data = Data()
            _ = try archive.extract(entry, bufferSize: 64 * 1024) { chunk in
                data.append(chunk)
            }
            result.append((path: entry.path, data: data))
        }
        return result
    }

    private static func sandboxEntries(baseDir: URL, subdirectory: String, zipPrefix: String, fileManager: FileManager) -> [ExportEntry] {
        let dir = baseDir.appendingPathComponent(subdirectory, isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return [] }
        return files.compactMap { name in
            let url = dir.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return ExportEntry(path: "\(zipPrefix)/\(name)", data: data)
        }
    }

    // MARK: 恢复（整库）

    struct RestoreReport: Equatable {
        let restoredFiles: Int
        let restoredTakes: Int
        let restoredGateEvents: Int
        let restoredPieces: Int
        let restoredMarks: Int
    }

    /// 从 zip 恢复：文件写回沙盒 + 表数据整体替换（恢复前由调用方快照，S26 交互态）。
    static func restore(from url: URL, into baseDir: URL, in context: ModelContext, fileManager: FileManager = .default) throws -> RestoreReport {
        let entries = try archiveEntries(from: url)
        var fileCount = 0

        // 1) 文件写回（不覆盖 metadata.json）
        for entry in entries where entry.path.hasPrefix("midi/") || entry.path.hasPrefix("scores/") || entry.path.hasPrefix("pdfs/") {
            let parts = entry.path.split(separator: "/")
            guard parts.count == 2 else { continue }
            let dir = baseDir.appendingPathComponent(String(parts[0]), isDirectory: true)
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            try entry.data.write(to: dir.appendingPathComponent(String(parts[1])))
            fileCount += 1
        }

        // 2) 元数据整库替换
        guard let metaEntry = entries.first(where: { $0.path == "data/metadata.json" }) else {
            throw RestoreError.malformedMetadata
        }
        let metadata = try JSONDecoder.iso.decode(ExportMetadata.self, from: metaEntry.data)

        // 删旧（这些表整体替换；AppSettings 保留本机记录只更新值）
        for row in (try? context.fetch(FetchDescriptor<Take>())) ?? [] { context.delete(row) }
        for row in (try? context.fetch(FetchDescriptor<GateEvent>())) ?? [] { context.delete(row) }
        for row in (try? context.fetch(FetchDescriptor<Piece>())) ?? [] { context.delete(row) }
        for row in (try? context.fetch(FetchDescriptor<ScoreFile>())) ?? [] { context.delete(row) }
        for row in (try? context.fetch(FetchDescriptor<ScoreErrorMark>())) ?? [] { context.delete(row) }
        for row in (try? context.fetch(FetchDescriptor<DailyPlan>())) ?? [] { context.delete(row) }
        for row in (try? context.fetch(FetchDescriptor<PracticeTask>())) ?? [] { context.delete(row) }
        for row in (try? context.fetch(FetchDescriptor<PlacementResult>())) ?? [] { context.delete(row) }
        for row in (try? context.fetch(FetchDescriptor<VelocityCalibration>())) ?? [] { context.delete(row) }

        for dto in metadata.takes {
            let take = Take(startedAt: dto.startedAt, endedAt: nil, durationSec: dto.durationSec,
                            taskType: dto.taskType, hasMidi: dto.midiEventCount > 0, isFreePlay: dto.isFreePlay,
                            midiFileURL: dto.midiFileURL, measureFrom: dto.measureFrom, measureTo: dto.measureTo,
                            tempoAvg: dto.tempoAvg, noteCount: dto.noteCount, wrongNoteCount: dto.wrongNoteCount,
                            pedalEventCount: dto.pedalEventCount, midiEventCount: dto.midiEventCount,
                            interruptionRanges: dto.interruptionRanges, title: dto.title)
            context.insert(take)
        }
        for dto in metadata.gateEvents {
            context.insert(GateEvent(date: dto.date, kind: dto.kind, reasonTag: dto.reasonTag,
                                     note: dto.note, weekIndex: dto.weekIndex))
        }
        for dto in metadata.pieces {
            context.insert(Piece(title: dto.title, book: dto.book, number: dto.number,
                                 status: dto.status, referenceTempo: dto.referenceTempo))
        }
        for dto in metadata.scoreFiles {
            context.insert(ScoreFile(kind: dto.kind, fileURL: dto.fileURL, title: dto.title,
                                     canFollow: dto.canFollow, importedAt: dto.importedAt))
        }
        for dto in metadata.errorMarks {
            context.insert(ScoreErrorMark(scoreName: dto.scoreName, measure: dto.measure,
                                          type: dto.type, note: dto.note, occurrenceCount: dto.occurrenceCount))
        }
        if let settings = (try? context.fetch(FetchDescriptor<AppSettings>()))?.first {
            settings.weeklyGoal = metadata.settings.weeklyGoal
        }
        if let dto = metadata.pathState {
            let state = (try? context.fetch(FetchDescriptor<CoursePathState>()))?.first ?? CoursePathState()
            state.currentBeyer = dto.currentBeyer
            state.currentHanon = dto.currentHanon
            state.current599 = dto.current599
            state.projected599Week = dto.projected599Week
            state.weekNumber = dto.weekNumber
            context.insert(state)
        }

        return RestoreReport(
            restoredFiles: fileCount,
            restoredTakes: metadata.takes.count,
            restoredGateEvents: metadata.gateEvents.count,
            restoredPieces: metadata.pieces.count,
            restoredMarks: metadata.errorMarks.count
        )
    }
}

extension JSONEncoder {
    static var iso: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - 视频保留规则（LRU；月度录像永不清理；P1 无视频捕获，规则先行 + 单测）

enum VideoRetentionService {

    struct VideoItem: Equatable {
        let id: UUID
        let createdAt: Date
        let isPermanent: Bool // Zf 月度录像 → 永不清理
    }

    enum Rule: Equatable {
        case lru(keepPerSource: Int) // 每曲保留最近 N 条（默认 8，可改）
        case never
    }

    /// 返回应删除的 id（超出保留数的最旧者；permanent 永不入选）
    static func evictionCandidates(_ items: [VideoItem], rule: Rule) -> [UUID] {
        switch rule {
        case .never:
            return []
        case let .lru(keep):
            guard keep >= 0 else { return [] }
            let evictable = items.filter { !$0.isPermanent }
            // P1 单曲口径（每曲分组在 VideoClip 关联 Piece 后启用；规则保持纯函数）
            let sorted = evictable.sorted { $0.createdAt < $1.createdAt }
            guard sorted.count > keep else { return [] }
            return Array(sorted.prefix(sorted.count - keep)).map(\.id)
        }
    }
}

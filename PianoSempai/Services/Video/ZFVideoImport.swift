import Foundation
import SwiftData

// Zf 月度录像导入（ADR-0012 / S17）：纯规划 + 落盘落库。
// 本 stage 不含 UI：候选来自相册（PhotoLibraryService），已导出的临时文件经 sourceURLs 传入。
// 红线：原片复制不转码；失败/取消全量回滚；Zf 归档永不参与 LRU 清理。

struct ZFImportCandidate: Identifiable, Equatable, Sendable {
    let id: String              // assetIdentifier
    let metadata: ZFAssetMetadata
    let byteSize: Int64         // 来自导出后的临时文件；UI 预览阶段可先 0
}

enum ZFImportBlockReason: Equatable, Sendable {
    case missingCreationDate
    case tooLarge(bytes: Int64)          // > 2 GB
    case alreadyImported
    case insufficientSpace(needed: Int64, available: Int64)
}

/// 导入失败（除 PhotoLibraryError 之外的本地校验失败；全部触发回滚）
enum ZFImportError: Error, Equatable {
    case missingSourceURL(assetIdentifier: String)
    case missingCreationDate(assetIdentifier: String)
    case destinationUnavailable(assetIdentifier: String)
    case sizeMismatch(assetIdentifier: String, expected: Int64, actual: Int64)
}

/// 纯函数，全部可单测
enum ZFImportPlanner {

    static let maxFileBytes: Int64 = 2 * 1024 * 1024 * 1024

    /// 月份 key "yyyy-MM"（Calendar.current；creationDate 为 nil 时返回 nil）
    static func monthKey(for date: Date?, calendar: Calendar = .current) -> String? {
        guard let date else { return nil }
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else { return nil }
        return String(format: "%04d-%02d", year, month)
    }

    /// 每条候选的阻塞原因（nil = 可导入）。
    /// 单条原因优先（无日期 → 过大 → 已导入）；剩余空间不足按「本次可导入合计」整体判定。
    static func blockReasons(candidates: [ZFImportCandidate],
                             existingAssetIdentifiers: Set<String>,
                             availableBytes: Int64) -> [String: ZFImportBlockReason] {
        var reasons: [String: ZFImportBlockReason] = [:]
        var importableBytes: Int64 = 0
        var importableIds: [String] = []

        for candidate in candidates {
            if candidate.metadata.creationDate == nil {
                reasons[candidate.id] = .missingCreationDate
            } else if candidate.byteSize > maxFileBytes {
                reasons[candidate.id] = .tooLarge(bytes: candidate.byteSize)
            } else if existingAssetIdentifiers.contains(candidate.id) {
                reasons[candidate.id] = .alreadyImported
            } else {
                importableBytes += candidate.byteSize
                importableIds.append(candidate.id)
            }
        }

        if importableBytes > availableBytes {
            for id in importableIds {
                reasons[id] = .insufficientSpace(needed: importableBytes, available: availableBytes)
            }
        }
        return reasons
    }

    /// 已选且可导入的合计字节
    static func totalBytes(_ candidates: [ZFImportCandidate]) -> Int64 {
        candidates.reduce(0) { total, candidate in
            let (sum, overflow) = total.addingReportingOverflow(candidate.byteSize)
            return overflow ? Int64.max : sum
        }
    }
}

@MainActor
enum ZFImportService {

    /// 复制 + 落 Take；任何失败/取消都回滚已写入的文件与新 Take 行。
    /// - Parameters:
    ///   - sourceURLs: assetId → 已导出临时文件（成功后删除；已导入的候选不触碰）
    ///   - isCancelled: 任一时刻返回 true 即中止并回滚
    ///   - progress: (已完成条数, 总条数)
    static func importCandidates(_ candidates: [ZFImportCandidate],
                                 pieceId: UUID?,
                                 sourceURLs: [String: URL],
                                 in context: ModelContext,
                                 isCancelled: @escaping () -> Bool,
                                 progress: (@MainActor (Int, Int) -> Void)?) async throws -> [Take] {
        let fileManager = FileManager.default

        // 去重：库里已有的 sourceAssetIdentifier + 本批重复 id 都跳过，绝不建第二条
        let existingTakes = try context.fetch(FetchDescriptor<Take>())
        var knownIds = Set(existingTakes.compactMap(\.sourceAssetIdentifier))
        var queued: [ZFImportCandidate] = []
        for candidate in candidates where knownIds.insert(candidate.id).inserted {
            queued.append(candidate)
        }

        var copiedFiles: [URL] = []
        var insertedTakes: [Take] = []
        let total = queued.count

        do {
            for candidate in queued {
                if isCancelled() { throw PhotoLibraryError.cancelled }

                guard let creationDate = candidate.metadata.creationDate else {
                    throw ZFImportError.missingCreationDate(assetIdentifier: candidate.id)
                }
                guard let sourceURL = sourceURLs[candidate.id] else {
                    throw ZFImportError.missingSourceURL(assetIdentifier: candidate.id)
                }

                let destination = try VideoStore.zfDestinationURL(
                    assetIdentifier: candidate.id,
                    creationDate: creationDate
                )
                // 同名残留（历史失败留下的孤儿文件）先清掉，避免 copyItem 报存在
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: sourceURL, to: destination)
                copiedFiles.append(destination)

                let sourceBytes = try fileSize(at: sourceURL, fileManager: fileManager)
                let copiedBytes = try fileSize(at: destination, fileManager: fileManager)
                guard sourceBytes == copiedBytes else {
                    throw ZFImportError.sizeMismatch(
                        assetIdentifier: candidate.id,
                        expected: sourceBytes,
                        actual: copiedBytes
                    )
                }
                // 校验通过才删临时导出文件
                try? fileManager.removeItem(at: sourceURL)

                guard let relativePath = VideoStore.relativePath(for: destination) else {
                    throw ZFImportError.destinationUnavailable(assetIdentifier: candidate.id)
                }

                let durationSec = Int(candidate.metadata.durationSec.rounded())
                let take = Take(
                    startedAt: creationDate,
                    endedAt: nil,
                    durationSec: durationSec,
                    taskType: "zfImport",
                    hasMidi: false,
                    isFreePlay: false,
                    pieceId: pieceId,
                    isPassEligible: false,
                    title: Self.title(for: creationDate),
                    videoFileURL: relativePath,
                    videoDurationSec: durationSec,
                    videoStartedAtOffset: 0,
                    isRecordingSession: false,
                    sourceAssetIdentifier: candidate.id
                )
                context.insert(take)
                insertedTakes.append(take)

                progress?(insertedTakes.count, total)
            }

            if isCancelled() { throw PhotoLibraryError.cancelled }
            try context.save()
            return insertedTakes
        } catch {
            // 回滚：先删落盘文件，再删已插入的 Take 行（不碰已存在的历史数据）
            for url in copiedFiles {
                try? fileManager.removeItem(at: url)
            }
            for take in insertedTakes {
                context.delete(take)
            }
            try? context.save()
            throw error
        }
    }

    // MARK: - 私有

    private static func title(for date: Date, calendar: Calendar = .current) -> String {
        "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date)) Zf 录像"
    }

    private static func fileSize(at url: URL, fileManager: FileManager) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}

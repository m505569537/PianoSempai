import Foundation
import SwiftData

// 视频附件挂载与保留规则执行（ADR-0010）。
// 淘汰只清视频字段 + 删视频文件：take 行 / MIDI / 分析永久保留。

@MainActor
enum VideoAttachmentStore {

    /// 挂视频到 take（相对路径 + 时长 + 偏移），并立即执行保留规则
    static func attach(result: VideoRecordingResult, to take: Take, in context: ModelContext) throws {
        // result.relativePath 通常已是 Documents 相对路径；若是绝对路径/file URL 则换算
        take.videoFileURL = normalizedRelativePath(result.relativePath)
        take.videoDurationSec = result.durationSec
        take.videoStartedAtOffset = result.startedAt.timeIntervalSince(take.startedAt)
        try enforceRetention(pieceId: take.pieceId, in: context)
    }

    /// 按 AppSettings.videoRetentionMode 执行 LRU（按 pieceId 分组；无 pieceId 的 take 各自成组）
    static func enforceRetention(pieceId: UUID?, in context: ModelContext) throws {
        let settings = AppSettings.fetchOrCreate(in: context)
        let rule: VideoRetentionService.Rule = settings.videoRetentionMode == "never"
            ? .never
            : .lru(keepPerSource: 8)

        // 只取有视频的 take 作为候选；无视频 take 永不计入配额
        let takes = try context.fetch(FetchDescriptor<Take>())
        var groups: [UUID: [Take]] = [:]
        for take in takes where take.videoFileURL != nil {
            let key = take.pieceId ?? take.entityId
            groups[key, default: []].append(take)
        }

        var evicted: [Take] = []
        for group in groups.values {
            let items = group.map {
                VideoRetentionService.VideoItem(
                    id: $0.entityId,
                    createdAt: $0.startedAt,
                    isPermanent: false
                )
            }
            let ids = Set(VideoRetentionService.evictionCandidates(items, rule: rule))
            evicted.append(contentsOf: group.filter { ids.contains($0.entityId) })
        }

        for take in evicted {
            if let path = take.videoFileURL {
                try VideoStore.delete(relativePath: path)
            }
            take.videoFileURL = nil
            take.videoDurationSec = 0
            take.videoStartedAtOffset = 0
        }

        try context.save()
    }

    /// 清字段 + 删文件（只影响这一条 take）
    static func deleteVideo(for take: Take, in context: ModelContext) throws {
        if let path = take.videoFileURL {
            try VideoStore.delete(relativePath: path)
        }
        take.videoFileURL = nil
        take.videoDurationSec = 0
        take.videoStartedAtOffset = 0
        try context.save()
    }

    private static func normalizedRelativePath(_ path: String) -> String {
        if path.hasPrefix("file://"), let url = URL(string: path),
           let relative = VideoStore.relativePath(for: url) {
            return relative
        }
        if path.hasPrefix("/"), let relative = VideoStore.relativePath(for: URL(fileURLWithPath: path)) {
            return relative
        }
        return path
    }
}

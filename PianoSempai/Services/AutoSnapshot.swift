import Foundation
import SwiftData

/// 自动快照（2026-11-12）。
///
/// 背景：练习数据全部只存本机 SwiftData，没有 iCloud 同步；换机 / 重装 / 手机丢失
/// 之前如果没手动导出过，几百小时的练习历史会一起消失。S26 导出页能手动打包，
/// 但没人会记得每周去点一次——这里补一个「到期自动打一份」的本机兜底。
///
/// 边界（有意为之）：
/// - **不是同步**，也不写 iCloud；真正换机恢复仍走 S26 导出 → 新机导入。
/// - 默认**不含视频**（视频在相册另有原件，且体积以 GB 计），只备份元数据 + midi/scores/pdfs。
/// - 文件名用 `auto-snapshot-` 前缀，与手动导出 `pianosempai-export-*` 区分，
///   清理只动自己的，绝不删用户手动导出的包。
enum AutoSnapshot {

    /// 快照间隔：一周
    static let interval: TimeInterval = 7 * 24 * 60 * 60

    /// 滚动保留份数
    static let keepCount = 3

    /// 上次成功时间（失败不写，下次启动重试）
    static let lastRunDefaultsKey = "pianoSempai.autoSnapshot.lastRunAt"

    /// 文件名前缀（清理只认这个前缀）
    static let filePrefix = "auto-snapshot-"

    // MARK: - 纯逻辑（可单测）

    /// 是否到期。无历史记录 = 到期（首次安装立即备份一次）。
    static func isDue(lastRunAt: Date?, now: Date, interval: TimeInterval = interval) -> Bool {
        guard let lastRunAt else { return true }
        return now.timeIntervalSince(lastRunAt) >= interval
    }

    /// 快照文件名：前缀 + 可字典序排序的紧凑时间戳（yyyyMMdd-HHmmss，固定 en_US_POSIX）。
    /// 字典序 == 时间序，清理时直接按字符串倒序即可，不依赖文件系统时间戳。
    static func fileName(now: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(filePrefix)\(formatter.string(from: now)).zip"
    }

    /// 给定目录里已有的快照文件，返回应删除的那些（保留文件名倒序前 `keep` 份）。
    /// 只处理 `filePrefix` 前缀，其它文件一概不碰。
    static func urlsToPrune(_ urls: [URL], keep: Int = keepCount) -> [URL] {
        let own = urls.filter { $0.lastPathComponent.hasPrefix(filePrefix) }
        let sorted = own.sorted { $0.lastPathComponent > $1.lastPathComponent }
        guard keep > 0 else { return sorted }
        return Array(sorted.dropFirst(keep))
    }

    // MARK: - 执行

    /// 到期则打一份快照并滚动清理。返回新建文件；未到期或失败返回 nil。
    /// 在主线程调用：SwiftData 的 ModelContext 与当前 actor 绑定，且单份快照体积小（无视频）。
    @MainActor
    @discardableResult
    static func runIfDue(
        baseDir: URL,
        context: ModelContext,
        now: Date = Date(),
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) -> URL? {
        let last = defaults.object(forKey: lastRunDefaultsKey) as? Date
        guard isDue(lastRunAt: last, now: now) else { return nil }

        // 打包失败就保持「未备份」状态，下次启动再试（不写 lastRun，避免假成功）
        guard let built = try? ExportService.buildExport(
            baseDir: baseDir,
            includeVideos: false,
            context: context,
            fileManager: fileManager
        ) else { return nil }

        let exportsDir = baseDir.appendingPathComponent("exports", isDirectory: true)
        let dest = exportsDir.appendingPathComponent(fileName(now: now))
        try? fileManager.removeItem(at: dest)
        guard (try? fileManager.moveItem(at: built, to: dest)) != nil else {
            try? fileManager.removeItem(at: built)
            return nil
        }

        defaults.set(now, forKey: lastRunDefaultsKey)

        // 滚动清理：只删自己的前缀，保留最近 keep 份
        if let existing = try? fileManager.contentsOfDirectory(
            at: exportsDir, includingPropertiesForKeys: nil
        ) {
            for url in urlsToPrune(existing) {
                try? fileManager.removeItem(at: url)
            }
        }
        return dest
    }

    /// 最近一份自动快照（Settings 展示用；没有返回 nil）。
    static func latestSnapshot(baseDir: URL, fileManager: FileManager = .default) -> URL? {
        let exportsDir = baseDir.appendingPathComponent("exports", isDirectory: true)
        guard let existing = try? fileManager.contentsOfDirectory(
            at: exportsDir, includingPropertiesForKeys: nil
        ) else { return nil }
        return existing
            .filter { $0.lastPathComponent.hasPrefix(filePrefix) }
            .max { $0.lastPathComponent < $1.lastPathComponent }
    }
}

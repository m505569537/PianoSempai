import Foundation

// 视频文件落盘（与 TakeStore 的 midi/yyyy/MM/ 平行，ADR-0010）。
// 目录：Documents/videos/yyyy/MM/video-<uuid>.mov
// 文件名用录像会话 UUID（take 落库前录制已开始，takeId 尚不存在）。

enum VideoStore {

    enum StoreError: Error {
        case documentsUnavailable
    }

    /// 本次录像视频文件 URL（创建 yyyy/MM 目录）
    static func makeFileURL(now: Date = Date(), fileManager: FileManager = .default) throws -> URL {
        guard let docs = documentsURL(fileManager: fileManager) else {
            throw StoreError.documentsUnavailable
        }
        let cal = Calendar.current
        let dir = docs
            .appendingPathComponent("videos", isDirectory: true)
            .appendingPathComponent(String(cal.component(.year, from: now)), isDirectory: true)
            .appendingPathComponent(String(cal.component(.month, from: now)), isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("video-\(UUID().uuidString).mov")
    }

    /// Documents 根 + 相对路径；绝对路径、含 `..` 或逃出 Documents 的路径返回 nil
    static func absoluteURL(for relativePath: String, fileManager: FileManager = .default) -> URL? {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains(".."),
              let docs = documentsURL(fileManager: fileManager) else { return nil }
        let url = docs.appendingPathComponent(relativePath)
        // 标准化后二次校验，杜绝符号式逃逸
        let docsPath = docs.standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(docsPath + "/") else { return nil }
        return url
    }

    /// 相对路径（相对 Documents）；不在 Documents 下返回 nil
    static func relativePath(for url: URL, fileManager: FileManager = .default) -> String? {
        guard let docs = documentsURL(fileManager: fileManager) else { return nil }
        let docsPath = docs.standardizedFileURL.path
        let fullPath = url.standardizedFileURL.path
        guard fullPath.hasPrefix(docsPath + "/") else { return nil }
        return String(fullPath.dropFirst(docsPath.count + 1))
    }

    /// 删文件（不存在不报错；非法路径静默忽略，绝不越界删 Documents 外文件）
    static func delete(relativePath: String, fileManager: FileManager = .default) throws {
        guard let url = absoluteURL(for: relativePath, fileManager: fileManager),
              fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    /// 全部视频字节数（存储页用；目录不存在 = 0）
    static func totalBytes(fileManager: FileManager = .default) -> Int64 {
        guard let dir = absoluteURL(for: "videos", fileManager: fileManager),
              let enumerator = fileManager.enumerator(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
              ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    private static func documentsURL(fileManager: FileManager) -> URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    }
}

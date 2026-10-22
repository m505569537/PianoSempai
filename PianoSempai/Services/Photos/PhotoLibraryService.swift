import Foundation
import Photos
import UIKit

// 相册「读」能力（ADR-0012 / S17）：只在你主动导入 Zf 月度录像时读取。
// 与 PhotoLibraryWriter（add-only 写回）相反：这里请求 .readWrite（含受限访问），
// 不请求 .addOnly；不枚举整库、不上传、不修改相册。

/// 相册资产元数据（只读快照；缺失字段保持 nil / 0，由上层决定是否禁用）
struct ZFAssetMetadata: Equatable, Sendable {
    let assetIdentifier: String
    let creationDate: Date?
    let durationSec: Double
    let pixelWidth: Int
    let pixelHeight: Int
}

enum PhotoLibraryError: Error, Equatable {
    case denied
    case notFound
    case iCloudUnavailable
    case exportFailed(String)
    case cancelled
}

/// 「读」权限档位（S17 候选口径，ADR-0012 补充）：
/// full = 可枚举最近视频；limited = 只能访问用户勾选的项（走 PhotosPicker，不伪造列表）；
/// denied = 空态 + 去系统设置。
enum PhotoLibraryAccess: Equatable, Sendable {
    case full
    case limited
    case denied
}

protocol PhotoLibraryAccessing: AnyObject {
    /// 请求「读」权限（.readWrite 会弹受限访问）；返回是否可用于读取
    func requestReadAccess() async -> Bool
    /// 当前「读」权限档位（决定 S17 是枚举最近视频还是走 picker）
    func accessLevel() -> PhotoLibraryAccess
    /// 已选资产的元数据（creationDate/duration/分辨率）；受限访问下只对已选 asset 有效
    func metadata(forIdentifiers ids: [String]) async -> [String: ZFAssetMetadata]
    /// 最近视频（.video，按拍摄时间倒序，最多 limit 条）；仅 full 权限有真实内容
    func recentVideos(limit: Int) async -> [ZFAssetMetadata]
    /// 候选行缩略图（maxPixelSize 为像素边长的近似值；取不到返回 nil）
    func thumbnail(forIdentifier id: String, maxPixelSize: CGFloat) async -> UIImage?
    /// 把原片导出到临时目录（触发 iCloud 下载），progress 0...1，支持取消
    func exportOriginal(identifier: String,
                        to directory: URL,
                        progress: (@Sendable (Double) -> Void)?) async throws -> URL
}

final class PhotoLibraryService: PhotoLibraryAccessing {

    /// `.authorized` 与 `.limited` 都可用于读取；`.addOnly` 永不请求（ADR-0012 红线）
    func requestReadAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// 同步读当前档位（requestReadAccess 之后调用；.restricted / .notDetermined 视为 denied）
    func accessLevel() -> PhotoLibraryAccess {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized:
            return .full
        case .limited:
            return .limited
        default:
            return .denied
        }
    }

    /// 最近视频（.video，creationDate 倒序）。full 权限下才真正有内容；
    /// limited 下由系统只暴露已勾选项，S17 仍按 ADR 走 picker，不调用本方法伪造列表。
    func recentVideos(limit: Int) async -> [ZFAssetMetadata] {
        guard limit > 0 else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        let assets = PHAsset.fetchAssets(with: .video, options: options)
        var result: [ZFAssetMetadata] = []
        result.reserveCapacity(min(limit, assets.count))
        assets.enumerateObjects { asset, index, stop in
            guard index < limit else {
                stop.pointee = true
                return
            }
            result.append(Self.metadata(for: asset))
        }
        return result
    }

    /// 64×44 候选行的缩略图（按像素目标尺寸请求；iCloud 项允许拉取小图）
    func thumbnail(forIdentifier id: String, maxPixelSize: CGFloat) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let state = ThumbnailRequestState(continuation)
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: maxPixelSize, height: maxPixelSize),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // degraded 先到、final 后到：只认非 degraded（或取消/失败）的那次
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                state.finish(image)
            }
        }
    }

    /// 批量取元数据；取不到的 asset 不出现在结果里（调用方按「无法读取」处理）
    func metadata(forIdentifiers ids: [String]) async -> [String: ZFAssetMetadata] {
        guard !ids.isEmpty else { return [:] }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var result: [String: ZFAssetMetadata] = [:]
        result.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            result[asset.localIdentifier] = Self.metadata(for: asset)
        }
        return result
    }

    private static func metadata(for asset: PHAsset) -> ZFAssetMetadata {
        ZFAssetMetadata(
            assetIdentifier: asset.localIdentifier,
            creationDate: asset.creationDate,
            durationSec: asset.duration,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight
        )
    }

    /// 原片字节复制（不转码）：优先 .fullSizeVideo（编辑过的原片），否则 .video。
    /// iCloud 未下载的项以 networkAccessAllowed 触发下载并回报进度。
    func exportOriginal(identifier: String,
                        to directory: URL,
                        progress: (@Sendable (Double) -> Void)?) async throws -> URL {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            throw PhotoLibraryError.notFound
        }
        guard let resource = Self.originalVideoResource(for: asset) else {
            throw PhotoLibraryError.notFound
        }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw PhotoLibraryError.exportFailed(error.localizedDescription)
        }

        let ext = (resource.originalFilename as NSString).pathExtension
        let destination = directory.appendingPathComponent(
            "zf-export-\(UUID().uuidString).\(ext.isEmpty ? "mov" : ext)"
        )

        let state = ExportRequestState()
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    state.attach(continuation)

                    let options = PHAssetResourceRequestOptions()
                    options.isNetworkAccessAllowed = true // iCloud 未下载项自动下载（ADR-0012 第 5 条）
                    options.progressHandler = { fraction in
                        progress?(fraction)
                        // writeData 不返回 request id（SDK 只能 cancel requestData），
                        // 取消由 withTaskCancellationHandler 统一处理；这里只负责尽快收尾。
                        if state.isCancelled {
                            state.fail(.cancelled)
                        }
                    }

                    PHAssetResourceManager.default().writeData(
                        for: resource,
                        toFile: destination,
                        options: options
                    ) { error in
                        if state.isCancelled {
                            state.fail(.cancelled)
                        } else if let error {
                            state.fail(Self.mapExportError(error))
                        } else {
                            state.succeed()
                        }
                        // 取消后迟到的完成回调：再清一次可能被重建的半成品
                        if state.isCancelled {
                            try? FileManager.default.removeItem(at: destination)
                        }
                    }
                }
            } onCancel: {
                state.cancel()
            }
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }

        progress?(1.0)
        return destination
    }

    // MARK: - 私有

    /// 原片资源：.fullSizeVideo（有编辑时保留原始画面）优先，其次 .video
    private static func originalVideoResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first { $0.type == .fullSizeVideo }
            ?? resources.first { $0.type == .video }
    }

    private static func mapExportError(_ error: Error) -> PhotoLibraryError {
        let nsError = error as NSError
        if nsError.domain == PHPhotosErrorDomain {
            switch PHPhotosError.Code(rawValue: nsError.code) {
            case .networkAccessRequired, .networkError, .libraryVolumeOffline:
                return .iCloudUnavailable
            case .userCancelled:
                return .cancelled
            case .identifierNotFound, .missingResource:
                return .notFound
            default:
                return .exportFailed(nsError.localizedDescription)
            }
        }
        if nsError.domain == NSURLErrorDomain {
            return .iCloudUnavailable
        }
        return .exportFailed(nsError.localizedDescription)
    }
}

/// PHImageManager.requestImage 的完成状态（degraded/final/取消都可能回调；continuation 只 resume 一次）
private final class ThumbnailRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var finished = false

    init(_ continuation: CheckedContinuation<UIImage?, Never>) {
        self.continuation = continuation
    }

    func finish(_ image: UIImage?) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: image)
    }
}

/// PHAssetResourceManager.writeData 的完成/取消状态（回调在任意串行队列，用锁保护；
/// continuation 只允许 resume 一次）。
private final class ExportRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func attach(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if cancelled {
            finished = true
            lock.unlock()
            continuation.resume(throwing: PhotoLibraryError.cancelled)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: PhotoLibraryError.cancelled)
    }

    func succeed() { finish(nil) }

    func fail(_ error: PhotoLibraryError) { finish(error) }

    private func finish(_ error: PhotoLibraryError?) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }
}

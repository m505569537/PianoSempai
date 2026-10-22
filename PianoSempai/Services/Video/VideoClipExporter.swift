import AVFoundation
import Foundation

// 片段导出（ADR-0011）：AVAssetExportSession 裁切 + 转 720p H.264 mp4 到临时目录。
// 原录像不覆盖、不降质保存；产物由调用方在发送结束（成功/取消/失败）后删除。
//
// 本类的 AVFoundation 路径不做单测（真编码器耗时且依赖系统）；可测逻辑（区间校验、
// 热点→时间换算）在 ClipWindowMapper。clipDuration 作为 seam 注入，仅用于区间校验。

enum VideoClipExportError: Error, Equatable {
    /// 区间非法（end <= start / start < 0 / end 超出时长 + 0.05s）
    case invalidRange
    /// 读不到源视频时长（文件缺失/非视频）
    case assetUnreadable
    /// 系统没有可用的 720p 导出器
    case exportUnavailable
    /// 导出失败（原因短句）
    case exportFailed(String)
    case cancelled

    var summary: String {
        switch self {
        case .invalidRange: return "裁切区间不合法"
        case .assetUnreadable: return "读不到视频时长"
        case .exportUnavailable: return "系统无法导出 720p 视频"
        case .exportFailed(let detail): return "视频裁切失败：\(detail)"
        case .cancelled: return "视频裁切已取消"
        }
    }
}

protocol VideoClipExporting: AnyObject {
    /// 裁切 + 转 720p H.264 mp4 到临时目录；返回临时文件 URL（调用方负责删）
    func exportClip(source: URL, startSec: Double, endSec: Double) async throws -> URL
}

final class AVFoundationClipExporter: VideoClipExporting {
    private let fileManager: FileManager
    /// 源视频时长（秒）；测试可注入，生产走 AVAsset.load(.duration)
    private let clipDuration: (URL) async -> Double?

    init(
        fileManager: FileManager = .default,
        clipDuration: @escaping (URL) async -> Double? = AVFoundationClipExporter.assetDuration
    ) {
        self.fileManager = fileManager
        self.clipDuration = clipDuration
    }

    static func assetDuration(_ url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.isNumeric else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    func exportClip(source: URL, startSec: Double, endSec: Double) async throws -> URL {
        guard startSec >= 0, endSec > startSec else {
            throw VideoClipExportError.invalidRange
        }
        guard let duration = await clipDuration(source), duration > 0 else {
            throw VideoClipExportError.assetUnreadable
        }
        // 允许 50ms 内的尾部溢出并钳制；再大就是调用方算错了
        guard endSec <= duration + 0.05 else {
            throw VideoClipExportError.invalidRange
        }
        let clampedEnd = min(endSec, duration)
        guard clampedEnd > startSec else {
            throw VideoClipExportError.invalidRange
        }

        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw VideoClipExportError.exportUnavailable
        }

        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("clips", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw VideoClipExportError.exportFailed("无法创建临时目录")
        }
        let outputURL = directory.appendingPathComponent("\(UUID().uuidString).mp4")

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        // 时间轴用 600 时基（1/600 秒），避免浮点秒直接进 CMTime 的舍入抖动
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: startSec, preferredTimescale: 600),
            duration: CMTime(seconds: clampedEnd - startSec, preferredTimescale: 600)
        )

        do {
            try await Self.export(session)
        } catch {
            try? fileManager.removeItem(at: outputURL)
            throw error
        }
        return outputURL
    }

    /// 桥接回调式导出（部署目标 iOS 17；新 async 导出 API 要 iOS 18）。
    /// 取消时 cancelExport，并把 CancellationError 传出去。
    private static func export(_ session: AVAssetExportSession) async throws {
        // AVAssetExportSession 非 Sendable；导出期间只在 Apple 的回调队列/取消路径上访问，
        // 用 box 承载以通过 @Sendable 闭包的捕获检查。
        let box = ExportSessionBox(session)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                box.session.exportAsynchronously {
                    switch box.session.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: VideoClipExportError.cancelled)
                    default:
                        let detail = box.session.error?.localizedDescription ?? "未知原因"
                        continuation.resume(throwing: VideoClipExportError.exportFailed(detail))
                    }
                }
            }
        } onCancel: {
            box.session.cancelExport()
        }
    }
}

/// 仅用于把 AVAssetExportSession 跨进 @Sendable 闭包；不暴露给本文件以外。
private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

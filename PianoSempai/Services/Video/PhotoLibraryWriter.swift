import Foundation
import Photos

// 保存成功后 add-only 写一份进系统相册（PRD 299）：失败或被拒静默跳过，绝不打断保存。

protocol PhotoLibraryWriting: AnyObject {
    func saveVideo(at url: URL) async -> Bool
}

final class PhotoLibraryWriter: PhotoLibraryWriting {

    func saveVideo(at url: URL) async -> Bool {
        // 只请求写入权限；不请求、不读取相册
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            return true
        } catch {
            return false
        }
    }
}

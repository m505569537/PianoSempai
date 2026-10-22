import AVFoundation
import Foundation

// 录像状态机 + AVFoundation 真实现（ADR-0010 / PRD M8b）。
// 与练习会话同起同停；任一路失败只落已有的一半。

enum VideoRecordingState: Equatable {
    case idle
    case preparing
    case recording(startedAt: Date)
    case failed(VideoRecordingError)
}

enum VideoRecordingError: Error, Equatable {
    case cameraUnavailable
    case permissionDenied
    case configurationFailed(String)
    case startFailed(String)
    case stopFailed(String)
}

struct VideoRecordingResult: Equatable {
    let relativePath: String
    let durationSec: Int
    let startedAt: Date
}

protocol VideoRecording: AnyObject {
    var state: VideoRecordingState { get }
    var onStateChange: ((VideoRecordingState) -> Void)? { get set }
    func start(now: Date) async throws
    func stop() async -> VideoRecordingResult?
}

/// 真实现：AVCaptureSession + AVCaptureMovieFileOutput（1080p / H.264 / 现场音轨）。
/// 线程模型：session 操作全在私有串行队列；state 由内部锁保护，onStateChange 统一切回主线程。
/// @unchecked Sendable：全部可变状态都在 lock 或 sessionQueue 下访问，无并发裸读。
final class AVFoundationVideoRecorder: NSObject, VideoRecording,
                                        AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {

    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "com.eeexu.pianosempai.video-recording")

    private let lock = NSLock()
    private var storedState: VideoRecordingState = .idle
    private var stateHandler: ((VideoRecordingState) -> Void)?
    private var pendingStart: CheckedContinuation<Void, Error>?
    private var pendingStop: CheckedContinuation<VideoRecordingResult?, Never>?
    private var recordingStartedAt: Date?
    private var recordingURL: URL?
    private var recordingRelativePath: String?
    /// 仅 sessionQueue 访问
    private var sessionConfigured = false

    var state: VideoRecordingState {
        lock.lock()
        defer { lock.unlock() }
        return storedState
    }

    var onStateChange: ((VideoRecordingState) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stateHandler
        }
        set {
            lock.lock()
            stateHandler = newValue
            lock.unlock()
        }
    }

    // MARK: - 生命周期

    func start(now: Date) async throws {
        switch state {
        case .recording:
            throw VideoRecordingError.startFailed("已在录像")
        case .preparing:
            throw VideoRecordingError.startFailed("正在准备")
        default:
            break
        }

        setState(.preparing)

        do {
            try await requestCameraAccess()
        } catch {
            let failure = error as? VideoRecordingError ?? .permissionDenied
            setState(.failed(failure))
            throw failure
        }

        // 麦克风无权限 → 静音视频，不失败
        let micGranted = await requestMicrophoneAccess()

        let fileURL: URL
        let relativePath: String
        do {
            fileURL = try VideoStore.makeFileURL(now: now)
            guard let path = VideoStore.relativePath(for: fileURL) else {
                throw VideoRecordingError.configurationFailed("视频路径不在 Documents 下")
            }
            relativePath = path
        } catch {
            let failure = error as? VideoRecordingError ?? .configurationFailed("无法创建视频文件")
            setState(.failed(failure))
            throw failure
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: VideoRecordingError.startFailed("录制器已释放"))
                    return
                }
                do {
                    try self.configureSession(micGranted: micGranted)
                    try self.startSession()
                } catch {
                    try? FileManager.default.removeItem(at: fileURL)
                    let failure = (error as? VideoRecordingError)
                        ?? .configurationFailed(error.localizedDescription)
                    self.setState(.failed(failure))
                    continuation.resume(throwing: failure)
                    return
                }

                self.lock.lock()
                self.pendingStart = continuation
                self.recordingStartedAt = now
                self.recordingURL = fileURL
                self.recordingRelativePath = relativePath
                self.lock.unlock()

                self.movieOutput.startRecording(to: fileURL, recordingDelegate: self)
            }
        }
    }

    func stop() async -> VideoRecordingResult? {
        await withCheckedContinuation { (continuation: CheckedContinuation<VideoRecordingResult?, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }

                guard self.movieOutput.isRecording else {
                    // 未真正开始（或已停止）：清理半成品，绝不留悬挂 continuation
                    self.lock.lock()
                    let startContinuation = self.pendingStart
                    self.pendingStart = nil
                    let leftoverURL = self.recordingURL
                    self.recordingURL = nil
                    self.recordingStartedAt = nil
                    self.recordingRelativePath = nil
                    self.lock.unlock()

                    if let leftoverURL {
                        try? FileManager.default.removeItem(at: leftoverURL)
                    }
                    startContinuation?.resume(throwing: VideoRecordingError.startFailed("录像在开始前被停止"))
                    self.setState(.idle)
                    continuation.resume(returning: nil)
                    return
                }

                self.lock.lock()
                self.pendingStop = continuation
                self.lock.unlock()
                self.movieOutput.stopRecording()
            }
        }
    }

    // MARK: - 权限

    private func requestCameraAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) { return }
            throw VideoRecordingError.permissionDenied
        case .denied, .restricted:
            throw VideoRecordingError.permissionDenied
        @unknown default:
            throw VideoRecordingError.permissionDenied
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    // MARK: - 会话（sessionQueue）

    private func configureSession(micGranted: Bool) throws {
        if sessionConfigured { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }

        // 模拟器无摄像头：诚实失败，绝不崩
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            throw VideoRecordingError.cameraUnavailable
        }
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            throw VideoRecordingError.configurationFailed("视频输入不可用")
        }
        guard session.canAddInput(videoInput) else {
            throw VideoRecordingError.configurationFailed("无法添加视频输入")
        }
        session.addInput(videoInput)

        if micGranted, let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        guard session.canAddOutput(movieOutput) else {
            throw VideoRecordingError.configurationFailed("无法添加录像输出")
        }
        session.addOutput(movieOutput)

        if let connection = movieOutput.connection(with: .video) {
            // H.264：下一批 V3 可直接上传，不必转码
            if movieOutput.availableVideoCodecTypes.contains(.h264) {
                movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: connection)
            }
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }

        sessionConfigured = true
    }

    private func startSession() throws {
        if !session.isRunning {
            session.startRunning()
        }
        guard session.isRunning else {
            throw VideoRecordingError.startFailed("相机会话未能启动")
        }
    }

    /// 录像结束即熄屏关镜头（「视频镜头不常开」）：阻塞调用放回队列，避免卡住回调线程
    private func stopSessionAsync() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        lock.lock()
        let continuation = pendingStart
        pendingStart = nil
        let startedAt = recordingStartedAt ?? Date()
        lock.unlock()

        continuation?.resume()
        setState(.recording(startedAt: startedAt))
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        lock.lock()
        let continuation = pendingStop
        pendingStop = nil
        let startedAt = recordingStartedAt
        let relativePath = recordingRelativePath
        recordingStartedAt = nil
        recordingURL = nil
        recordingRelativePath = nil
        lock.unlock()

        stopSessionAsync()

        if let error = error as NSError? {
            let finishedOK = (error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
            if !finishedOK {
                try? FileManager.default.removeItem(at: outputFileURL)
                setState(.failed(.stopFailed(error.localizedDescription)))
                continuation?.resume(returning: nil)
                return
            }
        }

        setState(.idle)

        guard let continuation, let startedAt, let relativePath else {
            // 无等待者（异常路径）：不留半成品
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }

        Task {
            let result = await Self.validatedResult(
                fileURL: outputFileURL, relativePath: relativePath, startedAt: startedAt
            )
            continuation.resume(returning: result)
        }
    }

    /// 文件缺失 / 零字节 / 时长 < 1s 一律判不可用并删除
    private static func validatedResult(fileURL: URL, relativePath: String,
                                        startedAt: Date) async -> VideoRecordingResult? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return nil }

        let attributes = try? fm.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else {
            try? fm.removeItem(at: fileURL)
            return nil
        }

        let asset = AVURLAsset(url: fileURL)
        guard let duration = try? await asset.load(.duration) else {
            try? fm.removeItem(at: fileURL)
            return nil
        }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds >= 1 else {
            try? fm.removeItem(at: fileURL)
            return nil
        }
        return VideoRecordingResult(
            relativePath: relativePath,
            durationSec: max(1, Int(seconds.rounded())),
            startedAt: startedAt
        )
    }

    // MARK: - 状态

    private func setState(_ newState: VideoRecordingState) {
        lock.lock()
        if storedState == newState {
            lock.unlock()
            return
        }
        storedState = newState
        let handler = stateHandler
        lock.unlock()

        guard let handler else { return }
        if Thread.isMainThread {
            handler(newState)
        } else {
            DispatchQueue.main.async { handler(newState) }
        }
    }
}

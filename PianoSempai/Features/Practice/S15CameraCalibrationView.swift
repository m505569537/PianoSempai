import AVFoundation
import SwiftUI
import UIKit

// MARK: - S15 机位校准（4 步：摆放 / 取景 / 试录 / 完成）
// 真值：docs/design-reference/screens/S15-camera-calibration/spec.md。
// 本批只做「真实预览 + 静态取景框 + 提示 + 试录」：骨架层、检测 chips、观察卡一律不画
// （无数据源，ADR-0010 / PRD M8b 明确禁止造假）。
// 有意新增（spec 无）：左上 ✕ 退出——没有退出入口的话进屏即死路。
// 试录文件是校准产物，离屏即删；它不挂 Take，也不进保留规则。

struct S15CameraCalibrationView: View {
    let recorder: AVFoundationVideoRecorder
    /// true = 机位已确认（退回练习室后 armed）；false = 用户跳过录像
    var onFinish: (Bool) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    @State private var step: CalibrationStep = .place
    @State private var previewSession: AVCaptureSession?
    @State private var prepareFailure: VideoRecordingError?
    @State private var isPreparing = true

    @State private var isTestRecording = false
    @State private var testResult: VideoRecordingResult?
    @State private var testErrorText: String?
    @State private var testPlayer: AVPlayer?
    @State private var isTestPlaying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                stepIndicator.padding(.top, 4)
                titleBlock.padding(.top, 16)
                mediaCard.padding(.top, 16)
                if let testErrorText {
                    Text(testErrorText)
                        .font(.bodySm)
                        .foregroundStyle(Color.danger)
                        .padding(.top, 8)
                }
                if step == .done {
                    doneCard.padding(.top, 14)
                } else {
                    tipsCard.padding(.top, 14)
                }
                disclaimerCard.padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .bottom) {
            if prepareFailure == nil {
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .task { await prepare() }
        .onChange(of: step) { _, newValue in
            if newValue == .test { runTestRecording() }
        }
        .onDisappear { teardown() }
    }

    // MARK: 顶部

    private var topBar: some View {
        HStack {
            Button {
                finish(armed: false)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textMuted)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.04), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("退出机位校准")

            Spacer(minLength: 0)
        }
    }

    // MARK: 4 步进度

    private enum StepVisual { case done, current, future }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(CalibrationStep.allCases, id: \.rawValue) { item in
                stepDot(item)
                if let next = item.next() {
                    Rectangle()
                        .fill(Color.border)
                        .frame(width: 24, height: 1)
                        .accessibilityHidden(true)
                        .id(next.rawValue)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func visual(for item: CalibrationStep) -> StepVisual {
        if item.rawValue < step.rawValue { return .done }
        if item.rawValue == step.rawValue { return .current }
        return .future
    }

    private func stepDot(_ item: CalibrationStep) -> some View {
        let state = visual(for: item)
        return HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(state == .current ? Color.amber : Color.clear)
                Circle()
                    .strokeBorder(dotBorder(state), lineWidth: 1)
                if state == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.amber)
                } else {
                    Text("\(item.rawValue + 1)")
                        .font(.system(size: 9, weight: state == .current ? .bold : .medium))
                        .foregroundStyle(state == .current ? Color.canvas : Color.textMuted)
                }
            }
            .frame(width: 16, height: 16)
            .shadow(color: state == .current ? Color.amber.opacity(0.35) : .clear, radius: 4)

            Text(item.title)
                .font(.labelSm)
                .foregroundStyle(state == .current ? Color.textPrimary : Color.textMuted)
        }
        .opacity(state == .future ? 0.4 : (state == .done ? 0.6 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(item.rawValue + 1) 步 \(item.title)")
    }

    private func dotBorder(_ state: StepVisual) -> Color {
        switch state {
        case .done: return Color.amber.opacity(0.5)
        case .current: return Color.clear
        case .future: return Color.textMuted.opacity(0.6)
        }
    }

    // MARK: 标题

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("让手机能看到你的手")
                .font(.headlineLg)
                .foregroundStyle(Color.textPrimary)
            Text("你只需要跟着画面挪手机，不用记任何规则。")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
        }
        .padding(.horizontal, 4)
    }

    // MARK: 预览 / 试录回放 / 不可用卡

    @ViewBuilder
    private var mediaCard: some View {
        if let failure = prepareFailure {
            errorCard(failure)
        } else if let testPlayer, testResult != nil, step == .test || step == .done {
            testPlaybackCard(player: testPlayer)
        } else {
            livePreviewCard
        }
    }

    private var livePreviewCard: some View {
        ZStack {
            Color.surface
            if let previewSession {
                CameraPreviewLayerView(session: previewSession)
            } else if isPreparing {
                Text("正在准备相机…")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
            }
            framingOverlay
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
        .overlay(alignment: .bottom) {
            if isTestRecording {
                Text("正在试录 5 秒，请保持手在框内")
                    .font(.labelSm)
                    .foregroundStyle(Color.amber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.surface.opacity(0.9), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.amber.opacity(0.5), lineWidth: 1))
                    .padding(.bottom, 10)
            }
        }
    }

    /// 静态取景框：虚线框 + 四角 L 形角标 + 中置「手部区域」
    private var framingOverlay: some View {
        GeometryReader { _ in
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        Color.amber.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
                cornerMarks
                Text("手部区域")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(Color.amber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.canvas.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.amber.opacity(0.25), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 48)
        }
        .allowsHitTesting(false)
    }

    private var cornerMarks: some View {
        ZStack {
            FrameCornerMark(rotation: .degrees(0))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            FrameCornerMark(rotation: .degrees(90))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            FrameCornerMark(rotation: .degrees(180))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            FrameCornerMark(rotation: .degrees(270))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }

    private func testPlaybackCard(player: AVPlayer) -> some View {
        ZStack {
            Color.surface
            VideoSurfaceView(player: player)
                .contentShape(Rectangle())
                .onTapGesture { toggleTestPlayback() }
            Button {
                toggleTestPlayback()
            } label: {
                Image(systemName: isTestPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.4), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
        .overlay(alignment: .bottomLeading) {
            Text("刚才的 5 秒试录")
                .font(.system(size: 10))
                .foregroundStyle(Color.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.surface.opacity(0.9), in: Capsule())
                .padding(10)
        }
    }

    private func errorCard(_ failure: VideoRecordingError) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "video.slash")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.amber)
                Text("相机不可用")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
            }
            Text(errorMessage(failure))
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .lineSpacing(4)
            HStack(spacing: 10) {
                Button {
                    openSystemSettings()
                } label: {
                    Text("去系统设置")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    finish(armed: false)
                } label: {
                    Text("跳过录像")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.canvas)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.amber, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
    }

    private func errorMessage(_ failure: VideoRecordingError) -> String {
        switch failure {
        case .permissionDenied:
            return "相机权限被关闭了。可在「设置 › PianoSempai › 相机」里打开，再回来重新校准。也可以跳过录像，照常练琴。"
        case .cameraUnavailable:
            return "这台设备没有可用的相机（模拟器没有摄像头）。可以跳过录像，照常练琴。"
        case let .configurationFailed(detail):
            return "相机没能准备好（\(detail)）。可以跳过录像，照常练琴。"
        case let .startFailed(detail):
            return "录像没能启动（\(detail)）。可以跳过录像，照常练琴。"
        case let .stopFailed(detail):
            return "录像没能结束（\(detail)）。可以跳过录像，照常练琴。"
        }
    }

    // MARK: 提示卡 / 免责卡 / 完成卡

    private var tipsCard: some View {
        VStack(spacing: 0) {
            tipRow(icon: "video.fill", text: "手机架在琴右侧，镜头朝键盘")
            tipDivider
            tipRow(icon: "book.closed", text: "不用买支架，靠在谱架上就行")
            tipDivider
            tipRow(icon: "timer", text: "每次校准 30 秒，只在你主动录像时需要")
        }
        .padding(.horizontal, 12)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.amber)
                .frame(width: 24, height: 24)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.border, lineWidth: 1))
            Text(text)
                .font(.bodySm)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private var tipDivider: some View {
        Rectangle()
            .fill(Color.border.opacity(0.6))
            .frame(height: 1)
    }

    private var disclaimerCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 15))
                .foregroundStyle(Color.amber.opacity(0.8))
            Text("单个摄像头有死角：手掌遮挡、触键深度永远无法判断，手型建议不会影响过关。")
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.amber.opacity(0.2), lineWidth: 1))
    }

    private var doneCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("机位已记住")
                .font(.headlineSm)
                .foregroundStyle(Color.textPrimary)
            Text("点「完成」回到练习室；录像只在你按下开始练习时启动。")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
    }

    // MARK: 底部双按钮

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                skipAction()
            } label: {
                Text(ghostTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                primaryAction()
            } label: {
                Text(primaryTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.canvas)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.amber.opacity(primaryEnabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color.amber.opacity(0.25), radius: 8)
            }
            .buttonStyle(.plain)
            .disabled(!primaryEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(Color.canvas)
    }

    private var ghostTitle: String {
        switch step {
        case .place, .frame: "跳过，直接试录"
        case .test, .done: "跳过录像"
        }
    }

    private var primaryTitle: String {
        switch step {
        case .place: return "按建议调整"
        case .frame: return "开始试录"
        case .test:
            if isTestRecording { return "试录中…" }
            return testResult == nil ? "重新试录" : "继续"
        case .done: return "完成"
        }
    }

    private var primaryEnabled: Bool {
        !(step == .test && isTestRecording)
    }

    private func primaryAction() {
        switch step {
        case .place:
            step = .frame
        case .frame:
            step = .test
        case .test:
            if testResult == nil {
                runTestRecording()
            } else {
                step = .done
            }
        case .done:
            finish(armed: true)
        }
    }

    private func skipAction() {
        switch step {
        case .place, .frame:
            step = .test
        case .test, .done:
            finish(armed: false)
        }
    }

    // MARK: 预览与试录

    private func prepare() async {
        isPreparing = true
        do {
            try await recorder.preparePreview()
            previewSession = recorder.previewSession
            prepareFailure = nil
        } catch {
            prepareFailure = (error as? VideoRecordingError) ?? .cameraUnavailable
            previewSession = nil
        }
        isPreparing = false
    }

    private func runTestRecording() {
        guard !isTestRecording else { return }
        isTestRecording = true
        testErrorText = nil
        testResult = nil
        testPlayer?.pause()
        testPlayer = nil
        isTestPlaying = false

        Task { @MainActor in
            do {
                if case .recording = recorder.state {
                    _ = await recorder.stop()
                }
                try await recorder.start(now: Date())
                try? await Task.sleep(for: .seconds(5))
                let result = await recorder.stop()
                isTestRecording = false
                if let result {
                    testResult = result
                    if let url = VideoStore.absoluteURL(for: result.relativePath) {
                        testPlayer = AVPlayer(url: url)
                    }
                } else {
                    testErrorText = "这次试录没有保存成功，可以再试一次。"
                }
            } catch {
                isTestRecording = false
                testErrorText = "试录没能开始，检查相机权限后再试。"
            }
        }
    }

    private func toggleTestPlayback() {
        guard let testPlayer else { return }
        if isTestPlaying {
            testPlayer.pause()
            isTestPlaying = false
        } else {
            if let duration = testPlayer.currentItem?.duration.seconds,
               duration.isFinite,
               testPlayer.currentTime().seconds >= duration - 0.1 {
                testPlayer.seek(to: .zero)
            }
            testPlayer.play()
            isTestPlaying = true
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func finish(armed: Bool) {
        onFinish(armed)
        dismiss()
    }

    private func teardown() {
        testPlayer?.pause()
        testPlayer = nil
        isTestPlaying = false
        if let result = testResult, let url = VideoStore.absoluteURL(for: result.relativePath) {
            try? FileManager.default.removeItem(at: url) // 试录是校准产物，不挂 take、不留盘
        }
        testResult = nil

        if case .recording = recorder.state {
            let recorder = self.recorder
            Task { @MainActor in
                if let result = await recorder.stop(),
                   let url = VideoStore.absoluteURL(for: result.relativePath) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        recorder.endPreview()
    }
}

// MARK: - 预览层 / 播放层（真实相机画面与真实视频，无假图）

private struct CameraPreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}

private final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private struct VideoSurfaceView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

private final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// 取景框四角 L 形角标（14×14、2pt 实心琥珀）
private struct FrameCornerMark: View {
    let rotation: Angle

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 14))
            path.addLine(to: .zero)
            path.addLine(to: CGPoint(x: 14, y: 0))
        }
        .stroke(Color.amber, style: StrokeStyle(lineWidth: 2, lineCap: .square))
        .frame(width: 14, height: 14)
        .rotationEffect(rotation)
    }
}

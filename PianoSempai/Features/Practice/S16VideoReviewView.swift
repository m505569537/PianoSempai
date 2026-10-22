import AVFoundation
import SwiftData
import SwiftUI

// MARK: - S16 侧拍回看
// 真值：docs/design-reference/screens/S16-video-review/spec.md。
// 本批只有播放器 + 头部 + 动作：骨架叠加、观察卡（含置信度）、「问 Neko」一律不画
// （视频上传链路未做、也无手型数据源；ADR-0010 明确禁止造假）。
// 本页不产生任何过关/分数写入。

struct S16VideoReviewView: View {
    let take: Take
    /// 顶栏标题（曲名）；空则用「录像回看」
    var displayTitle: String = ""
    /// 「重新校准」：本页先关自己，再交给调用方打开 S15
    var onRecalibrate: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var isPlaying = false
    @State private var playbackError = false
    @State private var showDeleteConfirm = false

    private var headerTitle: String {
        displayTitle.isEmpty ? "录像回看" : displayTitle
    }

    private var subtitle: String {
        let when = take.startedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(when) · \(VideoUIFormatting.timecode(take.videoDurationSec))"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    playerCard
                    disclaimerCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .bottom) { actionsBar }
        .preferredColorScheme(.dark)
        .onAppear { setupPlayer() }
        .onDisappear { teardown() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
            isPlaying = false
            currentTime = 0
            player?.seek(to: .zero)
        }
        .alert("删除这段录像？", isPresented: $showDeleteConfirm) {
            Button("删除录像", role: .destructive) { deleteVideo() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删视频文件；这条 take、MIDI 和报告都会保留。")
        }
    }

    // MARK: 顶栏

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(height: 48)
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.border.opacity(0.4))
                .frame(height: 1)
        }
    }

    // MARK: 播放器

    private var playerCard: some View {
        VStack(spacing: 8) {
            ZStack {
                Color.surface
                if playbackError {
                    VStack(spacing: 6) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.textMuted)
                        Text("找不到这段录像文件")
                            .font(.bodySm)
                            .foregroundStyle(Color.textMuted)
                    }
                } else if let player {
                    PlayerLayerView(player: player)
                        .contentShape(Rectangle())
                        .onTapGesture { togglePlayback() }

                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.4), in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(playbackError)
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            scrubber
        }
        .padding(10)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
    }

    private var scrubber: some View {
        HStack(spacing: 8) {
            Text(VideoUIFormatting.timecode(Int(currentTime)))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.amber)
                .monospacedDigit()

            Slider(
                value: $currentTime,
                in: 0...max(1, duration),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        player?.seek(
                            to: CMTime(seconds: currentTime, preferredTimescale: 600),
                            toleranceBefore: .zero,
                            toleranceAfter: .zero
                        )
                    }
                }
            )
            .tint(Color.amber)
            .disabled(playbackError)

            Text(VideoUIFormatting.timecode(take.videoDurationSec))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.textMuted)
                .monospacedDigit()
        }
    }

    // MARK: 免责卡（逐字保留；本页没有手型结论）

    private var disclaimerCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 16))
                .foregroundStyle(Color.amber)
            Text("手型观察仅供参考，永远不会影响过关；单摄有死角，看不清的我会直接说。")
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.amber.opacity(0.4), lineWidth: 1))
    }

    // MARK: 底部动作

    private var actionsBar: some View {
        HStack(spacing: 10) {
            Button {
                recalibrate()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "tune")
                        .font(.system(size: 13))
                    Text("重新校准")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.amber)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.amber.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                showDeleteConfirm = true
            } label: {
                Text("删除这段录像")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.clear, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.danger.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.canvas)
    }

    // MARK: 行为

    private func setupPlayer() {
        guard let path = take.videoFileURL,
              let url = VideoStore.absoluteURL(for: path),
              FileManager.default.fileExists(atPath: url.path) else {
            playbackError = true
            return
        }
        let player = AVPlayer(url: url)
        self.player = player
        duration = Double(take.videoDurationSec)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { time in
            guard !isScrubbing else { return }
            currentTime = max(0, CMTimeGetSeconds(time))
        }
    }

    private func teardown() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
        player = nil
        isPlaying = false
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            return
        }
        let total = duration > 0 ? duration : Double(take.videoDurationSec)
        if total > 0, currentTime >= total - 0.1 {
            player.seek(to: .zero)
            currentTime = 0
        }
        player.play()
        isPlaying = true
    }

    private func recalibrate() {
        // 先关自己，再让调用方打开 S15（同一帧里 sheet 收起 + cover 弹出会互相打断）
        onRecalibrate?()
        dismiss()
    }

    private func deleteVideo() {
        try? VideoAttachmentStore.deleteVideo(for: take, in: context)
        dismiss()
    }
}

// MARK: - 播放层（真实视频画面）

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerContainerView {
        let view = PlayerLayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = UIColor(Color.surface)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

private final class PlayerLayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

import AVFoundation
import SwiftUI

// S17 候选视频全屏预览（只读本机文件；临时导出文件或已导入归档）。
// 不编辑、不上传、不生成任何新文件。

struct S17PreviewItem: Identifiable, Equatable {
    let id: String
    let url: URL
    let title: String
}

struct ZFVideoPreviewView: View {
    let item: S17PreviewItem

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                ZFPlayerLayerView(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(Color.amber)
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                centerControl
                Spacer()
                Text(item.title)
                    .font(.labelMd)
                    .foregroundStyle(Color.textPrimary.opacity(0.9))
                    .lineLimit(1)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
        }
        .statusBarHidden()
        .onAppear { start() }
        .onDisappear { teardown() }
    }

    private var topBar: some View {
        HStack {
            Text("预览")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Color.card.opacity(0.85), in: Circle())
                    .overlay(Circle().strokeBorder(Color.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭预览")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var centerControl: some View {
        Button {
            toggle()
        } label: {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.textPrimary.opacity(0.9))
                .shadow(color: Color.black.opacity(0.4), radius: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "暂停" : "播放")
    }

    private func start() {
        guard let url = Self.readableURL(item.url) else { return }
        let player = AVPlayer(url: url)
        self.player = player
        player.play()
        isPlaying = true
    }

    private func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if let duration = player.currentItem?.duration.seconds,
               duration.isFinite,
               player.currentTime().seconds >= duration - 0.1 {
                player.seek(to: .zero)
            }
            player.play()
            isPlaying = true
        }
    }

    private func teardown() {
        player?.pause()
        player = nil
        isPlaying = false
    }

    /// 只播真实存在的本机文件（导出失败的半成品/目录一律不播）
    private static func readableURL(_ url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }
        return url
    }
}

// MARK: - 播放层（AVPlayerLayer；与 S16 同构，独立一份避免跨文件依赖私有类型）

private struct ZFPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> ZFPlayerLayerContainerView {
        let view = ZFPlayerLayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: ZFPlayerLayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

private final class ZFPlayerLayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

import AVFoundation
import SwiftUI
import UIKit

// S18b 视频裁切与发送确认（ADR-0011 / spec: docs/design-reference/screens/S18b-video-upload-sheet/spec.md）
//
// 任何视频离开本机前的唯一闸口：选区间 → 核对提问 → 服务商明示 + 云端删除开关 → 确认发送。
// 本 sheet 只负责「裁切/转码/核对/发起发送」；上传、链式故障转移与回答由 ChatStore 完成。
//
// 两处刻意的实现偏差（brief 允许，均比真值更诚实/可用）：
// 1. 真值胶片轨是装饰性波形柱 → 这里用 AVAssetImageGenerator 抽真实帧（不画假波形）。
// 2. 真值播放头只展示 → 这里可拖动（仅移动预览位置，不播放）。
//
// 红线：不显示假进度百分比、不谎称「云端已删除」、不写死服务商名；scrim 不关闭。

// MARK: - 送入 sheet 的数据

/// 从 S16 / 报告页带到 S18b 的真实数据（视频地址、区间换算参数、默认提问）。
struct VideoSendDraft: Identifiable {
    let id = UUID()
    let take: Take
    /// 侧拍源文件（Documents 内解析出的绝对路径；只读）
    let videoURL: URL
    /// 录像总时长（秒）；0 = 未知，sheet 会尝试从 asset 读取
    let durationSec: Double
    /// 录像相对练习起点的偏移（热点小节 → 视频秒数）
    let videoStartedAtOffset: Double
    /// 最新 TakeAnalysis.hotspotMeasures（1-based；空 = 无热点，热点预设置灰）
    let hotspots: [Int]
    let totalMeasures: Int
    let timing: MeasureTiming
    /// 练习实测速度（take.tempoAvg 优先；0 = 算不出 → 热点预设置灰）
    let bpm: Int
    let defaultQuestion: String
    /// 链上第一个支持视频的服务商显示名（运行时读取；nil = 无可用视频服务商）
    let providerName: String?

    /// 热点窗口（用给定视频时长换算；nil = 算不出，热点 chip 置灰）
    func hotspotRange(videoDurationSec: Double) -> ClosedRange<Double>? {
        ClipWindowMapper.window(
            hotspots: hotspots,
            totalMeasures: totalMeasures,
            timing: timing,
            bpm: bpm,
            videoStartedAtOffset: videoStartedAtOffset,
            videoDurationSec: videoDurationSec
        )
    }

    var hotspotRange: ClosedRange<Double>? { hotspotRange(videoDurationSec: durationSec) }

    /// 默认选中：有热点窗口 → 热点 chip；否则整段（≤30s）。绝不造假区间。
    func initialSelection(videoDurationSec: Double? = nil) -> VideoSendInitialSelection {
        let duration = videoDurationSec ?? durationSec
        if let window = hotspotRange(videoDurationSec: duration) {
            return VideoSendInitialSelection(
                preset: .hotspot,
                range: VideoRangeSelection.capped(window, duration: duration)
            )
        }
        return VideoSendInitialSelection(preset: .whole, range: .whole(duration: duration))
    }
}

extension VideoSendDraft {
    /// 从本地真实数据组装；没有视频文件 / 拍号速度算不出时如实降级（不编数据）。
    static func make(
        take: Take,
        analysis: TakeAnalysis?,
        piece: Piece?,
        providers: [AIProvider],
        defaultQuestion: String
    ) -> VideoSendDraft? {
        guard let path = take.videoFileURL, !path.isEmpty,
              let url = VideoStore.absoluteURL(for: path),
              FileManager.default.fileExists(atPath: url.path) else { return nil }

        let hotspots = analysis?.hotspotMeasures ?? []
        // 曲目总小节优先；没有曲目元数据时至少允许热点后扩 2 小节（视频时长仍会钳制）
        let totalMeasures = max(piece?.totalMeasures ?? 0, take.measureTo ?? 0, (hotspots.max() ?? 0) + 2)
        let bpm = take.tempoAvg > 0 ? take.tempoAvg : (piece?.referenceTempo ?? 0)

        return VideoSendDraft(
            take: take,
            videoURL: url,
            durationSec: Double(max(0, take.videoDurationSec)),
            videoStartedAtOffset: take.videoStartedAtOffset,
            hotspots: hotspots,
            totalMeasures: totalMeasures,
            // 数据里没有真实拍号来源 → 4/4（不猜 3/4）
            timing: MeasureTiming(beats: 4, beatUnit: 4),
            bpm: bpm,
            defaultQuestion: defaultQuestion,
            providerName: VideoProviderResolver.firstVideoCapableName(from: providers)
        )
    }
}

/// 链上第一个支持视频输入的服务商显示名（运行时读取，绝不写死）。
enum VideoProviderResolver {
    static func firstVideoCapableName(from providers: [AIProvider]) -> String? {
        ProviderChainLogic.ordered(providers)
            .first { provider in
                provider.enabled
                    && ProviderChainLogic.hasModels(provider)
                    && ProviderChainRunner.supportsVideo(provider: provider)
            }
            .map { $0.displayName.isEmpty ? $0.providerId : $0.displayName }
    }
}

// MARK: - 区间选择（纯逻辑，可单测）

/// 视频内的裁切区间：2–30 秒，拖动钳制到对侧手柄与视频时长。
struct VideoRangeSelection: Equatable {
    static let minLength: Double = 2
    static let maxLength: Double = 30

    private(set) var start: Double
    private(set) var end: Double
    let duration: Double

    init(start: Double, end: Double, duration: Double) {
        let total = max(0, duration)
        self.duration = total
        let lower = min(max(0, start), total)
        self.start = lower
        self.end = min(max(lower, end), total)
    }

    var length: Double { max(0, end - start) }
    var isValid: Bool { length >= Self.minLength - 1e-9 }
    /// 拖手柄后长度合法的判定（<2s 时显示行内红字并禁用 CTA）
    var showsTooShortError: Bool { !isValid && duration >= Self.minLength }

    /// 拖动左手柄：保持区间 ≥2s、≤30s。
    mutating func moveStart(to proposed: Double) {
        let lower = max(0, end - Self.maxLength)
        let upper = max(lower, end - Self.minLength)
        start = min(max(proposed, lower), upper)
    }

    /// 拖动右手柄：保持区间 ≥2s、≤30s，且不超过视频时长。
    mutating func moveEnd(to proposed: Double) {
        let upper = min(duration, start + Self.maxLength)
        let lower = min(upper, start + Self.minLength)
        end = min(max(proposed, lower), upper)
    }

    /// 「整段」= 0…min(时长, 30)
    static func whole(duration: Double) -> VideoRangeSelection {
        VideoRangeSelection(start: 0, end: min(max(0, duration), maxLength), duration: duration)
    }

    /// 预设窗口：端点按 30s 上限收窄（超出时收紧末端，视频时长仍会再钳制）
    static func capped(_ range: ClosedRange<Double>, duration: Double) -> VideoRangeSelection {
        let start = max(0, range.lowerBound)
        let end = min(max(start, range.upperBound), start + maxLength)
        return VideoRangeSelection(start: start, end: end, duration: duration)
    }
}

/// 三个预设 chips（真值顺序：热点 / 整段 / 手动）
enum VideoSendPreset: String, CaseIterable, Identifiable {
    case hotspot
    case whole
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hotspot: return "错误热点前后各2小节"
        case .whole: return "整段"
        case .manual: return "手动"
        }
    }
}

struct VideoSendInitialSelection: Equatable {
    var preset: VideoSendPreset
    var range: VideoRangeSelection
}

// MARK: - 文案（可单测，不靠快照）

enum VideoSendText {
    static let title = "裁切并发送给 Neko"
    static let subtitle = "只发送你提问的那一段，原视频不会上传"
    static let toggleLabel = "分析后删除云端视频（推荐）"
    static let retentionNoteText = "云端文件会保留至过期（约 7 天）"
    static let providerRetryLine = "失败时按链上的下一个服务商重试"
    static let tooShort = "至少 2 秒"
    static let exportingLabel = "正在转码/上传…"
    static let footnote = "PianoSempai 自己不存储任何视频副本"
    static let confirmTitle = "确认裁切并发送"
    static let retryTitle = "重试"

    /// 秒 → m:ss（四舍五入到秒；与 VideoUIFormatting 同口径）
    static func timecode(_ seconds: Double) -> String {
        VideoUIFormatting.timecode(Int(seconds.rounded()))
    }

    /// 「已选 0:12–0:24（12秒）」
    static func badge(start: Double, end: Double) -> String {
        let length = max(0, end - start)
        return "已选 \(timecode(start))–\(timecode(end))（\(Int(length.rounded()))秒）"
    }

    /// 我方气泡附件 chip：「0:12–0:24 · 12 秒」
    static func attachmentChip(_ attachment: ChatVideoAttachment) -> String {
        "\(timecode(attachment.startSec))–\(timecode(attachment.endSec)) · \(Int(max(0, attachment.durationSec).rounded())) 秒"
    }

    /// 服务商披露首行（名字运行时读取；无可用服务商时如实说）
    static func providerLine(name: String?) -> String {
        if let name, !name.isEmpty {
            return "服务商：\(name) · 视频将上传至其服务器用于本次分析"
        }
        return "服务商：链上暂无可用的视频服务商"
    }

    /// 删除开关 OFF 的保留提示；ON 时不显示（不制造多余警告）
    static func retentionNote(deleteCloudFile: Bool) -> String? {
        deleteCloudFile ? nil : retentionNoteText
    }
}

// MARK: - S18b Sheet

struct S18bVideoSendSheet: View {
    let draft: VideoSendDraft
    let store: ChatStore
    /// 可注入导出器（测试/预览可替换；生产用 AVFoundation 720p）
    var exporter: any VideoClipExporting = AVFoundationClipExporter()

    @Environment(\.dismiss) private var dismiss

    @State private var duration: Double
    @State private var question: String
    @State private var preset: VideoSendPreset
    @State private var selection: VideoRangeSelection
    @State private var deleteCloudFile = true
    @State private var playheadSec: Double
    @State private var thumbnails: [UIImage] = []
    @State private var exportTask: Task<Void, Never>?
    @State private var dragStartSelection: VideoRangeSelection?
    @State private var dragStartPlayhead: Double?

    // 发送状态机（sheet 本地，配合 store.videoSendPhase）
    @State private var didStartSending = false
    @State private var didCancelSending = false
    @State private var lastFailureWasExport = false
    @State private var didLoadDuration = false

    @FocusState private var questionFocused: Bool

    init(
        draft: VideoSendDraft,
        store: ChatStore,
        exporter: any VideoClipExporting = AVFoundationClipExporter()
    ) {
        self.draft = draft
        self.store = store
        self.exporter = exporter

        let initial = draft.initialSelection()
        _duration = State(initialValue: max(draft.durationSec, initial.range.end))
        _question = State(initialValue: draft.defaultQuestion)
        _preset = State(initialValue: initial.preset)
        _selection = State(initialValue: initial.range)
        _playheadSec = State(initialValue: (initial.range.start + initial.range.end) / 2)
    }

    private var isBusy: Bool {
        switch store.videoSendPhase {
        case .exporting, .uploading: return true
        case .idle, .failed: return false
        }
    }

    private var canConfirm: Bool {
        guard draft.providerName != nil, store.hasAvailableProvider, !store.isSending else { return false }
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return selection.isValid
    }

    var body: some View {
        // 91% 卡 + 整屏压暗（真值：顶部 74pt 可见压暗背景）。
        // 用 fullScreenCover + 抽屉：抽屉自带的 scrim 覆盖全屏，卡片高度按屏幕 91% 定高
        //（抽屉组件固定 .presentationDetents 不参与此形态，遵循 S12 的全屏抽屉先例）。
        GeometryReader { geo in
            NocturneBottomDrawer(dismissOnScrimTap: false) {
                VStack(spacing: 0) {
                    DrawerGrabHandle()

                    titleRow
                        .padding(.horizontal, 20)

                    Rectangle()
                        .fill(Color.border.opacity(0.6))
                        .frame(height: 1)
                        .padding(.top, 14)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            filmSection
                            questionRow
                            providerCard
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                    }
                    .scrollDismissesKeyboard(.interactively)

                    ctaBlock
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                }
                .frame(height: geo.size.height * 0.91, alignment: .top)
            }
        }
        .task {
            if duration <= 0 { await loadDurationIfNeeded() }
            await loadThumbnails()
        }
        .onChange(of: store.videoSendPhase) { oldPhase, newPhase in
            // 成功：上传 + 回答都结束后回到 idle → 收起 sheet，消息已在对话里
            if didStartSending, !didCancelSending, newPhase == .idle, oldPhase != .idle {
                dismiss()
            }
        }
        .onDisappear {
            exportTask?.cancel()
        }
    }

    // MARK: 标题行

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(VideoSendText.title)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.textPrimary)
                Text(VideoSendText.subtitle)
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textMuted)
                    .frame(width: 32, height: 32)
                    .background(Color.canvas, in: Circle())
                    .overlay(Circle().strokeBorder(Color.border, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
    }

    // MARK: 裁切区

    private var filmSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("片段区间")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.amber)
                        .frame(width: 6, height: 6)
                    Text(VideoSendText.badge(start: selection.start, end: selection.end))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.amber)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.amber.opacity(0.30), lineWidth: 1))
            }

            filmStrip

            if selection.showsTooShortError {
                Text(VideoSendText.tooShort)
                    .font(.labelSm)
                    .foregroundStyle(Color.danger)
            }

            presetChips
        }
    }

    private var filmStrip: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let total = max(duration, 0.001)
                let startX = CGFloat(selection.start / total) * width
                let endX = CGFloat(selection.end / total) * width
                let selectionWidth = max(0, endX - startX)

                ZStack(alignment: .topLeading) {
                    // 真实缩略帧（只画真的；没生成出来就留深底，不画假波形）
                    HStack(spacing: 0) {
                        ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: width / CGFloat(max(1, thumbnails.count)), height: 52)
                                .clipped()
                        }
                    }
                    .frame(width: width, height: 52, alignment: .leading)
                    .background(Color.cardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    // 未选中段压暗
                    if startX > 0 {
                        Rectangle()
                            .fill(Color.black.opacity(0.55))
                            .frame(width: startX, height: 52)
                    }
                    if endX < width {
                        Rectangle()
                            .fill(Color.black.opacity(0.55))
                            .frame(width: width - endX, height: 52)
                            .offset(x: endX)
                    }

                    // 选中段：琥珀 10% 底 + 上下 2pt 琥珀边
                    Rectangle()
                        .fill(Color.amber.opacity(0.10))
                        .frame(width: selectionWidth, height: 52)
                        .offset(x: startX)
                    Rectangle()
                        .fill(Color.amber)
                        .frame(width: selectionWidth, height: 2)
                        .offset(x: startX)
                    Rectangle()
                        .fill(Color.amber)
                        .frame(width: selectionWidth, height: 2)
                        .offset(x: startX, y: 50)

                    // 播放头（真值：1.5pt 白线 + 10×8 三角；本实现可拖）
                    playhead(width: width)

                    // 双手柄：12pt 宽通高；热区外扩到 44pt
                    handle(at: startX, width: width, isStart: true)
                    handle(at: endX, width: width, isStart: false)
                }
                .frame(width: width, height: 52, alignment: .topLeading)
            }
            .frame(height: 52)
            .padding(4)
            .background(Color.cardElevated, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
            .frame(height: 62)

            ruler
        }
    }

    private var ruler: some View {
        HStack(spacing: 0) {
            Text(VideoSendText.timecode(0))
            Spacer(minLength: 4)
            Text(VideoSendText.timecode(selection.start))
                .foregroundStyle(Color.amber)
            Spacer(minLength: 4)
            Text(VideoSendText.timecode(selection.end))
                .foregroundStyle(Color.amber)
            Spacer(minLength: 4)
            Text(VideoSendText.timecode(duration))
        }
        .font(.labelMono(10))
        .foregroundStyle(Color.textMuted)
        .monospacedDigit()
    }

    private func handle(at x: CGFloat, width: CGFloat, isStart: Bool) -> some View {
        ZStack {
            Color.clear
                .frame(width: 44, height: 62)
                .contentShape(Rectangle())

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.amber)
                .frame(width: 12, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.canvas)
                        .frame(width: 2, height: 16)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
        }
        .offset(x: min(max(x - 22, -22), width - 22))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartSelection == nil { dragStartSelection = selection }
                    guard let base = dragStartSelection else { return }
                    let total = max(duration, 0.001)
                    let delta = Double(value.translation.width) / Double(max(1, width)) * total
                    if isStart {
                        selection.moveStart(to: base.start + delta)
                    } else {
                        selection.moveEnd(to: base.end + delta)
                    }
                    preset = .manual
                    playheadSec = min(max(playheadSec, selection.start), selection.end)
                }
                .onEnded { _ in dragStartSelection = nil }
        )
        .accessibilityLabel(isStart ? "片段起点" : "片段终点")
    }

    private func playhead(width: CGFloat) -> some View {
        let total = max(duration, 0.001)
        let x = CGFloat(min(max(playheadSec, 0), total) / total) * width
        return ZStack(alignment: .top) {
            Color.clear
                .frame(width: 44, height: 62)
                .contentShape(Rectangle())
            Rectangle()
                .fill(Color.white)
                .frame(width: 1.5, height: 52)
            PlayheadTriangle()
                .fill(Color.white)
                .frame(width: 10, height: 8)
        }
        .offset(x: min(max(x - 22, -22), width - 22))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartPlayhead == nil { dragStartPlayhead = playheadSec }
                    guard let base = dragStartPlayhead else { return }
                    let total = max(duration, 0.001)
                    let delta = Double(value.translation.width) / Double(max(1, width)) * total
                    playheadSec = min(max(base + delta, 0), total)
                }
                .onEnded { _ in dragStartPlayhead = nil }
        )
        .accessibilityLabel("预览位置")
    }

    private var presetChips: some View {
        HStack(spacing: 8) {
            chip(.hotspot, flexible: true, enabled: draft.hotspotRange(videoDurationSec: duration) != nil)
            chip(.whole, flexible: false, enabled: true)
            chip(.manual, flexible: false, enabled: true)
        }
        .padding(.top, 2)
    }

    private func chip(_ preset: VideoSendPreset, flexible: Bool, enabled: Bool) -> some View {
        let selected = self.preset == preset
        return Button {
            guard enabled else { return }
            selectPreset(preset)
        } label: {
            HStack(spacing: 5) {
                if selected {
                    Circle()
                        .fill(Color.amber)
                        .frame(width: 5, height: 5)
                }
                Text(preset.title)
                    .font(.system(size: 12, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Color.amber : Color.textMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, selected ? 10 : 14)
            .padding(.vertical, 8)
            .frame(maxWidth: flexible && selected ? .infinity : nil)
            .background(
                selected ? Color.amber.opacity(0.15) : Color.canvas,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.amber : Color.border, lineWidth: 1)
            )
            .opacity(enabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(S18bPressStyle())
        .disabled(!enabled)
    }

    private func selectPreset(_ preset: VideoSendPreset) {
        switch preset {
        case .hotspot:
            guard let window = draft.hotspotRange(videoDurationSec: duration) else { return }
            selection = VideoRangeSelection.capped(window, duration: duration)
        case .whole:
            selection = .whole(duration: duration)
        case .manual:
            break
        }
        self.preset = preset
        playheadSec = (selection.start + selection.end) / 2
    }

    // MARK: 提问行

    private var questionRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.system(size: 18))
                .foregroundStyle(Color.amber)

            Text("提问：")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)

            TextField("问题（必填）", text: $question, axis: .vertical)
                .font(.bodySm)
                .foregroundStyle(Color.textPrimary)
                .tint(Color.amber)
                .lineLimit(1...3)
                .focused($questionFocused)

            Button {
                questionFocused = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.textMuted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("编辑提问")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.canvas, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
    }

    // MARK: 服务商披露卡

    private var providerCard: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.amber)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.amber)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(VideoSendText.providerLine(name: draft.providerName))
                            .font(.bodySm)
                            .foregroundStyle(Color.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(VideoSendText.providerRetryLine)
                            .font(.labelSm)
                            .foregroundStyle(Color.textMuted.opacity(0.8))
                    }
                }

                Rectangle()
                    .fill(Color.border.opacity(0.7))
                    .frame(height: 1)

                HStack(spacing: 12) {
                    Text(VideoSendText.toggleLabel)
                        .font(.labelMd)
                        .foregroundStyle(Color.textBody)
                    Spacer(minLength: 8)
                    Button {
                        deleteCloudFile.toggle()
                    } label: {
                        ZStack(alignment: deleteCloudFile ? .trailing : .leading) {
                            Capsule()
                                .fill(deleteCloudFile ? Color.amber : Color.borderInput)
                                .frame(width: 40, height: 20)
                            Circle()
                                .fill(Color.canvas)
                                .frame(width: 16, height: 16)
                                .padding(2)
                        }
                        .animation(.easeInOut(duration: 0.2), value: deleteCloudFile)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(VideoSendText.toggleLabel)
                    .accessibilityValue(deleteCloudFile ? "开启" : "关闭")
                }

                if let note = VideoSendText.retentionNote(deleteCloudFile: deleteCloudFile) {
                    Text(note)
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                }
            }
            .padding(14)
        }
        .background(Color.cardElevated)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 0,
                bottomTrailingRadius: 12, topTrailingRadius: 12,
                style: .continuous
            )
        )
    }

    // MARK: CTA / 状态

    @ViewBuilder
    private var ctaBlock: some View {
        VStack(spacing: 8) {
            switch store.videoSendPhase {
            case .exporting, .uploading:
                progressRow
            case .failed(let message):
                failureRow(message)
            case .idle:
                confirmButton
                Button {
                    close()
                } label: {
                    Text("取消")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }

            Text(VideoSendText.footnote)
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
    }

    private var confirmButton: some View {
        Button {
            startSend()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16))
                Text(VideoSendText.confirmTitle)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(canConfirm ? Color.canvas : Color.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                canConfirm ? Color.amber : Color.borderInput,
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(S18bPressStyle(scale: 0.99))
        .disabled(!canConfirm)
    }

    private var progressRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Color.amber)
                .controlSize(.small)
            Text(VideoSendText.exportingLabel)
                .font(.labelMd)
                .foregroundStyle(Color.textBody)
            Spacer(minLength: 8)
            Button {
                cancelSending()
            } label: {
                Text("取消")
                    .font(.labelMd)
                    .foregroundStyle(Color.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }

    private func failureRow(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.bodySm)
                .foregroundStyle(Color.danger)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                retrySend()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                    Text(VideoSendText.retryTitle)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.canvas)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.amber, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(S18bPressStyle(scale: 0.99))

            Button {
                close()
            } label: {
                Text("取消")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 行为

    private func startSend() {
        guard canConfirm else { return }
        didStartSending = true
        didCancelSending = false
        lastFailureWasExport = false

        let questionText = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = selection.start
        let end = selection.end
        let attachment = ChatVideoAttachment(
            startSec: start,
            endSec: end,
            durationSec: max(0, end - start),
            providerModel: "",
            cloudFileDeleted: false
        )
        // 进入「转码中」；真正上传等导出完成
        store.send(text: questionText, attachment: attachment, clip: nil, deleteCloudFile: deleteCloudFile)

        let exportStart = start
        let exportEnd = end
        exportTask = Task {
            do {
                let url = try await exporter.exportClip(source: draft.videoURL, startSec: exportStart, endSec: exportEnd)
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                let clip = VideoClipPayload(fileURL: url, startSec: exportStart, endSec: exportEnd)
                store.send(
                    text: questionText,
                    attachment: attachment,
                    clip: clip,
                    deleteCloudFile: deleteCloudFile
                )
            } catch {
                if Task.isCancelled { return }
                lastFailureWasExport = true
                let message = (error as? VideoClipExportError)?.summary ?? "裁切失败：\(error.localizedDescription)"
                store.send(
                    text: questionText,
                    attachment: attachment,
                    clip: nil,
                    exportError: message,
                    deleteCloudFile: deleteCloudFile
                )
            }
        }
    }

    private func retrySend() {
        didCancelSending = false
        if lastFailureWasExport {
            startSend()
        } else {
            store.retry()
        }
    }

    private func cancelSending() {
        didCancelSending = true
        exportTask?.cancel()
        exportTask = nil
        store.cancelVideoSend()
    }

    private func close() {
        if isBusy { cancelSending() }
        dismiss()
    }

    // MARK: 数据加载

    private func loadDurationIfNeeded() async {
        guard !didLoadDuration else { return }
        didLoadDuration = true
        let asset = AVURLAsset(url: draft.videoURL)
        guard let loaded = try? await asset.load(.duration) else { return }
        let seconds = CMTimeGetSeconds(loaded)
        guard seconds.isFinite, seconds > 0 else { return }
        duration = seconds
        // 时长未知时先按整段；读到真实时长后重算默认选区（用户还没动过）
        if !didStartSending {
            selection = draft.initialSelection(videoDurationSec: seconds).range
            preset = draft.initialSelection(videoDurationSec: seconds).preset
            playheadSec = (selection.start + selection.end) / 2
        }
    }

    private func loadThumbnails() async {
        let asset = AVURLAsset(url: draft.videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)

        let count = 7
        let total = max(duration, 0.001)
        var images: [UIImage] = []
        for index in 0..<count {
            guard !Task.isCancelled else { return }
            let seconds = total * (Double(index) + 0.5) / Double(count)
            if let result = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) {
                images.append(UIImage(cgImage: result.image))
            }
        }
        if !images.isEmpty, !Task.isCancelled {
            thumbnails = images
        }
    }
}

// MARK: - 小部件

/// 播放头三角（真值 10×8，尖朝下）
private struct PlayheadTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 按压缩放（真值 pressed scale 0.95 / 0.99）
private struct S18bPressStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

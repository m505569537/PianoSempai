import SwiftData
import XCTest

@testable import PianoSempai

/// V3 Stage B · S18b 裁切确认 + ChatStore 视频发送（ADR-0011）。
/// 纯逻辑 + 内存 ModelContainer + 假 runner：不碰真实 AVFoundation / 网络 / Keychain。
@MainActor
final class VideoSendStageBTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Take.self, TakeAnalysis.self, ChatThread.self, ChatMessage.self, AIProvider.self,
                Piece.self, DailyPlan.self, AppSettings.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
    }

    // MARK: - 假依赖

    private final class FakeVideoRunner: ChatChainRunning {
        /// 依次消费；空 = 未配置（抛错，便于发现意外调用）
        var behaviors: [Result<ChainResult, Error>] = []
        var delay: Duration = .zero
        private(set) var videoRequests: [ChainVideoRequest] = []
        private(set) var textCallCount = 0

        func run(providers: [AIProvider], input: ChainInput) async throws -> ChainResult {
            textCallCount += 1
            throw AIProviderError.invalidRequest("视频测试不该走纯文字入口")
        }

        func run(
            providers: [AIProvider],
            input: ChainInput,
            video: ChainVideoRequest?
        ) async throws -> ChainResult {
            guard let video else {
                throw AIProviderError.invalidRequest("视频测试需要 ChainVideoRequest")
            }
            videoRequests.append(video)
            if delay > .zero {
                try await Task.sleep(for: delay)
            }
            guard !behaviors.isEmpty else {
                throw AIProviderError.decoding("假 runner 未配置该次调用的行为")
            }
            switch behaviors.removeFirst() {
            case .success(let result): return result
            case .failure(let error): throw error
            }
        }
    }

    private final class FakeTextRunner: ChatChainRunning {
        var result: ChainResult?

        func run(providers: [AIProvider], input: ChainInput) async throws -> ChainResult {
            if let result { return result }
            throw AIProviderError.decoding("假 runner 未配置回复")
        }
    }

    private final class FakeProviderSource: ChatProviderSource {
        var providers: [AIProvider]
        init(_ providers: [AIProvider]) { self.providers = providers }
        func currentProviders() -> [AIProvider] { providers }
    }

    private final class FakeProviderKeyStore: ProviderKeyStore {
        private var keys: [String: String]
        init(keys: [String: String] = [:]) { self.keys = keys }
        func save(_ key: String, providerId: String) throws { keys[providerId] = key }
        func read(providerId: String) -> String? { keys[providerId] }
        func delete(providerId: String) throws { keys[providerId] = nil }
        func hasKey(providerId: String) -> Bool { keys[providerId] != nil }
    }

    // MARK: - 夹具

    private func makeTake(videoDurationSec: Int = 64) -> Take {
        Take(
            startedAt: Date(timeIntervalSince1970: 1_758_000_000),
            durationSec: 64,
            taskType: "main",
            hasMidi: true,
            measureFrom: 1,
            measureTo: 16,
            tempoAvg: 120,
            title: "测试曲"
        )
    }

    private func makeDraft(
        duration: Double = 64,
        hotspots: [Int],
        bpm: Int = 120,
        totalMeasures: Int = 16,
        offset: Double = 0
    ) -> VideoSendDraft {
        VideoSendDraft(
            take: makeTake(),
            videoURL: URL(fileURLWithPath: "/tmp/ps-stage-b-test.mov"),
            durationSec: duration,
            videoStartedAtOffset: offset,
            hotspots: hotspots,
            totalMeasures: totalMeasures,
            timing: MeasureTiming(beats: 4, beatUnit: 4),
            bpm: bpm,
            defaultQuestion: "这段的手型有什么问题？",
            providerName: "视频商"
        )
    }

    private func provider(
        _ id: String,
        baseURL: String = "https://ark.cn-beijing.volces.com/api/v3",
        enabled: Bool = true,
        sortOrder: Int = 0
    ) -> AIProvider {
        AIProvider(
            providerId: id,
            displayName: "视频商 \(id)",
            baseURL: baseURL,
            modelIds: ["model-\(id)"],
            enabled: enabled,
            sortOrder: sortOrder
        )
    }

    private func makeStore(
        runner: any ChatChainRunning,
        providers: [AIProvider] = [],
        keys: [String: String] = [:]
    ) -> ChatStore {
        ChatStore(
            mode: .freeform,
            context: context,
            keyStore: FakeProviderKeyStore(keys: keys),
            runner: runner,
            providerSource: FakeProviderSource(providers)
        )
    }

    private func attachment(start: Double = 4, end: Double = 14) -> ChatVideoAttachment {
        ChatVideoAttachment(
            startSec: start,
            endSec: end,
            durationSec: max(0, end - start),
            providerModel: "",
            cloudFileDeleted: false
        )
    }

    /// 真实临时文件（用于断言「成功/取消后确实被删」）
    private func makeTempClip() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ps-stage-b-\(UUID().uuidString).mp4")
        try Data([0, 1, 2, 3]).write(to: url)
        return url
    }

    private func waitForIdle(_ store: ChatStore) async {
        for _ in 0..<400 where store.isSending {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func successResult(
        text: String = "这一段的 3 指转 1 指手腕要先带过去。",
        providerModel: String = "视频商 · model-ark",
        attachment: ChatVideoAttachment
    ) -> ChainResult {
        ChainResult(
            text: text,
            providerModel: providerModel,
            evidenceRefs: [],
            attempts: [],
            videoAttachment: attachment
        )
    }

    // MARK: - 1. 区间钳制

    func testRangeStartClampsAgainstEndAndMaxLength() {
        var range = VideoRangeSelection(start: 4, end: 14, duration: 64)

        // 越过右手柄 → 钉在 end - 2s
        range.moveStart(to: 100)
        XCTAssertEqual(range.start, 12, accuracy: 1e-9)
        XCTAssertEqual(range.end, 14, accuracy: 1e-9)

        // 越过 0 → 钉在 0
        range.moveStart(to: -8)
        XCTAssertEqual(range.start, 0, accuracy: 1e-9)

        // 区间最长 30s：end = 14 → start 不能小于 -16，但 0 已在下界内
        var wide = VideoRangeSelection(start: 40, end: 60, duration: 100)
        wide.moveStart(to: 0)
        XCTAssertEqual(wide.start, 30, accuracy: 1e-9, "start 不能超过 end - 30s")
        XCTAssertEqual(wide.length, 30, accuracy: 1e-9)
    }

    func testRangeEndClampsToDurationAndMaxLength() {
        var range = VideoRangeSelection(start: 5, end: 10, duration: 20)
        range.moveEnd(to: 100)
        XCTAssertEqual(range.end, 20, accuracy: 1e-9, "不能越过视频时长")

        var wide = VideoRangeSelection(start: 4, end: 10, duration: 100)
        wide.moveEnd(to: 90)
        XCTAssertEqual(wide.end, 34, accuracy: 1e-9, "最长 30 秒")

        var short = VideoRangeSelection(start: 4, end: 10, duration: 100)
        short.moveEnd(to: 0)
        XCTAssertEqual(short.end, 6, accuracy: 1e-9, "不能短于 2 秒")
    }

    func testTooShortRangeIsInvalid() {
        let range = VideoRangeSelection(start: 5, end: 6.5, duration: 20)
        XCTAssertFalse(range.isValid)
        XCTAssertTrue(range.showsTooShortError)
        XCTAssertEqual(range.length, 1.5, accuracy: 1e-9)
    }

    // MARK: - 2. 预设

    func testHotspotPresetSelectedWhenWindowAvailable() {
        // hotspots [5]、前后各 2 小节、120 BPM 4/4 → 每小节 2s → 第 3–7 小节 = 4…14s
        let draft = makeDraft(hotspots: [5])
        let window = draft.hotspotRange(videoDurationSec: 64)

        XCTAssertEqual(window?.lowerBound ?? -1, 4, accuracy: 1e-9)
        XCTAssertEqual(window?.upperBound ?? -1, 14, accuracy: 1e-9)

        let initial = draft.initialSelection(videoDurationSec: 64)
        XCTAssertEqual(initial.preset, .hotspot)
        XCTAssertEqual(initial.range.start, 4, accuracy: 1e-9)
        XCTAssertEqual(initial.range.end, 14, accuracy: 1e-9)
    }

    func testWholePresetWhenNoHotspot() {
        let draft = makeDraft(hotspots: [])
        XCTAssertNil(draft.hotspotRange(videoDurationSec: 64))

        let initial = draft.initialSelection(videoDurationSec: 64)
        XCTAssertEqual(initial.preset, .whole)
        XCTAssertEqual(initial.range.start, 0, accuracy: 1e-9)
        XCTAssertEqual(initial.range.end, 30, accuracy: 1e-9)
    }

    func testWholeRangeIsZeroToThirty() {
        let long = VideoRangeSelection.whole(duration: 45)
        XCTAssertEqual(long.start, 0, accuracy: 1e-9)
        XCTAssertEqual(long.end, 30, accuracy: 1e-9)

        let short = VideoRangeSelection.whole(duration: 12)
        XCTAssertEqual(short.start, 0, accuracy: 1e-9)
        XCTAssertEqual(short.end, 12, accuracy: 1e-9)
    }

    // MARK: - 3. 文案

    func testBadgeAndAttachmentChipText() {
        XCTAssertEqual(
            VideoSendText.badge(start: 12, end: 24),
            "已选 0:12–0:24（12秒）"
        )

        let chip = VideoSendText.attachmentChip(
            ChatVideoAttachment(
                startSec: 12, endSec: 24, durationSec: 12,
                providerModel: "视频商 · model", cloudFileDeleted: true
            )
        )
        XCTAssertEqual(chip, "0:12–0:24 · 12 秒")
    }

    func testRetentionNoteOnlyWhenDeletionOff() {
        XCTAssertNil(VideoSendText.retentionNote(deleteCloudFile: true))
        XCTAssertEqual(
            VideoSendText.retentionNote(deleteCloudFile: false),
            "云端文件会保留至过期（约 7 天）"
        )
    }

    // MARK: - 4. 附件 JSON

    func testAttachmentJSONRoundTrip() {
        let items = [
            attachment(start: 0, end: 2.5),
            ChatVideoAttachment(
                startSec: 12, endSec: 24, durationSec: 12,
                providerModel: "视频商 · model-ark", cloudFileDeleted: true
            ),
        ]
        let json = AIJSON.encode(items)
        let decoded = AIJSON.decode([ChatVideoAttachment].self, from: json)

        XCTAssertEqual(decoded, items)
        XCTAssertEqual(AIJSON.decode([ChatVideoAttachment].self, from: "[]"), [])
    }

    // MARK: - 5. 状态机（idle → exporting → uploading → failed → retry → uploading → idle）

    func testVideoSendPhaseTransitionsAndAttachmentUpdate() async throws {
        let clipURL = try makeTempClip()
        let clip = VideoClipPayload(fileURL: clipURL, startSec: 4, endSec: 14)

        let failure = ProviderChainFailure(attempts: [
            ProviderChainFailure.Attempt(
                providerId: "ark",
                providerDisplayName: "视频商 ark",
                modelId: "model-ark",
                errorSummary: "上传超时"
            ),
        ])

        let runner = FakeVideoRunner()
        runner.behaviors = [
            .failure(failure),
            .success(successResult(
                attachment: ChatVideoAttachment(
                    startSec: 4, endSec: 14, durationSec: 10,
                    providerModel: "视频商 · model-ark", cloudFileDeleted: true
                )
            )),
        ]
        let store = makeStore(runner: runner, providers: [provider("ark")], keys: ["ark": "k"])

        // 导出中：不落消息、不可取消
        store.send(text: "这段的手型有什么问题？", attachment: attachment(), clip: nil)
        XCTAssertEqual(store.videoSendPhase, .exporting)
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertFalse(store.canCancelVideoSend)

        // 导出完成 → 上传中：先落 user 消息
        store.send(text: "这段的手型有什么问题？", attachment: attachment(), clip: clip)
        XCTAssertEqual(store.videoSendPhase, .uploading)
        XCTAssertTrue(store.canCancelVideoSend)
        XCTAssertEqual(store.messages.count, 1)
        XCTAssertEqual(store.messages[0].role, "user")

        await waitForIdle(store)
        guard case .failed(let message) = store.videoSendPhase else {
            return XCTFail("全链失败应进入 .failed，实际 \(store.videoSendPhase)")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(store.canCancelVideoSend)
        XCTAssertEqual(store.messages.count, 1, "失败不写 Neko 消息，user 消息保留")
        XCTAssertTrue(FileManager.default.fileExists(atPath: clipURL.path), "失败保留片段供重试")

        // 重试：同一片段、不重新导出
        store.retry()
        XCTAssertEqual(store.videoSendPhase, .uploading)
        await waitForIdle(store)

        XCTAssertEqual(store.videoSendPhase, .idle)
        XCTAssertEqual(store.messages.map(\.role), ["user", "neko"])
        XCTAssertEqual(runner.videoRequests.count, 2)
        XCTAssertEqual(runner.videoRequests[1].payload.fileURL, clipURL)

        // user 消息落实际命中服务商 + 真实删除结果
        let written = store.messages[0].videoAttachments
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(written[0].providerModel, "视频商 · model-ark")
        XCTAssertTrue(written[0].cloudFileDeleted)
        XCTAssertEqual(written[0].startSec, 4, accuracy: 1e-9)
        XCTAssertEqual(written[0].endSec, 14, accuracy: 1e-9)
        XCTAssertFalse(FileManager.default.fileExists(atPath: clipURL.path), "成功后删临时片段")
    }

    func testTempClipDeletedOnSuccess() async throws {
        let clipURL = try makeTempClip()
        let runner = FakeVideoRunner()
        runner.behaviors = [
            .success(successResult(
                attachment: ChatVideoAttachment(
                    startSec: 0, endSec: 6, durationSec: 6,
                    providerModel: "视频商 · model-ark", cloudFileDeleted: false
                )
            )),
        ]
        let store = makeStore(runner: runner, providers: [provider("ark")], keys: ["ark": "k"])

        store.send(
            text: "这里怎么练？",
            attachment: attachment(start: 0, end: 6),
            clip: VideoClipPayload(fileURL: clipURL, startSec: 0, endSec: 6)
        )
        await waitForIdle(store)

        XCTAssertEqual(store.videoSendPhase, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: clipURL.path))
    }

    func testCancelDeletesTempClipAndWithdrawsMessage() async throws {
        let clipURL = try makeTempClip()
        let runner = FakeVideoRunner()
        runner.delay = .milliseconds(300)
        runner.behaviors = [
            .success(successResult(attachment: attachment())),
        ]
        let store = makeStore(runner: runner, providers: [provider("ark")], keys: ["ark": "k"])

        store.send(
            text: "这段的手型有什么问题？",
            attachment: attachment(),
            clip: VideoClipPayload(fileURL: clipURL, startSec: 4, endSec: 14)
        )
        let task = store.videoSendTask
        XCTAssertEqual(store.messages.count, 1)

        store.cancelVideoSend()
        await task?.value

        XCTAssertEqual(store.videoSendPhase, .idle)
        XCTAssertFalse(store.isSending)
        XCTAssertTrue(store.messages.isEmpty, "取消后撤回尚未发出的 user 消息")
        XCTAssertFalse(FileManager.default.fileExists(atPath: clipURL.path))
        XCTAssertEqual(store.videoSendPhase, .idle, "取消不能被后台任务的失败态覆盖")
    }

    // MARK: - 6. 纯文字不受影响

    func testTextOnlySendWritesEmptyAttachmentsJSON() async throws {
        let runner = FakeTextRunner()
        runner.result = ChainResult(text: "先慢练。", providerModel: "视频商 · model-ark", evidenceRefs: [], attempts: [])
        let store = makeStore(runner: runner, providers: [provider("ark")], keys: ["ark": "k"])

        store.send(text: "21 小节怎么练？")
        await waitForIdle(store)

        XCTAssertEqual(store.messages.map(\.role), ["user", "neko"])
        XCTAssertEqual(store.messages[0].attachmentsJSON, "[]")
        XCTAssertTrue(store.messages[0].videoAttachments.isEmpty)
        XCTAssertEqual(store.videoSendPhase, .idle)
        XCTAssertEqual(runner.result?.text, store.messages[1].text)
    }

    // MARK: - 7. 服务商解析 + 开关透传

    func testProviderResolverSkipsNonVideoAndDisabled() {
        let generic = provider("o", baseURL: "https://api.openai.com/v1", sortOrder: 0)
        let ark = provider("ark", sortOrder: 1)
        let disabledArk = provider("ark-off", enabled: false, sortOrder: 2)

        XCTAssertEqual(
            VideoProviderResolver.firstVideoCapableName(from: [generic, ark, disabledArk]),
            "视频商 ark"
        )
        XCTAssertNil(VideoProviderResolver.firstVideoCapableName(from: [generic]))
        XCTAssertNil(VideoProviderResolver.firstVideoCapableName(from: [disabledArk]))
    }

    func testDeleteTogglePropagatesToChainRequest() async throws {
        let clipURL = try makeTempClip()
        let runner = FakeVideoRunner()
        runner.behaviors = [
            .success(successResult(attachment: attachment())),
        ]
        let store = makeStore(runner: runner, providers: [provider("ark")], keys: ["ark": "k"])

        store.send(
            text: "这里怎么练？",
            attachment: attachment(),
            clip: VideoClipPayload(fileURL: clipURL, startSec: 4, endSec: 14),
            deleteCloudFile: false
        )
        await waitForIdle(store)

        XCTAssertEqual(runner.videoRequests.count, 1)
        XCTAssertEqual(runner.videoRequests[0].deleteCloudFile, false)
        XCTAssertEqual(runner.videoRequests[0].payload.startSec, 4, accuracy: 1e-9)
        XCTAssertEqual(runner.videoRequests[0].payload.endSec, 14, accuracy: 1e-9)
    }
}

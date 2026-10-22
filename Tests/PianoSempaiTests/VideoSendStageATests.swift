import XCTest
@testable import PianoSempai

/// V3 Stage A 验收（ADR-0011）：视频裁切发送的「纯逻辑 + 网络编解码 + 链式接线」。
/// 全程假 session / 假 client / 假 Files API：不打真实网络、不碰相机、不碰 Keychain。
final class VideoSendStageATests: XCTestCase {

    // MARK: - 假依赖

    private final class FakeURLSession: URLSessionDataProtocol {
        struct Reply {
            var statusCode: Int
            var body: Data
        }

        var handler: ((URLRequest) throws -> Reply)?
        private(set) var requests: [URLRequest] = []

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            let reply = try handler?(request) ?? Reply(statusCode: 500, body: Data())
            let url = request.url ?? URL(string: "https://example.com")!
            let response = HTTPURLResponse(
                url: url,
                statusCode: reply.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (reply.body, response)
        }
    }

    private final class FakeProviderKeyStore: ProviderKeyStore {
        private var keys: [String: String]

        init(keys: [String: String] = [:]) {
            self.keys = keys
        }

        func save(_ key: String, providerId: String) throws { keys[providerId] = key }
        func read(providerId: String) -> String? { keys[providerId] }
        func delete(providerId: String) throws { keys[providerId] = nil }
        func hasKey(providerId: String) -> Bool { keys[providerId] != nil }
    }

    private final class FakeAIClient: AIClient {
        struct Behavior {
            var reply: String?
            var error: AIProviderError?
        }

        var behaviors: [String: Behavior]
        private(set) var requestedModels: [String] = []
        private(set) var requests: [ChatCompletionRequest] = []
        private(set) var targets: [AIRequestTarget] = []

        init(behaviors: [String: Behavior]) {
            self.behaviors = behaviors
        }

        func send(_ request: ChatCompletionRequest, target: AIRequestTarget) async throws -> String {
            requestedModels.append(target.model)
            requests.append(request)
            targets.append(target)
            let behavior = behaviors[target.model]
                ?? FakeAIClient.Behavior(reply: nil, error: .http(status: 500, code: "NoBehaviorConfigured"))
            if let error = behavior.error { throw error }
            guard let reply = behavior.reply else {
                throw AIProviderError.decoding("假 client 未配置该模型的回复")
            }
            return reply
        }
    }

    private final class FakeFilesAPI: ArkFilesAPI {
        struct Upload {
            var fileURL: URL
            var model: String
            var fps: Double
            var key: String
            var baseURL: String
        }

        var uploads: [Upload] = []
        var deletes: [String] = []
        /// 记录删除时用的 key（验证每跳用自己的 key）
        var deleteKeys: [String] = []
        var uploadError: Error?
        var waitError: Error?
        var statusError: Error?
        var deleteError: Error?
        private var nextId = 0

        func upload(fileURL: URL, model: String, fps: Double, target: AIRequestTarget) async throws -> String {
            uploads.append(Upload(fileURL: fileURL, model: model, fps: fps, key: target.apiKey, baseURL: target.baseURL))
            if let uploadError { throw uploadError }
            nextId += 1
            return "file-\(nextId)"
        }

        func status(id: String, target: AIRequestTarget) async throws -> String {
            if let statusError { throw statusError }
            return "active"
        }

        func waitUntilActive(id: String, target: AIRequestTarget, timeout: TimeInterval, pollInterval: TimeInterval) async throws {
            if let waitError { throw waitError }
        }

        func delete(id: String, target: AIRequestTarget) async throws {
            deletes.append(id)
            deleteKeys.append(target.apiKey)
            if let deleteError { throw deleteError }
        }
    }

    // MARK: - 夹具

    private let arkBaseURL = "https://ark.cn-beijing.volces.com/api/v3"
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs { try? FileManager.default.removeItem(at: url) }
        tempURLs = []
        try super.tearDownWithError()
    }

    private func makeClipFile(bytes: Data = Data("FAKE-MP4-BYTES".utf8)) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-\(UUID().uuidString).mp4")
        try bytes.write(to: url)
        tempURLs.append(url)
        return url
    }

    private func target(model: String = "doubao-seed-1-6", key: String = "test-key-ark") -> AIRequestTarget {
        AIRequestTarget(
            providerId: "ark",
            providerDisplayName: "火山方舟",
            baseURL: arkBaseURL,
            model: model,
            apiKey: key
        )
    }

    private func provider(
        _ id: String,
        name: String,
        baseURL: String,
        models: [String],
        order: Int
    ) -> AIProvider {
        AIProvider(
            providerId: id,
            displayName: name,
            baseURL: baseURL,
            modelIds: models,
            enabled: true,
            sortOrder: order
        )
    }

    private func arkProvider(models: [String] = ["ark-m"], order: Int = 0) -> AIProvider {
        provider("ark", name: "火山方舟", baseURL: arkBaseURL, models: models, order: order)
    }

    private func makeRunner(
        client: FakeAIClient,
        files: FakeFilesAPI = FakeFilesAPI(),
        keys: [String: String] = ["ark": "k-ark"]
    ) -> ProviderChainRunner {
        ProviderChainRunner(
            client: client,
            keyStore: FakeProviderKeyStore(keys: keys),
            recovery: .stickyOnly,
            filesClient: files
        )
    }

    /// 视频提问的纯文字输入（ChainInput 结构上不含任何附件字段）
    private func videoInput() -> ChainInput {
        ChainInput(
            question: "这段的手型对吗？",
            systemPrompt: "只给建议，不改判分。",
            contextBlock: "第 12–14 小节是热点。",
            temperature: 0.2
        )
    }

    /// 视频附件请求（与 input 分离；单独传给 runner）
    private func videoRequest(
        clipURL: URL,
        deleteCloudFile: Bool = true,
        modelOverride: String? = nil
    ) -> ChainVideoRequest {
        ChainVideoRequest(
            payload: VideoClipPayload(fileURL: clipURL, startSec: 4, endSec: 12, fps: 2),
            deleteCloudFile: deleteCloudFile,
            modelOverride: modelOverride
        )
    }

    private func json(_ text: String) -> Data { Data(text.utf8) }

    private func assertBody(
        _ body: Data,
        contains text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNotNil(
            body.range(of: Data(text.utf8)),
            "multipart 请求体缺少：\(text)",
            file: file,
            line: line
        )
    }

    // MARK: - 1. ContentPart 编解码（file_id / url 两形态）

    func testContentPartEncodesFileIdInsteadOfURL() throws {
        let part = ContentPart(kind: .videoURL, fileId: "file-abc")
        let data = try JSONEncoder().encode(part)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["type"] as? String, "video_url")
        let nested = try XCTUnwrap(object["video_url"] as? [String: Any])
        XCTAssertEqual(nested["file_id"] as? String, "file-abc")
        XCTAssertNil(nested["url"], "有 fileId 时只写 file_id")
    }

    func testContentPartEncodesURLWhenNoFileId() throws {
        let part = ContentPart(kind: .videoURL, url: "https://example.com/a.mp4")
        let data = try JSONEncoder().encode(part)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let nested = try XCTUnwrap(object["video_url"] as? [String: Any])
        XCTAssertEqual(nested["url"] as? String, "https://example.com/a.mp4")
        XCTAssertNil(nested["file_id"])
    }

    func testContentPartDecodesBothVideoShapes() throws {
        let fileIdJSON = json(#"{"type":"video_url","video_url":{"file_id":"file-9"}}"#)
        XCTAssertEqual(
            try JSONDecoder().decode(ContentPart.self, from: fileIdJSON),
            ContentPart(kind: .videoURL, fileId: "file-9")
        )

        let urlJSON = json(#"{"type":"video_url","video_url":{"url":"https://example.com/b.mp4"}}"#)
        XCTAssertEqual(
            try JSONDecoder().decode(ContentPart.self, from: urlJSON),
            ContentPart(kind: .videoURL, url: "https://example.com/b.mp4")
        )
    }

    // MARK: - 2. ClipWindowMapper：每小节秒数

    func testMeasureSecondsForCommonTimings() {
        XCTAssertEqual(
            ClipWindowMapper.measureSeconds(timing: MeasureTiming(beats: 4, beatUnit: 4), bpm: 60),
            4.0,
            accuracy: 1e-9,
            "4/4 @ 60bpm = 4s"
        )
        XCTAssertEqual(
            ClipWindowMapper.measureSeconds(timing: MeasureTiming(beats: 3, beatUnit: 4), bpm: 90),
            2.0,
            accuracy: 1e-9,
            "3/4 @ 90bpm = 2s"
        )
    }

    // MARK: - 3. 热点 ±2 小节

    func testHotspotWindowPadsTwoMeasures() throws {
        // 4/4 @ 120bpm → 每小节 2s；第 10 小节 → [18, 20)s；±2 小节 → 第 8–12 小节 = 14...24
        let range = try XCTUnwrap(ClipWindowMapper.window(
            hotspots: [10],
            totalMeasures: 20,
            timing: MeasureTiming(beats: 4, beatUnit: 4),
            bpm: 120,
            videoStartedAtOffset: 0,
            videoDurationSec: 100
        ))
        XCTAssertEqual(range.lowerBound, 14, accuracy: 1e-9)
        XCTAssertEqual(range.upperBound, 24, accuracy: 1e-9)
    }

    // MARK: - 4. 首尾钳制

    func testWindowClampsAtVideoStartAndEnd() throws {
        let timing = MeasureTiming(beats: 4, beatUnit: 4)

        // 第 1 小节往前扩 → 钳到第 1 小节（0s 起）
        let head = try XCTUnwrap(ClipWindowMapper.window(
            hotspots: [1],
            totalMeasures: 20,
            timing: timing,
            bpm: 120,
            videoStartedAtOffset: 0,
            videoDurationSec: 100
        ))
        XCTAssertEqual(head.lowerBound, 0, accuracy: 1e-9)
        XCTAssertEqual(head.upperBound, 6, accuracy: 1e-9, "第 1–3 小节 = 6s")

        // 最后一小节往后扩 → 钳到总小节数
        let tail = try XCTUnwrap(ClipWindowMapper.window(
            hotspots: [20],
            totalMeasures: 20,
            timing: timing,
            bpm: 120,
            videoStartedAtOffset: 0,
            videoDurationSec: 100
        ))
        XCTAssertEqual(tail.lowerBound, 34, accuracy: 1e-9, "第 18 小节起 = 17×2s")
        XCTAssertEqual(tail.upperBound, 40, accuracy: 1e-9, "第 20 小节末 = 20×2s")
    }

    // MARK: - 5. 输入不足 → nil

    func testWindowReturnsNilForMissingInputs() {
        let timing = MeasureTiming(beats: 4, beatUnit: 4)
        XCTAssertNil(ClipWindowMapper.window(
            hotspots: [],
            totalMeasures: 20, timing: timing, bpm: 120,
            videoStartedAtOffset: 0, videoDurationSec: 100
        ), "无热点不造假区间")

        XCTAssertNil(ClipWindowMapper.window(
            hotspots: [5],
            totalMeasures: 20, timing: timing, bpm: 0,
            videoStartedAtOffset: 0, videoDurationSec: 100
        ), "bpm 非正算不出")

        XCTAssertNil(ClipWindowMapper.window(
            hotspots: [5],
            totalMeasures: 0, timing: timing, bpm: 120,
            videoStartedAtOffset: 0, videoDurationSec: 100
        ), "总小节数非正算不出")
    }

    // MARK: - 6. 钳制后不足 2 秒 → nil

    func testWindowReturnsNilWhenShorterThanTwoSeconds() {
        // 4/4 @ 240bpm → 每小节 1s；不扩 → 只有 1 秒
        XCTAssertNil(ClipWindowMapper.window(
            hotspots: [5],
            totalMeasures: 10,
            timing: MeasureTiming(beats: 4, beatUnit: 4),
            bpm: 240,
            videoStartedAtOffset: 0,
            videoDurationSec: 100,
            paddingMeasures: 0
        ))
    }

    // MARK: - 7. 录像偏移

    func testVideoStartedAtOffsetShiftsWindowAndClamps() throws {
        let timing = MeasureTiming(beats: 4, beatUnit: 4)

        let shifted = try XCTUnwrap(ClipWindowMapper.window(
            hotspots: [10],
            totalMeasures: 20,
            timing: timing,
            bpm: 120,
            videoStartedAtOffset: 5,
            videoDurationSec: 100
        ))
        XCTAssertEqual(shifted.lowerBound, 19, accuracy: 1e-9, "14s 起点 + 5s 偏移")
        XCTAssertEqual(shifted.upperBound, 29, accuracy: 1e-9)

        // 偏移后超出视频时长 → 钳到视频末尾；剩余不足 2s 则 nil
        let clipped = try XCTUnwrap(ClipWindowMapper.window(
            hotspots: [10],
            totalMeasures: 20,
            timing: timing,
            bpm: 120,
            videoStartedAtOffset: 5,
            videoDurationSec: 26
        ))
        XCTAssertEqual(clipped.upperBound, 26, accuracy: 1e-9)

        XCTAssertNil(ClipWindowMapper.window(
            hotspots: [10],
            totalMeasures: 20,
            timing: timing,
            bpm: 120,
            videoStartedAtOffset: 5,
            videoDurationSec: 17
        ), "钳到末尾后只剩 3s？→ 这里 14+5=19 > 17，整段被钳掉 → nil")
    }

    // MARK: - 8. multipart 请求体

    func testMultipartUploadBodyCarriesFieldsAndFileBytes() async throws {
        let fileURL = try makeClipFile(bytes: Data("MP4-PAYLOAD-0123456789".utf8))
        let session = FakeURLSession()
        session.handler = { _ in
            FakeURLSession.Reply(statusCode: 200, body: self.json(#"{"id":"file-1","status":"processing"}"#))
        }
        let client = ArkFileClient(session: session)

        _ = try await client.upload(fileURL: fileURL, model: "doubao-seed-2-1-pro-260915", fps: 2, target: target())

        let request = try XCTUnwrap(session.requests.first)
        let body = try XCTUnwrap(request.httpBody)
        assertBody(body, contains: "name=\"purpose\"")
        assertBody(body, contains: "user_data")
        assertBody(body, contains: "name=\"preprocess_configs[video][model]\"")
        assertBody(body, contains: "doubao-seed-2-1-pro-260915")
        assertBody(body, contains: "name=\"preprocess_configs[video][fps]\"")
        assertBody(body, contains: "name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"")
        XCTAssertNotNil(body.range(of: Data("MP4-PAYLOAD-0123456789".utf8)), "必须带视频二进制")
        XCTAssertTrue(
            request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://ark.cn-beijing.volces.com/api/v3/files")
    }

    // MARK: - 9. 上传：解析 id / 401 / 非 2xx

    func testUploadParsesFileIdAndSendsKeyOnlyInHeader() async throws {
        let fileURL = try makeClipFile()
        let session = FakeURLSession()
        session.handler = { _ in
            FakeURLSession.Reply(statusCode: 200, body: self.json(#"{"id":"file-xyz","status":"processing"}"#))
        }
        let client = ArkFileClient(session: session)

        let id = try await client.upload(fileURL: fileURL, model: "m", fps: 1, target: target(key: "secret-key"))

        XCTAssertEqual(id, "file-xyz")
        XCTAssertEqual(session.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer secret-key")
    }

    func testUploadMapsUnauthorizedAndRejected() async throws {
        let fileURL = try makeClipFile()

        let unauthorizedSession = FakeURLSession()
        unauthorizedSession.handler = { _ in
            FakeURLSession.Reply(statusCode: 401, body: self.json(#"{"error":{"message":"bad key"}}"#))
        }
        do {
            _ = try await ArkFileClient(session: unauthorizedSession)
                .upload(fileURL: fileURL, model: "m", fps: 1, target: target())
            XCTFail("401 必须抛 .unauthorized")
        } catch let error as ArkFileError {
            XCTAssertEqual(error, .unauthorized)
            XCTAssertFalse(error.summary.contains("test-key-ark"), "错误短句不能带 key")
        }

        let rejectedSession = FakeURLSession()
        rejectedSession.handler = { _ in
            FakeURLSession.Reply(statusCode: 400, body: self.json("quota exceeded"))
        }
        do {
            _ = try await ArkFileClient(session: rejectedSession)
                .upload(fileURL: fileURL, model: "m", fps: 1, target: target())
            XCTFail("非 2xx 必须抛 .rejected")
        } catch let error as ArkFileError {
            XCTAssertEqual(error, .rejected("quota exceeded"))
        }
    }

    // MARK: - 10. waitUntilActive：processing → active / failed / 超时

    func testWaitUntilActivePollsUntilActive() async throws {
        let session = FakeURLSession()
        var statuses = ["processing", "active"]
        session.handler = { _ in
            let status = statuses.isEmpty ? "active" : statuses.removeFirst()
            return FakeURLSession.Reply(
                statusCode: 200,
                body: Data("{\"id\":\"file-1\",\"status\":\"\(status)\"}".utf8)
            )
        }
        var sleeps: [TimeInterval] = []
        let client = ArkFileClient(
            session: session,
            pollInterval: 0.01,
            maxPolls: 10,
            sleep: { sleeps.append($0) }
        )

        try await client.waitUntilActive(id: "file-1", target: target(), timeout: 60, pollInterval: 0.01)

        XCTAssertEqual(session.requests.count, 2, "processing 后再查一次拿到 active")
        XCTAssertEqual(sleeps.count, 1, "中间只等待一次")
    }

    func testWaitUntilActiveThrowsProcessingFailedWithCloudMessage() async throws {
        let session = FakeURLSession()
        session.handler = { _ in
            FakeURLSession.Reply(
                statusCode: 200,
                body: self.json(#"{"id":"file-1","status":"failed","error":{"message":"InvalidVideoFormat"}}"#)
            )
        }
        let client = ArkFileClient(session: session, maxPolls: 5, sleep: { _ in })

        do {
            try await client.waitUntilActive(id: "file-1", target: target(), timeout: 5, pollInterval: 0.01)
            XCTFail("failed 必须抛 .processingFailed")
        } catch let error as ArkFileError {
            XCTAssertEqual(error, .processingFailed("InvalidVideoFormat"))
        }
    }

    func testWaitUntilActiveTimesOutWithoutRealWaiting() async throws {
        let session = FakeURLSession()
        session.handler = { _ in
            FakeURLSession.Reply(statusCode: 200, body: self.json(#"{"id":"file-1","status":"processing"}"#))
        }
        var sleeps = 0
        let client = ArkFileClient(
            session: session,
            pollInterval: 0.01,
            maxPolls: 3,
            sleep: { _ in sleeps += 1 }
        )

        do {
            try await client.waitUntilActive(id: "file-1", target: target(), timeout: 0.05, pollInterval: 0.01)
            XCTFail("轮询上限到必须抛 .timedOut")
        } catch let error as ArkFileError {
            XCTAssertEqual(error, .timedOut)
        }
        XCTAssertEqual(session.requests.count, 3, "maxPolls 兜底，不无限轮询")
        XCTAssertEqual(sleeps, 2)
    }

    // MARK: - 11. supportsVideo

    func testSupportsVideoOnlyForArkHost() {
        XCTAssertTrue(ProviderChainRunner.supportsVideo(baseURL: arkBaseURL))
        XCTAssertTrue(ProviderChainRunner.supportsVideo(
            provider: arkProvider()
        ))
        XCTAssertFalse(ProviderChainRunner.supportsVideo(baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1"))
        XCTAssertFalse(ProviderChainRunner.supportsVideo(baseURL: "https://api.deepseek.com/v1"))
        XCTAssertFalse(ProviderChainRunner.supportsVideo(baseURL: ""))
    }

    // MARK: - 12. 不支持视频的商跳过且不上传；下一跳用自己的 key 上传

    func testVideoChainSkipsUnsupportedProviderWithoutUpload() async throws {
        let clipURL = try makeClipFile()
        let client = FakeAIClient(behaviors: ["ark-m": FakeAIClient.Behavior(reply: "手型看清了。", error: nil)])
        let files = FakeFilesAPI()
        let runner = makeRunner(
            client: client,
            files: files,
            keys: ["bailian": "k-bailian", "ark": "k-ark"]
        )
        let providers = [
            provider("bailian", name: "百炼", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", models: ["bl-m"], order: 0),
            provider("ark", name: "火山方舟", baseURL: arkBaseURL, models: ["ark-m"], order: 1),
        ]

        let result = try await runner.run(
            providers: providers,
            input: videoInput(),
            video: videoRequest(clipURL: clipURL, modelOverride: "doubao-seed-2-1-pro-260915")
        )

        XCTAssertEqual(files.uploads.count, 1, "不支持视频的商不上传")
        XCTAssertEqual(files.uploads.first?.key, "k-ark", "必须用命中跳自己的 key")
        XCTAssertEqual(files.uploads.first?.baseURL, arkBaseURL)
        XCTAssertEqual(files.uploads.first?.model, "doubao-seed-2-1-pro-260915", "override 优先于 chat 模型")
        XCTAssertEqual(client.requestedModels, ["ark-m"])
        XCTAssertEqual(result.providerModel, "火山方舟 · ark-m")
        let skipped = try XCTUnwrap(result.attempts.first)
        XCTAssertFalse(skipped.succeeded)
        XCTAssertEqual(skipped.errorSummary, ProviderChainRunner.videoUnsupportedSummary)
    }

    // MARK: - 13. 成功后按开关删云端文件

    func testVideoChainDeletesCloudFileAfterSuccess() async throws {
        let clipURL = try makeClipFile()
        let client = FakeAIClient(behaviors: ["ark-m": FakeAIClient.Behavior(reply: "前 3 小节右手抬得太高。", error: nil)])
        let files = FakeFilesAPI()
        let runner = makeRunner(client: client, files: files)
        let input = videoInput()
        let result = try await runner.run(
            providers: [arkProvider()],
            input: input,
            video: videoRequest(clipURL: clipURL)
        )

        XCTAssertEqual(files.deletes, ["file-1"])
        XCTAssertEqual(
            result.videoAttachment,
            ChatVideoAttachment(
                startSec: 4,
                endSec: 12,
                durationSec: 8,
                providerModel: "火山方舟 · ark-m",
                cloudFileDeleted: true
            )
        )

        // 请求形态：user = parts[video_url(file_id), text]，文本沿用同一格式化逻辑
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.messages.count, 2)
        XCTAssertEqual(request.messages[0].role, "system")
        XCTAssertEqual(
            request.messages[1].content,
            .parts([
                ContentPart(kind: .videoURL, fileId: "file-1"),
                ContentPart(kind: .text, text: ProviderChainRunner.userText(for: input)),
            ])
        )
    }

    func testVideoChainKeepsCloudFileWhenDeleteToggleOff() async throws {
        let clipURL = try makeClipFile()
        let client = FakeAIClient(behaviors: ["ark-m": FakeAIClient.Behavior(reply: "ok", error: nil)])
        let files = FakeFilesAPI()
        let runner = makeRunner(client: client, files: files)

        let result = try await runner.run(
            providers: [arkProvider()],
            input: videoInput(),
            video: videoRequest(clipURL: clipURL, deleteCloudFile: false)
        )

        XCTAssertTrue(files.deletes.isEmpty, "开关 OFF 不删云端文件")
        XCTAssertEqual(result.videoAttachment?.cloudFileDeleted, false, "如实记录没删")
        XCTAssertEqual(result.videoAttachment?.providerModel, "火山方舟 · ark-m")
    }

    // MARK: - 14. 失败跳也删；删除失败不改变提问结果

    func testVideoChainDeletesAfterFailedHopAndDeleteErrorDoesNotFailQuestion() async throws {
        let clipURL = try makeClipFile()
        let client = FakeAIClient(behaviors: [
            "a1": FakeAIClient.Behavior(reply: nil, error: .unauthorized),
            "a2": FakeAIClient.Behavior(reply: "第二家答的。", error: nil),
        ])
        let files = FakeFilesAPI()
        files.deleteError = ArkFileError.network("offline")

        // 两家都是 Ark（都支持视频），各自用自己的 key 上传
        let providers = [
            provider("ark1", name: "方舟一", baseURL: arkBaseURL, models: ["a1"], order: 0),
            provider("ark2", name: "方舟二", baseURL: arkBaseURL, models: ["a2"], order: 1),
        ]
        let runner = makeRunner(
            client: client,
            files: files,
            keys: ["ark1": "k-1", "ark2": "k-2"]
        )

        let result = try await runner.run(
            providers: providers,
            input: videoInput(),
            video: videoRequest(clipURL: clipURL)
        )

        XCTAssertEqual(result.text, "第二家答的。", "删除失败不能让整次提问失败")
        XCTAssertEqual(result.providerModel, "方舟二 · a2")
        XCTAssertEqual(files.uploads.map(\.key), ["k-1", "k-2"], "每跳用自己的 key 上传")
        XCTAssertEqual(files.deletes.count, 2, "失败跳与成功跳都要删云端文件")
        XCTAssertEqual(result.videoAttachment?.cloudFileDeleted, false, "删除失败如实为 false")

        let deleteDiagnostics = runner.diagnostics.filter { $0.modelId == "file-delete" }
        XCTAssertEqual(deleteDiagnostics.count, 2)
        XCTAssertTrue(deleteDiagnostics.allSatisfy { !$0.succeeded })
        XCTAssertTrue(result.attempts.allSatisfy { $0.modelId != "file-delete" }, "删除诊断不进每跳结果")
    }

    func testDeleteFailureAfterWholeChainFailureDoesNotMaskChainFailure() async throws {
        let clipURL = try makeClipFile()
        let client = FakeAIClient(behaviors: [
            "a1": FakeAIClient.Behavior(reply: nil, error: .unauthorized),
            "a2": FakeAIClient.Behavior(reply: nil, error: .modelNotOpen),
        ])
        let files = FakeFilesAPI()
        files.deleteError = ArkFileError.rejected("delete failed")

        let providers = [
            provider("ark1", name: "方舟一", baseURL: arkBaseURL, models: ["a1"], order: 0),
            provider("ark2", name: "方舟二", baseURL: arkBaseURL, models: ["a2"], order: 1),
        ]
        let runner = makeRunner(client: client, files: files, keys: ["ark1": "k-1", "ark2": "k-2"])

        do {
            _ = try await runner.run(
                providers: providers,
                input: videoInput(),
                video: videoRequest(clipURL: clipURL)
            )
            XCTFail("全链失败必须抛 ProviderChainFailure")
        } catch let failure as ProviderChainFailure {
            XCTAssertEqual(failure.attempts.count, 2, "删除失败不冒充提问跳")
            XCTAssertEqual(failure.attempts[0].errorSummary, AIProviderError.unauthorized.summary)
            XCTAssertEqual(failure.attempts[1].errorSummary, AIProviderError.modelNotOpen.summary)
        }
        XCTAssertEqual(files.deletes.count, 2)
    }

    // MARK: - 15. 纯文字链完全不走 Files API

    func testTextOnlyChainDoesNotTouchFilesAPI() async throws {
        let client = FakeAIClient(behaviors: ["ark-m": FakeAIClient.Behavior(reply: "legato 是连奏。", error: nil)])
        let files = FakeFilesAPI()
        let runner = makeRunner(client: client, files: files)

        let result = try await runner.run(
            providers: [arkProvider()],
            input: ChainInput(question: "什么是 legato？")
        )

        XCTAssertTrue(files.uploads.isEmpty)
        XCTAssertTrue(files.deletes.isEmpty)
        XCTAssertNil(result.videoAttachment)
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.messages.count, 1)
        XCTAssertEqual(request.messages[0].content, .text("什么是 legato？"))
    }
}

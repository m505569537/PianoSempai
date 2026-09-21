import SwiftData
import XCTest

@testable import PianoSempai

/// M7.1 Stage B2 · S18 问答协调层验收（brief §测试 场景 1–6 + 边界）。
/// 全程假 runner / 假 keystore / 假服务商源 + 内存 ModelContainer：不打网络、不碰真实 Keychain。
@MainActor
final class ChatStoreTests: XCTestCase {

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

    private final class FakeChainRunner: ChatChainRunning {
        struct Behavior {
            var result: ChainResult?
            var failure: ProviderChainFailure?
        }

        var behaviors: [Behavior] = []
        private(set) var inputs: [ChainInput] = []
        private(set) var providerCounts: [Int] = []

        func run(providers: [AIProvider], input: ChainInput) async throws -> ChainResult {
            providerCounts.append(providers.count)
            inputs.append(input)
            if behaviors.isEmpty {
                throw AIProviderError.decoding("假 runner 未配置该次调用的行为")
            }
            let behavior = behaviors.removeFirst()
            if let failure = behavior.failure { throw failure }
            if let result = behavior.result { return result }
            throw AIProviderError.decoding("假 runner 未配置回复")
        }
    }

    private final class FakeProviderSource: ChatProviderSource {
        var providers: [AIProvider]

        init(_ providers: [AIProvider]) {
            self.providers = providers
        }

        func currentProviders() -> [AIProvider] { providers }
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

    // MARK: - 夹具

    private func makeTake(
        pieceId: UUID? = nil,
        startedAt: Date = Date(timeIntervalSince1970: 1_758_000_000),
        measureFrom: Int? = 12,
        measureTo: Int? = 20,
        durationSec: Int = 134,
        tempoAvg: Int = 72,
        noteCount: Int = 132,
        wrongNoteCount: Int = 2,
        taskType: String = "main",
        title: String = "拜厄 45"
    ) -> Take {
        Take(
            startedAt: startedAt,
            durationSec: durationSec,
            taskType: taskType,
            hasMidi: true,
            measureFrom: measureFrom,
            measureTo: measureTo,
            tempoAvg: tempoAvg,
            noteCount: noteCount,
            wrongNoteCount: wrongNoteCount,
            pieceId: pieceId,
            title: title
        )
    }

    private func makeAnalysis(
        takeId: UUID = UUID(),
        confidence: Double = 0.82,
        pitch: Int? = 74,
        rhythm: Int? = 61,
        wrongCount: Int = 3,
        missingCount: Int = 1,
        rhythmMedianMs: Double = 38,
        avgBPM: Double = 70,
        hotspots: [Int] = [12, 15],
        alignmentJSON: String = "[]"
    ) -> TakeAnalysis {
        TakeAnalysis(
            takeId: takeId,
            engineVersion: "P2-scoring-1.0",
            confidence: confidence,
            lowConfidenceReasons: ["可计时匹配不足 8 个"],
            pitchScore: pitch, rhythmScore: rhythm,
            wrongCount: wrongCount, missingCount: missingCount,
            rhythmMedianMs: rhythmMedianMs, avgBPM: avgBPM,
            hotspotMeasures: hotspots, canEvaluate: false,
            alignmentJSON: alignmentJSON
        )
    }

    private func provider(_ id: String, models: [String], enabled: Bool = true) -> AIProvider {
        AIProvider(
            providerId: id,
            displayName: "服务商 \(id)",
            baseURL: "https://\(id).example.com/api/v3",
            modelIds: models,
            enabled: enabled,
            sortOrder: 0
        )
    }

    private func makeStore(
        mode: ChatMode,
        runner: FakeChainRunner,
        providers: [AIProvider] = [],
        keys: [String: String] = [:]
    ) -> ChatStore {
        ChatStore(
            mode: mode,
            context: context,
            keyStore: FakeProviderKeyStore(keys: keys),
            runner: runner,
            providerSource: FakeProviderSource(providers)
        )
    }

    private func reply(_ text: String, _ providerModel: String) -> FakeChainRunner.Behavior {
        FakeChainRunner.Behavior(
            result: ChainResult(text: text, providerModel: providerModel, evidenceRefs: [], attempts: []),
            failure: nil
        )
    }

    private func failing(_ attempts: [ProviderChainFailure.Attempt]) -> FakeChainRunner.Behavior {
        FakeChainRunner.Behavior(result: nil, failure: ProviderChainFailure(attempts: attempts))
    }

    /// 等 store 的后台调用结束（isSending 在 send 里同步置位，故不会漏等）
    private func waitForIdle(_ store: ChatStore) async {
        for _ in 0..<400 where store.isSending {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func fetchedMessages() throws -> [ChatMessage] {
        try context.fetch(FetchDescriptor<ChatMessage>())
    }

    private func fetchedThreads() throws -> [ChatThread] {
        try context.fetch(FetchDescriptor<ChatThread>())
    }

    // MARK: ① 自由问答：建 thread(takeContextId=nil) → user + neko，providerModel 透传

    func testFreeformSendCreatesThreadAndPersistsBothMessages() async throws {
        let runner = FakeChainRunner()
        runner.behaviors = [reply("转指先单手 ♩=60 弹四遍，每遍之间甩手 10 秒。", "服务商 ark · doubao-pro")]
        let store = makeStore(
            mode: .freeform,
            runner: runner,
            providers: [provider("ark", models: ["doubao-pro"])],
            keys: ["ark": "k-ark"]
        )

        XCTAssertTrue(store.hasAvailableProvider)
        XCTAssertNil(store.threadId, "没发过消息就不该有会话")
        XCTAssertTrue(store.messages.isEmpty)

        store.send(text: "  21 小节我总卡，怎么办？  ")
        await waitForIdle(store)

        XCTAssertEqual(store.messages.map(\.role), ["user", "neko"])
        XCTAssertEqual(store.messages[0].text, "21 小节我总卡，怎么办？", "首尾空白 trim 后落库")
        XCTAssertEqual(store.messages[1].text, "转指先单手 ♩=60 弹四遍，每遍之间甩手 10 秒。")
        XCTAssertEqual(store.messages[1].providerModel, "服务商 ark · doubao-pro", "命中的「服务商·模型」原样透传")
        XCTAssertEqual(store.messages[0].providerModel, "", "user 消息不写 providerModel")
        XCTAssertEqual(store.messages[0].evidenceRefsJSON, "[]", "user 消息不带证据")
        XCTAssertFalse(store.isSending)
        XCTAssertNil(store.failure)

        // 会话落库：自由问答 takeContextId = nil
        let threads = try fetchedThreads()
        XCTAssertEqual(threads.count, 1)
        XCTAssertNil(threads[0].takeContextId)
        XCTAssertEqual(store.threadId, threads[0].entityId)
        XCTAssertEqual(try fetchedMessages().count, 2)

        // 自由问答不带任何练习数据
        XCTAssertEqual(runner.inputs.count, 1)
        XCTAssertEqual(runner.inputs[0].contextBlock, "")
        XCTAssertTrue(runner.inputs[0].systemPrompt.contains("本次是自由问答"))
        XCTAssertTrue(runner.inputs[0].evidenceRefs.isEmpty)
        XCTAssertEqual(runner.providerCounts, [1])
        XCTAssertFalse(store.hasTakeContext)
    }

    // MARK: ② take 问答：takeContextId + 真实 take/analysis + 证据落库

    func testTakeSendCarriesRealContextAndEvidence() async throws {
        let take = makeTake()
        let analysis = makeAnalysis(takeId: take.entityId)
        context.insert(take)
        context.insert(analysis)

        let runner = FakeChainRunner()
        runner.behaviors = [reply("第 12 小节转指平均慢了 30ms，主要是 3 指转 1 指手腕没提前带过去。", "服务商 bl · qwen-plus")]
        let store = makeStore(
            mode: .take(take, analysis: analysis, pieceTitle: "拜厄 45"),
            runner: runner,
            providers: [provider("bl", models: ["qwen-plus"])],
            keys: ["bl": "k-bl"]
        )

        store.send(text: "第 12 小节为什么总错音？")
        await waitForIdle(store)

        // 会话挂在这次 take 上
        let threads = try fetchedThreads()
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].takeContextId, take.entityId)
        XCTAssertEqual(store.threadId, threads[0].entityId)
        XCTAssertTrue(store.hasTakeContext)

        // ContextBuilder 用的是真实 take/analysis（不是假数据）
        let input = try XCTUnwrap(runner.inputs.first)
        XCTAssertTrue(input.contextBlock.contains("练习小节区间：第 12–20 小节"))
        XCTAssertTrue(input.contextBlock.contains("时长：134 秒"))
        XCTAssertTrue(input.contextBlock.contains("对齐置信度：82%"))
        XCTAssertTrue(input.contextBlock.contains("错音 3 / 漏音 1"))
        XCTAssertFalse(input.systemPrompt.contains("本次是自由问答"), "带上下文时不用自由问答口径")
        XCTAssertEqual(input.evidenceRefs.map(\.measure), [12, 15])

        // neko 消息的 evidenceRefsJSON 含本次证据（本地组装的那一份）
        let neko = try XCTUnwrap(store.messages.last)
        XCTAssertEqual(neko.role, "neko")
        let decoded = try XCTUnwrap(AIJSON.decode([EvidenceRef].self, from: neko.evidenceRefsJSON))
        XCTAssertEqual(decoded.map(\.measure), [12, 15])
        XCTAssertTrue(decoded.allSatisfy { $0.takeId == take.entityId })
    }

    // MARK: ③ 全链失败：不写成功消息、进失败态、重试不重复落 user 消息

    func testWholeChainFailureKeepsMessageAndRetryDoesNotDuplicateUserMessage() async throws {
        let runner = FakeChainRunner()
        let chainFailure = ProviderChainFailure(attempts: [
            ProviderChainFailure.Attempt(
                providerId: "ark", providerDisplayName: "服务商 ark", modelId: "m1",
                errorSummary: "401/403：Key 无效或无权限"
            ),
            ProviderChainFailure.Attempt(
                providerId: "bl", providerDisplayName: "服务商 bl", modelId: "m2",
                errorSummary: "网络失败：The Internet connection appears to be offline."
            ),
        ])
        runner.behaviors = [
            failing(chainFailure.attempts),
            reply("重试就连上了。", "服务商 bl · m2"),
        ]
        let store = makeStore(
            mode: .freeform,
            runner: runner,
            providers: [provider("ark", models: ["m1"]), provider("bl", models: ["m2"])],
            keys: ["ark": "k-ark", "bl": "k-bl"]
        )

        store.send(text: "第 12 小节怎么办？")
        await waitForIdle(store)

        XCTAssertEqual(store.messages.map(\.role), ["user"], "全链失败不写成功的 neko 消息")
        XCTAssertNotNil(store.threadId, "user 消息要挂到会话上")
        XCTAssertNotNil(store.failure)
        XCTAssertEqual(store.failure?.attempts.count, 2)
        XCTAssertTrue(store.failure?.summary.contains("全部 2 跳都失败") == true)
        XCTAssertTrue(store.failure?.summary.contains("服务商 ark·m1") == true)
        XCTAssertTrue(store.failure?.summary.contains("401/403") == true)
        XCTAssertEqual(try fetchedMessages().filter { $0.role == "neko" }.count, 0)

        // 重试：重发同一条用户输入，不重复落 user 消息
        store.retry()
        await waitForIdle(store)

        XCTAssertEqual(store.messages.map(\.role), ["user", "neko"])
        XCTAssertEqual(store.messages[1].text, "重试就连上了。")
        XCTAssertEqual(runner.inputs.count, 2, "两次调用")
        XCTAssertEqual(runner.inputs[1].question, "第 12 小节怎么办？", "重试用同一条输入")
        XCTAssertNil(store.failure)
        XCTAssertEqual(try fetchedMessages().filter { $0.role == "user" }.count, 1, "不重复落 user 消息")

        // 再发一条新问题 = 新 user 消息（旧失败的那轮仍原样留在会话里）
        runner.behaviors = [reply("第二个问题也能答。", "服务商 bl · m2")]
        store.send(text: "那慢练几遍合适？")
        await waitForIdle(store)
        XCTAssertEqual(store.messages.map(\.role), ["user", "neko", "user", "neko"])
        XCTAssertEqual(store.messages[2].text, "那慢练几遍合适？")
    }

    func testNonChainErrorAlsoEntersFailureStateWithoutNekoMessage() async throws {
        let runner = FakeChainRunner()
        runner.behaviors = [FakeChainRunner.Behavior(result: nil, failure: nil)] // 抛未知错误
        let store = makeStore(
            mode: .freeform,
            runner: runner,
            providers: [provider("ark", models: ["m1"])],
            keys: ["ark": "k-ark"]
        )

        store.send(text: "什么是 legato？")
        await waitForIdle(store)

        XCTAssertEqual(store.messages.map(\.role), ["user"])
        XCTAssertNotNil(store.failure, "非 ProviderChainFailure 的错误也要进失败态，不吞")
        XCTAssertTrue(store.failure?.summary.contains("未知错误") == true)
    }

    // MARK: ④ 无可用服务商：进入即空态、输入禁用（send 直接不动作）

    func testNoAvailableProviderShowsEmptyStateAndBlocksSend() async throws {
        let runner = FakeChainRunner()
        // 有服务商但没配 Key
        let store = makeStore(
            mode: .freeform,
            runner: runner,
            providers: [provider("ark", models: ["doubao-pro"])],
            keys: [:]
        )

        XCTAssertFalse(store.hasAvailableProvider)
        XCTAssertEqual(store.summary.state, .noneAvailable)
        XCTAssertEqual(store.summary.total, 1)
        XCTAssertEqual(store.summary.available, 0)

        store.send(text: "请问 legato 怎么练？")
        await waitForIdle(store)

        XCTAssertTrue(store.messages.isEmpty, "无可用服务商不该发请求、不落消息")
        XCTAssertNil(store.threadId)
        XCTAssertTrue(runner.inputs.isEmpty, "没有可用服务商就不调链")
        XCTAssertEqual(try fetchedThreads().count, 0)
        XCTAssertNil(store.failure)
    }

    func testProvidersWithoutModelsOrDisabledAreNotAvailable() async throws {
        // 有 Key 但没配模型
        let noModels = makeStore(
            mode: .freeform,
            runner: FakeChainRunner(),
            providers: [provider("ark", models: [])],
            keys: ["ark": "k-ark"]
        )
        XCTAssertFalse(noModels.hasAvailableProvider)

        // 已停用
        let disabled = makeStore(
            mode: .freeform,
            runner: FakeChainRunner(),
            providers: [provider("ark", models: ["m1"], enabled: false)],
            keys: ["ark": "k-ark"]
        )
        XCTAssertFalse(disabled.hasAvailableProvider)

        // 链上什么都没有
        let empty = makeStore(mode: .freeform, runner: FakeChainRunner(), providers: [], keys: [:])
        XCTAssertFalse(empty.hasAvailableProvider)
        XCTAssertEqual(empty.summary.state, .empty)
    }

    func testRefreshAvailabilityPicksUpNewlyAddedKey() async throws {
        let store = makeStore(
            mode: .freeform,
            runner: FakeChainRunner(),
            providers: [provider("ark", models: ["m1"])],
            keys: [:]
        )
        XCTAssertFalse(store.hasAvailableProvider)

        // 用户在 S25 填了 Key 后回到对话页
        store.refreshAvailability()
        XCTAssertFalse(store.hasAvailableProvider, "Keychain 没变就不该变成可用")
    }

    // MARK: ⑤ 证据缺 deviationMs → 不编造偏差

    func testEvidenceWithoutDeviationIsNeverFabricated() async throws {
        let take = makeTake()
        // 只有热点小节、没有逐音明细 → 本地算不出小节偏差
        let analysis = makeAnalysis(takeId: take.entityId, hotspots: [12, 15], alignmentJSON: "[]")
        context.insert(take)
        context.insert(analysis)

        let runner = FakeChainRunner()
        runner.behaviors = [reply("第 12、15 小节是热点。", "服务商 ark · m1")]
        let store = makeStore(
            mode: .take(take, analysis: analysis, pieceTitle: "拜厄 45"),
            runner: runner,
            providers: [provider("ark", models: ["m1"])],
            keys: ["ark": "k-ark"]
        )

        store.send(text: "哪些小节最需要慢练？")
        await waitForIdle(store)

        let neko = try XCTUnwrap(store.messages.last)
        let decoded = try XCTUnwrap(AIJSON.decode([EvidenceRef].self, from: neko.evidenceRefsJSON))
        XCTAssertEqual(decoded.map(\.measure), [12, 15])
        XCTAssertTrue(decoded.allSatisfy { $0.deviationMs == nil }, "算不出偏差就留 nil，不补 0")

        // 落库 JSON 里也不该出现伪造的 0（nil 被整体省略，不写 deviationMs:0）
        XCTAssertFalse(neko.evidenceRefsJSON.contains("deviationMs\":0"))
        XCTAssertTrue(neko.evidenceRefsJSON.contains("\"measure\":12"))
        XCTAssertTrue(neko.evidenceRefsJSON.contains("\"measure\":15"))

        // 视图层同样不显示偏差
        XCTAssertNil(EvidenceChipText.deviation(decoded[0]))
        XCTAssertEqual(EvidenceChipText.measure(decoded[0]), "第 12 小节")
    }

    func testEvidenceDeviationComesFromAlignedNotesWhenAvailable() async throws {
        let take = makeTake()
        // 第 12 小节两个非 correct 音：+40ms / -20ms → 均值 30ms
        let aligned = """
        [
          {"refMeasureIndex":11,"refBeatInMeasure":1,"refPitch":60,"playedPitch":61,"deltaMs":40,"cls":"wrongPitch","hand":"right"},
          {"refMeasureIndex":11,"refBeatInMeasure":2,"refPitch":62,"playedPitch":62,"deltaMs":40,"cls":"correct","hand":"right"},
          {"refMeasureIndex":11,"refBeatInMeasure":3,"refPitch":64,"playedPitch":null,"deltaMs":-20,"cls":"missing","hand":"right"}
        ]
        """
        let analysis = makeAnalysis(takeId: take.entityId, hotspots: [12, 15], alignmentJSON: aligned)
        context.insert(take)
        context.insert(analysis)

        let runner = FakeChainRunner()
        runner.behaviors = [reply("第 12 小节慢 30ms。", "服务商 ark · m1")]
        let store = makeStore(
            mode: .take(take, analysis: analysis, pieceTitle: "拜厄 45"),
            runner: runner,
            providers: [provider("ark", models: ["m1"])],
            keys: ["ark": "k-ark"]
        )

        store.send(text: "第 12 小节差多少？")
        await waitForIdle(store)

        let neko = try XCTUnwrap(store.messages.last)
        let decoded = try XCTUnwrap(AIJSON.decode([EvidenceRef].self, from: neko.evidenceRefsJSON))
        XCTAssertEqual(decoded[0].measure, 12)
        XCTAssertEqual(decoded[0].deviationMs ?? -1, 30, accuracy: 0.001)
        XCTAssertNil(decoded[1].deviationMs)
        XCTAssertEqual(EvidenceChipText.deviation(decoded[0]), "偏差 30 ms")
        XCTAssertNil(EvidenceChipText.deviation(decoded[1]))
    }

    // MARK: ⑥ 同一会话多轮：复用同一 threadId、消息按序

    func testMultipleTurnsReuseOneThreadAndKeepOrder() async throws {
        let runner = FakeChainRunner()
        runner.behaviors = [
            reply("第一轮回答。", "服务商 ark · m1"),
            reply("第二轮回答。", "服务商 ark · m1"),
            reply("第三轮回答。", "服务商 ark · m1"),
        ]
        let store = makeStore(
            mode: .freeform,
            runner: runner,
            providers: [provider("ark", models: ["m1"])],
            keys: ["ark": "k-ark"]
        )

        store.send(text: "第一问")
        await waitForIdle(store)
        store.send(text: "第二问")
        await waitForIdle(store)
        store.send(text: "第三问")
        await waitForIdle(store)

        XCTAssertEqual(store.messages.map(\.text), ["第一问", "第一轮回答。", "第二问", "第二轮回答。", "第三问", "第三轮回答。"])
        XCTAssertEqual(store.messages.map(\.role), ["user", "neko", "user", "neko", "user", "neko"])

        let messages = try fetchedMessages()
        XCTAssertEqual(messages.count, 6)
        XCTAssertEqual(Set(messages.map(\.threadId)).count, 1, "多轮复用同一会话")
        XCTAssertEqual(store.threadId, messages[0].threadId)
        XCTAssertEqual(try fetchedThreads().count, 1)
        XCTAssertEqual(runner.inputs.map(\.question), ["第一问", "第二问", "第三问"])
    }

    // MARK: 边界：空文本 / 会话复用 / 上下文文案

    func testBlankTextIsIgnored() async throws {
        let runner = FakeChainRunner()
        let store = makeStore(
            mode: .freeform,
            runner: runner,
            providers: [provider("ark", models: ["m1"])],
            keys: ["ark": "k-ark"]
        )

        store.send(text: "   \n  ")
        await waitForIdle(store)

        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertNil(store.threadId)
        XCTAssertTrue(runner.inputs.isEmpty)
        XCTAssertEqual(try fetchedThreads().count, 0)
    }

    func testTakeThreadIsReusedWhenReopeningTheReport() async throws {
        let take = makeTake()
        let analysis = makeAnalysis(takeId: take.entityId)
        context.insert(take)
        context.insert(analysis)

        let runner = FakeChainRunner()
        runner.behaviors = [reply("第一次进来答。", "服务商 ark · m1")]
        let first = makeStore(
            mode: .take(take, analysis: analysis, pieceTitle: "拜厄 45"),
            runner: runner,
            providers: [provider("ark", models: ["m1"])],
            keys: ["ark": "k-ark"]
        )
        first.send(text: "第一次问")
        await waitForIdle(first)
        let threadId = try XCTUnwrap(first.threadId)

        // 关掉再开（同一 take）：复用已有会话，历史消息从 DB 回填
        let secondRunner = FakeChainRunner()
        secondRunner.behaviors = [reply("第二次进来答。", "服务商 ark · m1")]
        let second = makeStore(
            mode: .take(take, analysis: analysis, pieceTitle: "拜厄 45"),
            runner: secondRunner,
            providers: [provider("ark", models: ["m1"])],
            keys: ["ark": "k-ark"]
        )
        XCTAssertEqual(second.threadId, threadId, "同一 take 复用已有会话")
        XCTAssertEqual(second.messages.map(\.text), ["第一次问", "第一次进来答。"])
        XCTAssertEqual(try fetchedThreads().count, 1, "不重复建会话")

        // 接着问：消息继续追加到同一会话
        second.send(text: "第二次问")
        await waitForIdle(second)
        XCTAssertEqual(second.messages.map(\.text), ["第一次问", "第一次进来答。", "第二次问", "第二次进来答。"])
        XCTAssertEqual(try fetchedThreads().count, 1)
    }

    func testFreeformThreadIsNotReusedAcrossStores() async throws {
        let runner = FakeChainRunner()
        runner.behaviors = [reply("答。", "服务商 ark · m1")]
        let first = makeStore(
            mode: .freeform,
            runner: runner,
            providers: [provider("ark", models: ["m1"])],
            keys: ["ark": "k-ark"]
        )
        first.send(text: "问")
        await waitForIdle(first)

        // 自由问答每次进来都是新会话（历史会话列表非 M7.1 必需）
        let second = makeStore(
            mode: .freeform,
            runner: FakeChainRunner(),
            providers: [provider("ark", models: ["m1"])],
            keys: ["ark": "k-ark"]
        )
        XCTAssertNil(second.threadId)
        XCTAssertTrue(second.messages.isEmpty)
        XCTAssertEqual(try fetchedThreads().count, 1)
    }

    func testPracticeIndexCountsSamePieceTakesOnly() async throws {
        let pieceId = UUID()
        let first = makeTake(pieceId: pieceId, startedAt: Date(timeIntervalSince1970: 1_000))
        let second = makeTake(pieceId: pieceId, startedAt: Date(timeIntervalSince1970: 2_000))
        let otherPiece = makeTake(pieceId: UUID(), startedAt: Date(timeIntervalSince1970: 1_500))
        let noPiece = makeTake(pieceId: nil, startedAt: Date(timeIntervalSince1970: 500))
        [first, second, otherPiece, noPiece].forEach { context.insert($0) }

        let takes = (try? context.fetch(FetchDescriptor<Take>())) ?? []
        XCTAssertEqual(ChatContextText.practiceIndex(of: second, among: takes), 2)
        XCTAssertEqual(ChatContextText.practiceIndex(of: first, among: takes), 1)
        XCTAssertEqual(ChatContextText.practiceIndex(of: otherPiece, among: takes), 1)
        XCTAssertNil(ChatContextText.practiceIndex(of: noPiece, among: takes), "没有 pieceId 就算不出第几次，不编")
    }

    func testContextChipAndTitleUseRealTakeFields() async throws {
        let take = makeTake(pieceId: UUID(), startedAt: Date(timeIntervalSince1970: 1_758_000_000))

        // 自由问答
        XCTAssertEqual(ChatContextText.title(mode: .freeform), "问 Neko")
        XCTAssertEqual(ChatContextText.chip(mode: .freeform, practiceIndex: nil), "自由提问 · 不附带练习数据")

        // take 问答：序号 + 日期 + 曲名
        let mode: ChatMode = .take(take, analysis: nil, pieceTitle: "拜厄 45")
        XCTAssertEqual(ChatContextText.title(mode: mode), "拜厄 45")
        XCTAssertEqual(
            ChatContextText.chip(mode: mode, practiceIndex: 3),
            "第 3 次练习 · \(ChatContextText.stamp(take.startedAt)) · 拜厄 45"
        )

        // 没有曲名就退回小节区间，再不行退回中性描述（不编曲名）
        let bare = makeTake(pieceId: nil, measureFrom: 12, measureTo: 20, title: "")
        XCTAssertEqual(ChatContextText.title(mode: .take(bare, analysis: nil, pieceTitle: nil)), "第 12–20 小节")
        XCTAssertEqual(
            ChatContextText.title(mode: .take(makeTake(measureFrom: nil, measureTo: nil, title: ""), analysis: nil, pieceTitle: nil)),
            "练习 take"
        )
        XCTAssertEqual(ChatContextText.chip(mode: .take(bare, analysis: nil, pieceTitle: nil), practiceIndex: nil), "\(ChatContextText.stamp(take.startedAt)) · 第 12–20 小节")
    }

    func testDegradationIsSurfacedWhenTakeHasNoAnalysis() async throws {
        let take = makeTake()
        context.insert(take)
        let store = makeStore(
            mode: .take(take, analysis: nil, pieceTitle: "拜厄 45"),
            runner: FakeChainRunner(),
            providers: [provider("ark", models: ["m1"])],
            keys: ["ark": "k-ark"]
        )

        XCTAssertTrue(store.hasTakeContext)
        XCTAssertEqual(store.contextDegradations, ["该 take 暂无判分结果，只用 take 自身的真实统计（时长/速度/音符数/错音数）"])
        XCTAssertTrue(store.contextOutput?.contextBlock.contains("时长：134 秒") == true)
        XCTAssertFalse(store.contextOutput?.contextBlock.contains("六维得分") == true, "没有判分就不出现六维段落")
    }

    // MARK: 红线：AI 只建议、不写任何状态；Key 不入库

    func testAnswerNeverWritesCourseOrScoringState() async throws {
        let take = makeTake()
        let analysis = makeAnalysis(takeId: take.entityId)
        context.insert(take)
        context.insert(analysis)
        // 放几个会被"AI 指令"误改的对象，验证数量与字段都不动
        let plan = DailyPlan(date: Date(), durationChoice: 30)
        let piece = Piece(title: "拜厄 45", book: "拜厄", number: 45, status: "notStarted")
        let settings = AppSettings()
        context.insert(plan)
        context.insert(piece)
        context.insert(settings)

        let runner = FakeChainRunner()
        // 回答里带"指令式"内容：只应被渲染，不该被执行
        runner.behaviors = [reply("建议回退拜厄第 40 条，并把节奏阈值改成 ±40ms，本周目标改 7 次。", "服务商 ark · m1")]
        let store = makeStore(
            mode: .take(take, analysis: analysis, pieceTitle: "拜厄 45"),
            runner: runner,
            providers: [provider("ark", models: ["m1"])],
            keys: ["ark": "k-ark"]
        )

        store.send(text: "我该怎么调整？")
        await waitForIdle(store)

        XCTAssertEqual(store.messages.last?.text, "建议回退拜厄第 40 条，并把节奏阈值改成 ±40ms，本周目标改 7 次。", "回答原样落库（只渲染）")
        XCTAssertEqual(piece.status, "notStarted", "AI 不改曲目状态")
        XCTAssertEqual(plan.durationChoice, 30, "AI 不改今日计划")
        XCTAssertEqual(settings.weeklyGoal, 3, "AI 不改设置")
        XCTAssertEqual(analysis.canEvaluate, false, "AI 不改判分结果")
        XCTAssertEqual(analysis.wrongCount, 3)
        XCTAssertEqual((try? context.fetch(FetchDescriptor<Piece>()))?.count, 1)
    }

    func testPersistedMessagesNeverContainKeyMaterial() async throws {
        let runner = FakeChainRunner()
        runner.behaviors = [reply("答。", "服务商 ark · m1")]
        let store = makeStore(
            mode: .freeform,
            runner: runner,
            providers: [provider("ark", models: ["m1"])],
            keys: ["ark": "sk-super-secret-key"]
        )

        store.send(text: "问")
        await waitForIdle(store)

        for message in try fetchedMessages() {
            XCTAssertFalse(message.text.contains("sk-super-secret-key"))
            XCTAssertFalse(message.providerModel.contains("sk-super-secret-key"))
            XCTAssertFalse(message.evidenceRefsJSON.contains("sk-super-secret-key"))
            XCTAssertFalse(message.attachmentsJSON.contains("key"))
        }
    }
}

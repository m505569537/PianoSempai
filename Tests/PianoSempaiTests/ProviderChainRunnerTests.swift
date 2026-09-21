import XCTest
@testable import PianoSempai

/// M7.1 多服务商故障转移链验收（brief §5 场景 1–5 + 边界）。
/// 全程假 client / 假 keystore，不打真实网络、不碰真实 Keychain。
final class ProviderChainRunnerTests: XCTestCase {

    // MARK: - 假依赖

    /// 按 modelId 决定行为的假 client（记录被请求的模型顺序）
    private final class FakeAIClient: AIClient {
        struct Behavior {
            var reply: String?
            var error: AIProviderError?
        }

        var behaviors: [String: Behavior]
        private(set) var requestedModels: [String] = []
        private(set) var lastRequest: ChatCompletionRequest?

        init(behaviors: [String: Behavior]) {
            self.behaviors = behaviors
        }

        func send(_ request: ChatCompletionRequest, target: AIRequestTarget) async throws -> String {
            requestedModels.append(target.model)
            lastRequest = request
            let behavior = behaviors[target.model] ?? FakeAIClient.Behavior(reply: nil, error: .http(status: 500, code: "NoBehaviorConfigured"))
            if let error = behavior.error { throw error }
            guard let reply = behavior.reply else {
                throw AIProviderError.decoding("假 client 未配置该模型的回复")
            }
            return reply
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

    // MARK: - 夹具

    private func provider(_ id: String, name: String, models: [String], order: Int, enabled: Bool = true) -> AIProvider {
        AIProvider(providerId: id, displayName: name, baseURL: "https://\(id).example.com/api/v3", modelIds: models, enabled: enabled, sortOrder: order)
    }

    private func makeRunner(
        client: FakeAIClient,
        keys: [String: String] = ["ark": "k-ark", "bailian": "k-bailian", "deepseek": "k-ds"],
        recovery: ChainRecoveryStrategy = .stickyOnly,
        maxDiagnostics: Int = 50
    ) -> ProviderChainRunner {
        ProviderChainRunner(client: client, keyStore: FakeProviderKeyStore(keys: keys), recovery: recovery, maxDiagnosticEntries: maxDiagnostics)
    }

    private func chainInput(question: String = "第 12 小节为什么总错音？") -> ChainInput {
        ChainInput(
            question: question,
            systemPrompt: ContextBuilder.systemPrompt(freeQnA: false),
            contextBlock: "练习小节区间：第 12–20 小节",
            evidenceRefs: [EvidenceRef(takeId: UUID(), measure: 12)],
            temperature: 0.2
        )
    }

    // MARK: ① 链首模型成功 → 只调它、返回命中名

    func testFirstModelSuccessOnlyCallsIt() async throws {
        let client = FakeAIClient(behaviors: [
            "m-fast": FakeAIClient.Behavior(reply: "第 12 小节是转指，慢练三遍。", error: nil),
            "m-slow": FakeAIClient.Behavior(reply: "不该被调用", error: nil),
        ])
        let runner = makeRunner(client: client)
        let providers = [provider("ark", name: "火山方舟", models: ["m-fast", "m-slow"], order: 0)]

        let result = try await runner.run(providers: providers, input: chainInput())

        XCTAssertEqual(client.requestedModels, ["m-fast"], "链首成功就不再试探后续模型")
        XCTAssertEqual(result.text, "第 12 小节是转指，慢练三遍。")
        XCTAssertEqual(result.providerModel, "火山方舟 · m-fast")
        XCTAssertEqual(result.evidenceRefs.count, 1, "证据引用原样透传")
        XCTAssertEqual(result.attempts.count, 1)
        XCTAssertTrue(result.attempts[0].succeeded)
        XCTAssertNil(result.attempts[0].errorSummary)
    }

    // MARK: ② 链首 401、第二模型成功 → 静默转移 + 诊断含第一跳失败

    func testUnauthorizedOnFirstFallsOverToSecondModel() async throws {
        let client = FakeAIClient(behaviors: [
            "m-a": FakeAIClient.Behavior(reply: nil, error: .unauthorized),
            "m-b": FakeAIClient.Behavior(reply: "换模型也能答。", error: nil),
        ])
        let runner = makeRunner(client: client)
        let providers = [provider("ark", name: "火山方舟", models: ["m-a", "m-b"], order: 0)]

        let result = try await runner.run(providers: providers, input: chainInput())

        XCTAssertEqual(client.requestedModels, ["m-a", "m-b"])
        XCTAssertEqual(result.providerModel, "火山方舟 · m-b")
        XCTAssertEqual(result.attempts.count, 2)
        XCTAssertFalse(result.attempts[0].succeeded, "第一跳失败必须留在诊断里（S25 展示）")
        XCTAssertEqual(result.attempts[0].errorSummary, AIProviderError.unauthorized.summary)
        XCTAssertTrue(result.attempts[1].succeeded)
        XCTAssertEqual(runner.diagnostics.count, 2, "诊断同时进 runner 历史")
    }

    // MARK: ③ 服务商 1 全模型失败、服务商 2 成功 → 跨商转移

    func testAllModelsOfProviderOneFailCrossesToProviderTwo() async throws {
        let client = FakeAIClient(behaviors: [
            "ark-m1": FakeAIClient.Behavior(reply: nil, error: .unauthorized),
            "ark-m2": FakeAIClient.Behavior(reply: nil, error: .modelNotOpen),
            "bl-m1": FakeAIClient.Behavior(reply: "百炼答。", error: nil),
        ])
        let runner = makeRunner(client: client)
        let providers = [
            provider("ark", name: "火山方舟", models: ["ark-m1", "ark-m2"], order: 0),
            provider("bailian", name: "百炼", models: ["bl-m1"], order: 1),
        ]

        let result = try await runner.run(providers: providers, input: chainInput())

        XCTAssertEqual(client.requestedModels, ["ark-m1", "ark-m2", "bl-m1"], "跨商转移按链顺序继续")
        XCTAssertEqual(result.providerModel, "百炼 · bl-m1")
        XCTAssertEqual(result.attempts.map(\.succeeded), [false, false, true])
        XCTAssertEqual(result.attempts[1].errorSummary, AIProviderError.modelNotOpen.summary)
    }

    // MARK: ④ 全链失败 → 抛含各跳原因的错误

    func testWholeChainFailureThrowsWithEveryHopReason() async throws {
        let client = FakeAIClient(behaviors: [
            "ark-m1": FakeAIClient.Behavior(reply: nil, error: .unauthorized),
            "ark-m2": FakeAIClient.Behavior(reply: nil, error: .modelNotOpen),
            "bl-m1": FakeAIClient.Behavior(reply: nil, error: .network("The Internet connection appears to be offline.")),
        ])
        let runner = makeRunner(client: client)
        let providers = [
            provider("ark", name: "火山方舟", models: ["ark-m1", "ark-m2"], order: 0),
            provider("bailian", name: "百炼", models: ["bl-m1"], order: 1),
        ]

        do {
            _ = try await runner.run(providers: providers, input: chainInput())
            XCTFail("全链失败必须抛错，不得静默返回空回答")
        } catch let failure as ProviderChainFailure {
            XCTAssertEqual(failure.attempts.count, 3, "每一跳的原因都要带上")
            XCTAssertEqual(failure.attempts[0].errorSummary, AIProviderError.unauthorized.summary)
            XCTAssertEqual(failure.attempts[1].errorSummary, AIProviderError.modelNotOpen.summary)
            XCTAssertTrue(failure.attempts[2].errorSummary.contains("网络失败"))
            XCTAssertTrue(failure.summary.contains("全部 3 跳都失败"))
            XCTAssertTrue(failure.summary.contains("火山方舟·ark-m1"))
        }
        XCTAssertNil(runner.lastSuccessful, "全链失败不粘任何模型")
        XCTAssertEqual(runner.diagnostics.count, 3)
    }

    // MARK: ⑤ 粘住上次成功模型：上次成功的排第二，下次先试它

    func testStickyLastSuccessfulIsTriedFirstNextCall() async throws {
        let client = FakeAIClient(behaviors: [
            "ark-m1": FakeAIClient.Behavior(reply: nil, error: .unauthorized),
            "ark-m2": FakeAIClient.Behavior(reply: "方舟第二个模型可用。", error: nil),
            "bl-m1": FakeAIClient.Behavior(reply: "百炼可用。", error: nil),
        ])
        let runner = makeRunner(client: client)
        let providers = [
            provider("ark", name: "火山方舟", models: ["ark-m1", "ark-m2"], order: 0),
            provider("bailian", name: "百炼", models: ["bl-m1"], order: 1),
        ]

        // 第一次：ark-m1 挂 → ark-m2 成
        let first = try await runner.run(providers: providers, input: chainInput())
        XCTAssertEqual(first.providerModel, "火山方舟 · ark-m2")
        XCTAssertEqual(runner.lastSuccessful, ProviderChainRunner.LastSuccessful(providerId: "ark", modelId: "ark-m2"))

        // 第二次：粘性把 ark-m2 提到最前，不再先撞 ark-m1
        let second = try await runner.run(providers: providers, input: chainInput(question: "那慢练几遍合适？"))
        XCTAssertEqual(Array(client.requestedModels.suffix(1)), ["ark-m2"], "第二次直接起手上次成功的模型")
        XCTAssertEqual(second.attempts.count, 1, "粘性命中即返回，不再多跳")
        XCTAssertTrue(second.attempts[0].wasStickyStart)

        // 第三次：ark-m2 也挂了 → 粘性起手失败后仍按链顺序继续
        client.behaviors["ark-m2"] = FakeAIClient.Behavior(reply: nil, error: .modelNotOpen)
        let third = try await runner.run(providers: providers, input: chainInput(question: "再问一次"))
        XCTAssertEqual(Array(client.requestedModels.suffix(3)), ["ark-m2", "ark-m1", "bl-m1"], "粘性命中失败后沿链顺序走")
        XCTAssertEqual(third.providerModel, "百炼 · bl-m1")
        XCTAssertEqual(runner.lastSuccessful, ProviderChainRunner.LastSuccessful(providerId: "bailian", modelId: "bl-m1"))
    }

    // MARK: ⑤b 恢复探测：每 N 次调用重置为链首顺序

    func testProbeStrategyResetsToChainOrderEveryNthCall() async throws {
        let client = FakeAIClient(behaviors: [
            "m1": FakeAIClient.Behavior(reply: "高优先级可用。", error: nil),
            "m2": FakeAIClient.Behavior(reply: "次优先级可用。", error: nil),
        ])
        let runner = makeRunner(client: client, recovery: .probeEveryN(3))
        let providers = [provider("ark", name: "火山方舟", models: ["m1", "m2"], order: 0)]

        // 第 1 次：无粘性，按链首 → m1 成，粘住 m1
        _ = try await runner.run(providers: providers, input: chainInput())
        XCTAssertEqual(runner.lastSuccessful?.modelId, "m1")

        // m1 挂掉；第 2 次（非探测）：粘性起手 m1 → 失败 → 沿链到 m2 成
        client.behaviors["m1"] = FakeAIClient.Behavior(reply: nil, error: .modelNotOpen)
        _ = try await runner.run(providers: providers, input: chainInput())
        XCTAssertEqual(runner.lastSuccessful?.modelId, "m2")
        XCTAssertEqual(client.requestedModels, ["m1", "m1", "m2"])

        // 第 3 次（3 % 3 == 0 = 探测）：忽略粘性，按链首顺序起手
        _ = try await runner.run(providers: providers, input: chainInput())
        XCTAssertEqual(client.requestedModels, ["m1", "m1", "m2", "m1", "m2"], "探测跳起手链首 m1，失败后仍沿链")
    }

    // MARK: 边界：未配 Key / 未启用 / 空链 / 排序

    func testProviderWithoutKeyIsSkippedWithDiagnostic() async throws {
        let client = FakeAIClient(behaviors: [
            "bl-m1": FakeAIClient.Behavior(reply: "百炼答。", error: nil),
        ])
        let runner = makeRunner(client: client, keys: ["bailian": "k-bailian"]) // ark 无 key
        let providers = [
            provider("ark", name: "火山方舟", models: ["ark-m1"], order: 0),
            provider("bailian", name: "百炼", models: ["bl-m1"], order: 1),
        ]

        let result = try await runner.run(providers: providers, input: chainInput())

        XCTAssertEqual(client.requestedModels, ["bl-m1"], "没配 Key 的服务商不发起请求")
        XCTAssertEqual(result.providerModel, "百炼 · bl-m1")
        XCTAssertEqual(result.attempts[0].errorSummary, "未配置 Key")
        XCTAssertFalse(result.attempts[0].succeeded)
    }

    func testDisabledProviderIsNotTried() async throws {
        let client = FakeAIClient(behaviors: [
            "off-m1": FakeAIClient.Behavior(reply: "被停用的服务商不该被调用", error: nil),
            "on-m1": FakeAIClient.Behavior(reply: "启用的答。", error: nil),
        ])
        let runner = makeRunner(client: client, keys: ["on": "k-on"])
        let providers = [
            provider("off", name: "已停用", models: ["off-m1"], order: 0, enabled: false),
            provider("on", name: "启用中", models: ["on-m1"], order: 1),
        ]

        let result = try await runner.run(providers: providers, input: chainInput())
        XCTAssertEqual(client.requestedModels, ["on-m1"])
        XCTAssertEqual(result.providerModel, "启用中 · on-m1")
    }

    func testEmptyChainThrowsConfigurationFailure() async throws {
        let client = FakeAIClient(behaviors: [:])
        let runner = makeRunner(client: client)

        do {
            _ = try await runner.run(providers: [], input: chainInput())
            XCTFail("没有服务商必须抛错")
        } catch let failure as ProviderChainFailure {
            XCTAssertTrue(failure.attempts.isEmpty)
            XCTAssertTrue(failure.summary.contains("没有可用的服务商"))
        }

        // 全停用同理
        do {
            _ = try await runner.run(providers: [provider("ark", name: "方舟", models: ["m"], order: 0, enabled: false)], input: chainInput())
            XCTFail("全停用必须抛错")
        } catch let failure as ProviderChainFailure {
            XCTAssertTrue(failure.attempts.isEmpty)
        }
    }

    func testProvidersSortedBySortOrderNotInputOrder() async throws {
        let client = FakeAIClient(behaviors: [
            "p2": FakeAIClient.Behavior(reply: "排序第二的先试。", error: nil),
            "p1": FakeAIClient.Behavior(reply: "不该被调用", error: nil),
        ])
        let runner = makeRunner(client: client, keys: ["a": "k-a", "b": "k-b"])
        let providers = [
            provider("b", name: "排序1", models: ["p1"], order: 1),
            provider("a", name: "排序0", models: ["p2"], order: 0),
        ]

        let result = try await runner.run(providers: providers, input: chainInput())
        XCTAssertEqual(client.requestedModels, ["p2"])
        XCTAssertEqual(result.providerModel, "排序0 · p2")
    }

    // MARK: 请求形态

    func testRequestMessagesCarrySystemAndContext() async throws {
        let client = FakeAIClient(behaviors: ["m": FakeAIClient.Behavior(reply: "ok", error: nil)])
        let runner = makeRunner(client: client)
        let providers = [provider("ark", name: "火山方舟", models: ["m"], order: 0)]

        _ = try await runner.run(providers: providers, input: chainInput(question: "第 12 小节"))

        let request = try XCTUnwrap(client.lastRequest)
        XCTAssertEqual(request.model, "m")
        XCTAssertEqual(request.temperature, 0.2)
        XCTAssertEqual(request.messages.count, 2)
        XCTAssertEqual(request.messages[0].role, "system")
        XCTAssertTrue(request.messages[0].content.flatText.contains("必须引用"), "system 带引用证据的行为规则")

        let userText = request.messages[1].content.flatText
        XCTAssertTrue(userText.contains("以下是我本地练习里的真实数据"))
        XCTAssertTrue(userText.contains("练习小节区间：第 12"))
        XCTAssertTrue(userText.contains("我的问题：第 12 小节"))
    }

    func testRequestWithoutContextOrSystemOnlySendsUserMessage() async throws {
        let client = FakeAIClient(behaviors: ["m": FakeAIClient.Behavior(reply: "ok", error: nil)])
        let runner = makeRunner(client: client)
        let providers = [provider("ark", name: "火山方舟", models: ["m"], order: 0)]

        _ = try await runner.run(providers: providers, input: ChainInput(question: "什么是 legato？"))

        let request = try XCTUnwrap(client.lastRequest)
        XCTAssertEqual(request.messages.count, 1)
        XCTAssertEqual(request.messages[0].role, "user")
        XCTAssertEqual(request.messages[0].content.flatText, "什么是 legato？")
        XCTAssertNil(request.temperature, "temperature 未给就不发")
    }

    // MARK: 诊断上限与重置

    func testDiagnosticsKeepOnlyMostRecentN() async throws {
        let client = FakeAIClient(behaviors: [
            "m1": FakeAIClient.Behavior(reply: nil, error: .unauthorized),
            "m2": FakeAIClient.Behavior(reply: nil, error: .modelNotOpen),
            "m3": FakeAIClient.Behavior(reply: nil, error: .network("offline")),
        ])
        let runner = makeRunner(client: client, maxDiagnostics: 5)
        let providers = [provider("ark", name: "方舟", models: ["m1", "m2", "m3"], order: 0)]

        // 每轮 3 跳全失败（不粘任何模型）→ 3 轮 9 条，只留最近 5 条
        for _ in 0..<3 {
            _ = try? await runner.run(providers: providers, input: chainInput())
        }

        XCTAssertEqual(runner.diagnostics.map(\.modelId), ["m2", "m3", "m1", "m2", "m3"], "裁掉的是最旧的 m1 失败跳")
        XCTAssertTrue(runner.diagnostics.allSatisfy { !$0.succeeded })
        XCTAssertTrue(runner.diagnostics.allSatisfy { $0.errorSummary != nil })
    }

    func testResetClearsStickyAndDiagnostics() async throws {
        let client = FakeAIClient(behaviors: ["m": FakeAIClient.Behavior(reply: "ok", error: nil)])
        let runner = makeRunner(client: client)
        let providers = [provider("ark", name: "方舟", models: ["m"], order: 0)]

        _ = try await runner.run(providers: providers, input: chainInput())
        XCTAssertNotNil(runner.lastSuccessful)

        runner.reset()
        XCTAssertNil(runner.lastSuccessful)
        XCTAssertTrue(runner.diagnostics.isEmpty)
    }

    // MARK: 计划（纯函数）

    func testPlanMovesStickyHopToFrontKeepingRelativeOrder() {
        let providers = [
            provider("ark", name: "方舟", models: ["a1", "a2"], order: 0),
            provider("bl", name: "百炼", models: ["b1"], order: 1),
        ]
        let hops = ProviderChainRunner.plan(
            providers: providers,
            sticky: ProviderChainRunner.LastSuccessful(providerId: "ark", modelId: "a2")
        )
        XCTAssertEqual(hops.map(\.modelId), ["a2", "a1", "b1"])
        XCTAssertEqual(hops.map(\.isStickyStart), [true, false, false])

        // 粘的模型不在链上（被删/改名）→ 保持链顺序，不崩
        let orphan = ProviderChainRunner.plan(
            providers: providers,
            sticky: ProviderChainRunner.LastSuccessful(providerId: "gone", modelId: "x")
        )
        XCTAssertEqual(orphan.map(\.modelId), ["a1", "a2", "b1"])
        XCTAssertTrue(orphan.allSatisfy { !$0.isStickyStart })
    }

    func testPlanSkipsBlankModelsAndDisabledProviders() {
        let providers = [
            provider("ark", name: "方舟", models: ["a1", "  ", ""], order: 0),
            provider("off", name: "停用", models: ["o1"], order: 1, enabled: false),
        ]
        let hops = ProviderChainRunner.plan(providers: providers, sticky: nil)
        XCTAssertEqual(hops.map(\.modelId), ["a1"], "空白 modelId 与停用服务商都不进尝试序列")
    }

    func testDisplayNameFallsBackToProviderIdWhenBlank() {
        let providers = [provider("ark", name: "", models: ["m1"], order: 0)]
        let hops = ProviderChainRunner.plan(providers: providers, sticky: nil)
        XCTAssertEqual(hops.first?.providerDisplayName, "ark", "没填显示名就用 providerId，不显示空串")
    }
}

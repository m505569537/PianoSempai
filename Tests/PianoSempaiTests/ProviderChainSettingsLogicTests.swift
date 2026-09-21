import XCTest
@testable import PianoSempai

/// S25 服务商链 UI 逻辑验收（M7.1 Stage B1）：链路状态聚合、状态点判定、诊断行格式化、
/// 拖拽落位、模型增删、providerId 去重/生成、预设入口、baseURL 校验、常驻运行时校验 ping。
/// 布局用 SwiftUI 预览自查；可测逻辑全部在这里断言。
final class ProviderChainSettingsLogicTests: XCTestCase {

    // MARK: - 假依赖（不打真实网络、不碰真实 Keychain）

    private final class FakeAIClient: AIClient {
        struct Behavior {
            var reply: String?
            var error: AIProviderError?
        }

        var behaviors: [String: Behavior]
        private(set) var requestedModels: [String] = []

        init(behaviors: [String: Behavior]) {
            self.behaviors = behaviors
        }

        func send(_ request: ChatCompletionRequest, target: AIRequestTarget) async throws -> String {
            requestedModels.append(target.model)
            let behavior = behaviors[target.model] ?? FakeAIClient.Behavior(reply: nil, error: .http(status: 500, code: "NoBehaviorConfigured"))
            if let error = behavior.error { throw error }
            guard let reply = behavior.reply else {
                throw AIProviderError.decoding("假 client 未配置该模型的回复")
            }
            return reply
        }
    }

    private final class FakeProviderKeyStore: ProviderKeyStore {
        private var keys: [String: String] = [:]

        init(keys: [String: String] = [:]) {
            self.keys = keys
        }

        func save(_ key: String, providerId: String) throws { keys[providerId] = key }
        func read(providerId: String) -> String? { keys[providerId] }
        func delete(providerId: String) throws { keys[providerId] = nil }
        func hasKey(providerId: String) -> Bool { keys[providerId] != nil }
    }

    // MARK: - 夹具

    private func provider(
        _ id: String,
        name: String,
        models: [String],
        order: Int,
        enabled: Bool = true,
        baseURL: String? = nil
    ) -> AIProvider {
        AIProvider(
            providerId: id,
            displayName: name,
            baseURL: baseURL ?? "https://\(id).example.com/api/v3",
            modelIds: models,
            enabled: enabled,
            sortOrder: order
        )
    }

    private func keys(_ map: [String: String]) -> (String) -> Bool {
        { providerId in map[providerId] != nil }
    }

    // MARK: ① 链路状态聚合

    func testSummarizeEmptyChain() {
        let summary = ProviderChainLogic.summarize([], hasKey: keys(["ark": "k"]))
        XCTAssertEqual(summary.total, 0)
        XCTAssertEqual(summary.available, 0)
        XCTAssertEqual(summary.state, .empty)
        XCTAssertEqual(summary.statusTitle, "还没有可用的服务商")
        XCTAssertEqual(summary.settingsRowValue, "0 个服务商 · 0 个可用")
    }

    func testSummarizeCountsAvailableOnly() {
        let providers = [
            provider("ark", name: "火山方舟", models: ["m-a"], order: 0),
            provider("bailian", name: "百炼", models: ["m-b"], order: 1),
            provider("deepseek", name: "DeepSeek", models: ["m-c"], order: 2),
        ]
        let summary = ProviderChainLogic.summarize(providers, hasKey: keys(["ark": "k", "bailian": "k"]))
        XCTAssertEqual(summary.total, 3)
        XCTAssertEqual(summary.available, 2, "只有「有 key + 有模型」的服务商算可用")
        XCTAssertEqual(summary.state, .healthy)
        XCTAssertEqual(summary.statusTitle, "链路正常")
        XCTAssertEqual(summary.settingsRowValue, "3 个服务商 · 2 个可用")
        XCTAssertEqual(summary.statusDetail, "提问时按顺序尝试，任一可用即工作，失败自动切换")
    }

    func testSummarizeNoneAvailableWhenKeyModelOrEnabledMissing() {
        let providers = [
            provider("ark", name: "火山方舟", models: [], order: 0),                    // 有 key 没模型
            provider("bailian", name: "百炼", models: ["m-b"], order: 1),              // 有模型没 key
            provider("deepseek", name: "DeepSeek", models: ["m-c"], order: 2, enabled: false), // 停用
        ]
        let summary = ProviderChainLogic.summarize(providers, hasKey: keys(["ark": "k", "deepseek": "k"]))
        XCTAssertEqual(summary.total, 3)
        XCTAssertEqual(summary.available, 0)
        XCTAssertEqual(summary.state, .noneAvailable)
        XCTAssertEqual(summary.statusTitle, "还没有可用的服务商")
        XCTAssertEqual(summary.settingsRowValue, "3 个服务商 · 0 个可用")
    }

    // MARK: ② 状态点判定

    func testRowStatusAvailableRequiresEnabledKeyAndModels() {
        let provider = provider("ark", name: "火山方舟", models: ["m-a"], order: 0)
        XCTAssertEqual(ProviderChainLogic.rowStatus(provider: provider, hasKey: true, recentFailure: false), .available)
    }

    func testRowStatusUnconfiguredOnMissingPieces() {
        let noModels = provider("ark", name: "火山方舟", models: [], order: 0)
        XCTAssertEqual(ProviderChainLogic.rowStatus(provider: noModels, hasKey: true, recentFailure: false), .unconfigured)

        let noKey = provider("bailian", name: "百炼", models: ["m-b"], order: 1)
        XCTAssertEqual(ProviderChainLogic.rowStatus(provider: noKey, hasKey: false, recentFailure: false), .unconfigured)

        let disabled = provider("deepseek", name: "DeepSeek", models: ["m-c"], order: 2, enabled: false)
        XCTAssertEqual(ProviderChainLogic.rowStatus(provider: disabled, hasKey: true, recentFailure: false), .unconfigured)

        let blankModels = provider("custom", name: "自定义", models: ["   ", ""], order: 3)
        XCTAssertEqual(ProviderChainLogic.rowStatus(provider: blankModels, hasKey: true, recentFailure: false), .unconfigured, "空白模型 id 不算配置")
    }

    func testRowStatusRecentFailureOverridesAvailable() {
        let provider = provider("ark", name: "火山方舟", models: ["m-a"], order: 0)
        XCTAssertEqual(
            ProviderChainLogic.rowStatus(provider: provider, hasKey: true, recentFailure: true),
            .failedRecently,
            "最近一次调用失败必须点红，不谎称正常"
        )
    }

    // MARK: ③ 诊断行

    func testDiagnosticRowFormatsSuccessAndFailure() {
        let timestamp = Date(timeIntervalSince1970: 1_758_900_000)
        // 期望值按测试机本地时区算（与实现同一套 MM-dd HH:mm 语义），不受跑测机器时区影响
        let parts = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: timestamp)
        let expectedTime = String(format: "%02d-%02d %02d:%02d", parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)

        let success = ChainDiagnosticEntry(
            timestamp: timestamp,
            providerId: "bailian",
            providerDisplayName: "百炼",
            modelId: "qwen3-vl",
            succeeded: true,
            errorSummary: nil,
            durationMs: 1800
        )
        let successRow = ProviderChainLogic.diagnosticRow(success)
        XCTAssertEqual(successRow.timeText, expectedTime)
        XCTAssertEqual(successRow.targetText, "百炼 qwen3-vl")
        XCTAssertEqual(successRow.resultText, "✓1.8s")
        XCTAssertTrue(successRow.succeeded)

        let failure = ChainDiagnosticEntry(
            timestamp: timestamp,
            providerId: "ark",
            providerDisplayName: "火山方舟",
            modelId: "doubao-seed-2-1-pro",
            succeeded: false,
            errorSummary: "模型未开通（ModelNotOpen）",
            durationMs: 640
        )
        let failureRow = ProviderChainLogic.diagnosticRow(failure)
        XCTAssertFalse(failureRow.succeeded)
        XCTAssertEqual(failureRow.resultText, "✗模型未开通（ModelNotOpen）")
        XCTAssertEqual(failureRow.targetText, "火山方舟 doubao-se…", "超长目标截断")
    }

    func testDurationTextUsesSecondsAboveOneSecond() {
        XCTAssertEqual(ProviderChainLogic.durationText(640), "640ms")
        XCTAssertEqual(ProviderChainLogic.durationText(999), "999ms")
        XCTAssertEqual(ProviderChainLogic.durationText(1000), "1.0s")
        XCTAssertEqual(ProviderChainLogic.durationText(2300), "2.3s")
    }

    func testDiagnosticEntryAndRowCarryNoKeyFields() {
        let entry = ChainDiagnosticEntry(
            providerId: "ark",
            providerDisplayName: "火山方舟",
            modelId: "m-a",
            succeeded: true,
            errorSummary: nil,
            durationMs: 12
        )
        let entryFields = Mirror(reflecting: entry).children.compactMap { $0.label }
        for field in entryFields {
            let lowered = field.lowercased()
            XCTAssertFalse(lowered.contains("key"), "诊断条目不得带 key 字段：\(field)")
            XCTAssertFalse(lowered.contains("secret"), "诊断条目不得带 secret 字段：\(field)")
            XCTAssertFalse(lowered.contains("token"), "诊断条目不得带 token 字段：\(field)")
        }
        let rowFields = Mirror(reflecting: ProviderChainLogic.diagnosticRow(entry)).children.compactMap { $0.label }
        for field in rowFields {
            let lowered = field.lowercased()
            XCTAssertFalse(lowered.contains("key"), "诊断行不得带 key 字段：\(field)")
            XCTAssertFalse(lowered.contains("secret"), "诊断行不得带 secret 字段：\(field)")
        }
    }

    func testRecentFailureProviderIdsUsesLatestEntryPerProvider() {
        let diagnostics = [
            ChainDiagnosticEntry(providerId: "ark", providerDisplayName: "方舟", modelId: "m1", succeeded: false, errorSummary: "401/403", durationMs: 10),
            ChainDiagnosticEntry(providerId: "ark", providerDisplayName: "方舟", modelId: "m1", succeeded: true, durationMs: 20),
            ChainDiagnosticEntry(providerId: "bailian", providerDisplayName: "百炼", modelId: "m2", succeeded: true, durationMs: 30),
            ChainDiagnosticEntry(providerId: "bailian", providerDisplayName: "百炼", modelId: "m2", succeeded: false, errorSummary: "网络失败", durationMs: 40),
        ]
        let failed = ProviderChainLogic.recentFailureProviderIds(diagnostics)
        XCTAssertEqual(failed, ["bailian"], "ark 后来成功了就不算失败；bailian 最后一次失败才点红")
    }

    func testStatusCurrentTextReflectsActualHitNotChainHead() {
        let providers = [
            provider("ark", name: "火山方舟", models: ["m-a"], order: 0),
            provider("deepseek", name: "DeepSeek", models: ["m-c"], order: 1),
        ]
        XCTAssertNil(ProviderChainLogic.statusCurrentText(lastSuccessful: nil, providers: providers))
        let degraded = ProviderChainRunner.LastSuccessful(providerId: "deepseek", modelId: "m-c")
        XCTAssertEqual(
            ProviderChainLogic.statusCurrentText(lastSuccessful: degraded, providers: providers),
            "当前使用：DeepSeek · m-c",
            "降级命中时如实写实际生效者，不谎称首选"
        )
    }

    // MARK: ④ 拖拽落位与重排

    func testTargetIndexRoundsPerPitchAndClamps() {
        let pitch: CGFloat = 82
        XCTAssertEqual(ProviderChainLogic.targetIndex(startIndex: 1, translation: 0, pitch: pitch, count: 4), 1)
        XCTAssertEqual(ProviderChainLogic.targetIndex(startIndex: 1, translation: 40, pitch: pitch, count: 4), 1)
        XCTAssertEqual(ProviderChainLogic.targetIndex(startIndex: 1, translation: 45, pitch: pitch, count: 4), 2, "过半格即进位")
        XCTAssertEqual(ProviderChainLogic.targetIndex(startIndex: 1, translation: -200, pitch: pitch, count: 4), 0, "向上钳在链首")
        XCTAssertEqual(ProviderChainLogic.targetIndex(startIndex: 1, translation: 999, pitch: pitch, count: 4), 3, "向下钳在链尾")
        XCTAssertEqual(ProviderChainLogic.targetIndex(startIndex: 0, translation: 50, pitch: pitch, count: 0), 0, "空链不越界")
    }

    func testSortOrderAssignmentsAreDense() {
        let assignments = ProviderChainLogic.sortOrderAssignments(["ark", "bailian", "deepseek"])
        XCTAssertEqual(assignments["ark"], 0)
        XCTAssertEqual(assignments["bailian"], 1)
        XCTAssertEqual(assignments["deepseek"], 2)
    }

    func testNextSortOrderFollowsMax() {
        XCTAssertEqual(ProviderChainLogic.nextSortOrder([]), 0, "空链从 0 起")
        let providers = [
            provider("a", name: "A", models: ["m"], order: 0),
            provider("b", name: "B", models: ["m"], order: 2),
            provider("c", name: "C", models: ["m"], order: 5),
        ]
        XCTAssertEqual(ProviderChainLogic.nextSortOrder(providers), 6)
    }

    func testOrderedSortsStablyBySortOrder() {
        let providers = [
            provider("c", name: "C", models: ["m"], order: 1),
            provider("a", name: "A", models: ["m"], order: 0),
            provider("b", name: "B", models: ["m"], order: 1),
        ]
        XCTAssertEqual(ProviderChainLogic.ordered(providers).map(\.providerId), ["a", "c", "b"], "同 sortOrder 按录入序")
    }

    // MARK: ⑤ 模型 id 增删

    func testAddModelRejectsEmptyAndDuplicate() {
        XCTAssertNil(ProviderChainLogic.addModel("   ", to: []))
        XCTAssertNil(ProviderChainLogic.addModel("", to: []))

        var models = ProviderChainLogic.addModel("  m-a  ", to: [])
        XCTAssertEqual(models, ["m-a"], "trim 后入库")
        models = ProviderChainLogic.addModel("m-b", to: models ?? [])
        XCTAssertEqual(models, ["m-a", "m-b"])
        XCTAssertNil(ProviderChainLogic.addModel("m-a", to: models ?? []), "去重")
        XCTAssertNil(ProviderChainLogic.addModel(" m-a ", to: models ?? []), "trim 后仍判重")
    }

    // MARK: ⑥ 预设 / providerId / baseURL

    func testPresetsHaveStableIdsAndDefaultBaseURLs() {
        XCTAssertEqual(ProviderPreset.ark.rawValue, "ark")
        XCTAssertEqual(ProviderPreset.ark.defaultBaseURL, "https://ark.cn-beijing.volces.com/api/v3")
        XCTAssertEqual(ProviderPreset.ark.displayName, "火山方舟")
        XCTAssertEqual(ProviderPreset.bailian.rawValue, "bailian")
        XCTAssertNotNil(ProviderPreset.bailian.defaultBaseURL)
        XCTAssertEqual(ProviderPreset.deepseek.rawValue, "deepseek")
        XCTAssertNotNil(ProviderPreset.deepseek.defaultBaseURL)
        XCTAssertTrue(ProviderPreset.custom.isCustom)
        XCTAssertNil(ProviderPreset.custom.defaultBaseURL, "自定义入口由用户自填")
    }

    func testMakeProviderFromPreset() {
        let result = ProviderChainLogic.makeProvider(
            preset: .ark,
            displayName: "火山方舟",
            baseURL: ProviderPreset.ark.defaultBaseURL ?? "",
            sortOrder: 3
        )
        guard case .success(let created) = result else {
            return XCTFail("预设创建不应失败：\(String(describing: result))")
        }
        XCTAssertEqual(created.providerId, "ark", "预设用稳定 providerId（Keychain account 不漂移）")
        XCTAssertEqual(created.displayName, "火山方舟")
        XCTAssertEqual(created.baseURL, "https://ark.cn-beijing.volces.com/api/v3")
        XCTAssertTrue(created.modelIds.isEmpty, "模型 id 一律用户后配，不写死")
        XCTAssertTrue(created.enabled)
        XCTAssertEqual(created.sortOrder, 3)
    }

    func testMakeProviderCustomUsesUniqueProviderId() {
        let first = ProviderChainLogic.makeProvider(preset: .custom, displayName: "网关 A", baseURL: "https://a.example.com/v1", sortOrder: 0)
        let second = ProviderChainLogic.makeProvider(preset: .custom, displayName: "网关 B", baseURL: "https://b.example.com/v1", sortOrder: 1)
        guard case .success(let a) = first, case .success(let b) = second else {
            return XCTFail("自定义创建应成功")
        }
        XCTAssertNotEqual(a.providerId, b.providerId)
        XCTAssertFalse(ProviderChainLogic.isDuplicate(providerId: a.providerId, in: [b]))
        XCTAssertTrue(ProviderChainLogic.isDuplicate(providerId: "ark", in: [provider("ark", name: "方舟", models: [], order: 0)]))
    }

    func testMakeProviderRejectsBadInput() {
        let badURL = ProviderChainLogic.makeProvider(preset: .custom, displayName: "网关", baseURL: "not-a-url", sortOrder: 0)
        guard case .failure(let error) = badURL else {
            return XCTFail("非法 baseURL 必须拒绝")
        }
        XCTAssertTrue(error.message.contains("baseURL"), "错误短句要能直接展示：\(error.message)")

        let emptyName = ProviderChainLogic.makeProvider(preset: .custom, displayName: "  ", baseURL: "https://x.example.com/v1", sortOrder: 0)
        guard case .failure(let nameError) = emptyName else {
            return XCTFail("空显示名必须拒绝")
        }
        XCTAssertTrue(nameError.message.contains("显示名"))
    }

    func testValidateBaseURLMatchesClientRules() {
        XCTAssertNil(ProviderChainLogic.validateBaseURL("https://ark.cn-beijing.volces.com/api/v3"))
        XCTAssertNil(ProviderChainLogic.validateBaseURL("  https://api.deepseek.com/v1/  "), "尾斜杠与空白容错")
        XCTAssertNil(ProviderChainLogic.validateBaseURL("http://localhost:11434/v1"), "自建网关常用 http")
        XCTAssertNotNil(ProviderChainLogic.validateBaseURL("https://"), "壳子 URL 判非法")
        XCTAssertNotNil(ProviderChainLogic.validateBaseURL("ftp://x.example.com"))
        XCTAssertNotNil(ProviderChainLogic.validateBaseURL("ark.cn-beijing.volces.com"), "无 scheme 判非法")
        XCTAssertNotNil(ProviderChainLogic.validateBaseURL(""))
    }

    // MARK: ⑦ 常驻运行时（假 client / 假 keystore）

    @MainActor
    func testRuntimeValidateSuccessRecordsDiagnosticAndLastSuccessful() async throws {
        let client = FakeAIClient(behaviors: ["m-ping": FakeAIClient.Behavior(reply: "pong", error: nil)])
        let runtime = ProviderChainRuntime(client: client, keyStore: FakeProviderKeyStore(keys: ["ark": "k"]))
        let target = provider("ark", name: "火山方舟", models: ["m-ping"], order: 0)

        runtime.refreshKeys(["ark"])
        XCTAssertEqual(runtime.keyPresence["ark"], true)

        let outcome = await runtime.validate(target)
        XCTAssertEqual(outcome, .success("火山方舟 · m-ping"))
        XCTAssertEqual(client.requestedModels, ["m-ping"], "最小校验只发一条")
        XCTAssertEqual(runtime.diagnostics.count, 1)
        XCTAssertTrue(runtime.diagnostics[0].succeeded)
        XCTAssertEqual(runtime.lastSuccessful?.modelId, "m-ping", "校验命中即写入粘性（状态卡「当前使用」读它）")
    }

    @MainActor
    func testRuntimeValidateFailureKeepsReason() async {
        let client = FakeAIClient(behaviors: ["m-ping": FakeAIClient.Behavior(reply: nil, error: .unauthorized)])
        let runtime = ProviderChainRuntime(client: client, keyStore: FakeProviderKeyStore(keys: ["ark": "k"]))
        let target = provider("ark", name: "火山方舟", models: ["m-ping"], order: 0)

        let outcome = await runtime.validate(target)
        XCTAssertEqual(outcome, .failed("401/403：Key 无效或无权限"))
        XCTAssertEqual(runtime.diagnostics.count, 1)
        XCTAssertFalse(runtime.diagnostics[0].succeeded)
        XCTAssertNil(runtime.lastSuccessful, "失败不写粘性")
    }

    @MainActor
    func testRuntimeValidateSkippedWithoutModelsAndOnBadBaseURL() async {
        let client = FakeAIClient(behaviors: [:])
        let runtime = ProviderChainRuntime(client: client, keyStore: FakeProviderKeyStore(keys: ["ark": "k"]))

        let noModels = provider("ark", name: "火山方舟", models: [], order: 0)
        let outcome = await runtime.validate(noModels)
        guard case .skipped(let reason) = outcome else {
            return XCTFail("没配模型不该发请求：\(outcome)")
        }
        XCTAssertTrue(reason.contains("模型"))

        let badBase = provider("ark", name: "火山方舟", models: ["m-ping"], order: 0, baseURL: "https://")
        let badOutcome = await runtime.validate(badBase)
        guard case .failed(let reason) = badOutcome else {
            return XCTFail("非法 baseURL 不该发请求：\(badOutcome)")
        }
        XCTAssertTrue(reason.contains("baseURL"))
        XCTAssertTrue(client.requestedModels.isEmpty, "本地校验拦住，不打网络")
    }

    @MainActor
    func testRuntimeKeyPresenceFollowsKeychain() throws {
        let runtime = ProviderChainRuntime(client: FakeAIClient(behaviors: [:]), keyStore: FakeProviderKeyStore())
        XCTAssertEqual(runtime.keyPresence["ark"], nil)

        try runtime.saveKey("sk-fake-key-abcdef123456", providerId: "ark")
        XCTAssertEqual(runtime.keyPresence["ark"], true)
        XCTAssertTrue(runtime.hasKey(providerId: "ark"))

        try runtime.deleteKey(providerId: "ark")
        XCTAssertEqual(runtime.keyPresence["ark"], false)
        XCTAssertFalse(runtime.hasKey(providerId: "ark"))
    }

    @MainActor
    func testRuntimeMaskedKeyNeverReturnsRawValue() throws {
        let runtime = ProviderChainRuntime(client: FakeAIClient(behaviors: [:]), keyStore: FakeProviderKeyStore())
        let raw = "sk-fake-key-abcdef123456"
        try runtime.saveKey(raw, providerId: "ark")

        let masked = try XCTUnwrap(runtime.maskedKey(providerId: "ark", visible: false))
        XCTAssertNotEqual(masked, raw)
        XCTAssertTrue(masked.hasSuffix("3456"), "掩码只露末 4 位")
        XCTAssertFalse(masked.contains("abcdef"), "中段不得出现")

        let visible = try XCTUnwrap(runtime.maskedKey(providerId: "ark", visible: true))
        XCTAssertNotEqual(visible, raw)
        XCTAssertFalse(visible.contains("1234"), "显态中段仍是圆点")
    }

    @MainActor
    func testRuntimeResetChainClearsStickinessAndDiagnostics() async {
        let client = FakeAIClient(behaviors: ["m-ping": FakeAIClient.Behavior(reply: "pong", error: nil)])
        let runtime = ProviderChainRuntime(client: client, keyStore: FakeProviderKeyStore(keys: ["ark": "k"]))
        let target = provider("ark", name: "火山方舟", models: ["m-ping"], order: 0)

        _ = await runtime.validate(target)
        XCTAssertEqual(runtime.diagnostics.count, 1)
        XCTAssertNotNil(runtime.lastSuccessful)

        runtime.resetChain()
        XCTAssertTrue(runtime.diagnostics.isEmpty)
        XCTAssertNil(runtime.lastSuccessful, "用户手动改优先级后清粘性")
    }
}

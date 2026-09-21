import Foundation
import Observation

// S25 常驻链状态（brief §1：ProviderChainRunner 是为一次提问构建的，本页要一个常驻实例
// 持有 diagnostics/lastSuccessful，供状态卡与诊断卡读取）。
// 只读 Keychain、只出网；不写任何课程/判分/设置状态（红线 3，同 runner 层）。

/// 保存 Key 后的最小校验结果（S25 详情页行内展示；校验不阻塞保存）。
enum KeyValidationOutcome: Equatable {
    case idle
    case checking
    /// 校验通过（「服务商显示名 · 模型 id」）
    case success(String)
    /// 校验失败（原因短句，AIProviderError.summary；不吞错）
    case failed(String)
    /// 本地就不该发请求（没配模型 / baseURL 不合法）
    case skipped(String)
}

@MainActor
@Observable
final class ProviderChainRuntime {
    private let keyStore: any ProviderKeyStore
    private let runner: ProviderChainRunner

    /// providerId → 是否有 key（Keychain 的 UI 缓存；真实值永远以 Keychain 为准）
    private(set) var keyPresence: [String: Bool] = [:]
    /// 最近 N 条诊断（新者在尾部）
    private(set) var diagnostics: [ChainDiagnosticEntry] = []
    /// 上次成功命中的服务商·模型（内存态；状态卡与「首选生效」标记读它）
    private(set) var lastSuccessful: ProviderChainRunner.LastSuccessful?

    init(client: any AIClient = OpenAICompatClient(), keyStore: any ProviderKeyStore = KeychainProviderKeyStore()) {
        self.keyStore = keyStore
        self.runner = ProviderChainRunner(client: client, keyStore: keyStore)
    }

    // MARK: Key（Keychain 是唯一真值；原始 key 不出本类）

    /// 刷新 key 存在性缓存（进入页面 / 增删 key 后调用）
    func refreshKeys(_ providerIds: [String]) {
        for providerId in providerIds {
            keyPresence[providerId] = keyStore.hasKey(providerId: providerId)
        }
    }

    func hasKey(providerId: String) -> Bool { keyStore.hasKey(providerId: providerId) }

    func saveKey(_ key: String, providerId: String) throws {
        try keyStore.save(key, providerId: providerId)
        keyPresence[providerId] = keyStore.hasKey(providerId: providerId)
    }

    func deleteKey(providerId: String) throws {
        try keyStore.delete(providerId: providerId)
        keyPresence[providerId] = false
    }

    /// 掩码显示（末 4 位；显态也不整串裸露）。原始 key 只在 Keychain 与本方法内存在。
    func maskedKey(providerId: String, visible: Bool) -> String? {
        guard let key = keyStore.read(providerId: providerId) else { return nil }
        return APIKeyMasking.mask(key, visible: visible)
    }

    // MARK: 诊断 / 粘性

    /// 清空诊断与粘性（S25 拖拽改优先级后调用：用户手动重排 = 清粘性）
    func resetChain() {
        runner.reset()
        syncFromRunner()
    }

    private func syncFromRunner() {
        diagnostics = runner.diagnostics
        lastSuccessful = runner.lastSuccessful
    }

    // MARK: 保存 Key 后的最小校验

    /// 用该商 key + 首个模型发一条 "ping"（走 runner：诊断留痕、粘性如常）。
    /// 调用方先存 key 再调本方法——校验不阻塞保存。
    func validate(_ provider: AIProvider) async -> KeyValidationOutcome {
        guard ProviderChainLogic.hasModels(provider) else {
            return .skipped("先添加至少一个模型 id 再校验")
        }
        if let baseError = ProviderChainLogic.validateBaseURL(provider.baseURL) {
            return .failed(baseError)
        }
        do {
            let result = try await runner.run(providers: [provider], input: ChainInput(question: "ping"))
            syncFromRunner()
            return .success(result.providerModel)
        } catch let failure as ProviderChainFailure {
            syncFromRunner()
            return .failed(failure.attempts.first?.errorSummary ?? failure.summary)
        } catch {
            syncFromRunner()
            return .failed("未知错误：\(error.localizedDescription)")
        }
    }
}

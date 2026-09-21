import Foundation

// S25 服务商链 UI 的纯逻辑层：预设模板、链路状态聚合、状态点判定、诊断行格式化、
// 拖拽落位、模型增删、providerId 去重、baseURL 校验、添加流程工厂。
// 不碰 UI / SwiftData 容器 / Keychain / 网络——只收值、返回值；UI 与单测共用同一份实现。
// （布局用 SwiftUI 预览自查，可测逻辑全部下沉到这层。）

// MARK: - 预设

/// 服务商预设（S25 spec：火山方舟/百炼/DeepSeek 带默认入口 + OpenAI 兼容自定义）。
/// 预设只提供「默认 baseURL 与默认显示名」——模型 id 一律不写死，由用户在详情里配。
enum ProviderPreset: String, CaseIterable, Identifiable {
    case ark
    case bailian
    case deepseek
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ark: return "火山方舟"
        case .bailian: return "百炼"
        case .deepseek: return "DeepSeek"
        case .custom: return "自定义服务商"
        }
    }

    /// 默认 OpenAI 兼容入口；custom 为 nil（用户自填）
    var defaultBaseURL: String? {
        switch self {
        case .ark: return "https://ark.cn-beijing.volces.com/api/v3"
        case .bailian: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .custom: return nil
        }
    }

    var isCustom: Bool { self == .custom }
}

// MARK: - 链路状态聚合（S25 状态卡 / S23 行文案共用）

struct ProviderChainSummary: Equatable {
    enum State: Equatable {
        /// 链上还没有任何服务商
        case empty
        /// 有服务商、至少一个可用（enabled + 有 key + 有模型）
        case healthy
        /// 有服务商但无一可用
        case noneAvailable
    }

    var total: Int
    var available: Int

    var state: State {
        if total == 0 { return .empty }
        return available > 0 ? .healthy : .noneAvailable
    }

    var statusTitle: String {
        state == .healthy ? "链路正常" : "还没有可用的服务商"
    }

    var statusDetail: String {
        switch state {
        case .healthy: return "提问时按顺序尝试，任一可用即工作，失败自动切换"
        case .empty: return "添加第一个服务商并填入 Key，就能向 AI 助教提问。"
        case .noneAvailable: return "给服务商补上 Key 和模型（或重新启用停用的服务商），任一可用即工作。"
        }
    }

    /// S23 设置行值文案（「N 个服务商 · M 个可用」）
    var settingsRowValue: String { "\(total) 个服务商 · \(available) 个可用" }

    static let empty = ProviderChainSummary(total: 0, available: 0)
}

// MARK: - 链路行状态点（S25 spec：绿 #7FA97C / 暗灰 #524B46 / 陶土红 #C97064）

enum ProviderRowStatus: Equatable {
    /// enabled + 有 key + 有模型，且最近一次调用未失败
    case available
    /// 未配置（缺 key / 缺模型 / 已停用）
    case unconfigured
    /// 最近一次调用该商失败（红：不谎称正常）
    case failedRecently
}

// MARK: - 诊断行（mono 三列：时间 / 服务商·模型 / 结果）

/// 诊断卡一行的展示数据（时间戳等已格式化）。永不包含 key——入参本来就不带 key。
struct ChainDiagnosticRow: Equatable, Identifiable {
    var id: UUID
    var timeText: String
    var targetText: String
    var resultText: String
    var succeeded: Bool
}

// MARK: - 添加流程

/// 添加流程的失败原因（Result 的 Failure 必须 conform Error；message 直接展示给用户，不吞错）
struct ProviderChainError: Error, Equatable {
    var message: String
}

// MARK: - 纯逻辑

enum ProviderChainLogic {
    /// 稳定升序（同 sortOrder 按录入序，不抖动）。含已停用——停用行在链区外单独展示。
    static func ordered(_ providers: [AIProvider]) -> [AIProvider] {
        providers.enumerated().sorted { lhs, rhs in
            lhs.element.sortOrder == rhs.element.sortOrder
                ? lhs.offset < rhs.offset
                : lhs.element.sortOrder < rhs.element.sortOrder
        }.map(\.element)
    }

    /// 状态聚合。hasKey 由调用方注入（Keychain 读；本层不碰凭据）。
    static func summarize(_ providers: [AIProvider], hasKey: (String) -> Bool) -> ProviderChainSummary {
        ProviderChainSummary(
            total: providers.count,
            available: providers.filter { isAvailable($0, hasKey: hasKey) }.count
        )
    }

    /// 可用 = enabled + 有 key + 有至少一个非空模型 id
    static func isAvailable(_ provider: AIProvider, hasKey: (String) -> Bool) -> Bool {
        provider.enabled && hasKey(provider.providerId) && hasModels(provider)
    }

    static func hasModels(_ provider: AIProvider) -> Bool {
        provider.modelIds.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func rowStatus(provider: AIProvider, hasKey: Bool, recentFailure: Bool) -> ProviderRowStatus {
        if recentFailure { return .failedRecently }
        if provider.enabled && hasKey && hasModels(provider) { return .available }
        return .unconfigured
    }

    /// 每个服务商「最近一次调用」是否失败（诊断按时间正序，取该商最后一条）
    static func recentFailureProviderIds(_ diagnostics: [ChainDiagnosticEntry]) -> Set<String> {
        var latest: [String: Bool] = [:] // providerId → 最近一次是否失败
        for entry in diagnostics {
            latest[entry.providerId] = !entry.succeeded
        }
        return Set(latest.filter { $0.value }.keys)
    }

    /// 状态卡「当前使用」：上次成功命中的服务商·模型（降级时如实写实际生效者）
    static func statusCurrentText(lastSuccessful: ProviderChainRunner.LastSuccessful?, providers: [AIProvider]) -> String? {
        guard let lastSuccessful,
              let provider = providers.first(where: { $0.providerId == lastSuccessful.providerId }) else {
            return nil
        }
        let name = provider.displayName.isEmpty ? provider.providerId : provider.displayName
        return "当前使用：\(name) · \(lastSuccessful.modelId)"
    }

    /// 新服务商的 sortOrder（当前最大值 + 1；空链 = 0）
    static func nextSortOrder(_ providers: [AIProvider]) -> Int {
        (providers.map(\.sortOrder).max() ?? -1) + 1
    }

    static func isDuplicate(providerId: String, in providers: [AIProvider]) -> Bool {
        providers.contains { $0.providerId == providerId }
    }

    /// 自定义服务商的 providerId（稳定唯一；改了等于换 Keychain 条目，历史 key 不串）
    static func newCustomProviderId() -> String { UUID().uuidString }

    // MARK: 拖拽排序

    /// 拖拽落位：从 startIndex 出发，每过一个 pitch 进位一格，钳在 [0, count)。
    static func targetIndex(startIndex: Int, translation: CGFloat, pitch: CGFloat, count: Int) -> Int {
        guard count > 0, pitch > 0 else { return 0 }
        let raw = startIndex + Int((translation / pitch).rounded())
        return min(max(raw, 0), count - 1)
    }

    /// 落位后密集重排：sortOrder = 下标（0..<n），不残留同值
    static func sortOrderAssignments(_ orderedIds: [String]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: orderedIds.enumerated().map { ($0.element, $0.offset) })
    }

    // MARK: 模型 id

    /// 模型 id 增补：非空、trim 后去重；合法返回新数组，否则 nil（原因由调用方分辨）
    static func addModel(_ raw: String, to models: [String]) -> [String]? {
        let modelId = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelId.isEmpty else { return nil }
        let existing = models.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !existing.contains(modelId) else { return nil }
        return models + [modelId]
    }

    // MARK: baseURL 校验

    /// 与 OpenAICompatClient.endpointURL 同一判定（https(s) + host）；合法返回 nil。
    static func validateBaseURL(_ baseURL: String) -> String? {
        do {
            _ = try OpenAICompatClient.endpointURL(baseURL: baseURL)
            return nil
        } catch let error as AIProviderError {
            return error.summary
        } catch {
            return "baseURL 不合法：\(baseURL)"
        }
    }

    // MARK: 添加流程工厂

    /// 预设 + 用户输入 → AIProvider（sortOrder 由调用方给 nextSortOrder 的结果）。
    /// 非法返回错误短句（直接展示给用户，不吞错）。
    static func makeProvider(
        preset: ProviderPreset,
        displayName: String,
        baseURL: String,
        sortOrder: Int
    ) -> Result<AIProvider, ProviderChainError> {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(ProviderChainError(message: "显示名不能为空")) }
        let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = validateBaseURL(url) { return .failure(ProviderChainError(message: error)) }
        let providerId = preset.isCustom ? newCustomProviderId() : preset.rawValue
        return .success(AIProvider(
            providerId: providerId,
            displayName: name,
            baseURL: url,
            modelIds: [],
            enabled: true,
            sortOrder: sortOrder
        ))
    }

    // MARK: 诊断行格式化

    /// 一条诊断 → mono 三列展示数据（时间 MM-dd HH:mm / 服务商·模型截断 / ✓耗时 或 ✗原因）。
    static func diagnosticRow(
        _ entry: ChainDiagnosticEntry,
        targetLimit: Int = 14,
        resultLimit: Int = 24
    ) -> ChainDiagnosticRow {
        ChainDiagnosticRow(
            id: entry.id,
            timeText: timeFormatter.string(from: entry.timestamp),
            targetText: truncated("\(entry.providerDisplayName) \(entry.modelId)", limit: targetLimit),
            resultText: truncated(
                entry.succeeded ? "✓\(durationText(entry.durationMs))" : "✗\(entry.errorSummary ?? "失败")",
                limit: resultLimit
            ),
            succeeded: entry.succeeded
        )
    }

    /// 耗时：≥1s 一位小数秒，否则毫秒（S25 spec「✓1.8s」）
    static func durationText(_ ms: Int) -> String {
        guard ms >= 1000 else { return "\(ms)ms" }
        return String(format: "%.1fs", Double(ms) / 1000)
    }

    static func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

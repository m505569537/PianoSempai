import Foundation

// 多服务商故障转移链（用户架构原话锁定：「依次调用，有一个能够调用得通，那么就正常工作了」）。
//
// 行为契约（docs/decisions/0001 Q2–Q4 + data-model §5）：
// 1. 按 sortOrder 遍历服务商，商内按 modelIds 顺序尝试；任一 HTTP 200 且解析到内容即返回。
// 2. 失败静默继续下一个，每跳记诊断（providerId/displayName/modelId/error/耗时/时间戳）。
// 3. 全链失败 → 抛含各跳原因的 ProviderChainFailure，由调用方决定展示；本层无 UI、不弹窗。
// 4. 粘住上次成功模型：下次调用把它提到尝试序列最前；按 ChainRecoveryStrategy 试探恢复。
// 5. 诊断只留最近 N 条（默认 50），供 Stage B 的 S25 展示。
//
// 本层只读 Keychain、只出网、只返回结果：不写任何课程/判分/设置状态（红线 3）。

// MARK: - 输入

struct ChainInput: Equatable, Sendable {
    /// 用户原话（纯文字/MIDI 提问永不带附件）
    var question: String
    /// 行为规则提示（ContextBuilder 产出；空 = 不带 system 消息）
    var systemPrompt: String = ""
    /// 本地数据块（ContextBuilder 产出；空 = 本次无 take 上下文）
    var contextBlock: String = ""
    /// 本地组装的证据引用（随回答一起返回，落 ChatMessage.evidenceRefsJSON）
    var evidenceRefs: [EvidenceRef] = []
    var temperature: Double? = nil

    init(question: String, systemPrompt: String = "", contextBlock: String = "", evidenceRefs: [EvidenceRef] = [], temperature: Double? = nil) {
        self.question = question
        self.systemPrompt = systemPrompt
        self.contextBlock = contextBlock
        self.evidenceRefs = evidenceRefs
        self.temperature = temperature
    }
}

/// 视频提问的附加请求（与 ChainInput 分离：纯文字输入在结构上无法携带附件，
/// 月报观察等调用方用 Mirror 反射字段的红线测试因此仍然成立）。
struct ChainVideoRequest: Equatable, Sendable {
    /// 本地临时片段 + 区间元数据
    var payload: VideoClipPayload
    /// 「分析后删除云端视频」开关（默认 ON；仅视频提问生效）
    var deleteCloudFile: Bool = true
    /// 上传预处理用的视频模型 id（nil = 用该跳的 chat 模型 id）
    var modelOverride: String? = nil

    init(payload: VideoClipPayload, deleteCloudFile: Bool = true, modelOverride: String? = nil) {
        self.payload = payload
        self.deleteCloudFile = deleteCloudFile
        self.modelOverride = modelOverride
    }
}

// MARK: - 输出

struct ChainResult: Equatable, Sendable {
    /// 模型回答原文
    var text: String
    /// 「服务商显示名 · 模型 id」（运行时命中值，非写死）
    var providerModel: String
    /// 透传本次输入的证据引用（含失败跳的完整链路，供 S25 诊断）
    var evidenceRefs: [EvidenceRef]
    /// 本次调用的每跳记录（按尝试顺序）
    var attempts: [ChainDiagnosticEntry]
    /// 视频附件描述（纯文字提问为 nil）
    var videoAttachment: ChatVideoAttachment? = nil
}

/// 单跳诊断（S25 展示；永不包含 key）
struct ChainDiagnosticEntry: Equatable, Sendable, Identifiable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var providerId: String
    var providerDisplayName: String
    var modelId: String
    var succeeded: Bool
    /// 失败原因短句（AIProviderError.summary / "未配置 Key"）
    var errorSummary: String?
    /// 该跳耗时（毫秒）
    var durationMs: Int
    /// 本跳是否因"粘住上次成功模型"被提到最前（诊断里可解释为什么没按链首走）
    var wasStickyStart: Bool

    init(timestamp: Date = Date(), providerId: String, providerDisplayName: String, modelId: String, succeeded: Bool, errorSummary: String? = nil, durationMs: Int = 0, wasStickyStart: Bool = false) {
        self.timestamp = timestamp
        self.providerId = providerId
        self.providerDisplayName = providerDisplayName
        self.modelId = modelId
        self.succeeded = succeeded
        self.errorSummary = errorSummary
        self.durationMs = durationMs
        self.wasStickyStart = wasStickyStart
    }
}

/// 全链失败（含各跳原因；summary 供 Stage B 直接展示）
struct ProviderChainFailure: Error, Equatable, Sendable {
    struct Attempt: Equatable, Sendable {
        var providerId: String
        var providerDisplayName: String
        var modelId: String
        var errorSummary: String
    }

    var attempts: [Attempt]

    var summary: String {
        if attempts.isEmpty {
            return "没有可用的服务商或模型（未启用 / 未配置模型）"
        }
        let lines = attempts.map { "\($0.providerDisplayName)·\($0.modelId)：\($0.errorSummary)" }
        return "全部 \(attempts.count) 跳都失败：" + lines.joined(separator: "；")
    }
}

// MARK: - 恢复探测策略

/// 粘住成功模型后，何时重新试探链上更高优先级者（可注入，默认探测式）。
enum ChainRecoveryStrategy: Equatable, Sendable {
    /// 只以上次成功模型起手，不主动探测（测试/用户手动"锁定当前模型"用）
    case stickyOnly
    /// 每 N 次调用（第 1 次起算，命中 N 的整数倍那次）忽略粘性、按链首顺序起手，
    /// 用以试探高优先级模型是否恢复。N ≤ 0 视为 stickyOnly。
    case probeEveryN(Int)

    static let `default` = ChainRecoveryStrategy.probeEveryN(5)
}

// MARK: - Runner

final class ProviderChainRunner {
    private let client: any AIClient
    private let keyStore: any ProviderKeyStore
    private let filesClient: any ArkFilesAPI
    private let recovery: ChainRecoveryStrategy
    private let maxDiagnosticEntries: Int

    /// 最近 N 条诊断（新者在尾部；只增不删旧于 N 的）
    private(set) var diagnostics: [ChainDiagnosticEntry] = []
    /// 上次成功的「服务商 + 模型」（内存态；Stage B 可落 AppSettings.lastSuccessfulProviderModel 持久化）
    private(set) var lastSuccessful: LastSuccessful?
    /// 已完成调用次数（恢复探测用）
    private var callCount = 0

    struct LastSuccessful: Equatable, Sendable {
        var providerId: String
        var modelId: String
    }

    init(
        client: any AIClient,
        keyStore: any ProviderKeyStore,
        recovery: ChainRecoveryStrategy = .default,
        maxDiagnosticEntries: Int = 50,
        filesClient: any ArkFilesAPI = ArkFileClient()
    ) {
        self.client = client
        self.keyStore = keyStore
        self.recovery = recovery
        self.maxDiagnosticEntries = max(1, maxDiagnosticEntries)
        self.filesClient = filesClient
    }

    // MARK: 主入口

    /// 依次尝试链上每一跳，任一成功即返回。
    /// - Parameters:
    ///   - providers: 全部服务商配置（内部只取 enabled，按 sortOrder 稳定升序）
    ///   - input: 纯文字输入（结构上不含附件字段）
    ///   - video: 视频提问附加请求（nil = 纯文字提问；S18b 确认后才非 nil）
    func run(providers: [AIProvider], input: ChainInput, video: ChainVideoRequest? = nil) async throws -> ChainResult {
        callCount += 1
        let hops = Self.plan(
            providers: providers,
            sticky: shouldProbe() ? nil : lastSuccessful
        )
        guard !hops.isEmpty else {
            throw ProviderChainFailure(attempts: [])
        }

        let textMessages = Self.messages(for: input)
        var attempts: [ChainDiagnosticEntry] = []

        for hop in hops {
            // 没配 key 的服务商：不请求，直接记一跳（Key 不在诊断里，只说"未配置"）
            guard let key = keyStore.read(providerId: hop.providerId), !key.isEmpty else {
                let entry = ChainDiagnosticEntry(
                    providerId: hop.providerId,
                    providerDisplayName: hop.providerDisplayName,
                    modelId: hop.modelId,
                    succeeded: false,
                    errorSummary: "未配置 Key",
                    durationMs: 0,
                    wasStickyStart: hop.isStickyStart
                )
                attempts.append(entry)
                appendDiagnostic(entry)
                continue
            }

            let target = AIRequestTarget(
                providerId: hop.providerId,
                providerDisplayName: hop.providerDisplayName,
                baseURL: hop.baseURL,
                model: hop.modelId,
                apiKey: key
            )

            // ---- 视频路径（仅 video != nil；纯文字路径行为完全不变）----
            if let videoRequest = video {
                let payload = videoRequest.payload
                // 每跳先判支持性：不支持就不上传、不请求（跨账号 file_id 不能复用）
                guard Self.supportsVideo(baseURL: hop.baseURL) else {
                    let entry = failureEntry(
                        hop: hop,
                        error: Self.videoUnsupportedSummary,
                        started: Date()
                    )
                    attempts.append(entry)
                    appendDiagnostic(entry)
                    continue
                }

                let uploadModel = Self.nonEmpty(videoRequest.modelOverride) ?? hop.modelId
                var cloudFileId: String?
                let started = Date()
                do {
                    // 用「该跳自己的 key/model」上传（不同账号的 file_id 不能跨账号使用）
                    let fileId = try await filesClient.upload(
                        fileURL: payload.fileURL,
                        model: uploadModel,
                        fps: payload.fps,
                        target: target
                    )
                    cloudFileId = fileId
                    try await filesClient.waitUntilActive(
                        id: fileId,
                        target: target,
                        timeout: 60,
                        pollInterval: 1
                    )

                    let request = ChatCompletionRequest(
                        model: hop.modelId,
                        messages: Self.videoMessages(for: input, fileId: fileId),
                        temperature: input.temperature
                    )
                    let text = try await client.send(request, target: target)

                    // 成功也要删云端文件；删除失败只进诊断，不影响本次回答
                    let deleted = await cleanUpCloudFile(
                        fileId,
                        target: target,
                        hop: hop,
                        video: videoRequest,
                        started: started
                    )
                    let entry = ChainDiagnosticEntry(
                        timestamp: started,
                        providerId: hop.providerId,
                        providerDisplayName: hop.providerDisplayName,
                        modelId: hop.modelId,
                        succeeded: true,
                        errorSummary: nil,
                        durationMs: Self.milliseconds(from: started, to: Date()),
                        wasStickyStart: hop.isStickyStart
                    )
                    attempts.append(entry)
                    appendDiagnostic(entry)
                    lastSuccessful = LastSuccessful(providerId: hop.providerId, modelId: hop.modelId)
                    return ChainResult(
                        text: text,
                        providerModel: target.providerModel,
                        evidenceRefs: input.evidenceRefs,
                        attempts: attempts,
                        videoAttachment: ChatVideoAttachment(
                            startSec: payload.startSec,
                            endSec: payload.endSec,
                            durationSec: max(0, payload.endSec - payload.startSec),
                            providerModel: target.providerModel,
                            cloudFileDeleted: deleted
                        )
                    )
                } catch {
                    // 失败（上传/等待/提问任一步）同样尝试删除已上传的云端文件
                    if let cloudFileId {
                        _ = await cleanUpCloudFile(
                            cloudFileId,
                            target: target,
                            hop: hop,
                            video: videoRequest,
                            started: started
                        )
                    }
                    if error is CancellationError { throw error }
                    let entry = failureEntry(hop: hop, error: Self.summary(for: error), started: started)
                    attempts.append(entry)
                    appendDiagnostic(entry)
                    continue
                }
            }

            // ---- 纯文字路径（M7.1 行为原样）----
            let request = ChatCompletionRequest(
                model: hop.modelId,
                messages: textMessages,
                temperature: input.temperature
            )

            let started = Date()
            do {
                let text = try await client.send(request, target: target)
                let entry = ChainDiagnosticEntry(
                    timestamp: started,
                    providerId: hop.providerId,
                    providerDisplayName: hop.providerDisplayName,
                    modelId: hop.modelId,
                    succeeded: true,
                    errorSummary: nil,
                    durationMs: Self.milliseconds(from: started, to: Date()),
                    wasStickyStart: hop.isStickyStart
                )
                attempts.append(entry)
                appendDiagnostic(entry)
                lastSuccessful = LastSuccessful(providerId: hop.providerId, modelId: hop.modelId)
                return ChainResult(
                    text: text,
                    providerModel: target.providerModel,
                    evidenceRefs: input.evidenceRefs,
                    attempts: attempts
                )
            } catch let error as AIProviderError {
                let entry = failureEntry(hop: hop, error: error.summary, started: started)
                attempts.append(entry)
                appendDiagnostic(entry)
            } catch {
                let entry = failureEntry(hop: hop, error: "未知错误：\(error.localizedDescription)", started: started)
                attempts.append(entry)
                appendDiagnostic(entry)
            }
        }

        throw ProviderChainFailure(attempts: attempts.map {
            ProviderChainFailure.Attempt(
                providerId: $0.providerId,
                providerDisplayName: $0.providerDisplayName,
                modelId: $0.modelId,
                errorSummary: $0.errorSummary ?? "未知错误"
            )
        })
    }

    /// 纯文字入口（ChatChainRunning 协议要求的两参形态；等价于 video: nil）
    func run(providers: [AIProvider], input: ChainInput) async throws -> ChainResult {
        try await run(providers: providers, input: input, video: nil)
    }

    /// 清空诊断与粘性（Stage B 的 S25「重新测试链」/改配置后调用）
    func reset() {
        diagnostics.removeAll()
        lastSuccessful = nil
        callCount = 0
    }

    // MARK: 内部

    /// 不支持视频的服务商诊断短句（S25 可读；不造假服务商名）
    static let videoUnsupportedSummary = "该服务商不支持视频输入"

    /// 视频输入支持判定：方舟（Ark 兼容）系才支持 Files API / video_url.file_id。
    /// 其余服务商照常走链，只是视频提问这一跳被跳过。
    static func supportsVideo(provider: AIProvider) -> Bool {
        supportsVideo(baseURL: provider.baseURL)
    }

    static func supportsVideo(baseURL: String) -> Bool {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = URLComponents(string: trimmed)?.host?.lowercased() else { return false }
        return !host.isEmpty && host.contains("ark.cn-beijing.volces.com")
    }

    /// 失败原因短句（AIProviderError / ArkFileError 各用自己的 summary；永不包含 key）
    static func summary(for error: Error) -> String {
        switch error {
        case let error as AIProviderError: return error.summary
        case let error as ArkFileError: return error.summary
        case is CancellationError: return "已取消"
        default: return "未知错误：\(error.localizedDescription)"
        }
    }

    /// 删除云端文件（开关 ON 时）。永不抛错——失败只追加一条 modelId == "file-delete" 的诊断。
    /// - Returns: 实际删除成功才为 true（关开关 / 删除失败都如实为 false）
    private func cleanUpCloudFile(
        _ fileId: String,
        target: AIRequestTarget,
        hop: Hop,
        video: ChainVideoRequest,
        started: Date
    ) async -> Bool {
        guard video.deleteCloudFile else { return false }
        do {
            try await filesClient.delete(id: fileId, target: target)
            return true
        } catch {
            let entry = ChainDiagnosticEntry(
                timestamp: Date(),
                providerId: hop.providerId,
                providerDisplayName: hop.providerDisplayName,
                modelId: "file-delete",
                succeeded: false,
                errorSummary: Self.summary(for: error),
                durationMs: Self.milliseconds(from: started, to: Date()),
                wasStickyStart: hop.isStickyStart
            )
            appendDiagnostic(entry)
            return false
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func failureEntry(hop: Hop, error: String, started: Date) -> ChainDiagnosticEntry {
        ChainDiagnosticEntry(
            providerId: hop.providerId,
            providerDisplayName: hop.providerDisplayName,
            modelId: hop.modelId,
            succeeded: false,
            errorSummary: error,
            durationMs: Self.milliseconds(from: started, to: Date()),
            wasStickyStart: hop.isStickyStart
        )
    }

    private func appendDiagnostic(_ entry: ChainDiagnosticEntry) {
        diagnostics.append(entry)
        if diagnostics.count > maxDiagnosticEntries {
            diagnostics.removeFirst(diagnostics.count - maxDiagnosticEntries)
        }
    }

    /// 本次调用是否忽略粘性、按链首顺序起手（恢复探测）
    private func shouldProbe() -> Bool {
        guard lastSuccessful != nil else { return false }
        switch recovery {
        case .stickyOnly: return false
        case .probeEveryN(let n): return n > 0 && callCount % n == 0
        }
    }

    /// system（行为规则）+ user（数据块 + 问题）。无 system 时只发 user。
    static func messages(for input: ChainInput) -> [ChatCompletionMessage] {
        var messages: [ChatCompletionMessage] = []
        if !input.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(.text(role: "system", input.systemPrompt))
        }
        messages.append(.text(role: "user", userText(for: input)))
        return messages
    }

    /// 视频提问：system 同文字路径；user 是 parts = [video_url(file_id), text]。
    /// 文本部分复用 userText(for:)，不复制格式化逻辑。
    static func videoMessages(for input: ChainInput, fileId: String) -> [ChatCompletionMessage] {
        var messages: [ChatCompletionMessage] = []
        if !input.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(.text(role: "system", input.systemPrompt))
        }
        let parts: [ContentPart] = [
            ContentPart(kind: .videoURL, fileId: fileId),
            ContentPart(kind: .text, text: userText(for: input)),
        ]
        messages.append(ChatCompletionMessage(role: "user", content: .parts(parts)))
        return messages
    }

    /// user 消息正文：有本地数据块时按 ContextBuilder 口径包一层；纯问题原样。
    static func userText(for input: ChainInput) -> String {
        if !input.contextBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "以下是我本地练习里的真实数据，仅供你引用：\n\(input.contextBlock)\n\n我的问题：\(input.question)"
        }
        return input.question
    }

    private static func milliseconds(from: Date, to: Date) -> Int {
        Int((to.timeIntervalSince(from) * 1000).rounded())
    }

    // MARK: 计划（纯函数，可单测）

    /// 一次调用的尝试序列：enabled 服务商按 sortOrder 稳定升序，商内按 modelIds 顺序；
    /// 上次成功的那一跳被提到最前（isStickyStart = true），其余相对顺序不变。
    struct Hop: Equatable, Sendable {
        var providerId: String
        var providerDisplayName: String
        var baseURL: String
        var modelId: String
        var isStickyStart: Bool
    }

    static func plan(providers: [AIProvider], sticky: LastSuccessful?) -> [Hop] {
        let ordered = providers
            .filter(\.enabled)
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.sortOrder == rhs.element.sortOrder
                    ? lhs.offset < rhs.offset   // 同优先级按录入序（稳定排序）
                    : lhs.element.sortOrder < rhs.element.sortOrder
            }
            .map(\.element)

        var hops: [Hop] = ordered.flatMap { provider -> [Hop] in
            provider.modelIds
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { modelId in
                    Hop(
                        providerId: provider.providerId,
                        providerDisplayName: provider.displayName.isEmpty ? provider.providerId : provider.displayName,
                        baseURL: provider.baseURL,
                        modelId: modelId,
                        isStickyStart: false
                    )
                }
        }

        guard let sticky,
              let index = hops.firstIndex(where: { $0.providerId == sticky.providerId && $0.modelId == sticky.modelId }) else {
            return hops
        }
        let hit = hops.remove(at: index)
        hops.insert(Hop(
            providerId: hit.providerId,
            providerDisplayName: hit.providerDisplayName,
            baseURL: hit.baseURL,
            modelId: hit.modelId,
            isStickyStart: true
        ), at: 0)
        return hops
    }
}

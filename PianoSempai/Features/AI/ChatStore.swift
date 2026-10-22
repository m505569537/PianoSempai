import Foundation
import Observation
import SwiftData

// M7.1 Stage B2 · S18 AI 问答协调层（brief §1 ChatStore）。
//
// 职责：持有一个对话的消息状态、装配上下文、调链、持久化。
// 边界（红线 3）：只读本地数据；只在用户主动点发送时出网；回答只渲染为文字建议——
// 不写课程/判分/设置状态，不解析 AI 输出里的"指令"，不提供任何执行入口。
// Runner / KeyStore / 服务商列表全部协议化可注入：单测用假 runner，不打网络。

// MARK: - 依赖协议

/// 一次提问的执行者（S18 只问结果，不关心链上跳了几次）。
/// ProviderChainRunner 天然满足本协议（见文末 extension）。
protocol ChatChainRunning: AnyObject {
    func run(providers: [AIProvider], input: ChainInput) async throws -> ChainResult
    /// 视频提问（S18b 确认后才调用；纯文字调用走上面两参入口）
    func run(providers: [AIProvider], input: ChainInput, video: ChainVideoRequest?) async throws -> ChainResult
}

extension ChatChainRunning {
    /// 旧假 runner 只实现两参入口：视频请求明确报错，而不是静默丢掉附件。
    func run(providers: [AIProvider], input: ChainInput, video: ChainVideoRequest?) async throws -> ChainResult {
        guard video == nil else {
            throw AIProviderError.invalidRequest("该 runner 不支持视频提问")
        }
        return try await run(providers: providers, input: input)
    }
}

/// 服务商列表来源（视图侧注入 SwiftData 读取；单测注入假值）。
/// enabled 过滤由 runner 内部做，这里给全量。
protocol ChatProviderSource: AnyObject {
    func currentProviders() -> [AIProvider]
}

/// SwiftData 实现：读全部服务商配置（非密配置；Key 只在 Keychain）
final class SwiftDataChatProviderSource: ChatProviderSource {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func currentProviders() -> [AIProvider] {
        (try? context.fetch(FetchDescriptor<AIProvider>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }
}

// MARK: - 进入方式

/// S18 的两种入口（neko-ai.md「S18 入口与预填」）：
/// - FAB：自由问答，不带任何练习数据（takeContextId = nil）
/// - S13「问 Neko 这一段」：针对某次 take，附带 ContextBuilder 组装的真实数据
/// pieceTitle 由调用方从已有曲目数据传入（算不出传 nil，不编）
enum ChatMode {
    case freeform
    case take(Take, analysis: TakeAnalysis?, pieceTitle: String?)
}

// MARK: - 消息角色

/// ChatMessage.role 的取值域（data-model §2：user / neko）
enum ChatMessageRole: String {
    case user
    case neko
}

extension ChatMessage {
    var evidenceRefs: [EvidenceRef] {
        AIJSON.decode([EvidenceRef].self, from: evidenceRefsJSON) ?? []
    }

    /// 视频附件描述（attachmentsJSON 不存视频本体，只存区间与服务商结果）
    var videoAttachments: [ChatVideoAttachment] {
        AIJSON.decode([ChatVideoAttachment].self, from: attachmentsJSON) ?? []
    }

    var isUser: Bool { role == ChatMessageRole.user.rawValue }
}

// MARK: - 视频发送阶段（S18b 进度 / 取消 / 重试）

/// 视频发送只对「当前这一次提问」生效；纯文字提问从不进入这些阶段。
enum VideoSendPhase: Equatable, Sendable {
    case idle
    /// 本地裁切转码中（S18b 调 exportClip；此阶段还没上传任何字节）
    case exporting
    /// 上传 + 等待云端处理 + 等回答
    case uploading
    /// 失败原因短句（导出失败或全链失败；不吞错）
    case failed(String)
}

// MARK: - 纯文案（可单测；算不出就不显示，不编造）

/// 顶部标题 / 上下文条 / 证据 chip 的真实取值。
/// 数字与字段全部来自本地真实数据；缺字段就省略，不补默认值（红线 2）。
enum ChatContextText {

    /// 顶部 serif 标题：take 问答显曲名/简短上下文，自由问答显「问 Neko」
    static func title(mode: ChatMode) -> String {
        switch mode {
        case .freeform: return "问 Neko"
        case let .take(take, _, pieceTitle): return practiceTitle(take: take, pieceTitle: pieceTitle)
        }
    }

    /// 上下文条文案：告诉用户这次回答基于哪次练习（自由问答则明说不带数据）
    static func chip(mode: ChatMode, practiceIndex: Int?) -> String {
        switch mode {
        case .freeform:
            return "自由提问 · 不附带练习数据"
        case let .take(take, _, pieceTitle):
            var parts: [String] = []
            if let practiceIndex { parts.append("第 \(practiceIndex) 次练习") }
            parts.append(stamp(take.startedAt))
            let name = practiceTitle(take: take, pieceTitle: pieceTitle)
            if !name.isEmpty { parts.append(name) }
            return parts.joined(separator: " · ")
        }
    }

    /// 曲名优先取调用方给的 pieceTitle，再退回 take.title，最后退回小节区间；都没有就中性描述
    static func practiceTitle(take: Take, pieceTitle: String?) -> String {
        if let pieceTitle, !pieceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return pieceTitle
        }
        if !take.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return take.title }
        if let from = take.measureFrom, let to = take.measureTo { return "第 \(from)–\(to) 小节" }
        if let from = take.measureFrom { return "自第 \(from) 小节起" }
        return "练习 take"
    }

    /// 同一曲目的第几次练习（startedAt 升序，1-based）。
    /// take 无 pieceId 或不在列表里 → nil：算不出就不显示序号，不编（红线 2）。
    static func practiceIndex(of take: Take, among takes: [Take]) -> Int? {
        guard let pieceId = take.pieceId else { return nil }
        let samePiece = takes
            .filter { $0.pieceId == pieceId }
            .sorted { $0.startedAt < $1.startedAt }
        guard let offset = samePiece.firstIndex(where: { $0.entityId == take.entityId }) else { return nil }
        return offset + 1
    }

    /// 日期短签（M/d HH:mm）
    static func stamp(_ date: Date) -> String {
        stampFormatter.string(from: date)
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()
}

/// neko 气泡下方的证据引用 chip 文案（只显示 evidence 里真实存在的字段）
enum EvidenceChipText {
    static func measure(_ ref: EvidenceRef) -> String { "第 \(ref.measure) 小节" }

    /// deviationMs 为 nil → nil：不补 0、不拿全局中位数冒充小节偏差（红线 2）
    static func deviation(_ ref: EvidenceRef) -> String? {
        guard let ms = ref.deviationMs else { return nil }
        return "偏差 \(Int(ms.rounded())) ms"
    }
}

// MARK: - 协调器

@MainActor
@Observable
final class ChatStore {
    private let context: ModelContext
    private let runner: any ChatChainRunning
    private let keyStore: any ProviderKeyStore
    private let providerSource: any ChatProviderSource
    private let mode: ChatMode

    /// 本会话的消息（按时间正序；与 DB 同一批对象）
    private(set) var messages: [ChatMessage] = []
    /// 已建/复用的会话 id（nil = 还没发过消息，首次发送时建）
    private(set) var threadId: UUID?
    /// 发送中（视图显思考态并暂时禁用发送，防重复）
    private(set) var isSending = false
    /// 全链失败（ProviderChainFailure.summary + 各跳原因）；nil = 无失败
    private(set) var failure: ProviderChainFailure?
    /// 链路可用性（无可用服务商 → 空态 + 输入禁用）
    private(set) var summary: ProviderChainSummary = .empty
    /// 本次上下文组装结果（上下文条 / 降级提示 / 证据都用它）
    private(set) var contextOutput: ContextBuilder.Output?
    /// 该 take 是同一曲目的第几次练习（算不出 → nil，不显示序号）
    private(set) var practiceIndex: Int?

    /// 全链失败后待重试的用户输入：重发它时不重复落 user 消息
    private var pendingQuestion: String?

    // MARK: 视频发送（S18b）

    /// 视频发送阶段（S18b 观察；纯文字恒 idle）
    private(set) var videoSendPhase: VideoSendPhase = .idle
    /// 当前视频发送是否可取消（上传中有可取消的 Task）
    private(set) var canCancelVideoSend = false
    /// 当前视频发送任务（测试可 await；用户取消走 cancelVideoSend）
    private(set) var videoSendTask: Task<Void, Never>?

    /// 待重试的视频提问（失败后保留同一临时片段，重试不重新裁切）
    private var pendingVideo: PendingVideo?
    /// 本次视频提问落下的 user 消息（成功后回填真实 providerModel/删除结果）
    private var appendedVideoMessage: ChatMessage?

    private struct PendingVideo {
        var question: String
        var attachment: ChatVideoAttachment
        var clip: VideoClipPayload
        var deleteCloudFile: Bool
    }

    init(
        mode: ChatMode,
        context: ModelContext,
        keyStore: any ProviderKeyStore = KeychainProviderKeyStore(),
        runner: (any ChatChainRunning)? = nil,
        providerSource: (any ChatProviderSource)? = nil
    ) {
        self.mode = mode
        self.context = context
        self.keyStore = keyStore
        self.runner = runner ?? ProviderChainRunner(client: OpenAICompatClient(), keyStore: keyStore)
        self.providerSource = providerSource ?? SwiftDataChatProviderSource(context: context)
        loadState()
    }

    // MARK: 派生状态

    /// 有没有可用服务商（enabled + 有 key + 有模型）；false → 空态、输入禁用
    var hasAvailableProvider: Bool { summary.state == .healthy }

    var headerTitle: String { ChatContextText.title(mode: mode) }

    var contextChipText: String { ChatContextText.chip(mode: mode, practiceIndex: practiceIndex) }

    /// 本次是否带 take 上下文（false = 自由问答口径）
    var hasTakeContext: Bool { contextOutput?.hasTakeContext ?? false }

    /// 降级说明（如该 take 无判分结果）：如实提示，不假装带了完整数据
    var contextDegradations: [String] { contextOutput?.degradations ?? [] }

    // MARK: 生命周期

    /// 进入/回到前台时刷新（Key 可能在 S25 刚被填上）
    func refreshAvailability() {
        summary = ProviderChainLogic.summarize(providerSource.currentProviders()) {
            keyStore.hasKey(providerId: $0)
        }
    }

    /// 建会话 + 回填历史。take 问答：该 take 已有 thread 就复用（多次进来接着聊）；
    /// 自由问答：每次新会话（历史会话列表非 M7.1 必需）。
    private func loadState() {
        refreshAvailability()
        if case let .take(take, _, _) = mode {
            practiceIndex = ChatContextText.practiceIndex(of: take, among: fetchTakes())
            if let thread = existingThread(takeId: take.entityId) {
                threadId = thread.entityId
                messages = fetchMessages(threadId: thread.entityId)
            }
        }
        contextOutput = buildContext()
    }

    // MARK: 发送

    /// 纯文字发送（旧入口；行为与 M7.1 完全一致）。
    func send(text raw: String) {
        send(text: raw, attachment: nil, clip: nil)
    }

    /// 发送入口（S18b 视频提问复用）。
    /// - Parameters:
    ///   - attachment: nil = 纯文字；非 nil = 视频提问（必过 S18b 闸口）
    ///   - clip: 已裁切转码的 720p 临时片段；nil + exportError == nil 表示正在导出
    ///   - exportError: 本地导出失败原因（不发起上传，直接进失败态）
    ///   - deleteCloudFile: 「分析后删除云端视频」开关（默认 ON）
    func send(
        text raw: String,
        attachment: ChatVideoAttachment?,
        clip: VideoClipPayload?,
        exportError: String? = nil,
        deleteCloudFile: Bool = true
    ) {
        guard let attachment else {
            sendText(raw)
            return
        }

        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending, hasAvailableProvider else { return }

        // 导出失败：如实进失败态，不发明「正在上传」
        if let exportError {
            videoSendPhase = .failed(exportError)
            canCancelVideoSend = false
            return
        }

        // 导出中：S18b 随后带着 clip 再调一次（此阶段不落消息、不上传）
        guard let clip else {
            videoSendPhase = .exporting
            canCancelVideoSend = false
            return
        }

        // 开始上传/提问
        ensureThread()
        let userMessage = append(
            role: .user,
            text: text,
            evidenceRefs: [],
            providerModel: "",
            attachments: [attachment]
        )
        appendedVideoMessage = userMessage
        pendingVideo = PendingVideo(
            question: text,
            attachment: attachment,
            clip: clip,
            deleteCloudFile: deleteCloudFile
        )
        failure = nil
        videoSendPhase = .uploading
        canCancelVideoSend = true
        isSending = true
        let output = buildContext()
        contextOutput = output
        videoSendTask = Task { await runVideo(question: text, output: output) }
    }

    /// 纯文字发送（原 M7.1 逻辑逐行保留）。
    private func sendText(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending, hasAvailableProvider else { return }

        if pendingQuestion != text {
            ensureThread()
            append(role: .user, text: text, evidenceRefs: [], providerModel: "")
            pendingQuestion = text
        }
        failure = nil
        isSending = true
        let output = buildContext()
        contextOutput = output
        Task { await run(question: text, output: output) }
    }

    /// 全链失败后的「重试」：纯文字重发原问题；视频重发同一临时片段（不重新裁切）。
    func retry() {
        if let pending = pendingVideo {
            guard !isSending, hasAvailableProvider,
                  FileManager.default.fileExists(atPath: pending.clip.fileURL.path) else { return }
            failure = nil
            videoSendPhase = .uploading
            canCancelVideoSend = true
            isSending = true
            let output = buildContext()
            contextOutput = output
            videoSendTask = Task { await runVideo(question: pending.question, output: output) }
            return
        }
        guard let question = pendingQuestion else { return }
        send(text: question)
    }

    /// 取消本次视频发送：停任务、删临时片段、撤回尚未发出的 user 消息，回到 idle。
    func cancelVideoSend() {
        videoSendTask?.cancel()
        videoSendTask = nil
        if let pending = pendingVideo {
            deleteTempClip(pending.clip)
        }
        if let message = appendedVideoMessage {
            context.delete(message)
            messages.removeAll { $0.entityId == message.entityId }
            try? context.save()
        }
        pendingVideo = nil
        appendedVideoMessage = nil
        videoSendPhase = .idle
        canCancelVideoSend = false
        isSending = false
    }

    private func run(question: String, output: ContextBuilder.Output) async {
        let providers = providerSource.currentProviders()
        do {
            let result = try await runner.run(providers: providers, input: ChainInput(
                question: question,
                systemPrompt: output.systemPrompt,
                contextBlock: output.contextBlock,
                evidenceRefs: output.evidenceRefs
            ))
            // 成功：落 neko 消息；证据引用存本地组装的那一份（不是 AI 文本里解析出来的）
            append(role: .neko, text: result.text, evidenceRefs: output.evidenceRefs, providerModel: result.providerModel)
            pendingQuestion = nil
            failure = nil
        } catch let chainFailure as ProviderChainFailure {
            // 全链失败：不写成功消息，进错误态；user 消息保留可重试
            failure = chainFailure
        } catch {
            failure = ProviderChainFailure(attempts: [
                ProviderChainFailure.Attempt(
                    providerId: "",
                    providerDisplayName: "",
                    modelId: "",
                    errorSummary: "未知错误：\(error.localizedDescription)"
                ),
            ])
        }
        isSending = false
        refreshAvailability()
    }

    /// 视频提问：导出完成后的上传 + 等待回答。
    /// 成功：回填 user 消息的真实附件结果、删临时片段；失败：保留消息/片段供重试。
    private func runVideo(question: String, output: ContextBuilder.Output) async {
        guard let pending = pendingVideo else { return }
        do {
            let result = try await runner.run(
                providers: providerSource.currentProviders(),
                input: ChainInput(
                    question: question,
                    systemPrompt: output.systemPrompt,
                    contextBlock: output.contextBlock,
                    evidenceRefs: output.evidenceRefs
                ),
                video: ChainVideoRequest(
                    payload: pending.clip,
                    deleteCloudFile: pending.deleteCloudFile
                )
            )
            guard !Task.isCancelled else { return }

            // user 消息落实际命中的服务商·模型与云端删除结果（不谎称已删）
            if let message = appendedVideoMessage {
                message.attachmentsJSON = AIJSON.encode([result.videoAttachment ?? pending.attachment])
                try? context.save()
            }
            append(role: .neko, text: result.text, evidenceRefs: output.evidenceRefs, providerModel: result.providerModel)
            deleteTempClip(pending.clip)
            pendingVideo = nil
            appendedVideoMessage = nil
            pendingQuestion = nil
            failure = nil
            videoSendPhase = .idle
        } catch {
            // 用户取消：cancelVideoSend 已清理，这里不再改写状态
            guard !Task.isCancelled else { return }

            let summary = Self.videoFailureSummary(error)
            if let chainFailure = error as? ProviderChainFailure {
                failure = chainFailure
            } else {
                failure = ProviderChainFailure(attempts: [
                    ProviderChainFailure.Attempt(
                        providerId: "",
                        providerDisplayName: "",
                        modelId: "",
                        errorSummary: summary
                    ),
                ])
            }
            videoSendPhase = .failed(summary)
            // 保留 user 消息、附件与临时片段：用户在 S18b 点「重试」重发同一段
        }
        canCancelVideoSend = false
        isSending = false
        refreshAvailability()
    }

    /// 视频失败原因短句（永不包含 key；失败就是失败，不改写成成功）
    private static func videoFailureSummary(_ error: Error) -> String {
        switch error {
        case let error as ProviderChainFailure: return error.summary
        case let error as AIProviderError: return error.summary
        case let error as ArkFileError: return error.summary
        default: return "未知错误：\(error.localizedDescription)"
        }
    }

    private func deleteTempClip(_ clip: VideoClipPayload) {
        guard FileManager.default.fileExists(atPath: clip.fileURL.path) else { return }
        try? FileManager.default.removeItem(at: clip.fileURL)
    }

    // MARK: 持久化

    private func buildContext() -> ContextBuilder.Output {
        switch mode {
        case .freeform:
            return ContextBuilder.build(take: nil, analysis: nil)
        case let .take(take, analysis, _):
            return ContextBuilder.build(take: take, analysis: analysis)
        }
    }

    private func ensureThread() {
        if threadId != nil { return }
        let takeContextId: UUID?
        if case let .take(take, _, _) = mode { takeContextId = take.entityId } else { takeContextId = nil }
        let thread = ChatThread(takeContextId: takeContextId)
        context.insert(thread)
        threadId = thread.entityId
        try? context.save()
    }

    @discardableResult
    private func append(
        role: ChatMessageRole,
        text: String,
        evidenceRefs: [EvidenceRef],
        providerModel: String,
        attachments: [ChatVideoAttachment] = []
    ) -> ChatMessage? {
        guard let threadId else { return nil }
        let message = ChatMessage(
            threadId: threadId,
            role: role.rawValue,
            text: text,
            // 纯文字恒 "[]"（红线）；视频提问只存区间/服务商描述，不存视频本体
            attachmentsJSON: attachments.isEmpty ? "[]" : AIJSON.encode(attachments),
            evidenceRefsJSON: AIJSON.encode(evidenceRefs),
            providerModel: providerModel
        )
        context.insert(message)
        messages.append(message)
        try? context.save()
        return message
    }

    private func fetchTakes() -> [Take] {
        (try? context.fetch(FetchDescriptor<Take>())) ?? []
    }

    /// 该 take 上最新的会话（take 问答复用；同一 take 多次进来接着聊）
    private func existingThread(takeId: UUID) -> ChatThread? {
        (try? context.fetch(FetchDescriptor<ChatThread>()))?
            .filter { $0.takeContextId == takeId }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    private func fetchMessages(threadId: UUID) -> [ChatMessage] {
        (try? context.fetch(FetchDescriptor<ChatMessage>()))?
            .filter { $0.threadId == threadId }
            .sorted { $0.createdAt < $1.createdAt } ?? []
    }
}

// MARK: - Runner 满足协议

extension ProviderChainRunner: ChatChainRunning {}

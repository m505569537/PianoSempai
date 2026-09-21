import Foundation

// M7.1 AI 层共享 Codable 结构：请求 / 响应 / 证据引用 / JSON 存取。
// 纯值类型：不碰网络、不碰 SwiftData、不写任何状态（红线 3：AI 层只读）。

// MARK: - 证据引用（data-model §2 evidenceRefs[]）

/// 一条证据引用。由 ContextBuilder 从本地真实数据组装，随回答一起存
/// ChatMessage.evidenceRefsJSON，供对话/笔记钉到具体小节。
/// **不解析 AI 文本里的"指令"**（红线 1）：证据只来自本地数据。
struct EvidenceRef: Codable, Equatable, Identifiable, Sendable {
    var takeId: UUID
    /// 1-based 小节
    var measure: Int
    /// 该小节实测节奏偏差绝对值均值（ms）；本地没有这个数就留 nil——不编 0
    var deviationMs: Double?

    var id: String { "\(takeId.uuidString)#\(measure)" }

    init(takeId: UUID, measure: Int, deviationMs: Double? = nil) {
        self.takeId = takeId
        self.measure = measure
        self.deviationMs = deviationMs
    }
}

// MARK: - JSON 存取（ChatMessage 的两个 JSON 字段共用）

/// ChatMessage.attachmentsJSON / evidenceRefsJSON 的编解码入口。
/// 解析失败一律返回 nil/false（坏 JSON 不崩溃，调用方按"无数据"降级）。
enum AIJSON {
    static func encode(_ value: some Encodable) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - 请求

/// OpenAI content 的两种形态：纯文本，或多模态 parts 数组。
/// M7.1 只发 `.text`（纯文字/MIDI 问题永不带附件，红线 3）；
/// `.parts` 分支为 M7.2 视频/图片预留——不预先实现，只留编码形态。
enum MessageContent: Codable, Equatable, Sendable {
    case text(String)
    case parts([ContentPart])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            self = .parts(try container.decode([ContentPart].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .parts(let parts): try container.encode(parts)
        }
    }

    /// 扁平文本（parts 只取 text 类拼接）；诊断/落库用
    var flatText: String {
        switch self {
        case .text(let text): return text
        case .parts(let parts):
            return parts.compactMap { $0.kind == .text ? $0.text : nil }.joined(separator: "\n")
        }
    }
}

/// 多模态 part（M7.2 才真正产生；M7.1 只定义编码形态，见上方 MessageContent）
struct ContentPart: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case text
        case imageURL = "image_url"
        case videoURL = "video_url"
    }

    var kind: Kind
    /// kind == .text 时的正文
    var text: String?
    /// kind == .imageURL/.videoURL 时的地址（M7.2：经 S18b 确认的切片）
    var url: String?

    enum CodingKeys: String, CodingKey {
        case type, text, imageURL = "image_url", videoURL = "video_url"
    }

    init(kind: Kind, text: String? = nil, url: String? = nil) {
        self.kind = kind
        self.text = text
        self.url = url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(Kind.self, forKey: .type) ?? .text
        self.kind = kind
        self.text = try container.decodeIfPresent(String.self, forKey: .text)
        switch kind {
        case .imageURL:
            // OpenAI 形态 {"type":"image_url","image_url":{"url":"..."}}
            if let nested = try? container.decodeIfPresent(NestedURL.self, forKey: .imageURL) {
                self.url = nested.url
            } else {
                self.url = try container.decodeIfPresent(String.self, forKey: .imageURL)
            }
        case .videoURL:
            if let nested = try? container.decodeIfPresent(NestedURL.self, forKey: .videoURL) {
                self.url = nested.url
            } else {
                self.url = try container.decodeIfPresent(String.self, forKey: .videoURL)
            }
        case .text:
            self.url = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)
        switch kind {
        case .text:
            try container.encodeIfPresent(text, forKey: .text)
        case .imageURL:
            try container.encodeIfPresent(NestedURL(url: url), forKey: .imageURL)
        case .videoURL:
            try container.encodeIfPresent(NestedURL(url: url), forKey: .videoURL)
        }
    }

    private struct NestedURL: Codable, Equatable, Sendable {
        var url: String?
    }
}

/// 一条对话消息（OpenAI 格式）。role ∈ system/user/assistant。
struct ChatCompletionMessage: Codable, Equatable, Sendable {
    var role: String
    var content: MessageContent

    init(role: String, content: MessageContent) {
        self.role = role
        self.content = content
    }

    /// 纯文本消息便捷构造
    static func text(role: String, _ text: String) -> ChatCompletionMessage {
        ChatCompletionMessage(role: role, content: .text(text))
    }
}

/// POST {baseURL}/chat/completions 的请求体。temperature 为 nil 时不出现在 JSON 里。
/// 也实现 Decodable：测试/诊断需要把发出去的 body 原样读回来核对。
struct ChatCompletionRequest: Codable, Equatable, Sendable {
    var model: String
    var messages: [ChatCompletionMessage]
    var temperature: Double?

    init(model: String, messages: [ChatCompletionMessage], temperature: Double? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
    }
}

// MARK: - 响应

/// 成功响应（只取用得到的字段；未知字段忽略）
struct ChatCompletionResponse: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        var index: Int?
        var message: ResponseMessage?
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }

    struct ResponseMessage: Decodable, Sendable {
        var role: String?
        var content: String?
    }

    var id: String?
    var choices: [Choice]?

    /// choices[0].message.content（去空白后可为空串——由调用方判解码失败）
    var firstContent: String? {
        choices?.first?.message?.content
    }

    /// 解析成功返回 self；结构不符返回 nil（由调用方抛 decoding）
    static func decode(from data: Data) -> ChatCompletionResponse? {
        try? JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    }
}

/// OpenAI 兼容错误体：{"error":{"type":...,"code":"ModelNotOpen","message":...}}
struct OpenAIErrorEnvelope: Decodable, Sendable {
    struct ErrorBody: Decodable, Sendable {
        var type: String?
        var code: String?
        var message: String?
    }

    var error: ErrorBody?

    /// body 不是这个形态时返回 nil（按"无错误码"处理）
    static func decode(from data: Data) -> OpenAIErrorEnvelope? {
        try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data)
    }
}

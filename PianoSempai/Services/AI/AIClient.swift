import Foundation

// OpenAI 兼容出站客户端（data-model §5：出站域名仅限用户在 S25 配置的服务商）。
// 无 UI、无状态写入；协议化 URLSession，测试注入假 session 不打真实网络。

// MARK: - 请求目标

/// 单服务商单模型的一次请求目标。
/// `apiKey` 只从 Keychain 读出后直达 Authorization 头：**不进日志/诊断/导出**（红线 2）。
/// 自定义 description 恒掩码，防止误打印（诊断里只放 providerId/modelId，不放 target）。
struct AIRequestTarget: Equatable, Sendable, CustomStringConvertible {
    var providerId: String
    var providerDisplayName: String
    var baseURL: String
    var model: String
    var apiKey: String

    /// 「服务商显示名 · 模型 id」——命中文案与 ChatMessage.providerModel 同源
    var providerModel: String { "\(providerDisplayName) · \(model)" }

    var description: String {
        "AIRequestTarget(provider: \(providerId), model: \(model), baseURL: \(baseURL), key: ••••)"
    }
}

// MARK: - 错误（不吞错：每跳原因都带进诊断）

enum AIProviderError: Error, Equatable, Sendable {
    /// 401/403：key 无效、过期、或对该模型无权限
    case unauthorized
    /// 模型未开通（方舟 ModelNotOpen / InvalidEndpointOrModel / model_not_found 等）
    case modelNotOpen
    /// 传输层失败（无网、超时、TLS、连接被拒）
    case network(String)
    /// HTTP 200 但 body 里取不到内容（空 choices / 结构不符）
    case decoding(String)
    /// 其他 HTTP 错误（保留原始状态码与错误码，供 S25 诊断）
    case http(status: Int, code: String?)
    /// 本地组请求就失败（baseURL 不合法等）
    case invalidRequest(String)

    /// 诊断/报错用短句（永不包含 key）
    var summary: String {
        switch self {
        case .unauthorized: return "401/403：Key 无效或无权限"
        case .modelNotOpen: return "模型未开通（ModelNotOpen）"
        case .network(let detail): return "网络失败：\(detail)"
        case .decoding(let detail): return "响应解析失败：\(detail)"
        case .http(let status, let code): return "HTTP \(status)\(code.map { "（\($0)）" } ?? "")"
        case .invalidRequest(let detail): return "请求非法：\(detail)"
        }
    }
}

/// 状态码 + 错误体 → AIProviderError。
/// 判定以服务商返回的 code 优先（方舟把"模型未开通"也挂在 401 上），其次看状态码。
enum AIErrorClassifier {
    /// 各服务商对"模型没开通/模型名不存在"的错误码（大小写不敏感比对）
    static let modelNotOpenCodes: Set<String> = [
        "ModelNotOpen", "model_not_open", "ModelNotSupported",
        "InvalidEndpointOrModel", "model_not_found", "ModelNotFound",
    ]

    static func classify(statusCode: Int, body: Data?) -> AIProviderError {
        let envelope = body.flatMap { OpenAIErrorEnvelope.decode(from: $0) }
        let code = envelope?.error?.code
        let message = envelope?.error?.message

        if let code, modelNotOpenCodes.contains(where: { $0.lowercased() == code.lowercased() }) {
            return .modelNotOpen
        }

        switch statusCode {
        case 401, 403:
            return .unauthorized
        default:
            // 429（限流）/5xx 等都按普通失败走：链上静默转移到下一个
            return .http(status: statusCode, code: code ?? message)
        }
    }
}

// MARK: - 协议

/// 出站客户端。一个实现可服务整条链（target 里带 baseURL/key/model，实现本身无状态）。
protocol AIClient: AnyObject {
    /// 返回 choices[0].message.content 的原文（去首尾空白由调用方决定）
    func send(_ request: ChatCompletionRequest, target: AIRequestTarget) async throws -> String
}

/// URLSession 抽象（测试注入假 session）
protocol URLSessionDataProtocol: AnyObject {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// 真 URLSession 适配
final class SystemURLSession: URLSessionDataProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

// MARK: - 实现

/// OpenAI 兼容 /chat/completions 客户端（火山方舟/百炼/DeepSeek/自定义通用）。
final class OpenAICompatClient: AIClient {
    private let session: any URLSessionDataProtocol
    private let timeout: TimeInterval

    init(session: any URLSessionDataProtocol = SystemURLSession(), timeout: TimeInterval = 60) {
        self.session = session
        self.timeout = timeout
    }

    func send(_ request: ChatCompletionRequest, target: AIRequestTarget) async throws -> String {
        let url = try Self.endpointURL(baseURL: target.baseURL)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("Bearer \(target.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            throw AIProviderError.network(error.localizedDescription)
        } catch {
            throw AIProviderError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIProviderError.decoding("响应不是 HTTP（\(type(of: response))）")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIErrorClassifier.classify(statusCode: http.statusCode, body: data)
        }

        guard let envelope = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data) else {
            throw AIProviderError.decoding("200 响应不是预期的 JSON 结构")
        }
        guard let content = envelope.firstContent?
            .trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            throw AIProviderError.decoding("choices[0].message.content 为空")
        }
        return content
    }

    /// baseURL + "/chat/completions"。尾斜杠/多余空白都容错；
    /// scheme 必须 http(s) 且带 host——"https://" 这种壳子判非法（红线：出站域名必须明确）。
    static func endpointURL(baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed + "/chat/completions"),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty,
              let url = components.url else {
            throw AIProviderError.invalidRequest("baseURL 不合法：\(baseURL)")
        }
        return url
    }
}

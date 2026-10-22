import Foundation

// 火山方舟 Files API 客户端（ADR-0011 / PRD M7 V3）。
//
// 流程：POST /files 上传片段 → 轮询 GET /files/{id} 到 active → 提问 → DELETE /files/{id}。
// 只有 Files API 能让「分析后删除云端视频」开关真生效，且不受 Base64 50MB/64MB 限制。
//
// 红线：Key 只进 Authorization 头，永不出现在日志/错误/诊断里；本层不碰 SwiftData。

// MARK: - 错误

enum ArkFileError: Error, Equatable {
    /// 401/403：Key 无效、过期，或对该服务无权限
    case unauthorized
    /// 非 2xx（保留响应体短句，供 S25 诊断）
    case rejected(String)
    /// 云端预处理失败（status == failed）
    case processingFailed(String)
    /// 轮询到超时仍非 active
    case timedOut
    /// 传输层失败（无网、超时、TLS 等）
    case network(String)

    /// 诊断/报错用短句（永不包含 key）
    var summary: String {
        switch self {
        case .unauthorized: return "401/403：Key 无效或无权限"
        case .rejected(let detail): return "文件上传被拒绝：\(detail)"
        case .processingFailed(let detail): return "云端视频处理失败：\(detail)"
        case .timedOut: return "云端视频处理超时"
        case .network(let detail): return "网络失败：\(detail)"
        }
    }
}

// MARK: - 协议

/// Files API 的可注入抽象（ProviderChainRunner 单测用假实现，不打真实网络）。
protocol ArkFilesAPI: AnyObject {
    /// 上传视频文件，返回云端 file id（"file-..."）
    func upload(fileURL: URL, model: String, fps: Double, target: AIRequestTarget) async throws -> String
    /// 查询文件状态原文："processing" / "active" / "failed" / 未知值原样返回
    func status(id: String, target: AIRequestTarget) async throws -> String
    /// 轮询直到 active；超时抛 .timedOut，failed 抛 .processingFailed，取消抛 CancellationError
    func waitUntilActive(id: String, target: AIRequestTarget, timeout: TimeInterval, pollInterval: TimeInterval) async throws
    /// 删除云端文件
    func delete(id: String, target: AIRequestTarget) async throws
}

extension ArkFilesAPI {
    /// 默认口径：60s 超时、1s 间隔（ADR-0011）
    func waitUntilActive(id: String, target: AIRequestTarget) async throws {
        try await waitUntilActive(id: id, target: target, timeout: 60, pollInterval: 1)
    }
}

// MARK: - 实现

final class ArkFileClient: ArkFilesAPI {
    private let session: any URLSessionDataProtocol
    private let pollInterval: TimeInterval
    /// 轮询次数上限（与超时共同兜底；测试注入小值即可不真等待）
    private let maxPolls: Int
    /// 可注入的等待（测试注入空实现，避免真实 sleep）
    private let sleep: (TimeInterval) async throws -> Void

    init(
        session: any URLSessionDataProtocol = SystemURLSession(),
        pollInterval: TimeInterval = 1.0,
        maxPolls: Int = 120,
        sleep: @escaping (TimeInterval) async throws -> Void = { interval in
            try await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
        }
    ) {
        self.session = session
        self.pollInterval = pollInterval
        self.maxPolls = max(1, maxPolls)
        self.sleep = sleep
    }

    // MARK: 上传

    func upload(fileURL: URL, model: String, fps: Double, target: AIRequestTarget) async throws -> String {
        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            throw ArkFileError.rejected("无法读取本地视频文件")
        }

        let url = try Self.endpoint(baseURL: target.baseURL, path: "files")
        let boundary = "PianoSempaiBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(target.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            filename: fileURL.lastPathComponent,
            fileData: fileData,
            model: model,
            fps: fps
        )

        let (data, response) = try await perform(request)
        try Self.validate(response: response, body: data)

        let object = Self.decodeFileObject(data)
        guard let id = object.id, !id.isEmpty else {
            throw ArkFileError.rejected("上传响应缺少 file id")
        }
        if object.status == "failed" {
            throw ArkFileError.processingFailed(object.errorMessage ?? "云端处理失败")
        }
        return id
    }

    // MARK: 状态

    func status(id: String, target: AIRequestTarget) async throws -> String {
        let object = try await fetchFile(id: id, target: target)
        return object.status ?? "unknown"
    }

    func waitUntilActive(id: String, target: AIRequestTarget, timeout: TimeInterval, pollInterval: TimeInterval) async throws {
        let interval = max(0, pollInterval)
        // 次数预算 = 超时 / 间隔 + 首次查询；再受 maxPolls 兜底。测试注入的空 sleep 下也能确定性地超时。
        let byTimeout = Int(ceil(max(0, timeout) / max(interval, 0.001))) + 1
        let budget = max(1, min(maxPolls, byTimeout))
        let deadline = Date().addingTimeInterval(max(0, timeout))
        var polls = 0

        while true {
            try Task.checkCancellation()
            let object = try await fetchFile(id: id, target: target)
            switch object.status {
            case "active":
                return
            case "failed":
                throw ArkFileError.processingFailed(object.errorMessage ?? "云端处理失败")
            default:
                break
            }

            polls += 1
            if polls >= budget || Date() >= deadline {
                throw ArkFileError.timedOut
            }

            try Task.checkCancellation()
            try await sleep(interval)
        }
    }

    // MARK: 删除

    func delete(id: String, target: AIRequestTarget) async throws {
        let url = try Self.endpoint(baseURL: target.baseURL, path: "files/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30
        request.setValue("Bearer \(target.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await perform(request)
        try Self.validate(response: response, body: data)
    }

    // MARK: 内部

    private func fetchFile(id: String, target: AIRequestTarget) async throws -> FileObject {
        let url = try Self.endpoint(baseURL: target.baseURL, path: "files/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(target.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await perform(request)
        try Self.validate(response: response, body: data)
        return Self.decodeFileObject(data)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ArkFileError.network(error.localizedDescription)
        }
    }

    /// 状态码判定：401/403 → unauthorized；其余非 2xx → rejected(响应体短句)
    static func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ArkFileError.network("响应不是 HTTP")
        }
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw ArkFileError.unauthorized
        default:
            let text = String(data: body, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ArkFileError.rejected(text.isEmpty ? "HTTP \(http.statusCode)" : String(text.prefix(300)))
        }
    }

    /// baseURL + path；尾斜杠与多余空白容错，不产生双斜杠。
    static func endpoint(baseURL: String, path: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed + "/" + suffix),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty,
              let url = components.url else {
            throw ArkFileError.rejected("baseURL 不合法")
        }
        return url
    }

    /// 手写 multipart（不引第三方库）：purpose / preprocess_configs[video][model|fps] / file
    static func multipartBody(
        boundary: String,
        filename: String,
        fileData: Data,
        model: String,
        fps: Double
    ) -> Data {
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }

        func field(name: String, value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        field(name: "purpose", value: "user_data")
        field(name: "preprocess_configs[video][model]", value: model)
        field(name: "preprocess_configs[video][fps]", value: Self.fpsText(fps))

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: video/mp4\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    /// fps 文本：整数值不带小数点（1 而不是 1.0），其余保留原值
    static func fpsText(_ fps: Double) -> String {
        if fps.rounded() == fps, fps >= 0, fps <= Double(Int.max) {
            return String(Int(fps))
        }
        return String(fps)
    }

    private struct FileObject: Decodable {
        struct ErrorBody: Decodable {
            var message: String?
        }

        var id: String?
        var status: String?
        var error: ErrorBody?
        /// 方舟 failed 文件可能把原因放在 error.message，也可能放在 error_message
        var errorMessageField: String?

        enum CodingKeys: String, CodingKey {
            case id, status, error
            case errorMessageField = "error_message"
        }

        init(id: String? = nil, status: String? = nil, error: ErrorBody? = nil, errorMessageField: String? = nil) {
            self.id = id
            self.status = status
            self.error = error
            self.errorMessageField = errorMessageField
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            status = try container.decodeIfPresent(String.self, forKey: .status)
            error = try container.decodeIfPresent(ErrorBody.self, forKey: .error)
            errorMessageField = try container.decodeIfPresent(String.self, forKey: .errorMessageField)
        }

        var errorMessage: String? {
            if let message = error?.message, !message.isEmpty { return message }
            if let message = errorMessageField, !message.isEmpty { return message }
            return nil
        }
    }

    private static func decodeFileObject(_ data: Data) -> FileObject {
        (try? JSONDecoder().decode(FileObject.self, from: data)) ?? FileObject()
    }
}

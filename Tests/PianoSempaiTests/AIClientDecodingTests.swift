import XCTest
@testable import PianoSempai

/// M7.1 网络层验收（brief 场景 6：错误码解析 401 / ModelNotOpen / 解码失败）。
/// 假 URLSession：不打真实网络，只驱动 OpenAICompatClient 的编解码与错误分类。
final class AIClientDecodingTests: XCTestCase {

    private final class FakeURLSession: URLSessionDataProtocol {
        struct Reply {
            var statusCode: Int
            var body: Data
            var url: URL?
            var error: Error?
        }

        var reply: Reply
        private(set) var lastRequest: URLRequest?

        init(reply: Reply) {
            self.reply = reply
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            lastRequest = request
            if let error = reply.error { throw error }
            let url = reply.url ?? request.url ?? URL(string: "https://example.com")!
            let response = HTTPURLResponse(url: url, statusCode: reply.statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (reply.body, response)
        }
    }

    private func json(_ text: String) -> Data { Data(text.utf8) }

    private func target(model: String = "doubao-seed-1-6", providerId: String = "ark") -> AIRequestTarget {
        AIRequestTarget(
            providerId: providerId,
            providerDisplayName: "火山方舟",
            baseURL: "https://ark.cn-beijing.volces.com/api/v3",
            model: model,
            apiKey: "fake-test-key-not-real"
        )
    }

    private func client(_ reply: FakeURLSession.Reply) -> (OpenAICompatClient, FakeURLSession) {
        let session = FakeURLSession(reply: reply)
        return (OpenAICompatClient(session: session), session)
    }

    // MARK: 成功路径

    func testSuccessExtractsFirstChoiceContent() async throws {
        let body = json(#"""
        {"id":"chatcmpl-1","choices":[{"index":0,"message":{"role":"assistant","content":"第 12 小节慢练三遍。"},"finish_reason":"stop"}]}
        """#)
        let (client, _) = self.client(FakeURLSession.Reply(statusCode: 200, body: body))

        let text = try await client.send(ChatCompletionRequest(model: "m", messages: [.text(role: "user", "问")]), target: target())

        XCTAssertEqual(text, "第 12 小节慢练三遍。", "取 choices[0].message.content 原文")
    }

    func testSuccessTrimsWhitespaceAroundContent() async throws {
        let body = json(#"""
        {"choices":[{"message":{"content":"  前后有空白的回答  "}}]}
        """#)
        let (client, _) = self.client(FakeURLSession.Reply(statusCode: 200, body: body))

        let text = try await client.send(ChatCompletionRequest(model: "m", messages: []), target: target())
        XCTAssertEqual(text, "前后有空白的回答", "只去首尾空白，内部文本不改")
    }

    // MARK: 错误码解析

    func testUnauthorized401MapsToUnauthorized() async throws {
        let body = json(#"""
        {"error":{"type":"AuthenticationError","code":"InvalidApiKey","message":"api key is invalid"}}
        """#)
        let (client, _) = self.client(FakeURLSession.Reply(statusCode: 401, body: body))

        do {
            _ = try await client.send(ChatCompletionRequest(model: "m", messages: []), target: target())
            XCTFail("401 必须抛错")
        } catch let error as AIProviderError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testForbidden403MapsToUnauthorized() async throws {
        let body = json(#"{"error":{"code":"AccessDenied","message":"no permission"}}"#)
        let (client, _) = self.client(FakeURLSession.Reply(statusCode: 403, body: body))

        do {
            _ = try await client.send(ChatCompletionRequest(model: "m", messages: []), target: target())
            XCTFail("403 必须抛错")
        } catch let error as AIProviderError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testModelNotOpenCodeMapsToModelNotOpen() async throws {
        // 方舟：标准入口身份有效但模型未开通，错误码挂在 400/401 上
        let body = json(#"""
        {"error":{"type":"InvalidRequest","code":"ModelNotOpen","message":"model is not open for this account"}}
        """#)
        for status in [400, 401, 404] {
            let (client, _) = self.client(FakeURLSession.Reply(statusCode: status, body: body))
            do {
                _ = try await client.send(ChatCompletionRequest(model: "m", messages: []), target: target())
                XCTFail("HTTP \(status) + ModelNotOpen 必须抛错")
            } catch let error as AIProviderError {
                XCTAssertEqual(error, .modelNotOpen, "错误码优先于状态码（HTTP \(status)）")
            }
        }
    }

    func testInvalidEndpointOrModelAlsoCountsAsModelNotOpen() async throws {
        let body = json(#"{"error":{"code":"InvalidEndpointOrModel","message":"bad model"}}"#)
        let (client, _) = self.client(FakeURLSession.Reply(statusCode: 404, body: body))

        do {
            _ = try await client.send(ChatCompletionRequest(model: "m", messages: []), target: target())
            XCTFail("404 + InvalidEndpointOrModel 必须抛错")
        } catch let error as AIProviderError {
            XCTAssertEqual(error, .modelNotOpen)
        }
    }

    func testOtherHTTPStatusKeepsStatusCodeAndCode() async throws {
        let body = json(#"{"error":{"code":"RateLimitReached","message":"slow down"}}"#)
        let (client, _) = self.client(FakeURLSession.Reply(statusCode: 429, body: body))

        do {
            _ = try await client.send(ChatCompletionRequest(model: "m", messages: []), target: target())
            XCTFail("429 必须抛错")
        } catch let error as AIProviderError {
            XCTAssertEqual(error, .http(status: 429, code: "RateLimitReached"))
            XCTAssertTrue(error.summary.contains("429"))
            XCTAssertTrue(error.summary.contains("RateLimitReached"))
        }
    }

    func testNonJSONErrorBodyFallsBackToStatusOnly() async throws {
        let body = Data("upstream connect error".utf8)
        let (client, _) = self.client(FakeURLSession.Reply(statusCode: 502, body: body))

        do {
            _ = try await client.send(ChatCompletionRequest(model: "m", messages: []), target: target())
            XCTFail("502 必须抛错")
        } catch let error as AIProviderError {
            XCTAssertEqual(error, .http(status: 502, code: nil))
        }
    }

    // MARK: 解码失败

    func testEmptyChoicesIsDecodingFailure() async throws {
        let body = json(#"{"id":"x","choices":[]}"#)
        let (client, _) = self.client(FakeURLSession.Reply(statusCode: 200, body: body))

        do {
            _ = try await client.send(ChatCompletionRequest(model: "m", messages: []), target: target())
            XCTFail("空 choices 必须抛错")
        } catch let error as AIProviderError {
            guard case .decoding = error else { return XCTFail("应是 decoding，实为 \(error)") }
        }
    }

    func testNullContentIsDecodingFailure() async throws {
        let body = json(#"{"choices":[{"message":{"role":"assistant","content":null}}]}"#)
        let (client, _) = self.client(FakeURLSession.Reply(statusCode: 200, body: body))

        do {
            _ = try await client.send(ChatCompletionRequest(model: "m", messages: []), target: target())
            XCTFail("content 为 null 必须抛错")
        } catch let error as AIProviderError {
            guard case .decoding = error else { return XCTFail("应是 decoding，实为 \(error)") }
        }
    }

    func testBlankContentIsDecodingFailure() async throws {
        // 单反斜杠 \n 在 JSON 里是换行转义 → trim 后为空
        let body = json(#"{"choices":[{"message":{"content":"   \n  "}}]}"#)
        let (client, _) = self.client(FakeURLSession.Reply(statusCode: 200, body: body))

        do {
            _ = try await client.send(ChatCompletionRequest(model: "m", messages: []), target: target())
            XCTFail("空白 content 必须抛错")
        } catch let error as AIProviderError {
            guard case .decoding = error else { return XCTFail("应是 decoding，实为 \(error)") }
        }
    }

    func testMalformedSuccessBodyIsDecodingFailure() async throws {
        let body = json(#"{"choices":"not-an-array"}"#)
        let (client, _) = self.client(FakeURLSession.Reply(statusCode: 200, body: body))

        do {
            _ = try await client.send(ChatCompletionRequest(model: "m", messages: []), target: target())
            XCTFail("结构不符必须抛错")
        } catch let error as AIProviderError {
            guard case .decoding = error else { return XCTFail("应是 decoding，实为 \(error)") }
        }
    }

    // MARK: 传输层

    func testURLErrorMapsToNetworkFailure() async throws {
        let (client, _) = self.client(FakeURLSession.Reply(
            statusCode: 200,
            body: Data(),
            error: URLError(.notConnectedToInternet)
        ))

        do {
            _ = try await client.send(ChatCompletionRequest(model: "m", messages: []), target: target())
            XCTFail("无网必须抛错")
        } catch let error as AIProviderError {
            guard case .network = error else { return XCTFail("应是 network，实为 \(error)") }
            XCTAssertTrue(error.summary.contains("网络失败"))
        }
    }

    // MARK: 请求形态

    func testRequestShapeURLHeadersAndBody() async throws {
        let body = json(#"{"choices":[{"message":{"content":"ok"}}]}"#)
        let (client, session) = self.client(FakeURLSession.Reply(statusCode: 200, body: body))

        _ = try await client.send(
            ChatCompletionRequest(model: "doubao-seed-1-6", messages: [.text(role: "user", "第 3 小节")], temperature: 0.3),
            target: target()
        )

        let request = try XCTUnwrap(session.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://ark.cn-beijing.volces.com/api/v3/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fake-test-key-not-real")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let decoded = try JSONDecoder().decode(ChatCompletionRequest.self, from: try XCTUnwrap(request.httpBody))
        XCTAssertEqual(decoded.model, "doubao-seed-1-6")
        XCTAssertEqual(decoded.temperature, 0.3)
        XCTAssertEqual(decoded.messages.count, 1)
        XCTAssertEqual(decoded.messages[0].role, "user")
        XCTAssertEqual(decoded.messages[0].content, MessageContent.text("第 3 小节"))
    }

    func testEndpointURLToleratesTrailingSlashAndRejectsGarbage() throws {
        XCTAssertEqual(
            try OpenAICompatClient.endpointURL(baseURL: "https://ark.cn-beijing.volces.com/api/v3/").absoluteString,
            "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
        )
        XCTAssertEqual(
            try OpenAICompatClient.endpointURL(baseURL: "  https://api.deepseek.com/v1  ").absoluteString,
            "https://api.deepseek.com/v1/chat/completions"
        )
        XCTAssertEqual(
            try OpenAICompatClient.endpointURL(baseURL: "http://localhost:8080/v1").absoluteString,
            "http://localhost:8080/v1/chat/completions"
        )

        // 没写 scheme / 只有壳子 / 空串：一律判非法（出站域名必须明确，红线 §5）
        for bad in ["", "   ", "https://", "http://", "api.deepseek.com/v1", "not a url"] {
            do {
                _ = try OpenAICompatClient.endpointURL(baseURL: bad)
                XCTFail("\(bad) 必须判非法")
            } catch let error as AIProviderError {
                guard case .invalidRequest = error else { return XCTFail("应是 invalidRequest，实为 \(error)") }
            }
        }
    }

    // MARK: Key 不外泄

    func testTargetDescriptionNeverContainsKey() {
        let t = target()
        XCTAssertFalse(t.description.contains("fake-test-key-not-real"), "target 的 description 必须掩码 key（防误打印）")
        XCTAssertTrue(t.description.contains("••••"))
        XCTAssertEqual(t.providerModel, "火山方舟 · doubao-seed-1-6")
    }

    func testDiagnosticSummaryNeverContainsKey() {
        for error in [
            AIProviderError.unauthorized,
            AIProviderError.modelNotOpen,
            AIProviderError.network("offline"),
            AIProviderError.decoding("empty"),
            AIProviderError.http(status: 500, code: "InternalError"),
            AIProviderError.invalidRequest("bad url"),
        ] {
            XCTAssertFalse(error.summary.contains("fake-test-key-not-real"))
        }
    }
}

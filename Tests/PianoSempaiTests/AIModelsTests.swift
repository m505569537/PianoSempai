import XCTest
@testable import PianoSempai

/// M7.1 AI 线结构验收：请求/响应/证据引用的 Codable 形态与 JSON 存取。
final class AIModelsTests: XCTestCase {

    // MARK: 证据引用

    func testEvidenceRefRoundTripAndOmitsNilDeviation() throws {
        let refs = [
            EvidenceRef(takeId: UUID(), measure: 12, deviationMs: 38),
            EvidenceRef(takeId: UUID(), measure: 15),
        ]
        let json = AIJSON.encode(refs)
        XCTAssertTrue(json.contains("\"measure\":12"))
        XCTAssertFalse(json.contains("\"deviationMs\":null"), "nil 偏差不出现在 JSON 里（存的就是「没有」）")

        let decoded = try XCTUnwrap(AIJSON.decode([EvidenceRef].self, from: json))
        XCTAssertEqual(decoded, refs)
        XCTAssertEqual(decoded[0].deviationMs, 38)
        XCTAssertNil(decoded[1].deviationMs)
    }

    func testEvidenceRefDecodingToleratesMissingDeviationField() throws {
        let json = #"[{"takeId":"11111111-2222-3333-4444-555555555555","measure":9}]"#
        let decoded = try XCTUnwrap(AIJSON.decode([EvidenceRef].self, from: json))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].measure, 9)
        XCTAssertNil(decoded[0].deviationMs)
        XCTAssertEqual(decoded[0].id, "11111111-2222-3333-4444-555555555555#9")
    }

    func testAIJSONReturnsNilOnGarbageInsteadOfCrashing() {
        XCTAssertNil(AIJSON.decode([EvidenceRef].self, from: "{不是 JSON"))
        XCTAssertNil(AIJSON.decode([EvidenceRef].self, from: ""))
        // 编码正常时给出数组字面量（调用方按"无数据"降级）
        XCTAssertTrue(AIJSON.encode([EvidenceRef(takeId: UUID(), measure: 1)]).hasPrefix("["))
    }

    // MARK: MessageContent 形态

    func testTextContentEncodesAsPlainString() throws {
        let message = ChatCompletionMessage.text(role: "user", "第 3 小节")
        let data = try JSONEncoder().encode(message)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["role"] as? String, "user")
        XCTAssertEqual(object["content"] as? String, "第 3 小节", "纯文本 content 是裸字符串，不是对象")
        XCTAssertEqual(message.content, .text("第 3 小节"))
        XCTAssertEqual(message.content.flatText, "第 3 小节")
    }

    func testPartsContentEncodesAsArrayWithOpenAIShape() throws {
        let message = ChatCompletionMessage(role: "user", content: .parts([
            ContentPart(kind: .text, text: "这段在弹什么？"),
            ContentPart(kind: .imageURL, url: "https://cdn.example.com/clip.png"),
        ]))
        let data = try JSONEncoder().encode(message)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let parts = try XCTUnwrap(object["content"] as? [[String: Any]])

        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0]["type"] as? String, "text")
        XCTAssertEqual(parts[0]["text"] as? String, "这段在弹什么？")
        XCTAssertEqual(parts[1]["type"] as? String, "image_url")
        XCTAssertEqual((parts[1]["image_url"] as? [String: Any])?["url"] as? String, "https://cdn.example.com/clip.png")

        // flatText 只取文本 part（多模态分支 M7.2 才真正产生）
        XCTAssertEqual(message.content.flatText, "这段在弹什么？")
    }

    func testMessageContentDecodesBothShapes() throws {
        let textJSON = #"{"role":"user","content":"hi"}"#
        let partsJSON = #"{"role":"user","content":[{"type":"text","text":"hi"}]}"#
        let decoder = JSONDecoder()

        XCTAssertEqual(try decoder.decode(ChatCompletionMessage.self, from: Data(textJSON.utf8)).content, .text("hi"))
        let decoded = try decoder.decode(ChatCompletionMessage.self, from: Data(partsJSON.utf8))
        XCTAssertEqual(decoded.content, .parts([ContentPart(kind: .text, text: "hi")]))
    }

    // MARK: 请求体

    func testRequestOmitsNilTemperatureAndKeepsGivenOne() throws {
        let withoutTemp = try JSONEncoder().encode(ChatCompletionRequest(model: "m", messages: [.text(role: "user", "q")]))
        XCTAssertFalse(String(data: withoutTemp, encoding: .utf8)!.contains("temperature"))

        let withTemp = try JSONEncoder().encode(ChatCompletionRequest(model: "m", messages: [], temperature: 0))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: withTemp) as? [String: Any])
        XCTAssertEqual(object["temperature"] as? Double, 0, "0 是合法值，必须真的发出去")
        XCTAssertEqual(object["model"] as? String, "m")
        XCTAssertEqual((object["messages"] as? [Any])?.count, 0)
    }

    // MARK: 响应体

    func testResponseExtractsFirstChoiceContent() throws {
        let json = """
        {"id":"chatcmpl-1","choices":[{"index":0,"message":{"role":"assistant","content":"答"},"finish_reason":"stop"},
         {"index":1,"message":{"role":"assistant","content":"第二个"},"finish_reason":"stop"}]}
        """
        let response = try XCTUnwrap(ChatCompletionResponse.decode(from: Data(json.utf8)))
        XCTAssertEqual(response.firstContent, "答", "只取第一个 choice")
        XCTAssertEqual(response.choices?.count, 2)
        XCTAssertEqual(response.choices?.first?.finishReason, "stop")
    }

    func testResponseWithNoChoicesHasNilContent() throws {
        let json = #"{"id":"x","choices":[]}"#
        let response = try XCTUnwrap(ChatCompletionResponse.decode(from: Data(json.utf8)))
        XCTAssertNil(response.firstContent)
    }

    func testResponseMalformedBodyDecodesToNil() {
        XCTAssertNil(ChatCompletionResponse.decode(from: Data(#"{"choices":"nope"}"#.utf8)))
        XCTAssertNil(ChatCompletionResponse.decode(from: Data("not json".utf8)))
    }

    // MARK: 错误体

    func testErrorEnvelopeDecodesCodeAndMessage() throws {
        let json = #"{"error":{"type":"InvalidRequest","code":"ModelNotOpen","message":"model is not open"}}"#
        let envelope = try XCTUnwrap(OpenAIErrorEnvelope.decode(from: Data(json.utf8)))
        XCTAssertEqual(envelope.error?.code, "ModelNotOpen")
        XCTAssertEqual(envelope.error?.message, "model is not open")
        XCTAssertEqual(envelope.error?.type, "InvalidRequest")
    }

    func testErrorEnvelopeOnNonErrorBodyHasNilError() throws {
        // choices 响应不是错误体：能解出结构但 error 为 nil（分类器据此按"无错误码"处理）
        let envelope = try XCTUnwrap(OpenAIErrorEnvelope.decode(from: Data(#"{"choices":[]}"#.utf8)))
        XCTAssertNil(envelope.error)
        XCTAssertNil(OpenAIErrorEnvelope.decode(from: Data("upstream error".utf8)), "非 JSON 直接解不出")
    }

    // MARK: 分类器

    func testClassifierPrefersCodeOverStatus() throws {
        let body = Data(#"{"error":{"code":"ModelNotOpen"}}"#.utf8)
        XCTAssertEqual(AIErrorClassifier.classify(statusCode: 401, body: body), .modelNotOpen)
        XCTAssertEqual(AIErrorClassifier.classify(statusCode: 400, body: body), .modelNotOpen)
    }

    func testClassifierMapsStatusCodes() throws {
        XCTAssertEqual(AIErrorClassifier.classify(statusCode: 401, body: nil), .unauthorized)
        XCTAssertEqual(AIErrorClassifier.classify(statusCode: 403, body: nil), .unauthorized)
        XCTAssertEqual(AIErrorClassifier.classify(statusCode: 429, body: nil), .http(status: 429, code: nil))
        XCTAssertEqual(AIErrorClassifier.classify(statusCode: 500, body: nil), .http(status: 500, code: nil))
        // 无 body 时用 message 兜底当 code（部分服务商只给 message）
        let messageOnly = Data(#"{"error":{"message":"quota exceeded"}}"#.utf8)
        XCTAssertEqual(AIErrorClassifier.classify(statusCode: 429, body: messageOnly), .http(status: 429, code: "quota exceeded"))
    }

    func testClassifierModelNotOpenCodesAreCaseInsensitive() throws {
        let body = Data(#"{"error":{"code":"model_not_open"}}"#.utf8)
        XCTAssertEqual(AIErrorClassifier.classify(statusCode: 400, body: body), .modelNotOpen)
    }

    // MARK: ChatMessage JSON 字段

    func testChatMessageStoresEvidenceRefsAsJSON() throws {
        let refs = [EvidenceRef(takeId: UUID(), measure: 12, deviationMs: 42)]
        let message = ChatMessage(
            role: "neko",
            text: "第 12 小节是转指问题。",
            evidenceRefsJSON: AIJSON.encode(refs),
            providerModel: "火山方舟 · doubao-seed-1-6"
        )

        XCTAssertEqual(message.role, "neko")
        XCTAssertEqual(message.attachmentsJSON, "[]", "M7.1 恒空附件（视频阶段才写）")
        XCTAssertEqual(message.providerModel, "火山方舟 · doubao-seed-1-6")
        XCTAssertEqual(AIJSON.decode([EvidenceRef].self, from: message.evidenceRefsJSON), refs)
    }

    func testUserMessageCarriesNoProviderModel() throws {
        let message = ChatMessage(role: "user", text: "第 12 小节为什么总错音？")
        XCTAssertEqual(message.providerModel, "", "user 消息不记命中模型")
        XCTAssertEqual(message.evidenceRefsJSON, "[]")
    }
}

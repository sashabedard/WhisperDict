import XCTest
@testable import Pith

private final class MockTransport: HTTPTransport, @unchecked Sendable {
    var captured: URLRequest?
    var result: Result<(Data, HTTPURLResponse), Error>
    init(_ result: Result<(Data, HTTPURLResponse), Error>) { self.result = result }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        captured = request
        return try result.get()
    }
}

private func http(_ code: Int, _ body: String, url: String = "https://x/api/v1/chat/completions") -> (Data, HTTPURLResponse) {
    (Data(body.utf8), HTTPURLResponse(url: URL(string: url)!, statusCode: code, httpVersion: nil, headerFields: nil)!)
}

private let okBody = #"{"choices":[{"message":{"content":"Clean text."}}]}"#

final class OpenAICompatibleEnhanceBackendTests: XCTestCase {
    func testIsReadyRequiresEndpointAndModel() {
        XCTAssertFalse(OpenAICompatibleEnhanceBackend(endpoint: "", model: "m", apiKey: "").isReady)
        XCTAssertFalse(OpenAICompatibleEnhanceBackend(endpoint: "https://x/v1", model: "", apiKey: "").isReady)
        XCTAssertTrue(OpenAICompatibleEnhanceBackend(endpoint: "https://x/v1", model: "m", apiKey: "").isReady)
    }

    func testEnhanceBuildsRequestAndParsesContent() async {
        let mock = MockTransport(.success(http(200, okBody)))
        let backend = OpenAICompatibleEnhanceBackend(endpoint: "https://x/v1", model: "gpt-4o-mini",
                                                     apiKey: "sk-1", transport: mock)
        let out = await backend.enhance("um hello", style: .faithful, vocabulary: [], profile: "", formatLists: false)
        XCTAssertEqual(out, "Clean text.")
        let req = mock.captured!
        XCTAssertEqual(req.url?.absoluteString, "https://x/v1/chat/completions")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-1")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try! JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "gpt-4o-mini")
        XCTAssertEqual(body["temperature"] as? Double, 0)
        let messages = body["messages"] as! [[String: String]]
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertTrue(messages[1]["content"]!.contains("um hello"))
    }

    func testNoAuthHeaderWhenKeyEmpty() async {
        let mock = MockTransport(.success(http(200, okBody)))
        let backend = OpenAICompatibleEnhanceBackend(endpoint: "http://localhost:11434/v1", model: "llama3.1",
                                                     apiKey: "", transport: mock)
        _ = await backend.enhance("hi", style: .faithful, vocabulary: [], profile: "", formatLists: false)
        XCTAssertNil(mock.captured?.value(forHTTPHeaderField: "Authorization"))
    }

    func testNon2xxReturnsNil() async {
        let backend = OpenAICompatibleEnhanceBackend(endpoint: "https://x/v1", model: "m", apiKey: "k",
                                                     transport: MockTransport(.success(http(401, #"{"error":"bad key"}"#))))
        let out = await backend.enhance("hi", style: .faithful, vocabulary: [], profile: "", formatLists: false)
        XCTAssertNil(out)
    }

    func testMalformedAndEmptyReturnNil() async {
        for body in ["not json", #"{"choices":[]}"#, #"{"choices":[{"message":{"content":"   "}}]}"#] {
            let backend = OpenAICompatibleEnhanceBackend(endpoint: "https://x/v1", model: "m", apiKey: "k",
                                                         transport: MockTransport(.success(http(200, body))))
            let out = await backend.enhance("hi", style: .faithful, vocabulary: [], profile: "", formatLists: false)
            XCTAssertNil(out, "body: \(body)")
        }
    }

    func testTransportErrorReturnsNil() async {
        let backend = OpenAICompatibleEnhanceBackend(endpoint: "https://x/v1", model: "m", apiKey: "k",
                                                     transport: MockTransport(.failure(URLError(.timedOut))))
        let out = await backend.enhance("hi", style: .faithful, vocabulary: [], profile: "", formatLists: false)
        XCTAssertNil(out)
    }

    func testRunCommandParsesContent() async {
        let backend = OpenAICompatibleEnhanceBackend(endpoint: "https://x/v1", model: "m", apiKey: "k",
                                                     transport: MockTransport(.success(http(200, okBody))))
        let out = await backend.runCommand(instruction: "uppercase", on: "hi")
        XCTAssertEqual(out, "Clean text.")
    }

    func testOpenRouterEndpointEnforcesZDR() async {
        let mock = MockTransport(.success(http(200, okBody)))
        let backend = OpenAICompatibleEnhanceBackend(endpoint: "https://openrouter.ai/api/v1",
                                                     model: "meta-llama/llama-3.1-8b-instruct",
                                                     apiKey: "k", transport: mock)
        _ = await backend.enhance("hi", style: .faithful, vocabulary: [], profile: "", formatLists: false)
        let body = try! JSONSerialization.jsonObject(with: mock.captured!.httpBody!) as! [String: Any]
        let provider = body["provider"] as? [String: Any]
        XCTAssertEqual(provider?["zdr"] as? Bool, true)
    }

    func testNonOpenRouterEndpointHasNoProviderField() async {
        let mock = MockTransport(.success(http(200, okBody)))
        let backend = OpenAICompatibleEnhanceBackend(endpoint: "http://localhost:11434/v1",
                                                     model: "llama3.1", apiKey: "", transport: mock)
        _ = await backend.enhance("hi", style: .faithful, vocabulary: [], profile: "", formatLists: false)
        let body = try! JSONSerialization.jsonObject(with: mock.captured!.httpBody!) as! [String: Any]
        XCTAssertNil(body["provider"])
    }
}

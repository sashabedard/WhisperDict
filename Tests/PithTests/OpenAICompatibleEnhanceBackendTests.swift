// Pith — on-device push-to-talk dictation for macOS
// Copyright (C) 2026 Sasha Bédard
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

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

    // MARK: - stripPreamble (defensive cleanup for chatty BYOK models)

    private func strip(_ s: String) -> String { OpenAICompatibleEnhanceBackend.stripPreamble(s) }

    func testStripsLlamaPreambleLine() {
        XCTAssertEqual(strip("Here's the revised text:\n\nHello there."), "Hello there.")
        XCTAssertEqual(strip("Here is the cleaned version:\nHello there."), "Hello there.")
        XCTAssertEqual(strip("Voici le texte corrigé :\n\nBonjour."), "Bonjour.")
        XCTAssertEqual(strip("Sure! Here's the text:\n\nBonjour."), "Bonjour.")
    }

    func testStripsStrayLeadingBulletOnSingleLine() {
        XCTAssertEqual(strip("- Bonjour tout le monde."), "Bonjour tout le monde.")
        XCTAssertEqual(strip("* Hello there."), "Hello there.")
        XCTAssertEqual(strip("• Hello there."), "Hello there.")
    }

    func testKeepsGenuineMultiItemList() {
        let list = "- apples\n- pears\n- bananas"
        XCTAssertEqual(strip(list), list)
    }

    func testKeepsRealFirstLineThatIsNotPreamble() {
        // "Trois choses :" ends with ":" but isn't a known opener — must survive.
        let text = "Trois choses :\n\n- pommes\n- poires"
        XCTAssertEqual(strip(text), text)
        XCTAssertEqual(strip("Hello there, how are you?"), "Hello there, how are you?")
    }

    func testUnwrapsCodeFenceAndQuotes() {
        XCTAssertEqual(strip("```\nHello there.\n```"), "Hello there.")
        XCTAssertEqual(strip("```text\nHello there.\n```"), "Hello there.")
        XCTAssertEqual(strip("\"Hello there.\""), "Hello there.")
        XCTAssertEqual(strip("« Bonjour. »"), "Bonjour.")
    }

    func testStripsPhiChainOfThoughtKeepsOnlyFinalText() {
        let phi = """
        To clean up the dictation, we'll apply the specified fixes:

        1. **Remove filler words**: "J'ai jamais utilisé le modèle."
        2. **Capitalize and punctuate**: "J'ai jamais utilisé le modèle."
        3. **Resolve self-corrections**: There are no self-corrections.
        4. **Spell known terms exactly**: "Microsoft" is spelled correctly.
        5. **List formatting**: not applicable here.

        Applying these fixes, the cleaned text is:

        J'ai jamais utilisé le modèle d'intelligence artificielle de Microsoft. Je me demande s'il est bon.
        """
        XCTAssertEqual(strip(phi),
                       "J'ai jamais utilisé le modèle d'intelligence artificielle de Microsoft. Je me demande s'il est bon.")
    }

    func testStripsTrailingExplanationAndUnwrapsQuotedAnswer() {
        let out = """
        "I am testing to see if it works better now with the changes."

        This text maintains the speaker's language and meaning while removing filler words and ensuring proper capitalization and punctuation.
        """
        XCTAssertEqual(strip(out), "I am testing to see if it works better now with the changes.")
    }

    func testKeepsGenuineFinalParagraph() {
        // A real two-paragraph dictation must survive — the last paragraph does
        // not open with a meta-commentary phrase.
        let text = "Let's meet tomorrow.\n\nI have a question about the budget."
        XCTAssertEqual(strip(text), text)
    }

    func testResultMarkerInsideDictationIsNotTruncated() {
        // A real dictation never contains "the cleaned text is:" — but make sure
        // ordinary multi-sentence prose survives untouched.
        let text = "I reviewed the document twice. Everything looks correct now."
        XCTAssertEqual(strip(text), text)
    }

    func testEndToEndStripsBulletFromResponse() async {
        let body = #"{"choices":[{"message":{"content":"- Bonjour tout le monde."}}]}"#
        let backend = OpenAICompatibleEnhanceBackend(endpoint: "https://x/v1", model: "gemma",
                                                     apiKey: "k", transport: MockTransport(.success(http(200, body))))
        let out = await backend.enhance("bonjour", style: .faithful, vocabulary: [], profile: "", formatLists: false)
        XCTAssertEqual(out, "Bonjour tout le monde.")
    }
}

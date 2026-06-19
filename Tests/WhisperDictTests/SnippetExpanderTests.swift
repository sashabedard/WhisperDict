import XCTest
@testable import WhisperDict

final class SnippetExpanderTests: XCTestCase {

    func testExpandsWholeWordTrigger() {
        let out = SnippetExpander.expand("my email please", snippets: [("my email", "x@y.com")])
        XCTAssertEqual(out, "x@y.com please")
    }

    func testCaseInsensitive() {
        let out = SnippetExpander.expand("MY EMAIL", snippets: [("my email", "x@y.com")])
        XCTAssertEqual(out, "x@y.com")
    }

    func testLongerTriggerWinsOverShorterItContains() {
        let snippets = [("mon nom", "Sasha"), ("mon nom complet", "Sasha Bédard")]
        XCTAssertEqual(SnippetExpander.expand("mon nom complet", snippets: snippets), "Sasha Bédard")
        XCTAssertEqual(SnippetExpander.expand("mon nom", snippets: snippets), "Sasha")
    }

    func testDoesNotMatchInsideWords() {
        XCTAssertEqual(SnippetExpander.expand("summary", snippets: [("sum", "X")]), "summary")
    }

    func testEmptyInputsAreUnchanged() {
        XCTAssertEqual(SnippetExpander.expand("hello", snippets: []), "hello")
        XCTAssertEqual(SnippetExpander.expand("", snippets: [("a", "b")]), "")
    }

    func testExpansionWithRegexSpecialCharsIsLiteral() {
        // "$1" in the expansion must not be treated as a capture reference.
        let out = SnippetExpander.expand("price", snippets: [("price", "$1.00")])
        XCTAssertEqual(out, "$1.00")
    }
}

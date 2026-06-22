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

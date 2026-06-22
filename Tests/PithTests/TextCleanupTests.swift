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

final class TextCleanupTests: XCTestCase {

    func testStripsVocalizedPausesInBothLanguages() {
        XCTAssertEqual(TextCleanup.stripFillers("um so euh the thing", language: "auto"), "so the thing")
    }

    func testKeepsRealWordsLikeLike() {
        // "like" is a real word, never in the conservative set — must survive.
        XCTAssertEqual(TextCleanup.stripFillers("I like coffee", language: "auto"), "I like coffee")
    }

    func testRestoresLeadingCapitalization() {
        XCTAssertEqual(TextCleanup.stripFillers("Uh hello there", language: "en"), "Hello there")
    }

    func testEnglishSetDoesNotStripFrenchFiller() {
        XCTAssertEqual(TextCleanup.stripFillers("euh test", language: "en"), "euh test")
    }

    func testFrenchSetStripsAndCapitalizes() {
        XCTAssertEqual(TextCleanup.stripFillers("Euh bonjour", language: "fr"), "Bonjour")
    }

    func testWordBoundaryDoesNotTouchSubstrings() {
        // "uh" inside "though"/"uhuh" must not be removed.
        XCTAssertEqual(TextCleanup.stripFillers("though", language: "en"), "though")
        XCTAssertEqual(TextCleanup.stripFillers("uhuh", language: "en"), "uhuh")
    }

    func testAllFillersInputReturnsOriginalRatherThanEmpty() {
        // Stripping everything would yield "" — guard returns the input unchanged.
        XCTAssertEqual(TextCleanup.stripFillers("um uh", language: "en"), "um uh")
    }

    func testNoMatchIsUnchanged() {
        XCTAssertEqual(TextCleanup.stripFillers("hello world", language: "en"), "hello world")
    }
}

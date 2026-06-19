import XCTest
@testable import WhisperDict

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

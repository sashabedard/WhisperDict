import XCTest
@testable import WhisperDict

final class EnhancePromptTests: XCTestCase {
    func testInstructionsIncludeListRuleOnlyWhenAsked() {
        XCTAssertFalse(EnhancePrompt.instructions(style: .faithful, formatLists: false).contains("bulleted list"))
        XCTAssertTrue(EnhancePrompt.instructions(style: .faithful, formatLists: true).contains("bulleted list"))
    }
    func testInstructionsVaryByStyle() {
        XCTAssertTrue(EnhancePrompt.instructions(style: .email, formatLists: false).lowercased().contains("email"))
        XCTAssertTrue(EnhancePrompt.instructions(style: .code, formatLists: false).lowercased().contains("code"))
    }
    func testUserPromptEmbedsDictationVocabAndProfile() {
        let p = EnhancePrompt.userPrompt(dictation: "hello", vocabulary: ["WhisperKit"], profile: "Sasha")
        XCTAssertTrue(p.contains("hello"))
        XCTAssertTrue(p.contains("WhisperKit"))
        XCTAssertTrue(p.contains("Sasha"))
    }
    func testUserPromptOmitsEmptyVocabAndProfile() {
        let p = EnhancePrompt.userPrompt(dictation: "hi", vocabulary: [], profile: "")
        XCTAssertFalse(p.lowercased().contains("known terms"))
        XCTAssertFalse(p.lowercased().contains("profile"))
    }
    func testCommandUserPromptWrapsBoth() {
        let p = EnhancePrompt.commandUserPrompt(instruction: "make formal", on: "yo")
        XCTAssertTrue(p.contains("make formal"))
        XCTAssertTrue(p.contains("yo"))
    }
}

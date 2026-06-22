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

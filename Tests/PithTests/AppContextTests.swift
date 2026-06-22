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

final class AppContextTests: XCTestCase {

    func testMailMapsToEmail() {
        XCTAssertEqual(AppContext.resolvedStyle(userDefault: .faithful, bundleID: "com.apple.mail"), .email)
    }

    func testEditorMapsToCode() {
        XCTAssertEqual(AppContext.resolvedStyle(userDefault: .faithful, bundleID: "com.microsoft.vscode"), .code)
    }

    func testCasualAppMapsToFaithful() {
        XCTAssertEqual(AppContext.resolvedStyle(userDefault: .polished, bundleID: "com.tinyspeck.slackmacgap"), .faithful)
    }

    func testUnknownAppFallsBackToUserDefault() {
        XCTAssertEqual(AppContext.resolvedStyle(userDefault: .polished, bundleID: "com.unknown.app"), .polished)
        XCTAssertEqual(AppContext.resolvedStyle(userDefault: .email, bundleID: nil), .email)
    }

    func testSubstringMatchHandlesVendorPrefixedBundleIDs() {
        // Cursor ships under a todesktop.* bundle id — substring match should catch it.
        XCTAssertEqual(AppContext.resolvedStyle(userDefault: .faithful, bundleID: "com.todesktop.230313mzl4w4u92"), .code)
    }

    func testSupportsRichLists() {
        XCTAssertTrue(AppContext.supportsRichLists(bundleID: "com.tinyspeck.slackmacgap"))
        XCTAssertTrue(AppContext.supportsRichLists(bundleID: "com.apple.textedit"))
        XCTAssertFalse(AppContext.supportsRichLists(bundleID: "com.apple.finder"))
        XCTAssertFalse(AppContext.supportsRichLists(bundleID: nil))
    }
}

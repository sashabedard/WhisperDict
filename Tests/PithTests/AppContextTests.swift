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

import XCTest
@testable import Pith

final class UpdateCheckerTests: XCTestCase {
    func testIsNewerByPatchMinorMajor() {
        XCTAssertTrue(UpdateChecker.isNewer("0.2.2", than: "0.2.1"))
        XCTAssertTrue(UpdateChecker.isNewer("0.3.0", than: "0.2.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.0", than: "0.9.9"))
    }
    func testNotNewerWhenEqualOrOlder() {
        XCTAssertFalse(UpdateChecker.isNewer("0.2.1", than: "0.2.1"))
        XCTAssertFalse(UpdateChecker.isNewer("0.2.0", than: "0.2.1"))
    }
    func testMissingComponentsCountAsZero() {
        XCTAssertTrue(UpdateChecker.isNewer("0.3", than: "0.2.9"))   // 0.3.0 > 0.2.9
        XCTAssertFalse(UpdateChecker.isNewer("0.2", than: "0.2.0"))  // equal
    }
    func testStripsLeadingV() {
        XCTAssertTrue(UpdateChecker.isNewer("v0.2.2", than: "v0.2.1"))
        XCTAssertTrue(UpdateChecker.isNewer("v0.2.2", than: "0.2.1"))
    }
    func testGarbageIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("", than: "0.2.1"))
        XCTAssertFalse(UpdateChecker.isNewer("abc", than: "0.2.1"))
    }
    func testParseExtractsVersionAndDmgURL() {
        let json = """
        {"tag_name":"v0.2.2","assets":[
          {"name":"notes.txt","browser_download_url":"https://x/notes.txt"},
          {"name":"Pith-0.2.2.dmg","browser_download_url":"https://x/Pith-0.2.2.dmg"}
        ]}
        """.data(using: .utf8)!
        let release = UpdateChecker.parse(json)
        XCTAssertEqual(release?.version, "0.2.2")
        XCTAssertEqual(release?.dmgURL?.absoluteString, "https://x/Pith-0.2.2.dmg")
    }
    func testParseReturnsNilDmgWhenNoDmgAsset() {
        let json = """
        {"tag_name":"v0.2.2","assets":[{"name":"notes.txt","browser_download_url":"https://x/notes.txt"}]}
        """.data(using: .utf8)!
        let release = UpdateChecker.parse(json)
        XCTAssertEqual(release?.version, "0.2.2")
        XCTAssertNil(release?.dmgURL)
    }
    func testParseReturnsNilOnGarbage() {
        XCTAssertNil(UpdateChecker.parse(Data("not json".utf8)))
    }
}

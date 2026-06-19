import XCTest
@testable import WhisperDict

final class HotkeyManagerTests: XCTestCase {

    func testKnownPresetIsReturned() {
        let preset = HotkeyManager.preset(for: 54)
        XCTAssertEqual(preset.keyCode, 54)
        XCTAssertEqual(preset.flag, .command)
    }

    func testRightOptionPreset() {
        XCTAssertEqual(HotkeyManager.preset(for: 61).flag, .option)
    }

    func testUnknownKeyCodeFallsBackToFirstPreset() {
        let fallback = HotkeyManager.preset(for: 9999)
        XCTAssertEqual(fallback.keyCode, HotkeyManager.presets[0].keyCode)
    }
}

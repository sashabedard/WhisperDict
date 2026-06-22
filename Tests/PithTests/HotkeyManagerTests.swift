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

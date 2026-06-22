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

final class LevelMeterTests: XCTestCase {

    func testNormalizeClampsToZeroAndOne() {
        XCTAssertEqual(LevelMeter.normalize(rms: 0), 0, accuracy: 1e-6)   // silence → 0
        XCTAssertEqual(LevelMeter.normalize(rms: 1.0), 1, accuracy: 1e-6) // full scale → 1
    }

    func testNormalizeIsMonotonic() {
        XCTAssertLessThan(LevelMeter.normalize(rms: 0.01), LevelMeter.normalize(rms: 0.1))
    }

    func testSmoothAttackStep() {
        var meter = LevelMeter()
        // First step toward 1 uses the (fast) attack coefficient 0.6.
        XCTAssertEqual(meter.smooth(1.0), 0.6, accuracy: 1e-6)
    }

    func testReleaseIsSlowerThanAttack() {
        var meter = LevelMeter()
        _ = meter.smooth(1.0)                     // smoothed → 0.6 (attack)
        let afterRelease = meter.smooth(0.0)      // 0.6 + (0 - 0.6) * 0.15 = 0.51
        XCTAssertEqual(afterRelease, 0.51, accuracy: 1e-6)
    }

    func testSmoothClampsTargetAboveOne() {
        var meter = LevelMeter()
        XCTAssertEqual(meter.smooth(2.0), 0.6, accuracy: 1e-6)
    }
}

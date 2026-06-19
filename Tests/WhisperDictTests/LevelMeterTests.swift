import XCTest
@testable import WhisperDict

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

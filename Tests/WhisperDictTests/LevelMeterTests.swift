import XCTest
@testable import WhisperDict

final class LevelMeterTests: XCTestCase {
    func testSilenceMapsToZero() {
        XCTAssertEqual(LevelMeter.normalize(rms: 0), 0, accuracy: 0.001)
    }

    func testLoudMapsToOne() {
        // rms = 1.0 → 0 dB, well above the ceiling → clamps to 1
        XCTAssertEqual(LevelMeter.normalize(rms: 1.0), 1, accuracy: 0.001)
    }

    func testMonotonicInBetween() {
        let quiet = LevelMeter.normalize(rms: 0.01)
        let mid   = LevelMeter.normalize(rms: 0.1)
        let loud  = LevelMeter.normalize(rms: 0.5)
        XCTAssertLessThan(quiet, mid)
        XCTAssertLessThan(mid, loud)
    }

    func testOutputAlwaysInRange() {
        for rms: Float in [0, 0.0001, 0.01, 0.3, 1.0, 5.0] {
            let v = LevelMeter.normalize(rms: rms)
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
    }

    func testSmoothingRisesFastFallsSlow() {
        var meter = LevelMeter()
        _ = meter.update(rms: 0.0)        // start near 0
        let afterLoud = meter.update(rms: 1.0)   // fast attack → big jump
        let afterSilence = meter.update(rms: 0.0) // slow release → small drop
        XCTAssertGreaterThan(afterLoud, 0.4)
        XCTAssertGreaterThan(afterSilence, afterLoud * 0.5) // didn't collapse to 0
    }
}

import XCTest
@testable import WhisperDict

final class SpectrumAnalyzerTests: XCTestCase {
    private let sampleRate: Float = 16_000
    private let fftSize = 1024

    /// Generates `fftSize` samples of a sine at `freq` Hz.
    private func sine(_ freq: Float) -> [Float] {
        (0..<fftSize).map { sin(2 * .pi * freq * Float($0) / sampleRate) }
    }

    private func peakBand(_ bands: [Float]) -> Int {
        bands.enumerated().max { $0.element < $1.element }!.offset
    }

    func testOutputCountMatchesBandCount() {
        let a = SpectrumAnalyzer(fftSize: fftSize, bandCount: 8, sampleRate: sampleRate)
        XCTAssertEqual(a.bands(from: sine(1000)).count, 8)
    }

    func testSilenceIsAllZero() {
        let a = SpectrumAnalyzer(fftSize: fftSize, bandCount: 8, sampleRate: sampleRate)
        let bands = a.bands(from: [Float](repeating: 0, count: fftSize))
        for v in bands { XCTAssertEqual(v, 0, accuracy: 0.001) }
    }

    func testHighTonePeaksHigherBandThanLowTone() {
        let a = SpectrumAnalyzer(fftSize: fftSize, bandCount: 8, sampleRate: sampleRate)
        let lowPeak  = peakBand(a.bands(from: sine(200)))
        let highPeak = peakBand(a.bands(from: sine(6000)))
        XCTAssertLessThan(lowPeak, highPeak,
                          "A 6 kHz tone should peak in a higher band than a 200 Hz tone")
    }

    func testToneConcentratesEnergyInOneBand() {
        // A pure tone should make its peak band clearly dominate the average.
        let a = SpectrumAnalyzer(fftSize: fftSize, bandCount: 8, sampleRate: sampleRate)
        let bands = a.bands(from: sine(3000))
        let peak = bands.max()!
        let mean = bands.reduce(0, +) / Float(bands.count)
        XCTAssertGreaterThan(peak, mean,
                             "Pure tone energy should not be flat across bands")
    }

    func testOutputAlwaysInRange() {
        let a = SpectrumAnalyzer(fftSize: fftSize, bandCount: 8, sampleRate: sampleRate)
        for v in a.bands(from: sine(2500)) {
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
    }
}

import Accelerate

/// Computes a small log-spaced frequency spectrum from a window of audio
/// samples, for driving the equalizer bars. Real FFT via vDSP, grouped into
/// `bandCount` perceptually-spaced bands and normalized to [0, 1] per band.
final class SpectrumAnalyzer {
    let bandCount: Int
    private let fftSize: Int
    private let halfSize: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let window: [Float]
    private let bandRanges: [(lo: Int, hi: Int)]

    // Normalization range (power magnitude in dB) — tuned for 16 kHz voice.
    private let floorDB: Float = -90
    private let ceilDB: Float = -20

    init(fftSize: Int = 1024, bandCount: Int = 8, sampleRate: Float = 16_000) {
        self.fftSize = fftSize
        self.halfSize = fftSize / 2
        self.bandCount = bandCount
        self.log2n = vDSP_Length(log2(Float(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.window = vDSP.window(ofType: Float.self,
                                  usingSequence: .hanningDenormalized,
                                  count: fftSize, isHalfWindow: false)

        // Log-spaced band edges across bins [1, halfSize). Low frequencies get
        // narrower bands so the voice's fundamental/formants spread across bars
        // instead of piling into bin 0.
        let minBin = 1.0
        let maxBin = Double(fftSize / 2)
        var ranges: [(Int, Int)] = []
        for b in 0..<bandCount {
            let loFrac = Double(b) / Double(bandCount)
            let hiFrac = Double(b + 1) / Double(bandCount)
            let lo = Int((minBin * pow(maxBin / minBin, loFrac)).rounded())
            var hi = Int((minBin * pow(maxBin / minBin, hiFrac)).rounded())
            if hi <= lo { hi = lo + 1 }
            ranges.append((lo, min(hi, fftSize / 2)))
        }
        self.bandRanges = ranges
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Returns `bandCount` normalized [0, 1] band magnitudes for the most recent
    /// `fftSize` samples of `input` (zero-padded if shorter).
    func bands(from input: [Float]) -> [Float] {
        guard !input.isEmpty else { return [Float](repeating: 0, count: bandCount) }

        // Window the last fftSize samples.
        var windowed = [Float](repeating: 0, count: fftSize)
        let n = min(input.count, fftSize)
        let start = input.count - n
        for i in 0..<n { windowed[i] = input[start + i] * window[i] }

        var real = [Float](repeating: 0, count: halfSize)
        var imag = [Float](repeating: 0, count: halfSize)
        var magnitudes = [Float](repeating: 0, count: halfSize)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                // Pack the real signal into split-complex form (even→real, odd→imag).
                windowed.withUnsafeBufferPointer { wptr in
                    wptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { cptr in
                        vDSP_ctoz(cptr, 2, &split, 1, vDSP_Length(halfSize))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }

        // Group bins into bands (mean power), convert to dB, normalize.
        var out = [Float](repeating: 0, count: bandCount)
        for (b, range) in bandRanges.enumerated() {
            var sum: Float = 0
            var count = 0
            for bin in range.lo..<range.hi where bin < halfSize {
                sum += magnitudes[bin]
                count += 1
            }
            let meanPower = count > 0 ? sum / Float(count) : 0
            let db = 10 * log10(max(meanPower, 1e-12))
            out[b] = min(max((db - floorDB) / (ceilDB - floorDB), 0), 1)
        }
        return out
    }
}

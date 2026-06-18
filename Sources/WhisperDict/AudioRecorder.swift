import AVFoundation
import QuartzCore

final class AudioRecorder {
    private var engine = AVAudioEngine()
    private var samples: [Float] = []
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    /// Called on the main thread with the raw RMS of each buffer (throttled).
    var onLevel: ((Float) -> Void)?
    private var lastLevelEmit: CFTimeInterval = 0

    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    func start() throws {
        engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let conv = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw NSError(domain: "AudioRecorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "AVAudioConverter init failed"])
        }
        self.converter = conv
        lock.lock(); samples.removeAll(); lock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer, format: inputFormat)
        }
        engine.prepare()
        try engine.start()
    }

    private func process(buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        guard let converter else { return }
        let ratio = outputFormat.sampleRate / format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var inputProvided = false
        let status = converter.convert(to: out, error: nil) { _, statusPtr in
            if inputProvided { statusPtr.pointee = .noDataNow; return nil }
            inputProvided = true
            statusPtr.pointee = .haveData
            return buffer
        }
        guard status != .error, let channelData = out.floatChannelData else { return }
        let chunk = Array(UnsafeBufferPointer(start: channelData[0], count: Int(out.frameLength)))
        lock.lock(); samples.append(contentsOf: chunk); lock.unlock()

        // Voice-level metering for the recording overlay. Cheap math here is
        // fine on the audio thread; the UI hop + throttle happen below.
        var sumSquares: Float = 0
        for s in chunk { sumSquares += s * s }
        let rms = chunk.isEmpty ? 0 : (sumSquares / Float(chunk.count)).squareRoot()

        let now = CACurrentMediaTime()
        if now - lastLevelEmit >= 0.05 {   // ~20 fps
            lastLevelEmit = now
            DispatchQueue.main.async { [weak self] in self?.onLevel?(rms) }
        }
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        onLevel = nil
        lastLevelEmit = 0
        lock.lock()
        defer { lock.unlock() }
        let maxSamples = 16_000 * 30  // 30 seconds at 16 kHz
        let result = samples.count > maxSamples ? Array(samples.suffix(maxSamples)) : samples
        samples.removeAll()
        return result
    }
}

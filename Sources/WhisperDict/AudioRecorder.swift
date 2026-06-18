import AVFoundation
import QuartzCore

final class AudioRecorder {
    private let engine = AVAudioEngine()   // reused across recordings (warm-start)
    private var isSetUp = false
    private var samples: [Float] = []
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    /// Called on the main thread with normalized per-band spectrum magnitudes
    /// (throttled). Drives the equalizer bars in the recording overlay.
    var onBands: (([Float]) -> Void)?
    private let analyzer = SpectrumAnalyzer()
    private let fftSize = 1024
    /// Rolling window of the most recent samples, touched only on the audio
    /// thread (the tap callback is its sole reader/writer).
    private var recent: [Float] = []
    private var lastBandsEmit: CFTimeInterval = 0
    private var configObserver: NSObjectProtocol?

    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    init() {
        // The audio graph is built for a fixed input format. If the input device
        // or its format changes, rebuild the tap/converter so we don't feed the
        // converter mismatched buffers (which would yield empty transcriptions).
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in self?.rebuild() }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    /// Pre-builds the audio graph and warms the engine so the first recording
    /// captures from the very first word. Safe to call once the app is ready.
    func prepare() {
        setUpIfNeeded()
        if isSetUp { engine.prepare() }
    }

    private func setUpIfNeeded() {
        guard !isSetUp else { return }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              let conv = AVAudioConverter(from: inputFormat, to: outputFormat) else { return }
        converter = conv
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer, format: inputFormat)
        }
        isSetUp = true
    }

    private func rebuild() {
        let wasRunning = engine.isRunning
        if isSetUp { engine.inputNode.removeTap(onBus: 0) }
        engine.stop()
        converter = nil
        isSetUp = false
        setUpIfNeeded()
        if wasRunning, isSetUp {
            engine.prepare()
            try? engine.start()
        }
    }

    func start() throws {
        setUpIfNeeded()
        guard isSetUp else {
            throw NSError(domain: "AudioRecorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Audio input unavailable"])
        }
        lock.lock(); samples.removeAll(); lock.unlock()
        recent.removeAll(keepingCapacity: true)
        lastBandsEmit = 0
        // The engine is only stopped via pause() between recordings, so a fresh
        // start just resumes the already-warm hardware route — no cold-start gap
        // that would clip the first words.
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
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

        // Spectrum metering for the recording overlay. The FFT runs on the audio
        // thread (cheap at 1024 pts, only when the throttle fires); the UI hop
        // happens on the main thread below. `recent` is audio-thread-only state.
        recent.append(contentsOf: chunk)
        if recent.count > fftSize { recent.removeFirst(recent.count - fftSize) }

        let now = CACurrentMediaTime()
        if now - lastBandsEmit >= 0.05 {   // ~20 fps
            lastBandsEmit = now
            let bands = analyzer.bands(from: recent)
            DispatchQueue.main.async { [weak self] in self?.onBands?(bands) }
        }
    }

    func stop() -> [Float] {
        // pause() (not stop()) keeps render resources allocated so the next
        // start() resumes instantly, while still releasing the mic (indicator
        // off) between dictations.
        engine.pause()
        onBands = nil  // paired with AppDelegate.startRecording(); cleared so no stale callbacks fire between sessions
        lock.lock()
        defer { lock.unlock() }
        let maxSamples = 16_000 * 30  // 30 seconds at 16 kHz
        let result = samples.count > maxSamples ? Array(samples.suffix(maxSamples)) : samples
        samples.removeAll()
        return result
    }
}

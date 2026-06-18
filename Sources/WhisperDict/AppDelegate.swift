import Cocoa
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!
    private var hotkey:  HotkeyManager!
    private let recorder    = AudioRecorder()
    private let transcriber = Transcriber()
    private let overlay     = RecordingOverlayController()
    private var isBusy  = false
    private var isReady = false

    private var prefsWindow: PreferencesWindowController?
    private var onboarding:  OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let opts = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        menuBar = MenuBarController()
        menuBar.configure(onPreferences: { [weak self] in self?.showPreferences() })

        hotkey = HotkeyManager(
            onPress:   { [weak self] in self?.startRecording()    },
            onRelease: { [weak self] in self?.stopAndTranscribe() }
        )
        hotkey.start()

        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged),
            name: .preferencesChanged, object: nil
        )

        if UserSettings.shared.hasLaunchedBefore {
            startWarmup()
        } else {
            showOnboarding()
        }
    }

    // MARK: - Warmup

    func startWarmup() {
        isReady = false
        menuBar.setStatus("Loading model…", icon: "⏳")
        onboarding?.setModelStatus(loading: true, ready: false)

        Task {
            do {
                try await transcriber.warmup()
                isReady = true
                menuBar.setStatus("Hold Right-Option to dictate")
                onboarding?.setModelStatus(loading: false, ready: true)
            } catch {
                menuBar.setStatus("Model error: \(error.localizedDescription)", icon: "⚠️")
                onboarding?.setModelStatus(loading: false, ready: false)
            }
        }
    }

    @objc private func preferencesChanged() {
        Task { await transcriber.reset() }
        startWarmup()
    }

    // MARK: - Recording

    private func startRecording() {
        guard isReady, !isBusy else { return }
        isBusy = true
        do {
            try recorder.start()
            recorder.onBands = { [weak self] bands in self?.overlay.setBands(bands) }
            overlay.show()
            menuBar.setStatus("Recording…", icon: "🔴")
        } catch {
            menuBar.setStatus("Mic error: \(error.localizedDescription)", icon: "⚠️")
            isBusy = false
            overlay.hide()
        }
    }

    private func stopAndTranscribe() {
        guard isBusy else { return }
        let audio = recorder.stop()
        overlay.enterSpinner()
        menuBar.setStatus("Transcribing…", icon: "⏳")

        Task.detached { [self] in
            let transcriptionTask = Task<String, Never> {
                await self.transcriber.transcribe(audio)
            }
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                transcriptionTask.cancel()
            }
            let text = await transcriptionTask.value
            timeoutTask.cancel()
            await MainActor.run { [self] in
                if !text.isEmpty {
                    let pasted = PasteHelper.paste(text)
                    HistoryManager.shared.add(text)
                    self.menuBar.refreshHistory()
                    if pasted {
                        let preview = text.count <= 48 ? text : String(text.prefix(45)) + "…"
                        self.menuBar.setStatus("✓ \(preview)")
                    } else {
                        self.menuBar.setStatus("⚠️ Enable Accessibility to auto-paste (text copied)", icon: "⚠️")
                    }
                } else {
                    self.menuBar.setStatus("Hold Right-Option to dictate")
                }
                self.isBusy = false
                self.overlay.hide()
            }
        }
    }

    // MARK: - Windows

    private func showOnboarding() {
        let vc = OnboardingWindowController(onReady: { [weak self] in
            self?.startWarmup()
        })
        self.onboarding = vc
        vc.show()
        startWarmup()
    }

    private func showPreferences() {
        if prefsWindow == nil { prefsWindow = PreferencesWindowController() }
        prefsWindow?.show()
    }
}

import Cocoa
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!
    private var hotkey:  HotkeyManager!
    private let recorder    = AudioRecorder()
    private let transcriber = Transcriber()
    private let enhancer    = Enhancer()
    private let overlay     = RecordingOverlayController()
    private var isBusy  = false
    private var isReady = false
    private var pendingBundleID: String?   // frontmost app captured at record time

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
        NotificationCenter.default.addObserver(
            self, selector: #selector(enhanceSettingsChanged),
            name: .enhanceSettingsChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(hotkeyChanged),
            name: .hotkeyChanged, object: nil
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
                recorder.prepare()   // warm the audio graph so the first words aren't clipped
                if UserSettings.shared.enhanceEnabled, Enhancer.isAvailable {
                    Task { await self.enhancer.warmup() }
                }
                menuBar.setStatus(dictateHint)
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

    @objc private func enhanceSettingsChanged() {
        if UserSettings.shared.enhanceEnabled, Enhancer.isAvailable {
            Task { await enhancer.warmup() }
        }
    }

    @objc private func hotkeyChanged() {
        hotkey.restart()
        menuBar.setStatus(dictateHint)
    }

    /// "Hold Right Option (⌥) to dictate" — reflects the chosen push-to-talk key.
    private var dictateHint: String {
        "Hold \(HotkeyManager.preset(for: UserSettings.shared.hotkeyKeyCode).label) to dictate"
    }

    // MARK: - Recording

    private func startRecording() {
        guard isReady, !isBusy else { return }
        isBusy = true
        // Capture the target app now, before our overlay appears.
        pendingBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
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

        let bundleID = pendingBundleID

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

            // Optional on-device cleanup. Races the LLM against a 10s timeout;
            // on timeout or any failure it falls back to the raw transcript.
            var output = text
            if !text.isEmpty, UserSettings.shared.enhanceEnabled, Enhancer.isAvailable {
                await MainActor.run { [self] in self.menuBar.setStatus("Enhancing…", icon: "✨") }
                let userStyle = EnhanceStyle(rawValue: UserSettings.shared.enhanceStyle) ?? .faithful
                let style = UserSettings.shared.perAppContextEnabled
                    ? AppContext.resolvedStyle(userDefault: userStyle, bundleID: bundleID)
                    : userStyle
                let vocab = UserSettings.shared.vocabularyTerms
                let profile = UserSettings.shared.profile
                output = await withTaskGroup(of: String?.self) { group in
                    group.addTask { await self.enhancer.enhance(text, style: style, vocabulary: vocab, profile: profile) }
                    group.addTask { try? await Task.sleep(nanoseconds: 10_000_000_000); return nil }
                    let first = await group.next() ?? nil
                    group.cancelAll()
                    return first ?? text
                }
            }

            // Snippet expansion runs after Enhance (independent of Apple
            // Intelligence) so the model can't reword a canned expansion.
            output = SnippetExpander.expand(output, snippets: UserSettings.shared.snippets)
            let finalText = output   // immutable capture across the actor hop

            await MainActor.run { [self] in
                if !finalText.isEmpty {
                    let pasted = PasteHelper.paste(finalText)
                    HistoryManager.shared.add(finalText)
                    UserSettings.shared.totalDictations += 1
                    UserSettings.shared.totalWords += finalText.split(whereSeparator: \.isWhitespace).count
                    self.menuBar.refreshHistory()
                    if pasted {
                        let preview = finalText.count <= 48 ? finalText : String(finalText.prefix(45)) + "…"
                        self.menuBar.setStatus("✓ \(preview)")
                    } else {
                        self.menuBar.setStatus("⚠️ Enable Accessibility to auto-paste (text copied)", icon: "⚠️")
                    }
                } else {
                    self.menuBar.setStatus(self.dictateHint)
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

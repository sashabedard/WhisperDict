import Cocoa
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!
    private var hotkey:  HotkeyManager!
    private var commandHotkey: HotkeyManager!
    private var lastDictation = ""
    private var commandSelection: String?
    private var savedClipboard: String?
    private var commandUsedClipboard = false
    private let recorder    = AudioRecorder()
    private let transcriber = Transcriber()
    private let enhancer    = Enhancer()
    private let overlay     = RecordingOverlayController()
    private enum Activity { case idle, dictation, command }
    private var activity: Activity = .idle
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

        commandHotkey = HotkeyManager(
            keyCodeProvider: { UserSettings.shared.commandHotkeyKeyCode },
            onPress:   { [weak self] in self?.startCommand() },
            onRelease: { [weak self] in self?.stopAndRunCommand() }
        )
        commandHotkey.start()

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
        NotificationCenter.default.addObserver(
            self, selector: #selector(commandHotkeyChanged),
            name: .commandHotkeyChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(inputDeviceChanged),
            name: .inputDeviceChanged, object: nil
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

    @objc private func commandHotkeyChanged() {
        commandHotkey.restart()
    }

    @objc private func inputDeviceChanged() {
        recorder.setInputDevice()
    }

    /// "Hold Right Option (⌥) to dictate" — reflects the chosen push-to-talk key.
    private var dictateHint: String {
        "Hold \(HotkeyManager.preset(for: UserSettings.shared.hotkeyKeyCode).label) to dictate"
    }

    // MARK: - Recording

    private func startRecording() {
        guard isReady, !isBusy else { return }
        isBusy = true
        activity = .dictation
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
            activity = .idle
            overlay.hide()
        }
    }

    private func stopAndTranscribe() {
        guard activity == .dictation else { return }
        let audio = recorder.stop()
        overlay.enterSpinner()
        menuBar.setStatus("Transcribing…", icon: "⏳")

        let bundleID = pendingBundleID

        Task.detached { [self] in
            let transcriptionTask = Task<Transcription, Never> {
                await self.transcriber.transcribe(audio)
            }
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                transcriptionTask.cancel()
            }
            let transcription = await transcriptionTask.value
            timeoutTask.cancel()
            let text = transcription.text

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
                let formatLists = AppContext.supportsRichLists(bundleID: bundleID)
                output = await withTaskGroup(of: String?.self) { group in
                    group.addTask { await self.enhancer.enhance(text, style: style, vocabulary: vocab, profile: profile, formatLists: formatLists) }
                    group.addTask { try? await Task.sleep(nanoseconds: 10_000_000_000); return nil }
                    let first = await group.next() ?? nil
                    group.cancelAll()
                    return first ?? text
                }
            } else if !text.isEmpty {
                // Enhance is off/unavailable: guarantee fillers are still removed.
                output = TextCleanup.stripFillers(text, language: UserSettings.shared.language)
            }

            // Snippet expansion runs after Enhance (independent of Apple
            // Intelligence) so the model can't reword a canned expansion.
            output = SnippetExpander.expand(output, snippets: UserSettings.shared.snippets)
            let finalText = output   // immutable capture across the actor hop

            await MainActor.run { [self] in
                if !finalText.isEmpty {
                    let pasted = PasteHelper.paste(finalText)
                    HistoryManager.shared.add(finalText)
                    StatsStore.record(
                        words: finalText.split(whereSeparator: \.isWhitespace).count,
                        bundleID: bundleID,
                        seconds: Double(audio.count) / 16_000,
                        language: transcription.language)
                    self.menuBar.refreshHistory()
                    if pasted {
                        self.lastDictation = finalText
                        let preview = finalText.count <= 48 ? finalText : String(finalText.prefix(45)) + "…"
                        self.menuBar.setStatus("✓ \(preview)")
                    } else {
                        self.menuBar.setStatus("⚠️ Enable Accessibility to auto-paste (text copied)", icon: "⚠️")
                    }
                } else {
                    self.menuBar.setStatus(self.dictateHint)
                }
                self.isBusy = false
                self.activity = .idle
                self.overlay.hide()
            }
        }
    }

    // MARK: - Command mode

    private func startCommand() {
        // Inert if command mode is unavailable or shares the dictation key.
        guard UserSettings.shared.commandHotkeyKeyCode != UserSettings.shared.hotkeyKeyCode else { return }
        guard isReady, !isBusy, Enhancer.isAvailable else { return }
        isBusy = true
        activity = .command
        // Prefer the Accessibility API (deterministic, no clipboard). Fall back to a
        // synthetic ⌘C copy only when AX can't read the selection (e.g. Electron apps).
        if let sel = TextReplacer.focusedSelection() {
            commandSelection = sel
            savedClipboard = nil
            commandUsedClipboard = false
        } else {
            savedClipboard = NSPasteboard.general.string(forType: .string)
            commandSelection = PasteHelper.copySelection()
            commandUsedClipboard = true
        }
        do {
            try recorder.start()
            recorder.onBands = { [weak self] bands in self?.overlay.setBands(bands) }
            overlay.show()
            menuBar.setStatus("Command…", icon: "🪄")
        } catch {
            menuBar.setStatus("Mic error: \(error.localizedDescription)", icon: "⚠️")
            isBusy = false
            activity = .idle
            overlay.hide()
        }
    }

    private func stopAndRunCommand() {
        guard activity == .command else { return }
        let audio = recorder.stop()
        overlay.enterSpinner()
        menuBar.setStatus("Running command…", icon: "✨")

        let selection = commandSelection
        let fallback = lastDictation
        let savedClip = savedClipboard

        Task.detached { [self] in
            let instruction = await self.transcriber.transcribe(audio).text
            let target = (selection?.isEmpty == false) ? selection! : fallback

            guard !instruction.isEmpty, !target.isEmpty else {
                await MainActor.run { [self] in
                    self.menuBar.setStatus(target.isEmpty ? "Select text first" : self.dictateHint)
                    self.isBusy = false
                    self.activity = .idle
                    self.overlay.hide()
                }
                return
            }

            let result = await self.enhancer.runCommand(instruction: instruction, on: target)

            await MainActor.run { [self] in
                // Deterministic AX replacement first; fall back to ⌘V paste.
                var landed = TextReplacer.replaceFocusedSelection(with: result)
                if !landed {
                    // The clipboard to restore after the synthetic paste: on the ⌘C
                    // capture path the user's original was saved before ⌘C; on the AX
                    // capture path the clipboard was untouched, so snapshot it now
                    // (before PasteHelper.paste overwrites it).
                    let toRestore = self.commandUsedClipboard ? savedClip : NSPasteboard.general.string(forType: .string)
                    landed = PasteHelper.paste(result)
                    if landed, let toRestore {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(toRestore, forType: .string)
                        }
                    }
                }
                if landed {
                    self.lastDictation = result
                    StatsStore.recordCommand(instruction: instruction)
                    self.menuBar.setStatus("✓ edited")
                } else {
                    self.menuBar.setStatus("⚠️ Enable Accessibility to auto-paste (text copied)", icon: "⚠️")
                }
                self.isBusy = false
                self.activity = .idle
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

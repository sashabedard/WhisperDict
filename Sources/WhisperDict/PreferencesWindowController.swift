import Cocoa

extension Notification.Name {
    static let preferencesChanged = Notification.Name("preferencesChanged")
    static let enhanceSettingsChanged = Notification.Name("enhanceSettingsChanged")
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
}

private let languages: [(code: String, label: String)] = [
    ("auto", "Auto (Français + English)"),
    ("fr",   "Français"),
    ("en",   "English"),
    ("es",   "Español"),
    ("de",   "Deutsch"),
    ("it",   "Italiano"),
    ("pt",   "Português"),
    ("ja",   "日本語"),
    ("zh",   "中文"),
]

private let models: [(id: String, label: String)] = [
    ("openai_whisper-large-v3_turbo_954MB",  "Large v3 Turbo — 954 MB  (recommended)"),
    ("openai_whisper-large-v3_947MB",        "Large v3 — 947 MB"),
    ("distil-whisper_distil-large-v3_594MB", "Distil Large v3 — 594 MB"),
]

private let enhanceStyles: [(id: String, label: String)] = [
    ("faithful", "Faithful — clean only, keep my words"),
    ("polished", "Polished — tighten & rephrase"),
    ("email",    "Email — professional tone"),
]

/// One-line guidance shown under the model picker so a first-time user knows
/// which to pick. Distil is English-only — important for non-English users.
private let modelNotes: [String: String] = [
    "openai_whisper-large-v3_turbo_954MB":  "Multilingual and fast — recommended for most people.",
    "openai_whisper-large-v3_947MB":        "Multilingual, the most accurate, but slower.",
    "distil-whisper_distil-large-v3_594MB": "English only, but the fastest.",
]

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, NSTextViewDelegate {
    private let langPopup  = NSPopUpButton()
    private let modelPopup = NSPopUpButton()
    private let hotkeyPopup = NSPopUpButton()
    private let modelCaption = NSTextField(wrappingLabelWithString: "")
    private let enhanceSwitch = NSSwitch()
    private let perAppSwitch   = NSSwitch()
    private let stylePopup    = NSPopUpButton()
    private let enhanceCaption = NSTextField(wrappingLabelWithString: "")
    private let vocabField    = NSTextField()
    private let profileField  = ProfileTextField()
    private let snippetsField = ProfileTextField()

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 760),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Settings"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.center()
        self.init(window: panel)
        panel.delegate = self
        panel.contentView = buildContent()
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - View

    private func buildContent() -> NSView {
        let bg = NSVisualEffectView()
        bg.material = .windowBackground
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.translatesAutoresizingMaskIntoConstraints = false

        // ── Header ─────────────────────────────────────────
        let appIcon = NSImageView()
        if let icon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
            appIcon.image = icon
        }
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        appIcon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        appIcon.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let title = NSTextField(labelWithString: "WhisperDict")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "Voice dictation, anywhere on your Mac.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        let header = NSStackView(views: [appIcon, titleStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14

        // ── Form rows ──────────────────────────────────────
        configurePopup(langPopup,
                       items: languages.map { $0.label },
                       selectedIndex: languages.firstIndex { $0.code == UserSettings.shared.language } ?? 0,
                       action: #selector(languageChanged))

        configurePopup(modelPopup,
                       items: models.map { $0.label },
                       selectedIndex: models.firstIndex { $0.id == UserSettings.shared.modelName } ?? 0,
                       action: #selector(modelChanged))

        modelCaption.font = .systemFont(ofSize: 11)
        modelCaption.textColor = .secondaryLabelColor
        modelCaption.stringValue = modelNote(for: UserSettings.shared.modelName)

        // Keep the caption visually attached under the model popup.
        let modelCol = NSStackView(views: [modelPopup, modelCaption])
        modelCol.orientation = .vertical
        modelCol.alignment = .leading
        modelCol.spacing = 4

        configurePopup(hotkeyPopup,
                       items: HotkeyManager.presets.map { $0.label },
                       selectedIndex: HotkeyManager.presets.firstIndex { $0.keyCode == UInt16(UserSettings.shared.hotkeyKeyCode) } ?? 0,
                       action: #selector(hotkeyPopupChanged))

        let card = makeCard(rows: [
            ("Shortcut", hotkeyPopup),
            ("Language", langPopup),
            ("Model",    modelCol),
        ])

        // ── Enhancement card ───────────────────────────────
        let available = Enhancer.isAvailable

        enhanceSwitch.state = (UserSettings.shared.enhanceEnabled && available) ? .on : .off
        enhanceSwitch.isEnabled = available
        enhanceSwitch.target = self
        enhanceSwitch.action = #selector(enhanceToggled)

        perAppSwitch.state = (UserSettings.shared.perAppContextEnabled && available) ? .on : .off
        perAppSwitch.isEnabled = available && UserSettings.shared.enhanceEnabled
        perAppSwitch.target = self
        perAppSwitch.action = #selector(perAppToggled)

        configurePopup(stylePopup,
                       items: enhanceStyles.map { $0.label },
                       selectedIndex: enhanceStyles.firstIndex { $0.id == UserSettings.shared.enhanceStyle } ?? 0,
                       action: #selector(styleChanged))
        stylePopup.isEnabled = available && UserSettings.shared.enhanceEnabled

        enhanceCaption.font = .systemFont(ofSize: 11)
        enhanceCaption.textColor = .secondaryLabelColor
        enhanceCaption.stringValue = available
            ? "Cleans up dictation on-device. With Auto style on, the style adapts to the app (email, code…) and this picker is the fallback."
            : "Requires macOS 26 and Apple Intelligence — enable it in System Settings → Apple Intelligence."

        let styleCol = NSStackView(views: [stylePopup, enhanceCaption])
        styleCol.orientation = .vertical
        styleCol.alignment = .leading
        styleCol.spacing = 4

        vocabField.stringValue = UserSettings.shared.vocabulary
        vocabField.placeholderString = "WhisperKit, Sasha Bédard, …"
        vocabField.isEnabled = available && UserSettings.shared.enhanceEnabled
        vocabField.delegate = self
        vocabField.controlSize = .large
        vocabField.font = .systemFont(ofSize: 13)
        vocabField.translatesAutoresizingMaskIntoConstraints = false

        profileField.stringValue = UserSettings.shared.profile
        profileField.setEnabled(available && UserSettings.shared.enhanceEnabled)
        profileField.textView.delegate = self
        profileField.heightAnchor.constraint(equalToConstant: 60).isActive = true

        let enhanceCard = makeCard(rows: [
            ("Enhance",    enhanceSwitch),
            ("Auto style", perAppSwitch),
            ("Style",      styleCol),
            ("Vocabulary", vocabField),
            ("About you",  profileField),
        ])

        // ── Snippets card (independent of Apple Intelligence) ──
        snippetsField.stringValue = UserSettings.shared.snippetsRaw
        snippetsField.textView.delegate = self
        snippetsField.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let snippetsCard = makeCard(rows: [("Snippets", snippetsField)])

        let snippetsHint = NSTextField(wrappingLabelWithString: "Spoken shortcuts, one per line:  trigger => expansion  (e.g.  my email => you@example.com)")
        snippetsHint.font = .systemFont(ofSize: 11)
        snippetsHint.textColor = .tertiaryLabelColor

        // ── Footnote ───────────────────────────────────────
        let footnote = NSTextField(wrappingLabelWithString: "Changes apply automatically. Switching the model triggers a one-time reload on the next recording.")
        footnote.font = .systemFont(ofSize: 11)
        footnote.textColor = .tertiaryLabelColor
        footnote.alignment = .left

        // ── Layout ─────────────────────────────────────────
        let stack = NSStackView(views: [header, card, enhanceCard, snippetsCard, snippetsHint, footnote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 22
        stack.edgeInsets = NSEdgeInsets(top: 36, left: 32, bottom: 28, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false

        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bg.topAnchor),
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bg.bottomAnchor),
            card.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -64),
            enhanceCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -64),
            snippetsCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -64),
            snippetsHint.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -64),
            footnote.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -64),
        ])
        return bg
    }

    private func configurePopup(_ popup: NSPopUpButton, items: [String], selectedIndex: Int, action: Selector) {
        popup.removeAllItems()
        popup.addItems(withTitles: items)
        popup.selectItem(at: selectedIndex)
        popup.target = self
        popup.action = action
        popup.controlSize = .large
        popup.font = .systemFont(ofSize: 13)
        popup.translatesAutoresizingMaskIntoConstraints = false
    }

    private func makeCard(rows: [(String, NSView)]) -> NSView {
        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 14
        grid.columnSpacing = 18

        for (label, control) in rows {
            let lbl = NSTextField(labelWithString: label)
            lbl.font = .systemFont(ofSize: 13, weight: .regular)
            lbl.textColor = .secondaryLabelColor
            lbl.alignment = .right
            grid.addRow(with: [lbl, control])
        }
        // Configure columns AFTER rows exist (NSGridView creates columns lazily)
        if grid.numberOfColumns >= 1 {
            grid.column(at: 0).xPlacement = .trailing
        }
        if grid.numberOfColumns >= 2 {
            grid.column(at: 1).xPlacement = .fill
        }

        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            grid.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
        ])
        return card
    }

    // MARK: - Actions

    @objc private func languageChanged() {
        UserSettings.shared.language = languages[langPopup.indexOfSelectedItem].code
        // No reload needed — Transcriber reads the language on every call.
    }

    @objc private func enhanceToggled() {
        let on = enhanceSwitch.state == .on
        UserSettings.shared.enhanceEnabled = on
        perAppSwitch.isEnabled = on && Enhancer.isAvailable
        stylePopup.isEnabled = on && Enhancer.isAvailable
        vocabField.isEnabled = on && Enhancer.isAvailable
        profileField.setEnabled(on && Enhancer.isAvailable)
        NotificationCenter.default.post(name: .enhanceSettingsChanged, object: nil)
    }

    @objc private func perAppToggled() {
        UserSettings.shared.perAppContextEnabled = perAppSwitch.state == .on
        NotificationCenter.default.post(name: .enhanceSettingsChanged, object: nil)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === vocabField else { return }
        UserSettings.shared.vocabulary = vocabField.stringValue
        NotificationCenter.default.post(name: .enhanceSettingsChanged, object: nil)
    }

    func textDidEndEditing(_ notification: Notification) {
        let tv = notification.object as? NSTextView
        if tv === profileField.textView {
            UserSettings.shared.profile = profileField.stringValue
            NotificationCenter.default.post(name: .enhanceSettingsChanged, object: nil)
        } else if tv === snippetsField.textView {
            UserSettings.shared.snippetsRaw = snippetsField.stringValue
        }
    }

    @objc private func styleChanged() {
        UserSettings.shared.enhanceStyle = enhanceStyles[stylePopup.indexOfSelectedItem].id
        NotificationCenter.default.post(name: .enhanceSettingsChanged, object: nil)
    }

    @objc private func hotkeyPopupChanged() {
        UserSettings.shared.hotkeyKeyCode = Int(HotkeyManager.presets[hotkeyPopup.indexOfSelectedItem].keyCode)
        NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
    }

    @objc private func modelChanged() {
        let newModel = models[modelPopup.indexOfSelectedItem].id
        modelCaption.stringValue = modelNote(for: newModel)
        guard newModel != UserSettings.shared.modelName else { return }
        UserSettings.shared.modelName = newModel
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    private func modelNote(for id: String) -> String {
        modelNotes[id] ?? ""
    }
}

// MARK: - CardView

@MainActor
private final class CardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
    }

    private func applyTheme() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill: NSColor = isDark
            ? NSColor.white.withAlphaComponent(0.05)
            : NSColor.black.withAlphaComponent(0.03)
        let stroke: NSColor = isDark
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.08)
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = stroke.cgColor
    }
}

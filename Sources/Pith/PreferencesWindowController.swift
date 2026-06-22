import Cocoa

extension Notification.Name {
    static let preferencesChanged = Notification.Name("preferencesChanged")
    static let enhanceSettingsChanged = Notification.Name("enhanceSettingsChanged")
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
    static let commandHotkeyChanged = Notification.Name("commandHotkeyChanged")
    static let inputDeviceChanged = Notification.Name("inputDeviceChanged")
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

private let enhanceBackends: [(id: String, label: String)] = [
    ("apple",  "Apple (on-device)"),
    ("openai", "Custom — OpenAI-compatible"),
]

/// Endpoint + suggested-model presets for the BYOK engine. "Custom…" is last
/// and leaves the fields free. `models` seed the editable model combo box.
private struct ByokProvider { let label: String; let endpoint: String; let models: [String] }
private let byokProviders: [ByokProvider] = [
    // Cheap small instruct models, all present in OpenRouter's ZDR endpoint list
    // (/api/v1/endpoints/zdr) — text cleanup doesn't need a big model. ZDR is
    // enforced automatically for OpenRouter (see OpenAICompatibleEnhanceBackend).
    ByokProvider(label: "OpenRouter", endpoint: "https://openrouter.ai/api/v1",
                 models: ["meta-llama/llama-3.1-8b-instruct", "mistralai/mistral-nemo",
                          "qwen/qwen-2.5-7b-instruct", "google/gemma-3-4b-it", "microsoft/phi-4"]),
    ByokProvider(label: "OpenAI", endpoint: "https://api.openai.com/v1",
                 models: ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini"]),
    ByokProvider(label: "Groq", endpoint: "https://api.groq.com/openai/v1",
                 models: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"]),
    ByokProvider(label: "Ollama (local)", endpoint: "http://localhost:11434/v1",
                 models: ["llama3.1", "llama3.2", "qwen2.5", "mistral"]),
    ByokProvider(label: "LM Studio (local)", endpoint: "http://localhost:1234/v1", models: []),
    ByokProvider(label: "Custom…", endpoint: "", models: []),
]

/// One-line guidance shown under the model picker so a first-time user knows
/// which to pick. Distil is English-only — important for non-English users.
private let modelNotes: [String: String] = [
    "openai_whisper-large-v3_turbo_954MB":  "Multilingual and fast — recommended for most people.",
    "openai_whisper-large-v3_947MB":        "Multilingual, the most accurate, but slower.",
    "distil-whisper_distil-large-v3_594MB": "English only, but the fastest.",
]

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, NSTextViewDelegate, NSComboBoxDelegate {
    private let langPopup  = NSPopUpButton()
    private let modelPopup = NSPopUpButton()
    private let hotkeyPopup = NSPopUpButton()
    private let commandHotkeyPopup = NSPopUpButton()
    private let commandHotkeyCaption = NSTextField(wrappingLabelWithString: "")
    private let inputPopup = NSPopUpButton()
    /// Parallel to the popup's items: UID per row; index 0 is "" (system default).
    private var inputDeviceUIDs: [String] = []
    private let modelCaption = NSTextField(wrappingLabelWithString: "")
    private let autoUpdateSwitch = NSSwitch()
    private let enhanceSwitch = NSSwitch()
    private let perAppSwitch   = NSSwitch()
    private let stylePopup    = NSPopUpButton()
    private let enhanceCaption = NSTextField(wrappingLabelWithString: "")
    private let vocabField    = NSTextField()
    private let profileField  = ProfileTextField()
    private let snippetsField = ProfileTextField()
    private let backendPopup  = NSPopUpButton()
    private let providerPopup = NSPopUpButton()
    private let endpointField = NSTextField()
    private let modelCombo    = NSComboBox()
    private let apiKeyField   = NSSecureTextField()
    private let testButton    = NSButton(title: "Test", target: nil, action: nil)
    private let byokNote      = NSTextField(wrappingLabelWithString: "")

    // MARK: Stats dashboard
    private let statsDashboard = StatsDashboardView()

    // MARK: Tab-shell state
    private let tabs = ["General", "Enhance", "Commands", "Snippets", "Stats"]
    private var tabButtons: [NSButton] = []
    private var contentContainer = NSView()
    private var selectedTab = 0
    private var tabViewCache: [Int: NSView] = [:]
    private var saveButton: NSButton?

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 460),
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

    func windowDidBecomeKey(_ notification: Notification) {
        let mic = inputItems()
        inputPopup.removeAllItems()
        inputPopup.addItems(withTitles: mic.titles)
        inputPopup.selectItem(at: mic.index)
        self.refreshStats()
    }

    private func refreshStats() {
        statsDashboard.refresh()
    }

    // MARK: - View

    private func buildContent() -> NSView {
        let bg = NSVisualEffectView()
        bg.material = .windowBackground
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.translatesAutoresizingMaskIntoConstraints = false

        // ── Sidebar ────────────────────────────────────────
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        tabButtons = tabs.enumerated().map { (i, title) in
            let btn = NSButton(title: title, target: self, action: #selector(tabClicked(_:)))
            btn.tag = i
            btn.bezelStyle = .recessed
            btn.setButtonType(.toggle)
            btn.state = i == 0 ? .on : .off
            btn.font = .systemFont(ofSize: 13)
            btn.translatesAutoresizingMaskIntoConstraints = false
            return btn
        }

        let sideStack = NSStackView(views: tabButtons)
        sideStack.orientation = .vertical
        sideStack.alignment = .leading
        sideStack.spacing = 2
        sideStack.edgeInsets = NSEdgeInsets(top: 52, left: 12, bottom: 16, right: 12)
        sideStack.translatesAutoresizingMaskIntoConstraints = false

        sidebar.addSubview(sideStack)
        NSLayoutConstraint.activate([
            sideStack.topAnchor.constraint(equalTo: sidebar.topAnchor),
            sideStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            sideStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sideStack.bottomAnchor.constraint(lessThanOrEqualTo: sidebar.bottomAnchor),
        ])
        for btn in tabButtons {
            btn.widthAnchor.constraint(equalTo: sideStack.widthAnchor, constant: -24).isActive = true
        }

        // ── Content container ──────────────────────────────
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        // ── Save button ────────────────────────────────────
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        saveButton = saveBtn

        // ── Layout ─────────────────────────────────────────
        bg.addSubview(sidebar)
        bg.addSubview(contentContainer)
        bg.addSubview(saveBtn)

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: bg.topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 140),

            contentContainer.topAnchor.constraint(equalTo: bg.topAnchor, constant: 52),
            contentContainer.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 24),
            contentContainer.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -24),
            contentContainer.bottomAnchor.constraint(equalTo: saveBtn.topAnchor, constant: -16),

            saveBtn.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -24),
            saveBtn.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -20),
        ])

        // Fixed content size so the window keeps the same dimensions on every tab
        // (otherwise it auto-sizes to each tab's content — wide for General's popups,
        // narrow for Enhance's switches).
        bg.widthAnchor.constraint(equalToConstant: 660).isActive = true
        bg.heightAnchor.constraint(equalToConstant: 540).isActive = true

        selectTab(0)
        return bg
    }

    @objc private func tabClicked(_ sender: NSButton) {
        selectTab(sender.tag)
    }

    private func selectTab(_ index: Int) {
        selectedTab = index
        for (i, btn) in tabButtons.enumerated() {
            btn.state = i == index ? .on : .off
        }
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        let tabView = cachedTab(index)
        tabView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            tabView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            tabView.bottomAnchor.constraint(lessThanOrEqualTo: contentContainer.bottomAnchor),
        ])
        if index == 4 { statsDashboard.refresh() }
    }

    private func cachedTab(_ index: Int) -> NSView {
        if let cached = tabViewCache[index] { return cached }
        let view: NSView
        switch index {
        case 0: view = buildGeneralTab()
        case 1: view = buildEnhanceTab()
        case 2: view = buildCommandsTab()
        case 3: view = buildSnippetsTab()
        case 4: view = buildStatsTab()
        default: view = NSView()
        }
        tabViewCache[index] = view
        return view
    }

    @objc private func saveClicked() {
        guard let save = saveButton else { return }
        save.title = "Saved ✓"
        save.isEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak save] in
            save?.title = "Save"
            save?.isEnabled = true
        }
    }

    // MARK: - Tab Builders

    private func buildGeneralTab() -> NSView {
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

        let modelCol = tabColumn(modelPopup, caption: modelCaption)

        configurePopup(hotkeyPopup,
                       items: HotkeyManager.presets.map { $0.label },
                       selectedIndex: HotkeyManager.presets.firstIndex { $0.keyCode == UInt16(UserSettings.shared.hotkeyKeyCode) } ?? 0,
                       action: #selector(hotkeyPopupChanged))

        let mic = inputItems()
        configurePopup(inputPopup,
                       items: mic.titles,
                       selectedIndex: mic.index,
                       action: #selector(inputDeviceChanged))

        autoUpdateSwitch.state = UserSettings.shared.autoCheckUpdates ? .on : .off
        autoUpdateSwitch.target = self
        autoUpdateSwitch.action = #selector(autoUpdateToggled)

        let updateCaption = NSTextField(wrappingLabelWithString:
            "Off by default. The only time Pith touches the network: an optional version check against GitHub — no data about you is sent.")
        updateCaption.font = .systemFont(ofSize: 11)
        updateCaption.textColor = .secondaryLabelColor

        let updateCol = NSStackView(views: [autoUpdateSwitch, updateCaption])
        updateCol.orientation = .vertical
        updateCol.alignment = .leading
        updateCol.spacing = 4
        updateCaption.widthAnchor.constraint(equalTo: updateCol.widthAnchor).isActive = true

        return makeCard(rows: [
            ("Shortcut",   hotkeyPopup),
            ("Language",   langPopup),
            ("Model",      modelCol),
            ("Microphone", inputPopup),
            ("Updates",    updateCol),
        ])
    }

    private func buildEnhanceTab() -> NSView {
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

        let styleCol = tabColumn(stylePopup, caption: enhanceCaption)

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
        if profileField.constraints.filter({ $0.firstAttribute == .height }).isEmpty {
            profileField.heightAnchor.constraint(equalToConstant: 60).isActive = true
        }

        configurePopup(backendPopup,
                       items: enhanceBackends.map { $0.label },
                       selectedIndex: enhanceBackends.firstIndex { $0.id == UserSettings.shared.enhanceBackend } ?? 0,
                       action: #selector(backendChanged))

        configurePopup(providerPopup,
                       items: byokProviders.map { $0.label },
                       selectedIndex: selectedProviderIndex(),
                       action: #selector(providerChanged))

        endpointField.stringValue = UserSettings.shared.openAIEndpoint
        endpointField.placeholderString = "https://openrouter.ai/api/v1"
        endpointField.delegate = self
        endpointField.controlSize = .large
        endpointField.font = .systemFont(ofSize: 13)
        endpointField.translatesAutoresizingMaskIntoConstraints = false

        modelCombo.isEditable = true
        modelCombo.completes = true
        modelCombo.delegate = self
        modelCombo.controlSize = .large
        modelCombo.font = .systemFont(ofSize: 13)
        modelCombo.placeholderString = "openai/gpt-4o-mini"
        modelCombo.removeAllItems()
        modelCombo.addItems(withObjectValues: byokProviders[selectedProviderIndex()].models)
        modelCombo.stringValue = UserSettings.shared.openAIModel
        modelCombo.translatesAutoresizingMaskIntoConstraints = false

        apiKeyField.stringValue = KeychainStore().get("apiKey") ?? ""
        apiKeyField.placeholderString = "API key (optional for local servers)"
        apiKeyField.delegate = self
        apiKeyField.controlSize = .large
        apiKeyField.font = .systemFont(ofSize: 13)
        apiKeyField.translatesAutoresizingMaskIntoConstraints = false

        testButton.target = self
        testButton.action = #selector(testByokClicked)
        testButton.bezelStyle = .rounded
        testButton.translatesAutoresizingMaskIntoConstraints = false

        byokNote.stringValue = "⚠️ Your transcripts are sent to this endpoint. On-device privacy applies only to the Apple option."
        byokNote.font = .systemFont(ofSize: 11)
        byokNote.textColor = .secondaryLabelColor
        byokNote.lineBreakMode = .byWordWrapping
        byokNote.maximumNumberOfLines = 0
        byokNote.preferredMaxLayoutWidth = 360
        byokNote.translatesAutoresizingMaskIntoConstraints = false
        updateByokNote()

        // Uniform width: every text input / popup stretches to fill the row, so
        // they all line up at the same (generous) width regardless of content.
        for control in [stylePopup, backendPopup, providerPopup,
                        endpointField, modelCombo, apiKeyField, vocabField] as [NSView] {
            control.setContentHuggingPriority(.defaultLow, for: .horizontal)
            control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        var rows: [(String, NSView)] = [
            ("Enhance",    leadingControl(enhanceSwitch)),
            ("Auto style", leadingControl(perAppSwitch)),
            ("Style",      styleCol),
            ("Vocabulary", vocabField),
            ("About you",  profileField),
            ("Engine",     backendPopup),
        ]
        if UserSettings.shared.enhanceBackend == "openai" {
            rows += [
                ("Provider", providerPopup),
                ("Endpoint", endpointField),
                ("Model",    modelCombo),
                ("API key",  apiKeyField),
                ("",         leadingControl(testButton)),
                ("",         byokNote),
            ]
        }
        return makeCard(rows: rows)
    }

    private func buildCommandsTab() -> NSView {
        configurePopup(commandHotkeyPopup,
                       items: HotkeyManager.presets.map { $0.label },
                       selectedIndex: HotkeyManager.presets.firstIndex { $0.keyCode == UInt16(UserSettings.shared.commandHotkeyKeyCode) } ?? 1,
                       action: #selector(commandHotkeyPopupChanged))

        commandHotkeyCaption.font = .systemFont(ofSize: 11)
        commandHotkeyCaption.textColor = .secondaryLabelColor
        commandHotkeyCaption.stringValue = commandKeyNote()

        let commandCol = tabColumn(commandHotkeyPopup, caption: commandHotkeyCaption)

        let card = makeCard(rows: [
            ("Command key", commandCol),
        ])

        let examplesTitle = NSTextField(labelWithString: "Try saying, while holding the command key with text selected:")
        examplesTitle.font = .systemFont(ofSize: 11)
        examplesTitle.textColor = .secondaryLabelColor

        let examples = NSTextField(wrappingLabelWithString:
            "\u{201C}rends \u{00E7}a plus formel\u{201D}   \u{00B7}   \u{201C}traduis en anglais\u{201D}   \u{00B7}   \u{201C}corrige l\u{2019}orthographe\u{201D}\n\u{201C}r\u{00E9}sume\u{201D}   \u{00B7}   \u{201C}rends \u{00E7}a plus court\u{201D}   \u{00B7}   \u{201C}make this a bullet list\u{201D}")
        examples.font = .systemFont(ofSize: 12)
        examples.textColor = .labelColor

        let note = NSTextField(wrappingLabelWithString:
            "Works best in native apps (TextEdit, Mail, Notes). In some web/Electron apps (Slack, VS Code) the edit is pasted rather than replaced.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor

        let examplesCard = makeCard(rows: [("Examples", examples)])

        let stack = NSStackView(views: [card, examplesTitle, examplesCard, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        for v in stack.arrangedSubviews {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func buildSnippetsTab() -> NSView {
        snippetsField.stringValue = UserSettings.shared.snippetsRaw
        snippetsField.textView.delegate = self
        if snippetsField.constraints.filter({ $0.firstAttribute == .height }).isEmpty {
            snippetsField.heightAnchor.constraint(equalToConstant: 120).isActive = true
        }

        let card = makeCard(rows: [("Snippets", snippetsField)])

        let hint = NSTextField(wrappingLabelWithString: "Spoken shortcuts, one per line:  trigger => expansion  (e.g.  my email => you@example.com)")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [card, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        hint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func buildStatsTab() -> NSView {
        statsDashboard.refresh()
        statsDashboard.translatesAutoresizingMaskIntoConstraints = false
        return statsDashboard
    }

    /// Stacks a popup above a caption label for use as a card control.
    private func tabColumn(_ control: NSView, caption: NSTextField) -> NSView {
        let col = NSStackView(views: [control, caption])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 4
        col.translatesAutoresizingMaskIntoConstraints = false
        caption.widthAnchor.constraint(equalTo: col.widthAnchor).isActive = true
        return col
    }

    // MARK: - Helpers

    /// Recomputes the device list and the parallel `inputDeviceUIDs`, returning
    /// the popup titles and the index matching the saved UID (0 = system default).
    private func inputItems() -> (titles: [String], index: Int) {
        let devices = AudioDevices.inputDevices()
        inputDeviceUIDs = [""] + devices.map { $0.uid }
        let titles = ["System Default (follow macOS)"] + devices.map { $0.name }
        let index = inputDeviceUIDs.firstIndex(of: UserSettings.shared.inputDeviceUID) ?? 0
        return (titles, index)
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

    private static let labelColumnWidth: CGFloat = 96

    /// Wrap a control that shouldn't stretch (switch, button) so it stays its
    /// natural size at the leading edge — a trailing low-hugging spacer eats the
    /// rest of the row width, instead of the control being centered in a
    /// full-width slot.
    private func leadingControl(_ control: NSView) -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [control, spacer])
        row.orientation = .horizontal
        row.spacing = 0
        row.alignment = .centerY
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeCard(rows: [(String, NSView)]) -> NSView {
        let col = NSStackView()
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 14
        col.translatesAutoresizingMaskIntoConstraints = false

        var rowStacks: [NSStackView] = []
        for (label, control) in rows {
            let lbl = NSTextField(labelWithString: label)
            lbl.font = .systemFont(ofSize: 13, weight: .regular)
            lbl.textColor = .secondaryLabelColor
            lbl.alignment = .right
            lbl.translatesAutoresizingMaskIntoConstraints = false
            lbl.setContentHuggingPriority(.required, for: .horizontal)
            lbl.setContentCompressionResistancePriority(.required, for: .horizontal)
            lbl.widthAnchor.constraint(equalToConstant: Self.labelColumnWidth).isActive = true

            // Fixed-width label + control that fills the rest. Controls with low
            // horizontal hugging (popups, text fields, the profile field) stretch;
            // switches keep their natural size next to the label.
            let row = NSStackView(views: [lbl, control])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 14
            row.distribution = .fill
            row.translatesAutoresizingMaskIntoConstraints = false
            col.addArrangedSubview(row)
            rowStacks.append(row)
        }

        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(col)
        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            col.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            col.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            col.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
        ])
        for row in rowStacks {
            row.widthAnchor.constraint(equalTo: col.widthAnchor).isActive = true
        }
        return card
    }

    // MARK: - Actions

    @objc private func languageChanged() {
        UserSettings.shared.language = languages[langPopup.indexOfSelectedItem].code
        // No reload needed — Transcriber reads the language on every call.
    }

    @objc private func autoUpdateToggled() {
        UserSettings.shared.autoCheckUpdates = autoUpdateSwitch.state == .on
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
        guard let field = obj.object as? NSTextField else { return }
        if field === vocabField {
            UserSettings.shared.vocabulary = vocabField.stringValue
            NotificationCenter.default.post(name: .enhanceSettingsChanged, object: nil)
        } else if field === endpointField {
            UserSettings.shared.openAIEndpoint = endpointField.stringValue
            updateByokNote()
        } else if field === modelCombo {
            UserSettings.shared.openAIModel = modelCombo.stringValue
        } else if field === apiKeyField {
            KeychainStore().set(apiKeyField.stringValue, account: "apiKey")
        }
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

    @objc private func backendChanged() {
        UserSettings.shared.enhanceBackend = enhanceBackends[backendPopup.indexOfSelectedItem].id
        tabViewCache[1] = nil
        selectTab(1)
    }

    /// The byokProviders index whose endpoint matches the saved one, else the
    /// "Custom…" row (last).
    private func selectedProviderIndex() -> Int {
        let saved = UserSettings.shared.openAIEndpoint
        return byokProviders.firstIndex { !$0.endpoint.isEmpty && $0.endpoint == saved } ?? (byokProviders.count - 1)
    }

    @objc private func providerChanged() {
        let p = byokProviders[providerPopup.indexOfSelectedItem]
        guard p.label != "Custom…" else {
            modelCombo.removeAllItems()    // free entry; keep whatever's typed
            updateByokNote()
            return
        }
        endpointField.stringValue = p.endpoint
        UserSettings.shared.openAIEndpoint = p.endpoint
        modelCombo.removeAllItems()
        modelCombo.addItems(withObjectValues: p.models)
        // Keep the current model if it's valid for this provider, else default to
        // the first suggestion.
        if !p.models.contains(modelCombo.stringValue) {
            let m = p.models.first ?? ""
            modelCombo.stringValue = m
            UserSettings.shared.openAIModel = m
        }
        updateByokNote()
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        guard (notification.object as? NSComboBox) === modelCombo,
              let value = modelCombo.objectValueOfSelectedItem as? String else { return }
        UserSettings.shared.openAIModel = value
    }

    private func updateByokNote() {
        let endpoint = UserSettings.shared.openAIEndpoint
        let remote = !endpoint.isEmpty && !Endpoint.isLocal(endpoint)
        byokNote.isHidden = !(UserSettings.shared.enhanceBackend == "openai" && remote)
        if endpoint.lowercased().contains("openrouter.ai") {
            byokNote.stringValue = "🔒 Sent to OpenRouter with Zero Data Retention enforced — processed but never stored. (It still leaves your Mac.)"
        } else {
            byokNote.stringValue = "⚠️ Your transcripts are sent to this endpoint. On-device privacy applies only to the Apple option."
        }
    }

    @objc private func testByokClicked() {
        testButton.isEnabled = false
        testButton.title = "Testing…"
        let backend = OpenAICompatibleEnhanceBackend(endpoint: endpointField.stringValue,
                                                     model: modelCombo.stringValue,
                                                     apiKey: apiKeyField.stringValue)
        Task { @MainActor in
            let ok = await backend.enhance("ping", style: .faithful, vocabulary: [], profile: "", formatLists: false) != nil
            self.testButton.title = ok ? "✓ Connected" : "✗ Failed"
            self.testButton.isEnabled = true
        }
    }

    @objc private func hotkeyPopupChanged() {
        UserSettings.shared.hotkeyKeyCode = Int(HotkeyManager.presets[hotkeyPopup.indexOfSelectedItem].keyCode)
        NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
    }

    private func commandKeyNote() -> String {
        if !Enhancer.isAvailable {
            return "Voice commands need Apple Intelligence. Hold this key, select text, and speak an edit (e.g. \u{201C}make this formal\u{201D})."
        }
        if UserSettings.shared.commandHotkeyKeyCode == UserSettings.shared.hotkeyKeyCode {
            return "Must differ from the dictation shortcut \u{2014} command mode is off until you pick another key."
        }
        return "Hold to edit selected text by voice (e.g. \u{201C}make this formal\u{201D}, \u{201C}translate to English\u{201D})."
    }

    @objc private func commandHotkeyPopupChanged() {
        UserSettings.shared.commandHotkeyKeyCode = Int(HotkeyManager.presets[commandHotkeyPopup.indexOfSelectedItem].keyCode)
        commandHotkeyCaption.stringValue = commandKeyNote()
        NotificationCenter.default.post(name: .commandHotkeyChanged, object: nil)
    }

    @objc private func inputDeviceChanged() {
        let i = inputPopup.indexOfSelectedItem
        UserSettings.shared.inputDeviceUID = inputDeviceUIDs.indices.contains(i) ? inputDeviceUIDs[i] : ""
        NotificationCenter.default.post(name: .inputDeviceChanged, object: nil)
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

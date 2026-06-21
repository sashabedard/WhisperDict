import Cocoa

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Initializing…", action: nil, keyEquivalent: "")
    private let historySectionEnd = NSMenuItem.separator()
    private let aiNudgeItem = NSMenuItem(title: "✨ Enable Apple Intelligence for Smart cleanup", action: #selector(openAISettings), keyEquivalent: "")
    private let aiNudgeSeparator = NSMenuItem.separator()
    private var historyItems: [NSMenuItem] = []
    private var onPreferences: (() -> Void)?
    private var onCheckUpdates: (() -> Void)?

    // Two leading items (nudge + its separator) sit above the status line, so
    // history inserts after: nudge, nudgeSep, status, sep = index 4.
    private let historyInsertIndex = 4

    override init() {
        super.init()
        statusItem.button?.title = "🎙"
        buildMenuOnce()
        menu.delegate = self
        statusItem.menu = menu
        renderHistory()
    }

    func configure(onPreferences: @escaping () -> Void, onCheckUpdates: @escaping () -> Void) {
        self.onPreferences = onPreferences
        self.onCheckUpdates = onCheckUpdates
    }

    func setStatus(_ text: String, icon: String = "🎙") {
        statusItem.button?.title = icon
        statusMenuItem.title = text
    }

    func refreshHistory() {
        renderHistory()
    }

    private func buildMenuOnce() {
        aiNudgeItem.target = self
        aiNudgeItem.isHidden = true
        aiNudgeSeparator.isHidden = true
        menu.addItem(aiNudgeItem)
        menu.addItem(aiNudgeSeparator)

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        // history items get inserted between here…
        menu.addItem(historySectionEnd)
        // …and here.
        let updatesItem = NSMenuItem(title: "Check for updates…", action: #selector(checkUpdatesClicked), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)
        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Pith", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func renderHistory() {
        for item in historyItems { menu.removeItem(item) }
        historyItems.removeAll()

        let history = HistoryManager.shared.items
        var insertAt = historyInsertIndex
        if history.isEmpty {
            let empty = NSMenuItem(title: "No history yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.insertItem(empty, at: insertAt)
            historyItems.append(empty)
        } else {
            for text in history {
                let title = text.count <= 42 ? text : String(text.prefix(39)) + "..."
                let item = NSMenuItem(title: title, action: #selector(rePaste(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = text
                menu.insertItem(item, at: insertAt)
                historyItems.append(item)
                insertAt += 1
            }
        }
    }

    @objc private func rePaste(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        PasteHelper.paste(text)
    }

    @objc private func checkUpdatesClicked() { onCheckUpdates?() }

    @objc private func openPreferences() {
        onPreferences?()
    }

    @objc private func openAISettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    // NSMenuDelegate — re-evaluate the Apple Intelligence nudge each time the
    // menu opens, so it disappears the moment the user enables it.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let needsAI = Enhancer.availabilityState == .needsAppleIntelligence
        aiNudgeItem.isHidden = !needsAI
        aiNudgeSeparator.isHidden = !needsAI
    }
}

import Cocoa

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Initializing…", action: nil, keyEquivalent: "")
    private let historySectionEnd = NSMenuItem.separator()
    private var historyItems: [NSMenuItem] = []
    private var onPreferences: (() -> Void)?

    private let historyInsertIndex = 2  // after statusMenuItem + first separator

    override init() {
        super.init()
        statusItem.button?.title = "🎙"
        buildMenuOnce()
        statusItem.menu = menu
        renderHistory()
    }

    func configure(onPreferences: @escaping () -> Void) {
        self.onPreferences = onPreferences
    }

    func setStatus(_ text: String, icon: String = "🎙") {
        statusItem.button?.title = icon
        statusMenuItem.title = text
    }

    func refreshHistory() {
        renderHistory()
    }

    private func buildMenuOnce() {
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        // history items get inserted between here…
        menu.addItem(historySectionEnd)
        // …and here.
        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit WhisperDict", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
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

    @objc private func openPreferences() {
        onPreferences?()
    }
}

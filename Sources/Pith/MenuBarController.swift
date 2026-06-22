// Pith — on-device push-to-talk dictation for macOS
// Copyright (C) 2026 Sasha Bédard
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

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
        applyIcon("🎙")
        buildMenuOnce()
        menu.delegate = self
        statusItem.menu = menu
        renderHistory()
    }

    func configure(onPreferences: @escaping () -> Void, onCheckUpdates: @escaping () -> Void) {
        self.onPreferences = onPreferences
        self.onCheckUpdates = onCheckUpdates
    }

    // Idle/state glyphs as monochrome SF Symbols (template images that adapt to
    // light/dark + menu-bar tint). The idle dot echoes the app's "core" icon.
    private static let symbolForEmoji: [String: String] = [
        "🎙": "smallcircle.filled.circle",   // idle / ready
        "🔴": "record.circle",               // recording
        "⏳": "circle.dotted",               // loading model / transcribing
        "✨": "sparkles",                    // enhancing / running command
        "🪄": "wand.and.stars",              // command mode
        "⚠️": "exclamationmark.triangle",    // error / permission warning
    ]

    /// Render a menu-bar glyph. Known states map to an SF Symbol template image;
    /// anything else falls back to showing the raw string as the button title.
    private func applyIcon(_ icon: String) {
        guard let button = statusItem.button else { return }
        if let symbol = Self.symbolForEmoji[icon],
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: icon) {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            let rendered = image.withSymbolConfiguration(config) ?? image
            rendered.isTemplate = true
            button.image = rendered
            button.title = ""
        } else {
            button.image = nil
            button.title = icon
        }
    }

    func setStatus(_ text: String, icon: String = "🎙") {
        applyIcon(icon)
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

import Cocoa

enum PasteHelper {
    private static let kCKey: CGKeyCode = 0x08
    private static let kVKey: CGKeyCode = 0x09
    private static let kCmdKey: CGKeyCode = 0x37

    /// Copies `text` to the pasteboard and synthesizes ⌘V into the focused app.
    /// Returns `false` if Accessibility isn't granted — in that case the text is
    /// still on the clipboard, but the synthetic ⌘V would be silently dropped by
    /// the system, so the caller should surface a warning instead.
    @MainActor
    @discardableResult
    static func paste(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        guard AXIsProcessTrusted() else { return false }

        let src = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: kCmdKey, keyDown: true)
        let vDown   = CGEvent(keyboardEventSource: src, virtualKey: kVKey,   keyDown: true)
        let vUp     = CGEvent(keyboardEventSource: src, virtualKey: kVKey,   keyDown: false)
        let cmdUp   = CGEvent(keyboardEventSource: src, virtualKey: kCmdKey, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags   = .maskCommand
        let tap: CGEventTapLocation = .cghidEventTap
        cmdDown?.post(tap: tap); vDown?.post(tap: tap)
        vUp?.post(tap: tap);     cmdUp?.post(tap: tap)
        return true
    }

    /// Synthesizes ⌘C and returns the resulting selection text, or nil if nothing
    /// was copied (no selection, Accessibility not granted, or timeout). Does not
    /// preserve the pasteboard — the caller decides about restoration.
    @MainActor
    static func copySelection() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let pb = NSPasteboard.general
        let before = pb.changeCount

        let src = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: kCmdKey, keyDown: true)
        let cDown   = CGEvent(keyboardEventSource: src, virtualKey: kCKey,   keyDown: true)
        let cUp     = CGEvent(keyboardEventSource: src, virtualKey: kCKey,   keyDown: false)
        let cmdUp   = CGEvent(keyboardEventSource: src, virtualKey: kCmdKey, keyDown: false)
        cDown?.flags = .maskCommand
        cUp?.flags   = .maskCommand
        let tap: CGEventTapLocation = .cghidEventTap
        cmdDown?.post(tap: tap); cDown?.post(tap: tap)
        cUp?.post(tap: tap);     cmdUp?.post(tap: tap)

        // Wait briefly for the target app to write the selection to the pasteboard.
        let deadline = Date().addingTimeInterval(0.15)
        while pb.changeCount == before && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        guard pb.changeCount != before, let s = pb.string(forType: .string), !s.isEmpty else { return nil }
        return s
    }
}

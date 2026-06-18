import Cocoa

enum PasteHelper {
    private static let kVKey: CGKeyCode = 0x09
    private static let kCmdKey: CGKeyCode = 0x37

    @MainActor
    static func paste(_ text: String) {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

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
    }
}

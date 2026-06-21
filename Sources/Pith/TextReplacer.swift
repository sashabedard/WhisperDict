import AppKit
import ApplicationServices

/// Reads and replaces the focused UI element's selected text via the
/// Accessibility API, for deterministic in-place replacement (no synthetic
/// ⌘C/⌘V). Native AppKit apps support this; many Electron/web apps do not —
/// callers fall back to clipboard paste when these return nil/false.
enum TextReplacer {

    @MainActor
    static func focusedSelection() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        guard let element = focusedElement() else { return nil }
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    @MainActor
    static func replaceFocusedSelection(with text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let element = focusedElement() else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        // AX returns an AXUIElement (a CFType) here.
        return (focused as! AXUIElement)
    }
}

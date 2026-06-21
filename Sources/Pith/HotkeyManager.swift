import Cocoa

final class HotkeyManager {
    /// A selectable push-to-talk key. `keyCode` identifies the physical key;
    /// `flag` is the modifier that key toggles, used to tell press from release.
    struct Preset {
        let keyCode: UInt16
        let flag: NSEvent.ModifierFlags
        let label: String
    }

    /// Right-side modifiers only, so the left ones stay free for normal use.
    static let presets: [Preset] = [
        Preset(keyCode: 61, flag: .option,  label: "Right Option (⌥)"),
        Preset(keyCode: 54, flag: .command, label: "Right Command (⌘)"),
        Preset(keyCode: 62, flag: .control, label: "Right Control (⌃)"),
        Preset(keyCode: 60, flag: .shift,   label: "Right Shift (⇧)"),
    ]

    static func preset(for keyCode: Int) -> Preset {
        presets.first { $0.keyCode == UInt16(keyCode) } ?? presets[0]
    }

    private var monitor: Any?
    private var isPressed = false
    private let keyCodeProvider: () -> Int
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private var current: Preset

    init(keyCodeProvider: @escaping () -> Int = { UserSettings.shared.hotkeyKeyCode },
         onPress: @escaping () -> Void,
         onRelease: @escaping () -> Void) {
        self.keyCodeProvider = keyCodeProvider
        self.onPress = onPress
        self.onRelease = onRelease
        self.current = HotkeyManager.preset(for: keyCodeProvider())
    }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, event.keyCode == self.current.keyCode else { return }
            let nowDown = event.modifierFlags.contains(self.current.flag)
            if nowDown && !self.isPressed {
                self.isPressed = true
                Task { @MainActor in self.onPress() }
            } else if !nowDown && self.isPressed {
                self.isPressed = false
                Task { @MainActor in self.onRelease() }
            }
        }
    }

    /// Rebuilds the monitor for the currently-saved key (call after a change).
    func restart() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        isPressed = false
        current = HotkeyManager.preset(for: keyCodeProvider())
        start()
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

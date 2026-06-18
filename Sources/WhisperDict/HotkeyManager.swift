import Cocoa

final class HotkeyManager {
    private var monitor: Any?
    private var isPressed = false
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private let targetKeyCode: UInt16 = 61 // Right-Option

    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
    }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, event.keyCode == self.targetKeyCode else { return }
            let nowDown = event.modifierFlags.contains(.option)
            if nowDown && !self.isPressed {
                self.isPressed = true
                Task { @MainActor in self.onPress() }
            } else if !nowDown && self.isPressed {
                self.isPressed = false
                Task { @MainActor in self.onRelease() }
            }
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

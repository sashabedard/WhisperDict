import Cocoa
import AVFoundation

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private var micRow    = PermissionRow(icon: "mic.fill",           title: "Microphone")
    private var axRow     = PermissionRow(icon: "accessibility",      title: "Accessibility")
    private var modelRow  = ModelLoadRow()
    private var doneButton = NSButton()
    private var onReady: (() -> Void)?

    convenience init(onReady: @escaping () -> Void) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 330),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.center()
        self.init(window: panel)
        self.onReady = onReady
        panel.delegate = self
        panel.contentView = buildContent()
        refreshStatus()

        // Re-check whenever the user switches back to the app
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refreshStatus() }
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func setModelStatus(loading: Bool, ready: Bool) {
        if ready {
            modelRow.setState(.granted, detail: "Ready")
        } else if loading {
            modelRow.setState(.loading, detail: "Downloading…")
        } else {
            modelRow.setState(.pending, detail: "Will download (~954 MB)")
        }
        refreshDoneButton()
    }

    private func refreshStatus() {
        // Microphone
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micRow.setState(.granted, detail: "Granted")
        case .notDetermined:
            micRow.setState(.pending, detail: "Required")
            micRow.showButton(title: "Allow", action: #selector(requestMic), target: self)
        default:
            micRow.setState(.denied, detail: "Denied — open System Settings")
        }

        // Accessibility
        if AXIsProcessTrusted() {
            axRow.setState(.granted, detail: "Granted")
        } else {
            axRow.setState(.pending, detail: "Required")
            axRow.showButton(title: "Open Settings", action: #selector(openAXSettings), target: self)
        }

        refreshDoneButton()
    }

    private func refreshDoneButton() {
        let micOK = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let axOK  = AXIsProcessTrusted()
        doneButton.isEnabled = micOK && axOK
        doneButton.alphaValue = doneButton.isEnabled ? 1.0 : 0.4
    }

    @objc private func requestMic() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshStatus() }
        }
    }

    @objc private func openAXSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        // Poll for grant
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if AXIsProcessTrusted() {
                Task { @MainActor in self.refreshStatus(); t.invalidate() }
            }
        }
    }

    @objc private func done() {
        UserSettings.shared.hasLaunchedBefore = true
        close()
        onReady?()
    }

    private func buildContent() -> NSView {
        let effect = NSVisualEffectView()
        effect.material = .windowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false

        // Title
        let title = NSTextField(labelWithString: "Welcome to WhisperDict")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "Grant permissions below to get started.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor

        let headerStack = NSStackView(views: [title, subtitle])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 4

        // Done button
        doneButton = NSButton(title: "Start dictating", target: self, action: #selector(done))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.isEnabled = false
        doneButton.alphaValue = 0.4

        let stack = NSStackView(views: [headerStack, micRow, axRow, modelRow, doneButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 32, left: 28, bottom: 28, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }
}

// MARK: - PermissionRow

private enum RowState { case pending, loading, granted, denied }

@MainActor
private class PermissionRow: NSView {
    private let iconView  = NSTextField(labelWithString: "")
    private let titleLbl  = NSTextField(labelWithString: "")
    private let detailLbl = NSTextField(labelWithString: "")
    private var actionBtn: NSButton?
    private let stack: NSStackView

    init(icon: String, title: String) {
        iconView.font = .systemFont(ofSize: 15)
        titleLbl.stringValue = title
        titleLbl.font = .systemFont(ofSize: 13, weight: .medium)
        detailLbl.font = .systemFont(ofSize: 12)
        detailLbl.textColor = .secondaryLabelColor

        let textCol = NSStackView(views: [titleLbl, detailLbl])
        textCol.orientation = .vertical
        textCol.alignment = .leading
        textCol.spacing = 2

        stack = NSStackView(views: [iconView, textCol])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY

        super.init(frame: .zero)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Try SF Symbol, fallback to emoji
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            let iv = NSImageView(image: img)
            iv.contentTintColor = .secondaryLabelColor
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.widthAnchor.constraint(equalToConstant: 20).isActive = true
            stack.insertArrangedSubview(iv, at: 0)
            stack.removeArrangedSubview(iconView)
            iconView.removeFromSuperview()
        } else {
            iconView.stringValue = "◦"
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func setState(_ state: RowState, detail: String) {
        detailLbl.stringValue = detail
        switch state {
        case .granted:
            detailLbl.textColor = .systemGreen
        case .denied:
            detailLbl.textColor = .systemRed
        case .loading:
            detailLbl.textColor = .systemOrange
        case .pending:
            detailLbl.textColor = .secondaryLabelColor
        }
    }

    func showButton(title: String, action: Selector, target: AnyObject) {
        if actionBtn != nil { return }
        let btn = NSButton(title: title, target: target, action: action)
        btn.bezelStyle = .rounded
        btn.controlSize = .small
        stack.addArrangedSubview(btn)
        actionBtn = btn
    }
}

// MARK: - ModelLoadRow

@MainActor
private final class ModelLoadRow: PermissionRow {
    init() {
        super.init(icon: "cpu", title: "Whisper Model")
        setState(.pending, detail: "Will download (~954 MB)")
    }

    required init?(coder: NSCoder) { fatalError() }
}

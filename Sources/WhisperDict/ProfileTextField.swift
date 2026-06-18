import Cocoa

/// Bordered, scrollable multi-line plain-text input used for the "About you"
/// profile in onboarding and Preferences. Wraps the NSScrollView + NSTextView
/// boilerplate and exposes a simple `stringValue` plus an enabled toggle.
@MainActor
final class ProfileTextField: NSScrollView {
    let textView = NSTextView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        borderType = .bezelBorder
        hasVerticalScroller = true
        drawsBackground = true
        translatesAutoresizingMaskIntoConstraints = false

        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        documentView = textView
    }

    required init?(coder: NSCoder) { fatalError() }

    var stringValue: String {
        get { textView.string }
        set { textView.string = newValue }
    }

    func setEnabled(_ on: Bool) {
        textView.isEditable = on
        textView.isSelectable = on
        textView.textColor = on ? .labelColor : .disabledControlTextColor
        alphaValue = on ? 1.0 : 0.6
    }
}

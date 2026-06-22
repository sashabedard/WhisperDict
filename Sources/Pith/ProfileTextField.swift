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

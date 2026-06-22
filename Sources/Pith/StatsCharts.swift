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

import AppKit

/// A rounded card showing one big number and a small caption.
@MainActor
final class MetricTile: NSView {
    private let valueLabel = NSTextField(labelWithString: "—")
    private let captionLabel = NSTextField(labelWithString: "")

    init(caption: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        applyFill()
        valueLabel.font = .systemFont(ofSize: 24, weight: .bold)
        valueLabel.textColor = .labelColor
        captionLabel.font = .systemFont(ofSize: 11)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.stringValue = caption

        let stack = NSStackView(views: [valueLabel, captionLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 64),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    var value: String {
        get { valueLabel.stringValue }
        set { valueLabel.stringValue = newValue }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyFill()
    }
    private func applyFill() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.05)
                                       : NSColor.black.withAlphaComponent(0.03)).cgColor
    }
}

/// A row of bars, heights normalized to the max value.
@MainActor
final class BarTrendView: NSView {
    var data: [Int] = [] { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 48) }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard !data.isEmpty else { return }
        let maxV = max(data.max() ?? 0, 1)
        let n = CGFloat(data.count)
        let gap: CGFloat = 3
        let barW = max((bounds.width - gap * (n - 1)) / n, 1)
        for (i, v) in data.enumerated() {
            let x = CGFloat(i) * (barW + gap)
            let h = max(bounds.height * CGFloat(v) / CGFloat(maxV), v > 0 ? 3 : 1)
            (v > 0 ? NSColor.controlAccentColor : NSColor.quaternaryLabelColor).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: barW, height: h), xRadius: 2, yRadius: 2).fill()
        }
    }
}

/// A ring chart of up to 3 segments with a legend to the right.
@MainActor
final class DonutView: NSView {
    var segments: [(label: String, value: Int)] = [] { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 200, height: 96) }
    private let palette: [NSColor] = [.controlAccentColor, .systemTeal, .systemGray]

    override func draw(_ dirtyRect: NSRect) {
        guard !segments.isEmpty else {
            ("—" as NSString).draw(
                at: NSPoint(x: 4, y: bounds.midY - 8),
                withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor])
            return
        }
        let total = max(segments.reduce(0) { $0 + $1.value }, 1)
        let ringD: CGFloat = 80
        let center = NSPoint(x: 4 + ringD / 2, y: bounds.midY)
        let radius = ringD / 2
        var start: CGFloat = 90
        for (i, seg) in segments.enumerated() {
            let frac = CGFloat(seg.value) / CGFloat(total)
            let end = start - frac * 360
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
            path.lineWidth = 14
            palette[i % palette.count].setStroke()
            path.stroke()
            start = end
        }
        var ly = bounds.midY + 22
        let lx = 4 + ringD + 16
        for (i, seg) in segments.enumerated() {
            let pct = Int((Double(seg.value) / Double(total) * 100).rounded())
            palette[i % palette.count].setFill()
            NSBezierPath(ovalIn: NSRect(x: lx, y: ly + 2, width: 8, height: 8)).fill()
            ("\(seg.label)  \(pct)%" as NSString).draw(
                at: NSPoint(x: lx + 14, y: ly - 2),
                withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
            ly -= 22
        }
    }
}

/// Ranked rows: optional icon, label, a relative bar, and a value.
@MainActor
final class HBarListView: NSView {
    var rows: [(label: String, value: Int)] = [] { didSet { rebuild() } }
    var icons: [NSImage?] = [] { didSet { rebuild() } }

    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !rows.isEmpty else {
            let empty = NSTextField(labelWithString: "—")
            empty.font = .systemFont(ofSize: 11)
            empty.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(empty)
            return
        }
        let maxV = max(rows.map { $0.value }.max() ?? 0, 1)
        let useIcons = !icons.isEmpty
        for (i, row) in rows.enumerated() {
            var views: [NSView] = []

            // Fixed-width icon + label columns so every bar starts at the same x.
            if useIcons {
                let iv = NSImageView()
                if i < icons.count, let img = icons[i] { iv.image = img }
                iv.translatesAutoresizingMaskIntoConstraints = false
                iv.widthAnchor.constraint(equalToConstant: 16).isActive = true
                iv.heightAnchor.constraint(equalToConstant: 16).isActive = true
                views.append(iv)
            }

            let label = NSTextField(labelWithString: row.label)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 84).isActive = true
            views.append(label)

            // The bar fills the remaining width, so every row's track is the same
            // length and the accent fill is proportional/comparable.
            let bar = BarFill()
            bar.fraction = CGFloat(row.value) / CGFloat(maxV)
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.heightAnchor.constraint(equalToConstant: 6).isActive = true
            bar.setContentHuggingPriority(.defaultLow, for: .horizontal)
            bar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            views.append(bar)

            let value = NSTextField(labelWithString: "\(row.value)")
            value.font = .systemFont(ofSize: 11, weight: .medium)
            value.textColor = .secondaryLabelColor
            value.alignment = .right
            value.translatesAutoresizingMaskIntoConstraints = false
            value.widthAnchor.constraint(equalToConstant: 34).isActive = true
            value.setContentHuggingPriority(.required, for: .horizontal)
            views.append(value)

            let rowStack = NSStackView(views: views)
            rowStack.orientation = .horizontal
            rowStack.alignment = .centerY
            rowStack.spacing = 8
            rowStack.distribution = .fill
            stack.addArrangedSubview(rowStack)
            rowStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
}

/// A track with an accent fill proportional to `fraction` (0...1).
@MainActor
private final class BarFill: NSView {
    var fraction: CGFloat = 0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
        let w = max(bounds.width * max(0, min(1, fraction)), fraction > 0 ? 4 : 0)
        guard w > 0 else { return }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: bounds.height), xRadius: 3, yRadius: 3).fill()
    }
}

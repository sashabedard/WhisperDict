import Cocoa
import QuartzCore

/// A borderless, non-activating panel that floats above all apps while
/// dictating. It never becomes key/main, so the user's focused text field
/// stays focused and PasteHelper can still ⌘V into it.
@MainActor
final class RecordingOverlayController {
    private let panel: NSPanel
    private let bars = BarsView(frame: NSRect(x: 0, y: 0, width: 140, height: 44))
    private var meters: [LevelMeter]

    private let barCount = 8
    private let panelSize = NSSize(width: 160, height: 56)
    private let bottomMargin: CGFloat = 96

    init() {
        meters = Array(repeating: LevelMeter(), count: 8)

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let container = NSView(frame: NSRect(origin: .zero, size: panelSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.85).cgColor
        container.layer?.cornerRadius = panelSize.height / 2
        bars.frame = NSRect(
            x: (panelSize.width - bars.frame.width) / 2,
            y: (panelSize.height - bars.frame.height) / 2,
            width: bars.frame.width, height: bars.frame.height
        )
        container.addSubview(bars)
        panel.contentView = container
    }

    func show() {
        meters = Array(repeating: LevelMeter(), count: barCount)
        bars.setRecording()
        positionPanel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    func setBands(_ bands: [Float]) {
        // Each bar tracks its own frequency band, smoothed independently, so the
        // row behaves like a real spectrum analyzer instead of moving in lockstep.
        var heights: [CGFloat] = []
        for i in 0..<barCount {
            let raw = i < bands.count ? bands[i] : 0
            heights.append(CGFloat(meters[i].smooth(raw)))
        }
        bars.setHeights(heights)
    }

    func enterSpinner() {
        bars.setSpinner()
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.panel.orderOut(nil)
                self?.bars.setRecording()
            }
        })
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        let x = frame.midX - panelSize.width / 2
        let y = frame.minY + bottomMargin
        panel.setFrame(NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height), display: true)
    }
}

/// CALayer-backed equalizer bars with a recording mode (driven by levels) and a
/// spinner mode (a rotating arc) shown during transcription.
@MainActor
final class BarsView: NSView {
    private var barLayers: [CALayer] = []
    private let spinnerLayer = CAShapeLayer()
    private let barCount = 8
    private let barWidth: CGFloat = 6
    private let barGap: CGFloat = 8
    private let minHeight: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        buildBars()
        buildSpinner()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildBars() {
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
        var x = (bounds.width - totalWidth) / 2
        for _ in 0..<barCount {
            let layer = CALayer()
            layer.backgroundColor = NSColor.white.cgColor
            layer.cornerRadius = barWidth / 2
            layer.frame = CGRect(x: x, y: (bounds.height - minHeight) / 2, width: barWidth, height: minHeight)
            self.layer?.addSublayer(layer)
            barLayers.append(layer)
            x += barWidth + barGap
        }
    }

    private func buildSpinner() {
        // The layer gets real bounds and the arc is drawn in the layer's OWN
        // coordinate space (centered on those bounds), so anchorPoint (0.5, 0.5)
        // lands on the arc's center and transform.rotation.z spins in place
        // rather than orbiting the view origin.
        let box: CGFloat = 24
        let radius: CGFloat = 9
        spinnerLayer.bounds = CGRect(x: 0, y: 0, width: box, height: box)
        spinnerLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        spinnerLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        let center = CGPoint(x: box / 2, y: box / 2)
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 270)
        spinnerLayer.path = path.cgPathCompat
        spinnerLayer.strokeColor = NSColor.white.cgColor
        spinnerLayer.fillColor = NSColor.clear.cgColor
        spinnerLayer.lineWidth = 2.5
        spinnerLayer.lineCap = .round
        spinnerLayer.isHidden = true
        layer?.addSublayer(spinnerLayer)
    }

    func setHeights(_ levels: [CGFloat]) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.06)
        for (i, layer) in barLayers.enumerated() where i < levels.count {
            let h = minHeight + levels[i] * (bounds.height - minHeight)
            layer.frame = CGRect(x: layer.frame.origin.x, y: (bounds.height - h) / 2, width: barWidth, height: h)
        }
        CATransaction.commit()
    }

    func setRecording() {
        spinnerLayer.removeAnimation(forKey: "spin")
        spinnerLayer.isHidden = true
        barLayers.forEach { $0.isHidden = false }
    }

    func setSpinner() {
        barLayers.forEach { $0.isHidden = true }
        spinnerLayer.isHidden = false
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -Double.pi * 2
        spin.duration = 0.9
        spin.repeatCount = .infinity
        spinnerLayer.add(spin, forKey: "spin")
    }
}

private extension NSBezierPath {
    var cgPathCompat: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &points) {
            case .moveTo:    path.move(to: points[0])
            case .lineTo:    path.addLine(to: points[0])
            case .curveTo:   path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .cubicCurveTo:   path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:   path.addQuadCurve(to: points[1], control: points[0])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}

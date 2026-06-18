# Recording Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a floating equalizer-bar bubble at the bottom of the screen that appears while dictating, modulates with the user's voice, then becomes a spinner during transcription before disappearing.

**Architecture:** One new file (`RecordingOverlay.swift`) owning a non-activating `NSPanel` plus a CALayer bar view, fed by a new RMS-level callback on `AudioRecorder`, orchestrated from `AppDelegate`. The audio thread only computes math; all UI updates hop to the main thread. The level→height mapping is a pure, unit-tested function.

**Tech Stack:** Swift 5.9, AppKit, AVFoundation, Core Animation, SwiftPM, XCTest.

## Global Constraints

- Platform: macOS 13+ (`.macOS(.v13)`), Swift tools 5.9.
- The overlay panel MUST be non-activating and MUST NOT steal focus (the app pastes into the externally focused field via `PasteHelper`).
- No AppKit/UI access on AVAudioEngine's audio thread; UI updates dispatch to main and are throttled to ~20 fps.
- Additive only: the existing record → transcribe → paste → history pipeline keeps its current behavior.
- All new UI types are `@MainActor`.

---

## File Structure

- **Create** `Sources/WhisperDict/LevelMeter.swift` — pure RMS→normalized-level math (log scale + smoothing). Unit-tested.
- **Create** `Sources/WhisperDict/RecordingOverlay.swift` — `RecordingOverlayController` (non-activating panel + positioning) and `BarsView` (CALayer bars + spinner).
- **Create** `Tests/WhisperDictTests/LevelMeterTests.swift` — unit tests for the mapping.
- **Modify** `Package.swift` — add a test target.
- **Modify** `Sources/WhisperDict/AudioRecorder.swift` — add `onLevel` callback + RMS computation + throttle.
- **Modify** `Sources/WhisperDict/AppDelegate.swift` — own the overlay; show/spinner/hide at the right lifecycle points.

---

### Task 1: Level → height mapping (pure, tested)

**Files:**
- Create: `Sources/WhisperDict/LevelMeter.swift`
- Modify: `Package.swift`
- Test: `Tests/WhisperDictTests/LevelMeterTests.swift`

**Interfaces:**
- Produces:
  - `struct LevelMeter` with:
    - `static func normalize(rms: Float) -> Float` — pure, log-scaled, clamped to `[0, 1]`.
    - `mutating func update(rms: Float) -> Float` — applies `normalize` then asymmetric exponential smoothing (fast attack / slow release); returns smoothed `[0, 1]`.
    - tunable static constants: `floorDB`, `ceilDB`, `attack`, `release`.

- [ ] **Step 1: Add the test target to `Package.swift`**

Replace the `targets:` array so it reads:

```swift
    targets: [
        .executableTarget(
            name: "WhisperDict",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/WhisperDict"
        ),
        .testTarget(
            name: "WhisperDictTests",
            dependencies: ["WhisperDict"],
            path: "Tests/WhisperDictTests"
        ),
    ]
```

- [ ] **Step 2: Write the failing test**

Create `Tests/WhisperDictTests/LevelMeterTests.swift`:

```swift
import XCTest
@testable import WhisperDict

final class LevelMeterTests: XCTestCase {
    func testSilenceMapsToZero() {
        XCTAssertEqual(LevelMeter.normalize(rms: 0), 0, accuracy: 0.001)
    }

    func testLoudMapsToOne() {
        // rms = 1.0 → 0 dB, well above the ceiling → clamps to 1
        XCTAssertEqual(LevelMeter.normalize(rms: 1.0), 1, accuracy: 0.001)
    }

    func testMonotonicInBetween() {
        let quiet = LevelMeter.normalize(rms: 0.01)
        let mid   = LevelMeter.normalize(rms: 0.1)
        let loud  = LevelMeter.normalize(rms: 0.5)
        XCTAssertLessThan(quiet, mid)
        XCTAssertLessThan(mid, loud)
    }

    func testOutputAlwaysInRange() {
        for rms: Float in [0, 0.0001, 0.01, 0.3, 1.0, 5.0] {
            let v = LevelMeter.normalize(rms: rms)
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
    }

    func testSmoothingRisesFastFallsSlow() {
        var meter = LevelMeter()
        _ = meter.update(rms: 0.0)        // start near 0
        let afterLoud = meter.update(rms: 1.0)   // fast attack → big jump
        let afterSilence = meter.update(rms: 0.0) // slow release → small drop
        XCTAssertGreaterThan(afterLoud, 0.4)
        XCTAssertGreaterThan(afterSilence, afterLoud * 0.5) // didn't collapse to 0
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter LevelMeterTests`
Expected: FAIL — `cannot find 'LevelMeter' in scope` (type not defined yet).

- [ ] **Step 4: Write the implementation**

Create `Sources/WhisperDict/LevelMeter.swift`:

```swift
import Foundation

/// Maps a raw audio RMS amplitude to a normalized [0, 1] level for the
/// equalizer bars. Loudness is perceived logarithmically, so we map through a
/// dB curve and apply asymmetric smoothing (fast rise, slow fall) so the bars
/// feel lively without jittering.
struct LevelMeter {
    /// RMS (in dB) treated as silence (→ 0).
    static let floorDB: Float = -50
    /// RMS (in dB) treated as full scale (→ 1).
    static let ceilDB: Float = -10
    /// Smoothing toward a higher level (fast).
    static let attack: Float = 0.6
    /// Smoothing toward a lower level (slow).
    static let release: Float = 0.15

    private var smoothed: Float = 0

    /// Pure log-scaled, clamped mapping. No state.
    static func normalize(rms: Float) -> Float {
        let safe = max(rms, 1e-7)
        let db = 20 * log10(safe)
        let norm = (db - floorDB) / (ceilDB - floorDB)
        return min(max(norm, 0), 1)
    }

    /// Stateful: normalize + asymmetric exponential smoothing.
    mutating func update(rms: Float) -> Float {
        let target = Self.normalize(rms: rms)
        let coeff = target > smoothed ? Self.attack : Self.release
        smoothed += (target - smoothed) * coeff
        return smoothed
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter LevelMeterTests`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/WhisperDict/LevelMeter.swift Tests/WhisperDictTests/LevelMeterTests.swift
git commit -m "feat: add LevelMeter — pure RMS→bar-height mapping with smoothing"
```

---

### Task 2: AudioRecorder level callback

**Files:**
- Modify: `Sources/WhisperDict/AudioRecorder.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `AudioRecorder.onLevel: ((Float) -> Void)?` — called on the **main thread**, throttled to ~20 fps, with the raw buffer RMS (pre-mapping).
  - `onLevel` is set to `nil` inside `stop()`.

- [ ] **Step 1: Add the property and throttle state**

In `Sources/WhisperDict/AudioRecorder.swift`, add to the stored properties (after `private var converter`):

```swift
    /// Called on the main thread with the raw RMS of each buffer (throttled).
    var onLevel: ((Float) -> Void)?
    private var lastLevelEmit: CFTimeInterval = 0
```

- [ ] **Step 2: Emit RMS from the audio tap**

In `process(buffer:format:)`, after the existing line `lock.lock(); samples.append(contentsOf: chunk); lock.unlock()`, append:

```swift
        // Voice-level metering for the recording overlay. Cheap math here is
        // fine on the audio thread; the UI hop + throttle happen below.
        var sumSquares: Float = 0
        for s in chunk { sumSquares += s * s }
        let rms = chunk.isEmpty ? 0 : (sumSquares / Float(chunk.count)).squareRoot()

        let now = CACurrentMediaTime()
        if now - lastLevelEmit >= 0.05 {   // ~20 fps
            lastLevelEmit = now
            DispatchQueue.main.async { [weak self] in self?.onLevel?(rms) }
        }
```

- [ ] **Step 3: Ensure CoreAnimation import for `CACurrentMediaTime`**

At the top of the file, if not already present, add after `import AVFoundation`:

```swift
import QuartzCore
```

- [ ] **Step 4: Clear the callback on stop**

In `stop()`, immediately after `engine.stop()`, add:

```swift
        onLevel = nil
        lastLevelEmit = 0
```

- [ ] **Step 5: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds (no behavior change yet; `onLevel` is nil until Task 4 wires it).

- [ ] **Step 6: Commit**

```bash
git add Sources/WhisperDict/AudioRecorder.swift
git commit -m "feat: emit throttled RMS level from AudioRecorder tap"
```

---

### Task 3: Recording overlay panel + bars view

**Files:**
- Create: `Sources/WhisperDict/RecordingOverlay.swift`

**Interfaces:**
- Consumes: `LevelMeter` (Task 1).
- Produces:
  - `@MainActor final class RecordingOverlayController` with:
    - `func show()` — position on the screen under the mouse, fade in, enter recording mode.
    - `func setLevel(_ rms: Float)` — feed a raw RMS sample (drives bars).
    - `func enterSpinner()` — freeze bars, show a rotating loading indicator.
    - `func hide()` — fade out + order out, reset to hidden.

- [ ] **Step 1: Create the overlay file**

Create `Sources/WhisperDict/RecordingOverlay.swift`:

```swift
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

    func setLevel(_ rms: Float) {
        // One shared sample, fanned out to per-bar meters with slight offsets so
        // neighboring bars differ → looks like an equalizer, not 8 clones.
        var heights: [CGFloat] = []
        for i in 0..<barCount {
            let jitter = Float(1.0 - 0.25 * abs(Double(i) - Double(barCount) / 2) / Double(barCount))
            let level = meters[i].update(rms: rms * jitter)
            heights.append(CGFloat(level))
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
            self?.panel.orderOut(nil)
            self?.bars.setRecording()
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
        let radius: CGFloat = 9
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 270)
        spinnerLayer.path = path.cgPath
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
```

- [ ] **Step 2: Add the `NSBezierPath.cgPath` helper if missing**

`NSBezierPath` has no `cgPath` before macOS 14. To stay compatible with the macOS 13 floor, add this extension at the bottom of `RecordingOverlay.swift`:

```swift
private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &points) {
            case .moveTo:    path.move(to: points[0])
            case .lineTo:    path.addLine(to: points[0])
            case .curveTo:   path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds. (Nothing calls the controller yet.)

- [ ] **Step 4: Commit**

```bash
git add Sources/WhisperDict/RecordingOverlay.swift
git commit -m "feat: add non-activating recording overlay with equalizer bars + spinner"
```

---

### Task 4: Wire the overlay into the app lifecycle

**Files:**
- Modify: `Sources/WhisperDict/AppDelegate.swift`

**Interfaces:**
- Consumes: `RecordingOverlayController` (Task 3), `AudioRecorder.onLevel` (Task 2).

- [ ] **Step 1: Own an overlay instance**

In `AppDelegate`, add after `private let transcriber = Transcriber()`:

```swift
    private let overlay = RecordingOverlayController()
```

- [ ] **Step 2: Show the overlay and feed levels on record**

In `startRecording()`, inside the `do` block, after `try recorder.start()` and before `menuBar.setStatus("Recording…", icon: "🔴")`, add:

```swift
            recorder.onLevel = { [weak self] rms in self?.overlay.setLevel(rms) }
            overlay.show()
```

In the `catch` block of `startRecording()`, after `menuBar.setStatus("Mic error: …")` and `isBusy = false`, add:

```swift
            overlay.hide()
```

(So a failed start never leaves the bubble on screen.)

- [ ] **Step 3: Spinner on release, hide after paste**

In `stopAndTranscribe()`, immediately after `let audio = recorder.stop()`, add:

```swift
        overlay.enterSpinner()
```

Inside the final `await MainActor.run { [self] in … }` block, add `self.overlay.hide()` so it runs on both branches — place it right after `self.isBusy = false`:

```swift
                self.isBusy = false
                self.overlay.hide()
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 5: Build the app bundle and run a manual smoke test**

Run: `./build.sh && open WhisperDict.app`

Manual checklist (from the spec):
1. Hold Right-Option → bubble appears bottom-center on the screen under the mouse.
2. **Click into a text field in another app first, then dictate → the transcribed text still pastes there** (focus not stolen). Critical.
3. Bars move with your voice; silence → low/flat.
4. Release → bars become a spinner → bubble fades out after text is inserted.
5. No audio dropouts while the bars animate.

- [ ] **Step 6: Commit**

```bash
git add Sources/WhisperDict/AppDelegate.swift
git commit -m "feat: show recording overlay during dictation and transcription"
```

---

## Self-Review

**Spec coverage:**
- Non-activating panel / no focus steal → Task 3 (panel config) + Task 4 step 5 check #2. ✓
- No UI on audio thread, throttled 20 fps → Task 2. ✓
- Additive pipeline → Tasks 2 & 4 only add calls. ✓
- Bottom-center on mouse screen, full-screen aux → Task 3 `positionPanel` + `collectionBehavior`. ✓
- Equalizer bars, per-bar variation → Task 3 `setLevel` jitter + `BarsView`. ✓
- Log mapping + asymmetric smoothing → Task 1. ✓
- States hidden→recording→spinner→hidden → Tasks 3 & 4. ✓
- Error paths call `hide()` → Task 4 steps 2 & 3. ✓
- Pure mapping unit-tested → Task 1. ✓

**Placeholder scan:** none.

**Type consistency:** `LevelMeter.normalize`/`update`, `RecordingOverlayController.show/setLevel/enterSpinner/hide`, `BarsView.setHeights/setRecording/setSpinner`, `AudioRecorder.onLevel` — names used consistently across tasks. ✓

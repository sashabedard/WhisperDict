# Recording Overlay — Floating Voice Bubble

**Date:** 2026-06-18
**Status:** Approved design

## Goal

Add a floating bubble at the bottom of the screen that appears while the user
is dictating (Right-Option held) and modulates with their voice — equalizer
bars, Wispr Flow style. It gives live visual feedback that the app is listening
and hearing audio, then turns into a spinner during transcription before
disappearing.

## Constraints (non-negotiable)

- **Must never steal focus.** The whole app depends on synthesizing ⌘V into the
  *currently focused* app (`PasteHelper`). The overlay must use a
  non-activating panel so the user's text field stays focused.
- **No UI work on the audio thread.** `AudioRecorder.process()` runs on
  AVAudioEngine's real-time thread. Level computation may happen there (pure
  math) but any UI update must hop to the main thread and be throttled.
- **Additive only.** The existing recording → transcription → paste → history
  pipeline must not change behavior. The overlay observes; it does not
  participate in the critical path.

## Architecture

One new file, two small edits.

### New: `Sources/WhisperDict/RecordingOverlay.swift`

`RecordingOverlayController` (`@MainActor`) owns:

- **A non-activating `NSPanel`:**
  - style `.nonactivatingPanel` + `.borderless`
  - `level = .statusBar`, `ignoresMouseEvents = true`
  - `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`
  - transparent background (`isOpaque = false`, `backgroundColor = .clear`),
    rounded translucent capsule drawn by the content view
  - `hasShadow = true`
- **Positioning:** bottom-center of the `NSScreen` whose `frame` contains the
  current mouse location (`NSEvent.mouseLocation`), with a fixed margin above
  the screen's bottom edge. Falls back to `NSScreen.main`.
- **`BarsView`** (CALayer-backed `NSView`): draws 8 vertical bars; exposes
  `setLevel(_:)` and a `spinner` mode.

Public API:

```
show()                 // create/position panel, start recording visuals
setLevel(_ rms: Float) // drive bar heights (called on main thread, throttled)
enterSpinner()         // freeze bars → loading indicator
hide()                 // fade out + order out, reset to hidden
```

### Edit: `AudioRecorder.swift` (~6 lines)

- Add `var onLevel: ((Float) -> Void)?`.
- In `process()`, after building `chunk`, compute RMS of the buffer:
  `sqrt(mean(sample^2))`.
- Throttle to ~20 fps (skip if <50 ms since last emit) and dispatch the value
  to the main thread before calling `onLevel`.
- The existing sample-collection logic is untouched. `onLevel` is cleared in
  `stop()`.

### Edit: `AppDelegate.swift` (~4 lines)

- Hold a `private let overlay = RecordingOverlayController()`.
- `startRecording()`: after `recorder.start()` succeeds, set
  `recorder.onLevel = { [weak self] in self?.overlay.setLevel($0) }` and call
  `overlay.show()`.
- `stopAndTranscribe()`: call `overlay.enterSpinner()` right after
  `recorder.stop()`; call `overlay.hide()` in the final `MainActor.run` block
  (both the success and empty-text branches).
- Mic-error and any early-exit path that clears `isBusy` also calls
  `overlay.hide()`.

## Data flow

```
audio thread:  buffer → RMS → (throttle 20fps, dispatch to main) → onLevel(level)
main thread:   level → log-scale + exponential smoothing → 8 bar heights → CALayer
release:       bars → spinner → (text pasted) → fade out → hidden
```

## Level → bar-height mapping (implemented for the user)

Pure function, isolated for unit testing and easy tuning. Tunable constants at
the top of the file.

- **Log scale:** human loudness is perceived logarithmically, so map RMS through
  a log/decibel curve rather than linearly — quiet speech still moves the bars.
- **Exponential smoothing** with asymmetric coefficients: fast attack (bars jump
  up quickly), slow release (bars ease down) → lively but never jittery.
- **Per-bar variation:** neighboring bars get slightly offset/scaled values so
  the row looks like an equalizer, not 8 identical bars.
- Output clamped to `[minHeight, maxHeight]`.

## Bubble states

```
hidden → recording (live bars) → spinner (transcription) → fade out → hidden
```

## Error handling

Every path that clears `isBusy` also calls `overlay.hide()`: mic error, 30 s
transcription timeout, empty transcription, successful paste. The bubble can
never get stuck on screen.

## Testing

Menu-bar AppKit app → primarily manual verification:

1. Bubble appears bottom-center on the screen under the mouse.
2. **Focus is not stolen** — paste still lands in the previously focused field
   while the bubble is visible. (Critical regression check.)
3. Bars react to voice in real time; silence → low/flat, speech → active.
4. Release → spinner → bubble disappears after text is inserted.
5. No audio glitches or dropouts while the overlay animates.
6. Multi-display: bubble shows on the active screen; works over a full-screen app.

The level → height mapping is a pure function and gets a unit test
(silence → min, loud → near max, monotonic in between).

## Out of scope (YAGNI)

- User-configurable bubble position, size, color, or bar count.
- Click-to-cancel on the bubble (it ignores mouse events).
- Showing the live partial transcript in the bubble.

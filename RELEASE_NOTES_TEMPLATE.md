# Release notes template

Copy this into the GitHub Release description when you publish a build. Attach
`Pith.zip` (made with `ditto -c -k --keepParent Pith.app Pith.zip`)
as the release asset.

---

## Pith vX.Y.Z

Local push-to-talk dictation for macOS. Hold **Right-Option**, speak, release —
your words are transcribed 100% on-device and pasted where you're typing.

### Install

1. Download **`Pith.zip`** below and unzip it.
2. macOS blocks unidentified apps on first launch. Double-click `Pith.app`
   once (macOS refuses), then go to **System Settings → Privacy & Security**,
   scroll down, and click **“Open Anyway”** → **Open**.
   *(macOS 14 and earlier: Control-click the app → **Open** instead.)*
3. When the app opens, accept **“Move to Applications”** — this clears the
   warning permanently. Then grant **Microphone** and **Accessibility** when
   prompted (Accessibility is what lets Pith paste into other apps).

> Requires macOS 13+. Apple Silicon recommended. The first dictation downloads
> the Whisper model (~954 MB) once.

### What's new

- …
- …

### Known notes

- The app is ad-hoc signed, not notarized — hence the one-time Gatekeeper step
  above. Command-line alternative: `xattr -dr com.apple.quarantine Pith.app`.

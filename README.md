# WhisperDict 🎙

A lightweight **push-to-talk dictation** app for macOS that lives in your menu
bar. Hold a key, speak, release — your words are transcribed **100% on-device**
and pasted straight into whatever app you're using. No cloud, no account, no
data leaves your Mac.

Powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit) running
OpenAI's Whisper models locally via Core ML.

---

## Features

- **Push-to-talk** — hold the **Right-Option** key to record, release to
  transcribe and auto-paste at the cursor.
- **Fully local & private** — transcription runs on-device with WhisperKit; the
  default model is `whisper-large-v3-turbo`.
- **Menu-bar only** — no dock icon, stays out of your way (`🎙`).
- **History** — the last 8 transcriptions are kept; click one to re-paste it.
- **Configurable** — pick your language (defaults to French) and Whisper model
  in Preferences.

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon recommended (Core ML acceleration)
- On first launch, grant:
  - **Microphone** access (prompted automatically)
  - **Accessibility** access — System Settings → Privacy & Security →
    Accessibility (needed to synthesize ⌘V into other apps)

## Install

### Option A — Download (recommended)

1. Grab the latest `WhisperDict.app` from the [**Releases**](../../releases)
   page and unzip it.
2. **First launch is blocked by macOS** because the app is ad-hoc signed (not
   notarized). Double-click it once — macOS refuses — then open **System
   Settings → Privacy & Security**, scroll to the bottom, and click
   **“Open Anyway”**, then **Open** in the confirmation dialog.
   *(On macOS 14 and earlier you can instead Control-click the app → **Open**.)*
3. On first run, WhisperDict offers to **move itself into Applications** —
   accept it. That clears the security warning for good. From then on it
   launches normally and walks you through microphone + accessibility
   permissions.

> Prefer the command line? `xattr -dr com.apple.quarantine /path/to/WhisperDict.app`
> removes the quarantine flag so it opens directly.

### Option B — Build from source

```bash
git clone https://github.com/sashabedard/WhisperDict.git
cd WhisperDict
./build.sh
open WhisperDict.app
```

The first transcription downloads the Whisper model from the Hugging Face Hub
(one-time, a few hundred MB depending on the model).

## Usage

1. Launch WhisperDict — a `🎙` icon appears in the menu bar.
2. Click into any text field.
3. **Hold Right-Option**, speak, then **release**.
4. The transcribed text is pasted automatically.

## License

[MIT](LICENSE) © 2026 Sasha Bedard

Third-party components and their licenses are listed in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

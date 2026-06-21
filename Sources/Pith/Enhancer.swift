import Foundation

/// Why the on-device model is or isn't usable, so the UI can react: nudge the
/// user when Apple Intelligence is merely off, stay silent when the OS/device
/// can't run it at all.
enum EnhanceAvailability {
    case available             // ready to use
    case needsAppleIntelligence // macOS 26 but Apple Intelligence is off
    case unsupported           // macOS < 26, ineligible device, or no SDK
}

/// Cleanup styles for the on-device Enhance step. Each maps to a system prompt.
/// `faithful`/`polished`/`email` are user-selectable; `code` is applied
/// automatically by per-app context when dictating into an editor/terminal.
enum EnhanceStyle: String {
    case faithful, polished, email, code
}

/// Façade over the Enhance backends. AppDelegate/Preferences call this; it picks
/// the active backend per UserSettings and falls back Apple → raw.
actor Enhancer {
    private let apple = AppleEnhanceBackend()
    // Phase B adds: private let mlx = MLXEnhanceBackend()

    /// The Apple-specific availability, for the "enable Apple Intelligence" nudge.
    static var availabilityState: EnhanceAvailability { AppleEnhanceBackend.availabilityState }

    /// True when the effective backend (selected, or Apple fallback) can run.
    static var isAvailable: Bool {
        // Phase A: only the Apple backend exists. Phase B updates this to also
        // return true when the selected MLX model is downloaded.
        AppleEnhanceBackend.isAvailable
    }

    /// The effective backend for this call: the selected one if ready, else Apple.
    private func effectiveBackend() async -> EnhanceBackend? {
        // Phase A: always Apple. Phase B resolves UserSettings.enhanceBackend.
        apple.isReady ? apple : nil
    }

    func warmup() async {
        await effectiveBackend()?.warmup()
    }

    func enhance(_ raw: String, style: EnhanceStyle, vocabulary: [String] = [],
                 profile: String = "", formatLists: Bool = false) async -> String {
        guard let backend = await effectiveBackend() else { return raw }
        return await backend.enhance(raw, style: style, vocabulary: vocabulary,
                                     profile: profile, formatLists: formatLists) ?? raw
    }

    func runCommand(instruction: String, on text: String) async -> String {
        guard let backend = await effectiveBackend() else { return text }
        return await backend.runCommand(instruction: instruction, on: text) ?? text
    }
}

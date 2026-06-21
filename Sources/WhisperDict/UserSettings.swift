import Foundation

final class UserSettings {
    static let shared = UserSettings()

    var language: String {
        get { UserDefaults.standard.string(forKey: "language") ?? "auto" }
        set { UserDefaults.standard.set(newValue, forKey: "language") }
    }

    var modelName: String {
        get { UserDefaults.standard.string(forKey: "modelName") ?? "openai_whisper-large-v3_turbo_954MB" }
        set { UserDefaults.standard.set(newValue, forKey: "modelName") }
    }

    /// Whether the on-device LLM cleanup step runs after transcription.
    /// Uses `object(forKey:)` so the default is `true`, not UserDefaults'
    /// implicit `false`.
    var enhanceEnabled: Bool {
        get { (UserDefaults.standard.object(forKey: "enhanceEnabled") as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enhanceEnabled") }
    }

    /// Enhance style: "faithful", "polished", or "email".
    var enhanceStyle: String {
        get { UserDefaults.standard.string(forKey: "enhanceStyle") ?? "faithful" }
        set { UserDefaults.standard.set(newValue, forKey: "enhanceStyle") }
    }

    /// Raw vocabulary string as typed by the user (comma/newline separated).
    var vocabulary: String {
        get { UserDefaults.standard.string(forKey: "vocabulary") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "vocabulary") }
    }

    /// Local, private usage counters (never leave the Mac).
    var totalDictations: Int {
        get { UserDefaults.standard.integer(forKey: "totalDictations") }
        set { UserDefaults.standard.set(newValue, forKey: "totalDictations") }
    }
    var totalWords: Int {
        get { UserDefaults.standard.integer(forKey: "totalWords") }
        set { UserDefaults.standard.set(newValue, forKey: "totalWords") }
    }

    /// Raw snippets text, one `trigger => expansion` per line.
    var snippetsRaw: String {
        get { UserDefaults.standard.string(forKey: "snippets") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "snippets") }
    }

    /// Parsed snippet pairs (trigger, expansion), splitting each line on the
    /// first "=>" and dropping blanks.
    var snippets: [(trigger: String, expansion: String)] {
        snippetsRaw.split(whereSeparator: \.isNewline).compactMap { line in
            guard let r = line.range(of: "=>") else { return nil }
            let t = line[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            let e = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !e.isEmpty else { return nil }
            return (t, e)
        }
    }

    /// Key code of the push-to-talk key (see HotkeyManager.presets). Default 61
    /// is Right-Option.
    var hotkeyKeyCode: Int {
        get { (UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int) ?? 61 }
        set { UserDefaults.standard.set(newValue, forKey: "hotkeyKeyCode") }
    }

    /// Key code of the voice-command push-to-talk key (see HotkeyManager.presets).
    /// Default 62 is Right-Control. If equal to hotkeyKeyCode, command mode is
    /// treated as disabled.
    var commandHotkeyKeyCode: Int {
        get { (UserDefaults.standard.object(forKey: "commandHotkeyKeyCode") as? Int) ?? 62 }
        set { UserDefaults.standard.set(newValue, forKey: "commandHotkeyKeyCode") }
    }

    /// UID of the chosen input device. Empty string means "follow the macOS
    /// system default" (the original behavior). Persisted as the stable UID,
    /// never the ephemeral AudioDeviceID, which is reassigned on replug/reboot.
    var inputDeviceUID: String {
        get { UserDefaults.standard.string(forKey: "inputDeviceUID") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "inputDeviceUID") }
    }

    /// Whether to check GitHub for a newer release at launch. Default OFF — this
    /// is the only network access the app makes.
    var autoCheckUpdates: Bool {
        get { UserDefaults.standard.bool(forKey: "autoCheckUpdates") }   // default false
        set { UserDefaults.standard.set(newValue, forKey: "autoCheckUpdates") }
    }
    /// Timestamp of the last auto update check, to throttle to once per day.
    var lastUpdateCheck: Date? {
        get { UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastUpdateCheck") }
    }

    /// Which Enhance engine to use: "apple" (built-in, default) or "mlx" (Gemma).
    var enhanceBackend: String {
        get { UserDefaults.standard.string(forKey: "enhanceBackend") ?? "apple" }
        set { UserDefaults.standard.set(newValue, forKey: "enhanceBackend") }
    }
    /// MLX model variant when enhanceBackend == "mlx": "e2b" or "e4b" (default).
    var mlxModelVariant: String {
        get { UserDefaults.standard.string(forKey: "mlxModelVariant") ?? "e4b" }
        set { UserDefaults.standard.set(newValue, forKey: "mlxModelVariant") }
    }

    /// When true, the Enhance style is chosen from the frontmost app (email tone
    /// in mail clients, code style in editors), falling back to `enhanceStyle`.
    var perAppContextEnabled: Bool {
        get { (UserDefaults.standard.object(forKey: "perAppContextEnabled") as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "perAppContextEnabled") }
    }

    /// Free-form "about you" (name, role, projects) fed to the Enhance prompt as
    /// context so the model spells names/jargon and understands the domain.
    var profile: String {
        get { UserDefaults.standard.string(forKey: "profile") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "profile") }
    }

    /// Parsed, trimmed, non-empty vocabulary terms fed to the Enhance prompt so
    /// the model spells names/jargon correctly.
    var vocabularyTerms: [String] {
        vocabulary
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var hasLaunchedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: "hasLaunchedBefore") }
        set { UserDefaults.standard.set(newValue, forKey: "hasLaunchedBefore") }
    }
}

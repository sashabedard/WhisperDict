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

    /// Key code of the push-to-talk key (see HotkeyManager.presets). Default 61
    /// is Right-Option.
    var hotkeyKeyCode: Int {
        get { (UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int) ?? 61 }
        set { UserDefaults.standard.set(newValue, forKey: "hotkeyKeyCode") }
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

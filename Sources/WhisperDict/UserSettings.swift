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

    var hasLaunchedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: "hasLaunchedBefore") }
        set { UserDefaults.standard.set(newValue, forKey: "hasLaunchedBefore") }
    }
}

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

    var hasLaunchedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: "hasLaunchedBefore") }
        set { UserDefaults.standard.set(newValue, forKey: "hasLaunchedBefore") }
    }
}

import Foundation

/// How the app was installed — used so the in-app updater doesn't fight another
/// update manager (Homebrew). When Homebrew manages the app, the updater defers
/// to `brew upgrade` instead of downloading a .dmg that would desync brew.
enum InstallSource {
    /// Homebrew Caskroom locations to probe. Overridable in tests.
    static var caskroomPaths = [
        "/opt/homebrew/Caskroom/whisperdict",   // Apple Silicon
        "/usr/local/Caskroom/whisperdict",       // Intel
    ]

    /// True when the app lives in a Homebrew Cask install.
    static func isHomebrewManaged() -> Bool {
        caskroomPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }
}

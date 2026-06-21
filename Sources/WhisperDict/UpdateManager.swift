import AppKit

/// Orchestrates the update flow: check → (if newer) download the .dmg to
/// ~/Downloads → reveal it in Finder. All UI-facing state goes through the
/// `status` callback (a short line for the menu bar).
@MainActor
final class UpdateManager {

    func check(manual: Bool, status: @escaping (String) -> Void) async {
        // Auto-check self-gates on the setting and a 24h throttle. Manual bypasses.
        if !manual {
            guard UserSettings.shared.autoCheckUpdates else { return }
            if let last = UserSettings.shared.lastUpdateCheck,
               Date().timeIntervalSince(last) < 24 * 3600 { return }
            UserSettings.shared.lastUpdateCheck = Date()
        }

        guard let release = await UpdateChecker.fetchLatest() else {
            if manual { status("Couldn't check for updates") }
            return
        }

        let current = UpdateChecker.currentVersion()
        guard UpdateChecker.isNewer(release.version, than: current) else {
            if manual { status("You're up to date (v\(current))") }
            return
        }

        guard let dmgURL = release.dmgURL else {
            // No .dmg asset — fall back to the release page.
            status("Update v\(release.version) available")
            if let page = URL(string: "https://github.com/sashabedard/WhisperDict/releases/latest") {
                NSWorkspace.shared.open(page)
            }
            return
        }

        status("Downloading update v\(release.version)…")
        if let fileURL = await download(dmgURL, version: release.version) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            status("Update v\(release.version) downloaded → Finder")
        } else {
            status("Update v\(release.version) found — download failed")
        }
    }

    /// Downloads `url` to ~/Downloads/WhisperDict-<version>.dmg, overwriting an
    /// existing file. Returns the local URL, or nil on failure.
    private func download(_ url: URL, version: String) async -> URL? {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let dest = downloads.appendingPathComponent("WhisperDict-\(version).dmg")
        guard let (tmp, response) = try? await URLSession.shared.download(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: tmp, to: dest)
            return dest
        } catch {
            return nil
        }
    }
}

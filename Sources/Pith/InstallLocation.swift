// Pith — on-device push-to-talk dictation for macOS
// Copyright (C) 2026 Sasha Bédard
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import AppKit

/// Detects whether the app is running from outside /Applications (so we can
/// nudge a downloaded copy into place) and performs the move. Keyed on the
/// install location — the one signal that survives launch — rather than the
/// quarantine attribute, which macOS strips the moment it approves the app.
enum InstallLocation {
    static var bundleURL: URL { Bundle.main.bundleURL }
    private static var path: String { Bundle.main.bundlePath }

    static var isInApplications: Bool {
        let apps = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        return path.hasPrefix("/Applications/") || path.hasPrefix(apps + "/")
    }

    /// Prompt to move whenever the app isn't already in an Applications folder.
    /// Only ever shown during first-launch onboarding, so normal use isn't nagged.
    static var shouldPromptMove: Bool {
        !isInApplications
    }

    /// Copies the running bundle to /Applications, then relaunches the copy from
    /// a detached shell that waits for this instance to exit (launching a second
    /// instance of the same bundle id from the dying process is unreliable).
    /// Returns false on failure (e.g. no write permission) so the caller can
    /// fall back to revealing in Finder.
    @MainActor
    @discardableResult
    static func moveToApplicationsAndRelaunch() -> Bool {
        let dest = URL(fileURLWithPath: "/Applications").appendingPathComponent(bundleURL.lastPathComponent)
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: bundleURL, to: dest)
        } catch {
            return false
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        /usr/bin/xattr -dr com.apple.quarantine "\(dest.path)" 2>/dev/null
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done
        /usr/bin/open "\(dest.path)"
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        do { try task.run() } catch { return false }

        NSApp.terminate(nil)
        return true
    }

    @MainActor
    static func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }
}

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

import Foundation

/// How the app was installed — used so the in-app updater doesn't fight another
/// update manager (Homebrew). When Homebrew manages the app, the updater defers
/// to `brew upgrade` instead of downloading a .dmg that would desync brew.
enum InstallSource {
    /// Homebrew Caskroom locations to probe. Overridable in tests.
    static var caskroomPaths = [
        "/opt/homebrew/Caskroom/pith",   // Apple Silicon
        "/usr/local/Caskroom/pith",       // Intel
    ]

    /// True when the app lives in a Homebrew Cask install.
    static func isHomebrewManaged() -> Bool {
        caskroomPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }
}

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
import ServiceManagement

/// "Open at login" via SMAppService (macOS 13+). The system is the source of
/// truth — no UserDefaults mirror to drift out of sync.
///
/// Note: registration only persists for a signed app in /Applications (the
/// notarized / Homebrew build), not a dev binary run from the build folder.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Apply the desired state. Returns false (and logs) on failure so the UI can
    /// re-sync to the real status.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, let s) where s != .enabled:
                try SMAppService.mainApp.register()
            case (false, .enabled):
                try SMAppService.mainApp.unregister()
            default:
                break   // already in the desired state
            }
            return true
        } catch {
            NSLog("Pith: login item toggle failed: %@", String(describing: error))
            return false
        }
    }
}

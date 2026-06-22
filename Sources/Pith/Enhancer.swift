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

struct EnhanceResult: Sendable { let text: String; let warning: String? }

/// Façade over the Enhance backends. AppDelegate/Preferences call this; it picks
/// the active backend per UserSettings and falls back Apple → raw.
actor Enhancer {
    static let warningText = "Enhance endpoint failed"

    private let apple: EnhanceBackend
    /// Returns a chosen+ready BYOK backend, or nil. Injected for tests; default
    /// reads UserSettings + Keychain.
    private let byokProvider: @Sendable () -> EnhanceBackend?

    init(apple: EnhanceBackend = AppleEnhanceBackend(),
         byokProvider: @Sendable @escaping () -> EnhanceBackend? = Enhancer.settingsByok) {
        self.apple = apple
        self.byokProvider = byokProvider
    }

    /// The Apple-specific availability, for the "enable Apple Intelligence" nudge.
    static var availabilityState: EnhanceAvailability { AppleEnhanceBackend.availabilityState }

    /// True when SOME backend can run: Apple available, or BYOK configured.
    static var isAvailable: Bool {
        if AppleEnhanceBackend.isAvailable { return true }
        return settingsByok() != nil
    }

    /// Build the BYOK backend from settings, or nil if not selected/ready.
    static func settingsByok() -> EnhanceBackend? {
        guard UserSettings.shared.enhanceBackend == "openai" else { return nil }
        let b = OpenAICompatibleEnhanceBackend(
            endpoint: UserSettings.shared.openAIEndpoint,
            model: UserSettings.shared.openAIModel,
            apiKey: KeychainStore().get("apiKey") ?? "")
        return b.isReady ? b : nil
    }

    func warmup() async {
        if byokProvider() != nil { return }
        await apple.warmup()
    }

    func enhance(_ raw: String, style: EnhanceStyle = .faithful, vocabulary: [String] = [],
                 profile: String = "", formatLists: Bool = false) async -> EnhanceResult {
        await dispatch(raw: raw) { await $0.enhance(raw, style: style, vocabulary: vocabulary,
                                                    profile: profile, formatLists: formatLists) }
    }

    func runCommand(instruction: String, on text: String) async -> EnhanceResult {
        await dispatch(raw: text) { await $0.runCommand(instruction: instruction, on: text) }
    }

    private func dispatch(raw: String, _ run: (EnhanceBackend) async -> String?) async -> EnhanceResult {
        if let byok = byokProvider(), byok.isReady {
            if let out = await run(byok) { return EnhanceResult(text: out, warning: nil) }
            if apple.isReady, let out = await run(apple) { return EnhanceResult(text: out, warning: Self.warningText) }
            return EnhanceResult(text: raw, warning: Self.warningText)
        }
        if apple.isReady, let out = await run(apple) { return EnhanceResult(text: out, warning: nil) }
        return EnhanceResult(text: raw, warning: nil)
    }
}

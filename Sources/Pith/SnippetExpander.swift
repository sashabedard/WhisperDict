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

/// Expands spoken trigger phrases into canned text (e.g. "my email" → an address).
/// Case-insensitive, whole-word matching; longer triggers win over shorter ones
/// they contain. Applied after Enhance so the model can't reword an expansion.
enum SnippetExpander {
    static func expand(_ text: String, snippets: [(trigger: String, expansion: String)]) -> String {
        guard !text.isEmpty, !snippets.isEmpty else { return text }
        var result = text
        for (trigger, expansion) in snippets.sorted(by: { $0.trigger.count > $1.trigger.count }) {
            let t = trigger.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: t) + "\\b"
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(
                in: result, options: [], range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: expansion)
            )
        }
        return result
    }
}

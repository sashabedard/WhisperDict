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

/// Conservative, on-device transcript cleanup used when the AI Enhance step did
/// not run. Removes only unambiguous vocalized pauses (um, uh, euh…) as whole
/// words — never real words — so it can never change meaning.
enum TextCleanup {
    private static let english = ["umm", "uhh", "uhm", "um", "uh", "erm", "er"]
    private static let french  = ["heum", "euh", "heu"]

    /// Strips standalone filler pauses (whole-word, case-insensitive), collapses
    /// the spaces left behind, tidies space-before-punctuation, trims, and
    /// restores leading capitalization. Returns the input unchanged when nothing
    /// matches or the result would be empty.
    static func stripFillers(_ text: String, language: String) -> String {
        let fillers: [String]
        switch language {
        case "en": fillers = english
        case "fr": fillers = french
        default:   fillers = english + french
        }
        // Longest first so "umm" is tried before "um".
        let alternation = fillers
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        guard let regex = try? NSRegularExpression(
            pattern: "\\b(?:\(alternation))\\b", options: [.caseInsensitive]) else { return text }

        let full = NSRange(text.startIndex..., in: text)
        var out = regex.stringByReplacingMatches(in: text, range: full, withTemplate: "")
        out = out.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: " ([,.!?;:])", with: "$1", options: .regularExpression)
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedOriginal = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstOrig = trimmedOriginal.first, firstOrig.isUppercase,
           let firstOut = out.first, firstOut.isLowercase {
            out.replaceSubrange(out.startIndex...out.startIndex, with: String(firstOut).uppercased())
        }
        return out.isEmpty ? text : out
    }
}

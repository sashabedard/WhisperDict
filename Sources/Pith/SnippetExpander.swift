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

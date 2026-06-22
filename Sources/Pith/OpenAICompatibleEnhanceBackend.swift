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

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    init() {
        // Dedicated session with HARD timeouts. URLSession.shared defaults
        // timeoutIntervalForResource to 7 days, so a slow/held connection can
        // hang ~forever — this caps the whole request at 30s.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// BYOK Enhance engine: any OpenAI-compatible /chat/completions endpoint
/// (local Ollama/LM Studio or cloud OpenRouter/OpenAI/Groq). Returns nil on any
/// failure so the façade falls back.
actor OpenAICompatibleEnhanceBackend: EnhanceBackend {
    private let endpoint: String
    private let model: String
    private let apiKey: String
    private let transport: HTTPTransport

    init(endpoint: String, model: String, apiKey: String, transport: HTTPTransport = URLSessionTransport()) {
        self.endpoint = endpoint.trimmingCharacters(in: .whitespaces)
        self.model = model.trimmingCharacters(in: .whitespaces)
        self.apiKey = apiKey.trimmingCharacters(in: .whitespaces)
        self.transport = transport
    }

    nonisolated var isReady: Bool {
        !endpoint.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func warmup() async {}

    func enhance(_ raw: String, style: EnhanceStyle, vocabulary: [String],
                 profile: String, formatLists: Bool) async -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isReady else { return nil }
        return await chat(system: EnhancePrompt.instructions(style: style, formatLists: formatLists),
                          user: EnhancePrompt.userPrompt(dictation: trimmed, vocabulary: vocabulary, profile: profile))
    }

    func runCommand(instruction: String, on text: String) async -> String? {
        let inst = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inst.isEmpty, !text.isEmpty, isReady else { return nil }
        return await chat(system: EnhancePrompt.commandInstructions,
                          user: EnhancePrompt.commandUserPrompt(instruction: inst, on: text))
    }

    private func chat(system: String, user: String) async -> String? {
        guard let url = URL(string: endpoint.hasSuffix("/") ? endpoint + "chat/completions"
                                                            : endpoint + "/chat/completions") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        var payload: [String: Any] = [
            "model": model,
            "temperature": 0,
            "messages": [["role": "system", "content": system],
                         ["role": "user", "content": user]],
        ]
        // OpenRouter only: enforce Zero Data Retention so the prompt is never
        // stored. Other OpenAI-compatible servers would reject an unknown
        // "provider" field, so gate it on the OpenRouter host.
        if endpoint.lowercased().contains("openrouter.ai") {
            payload["provider"] = ["zdr": true]
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        req.httpBody = body
        do {
            let (data, response) = try await transport.send(req)
            guard (200..<300).contains(response.statusCode) else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else { return nil }
            let out = Self.stripPreamble(content).trimmingCharacters(in: .whitespacesAndNewlines)
            return out.isEmpty ? nil : out
        } catch { return nil }
    }

    /// Defensive cleanup for chatty BYOK models that ignore the "no preamble"
    /// instruction in the shared prompt. Arbitrary OpenAI-compatible models can't
    /// be trusted, so we strip the wrappers seen in practice as a backstop:
    ///   - llama: a "Here's the revised text:" preamble on its own line.
    ///   - mistral-nemo / gemma: a stray leading "- " bullet on a one-line answer.
    /// Guiding rule: the dictation is the user's own words, so when unsure we KEEP
    /// the text. Each strip is gated on a signal real content won't trip.
    static func stripPreamble(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Unwrap a fully-fenced reply: ```...``` or ```text\n...\n```.
        if text.hasPrefix("```"), let close = text.range(of: "```", options: .backwards),
           close.lowerBound > text.startIndex {
            let afterTag = text.firstIndex(where: \.isNewline).map { text.index(after: $0) }
                ?? close.lowerBound
            if afterTag < close.lowerBound {
                text = String(text[afterTag..<close.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 2. Phi-style chain-of-thought: the model narrates each fix as a numbered
        //    list, then ends with "…the cleaned text is:\n\n<text>". Keep only what
        //    follows the LAST result marker. Keyword-gated so ordinary dictation
        //    (which won't contain these phrases) is never truncated.
        let resultMarkers = ["cleaned text is:", "cleaned dictation is:",
                             "cleaned-up text is:", "cleaned up text is:",
                             "texte corrigé est :", "texte corrigé est:",
                             "texte nettoyé est :", "texte nettoyé est:"]
        for marker in resultMarkers {
            if let r = text.range(of: marker, options: [.caseInsensitive, .backwards]) {
                let tail = String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty { text = tail; break }
            }
        }

        // 3. Drop a leading preamble line (llama). The signal is the preamble on
        //    its own line — typically followed by a full blank line — before the
        //    real text. Only strip when that first line opens with a known
        //    preamble phrase, so a genuine first line is never eaten.
        if let firstBreak = text.firstIndex(where: \.isNewline) {
            let head = String(text[..<firstBreak]).trimmingCharacters(in: .whitespaces)
            let body = String(text[text.index(after: firstBreak)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty, isPreambleLine(head) { text = body }
        }

        // 4. Drop a stray leading bullet (mistral-nemo, gemma) — but ONLY when the
        //    whole answer is a single line, so genuine multi-item lists (which the
        //    list-formatting mode produces) keep their bullets.
        if !text.contains(where: \.isNewline) {
            for marker in ["- ", "* ", "• "] where text.hasPrefix(marker) {
                text = String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // 5. Drop a trailing explanation paragraph. Some models put the answer
        //    first (often quoted), then add a meta-commentary paragraph like
        //    "This text maintains the speaker's language…". Strip trailing
        //    paragraphs that open with a known meta phrase, as long as a real
        //    answer paragraph survives above them. Keyword-gated, so a genuine
        //    final paragraph of the dictation is never removed.
        var paragraphs = text.components(separatedBy: "\n\n")
        while paragraphs.count > 1, isMetaCommentary(paragraphs[paragraphs.count - 1]) {
            paragraphs.removeLast()
        }
        text = paragraphs.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)

        // 6. Unwrap surrounding quotes if the model quoted the whole output.
        for (open, close) in [("\"", "\""), ("«", "»"), ("\u{201C}", "\u{201D}")]
        where text.hasPrefix(open) && text.hasSuffix(close)
            && text.count > open.count + close.count {
            text = String(text.dropFirst(open.count).dropLast(close.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        return text
    }

    /// True when `paragraph` is trailing model meta-commentary like "This text
    /// maintains the speaker's language…" — an explanation the model appends after
    /// the real answer. Keyword-gated on phrases real dictation won't open a
    /// trailing paragraph with (deliberately NOT "I have…"/"J'ai…", which are
    /// common in genuine speech).
    private static func isMetaCommentary(_ paragraph: String) -> Bool {
        let p = paragraph.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let openers = ["this text", "this version", "this maintains", "this keeps",
                       "this preserves", "this removes", "this ensures", "this cleaned",
                       "this is the cleaned", "the revised text", "the cleaned text",
                       "the above text", "note:", "note that this", "explanation:",
                       "by removing", "ce texte", "cette version", "cette phrase",
                       "le texte ci-dessus", "j'ai supprimé", "j'ai retiré"]
        return openers.contains { p.hasPrefix($0) }
    }

    /// True when `line` is a model preamble like "Here's the revised text:" —
    /// a short single line opening with a known filler phrase. Deliberately
    /// keyword-gated (not just "ends with :") so a real dictated line such as
    /// "Trois choses :" is never mistaken for preamble.
    private static func isPreambleLine(_ line: String) -> Bool {
        guard !line.contains(where: \.isNewline), line.count <= 80 else { return false }
        let lower = line.lowercased()
        let openers = ["here's", "here\u{2019}s", "here is", "here are", "sure",
                       "certainly", "of course", "voici", "voilà", "bien sûr",
                       "i've", "i have", "j'ai"]
        return openers.contains { lower.hasPrefix($0) }
    }
}

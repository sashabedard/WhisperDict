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
            let out = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return out.isEmpty ? nil : out
        } catch { return nil }
    }
}

import Foundation

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
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
        let payload: [String: Any] = [
            "model": model,
            "temperature": 0,
            "messages": [["role": "system", "content": system],
                         ["role": "user", "content": user]],
        ]
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

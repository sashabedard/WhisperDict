import WhisperKit

struct Transcription {
    let text: String
    let language: String
}

actor Transcriber {
    private var pipe: WhisperKit?
    private var loadedModel = ""

    func warmup() async throws {
        let model = UserSettings.shared.modelName
        guard pipe == nil || loadedModel != model else { return }
        pipe = nil
        loadedModel = model
        let config = WhisperKitConfig(model: model)
        pipe = try await WhisperKit(config)
    }

    func reset() {
        pipe = nil
        loadedModel = ""
    }

    /// Languages allowed in "auto" mode. Constraining detection to these stops
    /// Whisper from tagging short/noisy dictation clips as random languages.
    private let autoLanguages = ["en", "fr"]

    /// Resolves which language to force. For a specific setting, use it. For
    /// "auto", run Whisper's language detector but pick the most probable of
    /// `autoLanguages` only — so the result is always English or French, never
    /// Welsh or Maori on a half-second clip.
    private func resolveLanguage(_ setting: String, audio: [Float], pipe: WhisperKit) async -> String {
        guard setting == "auto" else { return setting }
        guard let probs = try? await pipe.detectLangauge(audioArray: audio).langProbs else {
            return autoLanguages.first ?? "en"
        }
        return autoLanguages.max {
            (probs[$0] ?? -.greatestFiniteMagnitude) < (probs[$1] ?? -.greatestFiniteMagnitude)
        } ?? "en"
    }

    func transcribe(_ audio: [Float]) async -> Transcription {
        guard audio.count > 3_200 else { return Transcription(text: "", language: "") }
        do {
            try await warmup()
            guard let pipe else { return Transcription(text: "", language: "") }
            let setting = UserSettings.shared.language
            let language = await resolveLanguage(setting, audio: audio, pipe: pipe)
            let options = DecodingOptions(
                task: .transcribe,            // never translate — keep speech in its own language
                language: language,           // always forced; resolved below
                temperature: 0.0,
                usePrefillPrompt: true,       // inject <|lang|><|transcribe|> tokens
                detectLanguage: false         // we resolve the language ourselves
            )
            let results = try await pipe.transcribe(audioArray: audio, decodeOptions: options)
            let text = results.map { $0.text }.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Transcription(text: text, language: language)
        } catch {
            print("WhisperKit error: \(error)")
            return Transcription(text: "", language: "")
        }
    }
}

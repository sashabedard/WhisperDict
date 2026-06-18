import WhisperKit

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

    func transcribe(_ audio: [Float]) async -> String {
        guard audio.count > 3_200 else { return "" }
        do {
            try await warmup()
            guard let pipe else { return "" }
            let lang = UserSettings.shared.language
            let isAuto = (lang == "auto")
            let options = DecodingOptions(
                task: .transcribe,            // never translate — keep speech in its own language
                language: isAuto ? nil : lang,
                temperature: 0.0,
                usePrefillPrompt: true,       // actually inject <|lang|><|transcribe|> tokens
                detectLanguage: isAuto        // auto-detect per utterance only in Auto mode
            )
            let results = try await pipe.transcribe(audioArray: audio, decodeOptions: options)
            return results.map { $0.text }.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("WhisperKit error: \(error)")
            return ""
        }
    }
}

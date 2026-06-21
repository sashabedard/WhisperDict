import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
/// Guided-generation output. Markdown is disallowed EXCEPT a plain "- " bullet
/// list (the instructions opt into it per-app), otherwise the schema would veto
/// the list formatting.
@available(macOS 26.0, *)
@Generable
private struct CleanedDictation {
    @Guide(description: "The cleaned dictation text only, in the SAME language as the input, with no preamble and no quotes. No markdown, EXCEPT a plain \"- \" bulleted list (one item per line) when the instructions ask for list formatting.")
    var text: String
}
#endif

/// Apple's on-device FoundationModels engine — the zero-download default.
actor AppleEnhanceBackend: EnhanceBackend {

    static var isAvailable: Bool { availabilityState == .available }

    static var availabilityState: EnhanceAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(.appleIntelligenceNotEnabled): return .needsAppleIntelligence
            default: return .unsupported
            }
        }
        #endif
        return .unsupported
    }

    nonisolated var isReady: Bool { Self.isAvailable }

    func warmup() async {
        #if canImport(FoundationModels)
        guard Self.isAvailable else { return }
        if #available(macOS 26.0, *) {
            let session = LanguageModelSession(instructions: EnhancePrompt.instructions(style: .faithful, formatLists: false))
            _ = try? await session.respond(to: "warmup", generating: CleanedDictation.self)
        }
        #endif
    }

    func enhance(_ raw: String, style: EnhanceStyle, vocabulary: [String],
                 profile: String, formatLists: Bool) async -> String? {
        #if canImport(FoundationModels)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Self.isAvailable else { return nil }
        if #available(macOS 26.0, *) {
            let session = LanguageModelSession(instructions: EnhancePrompt.instructions(style: style, formatLists: formatLists))
            let prompt = EnhancePrompt.userPrompt(dictation: trimmed, vocabulary: vocabulary, profile: profile)
            do {
                let response = try await session.respond(
                    to: prompt, generating: CleanedDictation.self,
                    options: GenerationOptions(temperature: 0.0))
                let out = response.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return out.isEmpty ? nil : out
            } catch { return nil }
        }
        #endif
        return nil
    }

    func runCommand(instruction: String, on text: String) async -> String? {
        #if canImport(FoundationModels)
        let inst = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inst.isEmpty, !text.isEmpty, Self.isAvailable else { return nil }
        if #available(macOS 26.0, *) {
            let session = LanguageModelSession(instructions: EnhancePrompt.commandInstructions)
            let prompt = EnhancePrompt.commandUserPrompt(instruction: inst, on: text)
            do {
                let response = try await session.respond(
                    to: prompt, generating: CleanedDictation.self,
                    options: GenerationOptions(temperature: 0.0))
                let out = response.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return out.isEmpty ? nil : out
            } catch { return nil }
        }
        #endif
        return nil
    }
}

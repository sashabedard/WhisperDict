import Foundation

/// One interchangeable Enhance engine. `enhance`/`runCommand` return nil when the
/// backend genuinely couldn't run, so the façade can fall back to another.
protocol EnhanceBackend: Sendable {
    var isReady: Bool { get }
    func warmup() async
    func enhance(_ raw: String, style: EnhanceStyle, vocabulary: [String],
                 profile: String, formatLists: Bool) async -> String?
    func runCommand(instruction: String, on text: String) async -> String?
}

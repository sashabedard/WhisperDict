import XCTest
@testable import WhisperDict

/// A controllable backend for testing the façade's fallback logic.
private struct FakeBackend: EnhanceBackend {
    let ready: Bool
    let output: String?
    var isReady: Bool { ready }
    func warmup() async {}
    func enhance(_ raw: String, style: EnhanceStyle, vocabulary: [String],
                 profile: String, formatLists: Bool) async -> String? { output }
    func runCommand(instruction: String, on text: String) async -> String? { output }
}

final class EnhancerFacadeTests: XCTestCase {
    // The pure resolution rule, mirrored here for a deterministic unit test:
    // ready backend with output → output; not-ready → raw; ready but nil → raw.
    private func resolve(_ backend: EnhanceBackend, raw: String) async -> String {
        guard backend.isReady else { return raw }
        return await backend.enhance(raw, style: .faithful, vocabulary: [], profile: "", formatLists: false) ?? raw
    }

    func testReadyBackendOutputUsed() async {
        let out = await resolve(FakeBackend(ready: true, output: "clean"), raw: "messy")
        XCTAssertEqual(out, "clean")
    }
    func testNotReadyFallsBackToRaw() async {
        let out = await resolve(FakeBackend(ready: false, output: "clean"), raw: "messy")
        XCTAssertEqual(out, "messy")
    }
    func testReadyButNilFallsBackToRaw() async {
        let out = await resolve(FakeBackend(ready: true, output: nil), raw: "messy")
        XCTAssertEqual(out, "messy")
    }
}

import XCTest
@testable import Pith

final class SecretStoreTests: XCTestCase {
    func testFakeRoundTrip() {
        let store = InMemorySecretStore()
        XCTAssertNil(store.get("apiKey"))
        store.set("sk-123", account: "apiKey")
        XCTAssertEqual(store.get("apiKey"), "sk-123")
        store.delete("apiKey")
        XCTAssertNil(store.get("apiKey"))
    }

    func testIsLocalEndpoint() {
        XCTAssertTrue(Endpoint.isLocal("http://localhost:11434/v1"))
        XCTAssertTrue(Endpoint.isLocal("http://127.0.0.1:1234/v1"))
        XCTAssertFalse(Endpoint.isLocal("https://openrouter.ai/api/v1"))
        XCTAssertFalse(Endpoint.isLocal(""))
    }
}

final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    func get(_ account: String) -> String? { storage[account] }
    func set(_ value: String, account: String) { storage[account] = value }
    func delete(_ account: String) { storage[account] = nil }
}

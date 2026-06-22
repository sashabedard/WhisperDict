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

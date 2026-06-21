import Foundation
import Security

protocol SecretStore: Sendable {
    func get(_ account: String) -> String?
    func set(_ value: String, account: String)
    func delete(_ account: String)
}

struct KeychainStore: SecretStore {
    static let service = "com.sasha.pith.byok"

    func get(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let s = String(data: data, encoding: .utf8)
        else { return nil }
        return s
    }

    func set(_ value: String, account: String) {
        delete(account)
        guard !value.isEmpty else { return }
        var query = baseQuery(account)
        query[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: account]
    }
}

enum Endpoint {
    static func isLocal(_ urlString: String) -> Bool {
        guard let host = URLComponents(string: urlString)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

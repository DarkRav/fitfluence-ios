import Foundation
import Security

protocol AppleCredentialUserStore: Sendable {
    func loadUserIdentifier() throws -> String?
    func saveUserIdentifier(_ userIdentifier: String) throws
    func clearUserIdentifier() throws
}

final class KeychainAppleCredentialUserStore: AppleCredentialUserStore {
    private let service: String
    private let account: String

    init(service: String = "com.fitfluence.ios.auth", account: String = "apple_user_identifier") {
        self.service = service
        self.account = account
    }

    func loadUserIdentifier() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw TokenStoreError.keychain(status: status)
        }

        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw TokenStoreError.decodingFailed
        }

        return value.isEmpty ? nil : value
    }

    func saveUserIdentifier(_ userIdentifier: String) throws {
        let normalized = userIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = normalized.data(using: .utf8), !normalized.isEmpty else {
            throw TokenStoreError.encodingFailed
        }

        var query = baseQuery
        query[kSecValueData as String] = data

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let attributesToUpdate = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw TokenStoreError.keychain(status: updateStatus)
            }
            return
        }

        guard addStatus == errSecSuccess else {
            throw TokenStoreError.keychain(status: addStatus)
        }
    }

    func clearUserIdentifier() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.keychain(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

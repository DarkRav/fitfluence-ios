import Foundation
import Security

protocol TokenStore: Sendable {
    func load() throws -> TokenSet?
    func save(_ tokenSet: TokenSet) throws
    func clear() throws
}

enum TokenStoreError: Error {
    case encodingFailed
    case decodingFailed
    case keychain(status: OSStatus)
}

final class KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    init(service: String = "com.fitfluence.ios.auth", account: String = "token_set") {
        self.service = service
        self.account = account
    }

    func load() throws -> TokenSet? {
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

        guard let data = item as? Data else {
            throw TokenStoreError.decodingFailed
        }

        do {
            return try JSONDecoder().decode(TokenSet.self, from: data)
        } catch {
            throw TokenStoreError.decodingFailed
        }
    }

    func save(_ tokenSet: TokenSet) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(tokenSet)
        } catch {
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

    func clear() throws {
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

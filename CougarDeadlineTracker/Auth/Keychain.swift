import Foundation
import Security

/// Thin wrapper over the iOS keychain. Every secret in this app — the Canvas
/// token and the Learning Suite session cookies — lives here and nowhere else.
/// Nothing secret is ever written to UserDefaults or to a file.
struct Keychain {
    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
                return "Keychain error: \(message)"
            }
        }
    }

    /// Namespaced per app so a reinstall of another target cannot collide.
    let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.cougardeadlines.app") {
        self.service = service
    }

    func setData(_ data: Data, for account: String) throws {
        var query = baseQuery(for: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Available after first unlock so a background refresh can read the
            // token, but never synced to iCloud or included in a backup.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            query.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func data(for account: String) throws -> Data? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func setString(_ string: String, for account: String) throws {
        try setData(Data(string.utf8), for: account)
    }

    func string(for account: String) throws -> String? {
        guard let data = try data(for: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setValue<T: Encodable>(_ value: T, for account: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try setData(try encoder.encode(value), for: account)
    }

    func value<T: Decodable>(_ type: T.Type, for account: String) throws -> T? {
        guard let data = try data(for: account) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    func remove(_ account: String) throws {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    enum Account {
        static let canvasToken = "canvas.accessToken"
        static let learningSuiteSession = "learningSuite.session"
    }
}

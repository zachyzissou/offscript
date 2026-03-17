import Foundation
import Security

enum UserProfileService {
    private static let serviceName = "com.offscript.apple-id"
    private static let userIDKey = "userIdentifier"
    private static let displayNameKey = "offscript.displayName"

    static var currentUserID: String? {
        readKeychain(account: userIDKey)
    }

    static var displayName: String? {
        get { UserDefaults.standard.string(forKey: displayNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: displayNameKey) }
    }

    static func saveCredential(userID: String, displayName: String?) throws {
        try writeKeychain(account: userIDKey, value: userID)
        if let displayName {
            self.displayName = displayName
        }
    }

    static func deleteCredential() {
        deleteKeychain(account: userIDKey)
        UserDefaults.standard.removeObject(forKey: displayNameKey)
    }

    private static func writeKeychain(account: String, value: String) throws {
        let data = Data(value.utf8)
        deleteKeychain(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    private static func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error {
        case unhandled(OSStatus)
    }
}

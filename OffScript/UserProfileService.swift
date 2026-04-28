import Foundation
import Security

enum UserProfileService {
    private static let serviceName = "com.offscript.apple-id"
    private static let userIDKey = "userIdentifier"
    private static let displayNameKey = "offscript.displayName"
    #if DEBUG
    private static let debugUserIDFallbackKey = "offscript.debug.keychainFallback.userIdentifier"
    #endif

    static var currentUserID: String? {
        #if DEBUG
        readKeychain(account: userIDKey) ?? UserDefaults.standard.string(forKey: debugUserIDFallbackKey)
        #else
        readKeychain(account: userIDKey)
        #endif
    }

    static var displayName: String? {
        get { UserDefaults.standard.string(forKey: displayNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: displayNameKey) }
    }

    static func saveCredential(userID: String, displayName: String?) throws {
        do {
            try writeKeychain(account: userIDKey, value: userID)
            #if DEBUG
            UserDefaults.standard.removeObject(forKey: debugUserIDFallbackKey)
            #endif
        } catch KeychainError.unhandled(errSecMissingEntitlement) {
            #if DEBUG
            // Simulator/unit-test hosts can fail Keychain writes with
            // -34018 even when the app target is configured correctly. Keep
            // production strict, but let DEBUG tests exercise profile
            // round-tripping without requiring a signed app-host keychain.
            UserDefaults.standard.set(userID, forKey: debugUserIDFallbackKey)
            #else
            throw KeychainError.unhandled(errSecMissingEntitlement)
            #endif
        }
        if let displayName {
            self.displayName = displayName
        }
    }

    static func deleteCredential() {
        deleteKeychain(account: userIDKey)
        #if DEBUG
        UserDefaults.standard.removeObject(forKey: debugUserIDFallbackKey)
        #endif
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

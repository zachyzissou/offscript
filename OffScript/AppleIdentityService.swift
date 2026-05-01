import AuthenticationServices
import CloudKit
import Foundation
import OSLog

private let appleIdentityLogger = Logger(subsystem: "com.offscript", category: "AppleIdentity")

enum AppleCredentialValidationState: Equatable {
    case signedOut
    case authorized
    case revoked
    case notFound
    case transferred
    case unknown

    var isAuthorized: Bool {
        self == .authorized || self == .transferred
    }

    var displayText: String {
        switch self {
        case .signedOut: "APPLE ID · SIGNED OUT"
        case .authorized: "APPLE ID · VERIFIED"
        case .revoked: "APPLE ID · REVOKED"
        case .notFound: "APPLE ID · NOT FOUND"
        case .transferred: "APPLE ID · TRANSFERRED"
        case .unknown: "APPLE ID · UNKNOWN"
        }
    }

    var shortLabel: String {
        switch self {
        case .signedOut: "SIGNED OUT"
        case .authorized: "VERIFIED"
        case .revoked: "REVOKED"
        case .notFound: "NOT FOUND"
        case .transferred: "TRANSFERRED"
        case .unknown: "UNKNOWN"
        }
    }
}

enum CloudKitAccountAvailability: Equatable {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable
    case notConfigured

    var allowsSync: Bool {
        self == .available
    }

    var displayText: String {
        switch self {
        case .available: "ICLOUD · AVAILABLE"
        case .noAccount: "ICLOUD · NO ACCOUNT"
        case .restricted: "ICLOUD · RESTRICTED"
        case .couldNotDetermine: "ICLOUD · UNKNOWN"
        case .temporarilyUnavailable: "ICLOUD · TEMPORARY ISSUE"
        case .notConfigured: "ICLOUD · NOT CONFIGURED"
        }
    }

    var shortLabel: String {
        switch self {
        case .available: "AVAILABLE"
        case .noAccount: "NO ACCOUNT"
        case .restricted: "RESTRICTED"
        case .couldNotDetermine: "UNKNOWN"
        case .temporarilyUnavailable: "TEMP ISSUE"
        case .notConfigured: "NOT CONFIG"
        }
    }
}

enum AppleIdentityService {
    static func validateStoredCredential() async -> AppleCredentialValidationState {
        guard let userID = AppSettings.currentUserID else { return .signedOut }
        let state = await credentialState(for: userID)
        if state == .revoked || state == .notFound {
            AppSettings.clearCredential()
            AppSettings.cloudSyncEnabled = false
        }
        return state
    }

    static func credentialState(for userID: String) async -> AppleCredentialValidationState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, error in
                guard error == nil else {
                    continuation.resume(returning: .unknown)
                    return
                }

                switch state {
                case .authorized:
                    continuation.resume(returning: .authorized)
                case .revoked:
                    continuation.resume(returning: .revoked)
                case .notFound:
                    continuation.resume(returning: .notFound)
                case .transferred:
                    continuation.resume(returning: .transferred)
                @unknown default:
                    continuation.resume(returning: .unknown)
                }
            }
        }
    }
}

enum CloudKitAccountService {
    static func currentStatus() async -> CloudKitAccountAvailability {
        guard hasCloudKitEntitlement else { return .notConfigured }

        do {
            let status = try await CKContainer.default().accountStatus()
            switch status {
            case .available:
                return .available
            case .noAccount:
                return .noAccount
            case .restricted:
                return .restricted
            case .couldNotDetermine:
                return .couldNotDetermine
            case .temporarilyUnavailable:
                return .temporarilyUnavailable
            @unknown default:
                return .couldNotDetermine
            }
        } catch {
            return .couldNotDetermine
        }
    }

    static func entitlementsAllowCloudKitAccountStatus(
        services: Any?,
        containerIdentifiers: Any?
    ) -> Bool {
        guard let services = services as? [String],
              services.contains("CloudKit"),
              let containerIdentifiers = containerIdentifiers as? [String] else {
            return false
        }
        return !containerIdentifiers.isEmpty
    }

    private static var hasCloudKitEntitlement: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard let entitlements = embeddedProvisioningProfileEntitlements else { return false }
        return entitlementsAllowCloudKitAccountStatus(
            services: entitlements["com.apple.developer.icloud-services"],
            containerIdentifiers: entitlements["com.apple.developer.icloud-container-identifiers"]
        )
        #endif
    }

    private static var embeddedProvisioningProfileEntitlements: [String: Any]? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            appleIdentityLogger.warning("embedded.mobileprovision read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let rawProfile = String(data: data, encoding: .isoLatin1),
              let plistStart = rawProfile.range(of: "<plist"),
              let plistEnd = rawProfile.range(of: "</plist>", options: .backwards) else {
            return nil
        }

        let plistText = String(rawProfile[plistStart.lowerBound..<plistEnd.upperBound])
        guard let plistData = plistText.data(using: .utf8) else { return nil }
        let plistObject: Any
        do {
            plistObject = try PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
            )
        } catch {
            appleIdentityLogger.warning("embedded.mobileprovision plist parse failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let profile = plistObject as? [String: Any] else { return nil }
        return profile["Entitlements"] as? [String: Any]
    }
}

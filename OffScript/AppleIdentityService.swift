import AuthenticationServices
import CloudKit
import Foundation

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
}

enum CloudKitAccountAvailability: Equatable {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable

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
        }
    }
}

enum AppleIdentityService {
    static func validateStoredCredential() async -> AppleCredentialValidationState {
        guard let userID = AppSettings.currentUserID else { return .signedOut }
        let state = await credentialState(for: userID)
        if !state.isAuthorized {
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
}

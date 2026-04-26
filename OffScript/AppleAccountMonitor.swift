import AuthenticationServices
import Foundation
import OSLog

/// Watches the user's Apple ID credential state. If the user revokes Sign in
/// with Apple consent (Settings → Apple ID → Password & Security → Apps Using
/// Apple ID), this clears the local credential and disables iCloud sync so the
/// app falls back gracefully on next launch.
@MainActor
final class AppleAccountMonitor {
    static let shared = AppleAccountMonitor()

    private let logger = Logger(subsystem: "OffScript", category: "AppleAccount")

    private init() {}

    func validateOnLaunch() async {
        guard let userID = AppSettings.currentUserID else { return }

        let state: ASAuthorizationAppleIDProvider.CredentialState? = await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                continuation.resume(returning: state)
            }
        }

        guard let state else { return }
        handle(state: state)
    }

    private func handle(state: ASAuthorizationAppleIDProvider.CredentialState) {
        switch state {
        case .authorized:
            logger.debug("Apple ID still authorized")
        case .revoked, .notFound:
            logger.info("Apple ID credential no longer valid — clearing local state")
            AppSettings.clearCredential()
            AppSettings.cloudSyncEnabled = false
            AppSettings.lastCloudSyncDate = nil
        case .transferred:
            logger.info("Apple ID credential transferred")
        @unknown default:
            break
        }
    }
}

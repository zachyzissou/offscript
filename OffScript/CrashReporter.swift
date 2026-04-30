import Foundation
import OSLog
import Sentry
import StoreKit

enum SentryEnvironmentResolver {
    static let cacheKey = "offscript.sentryEnvironment"

    static func sentryEnvironment(storeKitEnvironmentRawValue rawValue: String) -> String {
        switch rawValue.lowercased() {
        case "sandbox":
            return "testflight"
        case "xcode":
            return "debug"
        case "production":
            return "production"
        default:
            return "production"
        }
    }
}

/// Quota-aware Sentry initializer.
///
/// We pay per-event on Sentry, so we lock the SDK into "errors only" mode:
///
/// - `tracesSampleRate: 0.05` — only 5% of view-transition / network spans
///   reach the server. Enough to spot SwiftUI render hotspots without
///   torching the daily transaction budget.
/// - `profilesSampleRate: 0` — no continuous CPU profiling.
/// - `beforeSend` filter drops everything below `.error`. Handled exceptions,
///   warnings, and `.info` breadcrumbs never become billable events.
/// - `enableAutoBreadcrumbTracking` stays on so when a real crash *does*
///   ship, the event includes the user's recent navigation / network trail.
/// - `attachScreenshot: false`, `attachViewHierarchy: false` — both could
///   leak PII (episode titles, queue contents) and neither is needed to
///   debug a crash.
///
/// MetricKit crash diagnostics are forwarded into Sentry by
/// `MetricKitReporter` so the same fault never gets double-counted —
/// Sentry's native crash handler always wins.
@MainActor
enum CrashReporter {
    private static let logger = Logger(subsystem: "OffScript", category: "CrashReporter")

    /// Read at launch. Empty / placeholder DSNs (e.g. on a CI build that
    /// didn't get the secret) skip Sentry init entirely so crash-on-init
    /// can't take the app down.
    private static var dsn: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("https://"), trimmed.contains("@") else {
            return nil
        }
        return trimmed
    }

    static func configure() {
        guard let dsn else {
            logger.notice("Sentry DSN absent or malformed — skipping Sentry init")
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = Self.releaseTag
            options.environment = Self.environment

            // Quota controls.
            options.sampleRate = 1.0          // keep all error events
            options.tracesSampleRate = 0.05   // 5% of perf transactions
            options.configureProfiling = { profiling in
                profiling.sessionSampleRate = 0 // no CPU profiling
            }

            // Drop anything below .error so handled / info noise never bills.
            options.beforeSend = { event in
                switch event.level {
                case .fatal, .error:
                    return event
                default:
                    return nil
                }
            }

            // Privacy: never auto-capture screen content. Episode titles
            // and queue state are user-identifying.
            options.attachScreenshot = false
            options.attachViewHierarchy = false

            // Useful crash context.
            options.attachStacktrace = true
            options.enableAutoSessionTracking = true
            options.enableCrashHandler = true
            options.enableSwizzling = true
        }

        logger.info("Sentry initialized — release \(Self.releaseTag, privacy: .public), env \(Self.environment, privacy: .public)")
        refreshStoreKitEnvironment()
    }

    /// `1.14.2-23` — matches App Store Connect release identifiers so you
    /// can filter "did 1.14.x introduce any new crashes" cleanly.
    private static var releaseTag: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return "\(version)-\(build)"
    }

    private static var environment: String {
        #if DEBUG
        return "debug"
        #else
        return UserDefaults.standard.string(forKey: SentryEnvironmentResolver.cacheKey) ?? "production"
        #endif
    }

    private static func refreshStoreKitEnvironment() {
        #if !DEBUG
        Task {
            do {
                let rawValue: String
                switch try await AppTransaction.shared {
                case .verified(let transaction):
                    rawValue = transaction.environment.rawValue
                case .unverified(let transaction, let error):
                    rawValue = transaction.environment.rawValue
                    logger.warning("StoreKit app transaction was unverified: \(String(describing: error), privacy: .public)")
                }

                let environment = SentryEnvironmentResolver.sentryEnvironment(storeKitEnvironmentRawValue: rawValue)
                UserDefaults.standard.set(environment, forKey: SentryEnvironmentResolver.cacheKey)
                SentrySDK.configureScope { scope in
                    scope.setTag(value: environment, key: "storekit.environment")
                }
                logger.info("Resolved StoreKit environment \(environment, privacy: .public)")
            } catch {
                logger.warning("Unable to resolve StoreKit environment: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
    }
}

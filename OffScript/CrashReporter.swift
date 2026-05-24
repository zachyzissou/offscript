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
    private static let logger = Logger(subsystem: "com.offscript", category: "CrashReporter")

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
                Self.filterAndScrub(event: event)
            }
            options.beforeBreadcrumb = { breadcrumb in
                Self.scrub(breadcrumb: breadcrumb)
            }

            // Privacy: never auto-capture screen content. Episode titles
            // and queue state are user-identifying.
            options.attachScreenshot = false
            options.attachViewHierarchy = false

            // Privacy: never send default PII (IP address, cookies, request
            // headers). The default is true in sentry-cocoa 8.x. CLAUDE.md
            // promises "no third-party API keys touch listening data" — that
            // promise covers crash telemetry too. Flagged by the 2026-05-19
            // privacy + production-readiness audit.
            options.sendDefaultPii = false

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

    nonisolated static func filterAndScrub(event: Event) -> Event? {
        switch event.level {
        case .fatal, .error:
            return scrub(event: event)
        default:
            return nil
        }
    }

    nonisolated static func scrub(event: Event) -> Event {
        event.transaction = event.transaction.map { SentryPrivacyScrubber.scrubRoute($0) }
        event.tags = event.tags.map { SentryPrivacyScrubber.scrubStringDictionary($0) }
        event.extra = event.extra.map { SentryPrivacyScrubber.scrubDictionary($0) }
        event.context = event.context.map { context in
            context.mapValues { SentryPrivacyScrubber.scrubDictionary($0) }
        }
        event.breadcrumbs = event.breadcrumbs?.compactMap { scrub(breadcrumb: $0) }

        if let request = event.request {
            request.url = request.url.map { SentryPrivacyScrubber.scrubURLOrString($0, key: "url") }
            request.queryString = nil
            request.fragment = nil
            request.cookies = nil
            request.headers = nil
        }

        if let message = event.message {
            let scrubbedFormatted = SentryPrivacyScrubber.scrubURLOrString(message.formatted, key: "message")
            let scrubbedMessage = SentryMessage(formatted: scrubbedFormatted)
            scrubbedMessage.message = message.message.map { SentryPrivacyScrubber.scrubURLOrString($0, key: "message") }
            scrubbedMessage.params = message.params?.map { SentryPrivacyScrubber.scrubURLOrString($0, key: "message") }
            event.message = scrubbedMessage
        }

        event.exceptions = event.exceptions?.map { exception in
            exception.value = SentryPrivacyScrubber.scrubURLOrString(exception.value, key: "exception")
            return exception
        }

        return event
    }

    nonisolated static func scrub(breadcrumb: Breadcrumb) -> Breadcrumb? {
        breadcrumb.message = breadcrumb.message.map { SentryPrivacyScrubber.scrubURLOrString($0, key: "message") }
        breadcrumb.data = breadcrumb.data.map { SentryPrivacyScrubber.scrubDictionary($0) }
        return breadcrumb
    }
}

private enum SentryPrivacyScrubber {
    nonisolated private static let redacted = "[redacted]"

    nonisolated private static let urlRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"(?:https?|feed|offscript)://[^\s<>"'`]+(?<![.,;:!?)\]\}])"#)
        } catch {
            fatalError("Invalid Sentry URL scrub regex: \(error)")
        }
    }()

    nonisolated private static let uuidRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
            )
        } catch {
            fatalError("Invalid Sentry UUID scrub regex: \(error)")
        }
    }()

    nonisolated static func scrubStringDictionary(_ dictionary: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: dictionary.map { key, value in
            (key, scrubURLOrString(value, key: key))
        })
    }

    nonisolated static func scrubDictionary(_ dictionary: [String: Any]) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: dictionary.map { key, value in
            (key, scrubValue(value, key: key))
        })
    }

    nonisolated static func scrubRoute(_ value: String) -> String {
        scrubURLOrString(value, key: "route")
    }

    nonisolated static func scrubURLOrString(_ value: String, key: String) -> String {
        var scrubbed = replaceURLs(in: value)
        scrubbed = replaceMatches(in: scrubbed, regex: uuidRegex, with: redacted)

        if isSensitiveKey(key), scrubbed == value {
            if isRouteKey(key) {
                return redactRouteSegments(scrubbed)
            }
            return value.isEmpty ? value : redacted
        }

        if isRouteKey(key) {
            return redactRouteSegments(scrubbed)
        }

        return scrubbed
    }

    nonisolated private static func scrubValue(_ value: Any, key: String) -> Any {
        switch value {
        case let string as String:
            return scrubURLOrString(string, key: key)
        case let url as URL:
            return scrubURL(url.absoluteString)
        case let dictionary as [String: Any]:
            return scrubDictionary(dictionary)
        case let dictionary as NSDictionary:
            var scrubbed: [String: Any] = [:]
            for (nestedKey, nestedValue) in dictionary {
                guard let nestedKey = nestedKey as? String else { continue }
                scrubbed[nestedKey] = scrubValue(nestedValue, key: nestedKey)
            }
            return scrubbed
        case let array as [Any]:
            return array.map { scrubValue($0, key: key) }
        default:
            if isSensitiveKey(key) {
                return redacted
            }
            return value
        }
    }

    nonisolated private static func replaceURLs(in value: String) -> String {
        replaceMatches(in: value, regex: urlRegex) { match in
            scrubURL(match)
        }
    }

    nonisolated private static func scrubURL(_ value: String) -> String {
        guard var components = URLComponents(string: value), let scheme = components.scheme else {
            return redacted
        }

        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil

        let hasSensitivePath = !components.path.isEmpty && components.path != "/"
        if hasSensitivePath {
            components.path = "/\(redacted)"
        }

        if components.host == nil {
            return "\(scheme):\(redacted)"
        }

        return (components.string ?? redacted)
            .replacingOccurrences(of: "%5Bredacted%5D", with: redacted)
    }

    nonisolated private static func redactRouteSegments(_ value: String) -> String {
        let separators = CharacterSet(charactersIn: "/?#&")
        return value
            .components(separatedBy: separators)
            .map { segment in
                shouldRedactRouteSegment(segment) ? redacted : segment
            }
            .joined(separator: "/")
    }

    nonisolated private static func shouldRedactRouteSegment(_ segment: String) -> Bool {
        guard !segment.isEmpty else { return false }
        if segment == redacted { return false }
        if segment.range(of: uuidRegex.pattern, options: .regularExpression) != nil { return true }
        return segment.count >= 16 && segment.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil
    }

    nonisolated private static func isSensitiveKey(_ key: String) -> Bool {
        let lowercased = key.lowercased()
        return [
            "url",
            "uri",
            "query",
            "search",
            "transcript",
            "feed",
            "podcast",
            "episode",
            "audio",
            "artwork",
            "route",
            "context",
            "identifier",
            "title"
        ].contains { lowercased.contains($0) }
    }

    nonisolated private static func isRouteKey(_ key: String) -> Bool {
        let lowercased = key.lowercased()
        return lowercased.contains("route") || lowercased.contains("context") || lowercased.contains("transaction")
    }

    nonisolated private static func replaceMatches(
        in value: String,
        regex: NSRegularExpression,
        with replacement: String
    ) -> String {
        replaceMatches(in: value, regex: regex) { _ in replacement }
    }

    nonisolated private static func replaceMatches(
        in value: String,
        regex: NSRegularExpression,
        transform: (String) -> String
    ) -> String {
        let nsValue = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: nsValue.length))
        guard !matches.isEmpty else { return value }

        var scrubbed = value
        for match in matches.reversed() {
            let original = nsValue.substring(with: match.range)
            guard let range = Range(match.range, in: scrubbed) else { continue }
            scrubbed.replaceSubrange(range, with: transform(original))
        }
        return scrubbed
    }
}

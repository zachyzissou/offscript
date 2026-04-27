import Foundation
import MetricKit
import OSLog
import Sentry

/// Subscribes to MetricKit and surfaces both daily metric payloads and
/// crash / hang diagnostics. Two channels:
///
/// 1. **OSLog**: human-readable summaries land in Console.app and Xcode's
///    debug console. Free, no quota, useful during development.
/// 2. **Sentry forwarding (errors only)**: crash diagnostics get promoted
///    to a Sentry event with `level: .fatal` and the MetricKit payload
///    attached as context — so the same crash is visible in App Store
///    Connect (Apple's pipeline), Sentry (our pipeline), AND grouped by
///    Sentry's stack-signature dedupe.
///
/// MetricKit only delivers payloads to App Store / TestFlight builds where
/// the user has opted in to "Share with App Developers." Coverage is
/// roughly 25–35% of users — Sentry's native crash handler covers the
/// other 65–75%.
@MainActor
final class MetricKitReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitReporter()

    private let logger = Logger(subsystem: "OffScript", category: "MetricKit")

    /// Call once on launch (after CrashReporter.configure so Sentry is up).
    func configure() {
        MXMetricManager.shared.add(self)
        logger.info("MetricKit subscriber registered")
    }

    // MARK: - MXMetricManagerSubscriber

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        // Hop to the main actor to log + forward. MetricKit calls in on a
        // background thread; Logger is fine but our forwarding logic
        // touches Sentry which is friendlier on the main actor.
        Task { @MainActor in
            for payload in payloads {
                self.handleMetric(payload)
            }
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        Task { @MainActor in
            for payload in payloads {
                self.handleDiagnostic(payload)
            }
        }
    }

    // MARK: - Metric payloads (daily summaries — OSLog only)

    private func handleMetric(_ payload: MXMetricPayload) {
        // `MXMetricPayload` exposes its data via `dictionaryRepresentation`
        // (and a JSON-string variant). We log the dict — Console.app /
        // Xcode's debug area renders it readably, and we can grep for
        // specific subkeys (e.g. `applicationLaunchMetrics`).
        let dict = payload.dictionaryRepresentation()
        logger.info("Metric payload [\(payload.timeStampBegin, privacy: .public) → \(payload.timeStampEnd, privacy: .public)]:\n\(dict, privacy: .public)")
    }

    // MARK: - Diagnostic payloads (crashes, hangs, etc.)

    private func handleDiagnostic(_ payload: MXDiagnosticPayload) {
        if let crashes = payload.crashDiagnostics, !crashes.isEmpty {
            for crash in crashes {
                forwardCrash(crash)
            }
        }
        if let hangs = payload.hangDiagnostics, !hangs.isEmpty {
            for hang in hangs {
                logger.warning("MetricKit hang diagnostic: \(hang.dictionaryRepresentation(), privacy: .public)")
            }
        }
        if let cpuExceptions = payload.cpuExceptionDiagnostics, !cpuExceptions.isEmpty {
            for cpu in cpuExceptions {
                logger.warning("MetricKit CPU exception: \(cpu.dictionaryRepresentation(), privacy: .public)")
            }
        }
        if let diskWrites = payload.diskWriteExceptionDiagnostics, !diskWrites.isEmpty {
            for disk in diskWrites {
                logger.warning("MetricKit disk-write exception: \(disk.dictionaryRepresentation(), privacy: .public)")
            }
        }
    }

    private func forwardCrash(_ crash: MXCrashDiagnostic) {
        // Native Sentry already caught most of these on-device. We forward
        // to Sentry primarily to capture crashes that ONLY MetricKit sees
        // (e.g. background-task kills, watchdog terminations) — Sentry
        // dedupes on stack signature, so already-reported crashes coalesce.
        let event = Event(level: .fatal)
        event.message = SentryMessage(formatted: "MetricKit crash diagnostic")
        event.extra = [
            "metrickit_payload": crash.dictionaryRepresentation(),
            "termination_reason": crash.terminationReason ?? "unknown",
            "exception_type": crash.exceptionType?.stringValue ?? "unknown",
            "exception_code": crash.exceptionCode?.stringValue ?? "unknown",
            "signal": crash.signal?.stringValue ?? "unknown"
        ]
        SentrySDK.capture(event: event)
        logger.error("Forwarded MetricKit crash diagnostic to Sentry")
    }
}

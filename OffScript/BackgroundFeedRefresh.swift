import BackgroundTasks
import Foundation
import OSLog
import SwiftData

enum BackgroundFeedRefresh {
    static let taskIdentifier = "com.offscript.feed-refresh"
    private static let minimumInterval: TimeInterval = 30 * 60 // 30 minutes
    /// Backoff floor when the previous run encountered nothing but failures —
    /// avoids hammering iOS's BGTaskScheduler with retries that will fail the
    /// same way and risk our app being throttled out of background slots.
    private static let backoffInterval: TimeInterval = 2 * 60 * 60 // 2 hours
    private static let logger = Logger(subsystem: "com.offscript", category: "BackgroundRefresh")

    // MARK: - Scheduling

    /// Schedule the next refresh. Pass `backoff: true` when the previous run
    /// had a high failure rate so we space attempts out and don't burn through
    /// our background budget.
    static func scheduleNextRefresh(backoff: Bool = false) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        let interval = backoff ? backoffInterval : minimumInterval
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info(
                "Scheduled next background feed refresh in \(interval / 60, privacy: .public) minutes\(backoff ? " (backoff)" : "", privacy: .public)"
            )
        } catch {
            logger.error("Failed to schedule background feed refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Execution

    /// Performs the background refresh.
    ///
    /// Cancellation: the enclosing `.backgroundTask(.appRefresh:)` SwiftUI
    /// modifier surfaces system reclaim as `Task` cancellation, which we
    /// observe via `Task.isCancelled` between podcasts and which `await`
    /// propagates through `service.sync`. That gives us the BGTaskScheduler
    /// `expirationHandler` semantics without manually wiring one.
    ///
    /// Re-arm: we schedule the next run BEFORE doing work so the timer is
    /// always in place even if we get force-stopped. On exit, if the run was
    /// dominated by failures we re-schedule with backoff to space retries.
    @Sendable
    static func performRefresh(container: ModelContainer) async {
        logger.info("Background feed refresh starting")

        // Schedule the next refresh before doing work so it's always queued
        // even if the system reclaims us mid-flight.
        scheduleNextRefresh()

        let context = ModelContext(container)
        let service = FeedSyncService()

        let descriptor = FetchDescriptor<Podcast>(
            predicate: #Predicate<Podcast> { $0.isSubscribed == true }
        )
        let podcasts: [Podcast]
        do {
            podcasts = try context.fetch(descriptor)
        } catch {
            logger.warning("Background refresh: failed to fetch podcasts: \(error.localizedDescription, privacy: .public)")
            return
        }

        logger.info("Background refresh: syncing \(podcasts.count, privacy: .public) subscriptions")

        var attempted = 0
        var failed = 0

        for podcast in podcasts {
            guard !Task.isCancelled else {
                logger.info("Background refresh: cancelled by system")
                // On cancellation, leave the previously-scheduled (minimum)
                // refresh in place — system reclaim isn't a failure signal.
                return
            }

            // Skip podcasts that don't need refresh (synced recently or pending retry)
            if podcast.syncStatus == "syncing" { continue }
            if let nextRetry = podcast.nextRetryAt, nextRetry > .now { continue }
            if let lastSync = podcast.lastSyncAt, lastSync.addingTimeInterval(45 * 60) > .now { continue }

            attempted += 1
            do {
                try await service.sync(podcast: podcast, in: context)
                podcast.syncFailureCount = 0
                podcast.syncErrorMessage = nil
                podcast.nextRetryAt = nil
                context.saveOrLog("BackgroundFeedRefresh")
            } catch is CancellationError {
                logger.info("Background refresh: cancelled mid-sync")
                return
            } catch {
                failed += 1
                let failureCount = podcast.syncFailureCount + 1
                podcast.syncFailureCount = failureCount
                podcast.syncErrorMessage = error.localizedDescription
                podcast.nextRetryAt = FeedSyncRetryPolicy.nextRetryDate(afterFailureCount: failureCount)
                context.saveOrLog("BackgroundFeedRefresh")
                logger.warning("Background refresh: failed to sync \(podcast.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Failure-throttle: if we attempted ≥3 syncs and every one failed,
        // back off the next run so we don't churn the BG budget. The
        // per-podcast `nextRetryAt` already enforces exponential retry per
        // feed; this just keeps the *task itself* from firing tight loops.
        if attempted >= 3 && failed == attempted {
            logger.warning("Background refresh: all \(attempted, privacy: .public) attempted syncs failed — rescheduling with backoff")
            scheduleNextRefresh(backoff: true)
        }

        logger.info(
            "Background feed refresh completed (attempted=\(attempted, privacy: .public), failed=\(failed, privacy: .public))"
        )
    }
}

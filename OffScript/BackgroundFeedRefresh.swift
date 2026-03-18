import BackgroundTasks
import Foundation
import OSLog
import SwiftData

enum BackgroundFeedRefresh {
    static let taskIdentifier = "com.offscript.feed-refresh"
    private static let minimumInterval: TimeInterval = 30 * 60 // 30 minutes
    private static let logger = Logger(subsystem: "OffScript", category: "BackgroundRefresh")

    // MARK: - Scheduling

    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled next background feed refresh in \(minimumInterval / 60, privacy: .public) minutes")
        } catch {
            logger.error("Failed to schedule background feed refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Execution

    @Sendable
    static func performRefresh(container: ModelContainer) async {
        logger.info("Background feed refresh starting")

        // Schedule the next refresh before doing work so it's always queued
        scheduleNextRefresh()

        let context = ModelContext(container)
        let service = FeedSyncService()

        let descriptor = FetchDescriptor<Podcast>()
        guard let podcasts = try? context.fetch(descriptor) else {
            logger.warning("Background refresh: failed to fetch podcasts")
            return
        }

        let subscribed = podcasts.filter(\.isSubscribed)
        logger.info("Background refresh: syncing \(subscribed.count, privacy: .public) subscriptions")

        for podcast in subscribed {
            guard !Task.isCancelled else {
                logger.info("Background refresh: cancelled by system")
                return
            }

            // Skip podcasts that don't need refresh (synced recently or pending retry)
            if podcast.syncStatus == "syncing" { continue }
            if let nextRetry = podcast.nextRetryAt, nextRetry > .now { continue }
            if let lastSync = podcast.lastSyncAt, lastSync.addingTimeInterval(45 * 60) > .now { continue }

            do {
                try await service.sync(podcast: podcast, in: context)
                podcast.syncFailureCount = 0
                podcast.syncErrorMessage = nil
                podcast.nextRetryAt = nil
                try? context.save()
            } catch {
                let failureCount = podcast.syncFailureCount + 1
                podcast.syncFailureCount = failureCount
                podcast.syncErrorMessage = error.localizedDescription
                let retryDelay = min(pow(2.0, Double(failureCount)) * 60, 60 * 60 * 6)
                podcast.nextRetryAt = Date().addingTimeInterval(retryDelay)
                try? context.save()
                logger.warning("Background refresh: failed to sync \(podcast.title ?? "unknown", privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        logger.info("Background feed refresh completed")
    }
}

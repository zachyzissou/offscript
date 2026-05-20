import BackgroundTasks
import Foundation
import SwiftData
import SwiftUI

/// Read-only helpers that surface per-podcast sync state for the Debug
/// Inspector. The actual `lastSyncAt`/`lastSyncAttemptAt`/`syncFailureCount`
/// fields live on `Podcast` and are written from `FeedSyncService` and
/// `BackgroundFeedRefresh`; this service just queries them.
///
/// Kept as a `@MainActor enum` (not a class) to mirror `SettingsCountService`
/// in `SettingsView.swift` — debug-only fetches that don't need lifecycle
/// management, dependency injection, or test-time replacement.
@MainActor
enum SyncHistoryService {
    /// Subscribed podcasts that have at least one sync attempt recorded,
    /// sorted by `lastSyncAttemptAt` descending, capped at `limit`. Falls
    /// back to subscribed-but-never-attempted podcasts only when the
    /// attempted set is empty so empty installs still render something.
    static func recentlyAttempted(in context: ModelContext, limit: Int) -> [Podcast] {
        var attemptedDescriptor = FetchDescriptor<Podcast>(
            predicate: #Predicate<Podcast> { $0.isSubscribed && $0.lastSyncAttemptAt != nil },
            sortBy: [SortDescriptor(\Podcast.lastSyncAttemptAt, order: .reverse)]
        )
        attemptedDescriptor.fetchLimit = limit
        let attempted = (try? context.fetch(attemptedDescriptor)) ?? []
        if !attempted.isEmpty { return attempted }

        var fallbackDescriptor = FetchDescriptor<Podcast>(
            predicate: #Predicate<Podcast> { $0.isSubscribed },
            sortBy: [SortDescriptor(\Podcast.title, order: .forward)]
        )
        fallbackDescriptor.fetchLimit = limit
        return (try? context.fetch(fallbackDescriptor)) ?? []
    }

    /// Human-readable status label for the inspector row. `Podcast.syncStatus`
    /// is a free-form string written by `FeedSyncService`; we normalize it to
    /// the small vocabulary the inspector renders.
    static func statusLabel(for podcast: Podcast) -> String {
        switch podcast.syncStatus.lowercased() {
        case "success", "ok": return "● SUCCESS"
        case "failed", "error": return "× FAILED"
        case "pending", "syncing", "running": return "◐ PENDING"
        case "idle" where podcast.lastSyncAttemptAt != nil: return "● IDLE"
        case "idle": return "○ NEVER"
        default:
            // Surface unknown raw values verbatim so engineers can spot any
            // new state words FeedSyncService starts writing without the
            // inspector silently swallowing them.
            return "● \(podcast.syncStatus.uppercased())"
        }
    }

    static func statusColor(for podcast: Podcast) -> Color {
        switch podcast.syncStatus.lowercased() {
        case "success", "ok": return .offscriptFnMode
        case "failed", "error": return .offscriptFnRecord
        case "pending", "syncing", "running": return .offscriptSignalYellow
        case "idle" where podcast.lastSyncAttemptAt != nil: return .offscriptFnInfo
        case "idle": return .offscriptSoftPaper
        default: return .offscriptFnInfo
        }
    }

    /// Query BGTaskScheduler for the next pending feed-refresh task. Returns
    /// `nil` if no task is queued (which is itself a useful diagnostic — the
    /// scheduler may have dropped our request).
    ///
    /// `getPendingTaskRequests` takes a completion handler; we surface the
    /// result via `completion` so the inspector can hop back to the main
    /// actor before writing into `@State`.
    nonisolated static func fetchNextBackgroundRefresh(completion: @escaping @Sendable (Date?) -> Void) {
        BGTaskScheduler.shared.getPendingTaskRequests { requests in
            let date = requests
                .first(where: { $0.identifier == BackgroundFeedRefresh.taskIdentifier })?
                .earliestBeginDate
            completion(date)
        }
    }
}

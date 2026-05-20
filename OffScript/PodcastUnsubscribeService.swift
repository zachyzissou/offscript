import Foundation
import OSLog
import SwiftData

private let unsubscribeLogger = Logger(subsystem: "com.offscript", category: "Unsubscribe")

/// Cleans up the side effects of unsubscribing from a podcast. Without
/// this, every unsubscribe leaves traces behind: Spotlight surfaces
/// episodes from shows the user no longer follows, downloaded files
/// occupy disk space indefinitely, transcript caches stay in memory,
/// queue items dangle. The model relationships handle SwiftData-side
/// cleanup, but Spotlight + the file system are out of band.
///
/// Behavior:
/// - Marks the podcast `isSubscribed = false` (data preserved for taste
///   profile continuity if the user re-subscribes).
/// - Removes the podcast's queue items.
/// - Deletes downloaded audio files for the podcast's episodes.
/// - De-indexes the podcast's episodes from CoreSpotlight.
/// - Saves once at the end so the changes commit atomically.
@MainActor
enum PodcastUnsubscribeService {

    /// Returns `true` on success. Caller decides what to do on failure
    /// (typically re-render to reflect partial state and surface the
    /// error in the UI).
    @discardableResult
    static func unsubscribe(_ podcast: Podcast, in context: ModelContext) -> Bool {
        unsubscribeLogger.info("Unsubscribe begin: \(podcast.title, privacy: .public)")

        // Capture the episode IDs before mutating anything — once
        // SwiftData saves the unsubscribe, related fetches change.
        let episodeIDs = podcast.episodes.map { $0.id }

        // 1. Mark the podcast unsubscribed.
        podcast.isSubscribed = false
        podcast.subscribedAt = nil

        // 2. Drop queue items pointing at this podcast's episodes.
        do {
            let queueItems = try QueueService.orderedItems(in: context)
            for item in queueItems where item.episode.podcast.id == podcast.id {
                try QueueService.remove(item, in: context)
            }
        } catch {
            unsubscribeLogger.error("Queue cleanup failed: \(error.localizedDescription, privacy: .public)")
        }

        // 3. If the currently-playing episode is from this podcast, stop
        // playback before we delete its file out from under AVPlayer.
        // Without this, `removeItem(at:)` can fire while AVPlayer is
        // mid-read on the local file URL, corrupting playback or
        // crashing on some iOS versions.
        let player = PlaybackController.shared
        if let current = player.currentEpisode,
           podcast.episodes.contains(where: { $0.id == current.id }) {
            player.pause()
        }

        // 4. Delete downloaded audio files for this podcast's episodes.
        for episode in podcast.episodes where episode.isDownloaded {
            DownloadService.shared.deleteDownload(for: episode)
        }

        // 4. De-index Spotlight entries so iOS Search stops surfacing
        // episodes from a show the user no longer follows.
        SpotlightIndexer.deindexEpisodes(ids: episodeIDs)

        // 5. Purge transcript cache rows for the unsubscribed episodes.
        // `EpisodeTranscriptCache` is keyed by `episodeID` (not a SwiftData
        // relationship) so it doesn't cascade-delete when the Episode goes
        // away. Without this sweep, transcripts from shows the user no longer
        // follows linger in the store forever, bloating iCloud sync and
        // making re-imports inconsistent (a stale `published` cache row would
        // be picked up before the re-import even hits the publisher's
        // feed-provided transcript URL).
        if !episodeIDs.isEmpty {
            let idSet = Set(episodeIDs)
            do {
                let descriptor = FetchDescriptor<EpisodeTranscriptCache>(
                    predicate: #Predicate<EpisodeTranscriptCache> { idSet.contains($0.episodeID) }
                )
                let staleCaches = try context.fetch(descriptor)
                for cache in staleCaches {
                    context.delete(cache)
                }
                if !staleCaches.isEmpty {
                    unsubscribeLogger.info("Removed \(staleCaches.count) transcript cache rows for unsubscribed podcast")
                }
            } catch {
                unsubscribeLogger.error("Transcript cache cleanup failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // 6. Single atomic save for everything that didn't already save
        // itself (queue removal saves; download delete saves; isSubscribed
        // toggle does not).
        do {
            try context.save()
        } catch {
            unsubscribeLogger.error("Final save failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        unsubscribeLogger.info("Unsubscribe complete: \(podcast.title, privacy: .public), \(episodeIDs.count) episodes deindexed")
        NotificationCenter.default.post(name: .offscriptLibrarySubscriptionsChanged, object: podcast.id)
        return true
    }
}

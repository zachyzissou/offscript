import CoreSpotlight
import Foundation
import OSLog
import SwiftData
import UniformTypeIdentifiers

private let spotlightLogger = Logger(subsystem: "com.offscript", category: "Spotlight")

/// Donates subscribed-show episodes to Spotlight so they show up in iOS
/// system search and Siri Suggestions. Tapping a result deep-links the
/// episode via the `offscript://episode/<uuid>` URL scheme handled in
/// `OffScriptApp.swift`.
///
/// Strategy:
/// - Index in batches of 200 so we don't allocate a giant array
/// - Index up to `maxEpisodesToIndex` newest episodes per refresh — the user
///   is unlikely to search for 5-year-old episodes
/// - Idempotent: indexSearchableItems replaces by uniqueIdentifier
@MainActor
enum SpotlightIndexer {
    static let domainIdentifier = "com.offscript.episodes"
    private static let maxEpisodesToIndex = 500
    private static let batchSize = 200
    private static let indexTTL: TimeInterval = 86_400 // 24 hours
    private static let lastIndexedKey = "offscript.spotlightLastIndexedAt"

    /// Index newest subscribed episodes. Safe to call repeatedly — Spotlight
    /// dedupes on uniqueIdentifier. Skips silently when CoreSpotlight is
    /// unavailable (Mac Catalyst on certain configs).
    ///
    /// Debounced: re-indexes at most once every 24 hours. The 30-day TTL on
    /// each item naturally ages out unsubscribed/old episodes, so running on
    /// every launch is unnecessary and wastes CPU on startup.
    static func indexEpisodes(in context: ModelContext) {
        let lastIndexed = UserDefaults.standard.double(forKey: lastIndexedKey)
        let elapsed = Date().timeIntervalSince1970 - lastIndexed
        guard elapsed >= indexTTL else { return }

        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.podcast.isSubscribed == true },
            sortBy: [SortDescriptor(\Episode.pubDate, order: .reverse)]
        )
        descriptor.fetchLimit = maxEpisodesToIndex

        guard let episodes = try? context.fetch(descriptor), !episodes.isEmpty else { return }

        // Stamp the last-indexed time before batching so a crash mid-run
        // doesn't cause a retry loop on the next launch.
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastIndexedKey)

        let index = CSSearchableIndex.default()
        var batch: [CSSearchableItem] = []
        batch.reserveCapacity(min(batchSize, episodes.count))

        for episode in episodes {
            let attributes = CSSearchableItemAttributeSet(contentType: UTType.audio)
            attributes.title = episode.title
            attributes.contentDescription = episode.summary?.strippingHTML
            attributes.artist = episode.podcast.author ?? episode.podcast.title
            attributes.album = episode.podcast.title
            attributes.containerTitle = episode.podcast.title
            attributes.contentCreationDate = episode.pubDate
            if let duration = episode.duration {
                attributes.duration = NSNumber(value: duration)
            }
            if let artworkURL = episode.artworkURL ?? episode.podcast.artworkURL {
                attributes.thumbnailURL = artworkURL
            }
            attributes.keywords = ["podcast", "OffScript", episode.podcast.title]

            let item = CSSearchableItem(
                uniqueIdentifier: episode.id.uuidString,
                domainIdentifier: domainIdentifier,
                attributeSet: attributes
            )
            // 30-day TTL so unsubscribed/old episodes age out automatically.
            item.expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())
            batch.append(item)

            if batch.count >= batchSize {
                let snapshot = batch
                batch.removeAll(keepingCapacity: true)
                index.indexSearchableItems(snapshot) { error in
                    if let error {
                        spotlightLogger.error("Spotlight index batch failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }

        if !batch.isEmpty {
            index.indexSearchableItems(batch) { error in
                if let error {
                    spotlightLogger.error("Spotlight index final batch failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Wipe everything we contributed. Useful on sign-out / library reset.
    static func deleteAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { error in
            if let error {
                spotlightLogger.error("Spotlight wipe failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Bypass the 24h TTL and schedule a full re-index on next `indexEpisodes`
    /// call. Use this after subscription changes so new shows appear in Spotlight
    /// immediately rather than waiting up to a day.
    static func invalidateIndex() {
        UserDefaults.standard.removeObject(forKey: lastIndexedKey)
    }
}

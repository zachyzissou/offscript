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

    /// Index newest subscribed episodes. Safe to call repeatedly — Spotlight
    /// dedupes on uniqueIdentifier. Skips silently when CoreSpotlight is
    /// unavailable (Mac Catalyst on certain configs).
    static func indexEpisodes(in context: ModelContext) {
        let index = CSSearchableIndex.default()

        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.podcast.isSubscribed == true },
            sortBy: [SortDescriptor(\Episode.pubDate, order: .reverse)]
        )
        descriptor.fetchLimit = maxEpisodesToIndex

        guard let episodes = try? context.fetch(descriptor), !episodes.isEmpty else { return }

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
}

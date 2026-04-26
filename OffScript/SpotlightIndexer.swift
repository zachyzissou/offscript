@preconcurrency import CoreSpotlight
import Foundation
import OSLog
import SwiftData
import UniformTypeIdentifiers

/// Indexes podcasts and recent episodes into Spotlight so the user can search OffScript content
/// from the iOS Search field. Each item deep-links back into the app via offscript:// URLs.
@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()

    private let logger = Logger(subsystem: "OffScript", category: "Spotlight")
    private let domain = "com.offscript.app"
    private let podcastDomain = "com.offscript.app.podcast"
    private let episodeDomain = "com.offscript.app.episode"
    private let episodesPerPodcast = 5

    private init() {}

    func reindex(in context: ModelContext) {
        let session = CSSearchableIndex.default()

        let podcastDescriptor = FetchDescriptor<Podcast>(
            predicate: #Predicate<Podcast> { $0.isSubscribed == true }
        )

        let podcasts: [Podcast]
        do {
            podcasts = try context.fetch(podcastDescriptor)
        } catch {
            logger.error("Spotlight reindex failed to fetch podcasts: \(String(describing: error), privacy: .public)")
            return
        }

        var items: [CSSearchableItem] = []
        items.reserveCapacity(podcasts.count * (episodesPerPodcast + 1))

        for podcast in podcasts {
            items.append(makeItem(for: podcast))

            let recent = podcast.episodes
                .sorted { $0.pubDate > $1.pubDate }
                .prefix(episodesPerPodcast)

            for episode in recent {
                items.append(makeItem(for: episode))
            }
        }

        session.deleteSearchableItems(withDomainIdentifiers: [podcastDomain, episodeDomain]) { [weak self] error in
            if let error {
                self?.logger.error("Spotlight delete failed: \(String(describing: error), privacy: .public)")
            }

            session.indexSearchableItems(items) { error in
                if let error {
                    self?.logger.error("Spotlight index failed: \(String(describing: error), privacy: .public)")
                } else {
                    self?.logger.info("Indexed \(items.count, privacy: .public) Spotlight items")
                }
            }
        }
    }

    func index(podcast: Podcast) {
        CSSearchableIndex.default().indexSearchableItems([makeItem(for: podcast)]) { [weak self] error in
            if let error {
                self?.logger.error("Spotlight podcast index failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func index(episode: Episode) {
        CSSearchableIndex.default().indexSearchableItems([makeItem(for: episode)]) { [weak self] error in
            if let error {
                self?.logger.error("Spotlight episode index failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func remove(podcastID: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ["podcast:\(podcastID.uuidString)"]) { _ in }
    }

    // MARK: - Item construction

    private func makeItem(for podcast: Podcast) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .audio)
        attrs.title = podcast.title
        attrs.contentDescription = podcast.summary?.strippingHTML ?? podcast.author ?? "Podcast on OffScript"
        attrs.keywords = (podcast.categories + [podcast.author].compactMap { $0 }).filter { !$0.isEmpty }
        attrs.contentURL = URL(string: "offscript://podcast/\(podcast.id.uuidString)")
        attrs.thumbnailURL = podcast.artworkURL
        attrs.artist = podcast.author
        attrs.contentSources = ["OffScript"]

        return CSSearchableItem(
            uniqueIdentifier: "podcast:\(podcast.id.uuidString)",
            domainIdentifier: podcastDomain,
            attributeSet: attrs
        )
    }

    private func makeItem(for episode: Episode) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .audio)
        attrs.title = episode.title
        attrs.contentDescription = episode.summary?.strippingHTML ?? episode.podcast.title
        attrs.album = episode.podcast.title
        attrs.artist = episode.podcast.author
        attrs.thumbnailURL = episode.artworkURL ?? episode.podcast.artworkURL
        attrs.contentURL = URL(string: "offscript://episode/\(episode.id.uuidString)")
        attrs.contentCreationDate = episode.pubDate
        if let duration = episode.duration {
            attrs.duration = NSNumber(value: duration)
        }
        attrs.keywords = episode.profile?.tags ?? []
        attrs.contentSources = ["OffScript"]

        return CSSearchableItem(
            uniqueIdentifier: "episode:\(episode.id.uuidString)",
            domainIdentifier: episodeDomain,
            attributeSet: attrs
        )
    }
}

//
//  CarPlaySceneDelegate.swift
//  OffScript
//
//  CarPlay browse / now-playing scaffolding.
//
//  This file is intentionally inert until Apple grants the
//  `com.apple.developer.carplay-audio` entitlement (request via
//  https://developer.apple.com/contact/carplay/). Once granted, the next
//  signed build will register this scene delegate via the
//  `CPTemplateApplicationSceneSessionRoleAudio` entry in Info.plist and the
//  in-car browse experience lights up automatically — no further code wiring
//  needed.
//
//  Prerequisites already in place (do NOT need to be wired again here):
//    - MPNowPlayingInfoCenter metadata: PlaybackController.swift
//    - MPRemoteCommandCenter targets (play/pause/skip/seek/like):
//      PlaybackController.swift, donated by NowPlayingPublisher
//    - Lock-screen scrubber: already shipped via MPRemoteCommandCenter
//      changePlaybackPositionCommand
//
//  CarPlay inherits all of the above for free as soon as the audio
//  entitlement is active and the app is signed with a provisioning profile
//  that includes it.
//

import CarPlay
import Foundation
import OSLog
import SwiftData
import UIKit

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private static let logger = Logger(subsystem: "com.offscript", category: "CarPlay")

    /// Cap section sizes to keep CarPlay list templates responsive. Apple
    /// silently truncates very long lists; we pick conservative limits so the
    /// in-car UI feels snappy even on cellular data.
    private enum ListLimits {
        static let podcasts = 50
        static let episodesPerPodcast = 50
        static let queue = 50
        static let recent = 20
        static let recommendations = 10
        /// Cap search hits so the in-car list renders quickly even on a long
        /// library. Subscribed podcasts and recent episodes are both filtered
        /// against this combined ceiling.
        static let searchResults = 30
        /// Minimum query length before we fire a search. CarPlay's input
        /// surfaces (voice + steering-wheel scroll wheel) tend to emit
        /// single-character noise during composition; a 2-char floor avoids
        /// thrashing the SwiftData fetch on every keystroke.
        static let searchMinChars = 2
        /// Up Next list shown when the user taps the now-playing Up Next
        /// button. Tight cap because this surface is presented while driving.
        static let upNext = 10
    }

    private var interfaceController: CPInterfaceController?

    /// In-memory cache for artwork downloaded for CarPlay list items. CarPlay
    /// re-queries `CPListItem` images opportunistically (template re-renders,
    /// dark/light switches), so we keep a small NSCache keyed by URL to avoid
    /// re-fetching the same JPEG every time. CarPlay reads back on the main
    /// actor, so MainActor isolation is fine here.
    private let artworkCache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 128
        return cache
    }()

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        Self.logger.notice("CarPlay scene connected")

        configureNowPlayingButtons()

        interfaceController.setRootTemplate(
            makeRootTemplate(),
            animated: false,
            completion: nil
        )
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        Self.logger.notice("CarPlay scene disconnected")
    }

    // MARK: - Root template

    private func makeRootTemplate() -> CPTabBarTemplate {
        let library = CPListTemplate(title: "Library", sections: librarySections())
        library.tabImage = UIImage(systemName: "books.vertical")

        let queue = CPListTemplate(title: "Queue", sections: queueSections())
        queue.tabImage = UIImage(systemName: "text.badge.plus")

        let recent = CPListTemplate(title: "Recent", sections: recentSections())
        recent.tabImage = UIImage(systemName: "clock")

        let recommendations = CPListTemplate(title: "Recommendations", sections: recommendationsSections())
        recommendations.tabImage = UIImage(systemName: "sparkles")

        let search = makeSearchTemplate()
        search.tabImage = UIImage(systemName: "magnifyingglass")
        search.tabTitle = "Search"

        return CPTabBarTemplate(templates: [library, queue, recent, recommendations, search])
    }

    // MARK: - Search

    /// CarPlay's text-input surface. Returns matches against the on-device
    /// library only — no network round-trip. The car is a poor place to be
    /// waiting on iTunes search latency, and the entitlement-gated CarPlay
    /// audio app surface is for *playing what you already follow*, not for
    /// discovery (the recommendations tab covers that path).
    private func makeSearchTemplate() -> CPSearchTemplate {
        let search = CPSearchTemplate()
        search.delegate = self
        return search
    }

    /// Find subscribed podcasts and recent episodes whose title contains
    /// `query` (case-insensitive). Podcasts always sort before episodes —
    /// once a driver knows what show they want, surfacing the show first
    /// lets them open the show and pick an episode in two glances rather
    /// than scrolling a flat list of episodes from many shows.
    private func searchPodcasts(matching query: String) -> [CPListItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= ListLimits.searchMinChars,
              let context = makeModelContext() else {
            return []
        }

        var hits: [CPListItem] = []
        hits.reserveCapacity(ListLimits.searchResults)

        // 1) Subscribed podcasts — title contains query (case-insensitive).
        // SwiftData's #Predicate macro does not yet support
        // `localizedCaseInsensitiveContains`, so we filter in memory after
        // fetching subscribed shows (already capped by `ListLimits.podcasts`
        // in the library section logic; here we widen to the full subscribed
        // set because the user has explicitly opted in by typing).
        do {
            let descriptor = FetchDescriptor<Podcast>(
                predicate: #Predicate<Podcast> { $0.isSubscribed },
                sortBy: [SortDescriptor(\Podcast.title)]
            )
            let podcasts = try context.fetch(descriptor)
            let matchingPodcasts = podcasts.filter { $0.title.range(of: trimmed, options: .caseInsensitive) != nil }
            for podcast in matchingPodcasts {
                guard hits.count < ListLimits.searchResults else { break }
                hits.append(searchListItem(for: podcast))
            }
        } catch {
            Self.logger.error("Search podcast fetch failed: \(String(describing: error), privacy: .public)")
        }

        // 2) Recent episodes — episodes the user has actually played
        // (`lastPlayedAt != nil`) whose title contains the query. Sorted
        // most-recently-played first so familiar episodes surface above
        // ancient backlog. Same in-memory case-insensitive filter as above.
        if hits.count < ListLimits.searchResults {
            do {
                let descriptor = FetchDescriptor<Episode>(
                    predicate: #Predicate<Episode> { $0.lastPlayedAt != nil },
                    sortBy: [SortDescriptor(\Episode.lastPlayedAt, order: .reverse)]
                )
                let episodes = try context.fetch(descriptor)
                for episode in episodes where episode.title.range(of: trimmed, options: .caseInsensitive) != nil {
                    guard hits.count < ListLimits.searchResults else { break }
                    hits.append(listItem(for: episode))
                }
            } catch {
                Self.logger.error("Search episode fetch failed: \(String(describing: error), privacy: .public)")
            }
        }

        return hits
    }

    /// `CPListItem` for a podcast row in the search results. Tapping pushes
    /// the existing episode list template for that podcast — same handler
    /// the library tab uses, so the navigation feels consistent.
    private func searchListItem(for podcast: Podcast) -> CPListItem {
        let detail = podcast.author ?? "Podcast"
        let item = CPListItem(text: podcast.title, detailText: detail)
        item.accessoryType = .disclosureIndicator
        attachArtwork(to: item, url: podcast.artworkURL)
        item.handler = { [weak self] _, completion in
            self?.pushEpisodeList(for: podcast)
            completion()
        }
        return item
    }

    // MARK: - Section builders

    /// Subscribed podcasts → tap opens an episode list for that podcast.
    private func librarySections() -> [CPListSection] {
        guard let context = makeModelContext() else {
            return [emptySection(title: "Library unavailable", detail: "Open OffScript on iPhone to sync")]
        }
        do {
            let descriptor = FetchDescriptor<Podcast>(
                predicate: #Predicate<Podcast> { $0.isSubscribed },
                sortBy: [SortDescriptor(\Podcast.title)]
            )
            let podcasts = try context.fetch(descriptor).prefix(ListLimits.podcasts)
            if podcasts.isEmpty {
                return [emptySection(title: "No subscriptions yet", detail: "Subscribe on iPhone")]
            }
            let items = podcasts.map { podcast -> CPListItem in
                let detail = podcast.author ?? "Podcast"
                let item = CPListItem(text: podcast.title, detailText: detail)
                item.accessoryType = .disclosureIndicator
                attachArtwork(to: item, url: podcast.artworkURL)
                item.handler = { [weak self] _, completion in
                    self?.pushEpisodeList(for: podcast)
                    completion()
                }
                return item
            }
            return [CPListSection(items: Array(items))]
        } catch {
            Self.logger.error("Library fetch failed: \(String(describing: error), privacy: .public)")
            return [emptySection(title: "Couldn't load library", detail: nil)]
        }
    }

    /// Queue in user-defined order.
    private func queueSections() -> [CPListSection] {
        guard let context = makeModelContext() else {
            return [emptySection(title: "Queue unavailable", detail: nil)]
        }
        do {
            let descriptor = FetchDescriptor<QueueItem>(
                sortBy: [
                    SortDescriptor(\QueueItem.position),
                    SortDescriptor(\QueueItem.createdAt)
                ]
            )
            let queueItems = try context.fetch(descriptor).prefix(ListLimits.queue)
            if queueItems.isEmpty {
                return [emptySection(title: "Queue is empty", detail: "Add episodes from iPhone")]
            }
            let items = queueItems.map { listItem(for: $0.episode) }
            return [CPListSection(items: items)]
        } catch {
            Self.logger.error("Queue fetch failed: \(String(describing: error), privacy: .public)")
            return [emptySection(title: "Couldn't load queue", detail: nil)]
        }
    }

    /// Last ~20 episodes the user actually started/played, sorted by
    /// `lastPlayedAt` descending.
    private func recentSections() -> [CPListSection] {
        guard let context = makeModelContext() else {
            return [emptySection(title: "Recent unavailable", detail: nil)]
        }
        do {
            var descriptor = FetchDescriptor<Episode>(
                predicate: #Predicate<Episode> { $0.lastPlayedAt != nil },
                sortBy: [SortDescriptor(\Episode.lastPlayedAt, order: .reverse)]
            )
            descriptor.fetchLimit = ListLimits.recent
            let episodes = try context.fetch(descriptor)
            if episodes.isEmpty {
                return [emptySection(title: "Nothing played yet", detail: nil)]
            }
            let items = episodes.map { listItem(for: $0) }
            return [CPListSection(items: items)]
        } catch {
            Self.logger.error("Recent fetch failed: \(String(describing: error), privacy: .public)")
            return [emptySection(title: "Couldn't load recent", detail: nil)]
        }
    }

    /// Top recommendations from RecommendationService.homeSections. CarPlay
    /// is a read-only consumer here — we don't write any of the surfacing
    /// telemetry RecommendationService gathers, just present the result.
    private func recommendationsSections() -> [CPListSection] {
        guard let context = makeModelContext() else {
            return [emptySection(title: "Recommendations unavailable", detail: nil)]
        }
        do {
            let service = RecommendationService()
            // RecommendationService.homeSections is synchronous and throws.
            // It returns multiple HomeFeedSection groups; we flatten and take
            // the top N scored episodes across all of them. refreshTasteProfile
            // is false to keep this call cheap on CarPlay scene-connect (the
            // main app refreshes it on its own cadence).
            let sections = try service.homeSections(
                context: context,
                mode: .balanced,
                limit: ListLimits.recommendations,
                refreshTasteProfile: false
            )
            let scored = sections
                .flatMap(\.scoredEpisodes)
                .sorted { $0.score > $1.score }
                .prefix(ListLimits.recommendations)

            // Dedupe by episode id while preserving score order.
            var seenIDs = Set<UUID>()
            let uniqueEpisodes = scored.compactMap { scored -> Episode? in
                let episode = scored.episode
                guard !seenIDs.contains(episode.id) else { return nil }
                seenIDs.insert(episode.id)
                return episode
            }

            if uniqueEpisodes.isEmpty {
                return [emptySection(title: "No recommendations yet", detail: "Listen a bit to unlock these")]
            }
            let items = uniqueEpisodes.map { listItem(for: $0) }
            return [CPListSection(items: items)]
        } catch {
            Self.logger.error("Recommendations fetch failed: \(String(describing: error), privacy: .public)")
            return [emptySection(title: "Couldn't load recommendations", detail: nil)]
        }
    }

    // MARK: - Nested templates

    /// Push an episode list for a single podcast.
    private func pushEpisodeList(for podcast: Podcast) {
        let episodes = podcast.episodes
            .sorted { $0.pubDate > $1.pubDate }
            .prefix(ListLimits.episodesPerPodcast)
        let items = episodes.map { listItem(for: $0) }
        let section = items.isEmpty
            ? emptySection(title: "No episodes", detail: nil)
            : CPListSection(items: Array(items))
        let template = CPListTemplate(title: podcast.title, sections: [section])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    // MARK: - Item construction

    private func listItem(for episode: Episode) -> CPListItem {
        let item = CPListItem(text: episode.title, detailText: episode.podcast.title)
        item.accessoryType = .none
        let artworkURL = episode.artworkURL ?? episode.podcast.artworkURL
        attachArtwork(to: item, url: artworkURL)
        item.handler = { _, completion in
            Task { @MainActor in
                let context = OffScriptApp.carPlayModelContainer?.mainContext
                PlaybackController.shared.play(episode, in: context)
                completion()
            }
        }
        return item
    }

    private func emptySection(title: String, detail: String?) -> CPListSection {
        let placeholder = CPListItem(text: title, detailText: detail)
        placeholder.isEnabled = false
        return CPListSection(items: [placeholder])
    }

    // MARK: - Artwork

    /// Fetch artwork off the main thread and apply it to the list item via
    /// `setImage(_:)`. CarPlay's `CPListItem` supports updating the image
    /// after the template is on screen, so we don't need to block scene-
    /// connect on image downloads — the row renders with a nil image first,
    /// then the image flows in when the download completes.
    private func attachArtwork(to item: CPListItem, url: URL?) {
        guard let url else { return }
        let nsURL = url as NSURL
        if let cached = artworkCache.object(forKey: nsURL) {
            item.setImage(cached)
            return
        }
        Task.detached(priority: .utility) { [weak self] in
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else { return }
            await self?.commitArtwork(image, for: nsURL, on: item)
        }
    }

    private func commitArtwork(_ image: UIImage, for url: NSURL, on item: CPListItem) {
        artworkCache.setObject(image, forKey: url)
        item.setImage(image)
    }

    // MARK: - Now Playing

    private func configureNowPlayingButtons() {
        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.isUpNextButtonEnabled = true
        nowPlaying.upNextTitle = "Up Next"
        nowPlaying.add(self)
    }

    // MARK: - ModelContext access

    /// Read the shared container published by `OffScriptApp` and return its
    /// main-actor context. Returns nil if the app process hasn't finished
    /// initializing the SwiftData stack yet (shouldn't happen — CarPlay
    /// scene-connect implies the app process is alive — but we degrade
    /// gracefully to an empty list rather than crash).
    private func makeModelContext() -> ModelContext? {
        OffScriptApp.carPlayModelContainer?.mainContext
    }
}

// MARK: - CPNowPlayingTemplateObserver

/// Empty conformance for now — `CPNowPlayingTemplate.add(_:)` requires an
/// observer object. The protocol has no required methods; we keep the
/// conformance here so future hook points (e.g. reacting to Up Next taps)
/// have a place to land.
extension CarPlaySceneDelegate: CPNowPlayingTemplateObserver {}

// MARK: - CPSearchTemplateDelegate

extension CarPlaySceneDelegate: CPSearchTemplateDelegate {
    /// CarPlay invokes this on every keystroke / voice-recognized chunk.
    /// We must respond on the main actor and call `completionHandler` with
    /// the result list (or `[]` to clear).
    nonisolated func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        updatedSearchText searchText: String,
        completionHandler: @escaping ([CPListItem]) -> Void
    ) {
        Task { @MainActor in
            // Short queries: clear results without burning a fetch. The
            // floor lives in `searchPodcasts(matching:)` so the empty-string
            // case (e.g. user backspaced everything) also clears cleanly.
            guard searchText.count >= ListLimits.searchMinChars else {
                completionHandler([])
                return
            }
            let results = self.searchPodcasts(matching: searchText)
            completionHandler(results)
        }
    }

    /// User tapped a search hit. The `handler` we attached in
    /// `listItem(for:)` / `searchListItem(for:)` already performs the right
    /// action (play episode / push podcast episode list); just forward.
    nonisolated func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        selectedResult item: CPListItem,
        completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            if let handler = item.handler {
                handler(item, completionHandler)
            } else {
                completionHandler()
            }
        }
    }
}

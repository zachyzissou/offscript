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

        return CPTabBarTemplate(templates: [library, queue, recent, recommendations])
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

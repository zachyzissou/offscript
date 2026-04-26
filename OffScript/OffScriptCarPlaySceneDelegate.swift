import CarPlay
import OSLog
import SwiftData
import UIKit

/// CarPlay audio scene. Renders OffScript's queue + recents as CarPlay templates
/// so the user can browse and trigger playback from the in-car dashboard.
final class OffScriptCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private let logger = Logger(subsystem: "OffScript", category: "CarPlay")
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        logger.info("CarPlay connected")

        let root = makeRootTemplate()
        interfaceController.setRootTemplate(root, animated: false) { [weak self] success, error in
            if let error {
                self?.logger.error("CarPlay set root failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        logger.info("CarPlay disconnected")
    }

    // MARK: - Template construction

    private func makeRootTemplate() -> CPTabBarTemplate {
        let nowPlayingTab = makeNowPlayingTab()
        let queueTab = makeQueueTab()
        let libraryTab = makeLibraryTab()

        let tabBar = CPTabBarTemplate(templates: [nowPlayingTab, queueTab, libraryTab])
        return tabBar
    }

    private func makeNowPlayingTab() -> CPTemplate {
        let snapshot = SharedNowPlayingState.read()

        let item: CPListItem
        if let snapshot {
            item = CPListItem(
                text: snapshot.episodeTitle,
                detailText: snapshot.podcastTitle,
                image: nil
            )
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    if let player = await PlaybackControllerProxy.toggle() {
                        self?.logger.info("CarPlay toggled playback: \(player ? "playing" : "paused", privacy: .public)")
                    }
                    completion()
                }
            }
        } else {
            item = CPListItem(text: "Nothing playing", detailText: "Pick something from the Queue tab.", image: nil)
        }

        let section = CPListSection(items: [item])
        let template = CPListTemplate(title: "Now Playing", sections: [section])
        template.tabImage = UIImage(systemName: "waveform")
        return template
    }

    private func makeQueueTab() -> CPTemplate {
        let context = makeContext()
        let queueItems = (try? context?.fetch(FetchDescriptor<QueueItem>())) ?? []
        let ordered = queueItems.sorted { $0.position < $1.position }

        let listItems: [CPListItem] = ordered.prefix(40).map { queueItem in
            let episode = queueItem.episode
            let item = CPListItem(
                text: episode.title,
                detailText: episode.podcast.title,
                image: nil
            )
            let episodeID = episode.id
            item.handler = { _, completion in
                Task { @MainActor in
                    await PlaybackControllerProxy.play(episodeID: episodeID)
                    completion()
                }
            }
            return item
        }

        let body: [CPListSection]
        if listItems.isEmpty {
            let empty = CPListItem(text: "Queue is empty", detailText: "Add an episode in the app first.", image: nil)
            body = [CPListSection(items: [empty])]
        } else {
            body = [CPListSection(items: listItems, header: "Up Next", sectionIndexTitle: nil)]
        }

        let template = CPListTemplate(title: "Queue", sections: body)
        template.tabImage = UIImage(systemName: "text.badge.plus")
        return template
    }

    private func makeLibraryTab() -> CPTemplate {
        let context = makeContext()
        let podcasts = (try? context?.fetch(
            FetchDescriptor<Podcast>(predicate: #Predicate<Podcast> { $0.isSubscribed == true })
        )) ?? []

        let items: [CPListItem] = podcasts.prefix(40).map { podcast in
            let item = CPListItem(text: podcast.title, detailText: podcast.author, image: nil)
            let podcastID = podcast.id
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    self?.pushPodcast(id: podcastID)
                    completion()
                }
            }
            return item
        }

        let body: [CPListSection] = items.isEmpty
            ? [CPListSection(items: [CPListItem(text: "No subscriptions", detailText: "Subscribe to a show in the app.", image: nil)])]
            : [CPListSection(items: items, header: "Shows", sectionIndexTitle: nil)]

        let template = CPListTemplate(title: "Library", sections: body)
        template.tabImage = UIImage(systemName: "books.vertical")
        return template
    }

    @MainActor
    private func pushPodcast(id: UUID) {
        guard let context = makeContext() else { return }
        let descriptor = FetchDescriptor<Podcast>(predicate: #Predicate<Podcast> { $0.id == id })
        guard let podcast = try? context.fetch(descriptor).first else { return }

        let episodes = podcast.episodes
            .sorted { $0.pubDate > $1.pubDate }
            .prefix(40)

        let items: [CPListItem] = episodes.map { episode in
            let label = EpisodeDurationFormatter.short(episode.duration ?? 0)
            let item = CPListItem(text: episode.title, detailText: label.isEmpty ? podcast.title : "\(podcast.title) · \(label)", image: nil)
            let episodeID = episode.id
            item.handler = { _, completion in
                Task { @MainActor in
                    await PlaybackControllerProxy.play(episodeID: episodeID)
                    completion()
                }
            }
            return item
        }

        let template = CPListTemplate(title: podcast.title, sections: [CPListSection(items: items)])
        interfaceController?.pushTemplate(template, animated: true) { _, _ in }
    }

    // MARK: - SwiftData context

    private func makeContext() -> ModelContext? {
        // Pull the shared model container from the running app instance.
        // The CarPlay scene runs in the same process as the host app.
        return ModelContainerRef.shared?.mainContext
    }
}

/// Holds a process-wide reference to the active model container so background
/// scenes (CarPlay) can read SwiftData without an environment value.
@MainActor
enum ModelContainerRef {
    static var shared: ModelContainer?
}

/// Tiny actor-isolated wrapper so CarPlay closures don't have to import
/// PlaybackController internals directly.
@MainActor
enum PlaybackControllerProxy {
    static func play(episodeID: UUID) async {
        let player = PlaybackController.shared
        let context = ModelContainerRef.shared?.mainContext
        guard let context else { return }
        let descriptor = FetchDescriptor<Episode>(predicate: #Predicate<Episode> { $0.id == episodeID })
        guard let episode = try? context.fetch(descriptor).first else { return }
        player.play(episode, in: context)
    }

    @discardableResult
    static func toggle() async -> Bool? {
        let player = PlaybackController.shared
        guard player.currentEpisode != nil else { return nil }
        player.togglePlayPause()
        return player.isPlaying
    }
}

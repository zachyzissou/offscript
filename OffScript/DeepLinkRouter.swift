import Foundation
import OSLog
import SwiftData
import SwiftUI

private let deepLinkLogger = Logger(subsystem: "com.offscript", category: "DeepLink")

/// App-local notifications used to route events between independent SwiftUI
/// surfaces without threading bindings through the whole shell.
extension Notification.Name {
    static let offscriptSwitchTab = Notification.Name("offscript.switchTab")
    static let offscriptActiveTabChanged = Notification.Name("offscript.activeTabChanged")
    static let offscriptRecommendationFeedbackChanged = Notification.Name("offscript.recommendationFeedbackChanged")
    static let offscriptLibrarySubscriptionsChanged = Notification.Name("offscript.librarySubscriptionsChanged")
    /// Posted by `DeepLinkRouter` when an `offscript://podcast/<uuid>` URL
    /// resolves to a real podcast. `LibraryView` listens and pushes
    /// `PodcastDetailView` via its existing `selectedPodcastID` binding.
    /// `userInfo["podcastID"]: UUID`.
    static let offscriptOpenPodcast = Notification.Name("offscript.openPodcast")
}

/// Centralized handler for `offscript://` URLs coming from:
///   - The Now Playing widget (tap → open the player)
///   - The Live Activity / Dynamic Island (tap → open the player)
///   - Spotlight search results (uniqueIdentifier carries the episode UUID)
///   - Future: shared episode links between users
///
/// URL grammar:
///   offscript://player                  → present full player on current playback
///   offscript://episode/<uuid>          → fetch episode + present detail
///   offscript://episode/<uuid>/play     → fetch episode + play immediately
///   offscript://podcast/<uuid>          → fetch podcast + present detail
///   offscript://tab/<home|library|queue|search>
///                                        → switch the tab bar selection
@MainActor
enum DeepLinkRouter {
    /// Pushed by ContentView's `.onOpenURL`. Reads the URL into a route,
    /// hydrates from SwiftData if needed, then mutates shared singletons
    /// (PlaybackController, navigation state) to drive UI.
    static func handle(_ url: URL, in context: ModelContext) {
        guard url.scheme == "offscript" else {
            deepLinkLogger.warning("Ignoring URL with non-offscript scheme: \(url.absoluteString, privacy: .public)")
            return
        }

        let host = url.host(percentEncoded: false) ?? ""
        let segments = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "player":
            // Open the player on whatever's currently loaded. If nothing's
            // loaded, restoreLastSessionIfNeeded already populated the
            // mini-player on launch, so the user sees that.
            if PlaybackController.shared.currentEpisode != nil {
                PlaybackController.shared.isPlayerPresented = true
            }

        case "episode":
            guard let uuidString = segments.first,
                  let episodeID = UUID(uuidString: uuidString) else {
                deepLinkLogger.warning("Invalid episode deep link: \(url.absoluteString, privacy: .public)")
                return
            }
            handleEpisode(id: episodeID, autoplay: segments.contains("play"), in: context)

        case "podcast":
            guard let uuidString = segments.first,
                  let podcastID = UUID(uuidString: uuidString) else {
                deepLinkLogger.warning("Invalid podcast deep link: \(url.absoluteString, privacy: .public)")
                return
            }
            handlePodcast(id: podcastID, in: context)

        case "tab":
            // offscript://tab/<name> — useful for widget shortcuts, debug
            // automation, and future Shortcuts integration. Validated against
            // a known set so an unknown tab name doesn't silently swap to
            // home (which would mask the bug).
            guard let tabName = segments.first?.lowercased(),
                  ["home", "library", "queue", "search"].contains(tabName) else {
                deepLinkLogger.warning("Invalid tab deep link: \(url.absoluteString, privacy: .public)")
                return
            }
            NotificationCenter.default.post(
                name: .offscriptSwitchTab,
                object: nil,
                userInfo: ["tab": tabName]
            )

        default:
            deepLinkLogger.warning("Unknown deep link host: \(host, privacy: .public)")
        }
    }

    private static func handleEpisode(id: UUID, autoplay: Bool, in context: ModelContext) {
        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        let episode: Episode?
        do {
            episode = try context.fetch(descriptor).first
        } catch {
            deepLinkLogger.error("Episode deep-link fetch failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let episode else {
            deepLinkLogger.warning("Episode not found for deep link: \(id, privacy: .public)")
            return
        }

        if autoplay {
            PlaybackController.shared.play(episode, in: context)
        } else {
            // Load the episode (sets up the player item + seeks to saved
            // position) but do not start playback. The user triggered this
            // from Spotlight / a widget tap and may just want to inspect the
            // episode before deciding to play.
            PlaybackController.shared.load(episode, in: context)
            PlaybackController.shared.isPlayerPresented = true
        }
    }

    private static func handlePodcast(id: UUID, in context: ModelContext) {
        // Verify the podcast exists in SwiftData before routing — a stale
        // Spotlight donation pointing at a deleted podcast would otherwise
        // switch to Library and push an empty detail view.
        var descriptor = FetchDescriptor<Podcast>(
            predicate: #Predicate<Podcast> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            guard try context.fetch(descriptor).first != nil else {
                deepLinkLogger.warning("Podcast deep link missed — id \(id, privacy: .public) not in store")
                return
            }
        } catch {
            deepLinkLogger.error("Podcast deep-link fetch failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }

        // Switch to the Library tab first so the LibraryView NavigationStack
        // is on screen when the open-podcast notification lands. The
        // notification carries the UUID — LibraryView listens and binds
        // to its existing `selectedPodcastID` state.
        NotificationCenter.default.post(
            name: .offscriptSwitchTab,
            object: nil,
            userInfo: ["tab": "library"]
        )
        NotificationCenter.default.post(
            name: .offscriptOpenPodcast,
            object: nil,
            userInfo: ["podcastID": id]
        )
    }
}

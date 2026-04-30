import Foundation
import OSLog
import SwiftData
import SwiftUI

private let deepLinkLogger = Logger(subsystem: "com.offscript", category: "DeepLink")

/// App-local notifications used to route events between independent SwiftUI
/// surfaces without threading bindings through the whole shell.
extension Notification.Name {
    static let offscriptSwitchTab = Notification.Name("offscript.switchTab")
    static let offscriptRecommendationFeedbackChanged = Notification.Name("offscript.recommendationFeedbackChanged")
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
        guard let episode = try? context.fetch(descriptor).first else {
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
        // Podcast deep linking still TODO — needs navigation state to push
        // PodcastDetailView from outside the LibraryView NavigationStack.
        // Logged so we know if anyone's hitting these URLs in the wild.
        deepLinkLogger.info("Podcast deep link received but navigation not yet wired: \(id, privacy: .public)")
    }
}

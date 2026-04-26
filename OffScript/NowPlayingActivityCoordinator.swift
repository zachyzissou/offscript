import ActivityKit
import Foundation
import OSLog

@MainActor
final class NowPlayingActivityCoordinator {
    static let shared = NowPlayingActivityCoordinator()

    private let logger = Logger(subsystem: "OffScript", category: "LiveActivity")
    private var activity: Activity<NowPlayingAttributes>?
    private var lastUpdate: Date = .distantPast
    private let throttleInterval: TimeInterval = 4

    private init() {}

    func start(
        episodeID: String,
        episodeTitle: String,
        podcastTitle: String,
        artworkURL: URL?,
        elapsed: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool,
        playbackRate: Double
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activities disabled — skipping start")
            return
        }

        let state = NowPlayingAttributes.State(
            episodeTitle: episodeTitle,
            podcastTitle: podcastTitle,
            artworkURL: artworkURL,
            elapsed: elapsed,
            duration: duration,
            isPlaying: isPlaying,
            playbackRate: playbackRate
        )

        if let existing = activity, existing.attributes.episodeID == episodeID {
            Task { await existing.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }

        Task { await activity?.end(nil, dismissalPolicy: .immediate) }

        do {
            activity = try Activity.request(
                attributes: NowPlayingAttributes(episodeID: episodeID),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            lastUpdate = .now
            logger.info("Started Live Activity for episode \(episodeID, privacy: .public)")
        } catch {
            logger.error("Failed to start Live Activity: \(String(describing: error), privacy: .public)")
        }
    }

    func update(
        elapsed: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool,
        playbackRate: Double,
        force: Bool = false
    ) {
        guard let activity else { return }

        if !force && Date().timeIntervalSince(lastUpdate) < throttleInterval && isPlaying {
            return
        }

        let current = activity.content.state
        let state = NowPlayingAttributes.State(
            episodeTitle: current.episodeTitle,
            podcastTitle: current.podcastTitle,
            artworkURL: current.artworkURL,
            elapsed: elapsed,
            duration: duration,
            isPlaying: isPlaying,
            playbackRate: playbackRate
        )
        lastUpdate = .now
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
    }
}

import ActivityKit
import Foundation
import OSLog

/// Mirror of `NowPlayingActivityAttributes` defined in OffScriptWidgets.
/// ActivityKit requires both the producer (main app) and consumer (widget
/// extension) to compile the same struct definition — so we duplicate it
/// here. Keep the two files in sync.
public struct NowPlayingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var episodeTitle: String
        public var podcastTitle: String
        public var isPlaying: Bool
        public var currentTime: TimeInterval
        public var duration: TimeInterval

        public init(
            episodeTitle: String,
            podcastTitle: String,
            isPlaying: Bool,
            currentTime: TimeInterval,
            duration: TimeInterval
        ) {
            self.episodeTitle = episodeTitle
            self.podcastTitle = podcastTitle
            self.isPlaying = isPlaying
            self.currentTime = currentTime
            self.duration = duration
        }

        public var progress: Double {
            guard duration > 0 else { return 0 }
            return min(max(currentTime / duration, 0), 1)
        }
    }

    public var artworkURL: URL?

    public init(artworkURL: URL? = nil) {
        self.artworkURL = artworkURL
    }
}

/// Lifecycle helpers for Live Activities. `NowPlayingPublisher` owns the
/// happy-path start/update/end calls; this enum is the catch-all for edge
/// cases (app re-launch with stale activities still pinned to the Dynamic
/// Island, force-quit recovery, etc.).
enum NowPlayingActivityCoordinator {
    private static let logger = Logger(subsystem: "com.offscript", category: "LiveActivity")

    /// Called once at app launch. ActivityKit doesn't auto-end activities
    /// when the host app is force-quit — they keep ticking with frozen state
    /// until the user dismisses them, which looks like a ghost. We
    /// authoritatively end every still-running NowPlaying activity here so
    /// the user gets a clean slate on each launch; `NowPlayingPublisher` will
    /// re-create one on the first state change if playback resumes.
    ///
    /// `dismissalPolicy: .immediate` removes them from the Lock Screen and
    /// Dynamic Island right away — anything else would leave the stale UI
    /// visible during the dismissal grace period.
    @MainActor
    static func endStaleActivities() async {
        let activities = Activity<NowPlayingActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        logger.info("Ending \(activities.count, privacy: .public) stale Live Activities at launch")
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// End every currently-running NowPlaying Live Activity. Unlike
    /// `endStaleActivities()` (which is a launch-time sweep), this is the
    /// in-session helper called on episode transitions: ActivityKit stores
    /// `artworkURL` in the Activity's *attributes*, which can't be mutated
    /// via `activity.update()` — only ContentState fields can. So a long-
    /// running activity that survives an episode change keeps the previous
    /// episode's artwork pinned to the Dynamic Island / Lock Screen even
    /// though the title/progress update correctly. Ending here lets
    /// `NowPlayingPublisher` re-request a fresh activity with the new
    /// episode's artwork on the next state tick.
    @MainActor
    static func endCurrent() async {
        let activities = Activity<NowPlayingActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

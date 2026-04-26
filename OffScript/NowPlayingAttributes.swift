import ActivityKit
import Foundation

/// Shared between the main app (which starts/updates the activity) and the
/// widget extension (which renders the lock-screen + Dynamic Island UI).
struct NowPlayingAttributes: ActivityAttributes {
    public typealias ContentState = State

    public struct State: Codable, Hashable {
        public var episodeTitle: String
        public var podcastTitle: String
        public var artworkURL: URL?
        public var elapsed: TimeInterval
        public var duration: TimeInterval
        public var isPlaying: Bool
        public var playbackRate: Double

        public init(
            episodeTitle: String,
            podcastTitle: String,
            artworkURL: URL?,
            elapsed: TimeInterval,
            duration: TimeInterval,
            isPlaying: Bool,
            playbackRate: Double
        ) {
            self.episodeTitle = episodeTitle
            self.podcastTitle = podcastTitle
            self.artworkURL = artworkURL
            self.elapsed = elapsed
            self.duration = duration
            self.isPlaying = isPlaying
            self.playbackRate = playbackRate
        }

        public var progress: Double {
            guard duration > 0 else { return 0 }
            return min(max(elapsed / duration, 0), 1)
        }

        public var remaining: TimeInterval {
            max(0, duration - elapsed)
        }
    }

    public var episodeID: String

    public init(episodeID: String) {
        self.episodeID = episodeID
    }
}

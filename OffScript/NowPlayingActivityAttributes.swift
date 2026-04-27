import ActivityKit
import Foundation

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

import Foundation
import WidgetKit

/// Bridge between the main app and the OffScriptWidgets extension. The app writes
/// the current playback snapshot here on every state change; the home-screen widget
/// reads it from the same suite via App Group entitlement.
public enum SharedNowPlayingState {
    public static let appGroup = "group.com.offscript.app"
    public static let widgetKind = "com.offscript.widget.nowplaying"

    private static let snapshotKey = "offscript.shared.nowPlaying"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    public struct Snapshot: Codable, Equatable {
        public var episodeID: String
        public var episodeTitle: String
        public var podcastTitle: String
        public var artworkURLString: String?
        public var elapsed: TimeInterval
        public var duration: TimeInterval
        public var isPlaying: Bool
        public var playbackRate: Double
        public var capturedAt: Date

        public init(
            episodeID: String,
            episodeTitle: String,
            podcastTitle: String,
            artworkURLString: String?,
            elapsed: TimeInterval,
            duration: TimeInterval,
            isPlaying: Bool,
            playbackRate: Double,
            capturedAt: Date = .now
        ) {
            self.episodeID = episodeID
            self.episodeTitle = episodeTitle
            self.podcastTitle = podcastTitle
            self.artworkURLString = artworkURLString
            self.elapsed = elapsed
            self.duration = duration
            self.isPlaying = isPlaying
            self.playbackRate = playbackRate
            self.capturedAt = capturedAt
        }

        public var artworkURL: URL? {
            artworkURLString.flatMap(URL.init(string:))
        }

        public var progress: Double {
            guard duration > 0 else { return 0 }
            return min(max(elapsed / duration, 0), 1)
        }

        /// Estimate of elapsed at the current moment, projecting forward from
        /// when the snapshot was captured if playback was active.
        public func projectedElapsed(at moment: Date = .now) -> TimeInterval {
            guard isPlaying else { return elapsed }
            let delta = moment.timeIntervalSince(capturedAt) * max(playbackRate, 0.5)
            return min(elapsed + delta, duration)
        }
    }

    public static func read() -> Snapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    public static func write(_ snapshot: Snapshot?) {
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        } else {
            defaults.removeObject(forKey: snapshotKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

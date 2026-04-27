import Foundation

/// Plain-data snapshot of the currently playing episode. Written by the main
/// app to the shared App Group UserDefaults whenever playback state changes;
/// read by the widget extension on each timeline refresh.
///
/// Codable so we can serialize via JSON; no SwiftData / no AVFoundation
/// dependencies — keeps the extension binary tiny.
struct NowPlayingSnapshot: Codable, Equatable {
    var episodeTitle: String
    var podcastTitle: String
    var artworkURL: URL?
    var isPlaying: Bool
    var currentTime: TimeInterval
    var duration: TimeInterval
    var updatedAt: Date

    static let empty = NowPlayingSnapshot(
        episodeTitle: "",
        podcastTitle: "",
        artworkURL: nil,
        isPlaying: false,
        currentTime: 0,
        duration: 0,
        updatedAt: .distantPast
    )

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var isActive: Bool { !episodeTitle.isEmpty }
}

/// Shared storage helper used by both the main app (writer) and the widget
/// extension (reader). Suite must be entitled in both targets via App Groups.
enum NowPlayingStorage {
    // Must match OffScript/SharedNowPlayingState.swift exactly. Both
    // targets' .entitlements files must declare this identifier.
    static let suiteName = "group.com.offscript.shared"
    private static let key = "nowPlayingSnapshot"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func write(_ snapshot: NowPlayingSnapshot) {
        guard let defaults = defaults else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    static func read() -> NowPlayingSnapshot {
        guard let defaults = defaults,
              let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(NowPlayingSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}

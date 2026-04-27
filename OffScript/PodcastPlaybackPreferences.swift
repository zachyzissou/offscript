import Foundation

/// Per-podcast playback preferences kept in UserDefaults instead of
/// SwiftData. These are pure UI state (the user changed the speed in the
/// player menu) and don't need to round-trip through iCloud sync, so they
/// live entirely off the model graph — keeps the schema stable and avoids
/// a migration for what's effectively a setting.
///
/// Storage layout: a single `[String: Float]` dict on UserDefaults keyed
/// by the podcast's UUID string. Empty / missing keys mean "use the
/// global default."
enum PodcastPlaybackPreferences {
    private static let podcastRatesKey = "offscript.podcastRates"
    private static let globalRateKey = "offscript.playbackRate.global"

    /// Resolve the per-podcast rate, returning nil when none is set so the
    /// caller can fall back to the global default. Bounded to [0.5, 3.0×]
    /// so a corrupted store never produces a silent / runaway player.
    static func preferredRate(for podcast: Podcast) -> Float? {
        let store = UserDefaults.standard.dictionary(forKey: podcastRatesKey) as? [String: Double] ?? [:]
        guard let raw = store[podcast.id.uuidString] else { return nil }
        let clamped = max(0.5, min(3.0, raw))
        return Float(clamped)
    }

    static func setPreferredRate(_ rate: Float, for podcast: Podcast) {
        var store = UserDefaults.standard.dictionary(forKey: podcastRatesKey) as? [String: Double] ?? [:]
        // Allow "reset to default" by passing 1.0× when no global override
        // exists — keeps the store small in the common case.
        if abs(rate - globalDefault) < 0.001 {
            store.removeValue(forKey: podcast.id.uuidString)
        } else {
            store[podcast.id.uuidString] = Double(max(0.5, min(3.0, rate)))
        }
        UserDefaults.standard.set(store, forKey: podcastRatesKey)
    }

    /// Drop the podcast's preferred rate so it falls back to the global
    /// default on the next play. Used by the "reset" affordance in the
    /// speed menu.
    static func clearPreferredRate(for podcast: Podcast) {
        var store = UserDefaults.standard.dictionary(forKey: podcastRatesKey) as? [String: Double] ?? [:]
        store.removeValue(forKey: podcast.id.uuidString)
        UserDefaults.standard.set(store, forKey: podcastRatesKey)
    }

    /// Default rate used when the podcast has no preference set yet. Falls
    /// back to 1.0× when the user has never picked a global default.
    static var globalDefault: Float {
        let raw = UserDefaults.standard.double(forKey: globalRateKey)
        guard raw > 0 else { return 1.0 }
        return Float(max(0.5, min(3.0, raw)))
    }

    static func setGlobalDefault(_ rate: Float) {
        UserDefaults.standard.set(Double(max(0.5, min(3.0, rate))), forKey: globalRateKey)
    }
}

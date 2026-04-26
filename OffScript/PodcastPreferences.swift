import Foundation

/// Per-podcast preferences keyed by podcast UUID. Stored in UserDefaults so we
/// don't have to migrate the SwiftData schema for what amounts to a few
/// scalars per show.
enum PodcastPreferences {
    private static let introKey = "offscript.podcastSkipIntroSeconds"
    private static let outroKey = "offscript.podcastSkipOutroSeconds"
    private static let rateKey  = "offscript.podcastPlaybackRate"
    private static let notifyKey = "offscript.podcastNotificationsEnabled"

    /// Seconds of intro to skip when a new episode starts. Default 0.
    static func skipIntroSeconds(for podcastID: UUID) -> Int {
        dictionary(forKey: introKey)[podcastID.uuidString] as? Int ?? 0
    }

    static func setSkipIntroSeconds(_ seconds: Int, for podcastID: UUID) {
        var dict = dictionary(forKey: introKey)
        if seconds == 0 {
            dict.removeValue(forKey: podcastID.uuidString)
        } else {
            dict[podcastID.uuidString] = seconds
        }
        UserDefaults.standard.set(dict, forKey: introKey)
    }

    /// Seconds before the end to consider "outro" — used by the player to fade
    /// gracefully into the next-up card.
    static func skipOutroSeconds(for podcastID: UUID) -> Int {
        dictionary(forKey: outroKey)[podcastID.uuidString] as? Int ?? 0
    }

    static func setSkipOutroSeconds(_ seconds: Int, for podcastID: UUID) {
        var dict = dictionary(forKey: outroKey)
        if seconds == 0 {
            dict.removeValue(forKey: podcastID.uuidString)
        } else {
            dict[podcastID.uuidString] = seconds
        }
        UserDefaults.standard.set(dict, forKey: outroKey)
    }

    /// Per-podcast playback rate override. Returns nil for "use global default".
    static func playbackRate(for podcastID: UUID) -> Float? {
        let dict = dictionary(forKey: rateKey)
        guard let raw = dict[podcastID.uuidString] as? Double else { return nil }
        return Float(raw)
    }

    static func setPlaybackRate(_ rate: Float?, for podcastID: UUID) {
        var dict = dictionary(forKey: rateKey)
        if let rate {
            dict[podcastID.uuidString] = Double(rate)
        } else {
            dict.removeValue(forKey: podcastID.uuidString)
        }
        UserDefaults.standard.set(dict, forKey: rateKey)
    }

    /// Per-podcast new-episode notification toggle. Default false.
    static func notificationsEnabled(for podcastID: UUID) -> Bool {
        dictionary(forKey: notifyKey)[podcastID.uuidString] as? Bool ?? false
    }

    static func setNotificationsEnabled(_ enabled: Bool, for podcastID: UUID) {
        var dict = dictionary(forKey: notifyKey)
        if enabled {
            dict[podcastID.uuidString] = true
        } else {
            dict.removeValue(forKey: podcastID.uuidString)
        }
        UserDefaults.standard.set(dict, forKey: notifyKey)
    }

    private static func dictionary(forKey key: String) -> [String: Any] {
        UserDefaults.standard.dictionary(forKey: key) ?? [:]
    }
}

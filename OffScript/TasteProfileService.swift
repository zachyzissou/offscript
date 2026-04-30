import Foundation
import SwiftData

@MainActor
enum TasteProfileService {
    private static let refreshInterval: TimeInterval = 10 * 60

    static func loadOrCreate(in context: ModelContext) throws -> UserTasteProfile {
        let descriptor = FetchDescriptor<UserTasteProfile>()
        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let profile = UserTasteProfile()
        context.insert(profile)
        try context.save()
        return profile
    }

    static func refresh(in context: ModelContext, force: Bool = false) throws {
        let profile = try loadOrCreate(in: context)
        let hasUsableProfile = !profile.topTags.isEmpty
            || !profile.showAffinity.isEmpty
            || !profile.preferredGenres.isEmpty
        if !force, hasUsableProfile, Date().timeIntervalSince(profile.lastUpdatedAt) < refreshInterval {
            return
        }

        let episodeProfiles = try context.fetch(FetchDescriptor<EpisodeProfile>())
        let playbackEvents = try context.fetch(FetchDescriptor<PlaybackEvent>())
        let preferenceSignals = try context.fetch(FetchDescriptor<PreferenceSignal>())

        let profileByEpisodeID = Dictionary(uniqueKeysWithValues: episodeProfiles.map { ($0.episodeID, $0) })
        var tagScores: [String: Double] = [:]

        for signal in preferenceSignals {
            guard let episodeProfile = profileByEpisodeID[signal.episode.id] else { continue }
            let weight = preferenceWeight(signal.action) * recencyWeight(for: signal.date)
            for tag in episodeProfile.tags {
                tagScores[tag.normalizedTasteKey, default: 0] += weight
            }
        }

        for event in playbackEvents {
            guard let episode = event.episode,
                  let episodeProfile = profileByEpisodeID[episode.id] else { continue }
            let weight = playbackTagWeight(event.kind) * recencyWeight(for: event.date)
            guard weight != 0 else { continue }
            for tag in episodeProfile.tags {
                tagScores[tag.normalizedTasteKey, default: 0] += weight
            }
        }

        profile.topTags = tagScores
            .filter { !$0.key.isEmpty && $0.value > 0 }
            .sorted { lhs, rhs in
                if abs(lhs.value - rhs.value) < 0.001 { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(8)
            .map(\.key)

        let completedDurations = playbackEvents
            .filter { $0.kind == .completed }
            .compactMap { $0.episode?.duration }
            .map { $0 / 60 }

        if !completedDurations.isEmpty {
            profile.averageCompletedDurationMinutes = completedDurations.reduce(0, +) / Double(completedDurations.count)
        }

        var showScores: [String: Double] = [:]
        for signal in preferenceSignals {
            let show = signal.episode.podcast.title
            let weight = preferenceWeight(signal.action) * recencyWeight(for: signal.date)
            showScores[show, default: 0] += weight
        }

        for event in playbackEvents {
            guard let show = event.episode?.podcast.title else { continue }
            let weight = playbackShowWeight(event.kind) * recencyWeight(for: event.date)
            guard weight != 0 else { continue }
            showScores[show, default: 0] += weight
        }
        profile.showAffinity = showScores
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if abs(lhs.value - rhs.value) < 0.001 { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(5)
            .map(\.key)

        let startedCount = max(playbackEvents.filter { $0.kind == .started || $0.kind == .resumed }.count, 1)
        let unfinishedCount = playbackEvents.filter { $0.kind == .abandoned || $0.kind == .skippedQuickly }.count
        profile.unfinishedEpisodeAffinity = Double(unfinishedCount) / Double(startedCount)
        profile.prefersShortEpisodes = AppSettings.preferShortEpisodes || profile.averageCompletedDurationMinutes <= 35
        profile.preferredGenres = AppSettings.preferredGenres.map(\.title)
        profile.lastUpdatedAt = .now

        try context.save()
    }

    private static func preferenceWeight(_ action: PreferenceSignal.Action) -> Double {
        switch action {
        case .moreLikeThis: 8.0
        case .like: 5.0
        case .lessLikeThis: -3.5
        case .notInterested: -5.0
        }
    }

    private static func playbackTagWeight(_ kind: PlaybackEvent.Kind) -> Double {
        switch kind {
        case .completed: 1.5
        case .advancedFromQueue: 0.9
        case .resumed: 0.35
        case .skippedQuickly: -1.4
        case .abandoned: -0.8
        case .started, .seekedForward, .seekedBackward: 0
        }
    }

    private static func playbackShowWeight(_ kind: PlaybackEvent.Kind) -> Double {
        switch kind {
        case .completed: 2.0
        case .advancedFromQueue: 1.2
        case .resumed: 0.45
        case .skippedQuickly: -1.6
        case .abandoned: -1.0
        case .started, .seekedForward, .seekedBackward: 0
        }
    }

    private static func recencyWeight(for date: Date) -> Double {
        let days = max(0, Date().timeIntervalSince(date) / 86_400)
        return max(0.15, exp(-days / 60))
    }
}

private extension String {
    var normalizedTasteKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

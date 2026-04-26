import Foundation
import SwiftData

@MainActor
enum TasteProfileService {
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

    /// Refresh is expensive — it fetches every EpisodeProfile + PlaybackEvent +
    /// PreferenceSignal. Skip when the profile was updated within the last
    /// 90 seconds unless `force` is set. Each fetch is also bounded to a
    /// reasonable horizon so the work doesn't grow with library age.
    static func refresh(in context: ModelContext, force: Bool = false) throws {
        let profile = try loadOrCreate(in: context)
        if !force, Date().timeIntervalSince(profile.lastUpdatedAt) < 90 {
            return
        }

        var profilesDescriptor = FetchDescriptor<EpisodeProfile>()
        profilesDescriptor.fetchLimit = 1500
        let episodeProfiles = (try? context.fetch(profilesDescriptor)) ?? []

        let cutoff = Calendar.current.date(byAdding: .day, value: -120, to: Date()) ?? .distantPast
        var playbackDescriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate<PlaybackEvent> { $0.date >= cutoff }
        )
        playbackDescriptor.fetchLimit = 3000
        let playbackEvents = (try? context.fetch(playbackDescriptor)) ?? []

        var signalsDescriptor = FetchDescriptor<PreferenceSignal>(
            predicate: #Predicate<PreferenceSignal> { $0.date >= cutoff }
        )
        signalsDescriptor.fetchLimit = 1000
        let preferenceSignals = (try? context.fetch(signalsDescriptor)) ?? []

        let likedEpisodeIDs = Set(
            preferenceSignals
                .filter { $0.action == .like || $0.action == .moreLikeThis }
                .compactMap(\.episode?.id)
        )

        let likedTags = episodeProfiles
            .filter { likedEpisodeIDs.contains($0.episodeID) }
            .flatMap(\.tags)

        let tagCounts = Dictionary(likedTags.map { ($0, 1) }, uniquingKeysWith: +)
        profile.topTags = tagCounts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
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

        let completedShows = playbackEvents
            .filter { $0.kind == .completed || $0.kind == .resumed || $0.kind == .advancedFromQueue }
            .compactMap { $0.episode?.podcast.title }
        let showAffinityCounts = Dictionary(completedShows.map { ($0, 1) }, uniquingKeysWith: +)
        profile.showAffinity = showAffinityCounts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
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
}

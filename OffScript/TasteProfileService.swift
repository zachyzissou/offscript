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

    static func refresh(in context: ModelContext) throws {
        let profile = try loadOrCreate(in: context)
        let episodeProfiles = try context.fetch(FetchDescriptor<EpisodeProfile>())
        let playbackEvents = try context.fetch(FetchDescriptor<PlaybackEvent>())
        let preferenceSignals = try context.fetch(FetchDescriptor<PreferenceSignal>())

        let likedEpisodeIDs = Set(
            preferenceSignals
                .filter { $0.action == .like || $0.action == .moreLikeThis }
                .map(\.episode.id)
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

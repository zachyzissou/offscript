import Foundation
import SwiftData

struct RecommendationScoreInputs {
    let recencyDays: Double
    let durationMinutes: Double
    let topicOverlap: Double
    let isFromSubscribedPodcast: Bool
    let isUnfinished: Bool
}

enum RecommendationScorer {
    static func score(_ input: RecommendationScoreInputs) -> Double {
        let recency = exp(-input.recencyDays / 10.0) * 0.28
        let durationFit = durationScore(minutes: input.durationMinutes) * 0.18
        let topic = min(1.0, input.topicOverlap / 3.0) * 0.26
        let subscription = (input.isFromSubscribedPodcast ? 1.0 : 0.0) * 0.12
        let unfinished = (input.isUnfinished ? 1.0 : 0.0) * 0.16
        return recency + durationFit + topic + subscription + unfinished
    }

    static func durationScore(minutes: Double) -> Double {
        switch minutes {
        case ..<12:
            return 0.45
        case 12...35:
            return 1.0
        case 35...60:
            return 0.8
        default:
            return 0.55
        }
    }
}

final class RecommendationService {
    @MainActor
    func homeSections(context: ModelContext, limit: Int = 6) throws -> [HomeFeedSection] {
        let episodes = try context.fetch(FetchDescriptor<Episode>())
            .filter { $0.podcast.isSubscribed }
            .sorted { $0.pubDate > $1.pubDate }

        let profiles = try context.fetch(FetchDescriptor<EpisodeProfile>())
        let preferences = try context.fetch(FetchDescriptor<PreferenceSignal>())
        let likedEpisodeIDs = Set(preferences.filter { $0.action == .like || $0.action == .moreLikeThis }.map(\.episode.id))
        let dislikedEpisodeIDs = Set(preferences.filter { $0.action == .notInterested || $0.action == .lessLikeThis }.map(\.episode.id))
        let likedTags = Set(
            profiles
                .filter { likedEpisodeIDs.contains($0.episodeID) }
                .flatMap(\.tags)
        )

        let scoredEpisodes = episodes
            .filter { !dislikedEpisodeIDs.contains($0.id) }
            .map { episode in
                ScoredEpisode(
                    episode: episode,
                    score: score(episode: episode, profiles: profiles, likedTags: likedTags)
                )
            }
            .sorted { $0.score > $1.score }

        let bestNext = Array(scoredEpisodes.prefix(limit).map(\.episode))
        let quickWins = scoredEpisodes
            .filter { (($0.episode.duration ?? 0) / 60) <= 35 }
            .prefix(limit)
            .map(\.episode)
        let fresh = episodes
            .filter { !$0.isPlayed }
            .sorted { $0.pubDate > $1.pubDate }
            .prefix(limit)
            .map(\.self)
        let becauseYouLiked = scoredEpisodes
            .filter { episodeHasTopicOverlap($0.episode, profiles: profiles, likedTags: likedTags) }
            .prefix(limit)
            .map(\.episode)

        return [
            HomeFeedSection(title: "Best Next", subtitle: "High-fit episodes based on your listening signals.", episodes: bestNext),
            HomeFeedSection(title: "Quick Wins", subtitle: "Short listens that still feel worth opening right now.", episodes: Array(quickWins)),
            HomeFeedSection(title: "Fresh From Library", subtitle: "Recent drops from shows you already care about.", episodes: Array(fresh)),
            HomeFeedSection(title: "Because You Liked", subtitle: "Similar ideas and voices from your recent favorites.", episodes: Array(becauseYouLiked))
        ].filter { !$0.episodes.isEmpty }
    }

    private func score(episode: Episode, profiles: [EpisodeProfile], likedTags: Set<String>) -> Double {
        let profile = profiles.first(where: { $0.episodeID == episode.id })
        let overlap = Double(Set(profile?.tags ?? []).intersection(likedTags).count)
        let days = max(0, Date().timeIntervalSince(episode.pubDate) / 86_400.0)
        let minutes = (episode.duration ?? 30 * 60) / 60
        var value = RecommendationScorer.score(
            RecommendationScoreInputs(
                recencyDays: days,
                durationMinutes: minutes,
                topicOverlap: overlap,
                isFromSubscribedPodcast: episode.podcast.isSubscribed,
                isUnfinished: episode.playedPosition > 0 && !episode.isPlayed
            )
        )
        if UserDefaults.standard.bool(forKey: "offscript.preferShortEpisodes"), minutes <= 35 {
            value += 0.08
        }
        return value
    }

    private func episodeHasTopicOverlap(_ episode: Episode, profiles: [EpisodeProfile], likedTags: Set<String>) -> Bool {
        guard let profile = profiles.first(where: { $0.episodeID == episode.id }) else { return false }
        return !Set(profile.tags).intersection(likedTags).isEmpty
    }
}

private struct ScoredEpisode {
    let episode: Episode
    let score: Double
}

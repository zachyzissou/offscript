import Foundation
import SwiftData

struct RecommendationScoreInputs {
    let recencyDays: Double
    let durationMinutes: Double
    let topicOverlap: Double
    let isFromSubscribedPodcast: Bool
    let isUnfinished: Bool
    let preferredDurationMinutes: Double?

    // Memberwise init with `preferredDurationMinutes` defaulting to nil so
    // existing call sites (and tests) don't have to thread the optional
    // through everywhere when there's no taste profile yet.
    init(
        recencyDays: Double,
        durationMinutes: Double,
        topicOverlap: Double,
        isFromSubscribedPodcast: Bool,
        isUnfinished: Bool,
        preferredDurationMinutes: Double? = nil
    ) {
        self.recencyDays = recencyDays
        self.durationMinutes = durationMinutes
        self.topicOverlap = topicOverlap
        self.isFromSubscribedPodcast = isFromSubscribedPodcast
        self.isUnfinished = isUnfinished
        self.preferredDurationMinutes = preferredDurationMinutes
    }
}

enum RecommendationScorer {
    static func score(_ input: RecommendationScoreInputs) -> Double {
        let recency = exp(-input.recencyDays / 10.0) * 0.28
        let durationFit = durationScore(minutes: input.durationMinutes, preferredMinutes: input.preferredDurationMinutes) * 0.18
        let topic = min(1.0, input.topicOverlap / 3.0) * 0.26
        let subscription = (input.isFromSubscribedPodcast ? 1.0 : 0.0) * 0.12
        let unfinished = (input.isUnfinished ? 1.0 : 0.0) * 0.16
        return recency + durationFit + topic + subscription + unfinished
    }

    static func genreBoost(podcastCategories: [String], preferredGenres: [String]) -> Double {
        let normalizedCategories = Set(podcastCategories.map { $0.lowercased() })
        let normalizedPreferred = Set(preferredGenres.map { $0.lowercased() })
        let overlapCount = normalizedCategories.intersection(normalizedPreferred).count
        return 0.03 * Double(min(overlapCount, 3))
    }

    static func durationScore(minutes: Double, preferredMinutes: Double? = nil) -> Double {
        if let preferred = preferredMinutes, preferred > 0 {
            let sigma: Double = 15.0
            let diff = minutes - preferred
            return exp(-(diff * diff) / (2.0 * sigma * sigma))
        }
        // Static fallback when no user data
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
    let discoveryService = DiscoveryService()

    @MainActor
    func discoverySection(context: ModelContext) async -> HomeFeedSection? {
        guard let tasteProfile = try? TasteProfileService.loadOrCreate(in: context) else { return nil }

        // Only show discovery if the user has some taste data
        let hasData = !tasteProfile.topTags.isEmpty || !tasteProfile.preferredGenres.isEmpty
        guard hasData else { return nil }

        let podcasts = (try? context.fetch(FetchDescriptor<Podcast>(
            predicate: #Predicate<Podcast> { $0.isSubscribed == true }
        ))) ?? []
        let subscribedFeedURLs = Set(podcasts.map { $0.feedURL.absoluteString })

        let results = await discoveryService.discoverPodcasts(
            tasteProfile: tasteProfile,
            subscribedFeedURLs: subscribedFeedURLs
        )

        guard !results.isEmpty else { return nil }

        return HomeFeedSection(
            title: "Discover New Shows",
            subtitle: "Podcasts you haven't tried that match your taste.",
            discoveryResults: results
        )
    }

    @MainActor
    func homeSections(context: ModelContext, limit: Int = 6) throws -> [HomeFeedSection] {
        try? TasteProfileService.refresh(in: context)
        let episodes = try context.fetch(FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.podcast.isSubscribed == true },
            sortBy: [SortDescriptor(\Episode.pubDate, order: .reverse)]
        ))

        let profiles = try context.fetch(FetchDescriptor<EpisodeProfile>())
        // Only fetch preference signals from the last 90 days to avoid loading stale history
        let signalCutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? .distantPast
        let preferences = try context.fetch(FetchDescriptor<PreferenceSignal>(
            predicate: #Predicate<PreferenceSignal> { $0.date >= signalCutoff }
        ))
        let tasteProfile = try? TasteProfileService.loadOrCreate(in: context)
        let likedEpisodeIDs: Set<UUID> = Set(preferences.filter { $0.action == .like || $0.action == .moreLikeThis }.compactMap { (signal: PreferenceSignal) -> UUID? in signal.episode.id })
        let dislikedEpisodeIDs: Set<UUID> = Set(preferences.filter { $0.action == .notInterested || $0.action == .lessLikeThis }.compactMap { (signal: PreferenceSignal) -> UUID? in signal.episode.id })
        let likedTags = Set(
            profiles
                .filter { likedEpisodeIDs.contains($0.episodeID) }
                .flatMap(\.tags)
        )

        let scoredEpisodes = episodes
            .filter { !dislikedEpisodeIDs.contains($0.id) }
            .enumerated()
            .map { index, episode -> ScoredEpisode in
                let result = scoreWithExplanation(
                    episode: episode,
                    profiles: profiles,
                    likedTags: likedTags,
                    tasteProfile: tasteProfile,
                    diversityPenalty: Double(index) * 0.005
                )
                return ScoredEpisode(
                    episode: episode,
                    score: result.score,
                    explanation: result.explanation
                )
            }
            .sorted { $0.score > $1.score }

        var usedEpisodeIDs = Set<UUID>()

        let bestNext = Self.diversified(scoredEpisodes, limit: limit, excluding: &usedEpisodeIDs)
        let quickWins = Self.diversified(
            scoredEpisodes.filter { (($0.episode.duration ?? 0) / 60) <= 35 },
            limit: limit,
            excluding: &usedEpisodeIDs
        )
        let freshCandidates = episodes
            .filter { !$0.isPlayed && !usedEpisodeIDs.contains($0.id) }
            .sorted { $0.pubDate > $1.pubDate }
            .prefix(limit * 2)
            .map { episode -> ScoredEpisode in
                let days = max(0, Date().timeIntervalSince(episode.pubDate) / 86_400.0)
                let explanation: String
                if days <= 1 {
                    explanation = "Dropped today from \(episode.podcast.title)"
                } else {
                    explanation = "Fresh from \(episode.podcast.title) — \(Int(days))d ago"
                }
                return ScoredEpisode(episode: episode, score: 0, explanation: explanation)
            }
        let fresh = Self.diversified(Array(freshCandidates), limit: limit, excluding: &usedEpisodeIDs)
        let becauseYouLiked = Self.diversified(
            scoredEpisodes.filter { episodeHasTopicOverlap($0.episode, profiles: profiles, likedTags: likedTags) },
            limit: limit,
            excluding: &usedEpisodeIDs
        )

        var allSections = [
            HomeFeedSection(title: "Best Next", subtitle: "High-fit episodes based on your listening signals.", scoredEpisodes: bestNext),
            HomeFeedSection(title: "Quick Wins", subtitle: "Short listens that still feel worth opening right now.", scoredEpisodes: quickWins),
            HomeFeedSection(title: "Fresh From Library", subtitle: "Recent drops from shows you already care about.", scoredEpisodes: fresh),
            HomeFeedSection(title: "Because You Liked", subtitle: "Similar ideas and voices from your recent favorites.", scoredEpisodes: becauseYouLiked)
        ].filter { !$0.episodes.isEmpty }

        // Adaptive: during commute hours (6-9am, 5-8pm), surface Quick Wins first
        let hour = Calendar.current.component(.hour, from: Date())
        let isCommuteTime = (6...9).contains(hour) || (17...20).contains(hour)
        if isCommuteTime, let quickWinsIndex = allSections.firstIndex(where: { $0.title == "Quick Wins" }), quickWinsIndex > 0 {
            let quickWinsSection = allSections.remove(at: quickWinsIndex)
            allSections.insert(quickWinsSection, at: 0)
        }

        // Late evening (10pm+): surface longer, deeper episodes first
        let isLateEvening = hour >= 22 || hour < 5
        if isLateEvening, let bestNextIndex = allSections.firstIndex(where: { $0.title == "Best Next" }), bestNextIndex > 0 {
            let bestSection = allSections.remove(at: bestNextIndex)
            allSections.insert(bestSection, at: 0)
        }

        return allSections
    }

    private func scoreWithExplanation(
        episode: Episode,
        profiles: [EpisodeProfile],
        likedTags: Set<String>,
        tasteProfile: UserTasteProfile?,
        diversityPenalty: Double = 0
    ) -> (score: Double, explanation: String) {
        let profile = profiles.first(where: { $0.episodeID == episode.id })
        let matchingTags = Set(profile?.tags ?? []).intersection(likedTags)
        let overlap = Double(matchingTags.count)
        let days = max(0, Date().timeIntervalSince(episode.pubDate) / 86_400.0)
        let minutes = (episode.duration ?? 30 * 60) / 60
        let isUnfinished = episode.playedPosition > 0 && !episode.isPlayed

        let inputs = RecommendationScoreInputs(
            recencyDays: days,
            durationMinutes: minutes,
            topicOverlap: overlap,
            isFromSubscribedPodcast: episode.podcast.isSubscribed,
            isUnfinished: isUnfinished,
            preferredDurationMinutes: tasteProfile?.averageCompletedDurationMinutes
        )

        var value = RecommendationScorer.score(inputs) - diversityPenalty
        if AppSettings.preferShortEpisodes, minutes <= 35 {
            value += 0.08
        }

        if let tasteProfile {
            value += RecommendationScorer.genreBoost(
                podcastCategories: episode.podcast.categories.map { $0.lowercased() },
                preferredGenres: tasteProfile.preferredGenres.map { $0.lowercased() }
            )

            if tasteProfile.showAffinity.contains(episode.podcast.title) {
                value += 0.09
            }

            if !Set(profile?.tags ?? []).intersection(Set(tasteProfile.topTags)).isEmpty {
                value += 0.07
            }

            if tasteProfile.prefersShortEpisodes, minutes <= 35 {
                value += 0.05
            }

            if tasteProfile.unfinishedEpisodeAffinity < 0.2, isUnfinished {
                value += 0.04
            }
        }

        let explanation: String
        if isUnfinished {
            let remaining = max(0, (episode.duration ?? 0) - episode.playedPosition)
            explanation = "\(EpisodeDurationFormatter.short(remaining)) left — pick up where you stopped"
        } else if tasteProfile?.showAffinity.contains(episode.podcast.title) == true {
            explanation = "You keep finishing \(episode.podcast.title)"
        } else if overlap >= 3 {
            let sample = Array(matchingTags.prefix(2)).joined(separator: ", ")
            explanation = "\(Int(overlap)) topic matches: \(sample)"
        } else if let topTag = Set(profile?.tags ?? []).intersection(Set(tasteProfile?.topTags ?? [])).first {
            explanation = "Fits your recent interest in \"\(topTag)\""
        } else if overlap >= 1 {
            let sample = matchingTags.first ?? ""
            explanation = "Connects to \"\(sample)\" from episodes you liked"
        } else if days <= 1 {
            explanation = "Dropped today from \(episode.podcast.title)"
        } else if days <= 3 {
            explanation = "Fresh from \(episode.podcast.title) — \(Int(days))d ago"
        } else if minutes <= 20 {
            explanation = "Quick \(EpisodeDurationFormatter.short(episode.duration ?? 0)) listen"
        } else if episode.podcast.isSubscribed {
            explanation = "From your library — \(episode.podcast.title)"
        } else {
            explanation = "Picked for you"
        }

        return (value, explanation)
    }

    /// Returns contextual recommendations for the player based on the currently playing episode
    @MainActor
    func playerSuggestions(currentEpisode: Episode, context: ModelContext, limit: Int = 5) throws -> [ScoredEpisode] {
        // Filter at the database level: subscribed podcasts, unplayed episodes only
        let currentEpisodeID = currentEpisode.id
        let episodes = try context.fetch(FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.podcast.isSubscribed == true && $0.id != currentEpisodeID && $0.isPlayed == false }
        ))

        let profiles = try context.fetch(FetchDescriptor<EpisodeProfile>())
        let signalCutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? .distantPast
        let preferences = try context.fetch(FetchDescriptor<PreferenceSignal>(
            predicate: #Predicate<PreferenceSignal> { $0.date >= signalCutoff }
        ))
        let tasteProfile = try? TasteProfileService.loadOrCreate(in: context)
        let likedEpisodeIDs: Set<UUID> = Set(preferences.filter { $0.action == .like || $0.action == .moreLikeThis }.compactMap { (signal: PreferenceSignal) -> UUID? in signal.episode.id })
        let likedTags = Set(
            profiles
                .filter { likedEpisodeIDs.contains($0.episodeID) }
                .flatMap(\.tags)
        )

        // Also boost episodes from the same podcast
        let currentPodcastID = currentEpisode.podcast.id
        let currentProfile = profiles.first(where: { $0.episodeID == currentEpisode.id })
        let currentTags = Set(currentProfile?.tags ?? [])

        return episodes
            .map { episode -> ScoredEpisode in
                var result = scoreWithExplanation(
                    episode: episode,
                    profiles: profiles,
                    likedTags: likedTags,
                    tasteProfile: tasteProfile
                )
                var score = result.score

                // Boost same podcast
                if episode.podcast.id == currentPodcastID {
                    score += 0.15
                    result = (score, "More from \(episode.podcast.title)")
                }

                // Boost episodes with overlapping tags to current episode
                let episodeProfile = profiles.first(where: { $0.episodeID == episode.id })
                let episodeTags = Set(episodeProfile?.tags ?? [])
                let currentOverlap = episodeTags.intersection(currentTags)
                if !currentOverlap.isEmpty {
                    score += Double(currentOverlap.count) * 0.05
                    if episode.podcast.id != currentPodcastID {
                        let tag = currentOverlap.first ?? ""
                        result = (score, "Also covers \"\(tag)\"")
                    }
                }

                return ScoredEpisode(episode: episode, score: score, explanation: result.explanation)
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    /// Enforces max 2 episodes per podcast, filters out already-used IDs, and interleaves results.
    private static func diversified(_ candidates: [ScoredEpisode], limit: Int, excluding usedIDs: inout Set<UUID>) -> [ScoredEpisode] {
        let filtered = candidates.filter { !usedIDs.contains($0.episode.id) }

        // Group by podcast, take at most 2 per podcast
        var podcastBuckets: [UUID: [ScoredEpisode]] = [:]
        var podcastOrder: [UUID] = []
        for scored in filtered {
            let pid = scored.episode.podcast.id
            if podcastBuckets[pid] == nil { podcastOrder.append(pid) }
            if (podcastBuckets[pid]?.count ?? 0) < 2 {
                podcastBuckets[pid, default: []].append(scored)
            }
        }

        // Interleave: round-robin across podcasts
        var result: [ScoredEpisode] = []
        var indices = [UUID: Int]()
        for pid in podcastOrder { indices[pid] = 0 }
        var added = true
        while added && result.count < limit {
            added = false
            for pid in podcastOrder {
                guard result.count < limit else { break }
                let idx = indices[pid] ?? 0
                if let bucket = podcastBuckets[pid], idx < bucket.count {
                    result.append(bucket[idx])
                    indices[pid] = idx + 1
                    added = true
                }
            }
        }

        for scored in result { usedIDs.insert(scored.episode.id) }
        return result
    }

    private func episodeHasTopicOverlap(_ episode: Episode, profiles: [EpisodeProfile], likedTags: Set<String>) -> Bool {
        guard let profile = profiles.first(where: { $0.episodeID == episode.id }) else { return false }
        return !Set(profile.tags).intersection(likedTags).isEmpty
    }
}

struct ScoredEpisode {
    let episode: Episode
    let score: Double
    let explanation: String
}

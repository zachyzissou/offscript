import Foundation
import SwiftData

struct RecommendationScoreInputs {
    let recencyDays: Double
    let durationMinutes: Double
    let topicOverlap: Double
    /// Sum of (1.0 / (1 + days_since_signal)) across user likes that touch this
    /// episode's tags. Acts as a recency-weighted boost for "what you've liked
    /// lately."
    let likeRecencyWeight: Double
    let isFromSubscribedPodcast: Bool
    let isUnfinished: Bool
    let isAlreadyQueued: Bool
    let preferredDurationMinutes: Double?
    /// Number of episodes from this same podcast played in the last 24 hours.
    /// More than two = recent overexposure → temporary fatigue penalty.
    let showRecentPlayCount: Int
    /// Per-show notInterested signals over the last 90 days. Each signal cuts
    /// the score multiplicatively so a single dismiss matters but doesn't
    /// permanently nuke the show.
    let negativeShowSignals: Int
    /// Hour-of-day fit (0..1) for current local hour using user's typical
    /// listening pattern. 1.0 if user usually listens at this hour, 0.5 floor
    /// otherwise.
    let timeOfDayFit: Double
}

enum RecommendationScorer {
    static func score(_ input: RecommendationScoreInputs) -> Double {
        let recency = exp(-input.recencyDays / 10.0) * 0.24
        let durationFit = durationScore(minutes: input.durationMinutes, preferredMinutes: input.preferredDurationMinutes) * 0.16
        let topic = min(1.0, input.topicOverlap / 3.0) * 0.22
        let subscription = (input.isFromSubscribedPodcast ? 1.0 : 0.0) * 0.10
        let unfinished = (input.isUnfinished ? 1.0 : 0.0) * 0.14
        let likeRecency = min(1.0, input.likeRecencyWeight / 2.5) * 0.10
        let timeOfDay = input.timeOfDayFit * 0.06
        // Episodes older than 60 days lose ~40% of their recency value.
        let agePenalty = input.recencyDays > 60 ? 0.06 : 0.0

        var raw = recency + durationFit + topic + subscription + unfinished + likeRecency + timeOfDay - agePenalty

        // Show fatigue: penalty escalates after the user has heard 2+ from this
        // show in the last day. Cap at -0.18 so we don't completely hide them.
        if input.showRecentPlayCount > 1 {
            let extra = Double(input.showRecentPlayCount - 1)
            raw -= min(0.18, extra * 0.07)
        }

        // Already-queued penalty: keep recommendations distinct from the queue.
        if input.isAlreadyQueued {
            raw -= 0.25
        }

        // Negative-show signal: each notInterested for a show in the window
        // multiplies the score down. Three dismisses ≈ 50% reduction.
        if input.negativeShowSignals > 0 {
            let factor = pow(0.78, Double(min(input.negativeShowSignals, 5)))
            raw *= factor
        }

        return raw
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

        // Cap episodes to the most recent 600. Even users with massive
        // libraries don't need older episodes scored every refresh — anything
        // older than that is firmly in archive territory.
        var episodeDescriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.podcast.isSubscribed == true },
            sortBy: [SortDescriptor(\Episode.pubDate, order: .reverse)]
        )
        episodeDescriptor.fetchLimit = 600
        let episodes = try context.fetch(episodeDescriptor)

        // Profiles are 1:1 with episodes — bound to the same ceiling so we
        // never load a runaway table.
        var profileDescriptor = FetchDescriptor<EpisodeProfile>()
        profileDescriptor.fetchLimit = 1500
        let profiles = (try? context.fetch(profileDescriptor)) ?? []

        let signalCutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? .distantPast
        let preferences = try context.fetch(FetchDescriptor<PreferenceSignal>(
            predicate: #Predicate<PreferenceSignal> { $0.date >= signalCutoff }
        ))
        let tasteProfile = try? TasteProfileService.loadOrCreate(in: context)

        let likeSignals = preferences.filter { $0.action == .like || $0.action == .moreLikeThis }
        let dislikeSignals = preferences.filter { $0.action == .notInterested || $0.action == .lessLikeThis }
        let dislikedEpisodeIDs: Set<UUID> = Set(dislikeSignals.compactMap { (signal: PreferenceSignal) -> UUID? in signal.episode?.id })

        // Cold start: no taste signal yet — drop straight into editor's-pick mode.
        if likeSignals.isEmpty && dislikeSignals.isEmpty && tasteProfile?.showAffinity.isEmpty != false {
            return try coldStartSections(episodes: episodes, profiles: profiles, tasteProfile: tasteProfile, limit: limit)
        }

        // Index liked tags by their *recency* (sum of 1/(1+days)) so a like
        // last week is worth more than one a month ago.
        var likedTagWeights: [String: Double] = [:]
        for signal in likeSignals {
            guard let episodeID = signal.episode?.id,
                  let profile = profiles.first(where: { $0.episodeID == episodeID }) else { continue }
            let days = max(0, Date().timeIntervalSince(signal.date) / 86_400.0)
            let weight = 1.0 / (1.0 + days)
            for tag in profile.tags {
                likedTagWeights[tag, default: 0] += weight
            }
        }
        let likedTags = Set(likedTagWeights.keys)

        // Show fatigue map — count playback events per podcast in the last 24h.
        let playbackCutoff = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? .distantPast
        var recentPlaybackDescriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate<PlaybackEvent> { $0.date >= playbackCutoff }
        )
        recentPlaybackDescriptor.fetchLimit = 200
        let recentPlayback = (try? context.fetch(recentPlaybackDescriptor)) ?? []
        var showRecentPlayCounts: [UUID: Int] = [:]
        for event in recentPlayback {
            guard let pid = event.episode?.podcast.id else { continue }
            showRecentPlayCounts[pid, default: 0] += 1
        }

        // Per-show negative signal counts.
        var negativeShowCounts: [UUID: Int] = [:]
        for signal in dislikeSignals {
            guard let pid = signal.episode?.podcast.id else { continue }
            negativeShowCounts[pid, default: 0] += 1
        }

        // Already-queued IDs.
        let queuedEpisodeIDs: Set<UUID> = Set(((try? context.fetch(FetchDescriptor<QueueItem>())) ?? [])
            .map { $0.episode.id })

        // Hour-of-day histogram so we can boost episodes that match the user's
        // typical listening hour. We pull a 30-day window of starts/resumes.
        let hourCutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        var hoursDescriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate<PlaybackEvent> { $0.date >= hourCutoff }
        )
        hoursDescriptor.fetchLimit = 1000
        let listeningHours = (try? context.fetch(hoursDescriptor)) ?? []
        var hourHistogram = Array(repeating: 0, count: 24)
        for event in listeningHours where event.kind == .started || event.kind == .resumed {
            let hour = Calendar.current.component(.hour, from: event.date)
            if (0..<24).contains(hour) {
                hourHistogram[hour] += 1
            }
        }
        let totalListens = hourHistogram.reduce(0, +)
        let currentHour = Calendar.current.component(.hour, from: Date())
        let hourFit: Double
        if totalListens >= 5 {
            let normalized = Double(hourHistogram[currentHour]) / Double(max(hourHistogram.max() ?? 1, 1))
            hourFit = max(0.3, min(1.0, normalized))
        } else {
            hourFit = 0.6
        }

        let scoredEpisodes = episodes
            .filter { !dislikedEpisodeIDs.contains($0.id) }
            .map { episode -> ScoredEpisode in
                let result = scoreWithExplanation(
                    episode: episode,
                    profiles: profiles,
                    likedTags: likedTags,
                    likedTagWeights: likedTagWeights,
                    tasteProfile: tasteProfile,
                    showRecentPlayCount: showRecentPlayCounts[episode.podcast.id] ?? 0,
                    negativeShowSignals: negativeShowCounts[episode.podcast.id] ?? 0,
                    isAlreadyQueued: queuedEpisodeIDs.contains(episode.id),
                    timeOfDayFit: hourFit
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
        likedTagWeights: [String: Double] = [:],
        tasteProfile: UserTasteProfile?,
        showRecentPlayCount: Int = 0,
        negativeShowSignals: Int = 0,
        isAlreadyQueued: Bool = false,
        timeOfDayFit: Double = 0.6,
        diversityPenalty: Double = 0
    ) -> (score: Double, explanation: String) {
        let profile = profiles.first(where: { $0.episodeID == episode.id })
        let episodeTags = Set(profile?.tags ?? [])
        let matchingTags = episodeTags.intersection(likedTags)
        let overlap = Double(matchingTags.count)
        let likeRecency = matchingTags.reduce(0.0) { $0 + (likedTagWeights[$1] ?? 0) }
        let days = max(0, Date().timeIntervalSince(episode.pubDate) / 86_400.0)
        let minutes = (episode.duration ?? 30 * 60) / 60
        let isUnfinished = episode.playedPosition > 0 && !episode.isPlayed

        let inputs = RecommendationScoreInputs(
            recencyDays: days,
            durationMinutes: minutes,
            topicOverlap: overlap,
            likeRecencyWeight: likeRecency,
            isFromSubscribedPodcast: episode.podcast.isSubscribed,
            isUnfinished: isUnfinished,
            isAlreadyQueued: isAlreadyQueued,
            preferredDurationMinutes: tasteProfile?.averageCompletedDurationMinutes,
            showRecentPlayCount: showRecentPlayCount,
            negativeShowSignals: negativeShowSignals,
            timeOfDayFit: timeOfDayFit
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

    /// First-launch fallback when there's zero listening signal yet. We rely
    /// purely on freshness, the user's stated preferred genres, and a per-show
    /// quota so the empty state isn't a wall of one-podcast-only.
    @MainActor
    private func coldStartSections(episodes: [Episode], profiles: [EpisodeProfile], tasteProfile: UserTasteProfile?, limit: Int) throws -> [HomeFeedSection] {
        let preferredGenres = (tasteProfile?.preferredGenres ?? AppSettings.preferredGenres.map(\.rawValue)).map { $0.lowercased() }

        let scored: [ScoredEpisode] = episodes
            .filter { !$0.isPlayed }
            .map { episode -> ScoredEpisode in
                let days = max(0, Date().timeIntervalSince(episode.pubDate) / 86_400.0)
                let recency = exp(-days / 14.0)
                let genreOverlap = Set(episode.podcast.categories.map { $0.lowercased() })
                    .intersection(Set(preferredGenres)).count
                let genreBoost = 0.15 * Double(min(genreOverlap, 3))
                let durationFit = RecommendationScorer.durationScore(minutes: (episode.duration ?? 1_800) / 60)
                let score = recency * 0.55 + durationFit * 0.20 + genreBoost
                let explanation: String
                if days <= 1 {
                    explanation = "Dropped today from \(episode.podcast.title)"
                } else if genreOverlap > 0 {
                    explanation = "Matches a genre you picked"
                } else if days <= 5 {
                    explanation = "Fresh from \(episode.podcast.title)"
                } else {
                    explanation = "Strong starting point"
                }
                return ScoredEpisode(episode: episode, score: score, explanation: explanation)
            }
            .sorted { $0.score > $1.score }

        var used: Set<UUID> = []
        let starters = Self.diversified(scored, limit: limit, excluding: &used)
        let recents = Self.diversified(
            scored.filter { (Date().timeIntervalSince($0.episode.pubDate) / 86_400.0) <= 7 },
            limit: limit,
            excluding: &used
        )

        return [
            HomeFeedSection(
                title: "Editor's first picks",
                subtitle: "Strong starting points from the shows you brought in. We'll learn fast — start playing.",
                scoredEpisodes: starters
            ),
            HomeFeedSection(
                title: "Fresh this week",
                subtitle: "Recent drops across your library.",
                scoredEpisodes: recents
            )
        ].filter { !$0.episodes.isEmpty }
    }

    /// Returns contextual recommendations for the player based on the currently playing episode
    @MainActor
    func playerSuggestions(currentEpisode: Episode, context: ModelContext, limit: Int = 5) throws -> [ScoredEpisode] {
        // Filter at the database level: subscribed podcasts, unplayed episodes only.
        let currentEpisodeID = currentEpisode.id
        var episodesDescriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.podcast.isSubscribed == true && $0.id != currentEpisodeID && $0.isPlayed == false },
            sortBy: [SortDescriptor(\Episode.pubDate, order: .reverse)]
        )
        episodesDescriptor.fetchLimit = 200
        let episodes = try context.fetch(episodesDescriptor)

        var profilesDescriptor = FetchDescriptor<EpisodeProfile>()
        profilesDescriptor.fetchLimit = 1500
        let profiles = (try? context.fetch(profilesDescriptor)) ?? []

        let signalCutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? .distantPast
        let preferences = try context.fetch(FetchDescriptor<PreferenceSignal>(
            predicate: #Predicate<PreferenceSignal> { $0.date >= signalCutoff }
        ))
        let tasteProfile = try? TasteProfileService.loadOrCreate(in: context)
        let likedEpisodeIDs: Set<UUID> = Set(preferences.filter { $0.action == .like || $0.action == .moreLikeThis }.compactMap { (signal: PreferenceSignal) -> UUID? in signal.episode?.id })
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

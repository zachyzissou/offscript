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

    private enum EvidenceStrength: Int {
        case catalog = 0
        case inferred = 1
        case listened = 2
        case chosen = 3

        var displayValue: String {
            switch self {
            case .catalog: "catalog"
            case .inferred: "inferred"
            case .listened: "listened"
            case .chosen: "chosen"
            }
        }
    }

    private struct RecommendationEvidence {
        let source: String
        let weight: Double
        let explanation: String
        let signals: [RecommendationSignal]
        let strength: EvidenceStrength
    }

    private struct ScoringContext {
        let profileByEpisodeID: [UUID: EpisodeProfile]
        let likedTags: Set<String>
        let completedTags: Set<String>
        let explicitPositiveTags: Set<String>
        let tasteProfile: UserTasteProfile?
        let topTags: Set<String>
        let showAffinity: Set<String>
        let completedShowCounts: [String: Int]
        let explicitPositiveShowCounts: [String: Int]
        let queuedPositionByEpisodeID: [UUID: Int]
        let preferredGenres: Set<String>
        let negativeTagWeights: [String: Double]
        let negativeShowWeights: [String: Double]
    }

    static func headlineCandidate(from sections: [HomeFeedSection]) -> ScoredEpisode? {
        sections
            .flatMap(\.scoredEpisodes)
            .max { headlineScore($0) < headlineScore($1) }
    }

    private static func headlineScore(_ scored: ScoredEpisode) -> Double {
        let sourceValues = Set(scored.signalTrace
            .filter { $0.label == "source" }
            .map { $0.value.lowercased() })
        let strength = Self.signalStrength(from: scored.signalTrace)
        var score = scored.score
        score += Double(min(scored.signalTrace.count, 4)) * 4
        score += Double(strength.rawValue) * 32

        if sourceValues.contains("queue") {
            score += 40
        }
        if sourceValues.contains("resume") {
            score += 28
        }
        if sourceValues.contains("completion") || sourceValues.contains("show affinity") {
            score += 22
        }
        if sourceValues.contains("tag match") || sourceValues.contains("topic overlap") || sourceValues.contains("recent interest") {
            score += 16
        }

        return score
    }

    private static func signalStrength(from signals: [RecommendationSignal]) -> EvidenceStrength {
        let sources = Set(signals
            .filter { $0.label.caseInsensitiveCompare("source") == .orderedSame }
            .map { $0.value.lowercased() })
        if !sources.intersection(["queue", "resume", "explicit signal", "show intent", "now playing"]).isEmpty {
            return .chosen
        }
        if !sources.intersection(["completion", "show affinity", "tag match", "topic overlap", "liked episode", "recent interest"]).isEmpty {
            return .listened
        }
        if !sources.intersection(["genre", "duration", "fresh", "subscription", "available"]).isEmpty {
            return .inferred
        }
        return .catalog
    }

    private static func composedExplanation(primary: RecommendationEvidence, secondary: RecommendationEvidence?) -> String {
        guard let secondary else { return primary.explanation }

        if primary.source == "explicit signal", secondary.source == "show intent" {
            let tags = primary.signals.first(where: { $0.label == "tags" })?.value ?? "your saved signal"
            let show = secondary.signals.first(where: { $0.label == "show" })?.value ?? "that show"
            return "You asked for more from \(show), and this matches \(tags)"
        }

        if primary.source == "show intent", secondary.source == "explicit signal" {
            let show = primary.signals.first(where: { $0.label == "show" })?.value ?? "this show"
            let tags = secondary.signals.first(where: { $0.label == "tags" })?.value ?? "your saved signal"
            return "You asked for more from \(show), and this matches \(tags)"
        }

        if primary.source == "completion", secondary.source == "tag match" {
            let show = primary.signals.first(where: { $0.label == "show" })?.value ?? "this show"
            let tags = secondary.signals.first(where: { $0.label == "tags" })?.value ?? "your saved signal"
            return "You keep finishing \(show), and this carries \(tags)"
        }

        if primary.source == "tag match", secondary.source == "completion" {
            let tags = primary.signals.first(where: { $0.label == "tags" })?.value ?? "your saved signal"
            let show = secondary.signals.first(where: { $0.label == "show" })?.value ?? "a show you finish"
            return "Matches \(tags) from a show you keep finishing: \(show)"
        }

        return primary.explanation
    }

    static func effectivePreferredGenreTitles(for tasteProfile: UserTasteProfile?) -> [String] {
        let profileGenres = tasteProfile?.preferredGenres ?? []
        if !profileGenres.isEmpty {
            return profileGenres
        }
        return AppSettings.preferredGenres.map(\.title)
    }

    @MainActor
    func discoverySection(
        context: ModelContext,
        mode: AppSettings.RecommendationMode,
        signalDrivenRailCount: Int? = nil
    ) async -> HomeFeedSection? {
        guard mode.allowsDiscovery else { return nil }
        guard let tasteProfile = try? TasteProfileService.loadOrCreate(in: context) else { return nil }

        // Only show discovery if the user has some taste data
        let preferredGenres = Self.effectivePreferredGenreTitles(for: tasteProfile)
        if tasteProfile.preferredGenres.isEmpty, !preferredGenres.isEmpty {
            tasteProfile.preferredGenres = preferredGenres
        }
        let hasData = !tasteProfile.topTags.isEmpty || !preferredGenres.isEmpty
        guard hasData else { return nil }

        let podcasts = (try? context.fetch(FetchDescriptor<Podcast>(
            predicate: #Predicate<Podcast> { $0.isSubscribed == true }
        ))) ?? []
        let subscribedFeedURLs = Set(podcasts.map { $0.feedURL.absoluteString })

        let limit = Self.discoveryCardLimit(
            mode: mode,
            signalDrivenRailCount: signalDrivenRailCount
        )

        let results = await discoveryService.discoverPodcasts(
            tasteProfile: tasteProfile,
            subscribedFeedURLs: subscribedFeedURLs,
            limit: limit
        )

        guard !results.isEmpty else { return nil }

        return HomeFeedSection(
            title: mode == .discovery ? "New Frequencies" : "Discovery Check",
            subtitle: mode == .discovery
                ? "Fetched from Apple Podcasts Search, then ranked on-device from saved signal."
                : "A small Apple Podcasts Search lane, kept behind your existing evidence.",
            discoveryResults: results
        )
    }

    @MainActor
    func homeSections(
        context: ModelContext,
        mode: AppSettings.RecommendationMode = .balanced,
        limit: Int = 6,
        refreshTasteProfile: Bool = true
    ) throws -> [HomeFeedSection] {
        if refreshTasteProfile {
            do {
                try TasteProfileService.refresh(in: context)
            } catch {
                context.rollback()
                NSLog("RecommendationService.homeSections: failed to refresh taste profile: \(String(describing: error))")
            }
        }
        let queueItems = try context.fetch(FetchDescriptor<QueueItem>(
            sortBy: [
                SortDescriptor(\QueueItem.position),
                SortDescriptor(\QueueItem.createdAt)
            ]
        ))

        // Only fetch preference signals from the last 90 days to avoid loading stale history
        let signalCutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? .distantPast
        let preferences = try context.fetch(FetchDescriptor<PreferenceSignal>(
            predicate: #Predicate<PreferenceSignal> { $0.date >= signalCutoff }
        ))
        let playbackEvents = try context.fetch(FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate<PlaybackEvent> { $0.date >= signalCutoff }
        ))
        let inProgressEpisodes = try context.fetch(Self.inProgressCandidateDescriptor(limit: 120))
            .filter { $0.podcast.isSubscribed }
        let recentEpisodes = try context.fetch(Self.recentCandidateDescriptor(limit: 360))
        let evidenceEpisodes = try context.fetch(Self.evidencePodcastCandidateDescriptor(
            podcastIDs: Self.evidencePodcastIDs(preferences: preferences, playbackEvents: playbackEvents),
            limit: 240
        ))
        let episodes = Self.uniqueEpisodes(queueItems.map(\.episode) + inProgressEpisodes + evidenceEpisodes + recentEpisodes)
        var profileEpisodeIDs = Set(episodes.map(\.id))
        profileEpisodeIDs.formUnion(preferences.map { $0.episode.id })
        profileEpisodeIDs.formUnion(playbackEvents.compactMap { $0.episode?.id })
        let profiles = try Self.profiles(for: profileEpisodeIDs, context: context)
        let profileByEpisodeID = Self.profileMap(from: profiles)
        let tasteProfile = try? TasteProfileService.loadOrCreate(in: context)
        let dislikedEpisodeIDs: Set<UUID> = Set(preferences.filter { $0.action == .notInterested }.compactMap { (signal: PreferenceSignal) -> UUID? in signal.episode.id })
        let negativePreferences = preferences.filter { $0.action == .notInterested || $0.action == .lessLikeThis }
        let negativePlaybackEvents = playbackEvents.filter { $0.kind == .skippedQuickly || $0.kind == .abandoned }
        let likedTags = Self.normalizedTags(preferences.lazy
            .filter { $0.action == .like || $0.action == .moreLikeThis }
            .flatMap { profileByEpisodeID[$0.episode.id]?.tags ?? $0.episode.profile?.tags ?? [] })
        let completedTags = Self.normalizedTags(playbackEvents.lazy
            .filter { $0.kind == .completed }
            .flatMap { event -> [String] in
                guard let episode = event.episode else { return [] }
                return profileByEpisodeID[episode.id]?.tags ?? episode.profile?.tags ?? []
            })
        let explicitPositivePreferences = preferences.filter { $0.action == .like || $0.action == .moreLikeThis }
        let explicitPositiveTags = Self.normalizedTags(explicitPositivePreferences.lazy.flatMap {
            profileByEpisodeID[$0.episode.id]?.tags ?? $0.episode.profile?.tags ?? []
        })
        let completedShows = playbackEvents
            .filter { $0.kind == .completed }
            .compactMap { $0.episode?.podcast.title }
        let completedShowCounts = Dictionary(completedShows.map { ($0, 1) }, uniquingKeysWith: +)
        let explicitPositiveShows = explicitPositivePreferences.map { $0.episode.podcast.title }
        let explicitPositiveShowCounts = Dictionary(explicitPositiveShows.map { ($0, 1) }, uniquingKeysWith: +)
        let negativeTagWeights = Self.negativeTagWeights(
            preferences: negativePreferences,
            playbackEvents: negativePlaybackEvents,
            profileByEpisodeID: profileByEpisodeID
        )
        let negativeShowWeights = Self.negativeShowWeights(
            preferences: negativePreferences,
            playbackEvents: negativePlaybackEvents
        )
        let queuedPositionByEpisodeID = Dictionary(uniqueKeysWithValues: queueItems.map { ($0.episode.id, $0.position) })
        let scoringContext = ScoringContext(
            profileByEpisodeID: profileByEpisodeID,
            likedTags: likedTags,
            completedTags: completedTags,
            explicitPositiveTags: explicitPositiveTags,
            tasteProfile: tasteProfile,
            topTags: Self.normalizedTags(tasteProfile?.topTags ?? []),
            showAffinity: Set(tasteProfile?.showAffinity ?? []),
            completedShowCounts: completedShowCounts,
            explicitPositiveShowCounts: explicitPositiveShowCounts,
            queuedPositionByEpisodeID: queuedPositionByEpisodeID,
            preferredGenres: Set(Self.effectivePreferredGenreTitles(for: tasteProfile).map { $0.lowercased() }),
            negativeTagWeights: negativeTagWeights,
            negativeShowWeights: negativeShowWeights
        )

        let scoredEpisodes = episodes
            .filter { !$0.isPlayed && !dislikedEpisodeIDs.contains($0.id) }
            .compactMap { episode -> ScoredEpisode? in
                guard let result = homeSignal(
                    episode: episode,
                    context: scoringContext
                ) else { return nil }
                return ScoredEpisode(
                    episode: episode,
                    score: result.score,
                    explanation: result.explanation,
                    signalTrace: result.signalTrace
                )
            }
            .sorted { $0.score > $1.score }

        var usedEpisodeIDs = Set<UUID>()

        let signalLock = Self.diversified(
            scoredEpisodes.filter { scoringContext.queuedPositionByEpisodeID[$0.episode.id] != nil },
            limit: limit,
            excluding: &usedEpisodeIDs
        )
        let resumeThread = Self.diversified(
            scoredEpisodes.filter { Self.hasMeaningfulProgress($0.episode) },
            limit: limit,
            excluding: &usedEpisodeIDs
        )
        let explicitShowIntent = Self.diversified(
            scoredEpisodes.filter {
                scoringContext.explicitPositiveShowCounts[$0.episode.podcast.title, default: 0] > 0
            },
            limit: limit,
            excluding: &usedEpisodeIDs
        )
        let showAffinity = Self.diversified(
            scoredEpisodes.filter {
                scoringContext.completedShowCounts[$0.episode.podcast.title, default: 0] > 0
                    || scoringContext.showAffinity.contains($0.episode.podcast.title)
            },
            limit: limit,
            excluding: &usedEpisodeIDs
        )
        let topicContinuation = Self.diversified(
            scoredEpisodes.filter { episodeHasTopicOverlap($0.episode, context: scoringContext) },
            limit: limit,
            excluding: &usedEpisodeIDs
        )
        let genreLane = Self.diversified(
            scoredEpisodes.filter { episodeHasGenreOverlap($0.episode, context: scoringContext) },
            limit: limit,
            excluding: &usedEpisodeIDs
        )
        let shortWindow = Self.diversified(
            scoredEpisodes.filter { AppSettings.preferShortEpisodes && (($0.episode.duration ?? 0) / 60) <= 35 },
            limit: limit,
            excluding: &usedEpisodeIDs
        )

        var allSections = [
            HomeFeedSection(title: "Signal Lock", subtitle: "The next listen is driven by something you actually did.", scoredEpisodes: signalLock),
            HomeFeedSection(title: "Resume Thread", subtitle: "Partially heard episodes with meaningful time left.", scoredEpisodes: resumeThread),
            HomeFeedSection(title: "More From Shows You Chose", subtitle: "Follow-ups from shows you explicitly liked or asked for more of.", scoredEpisodes: explicitShowIntent),
            HomeFeedSection(title: "Shows You Finish", subtitle: "Newer episodes from channels with completion signal.", scoredEpisodes: showAffinity),
            HomeFeedSection(title: "Topic Continuation", subtitle: "Shared tags from completed or explicitly liked listens.", scoredEpisodes: topicContinuation)
        ]

        if mode != .signalLocked {
            allSections.append(HomeFeedSection(title: "Tuned Genres", subtitle: "Genre lanes are allowed in Balanced and Discovery modes.", scoredEpisodes: genreLane))
            allSections.append(HomeFeedSection(title: "Short Window", subtitle: "Compact episodes only when you asked for shorter listens.", scoredEpisodes: shortWindow))
        }

        // From Your Subscriptions is the catch-all that fills the gap when
        // a user has imported shows but no recent listening signal. Built
        // from the subscribed-show pool directly (not via homeSignal) so
        // episodes with zero taste signal still surface — otherwise the
        // signal-thin Home reads as "Apple Podcasts catalog with TUNE
        // buttons" because Discovery / Tuned Genres dominate. Runs LAST
        // among the scoring rails so specific signal-driven rails always
        // win when they have content (#191 follow-up).
        let subscriptionFresh = Self.subscriptionFreshSection(
            recentEpisodes: recentEpisodes,
            profileByEpisodeID: profileByEpisodeID,
            negativeShowWeights: negativeShowWeights,
            negativeTagWeights: negativeTagWeights,
            excluding: &usedEpisodeIDs,
            dislikedEpisodeIDs: dislikedEpisodeIDs,
            limit: limit
        )
        allSections.append(HomeFeedSection(
            title: "From Your Subscriptions",
            subtitle: "Latest unplayed episodes across the channels you've tuned to.",
            scoredEpisodes: subscriptionFresh
        ))

        allSections = allSections.filter { !$0.episodes.isEmpty }

        return allSections
    }

    /// Demote discovery card count when signal-driven rails are sparse.
    /// The bigger the user's actual listening signal, the more discovery
    /// cards we surface; when signal is thin discovery shrinks so it
    /// doesn't dominate the screen and read as "Apple Podcasts catalog"
    /// (#191). Pure function so the limit logic can be unit-tested
    /// without hitting the discovery network path.
    static func discoveryCardLimit(
        mode: AppSettings.RecommendationMode,
        signalDrivenRailCount: Int?
    ) -> Int {
        guard let signalCount = signalDrivenRailCount else {
            return mode.discoveryLimit
        }
        switch signalCount {
        case 3...:
            return mode.discoveryLimit
        case 1...2:
            return max(3, mode.discoveryLimit / 2)
        default:
            return min(3, mode.discoveryLimit)
        }
    }

    private static func subscriptionFreshSection(
        recentEpisodes: [Episode],
        profileByEpisodeID: [UUID: EpisodeProfile],
        negativeShowWeights: [String: Double],
        negativeTagWeights: [String: Double],
        excluding usedEpisodeIDs: inout Set<UUID>,
        dislikedEpisodeIDs: Set<UUID>,
        limit: Int
    ) -> [ScoredEpisode] {
        var picks: [ScoredEpisode] = []
        // Negative show / tag signals must still suppress here — a user
        // who tapped "Less Like This" on a show or topic shouldn't see
        // those episodes resurface in the catch-all rail. Negative
        // weights are negative numbers (e.g. lessLikeThis is -3.5,
        // notInterested is -5.0), so we suppress when accumulated
        // weight crosses -0.5 in the negative direction.
        let suppressionThreshold: Double = -0.5
        for episode in recentEpisodes {
            guard picks.count < limit else { break }
            guard !usedEpisodeIDs.contains(episode.id),
                  !dislikedEpisodeIDs.contains(episode.id),
                  !episode.isPlayed,
                  episode.podcast.isSubscribed
            else { continue }
            let showTitle = episode.podcast.title
            if let showWeight = negativeShowWeights[showTitle], showWeight <= suppressionThreshold {
                continue
            }
            let profile = profileByEpisodeID[episode.id] ?? episode.profile
            let normalizedTags = Self.normalizedTags(profile?.tags ?? [])
            let hasNegativeTagOverlap = normalizedTags.contains(where: {
                (negativeTagWeights[$0] ?? 0) <= suppressionThreshold
            })
            if hasNegativeTagOverlap {
                continue
            }
            usedEpisodeIDs.insert(episode.id)
            let explanation = "From your subscribed show \(showTitle)"
            let signals: [RecommendationSignal] = [
                RecommendationSignal(label: "source", value: "subscription"),
                RecommendationSignal(label: "show", value: showTitle),
                RecommendationSignal(label: "strength", value: "inferred")
            ]
            // Score is intentionally low — this rail is the catch-all,
            // not a primary signal. Hero candidate selection should
            // prefer real signal-driven picks over this.
            picks.append(ScoredEpisode(
                episode: episode,
                score: 50,
                explanation: explanation,
                signalTrace: signals
            ))
        }
        return picks
    }

    private func homeSignal(
        episode: Episode,
        context: ScoringContext
    ) -> (score: Double, explanation: String, signalTrace: [RecommendationSignal])? {
        let profile = context.profileByEpisodeID[episode.id]
        let profileTags = Self.normalizedTags(profile?.tags ?? [])
        let matchingExplicitTags = profileTags.intersection(context.explicitPositiveTags)
        let matchingLikedTags = profileTags.intersection(context.likedTags)
        let matchingCompletedTags = profileTags.intersection(context.completedTags)
        let matchingTopTags = profileTags.intersection(context.topTags)
        let matchingTags = matchingLikedTags.union(matchingCompletedTags).union(matchingTopTags)
        let days = max(0, Date().timeIntervalSince(episode.pubDate) / 86_400.0)
        let minutes = (episode.duration ?? 30 * 60) / 60
        let quality = min(max(profile?.qualityScore ?? 0, 0), 1)
        let durationFit = RecommendationScorer.durationScore(
            minutes: minutes,
            preferredMinutes: context.tasteProfile?.averageCompletedDurationMinutes
        )
        let freshnessTieBreak = max(0, 1 - min(days, 30) / 30) * 8
        let durationTieBreak = durationFit * 5
        let qualityTieBreak = quality * 5

        var evidence: [RecommendationEvidence] = []

        if let queuePosition = context.queuedPositionByEpisodeID[episode.id] {
            let positionLabel = queuePosition == 0 ? "first" : "#\(queuePosition + 1)"
            evidence.append(RecommendationEvidence(
                source: "queue",
                weight: 500 - Double(queuePosition * 10),
                explanation: "You put this \(positionLabel) in queue",
                signals: [
                    RecommendationSignal(label: "source", value: "queue"),
                    RecommendationSignal(label: "position", value: positionLabel)
                ],
                strength: .chosen
            ))
        }

        if Self.hasMeaningfulProgress(episode) {
            let remaining = max(0, (episode.duration ?? 0) - episode.playedPosition)
            evidence.append(RecommendationEvidence(
                source: "resume",
                weight: 420 + durationTieBreak,
                // `.spoken` instead of `.short` so the WHY copy reads as a
                // sentence ("12 minutes left…") rather than a label
                // ("12m left…"). The chip value stays mono `.short`.
                explanation: "\(EpisodeDurationFormatter.spoken(remaining)) left from your last session",
                signals: [
                    RecommendationSignal(label: "source", value: "resume"),
                    RecommendationSignal(label: "left", value: EpisodeDurationFormatter.short(remaining))
                ],
                strength: .chosen
            ))
        }

        let negativeEvidence = Self.negativeEvidence(for: episode, profileTags: profileTags, context: context)
        if negativeEvidence.shouldSuppress {
            return nil
        }
        let negativePenalty = negativeEvidence.scorePenalty

        if !matchingExplicitTags.isEmpty {
            let sample = matchingExplicitTags.sorted().prefix(2).joined(separator: ", ")
            let matchCount = matchingExplicitTags.count
            // Concrete count surfaces how many of the user's "more like
            // this" tags this episode hits — Phase 20 sharpening replaces
            // the prior vague "Matches what you asked for: …" boilerplate.
            let explanation = matchCount > 1
                ? "Hits \(matchCount) tags you asked for: \(sample)"
                : "Tagged \"\(sample)\" — you asked for more of this"
            evidence.append(RecommendationEvidence(
                source: "explicit signal",
                weight: 400 + Double(min(matchingExplicitTags.count, 4)) * 24,
                explanation: explanation,
                signals: [
                    RecommendationSignal(label: "source", value: "explicit signal"),
                    RecommendationSignal(label: "tags", value: sample),
                    RecommendationSignal(label: "matches", value: "\(matchCount)")
                ],
                strength: .chosen
            ))
        }

        let explicitShowCount = context.explicitPositiveShowCounts[episode.podcast.title, default: 0]
        if explicitShowCount > 0 {
            // Phase 20: cite the number of "more like this" pulls when
            // > 1 so the user can verify the count against their own
            // recent actions. Single-pull case keeps the prior copy.
            let explanation = explicitShowCount > 1
                ? "You asked for more from \(episode.podcast.title) \(explicitShowCount) times"
                : "You asked for more from \(episode.podcast.title)"
            evidence.append(RecommendationEvidence(
                source: "show intent",
                weight: 380 + Double(min(explicitShowCount, 4)) * 20,
                explanation: explanation,
                signals: [
                    RecommendationSignal(label: "source", value: "show intent"),
                    RecommendationSignal(label: "show", value: episode.podcast.title),
                    RecommendationSignal(label: "asks", value: "\(explicitShowCount)")
                ],
                strength: .chosen
            ))
        }

        let completedShowCount = context.completedShowCounts[episode.podcast.title, default: 0]
        if completedShowCount > 0 || context.showAffinity.contains(episode.podcast.title) {
            let showSignal = max(completedShowCount, 1)
            // Phase 20: surface the concrete finish count when ≥ 2 so the
            // user can verify the evidence ("yes, I really did finish 3
            // of these"). Single-finish keeps the prior phrasing because
            // "1 time" reads awkwardly.
            let explanation = showSignal >= 2
                ? "You finished \(showSignal) episodes of \(episode.podcast.title)"
                : "You keep finishing \(episode.podcast.title)"
            evidence.append(RecommendationEvidence(
                source: "completion",
                weight: 320 + Double(min(showSignal, 5)) * 18,
                explanation: explanation,
                signals: [
                    RecommendationSignal(label: "source", value: "completion"),
                    RecommendationSignal(label: "show", value: episode.podcast.title),
                    RecommendationSignal(label: "finishes", value: "\(showSignal)")
                ],
                strength: .listened
            ))
        }

        if !matchingTags.isEmpty {
            let sample = matchingTags.sorted().prefix(2).joined(separator: ", ")
            // Phase 20: name WHERE the tag came from (a finish or a like)
            // instead of the prior vague "Matches your saved signal: …".
            // Completed-tags wins because finishing is the strongest
            // passive signal we capture.
            let explanation: String
            if !matchingCompletedTags.isEmpty {
                let finished = matchingCompletedTags.sorted().prefix(2).joined(separator: ", ")
                explanation = "Tagged \"\(finished)\" — you finished episodes like this"
            } else if !matchingLikedTags.isEmpty {
                let liked = matchingLikedTags.sorted().prefix(2).joined(separator: ", ")
                explanation = "Tagged \"\(liked)\" — you liked episodes like this"
            } else {
                explanation = "Tagged \"\(sample)\" — among your top topics"
            }
            evidence.append(RecommendationEvidence(
                source: "tag match",
                weight: 260 + Double(min(matchingTags.count, 4)) * 16,
                explanation: explanation,
                signals: [
                    RecommendationSignal(label: "source", value: "tag match"),
                    RecommendationSignal(label: "tags", value: sample)
                ],
                strength: .listened
            ))
        }

        let genreMatches = Set(episode.podcast.categories.map { $0.lowercased() }).intersection(context.preferredGenres)
        if !genreMatches.isEmpty {
            let genre = genreMatches.sorted().first ?? "saved genre"
            // Phase 20: "you saved" ties the lane back to the explicit
            // genre picker tap. Was "Matches your selected … lane" —
            // technically true but the user has to translate "selected".
            evidence.append(RecommendationEvidence(
                source: "genre",
                weight: 210 + durationTieBreak,
                explanation: "In \(genre) — a genre you saved",
                signals: [
                    RecommendationSignal(label: "source", value: "genre"),
                    RecommendationSignal(label: "lane", value: genre)
                ],
                strength: .inferred
            ))
        }

        if AppSettings.preferShortEpisodes, minutes <= 35 {
            // Phase 20: cite the actual episode duration so the user can
            // verify against the timestamp on the card. Prior copy
            // ("Fits your short-listen setting") referenced the setting
            // but not the evidence.
            let window = EpisodeDurationFormatter.spoken(episode.duration ?? 0)
            evidence.append(RecommendationEvidence(
                source: "duration",
                weight: 190 + durationTieBreak,
                explanation: "\(window) — under your short-listen cap",
                signals: [
                    RecommendationSignal(label: "source", value: "duration"),
                    RecommendationSignal(label: "window", value: EpisodeDurationFormatter.short(episode.duration ?? 0))
                ],
                strength: .inferred
            ))
        }

        guard !evidence.isEmpty else { return nil }
        let localEvidence = evidence.filter { $0.strength == .chosen || $0.strength == .listened }
        let usableEvidence = localEvidence.isEmpty ? evidence : localEvidence
        let primary = usableEvidence.sorted { $0.weight > $1.weight }.first!
        let secondary = usableEvidence
            .filter { $0.source != primary.source }
            .sorted { $0.weight > $1.weight }
            .first
        let composedScore = primary.weight
            + (secondary.map { min($0.weight * 0.18, 72) } ?? 0)
            + freshnessTieBreak
            + qualityTieBreak
            - negativePenalty
        var trace = primary.signals
        if let secondary {
            trace.append(contentsOf: secondary.signals.filter { !trace.contains($0) })
        }
        trace.append(RecommendationSignal(label: "strength", value: primary.strength.displayValue))
        let explanation = Self.composedExplanation(primary: primary, secondary: secondary)
        return (composedScore, explanation, trace)
    }

    private func scoreWithExplanation(
        episode: Episode,
        context: ScoringContext,
        diversityPenalty: Double = 0
    ) -> (score: Double, explanation: String, signalTrace: [RecommendationSignal]) {
        let profile = context.profileByEpisodeID[episode.id]
        let profileTags = Self.normalizedTags(profile?.tags ?? [])
        let matchingTags = profileTags.intersection(context.likedTags)
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
            preferredDurationMinutes: context.tasteProfile?.averageCompletedDurationMinutes
        )

        var value = RecommendationScorer.score(inputs) - diversityPenalty
        if AppSettings.preferShortEpisodes, minutes <= 35 {
            value += 0.08
        }
        let negativeEvidence = Self.negativeEvidence(for: episode, profileTags: profileTags, context: context)
        value -= negativeEvidence.normalizedPenalty

        if let tasteProfile = context.tasteProfile {
            value += RecommendationScorer.genreBoost(
                podcastCategories: episode.podcast.categories.map { $0.lowercased() },
                preferredGenres: tasteProfile.preferredGenres.map { $0.lowercased() }
            )

            if context.showAffinity.contains(episode.podcast.title) {
                value += 0.09
            }

            if !profileTags.intersection(context.topTags).isEmpty {
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
        let signalTrace: [RecommendationSignal]
        if isUnfinished {
            let remaining = max(0, (episode.duration ?? 0) - episode.playedPosition)
            explanation = "\(EpisodeDurationFormatter.spoken(remaining)) left — pick up where you stopped"
            signalTrace = [
                RecommendationSignal(label: "source", value: "resume"),
                RecommendationSignal(label: "left", value: EpisodeDurationFormatter.short(remaining))
            ]
        } else if context.showAffinity.contains(episode.podcast.title) {
            explanation = "You keep finishing \(episode.podcast.title)"
            signalTrace = [
                RecommendationSignal(label: "source", value: "show affinity"),
                RecommendationSignal(label: "show", value: episode.podcast.title)
            ]
        } else if overlap >= 3 {
            let sample = Array(matchingTags.prefix(2)).joined(separator: ", ")
            explanation = "\(Int(overlap)) topic matches: \(sample)"
            signalTrace = [
                RecommendationSignal(label: "source", value: "topic overlap"),
                RecommendationSignal(label: "tags", value: sample)
            ]
        } else if let topTag = profileTags.intersection(context.topTags).first {
            explanation = "Fits your recent interest in \"\(topTag)\""
            signalTrace = [
                RecommendationSignal(label: "source", value: "recent interest"),
                RecommendationSignal(label: "tag", value: topTag)
            ]
        } else if overlap >= 1 {
            let sample = matchingTags.first ?? ""
            explanation = "Connects to \"\(sample)\" from episodes you liked"
            signalTrace = [
                RecommendationSignal(label: "source", value: "liked episode"),
                RecommendationSignal(label: "tag", value: sample)
            ]
        } else if days <= 1 {
            explanation = "Dropped today from \(episode.podcast.title)"
            signalTrace = [
                RecommendationSignal(label: "source", value: "fresh"),
                RecommendationSignal(label: "show", value: episode.podcast.title)
            ]
        } else if days <= 3 {
            explanation = "Fresh from \(episode.podcast.title) — \(Int(days))d ago"
            signalTrace = [
                RecommendationSignal(label: "source", value: "fresh"),
                RecommendationSignal(label: "age", value: "\(Int(days))d")
            ]
        } else if minutes <= 20 {
            explanation = "Quick \(EpisodeDurationFormatter.spoken(episode.duration ?? 0)) listen"
            signalTrace = [
                RecommendationSignal(label: "source", value: "duration"),
                RecommendationSignal(label: "window", value: EpisodeDurationFormatter.short(episode.duration ?? 0))
            ]
        } else {
            // Phase 20: this path is reached when no concrete signal is
            // present. `playerSuggestions` already filters to
            // `isSubscribed == true`, so the prior "Available from …"
            // branch was dead code. Honest fallback names the subscribed
            // show — the only verifiable user action we have here is the
            // subscribe tap itself.
            explanation = "Newer episode from \(episode.podcast.title), a show you subscribed to"
            signalTrace = [
                RecommendationSignal(label: "source", value: "subscription"),
                RecommendationSignal(label: "show", value: episode.podcast.title)
            ]
        }

        return (value, explanation, signalTrace)
    }

    /// Returns contextual recommendations for the player based on the currently playing episode
    @MainActor
    func playerSuggestions(currentEpisode: Episode, context: ModelContext, limit: Int = 5) throws -> [ScoredEpisode] {
        // Filter at the database level: subscribed podcasts, unplayed episodes only
        let currentEpisodeID = currentEpisode.id
        let episodes = try context.fetch(FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.podcast.isSubscribed == true && $0.id != currentEpisodeID && $0.isPlayed == false }
        ))

        let signalCutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? .distantPast
        let preferences = try context.fetch(FetchDescriptor<PreferenceSignal>(
            predicate: #Predicate<PreferenceSignal> { $0.date >= signalCutoff }
        ))
        let skippedQuicklyRawValue = PlaybackEvent.Kind.skippedQuickly.rawValue
        let abandonedRawValue = PlaybackEvent.Kind.abandoned.rawValue
        let negativePlaybackEvents = try context.fetch(FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate<PlaybackEvent> {
                $0.date >= signalCutoff && ($0.kindRawValue == skippedQuicklyRawValue || $0.kindRawValue == abandonedRawValue)
            }
        ))
        let tasteProfile = try? TasteProfileService.loadOrCreate(in: context)
        let likedEpisodeIDs: Set<UUID> = Set(preferences.filter { $0.action == .like || $0.action == .moreLikeThis }.compactMap { (signal: PreferenceSignal) -> UUID? in signal.episode.id })
        let negativePreferences = preferences.filter { $0.action == .notInterested || $0.action == .lessLikeThis }
        var profileEpisodeIDs = Set(episodes.map(\.id))
        profileEpisodeIDs.insert(currentEpisode.id)
        profileEpisodeIDs.formUnion(preferences.map { $0.episode.id })
        profileEpisodeIDs.formUnion(negativePlaybackEvents.compactMap { $0.episode?.id })
        let profiles = try Self.profiles(for: profileEpisodeIDs, context: context)
        let profileByEpisodeID = Self.profileMap(from: profiles)
        let likedTags = Self.normalizedTags(likedEpisodeIDs.flatMap { profileByEpisodeID[$0]?.tags ?? [] })
        let negativeTagWeights = Self.negativeTagWeights(
            preferences: negativePreferences,
            playbackEvents: negativePlaybackEvents,
            profileByEpisodeID: profileByEpisodeID
        )
        let negativeShowWeights = Self.negativeShowWeights(
            preferences: negativePreferences,
            playbackEvents: negativePlaybackEvents
        )
        let scoringContext = ScoringContext(
            profileByEpisodeID: profileByEpisodeID,
            likedTags: likedTags,
            completedTags: [],
            explicitPositiveTags: likedTags,
            tasteProfile: tasteProfile,
            topTags: Self.normalizedTags(tasteProfile?.topTags ?? []),
            showAffinity: Set(tasteProfile?.showAffinity ?? []),
            completedShowCounts: [:],
            explicitPositiveShowCounts: [:],
            queuedPositionByEpisodeID: [:],
            preferredGenres: Set(Self.effectivePreferredGenreTitles(for: tasteProfile).map { $0.lowercased() }),
            negativeTagWeights: negativeTagWeights,
            negativeShowWeights: negativeShowWeights
        )

        // Also boost episodes from the same podcast
        let currentPodcastID = currentEpisode.podcast.id
        let currentProfile = profileByEpisodeID[currentEpisode.id]
        let currentTags = Self.normalizedTags(currentProfile?.tags ?? [])

        return episodes
            .filter { episode in
                let episodeTags = Self.normalizedTags(profileByEpisodeID[episode.id]?.tags ?? [])
                let negativeEvidence = Self.negativeEvidence(for: episode, profileTags: episodeTags, context: scoringContext)
                return !negativeEvidence.shouldSuppress && negativeEvidence.scorePenalty == 0
            }
            .map { episode -> ScoredEpisode in
                var result = scoreWithExplanation(
                    episode: episode,
                    context: scoringContext
                )
                var score = result.score

                // Boost same podcast
                if episode.podcast.id == currentPodcastID {
                    let episodeProfile = profileByEpisodeID[episode.id]
                    let episodeTags = Self.normalizedTags(episodeProfile?.tags ?? [])
                    let currentOverlap = episodeTags.intersection(currentTags)
                    let hasEvidence = !currentOverlap.isEmpty
                        || scoringContext.showAffinity.contains(episode.podcast.title)
                    score += hasEvidence ? 0.15 : 0.04
                    if hasEvidence {
                        result = (
                            score,
                            "More from \(episode.podcast.title)",
                            [
                                RecommendationSignal(label: "source", value: "same show"),
                                RecommendationSignal(label: "show", value: episode.podcast.title)
                            ]
                        )
                    }
                }

                // Boost episodes with overlapping tags to current episode
                let episodeProfile = profileByEpisodeID[episode.id]
                let episodeTags = Self.normalizedTags(episodeProfile?.tags ?? [])
                let currentOverlap = episodeTags.intersection(currentTags)
                if !currentOverlap.isEmpty {
                    score += Double(min(currentOverlap.count, 4)) * 0.12
                    if episode.podcast.id != currentPodcastID {
                        let tag = currentOverlap.first ?? ""
                        result = (
                            score,
                            "Also covers \"\(tag)\"",
                            [
                                RecommendationSignal(label: "source", value: "now playing"),
                                RecommendationSignal(label: "tag", value: tag)
                            ]
                        )
                    }
                }

                return ScoredEpisode(episode: episode, score: score, explanation: result.explanation, signalTrace: result.signalTrace)
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

    private static func isSuppressedByNegativeSignal(
        _ episode: Episode,
        profileTags: Set<String>,
        context: ScoringContext
    ) -> Bool {
        negativeEvidence(for: episode, profileTags: profileTags, context: context).shouldSuppress
    }

    private static func negativeEvidence(
        for episode: Episode,
        profileTags: Set<String>,
        context: ScoringContext
    ) -> (scorePenalty: Double, normalizedPenalty: Double, shouldSuppress: Bool) {
        let showWeight = context.negativeShowWeights[episode.podcast.title, default: 0]
        let tagWeight = profileTags.reduce(0) { total, tag in
            total + context.negativeTagWeights[tag, default: 0]
        }
        let totalWeight = showWeight + tagWeight
        let shouldSuppress = showWeight <= -7 || tagWeight <= -7 || totalWeight <= -10
        let magnitude = abs(min(totalWeight, 0))
        return (
            scorePenalty: magnitude * 18,
            normalizedPenalty: magnitude * 0.08,
            shouldSuppress: shouldSuppress
        )
    }

    private static func negativeTagWeights(
        preferences: [PreferenceSignal],
        playbackEvents: [PlaybackEvent],
        profileByEpisodeID: [UUID: EpisodeProfile]
    ) -> [String: Double] {
        var weights: [String: Double] = [:]
        for preference in preferences {
            let weight = preferenceNegativeWeight(preference.action)
            let tags = profileByEpisodeID[preference.episode.id]?.tags ?? preference.episode.profile?.tags ?? []
            for tag in normalizedTags(tags) {
                weights[tag, default: 0] += weight
            }
        }
        for event in playbackEvents {
            guard let episode = event.episode else { continue }
            let weight = playbackNegativeWeight(event.kind)
            let tags = profileByEpisodeID[episode.id]?.tags ?? episode.profile?.tags ?? []
            for tag in normalizedTags(tags) {
                weights[tag, default: 0] += weight
            }
        }
        return weights
    }

    private static func negativeShowWeights(
        preferences: [PreferenceSignal],
        playbackEvents: [PlaybackEvent]
    ) -> [String: Double] {
        var weights: [String: Double] = [:]
        for preference in preferences {
            weights[preference.episode.podcast.title, default: 0] += preferenceNegativeWeight(preference.action)
        }
        for event in playbackEvents {
            guard let episode = event.episode else { continue }
            weights[episode.podcast.title, default: 0] += playbackNegativeWeight(event.kind)
        }
        return weights
    }

    private static func preferenceNegativeWeight(_ action: PreferenceSignal.Action) -> Double {
        switch action {
        case .lessLikeThis: -3.5
        case .notInterested: -5.0
        case .like, .moreLikeThis: 0
        }
    }

    private static func playbackNegativeWeight(_ kind: PlaybackEvent.Kind) -> Double {
        switch kind {
        case .skippedQuickly: -1.4
        case .abandoned: -0.8
        case .completed, .advancedFromQueue, .resumed, .started, .seekedForward, .seekedBackward: 0
        }
    }

    private func episodeHasTopicOverlap(_ episode: Episode, context: ScoringContext) -> Bool {
        guard let profile = context.profileByEpisodeID[episode.id] else { return false }
        let tags = Self.normalizedTags(profile.tags)
        return !tags.intersection(context.likedTags).isEmpty
            || !tags.intersection(context.completedTags).isEmpty
            || !tags.intersection(context.topTags).isEmpty
    }

    private func episodeHasGenreOverlap(_ episode: Episode, context: ScoringContext) -> Bool {
        !Set(episode.podcast.categories.map { $0.lowercased() }).intersection(context.preferredGenres).isEmpty
    }

    private static func hasMeaningfulProgress(_ episode: Episode) -> Bool {
        guard episode.playedPosition >= 60, !episode.isPlayed else { return false }
        guard let duration = episode.duration, duration > 0 else { return true }
        return episode.playedPosition < duration * 0.9
    }

    private static func normalizedTags<S: Sequence>(_ tags: S) -> Set<String> where S.Element == String {
        Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
    }

    private static func profileMap(from profiles: [EpisodeProfile]) -> [UUID: EpisodeProfile] {
        Dictionary(profiles.map { ($0.episodeID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func profiles(for episodeIDs: Set<UUID>, context: ModelContext) throws -> [EpisodeProfile] {
        guard !episodeIDs.isEmpty else { return [] }
        let ids = Array(episodeIDs)
        return try context.fetch(FetchDescriptor<EpisodeProfile>(
            predicate: #Predicate<EpisodeProfile> { ids.contains($0.episodeID) }
        ))
    }

    private static func evidencePodcastIDs(
        preferences: [PreferenceSignal],
        playbackEvents: [PlaybackEvent]
    ) -> [UUID] {
        var seen = Set<UUID>()
        var ids: [UUID] = []

        func append(_ id: UUID) {
            guard !seen.contains(id) else { return }
            seen.insert(id)
            ids.append(id)
        }

        for preference in preferences
        where (preference.action == .like || preference.action == .moreLikeThis)
            && preference.episode.podcast.isSubscribed {
            append(preference.episode.podcast.id)
        }
        for event in playbackEvents where event.kind == .completed {
            guard let episode = event.episode, episode.podcast.isSubscribed else { continue }
            append(episode.podcast.id)
        }

        return ids
    }

    private static func recentCandidateDescriptor(limit: Int) -> FetchDescriptor<Episode> {
        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> {
                $0.podcast.isSubscribed == true && $0.isPlayed == false
            },
            sortBy: [SortDescriptor(\Episode.pubDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }

    private static func evidencePodcastCandidateDescriptor(podcastIDs: [UUID], limit: Int) -> FetchDescriptor<Episode> {
        guard !podcastIDs.isEmpty else {
            var descriptor = FetchDescriptor<Episode>(
                predicate: #Predicate<Episode> { _ in false }
            )
            descriptor.fetchLimit = 0
            return descriptor
        }

        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> {
                podcastIDs.contains($0.podcast.id)
                    && $0.podcast.isSubscribed == true
                    && $0.isPlayed == false
            },
            sortBy: [SortDescriptor(\Episode.pubDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }

    private static func inProgressCandidateDescriptor(limit: Int) -> FetchDescriptor<Episode> {
        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> {
                $0.playedPosition > 0 && $0.isPlayed == false
            },
            sortBy: [SortDescriptor(\Episode.pubDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }

    private static func uniqueEpisodes(_ episodes: [Episode]) -> [Episode] {
        var seen = Set<UUID>()
        var result: [Episode] = []
        for episode in episodes where !seen.contains(episode.id) {
            seen.insert(episode.id)
            result.append(episode)
        }
        return result
    }
}

struct RecommendationSignal: Hashable {
    let label: String
    let value: String

    var displayText: String {
        "\(label): \(value)"
    }
}

struct ScoredEpisode {
    let episode: Episode
    let score: Double
    let explanation: String
    let signalTrace: [RecommendationSignal]

    init(episode: Episode, score: Double, explanation: String, signalTrace: [RecommendationSignal] = []) {
        self.episode = episode
        self.score = score
        self.explanation = explanation
        self.signalTrace = signalTrace
    }
}

import Foundation
import SwiftData

@MainActor
enum TasteProfileService {
    private static let refreshInterval: TimeInterval = 10 * 60

    /// Half-life of a passive signal in days. Drives the exponential
    /// `recencyWeight` so a tag's contribution halves every `decayHalfLifeDays`.
    /// Tightened from the previous ~60d / 0.15-floor formulation: that
    /// kept a 6-month-old binge contributing forever, which contradicts
    /// the brand promise ("the recommendation engine works only on
    /// signals the user generated themselves — recently"). 14 days
    /// means a month-old completion already drops to ~25%, a 90-day
    /// signal is ~1.2%, and anything past the cutoff is zero.
    static let decayHalfLifeDays: Double = 14

    /// Hard cutoff in days. Beyond this, a signal contributes nothing
    /// regardless of how strong it originally was. Matches the 90-day
    /// fetch window RecommendationService already uses, with 30 days
    /// of headroom so signals barely past 90d don't snap to zero. Lets
    /// us drop the previous `0.15` recency floor cleanly.
    static let signalCutoffDays: Double = 120

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

        // Only load events inside the cutoff window. Previously this
        // method fetched the full PlaybackEvent / PreferenceSignal
        // history, then relied on the recencyWeight floor to dampen
        // old contributions — which never reached zero. Filtering at
        // fetch time keeps the in-memory set bounded and makes the
        // cutoff a hard contract that's testable.
        let cutoffDate = Date().addingTimeInterval(-signalCutoffDays * 86_400)
        let episodeProfiles = try context.fetch(FetchDescriptor<EpisodeProfile>())
        let playbackEvents = try context.fetch(FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate<PlaybackEvent> { $0.date >= cutoffDate }
        ))
        let preferenceSignals = try context.fetch(FetchDescriptor<PreferenceSignal>(
            predicate: #Predicate<PreferenceSignal> { $0.date >= cutoffDate }
        ))

        let profileByEpisodeID = Dictionary(uniqueKeysWithValues: episodeProfiles.map { ($0.episodeID, $0) })
        var tagScores: [String: Double] = [:]

        for signal in preferenceSignals {
            guard let episodeProfile = profileByEpisodeID[signal.episode.id] else { continue }
            let weight = preferenceWeight(signal.action) * recencyWeight(for: signal.date)
            guard weight != 0 else { continue }
            // Explicit signals (Like / More / Less / NotInterested) are
            // intentional taps — no binge dampening. The brand promise
            // hinges on these reading as first-class.
            for tag in episodeProfile.tags {
                tagScores[tag.normalizedTasteKey, default: 0] += weight
            }
        }

        // Binge dampener: the k-th passive playback contribution from a
        // single show contributes `1/sqrt(k)` of its raw weight, so one
        // show with 30 completions doesn't crush all other signal. The
        // first completion still counts at full weight; the second at
        // ~71%, fifth at ~45%, twentieth at ~22%. Explicit signals
        // above are not dampened because they were tapped deliberately.
        var showPlaybackCount: [String: Int] = [:]
        let sortedEvents = playbackEvents.sorted { $0.date > $1.date }
        for event in sortedEvents {
            guard let episode = event.episode,
                  let episodeProfile = profileByEpisodeID[episode.id] else { continue }
            let baseWeight = playbackTagWeight(event.kind) * recencyWeight(for: event.date)
            guard baseWeight != 0 else { continue }
            let showTitle = episode.podcast.title
            let priorCount = showPlaybackCount[showTitle, default: 0]
            showPlaybackCount[showTitle] = priorCount + 1
            let dampener = baseWeight > 0
                ? 1.0 / sqrt(Double(priorCount + 1))
                : 1.0 // negative signals (skipped, abandoned) are not binge-dampened
            let weight = baseWeight * dampener
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
            guard weight != 0 else { continue }
            showScores[show, default: 0] += weight
        }

        // Same binge dampener for show affinity — the k-th passive
        // event from the same show contributes 1/sqrt(k). Without
        // this, the show with the most completed events always sits
        // atop `showAffinity` even after the user has moved on.
        var showShowCount: [String: Int] = [:]
        for event in sortedEvents {
            guard let show = event.episode?.podcast.title else { continue }
            let baseWeight = playbackShowWeight(event.kind) * recencyWeight(for: event.date)
            guard baseWeight != 0 else { continue }
            let priorCount = showShowCount[show, default: 0]
            showShowCount[show] = priorCount + 1
            let dampener = baseWeight > 0
                ? 1.0 / sqrt(Double(priorCount + 1))
                : 1.0
            showScores[show, default: 0] += baseWeight * dampener
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

    /// Exponential decay with a hard cutoff. No floor — past the
    /// cutoff a signal contributes zero, so a 6-month-old binge stops
    /// influencing today's recommendations entirely. Half-life is
    /// `decayHalfLifeDays`, so the weight halves every 14 days.
    static func recencyWeight(for date: Date) -> Double {
        let seconds = Date().timeIntervalSince(date)
        let days = max(0, seconds / 86_400)
        guard days <= signalCutoffDays else { return 0 }
        // exp(-ln(2) * days / halfLife) — clean half-life formulation
        return exp(-Double.ln2 * days / decayHalfLifeDays)
    }
}

private extension Double {
    /// Natural log of 2, used by the half-life recency curve.
    static let ln2: Double = log(2.0)
}

private extension String {
    var normalizedTasteKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

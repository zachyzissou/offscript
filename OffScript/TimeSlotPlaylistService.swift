import Foundation
import OSLog
import SwiftData

/// Builds a queue that fits a target time window using the recommendation
/// scorer + a greedy bin-packing pass. Used by the "Got 25 minutes?" button on
/// the Queue tab and the matching App Intent.
@MainActor
final class TimeSlotPlaylistService {
    static let shared = TimeSlotPlaylistService()

    private let logger = Logger(subsystem: "OffScript", category: "TimeSlot")
    private let recommendationService = RecommendationService()

    private init() {}

    struct Plan {
        let episodes: [Episode]
        let totalDuration: TimeInterval
        let targetMinutes: Int

        var summary: String {
            let mins = Int(totalDuration / 60)
            return "\(episodes.count) episodes · \(mins) min"
        }
    }

    /// Picks up to 6 episodes that fit a target window. Prefers in-progress
    /// episodes first so the user finishes things they started, then fills with
    /// top-scored unstarted episodes.
    func buildPlan(targetMinutes: Int, in context: ModelContext) async -> Plan? {
        let target = TimeInterval(targetMinutes * 60)
        var remaining = target
        var picked: [Episode] = []
        var pickedIDs = Set<UUID>()

        // 1. Prefer in-progress episodes (already started, not finished).
        let inProgress = (try? context.fetch(FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.playedPosition > 0 && !$0.isPlayed }
        ))) ?? []

        let sortedInProgress = inProgress.sorted { lhs, rhs in
            (lhs.lastPlayedAt ?? .distantPast) > (rhs.lastPlayedAt ?? .distantPast)
        }

        for episode in sortedInProgress {
            let estimatedRemaining = remainingMinutesEstimate(for: episode)
            if estimatedRemaining <= remaining + 60 && remaining > 60 {
                picked.append(episode)
                pickedIDs.insert(episode.id)
                remaining -= min(estimatedRemaining, remaining)
                if picked.count >= 6 || remaining < 90 { break }
            }
        }

        // 2. Fill with recommendation-scored episodes.
        if remaining > 60 {
            let sections = (try? recommendationService.homeSections(context: context, limit: 8)) ?? []
            let pool = sections
                .flatMap(\.scoredEpisodes)
                .sorted { $0.score > $1.score }
                .map(\.episode)

            for episode in pool {
                guard !pickedIDs.contains(episode.id),
                      !episode.isPlayed,
                      let duration = episode.duration else { continue }
                if duration <= remaining + 60 {
                    picked.append(episode)
                    pickedIDs.insert(episode.id)
                    remaining -= min(duration, remaining)
                    if picked.count >= 6 || remaining < 90 { break }
                }
            }
        }

        guard !picked.isEmpty else { return nil }

        let total = picked.reduce(0) { $0 + (durationEstimate(for: $1)) }
        return Plan(episodes: picked, totalDuration: total, targetMinutes: targetMinutes)
    }

    /// Replaces the current queue with the plan and starts playback.
    func apply(plan: Plan, in context: ModelContext, autoplay: Bool = true) {
        // Clear the existing queue first so the user gets a clean slate.
        let existing = (try? context.fetch(FetchDescriptor<QueueItem>())) ?? []
        for item in existing {
            item.episode.isQueued = false
            context.delete(item)
        }

        for (index, episode) in plan.episodes.enumerated() {
            let item = QueueItem(episode: episode, position: index)
            episode.isQueued = true
            context.insert(item)
        }

        try? context.save()

        if autoplay, let first = plan.episodes.first {
            PlaybackController.shared.play(first, in: context, origin: .queue)
        }

        TelemetryService.track(
            "timeslot_playlist_built",
            metadata: [
                "minutes": "\(plan.targetMinutes)",
                "episodes": "\(plan.episodes.count)",
                "actual_minutes": "\(Int(plan.totalDuration / 60))",
                "autoplay": autoplay ? "true" : "false"
            ],
            in: context
        )
    }

    // MARK: - Helpers

    private func durationEstimate(for episode: Episode) -> TimeInterval {
        episode.duration ?? 30 * 60
    }

    private func remainingMinutesEstimate(for episode: Episode) -> TimeInterval {
        guard let duration = episode.duration, duration > 0 else { return 30 * 60 }
        return max(60, duration - episode.playedPosition)
    }
}

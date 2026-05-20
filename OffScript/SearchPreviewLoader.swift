import Foundation
import OSLog
import SwiftUI

// MARK: - SearchPreviewLoader
//
// Lazy, per-row latest-episode previews for Search results.
//
// The pattern: a Search hit gives us title + author + artwork + the iTunes
// `primaryGenreName` we abuse as `summary`. That's not enough for a stranger
// to decide whether to subscribe — OffScript's whole pitch is "fewer choices,
// better listening." So we pull the freshest episode out of each row's RSS
// feed on demand, using `PodcastPreviewService` (already exposed for
// `DiscoveryService`).
//
// Rules of the road:
//
// 1. Lazy. Don't fetch unless the row is being rendered. The 25-result
//    iTunes search would otherwise fan out into 25 RSS fetches the moment
//    the user types two characters.
// 2. Capped. Only the first `previewCap` (default 8) rows fetch — that's
//    everything visible above the fold on a tall device, plus a little
//    headroom. Rows below the cap render the no-preview shape, identical
//    to a `.failed` row, so layout doesn't shift if the user scrolls down.
// 3. Cached. Once a feed URL has been fetched (success or failure), we
//    keep the result. A query change clears in-flight tasks but keeps the
//    cache; flipping back to "the verge" shouldn't re-fetch The Vergecast.
// 4. Cancel-safe. Each in-flight fetch is tracked so a query change can
//    cancel them — the user typing "vergecas" then "vergecast" shouldn't
//    leave eight orphaned RSS parses chewing through main thread.
//
// State exposed to views is a small enum, not Optional<Snapshot>, so the
// row can render skeleton-while-loading without ambiguity.

@MainActor
@Observable
final class SearchPreviewLoader {
    enum PreviewState: Equatable {
        case loading
        case loaded(SearchPreviewMetadata)
        case failed

        static func == (lhs: PreviewState, rhs: PreviewState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.failed, .failed):
                return true
            case let (.loaded(a), .loaded(b)):
                return a == b
            default:
                return false
            }
        }
    }

    private let logger = Logger(subsystem: "com.offscript", category: "SearchPreview")
    private var states: [URL: PreviewState] = [:]
    private var inFlight: [URL: Task<Void, Never>] = [:]
    private let previewCap: Int
    private let now: () -> Date
    private let fetch: (PodcastSearchResult) async throws -> PodcastPreviewSnapshot

    init(
        previewCap: Int = 8,
        now: @escaping () -> Date = Date.init,
        fetch: @escaping (PodcastSearchResult) async throws -> PodcastPreviewSnapshot = { result in
            try await PodcastPreviewService.preview(for: result, episodeLimit: 1)
        }
    ) {
        self.previewCap = previewCap
        self.now = now
        self.fetch = fetch
    }

    /// Returns the current state for a row, requesting a fetch when the row
    /// is within `previewCap` of the top of the result list and hasn't been
    /// seen before. Rows beyond the cap return `nil` — the row treats `nil`
    /// the same as a `.failed` row (no preview block) so the layout stays
    /// stable as the user scrolls.
    func state(for result: PodcastSearchResult, rank: Int) -> PreviewState? {
        if let existing = states[result.feedURL] {
            return existing
        }
        guard rank <= previewCap else { return nil }
        requestFetch(for: result)
        return states[result.feedURL]
    }

    /// Cancel in-flight previews when the query changes. The cache itself
    /// is preserved so re-typing a previous query feels instant.
    func cancelAllInFlight() {
        for (_, task) in inFlight { task.cancel() }
        inFlight.removeAll()
    }

    /// Clear absolutely everything — cache and in-flight. Test-only seam;
    /// the real UI never needs this.
    func resetForTesting() {
        cancelAllInFlight()
        states.removeAll()
    }

    private func requestFetch(for result: PodcastSearchResult) {
        guard inFlight[result.feedURL] == nil else { return }
        states[result.feedURL] = .loading

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.fetch(result)
                if Task.isCancelled { return }
                await self.recordSuccess(for: result, snapshot: snapshot)
            } catch {
                if Task.isCancelled { return }
                await self.recordFailure(for: result, error: error)
            }
        }
        inFlight[result.feedURL] = task
    }

    private func recordSuccess(for result: PodcastSearchResult, snapshot: PodcastPreviewSnapshot) {
        defer { inFlight[result.feedURL] = nil }
        guard let metadata = SearchPreviewMetadata(snapshot: snapshot, now: now()) else {
            states[result.feedURL] = .failed
            return
        }
        states[result.feedURL] = .loaded(metadata)
    }

    private func recordFailure(for result: PodcastSearchResult, error: Error) {
        defer { inFlight[result.feedURL] = nil }
        logger.debug("Search preview failed for \(result.feedURL.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        states[result.feedURL] = .failed
    }
}

// MARK: - SearchPreviewMetadata
//
// Pre-formatted, view-ready snapshot of the freshest episode for a Search
// row. We do the formatting once at fetch-time so the row stays a pure
// renderer (no `Date()` calls, no `RelativeDateTimeFormatter` per frame).
//
// Three pieces matter to the user reading a Search row:
//   - The latest episode's title — what they'd actually start with.
//   - When it dropped — "is this show still active?"
//   - How long it runs — "do I have time for this?"
//
// `freshnessLabel` is intentionally short and uppercased — Tuner mono
// vocabulary, sits next to the existing `● IN LIBRARY` / `○ RSS IMPORT`
// chip. `freshnessSpoken` is the VoiceOver-friendly counterpart.

struct SearchPreviewMetadata: Equatable {
    let latestEpisodeTitle: String
    let pubDate: Date?
    let durationSeconds: TimeInterval?
    /// Pre-formatted "3D AGO" / "TODAY" / abbreviated date — uppercased,
    /// safe for `TunerLabel`.
    let freshnessLabel: String
    /// "3 days ago" / "today" / abbreviated date — VoiceOver-friendly.
    let freshnessSpoken: String
    /// Pre-formatted "47m" / "1h 12m" — empty string if we don't have a
    /// duration. View renders the separator dot only when this is set.
    let durationLabel: String
    /// "47 minutes" / "1 hour 12 minutes" — empty when no duration. Already
    /// plural-correct via `EpisodeDurationFormatter.spoken`.
    let durationSpoken: String

    init?(snapshot: PodcastPreviewSnapshot, now: Date) {
        // A snapshot with zero episodes is not a useful preview — we'd be
        // pinning a "● LATEST" chip with no content. Treat as failure so
        // the row renders the no-preview shape.
        guard let latest = snapshot.latestEpisodes.first else { return nil }
        let trimmedTitle = latest.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        self.latestEpisodeTitle = trimmedTitle
        self.pubDate = latest.pubDate
        self.durationSeconds = latest.duration

        if let pubDate = latest.pubDate {
            self.freshnessLabel = Self.freshnessLabel(pubDate: pubDate, now: now)
            self.freshnessSpoken = Self.freshnessSpoken(pubDate: pubDate, now: now)
        } else {
            self.freshnessLabel = "LATEST"
            self.freshnessSpoken = "latest episode"
        }

        if let duration = latest.duration, duration >= 60 {
            self.durationLabel = EpisodeDurationFormatter.short(duration).uppercased()
            self.durationSpoken = EpisodeDurationFormatter.spoken(duration)
        } else {
            self.durationLabel = ""
            self.durationSpoken = ""
        }
    }

    init(
        latestEpisodeTitle: String,
        pubDate: Date?,
        durationSeconds: TimeInterval?,
        freshnessLabel: String,
        freshnessSpoken: String,
        durationLabel: String,
        durationSpoken: String
    ) {
        self.latestEpisodeTitle = latestEpisodeTitle
        self.pubDate = pubDate
        self.durationSeconds = durationSeconds
        self.freshnessLabel = freshnessLabel
        self.freshnessSpoken = freshnessSpoken
        self.durationLabel = durationLabel
        self.durationSpoken = durationSpoken
    }

    /// Mono "3D AGO" / "TODAY" / abbreviated date string. The thresholds
    /// (today / yesterday / N days / N weeks / abbreviated) mirror Apple
    /// Podcasts' own freshness chip — feels familiar without aping it.
    static func freshnessLabel(pubDate: Date, now: Date) -> String {
        let interval = now.timeIntervalSince(pubDate)
        if interval < 0 {
            // Feeds occasionally publish with a future-dated `pubDate`
            // because of timezone slips. Treat as "today" rather than
            // showing the user a "−1D AGO" chip.
            return "TODAY"
        }
        let days = Int(interval / 86_400)
        switch days {
        case 0: return "TODAY"
        case 1: return "1D AGO"
        case ..<7: return "\(days)D AGO"
        case ..<14: return "1W AGO"
        case ..<60:
            let weeks = days / 7
            return "\(weeks)W AGO"
        default:
            return pubDate.formatted(date: .abbreviated, time: .omitted).uppercased()
        }
    }

    /// VoiceOver-friendly counterpart. Lowercase, plural-correct, no
    /// abbreviations — the screen reader speaks "three days ago" not
    /// "three D ago."
    static func freshnessSpoken(pubDate: Date, now: Date) -> String {
        let interval = now.timeIntervalSince(pubDate)
        if interval < 0 { return "today" }
        let days = Int(interval / 86_400)
        switch days {
        case 0: return "today"
        case 1: return "1 day ago"
        case ..<7: return "\(days) days ago"
        case ..<14: return "1 week ago"
        case ..<60:
            let weeks = days / 7
            return "\(weeks) weeks ago"
        default:
            return pubDate.formatted(date: .abbreviated, time: .omitted)
        }
    }
}

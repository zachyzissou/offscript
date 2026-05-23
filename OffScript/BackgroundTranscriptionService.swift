import BackgroundTasks
import Foundation
import OSLog
import SwiftData

private let bgTranscribeLogger = Logger(subsystem: "com.offscript", category: "BackgroundTranscription")

/// Opportunistically transcribes recently-downloaded episodes in the
/// background, so by the time the user opens EpisodeDetailView the transcript
/// is already there.
///
/// Modern shape: this is a real `BGTaskScheduler` task wired via the SwiftUI
/// `.backgroundTask(.appRefresh:)` modifier in `OffScriptApp` (see audit doc
/// `2026-05-19-transcript-pipeline-audit.md` Phase 24 for the host-app wiring
/// that's still required). Previously the service was a foreground-only
/// `NWPathMonitor`-driven loop that never ran in true background — which
/// defeated the whole point of "transcribe overnight". The new entry point
/// `performTranscriptionRound(container:)` is invoked by the OS when our
/// app-refresh window opens, processes a bounded number of episodes, and
/// re-arms the next round before doing work.
///
/// Policy:
///   - Process at most `maxEpisodesPerRun` episodes per refresh window —
///     Speech is CPU-heavy and iOS only gives us ~30s of wall clock.
///   - Hard cap at `maxRunDurationSeconds` so we leave margin to flush
///     SwiftData writes before the system reclaims us.
///   - Skip episodes that already have a persisted transcript.
///   - Skip episodes longer than 90 minutes (Speech struggles with long-form
///     in a single shot; a future SpeechAnalyzer-based path will handle these).
///   - Cancellation: the enclosing `.backgroundTask(.appRefresh:)` SwiftUI
///     modifier surfaces system reclaim as `Task` cancellation, which we
///     observe via `Task.checkCancellation()` between episodes.
///   - Failure throttle: 3 consecutive failed runs triggers a 2-hour cooldown,
///     mirroring `BackgroundFeedRefresh`'s task-level backoff. Resets on
///     success.
enum BackgroundTranscriptionService {
    /// BGTaskScheduler identifier — must match `Info.plist`'s
    /// `BGTaskSchedulerPermittedIdentifiers` entry. As of Phase 24 the
    /// Info.plist entry is still DEFERRED (see audit doc).
    static let taskIdentifier = "com.offscript.background-transcription"

    /// Wall-clock cap per refresh. iOS gives background tasks ~30s typically;
    /// cap at 25 to leave margin for the SwiftData save on exit.
    static let maxRunDurationSeconds: TimeInterval = 25

    /// Max episodes to process per refresh. Each on-device Speech pass is
    /// slow (real-time-ish on audio length), so even hitting 3 inside the
    /// 25s budget is optimistic — most rounds will only finish one.
    static let maxEpisodesPerRun = 3

    /// Min gap between scheduled rounds in the steady state.
    private static let minimumInterval: TimeInterval = 60 * 60 // 1 hour
    /// Cooldown when the failure throttle trips.
    private static let backoffInterval: TimeInterval = 2 * 60 * 60 // 2 hours
    /// How many consecutive failed runs before we back off the next schedule.
    private static let failureThrottleThreshold = 3

    /// Skip episodes longer than this (Speech single-shot doesn't handle
    /// long-form well — SpeechAnalyzer is the eventual fix).
    private static let maxEpisodeDurationSeconds: TimeInterval = 90 * 60

    private enum DefaultsKey {
        static let consecutiveFailures = "BackgroundTranscription.consecutiveFailures"
        static let lastFailureAt = "BackgroundTranscription.lastFailureAt"
    }

    // MARK: - Foreground compatibility shims

    /// Existing call sites (`ContentView`, `DownloadService`) reference the
    /// pre-refactor singleton API. These shims keep them compiling without
    /// re-introducing the NWPathMonitor + foreground scan loop. The
    /// `.backgroundTask` path now owns the actual transcription work.
    static let shared = ForegroundCompat()

    @MainActor
    final class ForegroundCompat {
        fileprivate init() {}

        /// No-op shim. Previously kicked off the NWPathMonitor + scan loop;
        /// now the work happens in `performTranscriptionRound` via
        /// BGTaskScheduler. Kept so `ContentView.onAppear` still compiles.
        func configure(context: ModelContext) {
            bgTranscribeLogger.debug("configure(context:) called — no-op under BGTaskScheduler path")
        }

        /// No-op shim. The post-download foreground kickoff is superseded by
        /// the scheduled background round which picks up downloaded episodes
        /// on its own cadence.
        func didFinishDownload(episodeID: UUID) {
            bgTranscribeLogger.debug("didFinishDownload(episodeID:) called — no-op under BGTaskScheduler path")
        }
    }

    // MARK: - Scheduling

    /// Schedule the next round. Call with `backoff: true` after a run dominated
    /// by failures so the next attempt spaces out and we don't burn iOS's
    /// background-refresh budget on a broken pipeline.
    static func scheduleNextRound(backoff: Bool = false) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        let interval = backoff ? backoffInterval : minimumInterval
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)

        do {
            try BGTaskScheduler.shared.submit(request)
            bgTranscribeLogger.info(
                "Scheduled next background transcription round in \(interval / 60, privacy: .public) minutes\(backoff ? " (backoff)" : "", privacy: .public)"
            )
        } catch {
            bgTranscribeLogger.error(
                "Failed to schedule background transcription round: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Execution

    /// Entry point invoked by the `.backgroundTask(.appRefresh:)` modifier.
    ///
    /// Cancellation: the modifier surfaces system reclaim as cooperative
    /// `Task` cancellation. We `try Task.checkCancellation()` between
    /// episodes and treat `CancellationError` as an info-level event
    /// (normal, not a failure — don't trip the throttle).
    ///
    /// Re-arm: we schedule the next round BEFORE doing work so the timer is
    /// always queued even if we get force-stopped. On exit, if every attempt
    /// failed we re-schedule with backoff to space out retries.
    @Sendable
    @MainActor
    static func performTranscriptionRound(container: ModelContainer) async {
        bgTranscribeLogger.info("Background transcription round starting")

        // Always queue the next round first so even a force-stop leaves a
        // timer in place.
        scheduleNextRound()

        let start = Date()
        let context = ModelContext(container)
        var attempted = 0
        var failed = 0

        do {
            let candidates = try fetchCandidates(in: context, limit: maxEpisodesPerRun)
            bgTranscribeLogger.info(
                "Background transcription: \(candidates.count, privacy: .public) candidate(s) queued"
            )

            for episode in candidates {
                let elapsed = Date().timeIntervalSince(start)
                let remainingBudget = maxRunDurationSeconds - elapsed
                if remainingBudget <= 1 {
                    bgTranscribeLogger.info(
                        "Hit time budget (\(elapsed, privacy: .public)s) after \(attempted, privacy: .public) episode(s) — exiting"
                    )
                    break
                }
                try Task.checkCancellation()

                guard let localURL = DownloadService.shared.localURL(for: episode) else {
                    bgTranscribeLogger.info(
                        "Skipping \(episode.title, privacy: .public) — local file vanished"
                    )
                    continue
                }

                attempted += 1
                bgTranscribeLogger.info(
                    "Transcribing in background: \(episode.title, privacy: .public)"
                )
                do {
                    let transcriptionTask = Task { @MainActor in
                        try await SpeechTranscriptionService.shared.transcribe(
                            episode: episode,
                            localAudioURL: localURL,
                            persistTo: context
                        )
                    }
                    let timeoutTask = Task {
                        try await Task.sleep(for: .seconds(remainingBudget))
                        transcriptionTask.cancel()
                    }
                    defer { timeoutTask.cancel() }
                    _ = try await transcriptionTask.value
                } catch is CancellationError {
                    // Re-throw so the outer catch handles cancellation
                    // uniformly (don't classify as a per-episode failure).
                    throw CancellationError()
                } catch {
                    failed += 1
                    bgTranscribeLogger.error(
                        "Background transcription failed for \(episode.title, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                    // Per-episode failure isn't fatal — keep trying others
                    // within budget. The task-level throttle below catches
                    // the systemic-failure case.
                }
            }
        } catch is CancellationError {
            bgTranscribeLogger.info("Background transcription cancelled by system")
            // System reclaim isn't a failure — don't trip the throttle.
            return
        } catch {
            bgTranscribeLogger.error(
                "Background transcription round failed: \(error.localizedDescription, privacy: .public)"
            )
            recordRoundOutcome(succeeded: false)
            return
        }

        // Task-level failure throttle: if we tried ≥1 episode and every
        // attempt failed, treat the round as a failure. Three consecutive
        // failures trips the 2-hour cooldown. SpeechTranscriptionService
        // already short-circuits on cached/persisted hits, so a "round with
        // 0 attempts" usually means nothing to do — not a failure.
        let roundFailed = attempted > 0 && failed == attempted
        recordRoundOutcome(succeeded: !roundFailed)

        bgTranscribeLogger.info(
            "Background transcription round completed (attempted=\(attempted, privacy: .public), failed=\(failed, privacy: .public))"
        )
    }

    // MARK: - Candidate selection

    /// Fetches downloaded, not-yet-transcribed episodes ranked by
    /// likelihood-of-being-played-next: recent listening first, then most
    /// recently downloaded. Bounded so we don't pull thousands of rows on
    /// users with large libraries.
    static func fetchCandidates(in context: ModelContext, limit: Int) throws -> [Episode] {
        // Pull a small superset, then filter in memory:
        //   - `duration` is optional → can't be expressed cleanly in #Predicate
        //   - persisted-transcript lookup is a second-table join we resolve
        //     here rather than try to push down
        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.isDownloaded == true },
            sortBy: [
                SortDescriptor(\Episode.lastPlayedAt, order: .reverse),
                SortDescriptor(\Episode.downloadCompletedAt, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 25

        let downloaded = try context.fetch(descriptor)
        var picked: [Episode] = []
        picked.reserveCapacity(limit)

        for episode in downloaded {
            if let duration = episode.duration, duration > maxEpisodeDurationSeconds { continue }
            if SpeechTranscriptionService.shared.persistedTranscript(for: episode.id, in: context) != nil {
                continue
            }
            picked.append(episode)
            if picked.count >= limit { break }
        }
        return picked
    }

    // MARK: - Failure throttle

    /// Records the outcome of a round. After `failureThrottleThreshold`
    /// consecutive failures we schedule the next round with backoff so we
    /// don't churn the background budget on a systemic problem (Speech
    /// permission denied, on-device recognition unavailable, etc.). Resets
    /// to zero on success.
    private static func recordRoundOutcome(succeeded: Bool) {
        let defaults = UserDefaults.standard
        if succeeded {
            if defaults.integer(forKey: DefaultsKey.consecutiveFailures) > 0 {
                bgTranscribeLogger.info("Resetting consecutive-failure counter after successful round")
            }
            defaults.set(0, forKey: DefaultsKey.consecutiveFailures)
            defaults.removeObject(forKey: DefaultsKey.lastFailureAt)
            return
        }

        let nextCount = defaults.integer(forKey: DefaultsKey.consecutiveFailures) + 1
        defaults.set(nextCount, forKey: DefaultsKey.consecutiveFailures)
        defaults.set(Date(), forKey: DefaultsKey.lastFailureAt)
        bgTranscribeLogger.warning(
            "Background transcription round failed — consecutive failures now \(nextCount, privacy: .public)"
        )

        if nextCount >= failureThrottleThreshold {
            bgTranscribeLogger.warning(
                "Failure threshold reached (\(nextCount, privacy: .public)) — rescheduling next round with backoff"
            )
            scheduleNextRound(backoff: true)
        }
    }
}

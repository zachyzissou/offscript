import ActivityKit
import Combine
import Foundation
import OSLog
import WidgetKit

private let publisherLogger = Logger(subsystem: "com.offscript", category: "NowPlayingPublisher")

/// Bridges `PlaybackController` state to:
///   - Widgets (via App Group UserDefaults snapshot + WidgetCenter reload)
///   - Live Activities (via ActivityKit start/update/end)
///
/// Subscribes to PlaybackController's published properties + the time
/// publisher, debounces aggressive updates (e.g. 1Hz time tick) so Live
/// Activity hits Apple's update-frequency budget cleanly.
@MainActor
final class NowPlayingPublisher {
    static let shared = NowPlayingPublisher()

    private var cancellables = Set<AnyCancellable>()
    private var currentActivity: Activity<NowPlayingActivityAttributes>?
    private var lastWriteAt: Date = .distantPast
    private let writeThrottle: TimeInterval = 5  // floor between widget writes
    private var pendingWriteTask: Task<Void, Never>?

    private init() {}

    #if DEBUG
    /// Drop all Combine subscriptions and tear down any in-flight Live
    /// Activity. Used by `PlaybackController.debugResetForTesting()` so
    /// the publisher doesn't hold stale `Episode` references across
    /// in-memory ModelContainers in the test suite.
    func debugStopForTesting() {
        cancellables.removeAll()
        pendingWriteTask?.cancel()
        pendingWriteTask = nil
        if let activity = currentActivity {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        currentActivity = nil
        lastWriteAt = .distantPast
    }
    #endif

    /// Hooked once at app launch from ContentView .task. Idempotent.
    func start() {
        guard cancellables.isEmpty else { return }

        let player = PlaybackController.shared

        // React to episode + isPlaying changes immediately (cheap).
        player.$currentEpisode
            .combineLatest(player.$isPlaying)
            .sink { [weak self] _, _ in
                self?.scheduleWrite(force: true)
            }
            .store(in: &cancellables)

        // Time ticks fire ~1Hz; we throttle the side effects.
        // Main's PlaybackController publishes currentTime directly (no
        // PlaybackTimePublisher indirection), so we subscribe straight to it.
        player.$currentTime
            .sink { [weak self] _ in
                self?.scheduleWrite(force: false)
            }
            .store(in: &cancellables)
    }

    /// Schedule a snapshot write. `force` skips the throttle (used on real
    /// state changes); time-tick callers use force=false to coalesce.
    private func scheduleWrite(force: Bool) {
        // Always cancel any previously-scheduled task. Without this, a forced
        // state-change write (isPlaying flip) leaves a pending time-tick task
        // running behind it — the task fires a few seconds later and produces
        // a redundant write/reload burst that can exceed ActivityKit's
        // update-frequency budget.
        pendingWriteTask?.cancel()
        pendingWriteTask = nil

        let elapsed = Date().timeIntervalSince(lastWriteAt)
        if force || elapsed >= writeThrottle {
            performWrite()
            return
        }

        let remaining = writeThrottle - elapsed
        pendingWriteTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            performWrite()
        }
    }

    private func performWrite() {
        lastWriteAt = .now
        let player = PlaybackController.shared

        guard let episode = player.currentEpisode else {
            // Nothing playing — clear the snapshot, end any active activity.
            NowPlayingStorage.write(.empty)
            WidgetCenter.shared.reloadAllTimelines()
            endActivity()
            return
        }

        let snapshot = NowPlayingSnapshot(
            episodeTitle: episode.title,
            podcastTitle: episode.podcast.title,
            artworkURL: episode.artworkURL ?? episode.podcast.artworkURL,
            isPlaying: player.isPlaying,
            currentTime: player.currentTime,
            duration: player.duration,
            updatedAt: .now
        )
        NowPlayingStorage.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        updateActivity(snapshot: snapshot, artworkURL: snapshot.artworkURL)
    }

    // MARK: - Live Activity lifecycle

    private func updateActivity(snapshot: NowPlayingSnapshot, artworkURL: URL?) {
        let state = NowPlayingActivityAttributes.ContentState(
            episodeTitle: snapshot.episodeTitle,
            podcastTitle: snapshot.podcastTitle,
            isPlaying: snapshot.isPlaying,
            currentTime: snapshot.currentTime,
            duration: snapshot.duration
        )

        if let activity = currentActivity {
            Task {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
            return
        }

        // Need to start a new activity. Apple requires this from the
        // foreground; first state change after backgrounding will be a no-op.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        do {
            currentActivity = try Activity<NowPlayingActivityAttributes>.request(
                attributes: NowPlayingActivityAttributes(artworkURL: artworkURL),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            publisherLogger.info("Started Live Activity for \(snapshot.episodeTitle, privacy: .public)")
        } catch {
            publisherLogger.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func endActivity() {
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }
}

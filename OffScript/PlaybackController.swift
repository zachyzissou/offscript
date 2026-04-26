import AVFoundation
import Combine
import MediaPlayer
import SwiftData
import SwiftUI
import UIKit

/// Lightweight publisher holding only time-varying playback state.
/// Only PlayerView and MiniPlayer should observe this to avoid
/// per-second invalidations in the rest of the view hierarchy.
@MainActor
final class PlaybackTimePublisher: ObservableObject {
    static let shared = PlaybackTimePublisher()
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    private init() {}
}

@MainActor
final class PlaybackController: ObservableObject {
    enum StartOrigin {
        case manual
        case queue
    }

    static let shared = PlaybackController()

    @Published private(set) var currentEpisode: Episode?
    @Published private(set) var isPlaying = false
    @Published var playbackRate: Float = UserDefaults.standard.float(forKey: "offscript.playbackRate").nonZeroOrDefault(1.0)
    @Published var isPlayerPresented = false
    @Published private(set) var sleepTimerEndDate: Date?

    // Preview playback state — streams without persisting to SwiftData
    @Published private(set) var previewEpisodeTitle: String?
    @Published private(set) var previewPodcastTitle: String?
    @Published private(set) var previewArtworkURL: URL?
    @Published private(set) var previewAudioURL: URL?
    var isPreviewMode: Bool { previewAudioURL != nil }

    /// Time state is published via PlaybackTimePublisher so that only
    /// PlayerView and MiniPlayer re-render every second instead of
    /// the entire view hierarchy rooted at ContentView.
    var currentTime: TimeInterval {
        get { PlaybackTimePublisher.shared.currentTime }
        set { PlaybackTimePublisher.shared.currentTime = newValue }
    }

    var duration: TimeInterval {
        get { PlaybackTimePublisher.shared.duration }
        set { PlaybackTimePublisher.shared.duration = newValue }
    }

    let player = AVPlayer()
    private var timeObserver: Any?
    private var completionObserver: Any?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var mediaServicesResetObserver: NSObjectProtocol?
    private var sleepTimerTask: Task<Void, Never>?
    private var modelContext: ModelContext?
    private var isFinishingCurrentEpisode = false
    private var lastPersistedPosition: TimeInterval = 0
    private var lastPersistedEpisodeID: UUID?

    private init() {
        configureAudioSession()
        observeTime()
        observePlaybackCompletion()
        observeSystemAudioEvents()
        configureRemoteCommands()
    }

    func configure(context: ModelContext) {
        modelContext = context
        DownloadService.shared.configure(context: context)
        SyncCoordinator.shared.configure(context: context)
        restoreLastSessionIfNeeded(context: context)
    }

    func play(_ episode: Episode, in context: ModelContext? = nil, origin: StartOrigin = .manual) {
        if let context {
            configure(context: context)
        }

        recordExitEventIfNeeded(replacingWith: episode)

        currentEpisode = episode
        UserDefaults.standard.set(episode.audioURL.absoluteString, forKey: "offscript.lastEpisodeAudioURL")
        let playableURL = DownloadService.shared.localURL(for: episode) ?? episode.audioURL
        let item = AVPlayerItem(url: playableURL)
        player.replaceCurrentItem(with: item)

        let savedPosition = episode.playedPosition
        let introSkip = TimeInterval(PodcastPreferences.skipIntroSeconds(for: episode.podcast.id))

        if savedPosition > 0 {
            let time = CMTime(seconds: savedPosition, preferredTimescale: 600)
            player.seek(to: time)
            currentTime = savedPosition
        } else if introSkip > 0 {
            // Fresh start on this episode — honor the per-show intro skip so
            // the user doesn't have to scrub past the same theme music.
            let time = CMTime(seconds: introSkip, preferredTimescale: 600)
            player.seek(to: time)
            currentTime = introSkip
        } else {
            currentTime = 0
        }
        lastPersistedEpisodeID = episode.id
        lastPersistedPosition = currentTime

        player.play()
        // Honor per-podcast playback rate override if present, otherwise the
        // user's global preferred rate.
        let effectiveRate = PodcastPreferences.playbackRate(for: episode.podcast.id) ?? playbackRate
        player.rate = effectiveRate
        isPlaying = true
        isPlayerPresented = true
        startOrUpdateLiveActivity(force: true)
        recordPlaybackEvent(kind: origin == .queue ? .advancedFromQueue : (savedPosition > 0 ? .resumed : .started), episode: episode, position: currentTime)
        TelemetryService.track(
            origin == .queue ? "queue_autoplay_started" : "play_started",
            metadata: [
                "episode": episode.title,
                "podcast": episode.podcast.title,
                "origin": origin == .queue ? "queue" : "manual",
                "source": DownloadService.shared.localURL(for: episode) == nil ? "stream" : "download"
            ],
            in: modelContext
        )
        updateNowPlaying(episode: episode)
    }

    /// Stream an episode preview without subscribing or persisting to SwiftData.
    func playPreview(title: String, podcastTitle: String, audioURL: URL, artworkURL: URL?) {
        // If currently playing a library episode, pause it first
        if currentEpisode != nil && !isPreviewMode {
            player.pause()
        }

        previewEpisodeTitle = title
        previewPodcastTitle = podcastTitle
        previewAudioURL = audioURL
        previewArtworkURL = artworkURL

        let item = AVPlayerItem(url: audioURL)
        player.replaceCurrentItem(with: item)
        player.play()
        player.rate = playbackRate
        isPlaying = true
    }

    /// Stop preview and optionally resume the library episode that was playing.
    func stopPreview() {
        guard isPreviewMode else { return }
        player.pause()

        previewEpisodeTitle = nil
        previewPodcastTitle = nil
        previewAudioURL = nil
        previewArtworkURL = nil

        // Resume library episode if one was loaded
        if let episode = currentEpisode {
            let item = AVPlayerItem(url: DownloadService.shared.localURL(for: episode) ?? episode.audioURL)
            player.replaceCurrentItem(with: item)
            let time = CMTime(seconds: episode.playedPosition, preferredTimescale: 600)
            player.seek(to: time)
            isPlaying = false
        } else {
            isPlaying = false
        }
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
            persistPlaybackProgress(force: true)
        } else {
            player.play()
            player.rate = playbackRate
        }
        isPlaying.toggle()
        updateNowPlayingPlaybackRate()
        startOrUpdateLiveActivity(force: true)
    }

    func seek(by seconds: Double) {
        let time = min(max(0, currentTime + seconds), max(duration - 0.5, 0))
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        currentTime = time
        persistPlaybackProgress(force: true)
        recordPlaybackEvent(
            kind: seconds >= 0 ? .seekedForward : .seekedBackward,
            episode: currentEpisode,
            position: currentTime
        )
    }

    func seek(to seconds: Double) {
        let delta = seconds - currentTime
        let time = max(0, seconds)
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        currentTime = time
        persistPlaybackProgress(force: true)
        if abs(delta) >= 5 {
            recordPlaybackEvent(
                kind: delta >= 0 ? .seekedForward : .seekedBackward,
                episode: currentEpisode,
                position: currentTime
            )
        }
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        UserDefaults.standard.set(rate, forKey: "offscript.playbackRate")
        if isPlaying {
            player.rate = rate
        }
        updateNowPlayingPlaybackRate()
    }

    func setSleepTimer(minutes: Int) {
        sleepTimerTask?.cancel()
        // Always restore volume to 1.0 in case a prior fade left it low.
        self.player.volume = 1.0
        let totalSeconds = TimeInterval(minutes * 60)
        let endDate = Date().addingTimeInterval(totalSeconds)
        sleepTimerEndDate = endDate

        // Fade out the audio over the final stretch so it doesn't feel like a
        // cliff. Window scales with timer length: 8s for short timers, 25s for
        // long ones.
        let fadeWindow: TimeInterval = min(25, max(6, totalSeconds * 0.10))
        let fadeStartOffset = max(0, totalSeconds - fadeWindow)

        sleepTimerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(fadeStartOffset))
            guard !Task.isCancelled else { return }

            // Drive the fade in 0.5s ticks.
            let steps = Int(fadeWindow / 0.5)
            for step in 0..<steps {
                guard !Task.isCancelled else { return }
                let progress = Double(step + 1) / Double(steps)
                let volume = Float(max(0.0, 1.0 - progress))
                self.player.volume = volume
                try? await Task.sleep(for: .milliseconds(500))
            }

            guard !Task.isCancelled else { return }
            self.player.pause()
            self.isPlaying = false
            self.sleepTimerEndDate = nil
            self.persistPlaybackProgress(force: true)
            self.updateNowPlayingPlaybackRate()
            // Restore volume so the next play doesn't start silent.
            self.player.volume = 1.0
        }
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerEndDate = nil
        // Snap volume back in case we cancel mid-fade.
        self.player.volume = 1.0
    }

    func extendSleepTimer(byMinutes additional: Int) {
        guard let current = sleepTimerEndDate else {
            setSleepTimer(minutes: additional)
            return
        }
        let remaining = max(0, current.timeIntervalSinceNow)
        let totalMinutes = Int((remaining + TimeInterval(additional * 60)) / 60)
        setSleepTimer(minutes: max(1, totalMinutes))
    }

    func skipToNextInQueue() {
        guard let context = modelContext else { return }
        guard let nextEpisode = try? QueueService.popNextEpisode(in: context) else { return }
        play(nextEpisode, in: context, origin: .queue)
    }

    func completeCurrentEpisode(markFromPosition position: TimeInterval? = nil, shouldAutoAdvance: Bool = true) {
        guard !isFinishingCurrentEpisode, let episode = currentEpisode else { return }
        isFinishingCurrentEpisode = true
        defer { isFinishingCurrentEpisode = false }

        episode.isPlayed = true
        episode.playedPosition = position ?? max(duration, currentTime)
        currentTime = episode.playedPosition
        duration = max(duration, episode.playedPosition)
        recordPlaybackEvent(kind: .completed, episode: episode, position: currentTime)
        UserDefaults.standard.removeObject(forKey: "offscript.lastEpisodeAudioURL")
        try? modelContext?.save()
        TelemetryService.track(
            "episode_completed",
            metadata: ["episode": episode.title, "podcast": episode.podcast.title],
            in: modelContext
        )

        if shouldAutoAdvance && AppSettings.autoPlayNext {
            skipToNextInQueue()
        } else {
            updateNowPlaying(episode: episode)
            NowPlayingActivityCoordinator.shared.end()
        }
    }

    #if DEBUG
    func debugPrimePlayback(
        episode: Episode,
        duration: TimeInterval,
        currentTime: TimeInterval,
        isPlaying: Bool,
        presentPlayer: Bool
    ) {
        currentEpisode = episode
        self.duration = max(duration, 1)
        self.currentTime = min(max(currentTime, 0), self.duration)
        self.isPlaying = isPlaying
        isPlayerPresented = presentPlayer
        updateNowPlaying(episode: episode)
        startOrUpdateLiveActivity(force: true)
    }
    #endif

    private func observeTime() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                currentTime = time.seconds
                if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite {
                    duration = itemDuration
                }

                persistPlaybackProgress()
                startOrUpdateLiveActivity()
            }
        }
    }

    private func startOrUpdateLiveActivity(force: Bool = false) {
        guard let episode = currentEpisode else {
            NowPlayingActivityCoordinator.shared.end()
            SharedNowPlayingState.write(nil)
            return
        }
        let coordinator = NowPlayingActivityCoordinator.shared
        coordinator.start(
            episodeID: episode.id.uuidString,
            episodeTitle: episode.title,
            podcastTitle: episode.podcast.title,
            artworkURL: episode.artworkURL ?? episode.podcast.artworkURL,
            elapsed: currentTime,
            duration: max(duration, 1),
            isPlaying: isPlaying,
            playbackRate: Double(playbackRate)
        )
        coordinator.update(
            elapsed: currentTime,
            duration: max(duration, 1),
            isPlaying: isPlaying,
            playbackRate: Double(playbackRate),
            force: force
        )

        // Mirror state into the shared App Group so the home-screen widget
        // can render real Now Playing data. Throttle to avoid widget reload spam.
        if force || shouldEmitSharedSnapshot {
            let snapshot = SharedNowPlayingState.Snapshot(
                episodeID: episode.id.uuidString,
                episodeTitle: episode.title,
                podcastTitle: episode.podcast.title,
                artworkURLString: (episode.artworkURL ?? episode.podcast.artworkURL)?.absoluteString,
                elapsed: currentTime,
                duration: max(duration, 1),
                isPlaying: isPlaying,
                playbackRate: Double(playbackRate)
            )
            SharedNowPlayingState.write(snapshot)
            lastSharedSnapshotAt = .now
        }
    }

    private var lastSharedSnapshotAt: Date = .distantPast
    /// Throttle widget reloads to once every 30s while playing — the home
    /// screen widget projects elapsed time forward client-side, so finer
    /// granularity isn't worth the WidgetKit reload cost.
    private var shouldEmitSharedSnapshot: Bool {
        Date().timeIntervalSince(lastSharedSnapshotAt) > 30
    }

    private func observePlaybackCompletion() {
        completionObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.completeCurrentEpisode()
            }
        }
    }

    private func observeSystemAudioEvents() {
        #if os(iOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleInterruption(typeValue: typeValue, optionValue: optionValue)
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleRouteChange(reasonValue: reasonValue)
            }
        }

        mediaServicesResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.configureAudioSession()
                if self?.isPlaying == true {
                    self?.player.play()
                    self?.player.rate = self?.playbackRate ?? 1.0
                }
            }
        }
        #endif
    }

    private func persistPlaybackProgress(force: Bool = false) {
        guard let episode = currentEpisode else { return }

        let shouldPersist = force
            || lastPersistedEpisodeID != episode.id
            || abs(currentTime - lastPersistedPosition) >= 15
            || currentTime == 0

        // Only write model properties and hit SQLite when we actually need to persist,
        // avoiding per-second @Query notifications across the app.
        if shouldPersist {
            episode.playedPosition = currentTime
            episode.lastPlayedAt = .now

            if duration > 0, currentTime >= duration * 0.9 {
                episode.isPlayed = true
            }

            try? modelContext?.save()
            lastPersistedEpisodeID = episode.id
            lastPersistedPosition = currentTime
        }
        updateNowPlaying(episode: episode)
    }

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        try? session.setActive(true)
        #endif
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.player.play()
                self.player.rate = self.playbackRate
                self.isPlaying = true
                self.updateNowPlayingPlaybackRate()
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.player.pause()
                self.isPlaying = false
                self.updateNowPlayingPlaybackRate()
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.togglePlayPause()
            }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.seek(by: 30)
            }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.seek(by: -15)
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skipToNextInQueue()
            }
            return .success
        }
    }

    private func updateNowPlaying(episode: Episode) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPMediaItemPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0
        ]
        info[MPMediaItemPropertyPodcastTitle] = episode.podcast.title
        info[MPMediaItemPropertyArtist] = episode.podcast.author ?? episode.podcast.title
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateNowPlayingArtwork(for: episode)
    }

    private func updateNowPlayingArtwork(for episode: Episode) {
        guard let url = episode.artworkURL ?? episode.podcast.artworkURL else { return }

        Task.detached(priority: .utility) {
            let data: Data?
            if url.isFileURL {
                data = try? Data(contentsOf: url)
            } else {
                data = try? await URLSession.shared.data(from: url).0
            }

            guard let data, let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }

            await MainActor.run {
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
            }
        }
    }

    private func updateNowPlayingPlaybackRate() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    }

    private func recordPlaybackEvent(kind: PlaybackEvent.Kind, episode: Episode?, position: TimeInterval) {
        guard let episode, let modelContext else { return }
        let event = PlaybackEvent(kind: kind, position: position, episode: episode)
        modelContext.insert(event)
        // Save is debounced — every event used to do a synchronous SQLite
        // write + a TasteProfile recompute, which stalled the UI on long
        // sessions. We coalesce within 750ms windows.
        scheduleDebouncedEventFlush()
        TelemetryService.track(
            "playback_event",
            metadata: [
                "kind": kind.rawValue,
                "episode": episode.title,
                "podcast": episode.podcast.title
            ],
            in: modelContext
        )
    }

    private var pendingEventFlushTask: Task<Void, Never>?

    private func scheduleDebouncedEventFlush() {
        pendingEventFlushTask?.cancel()
        let context = modelContext
        pendingEventFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled, let self, let context else { return }
            try? context.save()
            // TasteProfile.refresh internally throttles to once per 90s, but
            // even that's too eager during active playback — flushes happen
            // at most every ~750ms here, and the inner refresh skips if it
            // ran recently.
            try? TasteProfileService.refresh(in: context)
            self.pendingEventFlushTask = nil
        }
    }

    private func recordExitEventIfNeeded(replacingWith nextEpisode: Episode) {
        guard let episode = currentEpisode, episode.id != nextEpisode.id else { return }
        guard !episode.isPlayed else { return }

        let listenedThreshold = min(max(duration * 0.15, 30), 300)
        let kind: PlaybackEvent.Kind = currentTime < listenedThreshold ? .skippedQuickly : .abandoned
        recordPlaybackEvent(kind: kind, episode: episode, position: currentTime)
    }

    private func handleInterruption(typeValue: UInt?, optionValue: UInt?) {
        guard let typeValue,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            player.pause()
            isPlaying = false
            persistPlaybackProgress(force: true)
            updateNowPlayingPlaybackRate()
        case .ended:
            if let optionValue,
               AVAudioSession.InterruptionOptions(rawValue: optionValue).contains(.shouldResume) {
                player.play()
                player.rate = playbackRate
                isPlaying = true
                updateNowPlayingPlaybackRate()
            }
        @unknown default:
            break
        }
    }

    private func restoreLastSessionIfNeeded(context: ModelContext) {
        guard currentEpisode == nil else { return }
        guard let savedURL = UserDefaults.standard.string(forKey: "offscript.lastEpisodeAudioURL"),
              let audioURL = URL(string: savedURL) else { return }

        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.audioURL == audioURL }
        )
        descriptor.fetchLimit = 1
        guard let episode = try? context.fetch(descriptor).first else { return }

        // Restore episode in MiniPlayer without auto-playing
        currentEpisode = episode
        currentTime = episode.playedPosition
        duration = episode.duration ?? 0
        isPlaying = false
        updateNowPlaying(episode: episode)
    }

    private func handleRouteChange(reasonValue: UInt?) {
        guard let reasonValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            player.pause()
            isPlaying = false
            persistPlaybackProgress(force: true)
            updateNowPlayingPlaybackRate()
        case .newDeviceAvailable:
            if currentEpisode != nil, isPlaying {
                player.play()
                player.rate = playbackRate
            }
        default:
            break
        }
    }
}

private extension Float {
    func nonZeroOrDefault(_ defaultValue: Float) -> Float {
        self == 0 ? defaultValue : self
    }
}

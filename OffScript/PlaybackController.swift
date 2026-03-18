import AVFoundation
import Combine
import MediaPlayer
import SwiftData
import SwiftUI
import UIKit

@MainActor
final class PlaybackController: ObservableObject {
    enum StartOrigin {
        case manual
        case queue
    }

    static let shared = PlaybackController()

    @Published private(set) var currentEpisode: Episode?
    @Published private(set) var isPlaying = false
    @Published var playbackRate: Float = 1.0
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var isPlayerPresented = false
    @Published private(set) var sleepTimerEndDate: Date?

    private let player = AVPlayer()
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
    }

    func play(_ episode: Episode, in context: ModelContext? = nil, origin: StartOrigin = .manual) {
        if let context {
            configure(context: context)
        }

        recordExitEventIfNeeded(replacingWith: episode)

        currentEpisode = episode
        let playableURL = DownloadService.shared.localURL(for: episode) ?? episode.audioURL
        let item = AVPlayerItem(url: playableURL)
        player.replaceCurrentItem(with: item)

        let savedPosition = episode.playedPosition

        if savedPosition > 0 {
            let time = CMTime(seconds: savedPosition, preferredTimescale: 600)
            player.seek(to: time)
            currentTime = savedPosition
        } else {
            currentTime = 0
        }
        lastPersistedEpisodeID = episode.id
        lastPersistedPosition = currentTime

        player.play()
        player.rate = playbackRate
        isPlaying = true
        isPlayerPresented = true
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
        if isPlaying {
            player.rate = rate
        }
        updateNowPlayingPlaybackRate()
    }

    func setSleepTimer(minutes: Int) {
        sleepTimerTask?.cancel()
        let endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerEndDate = endDate
        sleepTimerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(TimeInterval(minutes * 60)))
            guard !Task.isCancelled else { return }
            self.player.pause()
            self.isPlaying = false
            self.sleepTimerEndDate = nil
            self.persistPlaybackProgress(force: true)
            self.updateNowPlayingPlaybackRate()
        }
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerEndDate = nil
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
            }
        }
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
            Task { @MainActor [weak self] in
                self?.handleInterruption(notification)
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleRouteChange(notification)
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
        episode.playedPosition = currentTime
        episode.lastPlayedAt = .now

        if duration > 0, currentTime >= duration * 0.9 {
            episode.isPlayed = true
        }

        let shouldPersist = force
            || lastPersistedEpisodeID != episode.id
            || abs(currentTime - lastPersistedPosition) >= 15
            || currentTime == 0
            || episode.isPlayed

        if shouldPersist {
            try? modelContext?.save()
            lastPersistedEpisodeID = episode.id
            lastPersistedPosition = currentTime
        }
        updateNowPlaying(episode: episode)
    }

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio, options: [.allowAirPlay])
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
        try? modelContext.save()
        try? TasteProfileService.refresh(in: modelContext)
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

    private func recordExitEventIfNeeded(replacingWith nextEpisode: Episode) {
        guard let episode = currentEpisode, episode.id != nextEpisode.id else { return }
        guard !episode.isPlayed else { return }

        let listenedThreshold = min(max(duration * 0.15, 30), 300)
        let kind: PlaybackEvent.Kind = currentTime < listenedThreshold ? .skippedQuickly : .abandoned
        recordPlaybackEvent(kind: kind, episode: episode, position: currentTime)
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
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
            if let optionValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
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

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
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

import AVFoundation
import Combine
import MediaPlayer
import OSLog
import SwiftData
import SwiftUI

@MainActor
final class PlaybackController: ObservableObject {
    static let shared = PlaybackController()
    private let logger = Logger(subsystem: "com.offscript", category: "Playback")

    @Published private(set) var currentEpisode: Episode?
    @Published private(set) var isPlaying = false
    @Published var playbackRate: Float = 1.0
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var isPlayerPresented = false

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var completionObserver: Any?
    private var modelContext: ModelContext?

    private init() {
        configureAudioSession()
        observeTime()
        observePlaybackCompletion()
        configureRemoteCommands()
    }

    func configure(context: ModelContext) {
        modelContext = context
    }

    /// True once `configure(context:)` has been called. App Intents running
    /// in-process should check this before supplying a new context so they
    /// don't replace the live app context with an intent-scoped one.
    var isModelContextConfigured: Bool { modelContext != nil }

    func play(_ episode: Episode, in context: ModelContext? = nil) {
        prepareItem(for: episode, in: context)

        // Re-activate the audio session immediately before starting playback.
        // The init-time activation can fail silently (no audio queued yet, or
        // another app holds focus); without re-activating here, the session
        // never enters .playback, and iOS silences us on background. Calling
        // setActive(true) right before player.play() is the supported pattern
        // for AVPlayer-backed apps.
        activateAudioSession()
        player.play()
        player.rate = playbackRate
        isPlaying = true
    }

    /// Load an episode into the player WITHOUT starting playback. Used by
    /// `DeepLinkRouter` for the "open the player but don't auto-play" path —
    /// e.g. tapping a Spotlight result, where the user may just want to look
    /// at the episode before deciding to play.
    func load(_ episode: Episode, in context: ModelContext? = nil) {
        prepareItem(for: episode, in: context)
        isPlaying = false
    }

    /// Shared setup for `play()` and `load()`: configures context, installs
    /// the AVPlayerItem, restores saved position, and opens the player UI.
    private func prepareItem(for episode: Episode, in context: ModelContext?) {
        if let context {
            configure(context: context)
        }

        currentEpisode = episode
        let url = episode.localFileURL ?? episode.audioURL
        player.replaceCurrentItem(with: AVPlayerItem(url: url))

        let savedPosition = episode.playedPosition
        if savedPosition > 0 {
            player.seek(to: CMTime(seconds: savedPosition, preferredTimescale: 600))
            currentTime = savedPosition
        } else {
            currentTime = 0
        }

        isPlayerPresented = true
        updateNowPlaying(episode: episode)
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            // Same reason as play() — the session can be inactive when we
            // resume from pause (especially after a long background pause
            // or after another app interrupted us).
            activateAudioSession()
            player.play()
            player.rate = playbackRate
        }
        isPlaying.toggle()
        updateNowPlayingPlaybackRate()
    }

    func seek(by seconds: Double) {
        let time = max(0, currentTime + seconds)
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime)
        currentTime = time
        persistPlaybackProgress()
    }

    func seek(to seconds: Double) {
        let time = max(0, seconds)
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        currentTime = time
        persistPlaybackProgress()
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player.rate = rate
        }
    }

    func skipToNextInQueue() {
        guard let context = modelContext else { return }
        let nextEpisode: Episode?
        do {
            nextEpisode = try QueueService.popNextEpisode(in: context)
        } catch {
            logger.error("Failed to pop next episode from queue: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let nextEpisode else { return }
        play(nextEpisode, in: context)
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

    private func persistPlaybackProgress() {
        guard let episode = currentEpisode else { return }
        episode.playedPosition = currentTime
        episode.lastPlayedAt = .now

        if duration > 0, currentTime >= duration * 0.9 {
            episode.isPlayed = true
        }

        if let context = modelContext {
            do { try context.save() } catch { logger.error("Failed to save playback progress: \(error.localizedDescription, privacy: .public)") }
        }
        updateNowPlaying(episode: episode)
    }

    private func observePlaybackCompletion() {
        completionObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let episode = self.currentEpisode else { return }
                episode.isPlayed = true
                episode.playedPosition = self.duration
                if let context = self.modelContext {
                    let event = PlaybackEvent(kind: .completed, position: self.duration, episode: episode)
                    context.insert(event)
                    do { try context.save() } catch { self.logger.error("Failed to save playback completion event: \(error.localizedDescription, privacy: .public)") }
                }
                if UserDefaults.standard.object(forKey: "offscript.autoPlayNext") as? Bool ?? true {
                    self.skipToNextInQueue()
                }
            }
        }
    }

    /// Set the AVAudioSession category at app launch. Splitting category-set
    /// from session-activation lets us call activateAudioSession() right
    /// before each player.play() without re-setting the category every time.
    /// Errors are logged via OSLog instead of swallowed by `try?` — silent
    /// failure here is the difference between background audio working and
    /// the app going mute the moment the user backgrounds.
    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback + .spokenAudio + .longFormAudio is the supported combo
            // for podcast apps that need lock-screen controls and background
            // audio. .longFormAudio prevents iOS from quietly switching us
            // into a duck-other-audio category.
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio, options: [.allowAirPlay, .allowBluetoothA2DP])
        } catch {
            logger.error("AVAudioSession setCategory failed: \(error.localizedDescription, privacy: .public)")
        }
        // First activation attempt — may fail at app launch if no audio is
        // queued; activateAudioSession() retries on every play() / resume.
        activateAudioSession()
        #endif
    }

    /// Activate the audio session right before starting playback. Idempotent —
    /// safe to call repeatedly. This is the call that actually grabs audio
    /// focus from iOS and enables background playback. Without this on every
    /// resume/play, the session can sit inactive and iOS silences the app on
    /// background.
    private func activateAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true, options: [])
        } catch {
            logger.error("AVAudioSession setActive(true) failed: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.player.play()
            self?.isPlaying = true
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.player.pause()
            self?.isPlaying = false
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.seek(by: 30)
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.seek(by: -15)
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.skipToNextInQueue()
            return .success
        }
    }

    private func updateNowPlaying(episode: Episode) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        info[MPMediaItemPropertyPodcastTitle] = episode.podcast.title
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlaybackRate() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    }
}

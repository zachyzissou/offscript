import AVFoundation
import Combine
import MediaPlayer
import OSLog
import SwiftData
import SwiftUI
import UIKit

#if os(iOS)
protocol OffScriptAudioSessionApplying {
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, policy: AVAudioSession.RouteSharingPolicy, options: AVAudioSession.CategoryOptions) throws
}

extension AVAudioSession: OffScriptAudioSessionApplying {}

enum OffScriptAudioSessionConfiguration {
    static let category: AVAudioSession.Category = .playback
    static let mode: AVAudioSession.Mode = .spokenAudio
    static let options: AVAudioSession.CategoryOptions = [.allowAirPlay, .allowBluetoothA2DP]

    static func apply(to session: OffScriptAudioSessionApplying) throws {
        try session.setCategory(category, mode: mode, options: options)
    }
}
#endif

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

    /// Set when an AVPlayerItem fails to load (404, codec, network drop)
    /// or stalls. PlayerView and MiniPlayer read this to render an inline
    /// error chip; ContentView could surface a global toast. Cleared on
    /// the next successful load.
    @Published private(set) var playbackError: String?

    private var itemStatusObservation: NSKeyValueObservation?
    private var itemFailureObserver: NSObjectProtocol?
    private var itemStallObserver: NSObjectProtocol?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var completionObserver: Any?
    private var modelContext: ModelContext?
    private var lastProgressSaveTime: TimeInterval = 0
    private var lastProgressSaveDate: Date = .distantPast
    private var nowPlayingArtworkURL: URL?
    private var nowPlayingArtworkTask: Task<Void, Never>?

    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var mediaServicesResetObserver: NSObjectProtocol?

    /// When non-nil, playback will pause at this date. Drives the PlayerView
    /// SLEEP key label (countdown). Cleared when the timer fires or is
    /// cancelled — UI binds to it as the source of truth.
    @Published private(set) var sleepTimerEndDate: Date?
    private var sleepTimerTask: Task<Void, Never>?

    private init() {
        configureAudioSession()
        observeTime()
        observePlaybackCompletion()
        observeSystemAudioEvents()
        configureRemoteCommands()
    }

    deinit {
        if let obs = interruptionObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = routeChangeObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = mediaServicesResetObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = itemFailureObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = itemStallObserver { NotificationCenter.default.removeObserver(obs) }
        itemStatusObservation?.invalidate()
        sleepTimerTask?.cancel()
        nowPlayingArtworkTask?.cancel()
    }

    /// Wire KVO + notifications on a fresh AVPlayerItem so we can tell
    /// "load failed" from "stalled" from "ready". Without this, a 404
    /// audio URL leaves the UI in a permanent "playing" state with no
    /// audio and no signal that anything went wrong — exactly the
    /// "tapped play, nothing happens" symptom we used to ship.
    private func observeItem(_ item: AVPlayerItem) {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        if let observer = itemFailureObserver {
            NotificationCenter.default.removeObserver(observer)
            itemFailureObserver = nil
        }
        if let observer = itemStallObserver {
            NotificationCenter.default.removeObserver(observer)
            itemStallObserver = nil
        }

        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .failed:
                    let message = item.error?.localizedDescription ?? "Couldn't play this episode."
                    self.handlePlaybackFailure(message: message)
                case .readyToPlay:
                    self.playbackError = nil
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        itemFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            let message = error?.localizedDescription ?? "Playback stopped unexpectedly."
            Task { @MainActor [weak self] in
                self?.handlePlaybackFailure(message: message)
            }
        }

        itemStallObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Stall isn't fatal — surface a buffering note so the user
                // knows the buffer ran dry. Clears on next readyToPlay.
                self?.playbackError = "Buffering — check your connection."
            }
        }
    }

    private func handlePlaybackFailure(message: String) {
        logger.error("Playback failed: \(message, privacy: .public)")
        player.pause()
        isPlaying = false
        playbackError = message
        updateNowPlayingPlaybackRate()
    }

    func clearPlaybackError() {
        playbackError = nil
    }

    // MARK: - Sleep timer

    /// Schedule playback to pause at `endDate`. Cancels any existing
    /// timer first so back-to-back menu picks reset cleanly.
    ///
    /// Implementation note: uses a periodic Task that wakes every second
    /// and checks against wallclock — not `Task.sleep(for: minutes)`. The
    /// original sleep-once approach died when the app backgrounded
    /// because Task suspends while the app is suspended. By driving the
    /// fire decision off a wallclock comparison, the timer fires the
    /// moment the user foregrounds again — even if the original deadline
    /// passed during the suspension window.
    func setSleepTimer(minutes: Int) {
        cancelSleepTimer()
        let endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerEndDate = endDate
        sleepTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.sleepTimerEndDate == endDate else { return }
                if Date() >= endDate {
                    self.player.pause()
                    self.isPlaying = false
                    self.sleepTimerEndDate = nil
                    self.updateNowPlayingPlaybackRate()
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerEndDate = nil
    }

    /// Force a sleep-timer evaluation. Call from the scene-active
    /// notification so a timer that should have fired during background
    /// suspension fires immediately on foreground.
    func reevaluateSleepTimerOnForeground() {
        guard let endDate = sleepTimerEndDate, Date() >= endDate else { return }
        sleepTimerTask?.cancel()
        player.pause()
        isPlaying = false
        sleepTimerEndDate = nil
        updateNowPlayingPlaybackRate()
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
    /// the AVPlayerItem, restores saved position, applies the episode's
    /// per-podcast playback rate, and opens the player UI.
    private func prepareItem(for episode: Episode, in context: ModelContext?) {
        if let context {
            configure(context: context)
        }

        currentEpisode = episode
        lastProgressSaveTime = episode.playedPosition
        lastProgressSaveDate = .distantPast
        nowPlayingArtworkURL = nil
        nowPlayingArtworkTask?.cancel()
        // Resolve the rate this podcast should play at — per-podcast
        // preference wins, then the global default, then 1.0×. Each podcast
        // remembers its own pace.
        playbackRate = PodcastPlaybackPreferences.preferredRate(for: episode.podcast)
            ?? PodcastPlaybackPreferences.globalDefault
        let url = episode.localFileURL ?? episode.audioURL
        let item = AVPlayerItem(url: url)
        observeItem(item)
        playbackError = nil
        player.replaceCurrentItem(with: item)

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

    /// Hard pause — stops playback regardless of current state. Used by
    /// services that need to take the player offline (e.g. unsubscribe
    /// flow before deleting the currently-playing file). Doesn't touch
    /// `currentEpisode` so the UI keeps the strip visible; caller can
    /// clear that explicitly if needed.
    func pause() {
        guard isPlaying else { return }
        player.pause()
        isPlaying = false
        updateNowPlayingPlaybackRate()
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
        persistPlaybackProgress(force: true)
    }

    func seek(to seconds: Double) {
        let time = max(0, seconds)
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        currentTime = time
        persistPlaybackProgress(force: true)
    }

    /// Set the rate for the currently playing podcast and persist it as
    /// the default for that podcast going forward. Per-podcast preferences
    /// store in UserDefaults keyed by podcast UUID — avoids a SwiftData
    /// schema migration for what's a UI preference, not a content fact.
    /// When no episode is loaded, falls back to setting the global default.
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if let podcast = currentEpisode?.podcast {
            PodcastPlaybackPreferences.setPreferredRate(rate, for: podcast)
        } else {
            PodcastPlaybackPreferences.setGlobalDefault(rate)
        }
        if isPlaying {
            player.rate = rate
        }
        updateNowPlayingPlaybackRate()
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
                persistPlaybackProgressIfNeeded()
                updateNowPlayingElapsed()
            }
        }
    }

    private func persistPlaybackProgress(force: Bool = false) {
        guard let episode = currentEpisode else { return }
        episode.playedPosition = currentTime
        episode.lastPlayedAt = .now

        if duration > 0, currentTime >= duration * 0.9 {
            episode.isPlayed = true
        }

        if let context = modelContext {
            do { try context.save() } catch { logger.error("Failed to save playback progress: \(error.localizedDescription, privacy: .public)") }
        }
        lastProgressSaveTime = currentTime
        lastProgressSaveDate = .now
        if force {
            updateNowPlaying(episode: episode)
        }
    }

    private func persistPlaybackProgressIfNeeded() {
        let crossedPlayedThreshold = duration > 0
            && currentTime >= duration * 0.9
            && currentEpisode?.isPlayed == false
        let movedEnough = abs(currentTime - lastProgressSaveTime) >= 15
        let waitedEnough = Date().timeIntervalSince(lastProgressSaveDate) >= 30

        guard crossedPlayedThreshold || movedEnough || waitedEnough else { return }
        persistPlaybackProgress()
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
            // .playback is what makes podcast audio ignore Silent Mode and
            // continue under lock/background when UIBackgroundModes includes
            // audio. Do not pass .longFormAudio here: iOS rejects that route
            // sharing policy when paired with our AirPlay/Bluetooth options,
            // leaving the app on the default Silent-Mode-bound category.
            try OffScriptAudioSessionConfiguration.apply(to: session)
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

    /// Listen for interruptions (phone calls, Siri), route changes (headphones
    /// unplugged), and media services resets. Without these handlers, a phone
    /// call ends playback permanently and unplugging headphones lets audio
    /// blast out of the speaker — both well-known podcast-app failure modes.
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
                guard let self else { return }
                self.logger.warning("Audio media services were reset; reconfiguring session.")
                self.configureAudioSession()
                if self.isPlaying {
                    self.player.play()
                    self.player.rate = self.playbackRate
                }
            }
        }
        #endif
    }

    private func handleInterruption(typeValue: UInt?, optionValue: UInt?) {
        guard let typeValue,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // Phone call / Siri began — pause and let iOS take focus.
            player.pause()
            isPlaying = false
            updateNowPlayingPlaybackRate()
        case .ended:
            // Resume only if the system says we should (user dismissed Siri,
            // call ended without other audio taking over).
            if let optionValue,
               AVAudioSession.InterruptionOptions(rawValue: optionValue).contains(.shouldResume) {
                activateAudioSession()
                player.play()
                player.rate = playbackRate
                isPlaying = true
                updateNowPlayingPlaybackRate()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonValue: UInt?) {
        guard let reasonValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        // Pause when headphones / bluetooth disconnect — same behavior the
        // music app uses. Anything else is fine to keep playing through.
        if reason == .oldDeviceUnavailable {
            player.pause()
            isPlaying = false
            updateNowPlayingPlaybackRate()
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            // Re-activate the session before resuming from a remote command.
            // Same reason as togglePlayPause(): the session can be inactive
            // when iOS routes us via lock-screen / CarPlay / control center.
            self?.activateAudioSession()
            self?.player.play()
            self?.player.rate = self?.playbackRate ?? 1.0
            self?.isPlaying = true
            self?.updateNowPlayingPlaybackRate()
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
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0
        ]
        info[MPMediaItemPropertyPodcastTitle] = episode.podcast.title
        info[MPMediaItemPropertyArtist] = episode.podcast.author ?? episode.podcast.title
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateNowPlayingArtwork(for: episode)
    }

    /// Fetch the episode artwork off-main and hand it to the Now Playing
    /// info center. Without this the lock screen and Control Center show
    /// title + podcast but no image — looked broken next to Apple Podcasts.
    /// Local file URLs read synchronously off the file system; remote URLs
    /// hit the network on a utility-priority detached task.
    private func updateNowPlayingArtwork(for episode: Episode) {
        guard let url = episode.artworkURL ?? episode.podcast.artworkURL else { return }
        guard nowPlayingArtworkURL != url else { return }
        nowPlayingArtworkURL = url
        nowPlayingArtworkTask?.cancel()
        nowPlayingArtworkTask = Task.detached(priority: .utility) {
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

    private func updateNowPlayingElapsed() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] = duration
    }

    private func updateNowPlayingPlaybackRate() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    }
}

import AVFoundation
import Combine
import MediaPlayer
import SwiftData
import SwiftUI

@MainActor
final class PlaybackController: ObservableObject {
    static let shared = PlaybackController()

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

    func play(_ episode: Episode, in context: ModelContext? = nil) {
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

        player.play()
        player.rate = playbackRate
        isPlaying = true
        isPlayerPresented = true
        updateNowPlaying(episode: episode)
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
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
        guard let nextEpisode = try? QueueService.popNextEpisode(in: context) else { return }
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
            try? context.save()
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
                    try? context.save()
                }
                if UserDefaults.standard.object(forKey: "offscript.autoPlayNext") as? Bool ?? true {
                    self.skipToNextInQueue()
                }
            }
        }
    }

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio, options: [.allowAirPlay, .allowBluetoothHFP])
        try? session.setActive(true)
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

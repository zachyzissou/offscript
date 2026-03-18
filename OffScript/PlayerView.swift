import AVKit
import SwiftData
import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var player = PlaybackController.shared
    @Query private var queueItems: [QueueItem]

    private var orderedQueueItems: [QueueItem] {
        queueItems.sorted { lhs, rhs in
            if lhs.position == rhs.position {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.position < rhs.position
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let episode = player.currentEpisode {
                    GeometryReader { proxy in
                        let artworkSize = min(max(proxy.size.width - 168, 196), 272)
                        let nextItem = orderedQueueItems.first
                        let chapters = episode.resolvedChapters
                        let transcripts = episode.transcriptReferences
                        let downloadStatus = DownloadService.shared.statusText(for: episode)
                        let isOfflineReady = DownloadService.shared.localURL(for: episode) != nil

                        ScrollView {
                            VStack(spacing: 18) {
                                OffScriptArtworkView(
                                    url: episode.artworkURL ?? episode.podcast.artworkURL,
                                    cornerRadius: OffScriptTheme.Radius.large
                                )
                                .frame(width: artworkSize, height: artworkSize)

                                VStack(spacing: 8) {
                                    Text(episode.title)
                                        .font(.offscriptDisplay)
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(Color.offscriptTextPrimary)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text(episode.podcast.title)
                                        .font(.headline)
                                        .foregroundStyle(Color.offscriptTextSecondary)

                                    HStack(spacing: 10) {
                                        OffScriptReasonBadge(text: player.currentTime > 0 ? "In session" : "Now playing")
                                        if let duration = episode.duration {
                                            OffScriptReasonBadge(text: EpisodeDurationFormatter.short(duration))
                                        }
                                        OffScriptReasonBadge(text: isOfflineReady ? "Offline ready" : "Streaming")
                                        if !transcripts.isEmpty {
                                            OffScriptReasonBadge(text: "Transcript")
                                        }
                                        if let sleepTimerEndDate = player.sleepTimerEndDate {
                                            OffScriptReasonBadge(text: "Sleep \(sleepTimerEndDate.formatted(date: .omitted, time: .shortened))")
                                        }
                                    }

                                    if let downloadStatus {
                                        Text(downloadStatus)
                                            .font(.offscriptMeta)
                                            .foregroundStyle(Color.offscriptTextMuted)
                                            .multilineTextAlignment(.center)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 16) {
                                    Slider(
                                        value: Binding(
                                            get: { player.currentTime },
                                            set: { player.seek(to: $0) }
                                        ),
                                        in: 0...max(player.duration, 1)
                                    )
                                    .tint(Color.offscriptAccent)

                                    HStack {
                                        Text(time(player.currentTime))
                                        Spacer()
                                        Text(remainingTime)
                                    }
                                    .font(.offscriptMeta.monospacedDigit())
                                    .foregroundStyle(Color.offscriptTextMuted)

                                }
                                .padding(20)
                                .offscriptSurface()
                                .frame(maxWidth: 440)

                                HStack(spacing: 18) {
                                    PlayerCircleButton(systemImage: "gobackward.15", accessibilityLabel: "Skip back 15 seconds", isPrimary: false) {
                                        player.seek(by: -15)
                                    }

                                    PlayerCircleButton(
                                        systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                                        accessibilityLabel: player.isPlaying ? "Pause playback" : "Resume playback",
                                        isPrimary: true,
                                        size: 84
                                    ) {
                                        player.togglePlayPause()
                                    }

                                    PlayerCircleButton(systemImage: "goforward.30", accessibilityLabel: "Skip forward 30 seconds", isPrimary: false) {
                                        player.seek(by: 30)
                                    }

                                    PlayerCircleButton(systemImage: "forward.end.fill", accessibilityLabel: "Play next queued episode", isPrimary: false) {
                                        player.skipToNextInQueue()
                                    }
                                }

                                if let nextItem {
                                    PlayerUpNextStrip(item: nextItem)
                                        .frame(maxWidth: 440)
                                }

                                if !chapters.isEmpty {
                                    PlayerChaptersSection(chapters: chapters)
                                        .frame(maxWidth: 440)
                                }

                                if !transcripts.isEmpty {
                                    PlayerTranscriptSection(transcripts: transcripts)
                                        .frame(maxWidth: 440)
                                }

                                PlayerWhatsNextSection(currentEpisode: episode)
                                    .frame(maxWidth: 440)

                                HStack(spacing: 10) {
                                    Menu {
                                        ForEach([("1.0x", Float(1.0)), ("1.25x", Float(1.25)), ("1.5x", Float(1.5)), ("2.0x", Float(2.0))], id: \.0) { label, rate in
                                            Button {
                                                player.setPlaybackRate(rate)
                                            } label: {
                                                HStack {
                                                    Text(label)
                                                    if player.playbackRate == rate {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                    } label: {
                                        Label(String(format: "%.2gx", player.playbackRate), systemImage: "speedometer")
                                    }
                                    .buttonStyle(SecondaryPillButtonStyle())
                                    .accessibilityLabel("Playback speed, currently \(String(format: "%.2gx", player.playbackRate))")
                                    .accessibilityHint("Opens menu to change playback speed")

                                    Menu {
                                        Button("Play Next") {
                                            try? QueueService.playNext(episode, in: modelContext)
                                        }

                                        Button("Add to End") {
                                            try? QueueService.addToEnd(episode, in: modelContext)
                                        }
                                    } label: {
                                        Label(episode.isQueued ? "Queued" : "Queue", systemImage: "text.badge.plus")
                                    }
                                    .buttonStyle(SecondaryPillButtonStyle())
                                    .disabled(episode.isQueued)
                                    .accessibilityLabel(episode.isQueued ? "Episode already in queue" : "Add to queue")
                                    .accessibilityHint(episode.isQueued ? "" : "Opens menu to add this episode to the queue")

                                    Button("Mark Played") {
                                        player.completeCurrentEpisode(shouldAutoAdvance: false)
                                    }
                                    .buttonStyle(PrimaryPillButtonStyle())
                                    .accessibilityLabel("Mark episode as played")
                                    .accessibilityHint("Marks this episode complete without auto-advancing")
                                }

                                HStack(spacing: 10) {
                                    Menu {
                                        Button("Sleep in 15 min") { player.setSleepTimer(minutes: 15) }
                                        Button("Sleep in 30 min") { player.setSleepTimer(minutes: 30) }
                                        Button("Sleep in 60 min") { player.setSleepTimer(minutes: 60) }
                                        if player.sleepTimerEndDate != nil {
                                            Button("Cancel Sleep Timer", role: .destructive) { player.cancelSleepTimer() }
                                        }
                                    } label: {
                                        Label("Sleep", systemImage: "moon.zzz.fill")
                                    }
                                    .buttonStyle(SecondaryPillButtonStyle())
                                    .accessibilityLabel(player.sleepTimerEndDate != nil ? "Sleep timer active" : "Sleep timer")
                                    .accessibilityHint("Opens menu to set or cancel a sleep timer")

                                    AirPlayRouteButton()
                                        .frame(width: 52, height: 40)
                                        .accessibilityLabel("AirPlay")
                                        .accessibilityHint("Select audio output device")

                                    ShareLink(item: episode.audioURL) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    .buttonStyle(SecondaryPillButtonStyle())
                                    .accessibilityLabel("Share episode")
                                    .accessibilityHint("Opens the share sheet for this episode's audio")

                                    DownloadButton(episode: episode)
                                }

                                Spacer(minLength: 8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 28)
                        }
                    }
                    .background {
                        PlayerAtmosphereBackground(url: episode.artworkURL ?? episode.podcast.artworkURL)
                    }
                } else {
                    ContentUnavailableView("Nothing playing", systemImage: "waveform.slash", description: Text("Start an episode from Home, Library, or Queue."))
                        .offscriptPageBackground()
                }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var remainingTime: String {
        let remaining = max(player.duration - player.currentTime, 0)
        return "-\(time(remaining))"
    }

    private func time(_ interval: TimeInterval) -> String {
        guard interval.isFinite else { return "0:00" }
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

private struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.activeTintColor = UIColor(Color.offscriptAccent)
        view.tintColor = UIColor(Color.offscriptTextPrimary)
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

private struct PlayerCircleButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let systemImage: String
    let accessibilityLabel: String
    let isPrimary: Bool
    var size: CGFloat = 60
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: isPrimary ? 28 : 22, weight: .semibold))
                .foregroundStyle(isPrimary ? Color.black : Color.offscriptTextPrimary)
                .frame(width: size, height: size)
                .background(isPrimary ? Color.offscriptAccent : Color.white.opacity(0.08))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(isPrimary ? Color.clear : Color.offscriptHairline, lineWidth: 1)
                )
                .scaleEffect(reduceMotion ? 1.0 : (isPressed ? 0.9 : 1.0))
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !reduceMotion { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
    }
}

private struct PlayerUpNextStrip: View {
    @ObservedObject private var player = PlaybackController.shared
    let item: QueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                OffScriptArtworkView(
                    url: item.episode.artworkURL ?? item.episode.podcast.artworkURL,
                    cornerRadius: OffScriptTheme.Radius.small
                )
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        OffScriptReasonBadge(text: "Up Next")
                        if let duration = item.episode.duration {
                            Text(EpisodeDurationFormatter.short(duration))
                                .font(.offscriptMeta)
                                .foregroundStyle(Color.offscriptTextMuted)
                        }
                    }

                    Text(item.episode.title)
                        .font(.headline)
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .lineLimit(2)

                    Text(item.episode.podcast.title)
                        .font(.offscriptBody)
                        .foregroundStyle(Color.offscriptTextSecondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Text("Autoplays when this episode ends.")
                    .font(.offscriptMeta)
                    .foregroundStyle(Color.offscriptTextMuted)

                Spacer()

                Button("Play Next Now") {
                    player.skipToNextInQueue()
                }
                .buttonStyle(SecondaryPillButtonStyle())
            }
        }
        .padding(18)
        .offscriptSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Up next: \(item.episode.title) from \(item.episode.podcast.title)")
    }
}

private struct PlayerWhatsNextSection: View {
    @Environment(\.modelContext) private var modelContext
    let currentEpisode: Episode
    @State private var suggestions: [ScoredEpisode] = []

    private let recommendationService = RecommendationService()

    var body: some View {
        Group {
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("What's Next")
                            .font(.offscriptSectionTitle)
                            .foregroundStyle(Color.offscriptTextPrimary)
                        Spacer()
                    }

                    ForEach(suggestions, id: \.episode.id) { scored in
                        PlayerSuggestionRow(scored: scored)
                    }
                }
                .padding(18)
                .offscriptSurface()
            }
        }
        .task(id: currentEpisode.id) { loadSuggestions() }
    }

    @MainActor
    private func loadSuggestions() {
        suggestions = []
        if let results = try? recommendationService.playerSuggestions(
            currentEpisode: currentEpisode,
            context: modelContext,
            limit: 3
        ) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                suggestions = results
            }
        }
    }
}

private struct PlayerSuggestionRow: View {
    @Environment(\.modelContext) private var modelContext
    let scored: ScoredEpisode

    var body: some View {
        HStack(spacing: 12) {
            OffScriptArtworkView(
                url: scored.episode.artworkURL ?? scored.episode.podcast.artworkURL,
                cornerRadius: OffScriptTheme.Radius.small
            )
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                OffScriptExplanationTag(text: scored.explanation)

                Text(scored.episode.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .lineLimit(1)

                Text(scored.episode.podcast.title)
                    .font(.offscriptMeta)
                    .foregroundStyle(Color.offscriptTextMuted)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                TelemetryService.track(
                    "recommendation_opened",
                    metadata: [
                        "source": "player",
                        "episode": scored.episode.title,
                        "podcast": scored.episode.podcast.title
                    ],
                    in: modelContext
                )
                PlaybackController.shared.play(scored.episode, in: modelContext)
            } label: {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(Color.offscriptAccent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(scored.episode.title)")
        }
    }
}

private struct PlayerChaptersSection: View {
    let chapters: [EpisodeChapter]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Chapters")
                .font(.offscriptSectionTitle)
                .foregroundStyle(Color.offscriptTextPrimary)

            VStack(spacing: 10) {
                ForEach(chapters) { chapter in
                    Button {
                        PlaybackController.shared.seek(to: chapter.startTime)
                    } label: {
                        HStack(spacing: 12) {
                            Text(Self.timestamp(chapter.startTime))
                                .font(.offscriptMeta.monospacedDigit())
                                .foregroundStyle(Color.offscriptAccent)
                                .frame(width: 46, alignment: .leading)

                            Text(chapter.title)
                                .font(.offscriptBody)
                                .foregroundStyle(Color.offscriptTextPrimary)
                                .multilineTextAlignment(.leading)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.offscriptTextMuted)
                        }
                        .padding(14)
                        .offscriptUtilitySurface(radius: OffScriptTheme.Radius.small)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Jump to \(chapter.title) at \(Self.timestamp(chapter.startTime))")
                }
            }
        }
        .padding(18)
        .offscriptSurface()
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainder = totalSeconds % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", remainder))"
        }
        return "\(minutes):\(String(format: "%02d", remainder))"
    }
}

private struct PlayerTranscriptSection: View {
    let transcripts: [EpisodeTranscriptReference]
    @State private var transcriptURL: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Transcript")
                .font(.offscriptSectionTitle)
                .foregroundStyle(Color.offscriptTextPrimary)

            VStack(spacing: 10) {
                ForEach(transcripts) { transcript in
                    Button {
                        transcriptURL = transcript.url
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "captions.bubble.fill")
                                .font(.body)
                                .foregroundStyle(Color.offscriptAccent)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(transcript.displayTitle)
                                    .font(.offscriptBody.weight(.semibold))
                                    .foregroundStyle(Color.offscriptTextPrimary)

                                Text(transcript.accessoryLabel)
                                    .font(.offscriptMeta)
                                    .foregroundStyle(Color.offscriptTextMuted)
                            }

                            Spacer()

                            Image(systemName: "doc.text")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.offscriptTextMuted)
                        }
                        .padding(14)
                        .offscriptUtilitySurface(radius: OffScriptTheme.Radius.small)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(transcript.displayTitle) transcript")
                    .accessibilityHint("Opens transcript in browser")
                }
            }
        }
        .padding(18)
        .offscriptSurface()
        .sheet(item: Binding(
            get: { transcriptURL.map { IdentifiableURL(url: $0) } },
            set: { transcriptURL = $0?.url }
        )) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
    }
}

private struct PlayerAtmosphereBackground: View {
    let url: URL?

    var body: some View {
        ZStack {
            OffScriptBackgroundView()
                .ignoresSafeArea()

            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 90)
                        .opacity(0.22)
                        .ignoresSafeArea()
                        .saturation(0.7)
                }
            }

            // Top region: lighter wash for artwork area
            LinearGradient(
                colors: [
                    Color.black.opacity(0.12),
                    Color.offscriptBackground.opacity(0.55),
                    Color.offscriptBackground.opacity(0.85),
                    Color.offscriptBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

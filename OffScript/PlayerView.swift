import OSLog
import SwiftData
import SwiftUI

private let playerLogger = Logger(subsystem: "com.offscript", category: "Player")

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var player = PlaybackController.shared
    @Query private var queueItems: [QueueItem]

    @State private var artworkAppeared = false

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

                        ScrollView {
                            VStack(spacing: 18) {
                                OffScriptArtworkView(
                                    url: episode.artworkURL ?? episode.podcast.artworkURL,
                                    cornerRadius: OffScriptTheme.Radius.large
                                )
                                .frame(width: artworkSize, height: artworkSize)
                                .scaleEffect(artworkAppeared ? 1.0 : 0.35)
                                .opacity(artworkAppeared ? 1.0 : 0.0)
                                .animation(.spring(response: 0.5, dampingFraction: 0.78), value: artworkAppeared)

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

                                    if !episode.isQueued {
                                        Button("Queue Next") {
                                            do { try QueueService.add(episode, in: modelContext) } catch { playerLogger.error("Failed to add episode to queue: \(error.localizedDescription, privacy: .public)") }
                                        }
                                        .buttonStyle(SecondaryPillButtonStyle())
                                    }

                                    Button("Mark Played") {
                                        episode.isPlayed = true
                                        episode.playedPosition = player.duration
                                        do { try modelContext.save() } catch { playerLogger.error("Failed to save mark-played state: \(error.localizedDescription, privacy: .public)") }
                                    }
                                    .buttonStyle(PrimaryPillButtonStyle())
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
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.offscriptTextSecondary)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Close player")
                }
            }
        }
        .onAppear {
            withAnimation {
                artworkAppeared = true
            }
        }
        .onDisappear {
            artworkAppeared = false
        }
    }

    private var progressValue: Double {
        guard player.duration > 0 else { return 0 }
        return player.currentTime / player.duration
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
    let item: QueueItem

    var body: some View {
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
        .onAppear { loadSuggestions() }
    }

    @MainActor
    private func loadSuggestions() {
        guard suggestions.isEmpty else { return }
        do {
            let results = try recommendationService.playerSuggestions(
                currentEpisode: currentEpisode,
                context: modelContext,
                limit: 3
            )
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                suggestions = results
            }
        } catch {
            playerLogger.error("Failed to load player suggestions: \(error.localizedDescription, privacy: .public)")
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

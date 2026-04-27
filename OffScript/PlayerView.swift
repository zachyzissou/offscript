import OSLog
import SwiftData
import SwiftUI

private let playerLogger = Logger(subsystem: "com.offscript", category: "Player")

// MARK: - PlayerView (Tuner instrument cluster)
//
// Vocabulary mirrors the EpisodeDetailView spec sheet:
//   ┌── PLAYER · NOW PLAYING ─────────────────────────┐
//   │  CHANNEL [PODCAST]   STATE [PLAYING]            │
//   │  Title (display weight)                         │
//   │  ── readouts: pos · dur · remaining             │
//   │  ── tick scrubber (signal yellow on hairline)   │
//   │  [< 15]  [▶/❙❙]  [30 >]  [⏭]                    │
//   │  ── UP NEXT (hairline rule)                     │
//   │  ── WHAT'S NEXT (rec rows)                      │
//   │  ── CONTROLS · SPEED · QUEUE · MARK PLAYED      │
//   └─────────────────────────────────────────────────┘

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
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            specHeader(episode: episode)
                            artworkBlock(episode: episode)
                            titleBlock(episode: episode)
                            readouts
                            scrubber
                            transportRow
                            upNext
                            whatsNextSection(episode: episode)
                            controlsSection(episode: episode)
                        }
                        .padding(.horizontal, OffScriptTheme.pagePadding)
                        .padding(.vertical, 12)
                    }
                    .background(Color.offscriptStudioBlack.ignoresSafeArea())
                } else {
                    emptyState
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.offscriptSignalYellow)
                            .frame(width: 36, height: 32)
                            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                    }
                    .accessibilityLabel("Close player")
                }
            }
            .toolbarBackground(Color.offscriptStudioBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: spec header

    private func specHeader(episode: Episode) -> some View {
        HStack {
            TunerLabel(text: "PLAYER · NOW PLAYING", color: .offscriptSignalYellow)
            Spacer()
            TunerLabel(text: stateLabel, color: stateColor)
        }
        .padding(.bottom, 4)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .bottom
        )
    }

    private var stateLabel: String {
        if player.isPlaying { return "● PLAYING" }
        if player.currentTime > 0 { return "❙❙ PAUSED" }
        return "○ READY"
    }

    private var stateColor: Color {
        if player.isPlaying { return .offscriptFnMode }
        if player.currentTime > 0 { return .offscriptSignalYellow }
        return .offscriptSoftPaper
    }

    // MARK: artwork block

    private func artworkBlock(episode: Episode) -> some View {
        HStack(alignment: .top, spacing: 14) {
            OffScriptArtworkView(
                url: episode.artworkURL ?? episode.podcast.artworkURL,
                cornerRadius: 3
            )
            .frame(width: 120, height: 120)
            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                TunerTag(text: episode.podcast.title, color: .offscriptFnRecord)
                    .lineLimit(1)
                if let date = formattedDate(episode.pubDate) {
                    TunerTag(text: date, color: .offscriptFnInfo, dim: true)
                }
                if let dur = episode.duration {
                    TunerLabel(text: "DURATION  \(EpisodeDurationFormatter.short(dur).uppercased())", color: .offscriptSoftPaper)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func titleBlock(episode: Episode) -> some View {
        Text(episode.title)
            .font(.system(size: 22, weight: .semibold))
            .tracking(-0.4)
            .foregroundStyle(Color.offscriptPaperWhite)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: readouts + scrubber

    private var readouts: some View {
        HStack {
            TunerLabel(text: "POS  \(time(player.currentTime).uppercased())", color: .offscriptSignalYellow)
            Spacer()
            TunerLabel(text: "REM  -\(time(max(0, player.duration - player.currentTime)).uppercased())", color: .offscriptFnInfo)
        }
        .padding(.top, 4)
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            // Tick rule — signal yellow fill on hairline
            GeometryReader { proxy in
                let clamped = min(max(progressValue, 0), 1)
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.offscriptHairline)
                    Rectangle()
                        .fill(Color.offscriptSignalYellow)
                        .frame(width: proxy.size.width * clamped)
                }
            }
            .frame(height: 2)

            // Hidden slider for tap-to-seek + drag — keeps Tuner visual rail
            // but uses native Slider interaction underneath.
            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 1)
            )
            .tint(Color.offscriptSignalYellow)
            .frame(height: 22)
            .opacity(0.001) // invisible but still touchable
            .padding(.top, -22) // overlay on top of the visual tick rail
        }
    }

    // MARK: transport

    private var transportRow: some View {
        HStack(spacing: 10) {
            tunerTransport(systemImage: "gobackward.15", label: "Skip back 15s") {
                player.seek(by: -15)
            }
            tunerTransportPrimary(systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                                  label: player.isPlaying ? "Pause" : "Play") {
                player.togglePlayPause()
            }
            tunerTransport(systemImage: "goforward.30", label: "Skip ahead 30s") {
                player.seek(by: 30)
            }
            tunerTransport(systemImage: "forward.end.fill", label: "Next in queue") {
                player.skipToNextInQueue()
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func tunerTransport(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.offscriptPaperWhite)
                .frame(width: 56, height: 56)
                .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func tunerTransportPrimary(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 80, height: 56)
                .background(Color.offscriptSignalYellow)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: up next

    @ViewBuilder
    private var upNext: some View {
        if let nextItem = orderedQueueItems.first {
            VStack(alignment: .leading, spacing: 8) {
                TunerLabel(text: "UP NEXT · CHANNEL QUEUE", color: .offscriptSignalYellow)

                HStack(spacing: 12) {
                    OffScriptArtworkView(
                        url: nextItem.episode.artworkURL ?? nextItem.episode.podcast.artworkURL,
                        cornerRadius: 3
                    )
                    .frame(width: 44, height: 44)
                    .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 2) {
                        TunerLabel(text: nextItem.episode.podcast.title.uppercased(), color: .offscriptFnInfo, size: 8)
                            .lineLimit(1)
                        Text(nextItem.episode.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Color.offscriptPaperWhite)
                            .lineLimit(2)
                    }
                    Spacer()
                    if let dur = nextItem.episode.duration {
                        TunerLabel(text: EpisodeDurationFormatter.short(dur).uppercased(), color: .offscriptSoftPaper)
                    }
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                Rectangle().fill(Color.offscriptHairline).frame(height: 1),
                alignment: .top
            )
        }
    }

    // MARK: what's next (recommendations)

    @ViewBuilder
    private func whatsNextSection(episode: Episode) -> some View {
        PlayerWhatsNextSection(currentEpisode: episode)
    }

    // MARK: controls

    private func controlsSection(episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TunerLabel(text: "CONTROLS · TRANSPORT", color: .offscriptSignalYellow)

            HStack(spacing: 8) {
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
                    tunerControlLabel(text: "SPEED  \(String(format: "%.2gX", player.playbackRate))",
                                      color: .offscriptPaperWhite)
                }
                .buttonStyle(.plain)

                if !episode.isQueued {
                    Button {
                        do { try QueueService.add(episode, in: modelContext) }
                        catch { playerLogger.error("Queue add failed: \(error.localizedDescription, privacy: .public)") }
                    } label: {
                        tunerControlLabel(text: "+ QUEUE NEXT", color: .offscriptPaperWhite)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    episode.isPlayed = true
                    episode.playedPosition = player.duration
                    do { try modelContext.save() }
                    catch { playerLogger.error("Mark-played save failed: \(error.localizedDescription, privacy: .public)") }
                } label: {
                    tunerControlLabel(text: "✓ MARK PLAYED", color: .offscriptSignalYellow)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
    }

    @ViewBuilder
    private func tunerControlLabel(text: String, color: Color) -> some View {
        TunerLabel(text: text, color: color, size: 10)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .overlay(Rectangle().stroke(color.opacity(0.7), lineWidth: 1))
    }

    // MARK: empty

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            TunerLabel(text: "● NO SIGNAL", color: .offscriptSoftPaper)
            Text("Nothing playing")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.offscriptPaperWhite)
            Text("Start an episode from Home, Library, or Queue to fill this panel.")
                .font(.system(size: 13.5))
                .foregroundStyle(Color.offscriptPaperWhite)
        }
        .padding(OffScriptTheme.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
    }

    // MARK: helpers

    private var progressValue: Double {
        guard player.duration > 0 else { return 0 }
        return player.currentTime / player.duration
    }

    private func time(_ interval: TimeInterval) -> String {
        guard interval.isFinite else { return "0:00" }
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private func formattedDate(_ date: Date) -> String? {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

// MARK: - What's Next (recommendation rows)

private struct PlayerWhatsNextSection: View {
    @Environment(\.modelContext) private var modelContext
    let currentEpisode: Episode
    @State private var suggestions: [ScoredEpisode] = []

    private let recommendationService = RecommendationService()

    var body: some View {
        Group {
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    TunerLabel(text: "WHAT'S NEXT · ON YOUR FREQUENCY", color: .offscriptSignalYellow)

                    VStack(spacing: 0) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.episode.id) { idx, scored in
                            PlayerSuggestionRow(scored: scored, rank: idx + 1)
                            if idx < suggestions.count - 1 {
                                Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(
                    Rectangle().fill(Color.offscriptHairline).frame(height: 1),
                    alignment: .top
                )
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
            withAnimation(.easeInOut(duration: 0.2)) {
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
    let rank: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", rank))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.offscriptSignalYellow)
                .frame(width: 22, alignment: .leading)

            OffScriptArtworkView(
                url: scored.episode.artworkURL ?? scored.episode.podcast.artworkURL,
                cornerRadius: 3
            )
            .frame(width: 40, height: 40)
            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                TunerTag(text: scored.explanation, color: .offscriptSignalYellow, dim: true)
                Text(scored.episode.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(1)
                TunerLabel(text: scored.episode.podcast.title.uppercased(), color: .offscriptSoftPaper, size: 8)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                PlaybackController.shared.play(scored.episode, in: modelContext)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 30)
                    .background(Color.offscriptSignalYellow)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(scored.episode.title)")
        }
        .padding(.vertical, 8)
    }
}

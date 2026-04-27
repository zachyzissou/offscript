import AVKit
import SwiftData
import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var player = PlaybackController.shared
    @ObservedObject private var timePublisher = PlaybackTimePublisher.shared
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
                        let isOfflineReady = DownloadService.shared.localURL(for: episode) != nil
                        let _ = DownloadService.shared.statusText(for: episode) // keep observation

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

                                    HStack(spacing: 8) {
                                        if let duration = episode.duration {
                                            Text(EpisodeDurationFormatter.short(duration))
                                                .font(.offscriptMeta)
                                                .foregroundStyle(Color.offscriptTextMuted)
                                        }
                                        if isOfflineReady {
                                            Image(systemName: "arrow.down.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(Color.offscriptAccent)
                                        }
                                        if !transcripts.isEmpty {
                                            Image(systemName: "captions.bubble.fill")
                                                .font(.caption)
                                                .foregroundStyle(Color.offscriptAccent)
                                        }
                                        if let sleepTimerEndDate = player.sleepTimerEndDate {
                                            Text("Sleep \(sleepTimerEndDate.formatted(date: .omitted, time: .shortened))")
                                                .font(.offscriptMeta)
                                                .foregroundStyle(Color.offscriptTextMuted)
                                        }
                                    }

                                }

                                VStack(spacing: 8) {
                                    OffScriptScrubber(
                                        value: Binding(
                                            get: { timePublisher.currentTime },
                                            set: { _ in }
                                        ),
                                        duration: timePublisher.duration,
                                        onSeek: { player.seek(to: $0) }
                                    )

                                    HStack {
                                        Text(time(timePublisher.currentTime))
                                        Spacer()
                                        Text(remainingTime)
                                    }
                                    .font(.offscriptMeta.monospacedDigit())
                                    .foregroundStyle(Color.offscriptTextMuted)
                                }
                                .frame(maxWidth: 440)

                                HStack(spacing: 18) {
                                    PlayerCircleButton(systemImage: "gobackward.15", accessibilityLabel: "Skip back 15 seconds", isPrimary: false) {
                                        player.seek(by: -15)
                                    }
                                    .sensoryFeedback(.impact(weight: .light), trigger: timePublisher.currentTime)

                                    PlayerCircleButton(
                                        systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                                        accessibilityLabel: player.isPlaying ? "Pause playback" : "Resume playback",
                                        isPrimary: true,
                                        size: 84
                                    ) {
                                        player.togglePlayPause()
                                    }
                                    .sensoryFeedback(.impact(flexibility: .soft), trigger: player.isPlaying)

                                    PlayerCircleButton(systemImage: "goforward.30", accessibilityLabel: "Skip forward 30 seconds", isPrimary: false) {
                                        player.seek(by: 30)
                                    }
                                    .sensoryFeedback(.impact(weight: .light), trigger: timePublisher.currentTime)

                                    PlayerCircleButton(systemImage: "forward.end.fill", accessibilityLabel: "Play next queued episode", isPrimary: false) {
                                        player.skipToNextInQueue()
                                    }
                                    .sensoryFeedback(.impact(weight: .medium), trigger: player.currentEpisode?.id)
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

                                // Tuner-direction control strip — single
                                // hairline-bordered panel, mono icon row,
                                // tap labels live on long-press menus. Reads
                                // as instrument-cluster instead of pill row.
                                PlayerControlStrip(episode: episode)
                                    .frame(maxWidth: 440)

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
        let remaining = max(timePublisher.duration - timePublisher.currentTime, 0)
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

/// Tuner-direction transport button. Primary (play/pause) keeps the warm
/// accent fill but gains a subtle metallic gradient + accent halo. Secondary
/// buttons get a tight inner gradient + double hairline ring so they read as
/// machined metal panel keys, not iOS Music transport.
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
                .font(.system(size: isPrimary ? 28 : 20, weight: .semibold))
                .foregroundStyle(isPrimary ? Color.black : Color.offscriptTextPrimary)
                .frame(width: size, height: size)
                .background(buttonFill)
                .clipShape(Circle())
                .overlay(buttonStroke)
                .shadow(color: shadowColor, radius: isPrimary ? 18 : 6, y: isPrimary ? 8 : 3)
                .scaleEffect(reduceMotion ? 1.0 : (isPressed ? 0.92 : 1.0))
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.62), value: isPressed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !reduceMotion { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
    }

    @ViewBuilder
    private var buttonFill: some View {
        if isPrimary {
            // Warm accent disc with subtle top-light gradient. Reads as a
            // machined illuminated key.
            LinearGradient(
                colors: [Color.offscriptAccent, Color.offscriptAccent.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            // Cool dark panel key — top-light gradient + faint inner
            // brightness gives it the "instrument key" depth.
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private var buttonStroke: some View {
        if isPrimary {
            // Inner accent halo + outer hairline.
            Circle()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                .padding(1)
                .overlay(
                    Circle().stroke(Color.offscriptAccent.opacity(0.4), lineWidth: 0.5)
                )
        } else {
            // Double hairline — outer dark, inner light. Tuner panel cue.
            Circle()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                .padding(0.5)
                .overlay(
                    Circle().stroke(Color.offscriptHairline, lineWidth: 0.5)
                )
        }
    }

    private var shadowColor: Color {
        isPrimary ? Color.offscriptAccent.opacity(0.35) : Color.black.opacity(0.4)
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
                OffScriptSmartExplanationTag(episodeID: scored.episode.id, fallback: scored.explanation)

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

/// Tuner-direction background: deep studio black with a single horizon
/// glow tinted from the artwork. No more breathing-blur photo wallpaper —
/// reads as instrument-cluster, not iOS Music. Hairline grid overlay sells
/// the "panel" feel without going overboard.
/// Tuner-direction "control strip" that replaces the two pill rows under
/// transport. Single hairline-bordered panel, mono icon row, with grouped
/// menus for speed / queue / sleep. Mark-played sits as the only filled
/// accent button — it's the destructive completion action and benefits from
/// being visually distinct.
private struct PlayerControlStrip: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var player = PlaybackController.shared
    let episode: Episode

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Speed
                Menu {
                    ForEach([("1.0x", Float(1.0)), ("1.25x", Float(1.25)), ("1.5x", Float(1.5)), ("1.75x", Float(1.75)), ("2.0x", Float(2.0))], id: \.0) { label, rate in
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
                    cell(icon: "speedometer", label: String(format: "%.2gx", player.playbackRate))
                }

                hairline

                // Queue
                Menu {
                    Button("Play Next") {
                        try? QueueService.playNext(episode, in: modelContext)
                    }
                    Button("Add to End") {
                        try? QueueService.addToEnd(episode, in: modelContext)
                    }
                } label: {
                    cell(icon: episode.isQueued ? "checkmark.circle" : "text.badge.plus",
                         label: episode.isQueued ? "Queued" : "Queue")
                }
                .disabled(episode.isQueued)

                hairline

                // Sleep timer
                Menu {
                    Button("15 minutes") { player.setSleepTimer(minutes: 15) }
                    Button("30 minutes") { player.setSleepTimer(minutes: 30) }
                    Button("60 minutes") { player.setSleepTimer(minutes: 60) }
                    if player.sleepTimerEndDate != nil {
                        Button("Cancel Timer", role: .destructive) { player.cancelSleepTimer() }
                    }
                } label: {
                    cell(icon: player.sleepTimerEndDate == nil ? "moon" : "moon.zzz.fill",
                         label: sleepLabel)
                }

                hairline

                // AirPlay route
                cellWrapper {
                    AirPlayRouteButton()
                        .frame(width: 28, height: 28)
                }

                hairline

                // Share
                ShareLink(item: episode.audioURL) {
                    cell(icon: "square.and.arrow.up", label: "Share")
                }

                hairline

                // Download
                cellWrapper {
                    DownloadButton(episode: episode)
                }
            }
            .frame(height: 64)

            Rectangle()
                .fill(Color.offscriptHairline)
                .frame(height: 0.5)

            // Mark Played — the one decisive action gets its own row + accent fill.
            Button {
                player.completeCurrentEpisode(shouldAutoAdvance: false)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline.weight(.bold))
                    Text("MARK PLAYED")
                        .font(.offscriptMicro.weight(.bold))
                        .tracking(1.4)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.offscriptAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark episode as played")
        }
        .background(Color.offscriptCardUtility.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: OffScriptTheme.Radius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.small, style: .continuous)
                .stroke(Color.offscriptHairline, lineWidth: 0.5)
        )
    }

    private var sleepLabel: String {
        guard let end = player.sleepTimerEndDate else { return "Sleep" }
        let remaining = max(0, end.timeIntervalSinceNow)
        let minutes = Int(remaining / 60)
        return minutes > 0 ? "\(minutes)m" : "<1m"
    }

    @ViewBuilder
    private func cell(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.offscriptTextPrimary)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.offscriptTextMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func cellWrapper<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 4) {
            content()
            // Spacer to keep alignment with cell() rows that have a label.
            Text("")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Without contentShape, the hit area is the rendered pixels only —
        // AVRoutePickerView (28pt) and DownloadButton are smaller than the
        // allocated frame, leaving dead zones in the cell corners.
        .contentShape(Rectangle())
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.offscriptHairline)
            .frame(width: 0.5)
            .frame(maxHeight: .infinity)
    }
}

private struct PlayerAtmosphereBackground: View {
    let url: URL?

    var body: some View {
        ZStack {
            // Solid near-black studio surface.
            Color.offscriptBackgroundBottom
                .ignoresSafeArea()

            // Single horizon glow at the top — sampled from artwork via the
            // existing image cache. No animation; instrument panels don't breathe.
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 120)
                    .opacity(0.32)
                    .frame(height: 360)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
                    .saturation(0.55)
            } placeholder: {
                Color.clear
            }

            // Vignette down to true black so the transport sits on a clean panel.
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.offscriptBackgroundBottom.opacity(0.55),
                    Color.offscriptBackgroundBottom.opacity(0.92),
                    Color.offscriptBackgroundBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Hairline horizon line where the glow ends — instrument-panel cue.
            VStack(spacing: 0) {
                Spacer().frame(height: 320)
                Rectangle()
                    .fill(Color.offscriptHairline)
                    .frame(height: 0.5)
                Spacer()
            }
            .ignoresSafeArea()
        }
    }
}

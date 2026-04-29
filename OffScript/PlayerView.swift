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
        // No NavigationStack here — iOS 26 wraps any toolbar item in a glass
        // capsule chrome that ignores .buttonStyle(.plain) and our color
        // tokens. Same problem the tab bar + settings cog had. PlayerView is
        // a full-screen modal cover; we render our own dismiss key inline at
        // the top so we keep full control over its rendering.
        Group {
            if let episode = player.currentEpisode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        dismissBar
                        specHeader(episode: episode)
                        artworkBlock(episode: episode)
                        titleBlock(episode: episode)
                        readouts
                        scrubber
                        if let error = player.playbackError {
                            playbackErrorStrip(message: error)
                        }
                        transportRow
                        chaptersSection(episode: episode)
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
    }

    /// Inline dismiss row — sharp Tuner button, no nav-bar chrome.
    private var dismissBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.offscriptSignalYellow)
                    .frame(width: 36, height: 30)
                    .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close player")
            Spacer()
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
                // Podcast title in info-cyan per the function-coded color
                // system. Was record-red (the same bug fixed in
                // QueueLeadStrip in 2.3.2) — record-red is reserved for
                // destructive / error signals.
                TunerLabel(text: episode.podcast.title.uppercased(),
                           color: .offscriptFnInfo, size: 9)
                    .lineLimit(1)
                if let date = formattedDate(episode.pubDate) {
                    TunerLabel(text: date.uppercased(),
                               color: .offscriptSoftPaper, size: 9)
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
        TunerScrubber(
            value: player.currentTime,
            duration: max(player.duration, 1),
            onSeek: { player.seek(to: $0) }
        )
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
                .foregroundStyle(Color.offscriptStudioBlack)
                .frame(width: 80, height: 56)
                .background(Color.offscriptSignalYellow)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Inline error strip rendered above the transport row when an
    /// AVPlayerItem fails to load or stalls. Sharp Tuner rectangle in
    /// record-red so it reads as fault state without dominating the
    /// player.
    private func playbackErrorStrip(message: String) -> some View {
        HStack(spacing: 8) {
            TunerLabel(text: "● PLAYBACK ERROR", color: .offscriptFnRecord, size: 9)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineLimit(2)
            Spacer()
            Button { player.clearPlaybackError() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.offscriptSoftPaper)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
    }

    // MARK: chapters

    /// Hairline-divided chapter list. Renders only when the episode actually
    /// has chapters (model parses both psc:chapter PSC tags and timestamp
    /// patterns in the summary via EpisodeChapterParser). Each row is a
    /// tap-to-seek button; the current chapter is highlighted in
    /// signal-yellow with a `▶` glyph.
    @ViewBuilder
    private func chaptersSection(episode: Episode) -> some View {
        let chapters = episode.resolvedChapters
        if !chapters.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TunerLabel(text: "CHAPTERS · TAP TO SEEK", color: .offscriptSignalYellow)
                    Spacer()
                    TunerLabel(text: "\(chapters.count) MARKS", color: .offscriptFnInfo)
                }

                LazyVStack(spacing: 0) {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { idx, chapter in
                        chapterRow(
                            idx: idx,
                            chapter: chapter,
                            isCurrent: isCurrentChapter(chapter, in: chapters)
                        )
                        if idx < chapters.count - 1 {
                            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                Rectangle().fill(Color.offscriptHairline).frame(height: 1),
                alignment: .top
            )
        }
    }

    private func chapterRow(idx: Int, chapter: EpisodeChapter, isCurrent: Bool) -> some View {
        Button {
            player.seek(to: chapter.startTime)
        } label: {
            HStack(spacing: 12) {
                Text(String(format: "%02d", idx + 1))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(isCurrent ? Color.offscriptSignalYellow : Color.offscriptSoftPaper)
                    .frame(width: 28, alignment: .leading)

                if isCurrent {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.offscriptSignalYellow)
                }

                Text(chapter.title)
                    .font(.system(size: 13.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.offscriptSignalYellow : Color.offscriptPaperWhite)
                    .lineLimit(1)

                Spacer()

                Text(time(chapter.startTime))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.offscriptSoftPaper)
                    .monospacedDigit()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chapter \(idx + 1): \(chapter.title) at \(time(chapter.startTime))")
    }

    /// A chapter is "current" when player time has crossed its startTime
    /// but hasn't yet crossed the next chapter's startTime. The last chapter
    /// stays current to the end of the episode.
    private func isCurrentChapter(_ chapter: EpisodeChapter, in chapters: [EpisodeChapter]) -> Bool {
        guard let idx = chapters.firstIndex(of: chapter) else { return false }
        let now = player.currentTime
        guard now >= chapter.startTime else { return false }
        if idx + 1 < chapters.count {
            return now < chapters[idx + 1].startTime
        }
        return true
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
                    Section("Speed for \(episode.podcast.title)") {
                        ForEach([("1.0×", Float(1.0)),
                                 ("1.1×", Float(1.1)),
                                 ("1.25×", Float(1.25)),
                                 ("1.5×", Float(1.5)),
                                 ("1.75×", Float(1.75)),
                                 ("2.0×", Float(2.0)),
                                 ("2.5×", Float(2.5))], id: \.0) { label, rate in
                            Button {
                                player.setPlaybackRate(rate)
                            } label: {
                                HStack {
                                    Text(label)
                                    if abs(player.playbackRate - rate) < 0.001 {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    tunerControlLabel(text: "SPEED  \(String(format: "%.2g", player.playbackRate))×",
                                      color: hasCustomRate(for: episode) ? .offscriptSignalYellow : .offscriptPaperWhite)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Playback speed")
                .accessibilityHint("Pick a speed for this podcast")

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

                // Sleep timer — Menu with the standard podcast app intervals.
                // Active timer shows live countdown in mm:ss as the SLEEP key
                // label; tapping reveals the menu so the user can extend or
                // cancel without leaving the player.
                Menu {
                    if player.sleepTimerEndDate != nil {
                        Button(role: .destructive) {
                            player.cancelSleepTimer()
                        } label: {
                            Label("Cancel Timer", systemImage: "xmark")
                        }
                        Divider()
                    }
                    ForEach([5, 15, 30, 45, 60], id: \.self) { minutes in
                        Button {
                            player.setSleepTimer(minutes: minutes)
                        } label: {
                            Text("\(minutes) min")
                        }
                    }
                } label: {
                    tunerControlLabel(text: sleepTimerLabel,
                                      color: player.sleepTimerEndDate != nil
                                        ? .offscriptSignalYellow
                                        : .offscriptPaperWhite)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sleep timer")
                .accessibilityHint(player.sleepTimerEndDate != nil
                    ? "Active. Pick a new duration or cancel."
                    : "Pick a duration to pause playback.")

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
            .frame(minHeight: 44)
            .contentShape(Rectangle())
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

    /// True when the podcast has its own rate that differs from the
    /// default — drives the SPEED key's color so the user can tell at a
    /// glance whether they're on a custom pace for this show.
    private func hasCustomRate(for episode: Episode) -> Bool {
        PodcastPlaybackPreferences.preferredRate(for: episode.podcast) != nil
    }

    /// Live countdown label for the SLEEP key. Re-renders alongside
    /// `currentTime` since both update once per second via the time observer,
    /// so the SwiftUI tick is enough to keep the countdown fresh without a
    /// dedicated Timer.
    private var sleepTimerLabel: String {
        guard let endDate = player.sleepTimerEndDate else { return "SLEEP  OFF" }
        // Bind to player.currentTime so SwiftUI re-renders this label every
        // second (the AVPlayer time observer drives that publisher).
        _ = player.currentTime
        let remaining = max(0, Int(endDate.timeIntervalSinceNow))
        let mm = remaining / 60
        let ss = remaining % 60
        return String(format: "SLEEP  %d:%02d", mm, ss)
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

private struct TunerScrubber: View {
    let value: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var dragValue: Double?

    private var displayValue: Double {
        min(max(dragValue ?? value, 0), max(duration, 1))
    }

    private var progress: Double {
        displayValue / max(duration, 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let thumbX = min(max(width * progress, 0), width)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.offscriptHairline)
                    .frame(height: 2)

                Rectangle()
                    .fill(Color.offscriptSignalYellow)
                    .frame(width: max(0, thumbX), height: 2)

                ForEach(0..<9, id: \.self) { index in
                    Rectangle()
                        .fill(Color.offscriptHairline)
                        .frame(width: 1, height: index == 0 || index == 8 ? 14 : 8)
                        .offset(x: width * CGFloat(index) / 8)
                }

                Rectangle()
                    .fill(Color.offscriptSignalYellow)
                    .frame(width: 6, height: 22)
                    .offset(x: min(max(thumbX - 3, 0), width - 6))
            }
            .frame(height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragValue = seekValue(for: gesture.location.x, width: width)
                    }
                    .onEnded { gesture in
                        let newValue = seekValue(for: gesture.location.x, width: width)
                        dragValue = nil
                        onSeek(newValue)
                    }
            )
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int(progress * 100)) percent")
        .accessibilityAdjustableAction { direction in
            let step = max(duration * 0.05, 5)
            switch direction {
            case .increment:
                onSeek(min(value + step, duration))
            case .decrement:
                onSeek(max(value - step, 0))
            @unknown default:
                break
            }
        }
    }

    private func seekValue(for locationX: CGFloat, width: CGFloat) -> Double {
        let ratio = min(max(Double(locationX / max(width, 1)), 0), 1)
        return ratio * max(duration, 1)
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
                TunerTag(text: scored.explanation, color: .offscriptSignalYellow, dim: true, wraps: true)
                RecommendationSignalTraceView(signals: scored.signalTrace, limit: 2, color: .offscriptSoftPaper)
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
                    .foregroundStyle(Color.offscriptStudioBlack)
                    .frame(width: 30, height: 30)
                    .background(Color.offscriptSignalYellow)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(scored.episode.title)")
        }
        .padding(.vertical, 8)
    }
}

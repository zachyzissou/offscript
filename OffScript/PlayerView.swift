import AVKit
import CoreSpotlight
import SwiftData
import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var player = PlaybackController.shared
    @ObservedObject private var timePublisher = PlaybackTimePublisher.shared
    @Query private var queueItems: [QueueItem]
    @State private var bookmarksSheetPresented = false
    @State private var bookmarkPulse = 0
    /// Cached sort — only the first queue item is actually used (Up Next),
    /// so we recompute on @Query mutations rather than every body eval.
    @State private var orderedQueueItems: [QueueItem] = []

    private func recomputeOrderedQueueItems() {
        orderedQueueItems = queueItems.sorted { lhs, rhs in
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
                    playerBody(for: episode)
                } else {
                    ContentUnavailableView("Nothing playing", systemImage: "waveform.slash", description: Text("Start an episode from Home, Library, or Queue."))
                        .offscriptPageBackground()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.offscriptTextPrimary)
                    }
                    .accessibilityLabel("Dismiss player")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { recomputeOrderedQueueItems() }
        .onChange(of: queueItems) { _, _ in recomputeOrderedQueueItems() }
        .sheet(isPresented: $bookmarksSheetPresented) {
            if let episode = player.currentEpisode {
                EpisodeBookmarksSheet(episode: episode)
                    .presentationDetents([.medium, .large])
            }
        }
        .userActivity("com.offscript.app.playing", isActive: player.currentEpisode != nil) { activity in
            guard let episode = player.currentEpisode else { return }
            activity.title = episode.title
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            activity.persistentIdentifier = episode.id.uuidString
            activity.userInfo = [
                "episodeID": episode.id.uuidString,
                "podcastID": episode.podcast.id.uuidString
            ]
            activity.requiredUserInfoKeys = ["episodeID"]
            activity.webpageURL = URL(string: "https://offscript.app/episode/\(episode.id.uuidString)")
            activity.contentAttributeSet?.title = episode.title
            activity.contentAttributeSet?.contentDescription = episode.podcast.title
        }
    }

    // MARK: - Tuner OLED player body
    //
    // Designed against the OffScript Redesign HTML (Tuner direction): pure
    // black, signal-yellow play key, hairline scrubber + transport row,
    // ring-meter cluster for SPEED / SLEEP / VOL, and a bottom strip of
    // outlined utility cells. The artwork (or video) reads as a hairline-
    // bordered panel on the dashboard, not a soft-shadowed glamour shot.
    @ViewBuilder
    private func playerBody(for episode: Episode) -> some View {
        let nextItem = orderedQueueItems.first
        let chapters = episode.resolvedChapters
        let transcripts = episode.transcriptReferences
        let isOfflineReady = DownloadService.shared.localURL(for: episode) != nil

        ScrollView {
            VStack(spacing: 24) {
                playerHeaderTags(for: episode, isOfflineReady: isOfflineReady, hasTranscript: !transcripts.isEmpty)
                playerArtwork(for: episode)
                playerTitleBlock(for: episode)
                SmartTakeStrip(episode: episode).frame(maxWidth: 440)
                if !chapters.isEmpty {
                    PlayerChapterStrip(chapters: chapters).frame(maxWidth: 440)
                }
                playerScrubberBlock()
                playerTransportRow()
                playerInstrumentCluster()
                playerSecondaryControls(for: episode)
                if let nextItem {
                    PlayerUpNextStrip(item: nextItem).frame(maxWidth: 440)
                }
                if !chapters.isEmpty {
                    PlayerChaptersSection(chapters: chapters).frame(maxWidth: 440)
                }
                if !transcripts.isEmpty {
                    PlayerTranscriptSection(transcripts: transcripts, episodeTitle: episode.title)
                        .frame(maxWidth: 440)
                }
                PlayerWhatsNextSection(currentEpisode: episode).frame(maxWidth: 440)
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func playerHeaderTags(for episode: Episode, isOfflineReady: Bool, hasTranscript: Bool) -> some View {
        // Top strip: REC dot when playing + episode metadata tag pills.
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(player.isPlaying ? Color.offscriptDestructive : Color.offscriptTextMuted)
                    .frame(width: 6, height: 6)
                Text(player.isPlaying ? "REC" : "PAUSED")
                    .font(.offscriptTagLabel)
                    .tracking(1.4)
                    .foregroundStyle(player.isPlaying ? Color.offscriptDestructive : Color.offscriptTextMuted)
            }

            Spacer()

            HStack(spacing: 6) {
                if let duration = episode.duration {
                    TTagPill(label: EpisodeDurationFormatter.short(duration), tone: .neutral)
                }
                if isOfflineReady {
                    TTagPill(label: "OFFLINE", tone: .ok)
                }
                if hasTranscript {
                    TTagPill(label: "TRANSCRIPT", tone: .info)
                }
                if let endDate = player.sleepTimerEndDate {
                    TTagPill(label: "SLEEP \(endDate.formatted(date: .omitted, time: .shortened))", tone: .signal)
                }
            }
        }
        .frame(maxWidth: 440)
    }

    @ViewBuilder
    private func playerArtwork(for episode: Episode) -> some View {
        GeometryReader { proxy in
            let artworkSize = min(max(proxy.size.width - 80, 220), 320)
            ZStack {
                if episode.isLikelyVideo {
                    OffScriptVideoPlayerView(player: player.player)
                        .frame(maxWidth: .infinity)
                        .frame(height: artworkSize * 0.75)
                } else {
                    OffScriptArtworkView(
                        url: episode.artworkURL ?? episode.podcast.artworkURL,
                        cornerRadius: OffScriptTheme.Radius.medium
                    )
                    .frame(width: artworkSize, height: artworkSize)
                }
            }
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                    .stroke(Color.offscriptHairline, lineWidth: 0.5)
                    .frame(width: artworkSize, height: episode.isLikelyVideo ? artworkSize * 0.75 : artworkSize)
            )
        }
        .frame(height: 320)
    }

    private func playerTitleBlock(for episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(episode.podcast.title.uppercased())
                .font(.offscriptTagLabel)
                .tracking(1.6)
                .foregroundStyle(Color.offscriptAccentSecondary)
                .lineLimit(1)

            Text(episode.title)
                .font(.offscriptDisplay)
                .foregroundStyle(Color.offscriptTextPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 440, alignment: .leading)
    }

    private func playerScrubberBlock() -> some View {
        // Two big readouts (CURRENT + REMAINING) framing the hairline
        // scrubber. The instrument-cluster equivalent of a tape deck timecode.
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                TReadout(
                    value: time(timePublisher.currentTime),
                    label: "Position",
                    size: 32
                )
                Spacer()
                TReadout(
                    value: remainingTime,
                    label: "Remaining",
                    tint: .offscriptAccent,
                    size: 32,
                    alignment: .trailing
                )
            }

            OffScriptScrubber(
                value: Binding(
                    get: { timePublisher.currentTime },
                    set: { _ in }
                ),
                duration: timePublisher.duration,
                onSeek: { player.seek(to: $0) }
            )
        }
        .frame(maxWidth: 440)
    }

    private func playerTransportRow() -> some View {
        // 5-cell hairline transport. Play key emphasized with a yellow ring;
        // every other cell shares the same skeleton so the row stays level.
        HStack(spacing: 0) {
            // Back = restart episode (CD-deck convention; Apple's player
            // works the same way). There's no "previous queued episode"
            // concept — Next plays the next queued item.
            TTransportCell(cap: "Restart", action: { player.seek(to: 0) }) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 16, weight: .medium))
            }
            .sensoryFeedback(.impact(weight: .light), trigger: player.currentEpisode?.id)

            TTransportCell(cap: "−15", action: { player.seek(by: -15) }) {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 18, weight: .medium))
            }
            .sensoryFeedback(.impact(weight: .light), trigger: timePublisher.currentTime)

            TTransportCell(
                cap: player.isPlaying ? "Pause" : "Play",
                emphasized: true,
                action: { player.togglePlayPause() }
            ) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
            }
            .sensoryFeedback(.impact(flexibility: .soft), trigger: player.isPlaying)

            TTransportCell(cap: "+30", action: { player.seek(by: 30) }) {
                Image(systemName: "goforward.30")
                    .font(.system(size: 18, weight: .medium))
            }
            .sensoryFeedback(.impact(weight: .light), trigger: timePublisher.currentTime)

            TTransportCell(cap: "Next", action: { player.skipToNextInQueue() }) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 16, weight: .medium))
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: player.currentEpisode?.id)
        }
        .frame(maxWidth: 440)
        .overlay(
            Rectangle()
                .stroke(Color.offscriptHairline, lineWidth: 0.5)
        )
    }

    private func playerInstrumentCluster() -> some View {
        // Three ring meters in a row: SPEED (yellow), PROGRESS (yellow),
        // SLEEP (mint when active, neutral otherwise). Replaces the
        // skeuomorphic round controls below the transport on the previous
        // theme.
        HStack(spacing: 24) {
            Spacer()
            speedRing
            progressRing
            sleepRing
            Spacer()
        }
        .frame(maxWidth: 440)
    }

    private var speedRing: some View {
        TRingMeter(
            value: Double(player.playbackRate),
            minValue: 0.5,
            maxValue: 2.5,
            tint: .offscriptAccent,
            diameter: 56,
            label: "Speed",
            centerText: String(format: "%.2g×", player.playbackRate)
        )
    }

    private var progressRing: some View {
        let frac = timePublisher.duration > 0
            ? min(timePublisher.currentTime / timePublisher.duration, 1)
            : 0
        return TRingMeter(
            value: frac,
            tint: .offscriptAccent,
            diameter: 56,
            label: "Progress",
            centerText: "\(Int(frac * 100))%"
        )
    }

    private var sleepRing: some View {
        let active = player.sleepTimerEndDate != nil
        let label = active
            ? player.sleepTimerEndDate?.formatted(date: .omitted, time: .shortened) ?? "ON"
            : "OFF"
        return TRingMeter(
            value: active ? 1 : 0,
            tint: active ? .offscriptAccentOK : .offscriptHairline,
            diameter: 56,
            label: "Sleep",
            centerText: label
        )
    }

    @ViewBuilder
    private func playerSecondaryControls(for episode: Episode) -> some View {
        // Outlined utility row — speed menu, queue add, mark played, sleep,
        // airplay, bookmark, share, download. Each cell is the same height
        // so the row stays level.
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Menu {
                    ForEach([("1.0×", Float(1.0)), ("1.25×", Float(1.25)), ("1.5×", Float(1.5)), ("2.0×", Float(2.0))], id: \.0) { label, rate in
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
                    Text(String(format: "%.2g×", player.playbackRate))
                }
                .buttonStyle(SecondaryPillButtonStyle())

                Menu {
                    Button("Play Next") {
                        try? QueueService.playNext(episode, in: modelContext)
                    }
                    Button("Add to End") {
                        try? QueueService.addToEnd(episode, in: modelContext)
                    }
                } label: {
                    Text(episode.isQueued ? "Queued" : "Queue")
                }
                .buttonStyle(SecondaryPillButtonStyle())
                .disabled(episode.isQueued)

                Spacer()

                Button("Mark Played") {
                    player.completeCurrentEpisode(shouldAutoAdvance: false)
                }
                .buttonStyle(SecondaryPillButtonStyle())
            }

            HStack(spacing: 8) {
                Menu {
                    Button("15 minutes") { player.setSleepTimer(minutes: 15) }
                    Button("30 minutes") { player.setSleepTimer(minutes: 30) }
                    Button("60 minutes") { player.setSleepTimer(minutes: 60) }
                    if player.sleepTimerEndDate != nil {
                        Button("Cancel Timer", role: .destructive) { player.cancelSleepTimer() }
                    }
                } label: {
                    Image(systemName: "moon.zzz")
                }
                .buttonStyle(SecondaryPillButtonStyle())

                AirPlayRouteButton()
                    .frame(width: 44, height: 36)

                Button {
                    addBookmark(at: episode)
                } label: {
                    Image(systemName: "bookmark")
                        .symbolEffect(.bounce, value: bookmarkPulse)
                }
                .buttonStyle(SecondaryPillButtonStyle())
                .accessibilityLabel("Save bookmark at current time")
                .sensoryFeedback(.impact(flexibility: .soft), trigger: bookmarkPulse)

                Button {
                    bookmarksSheetPresented = true
                } label: {
                    Image(systemName: "bookmark.square")
                }
                .buttonStyle(SecondaryPillButtonStyle())
                .accessibilityLabel("View saved bookmarks")

                ShareLink(item: episode.audioURL) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryPillButtonStyle())

                DownloadButton(episode: episode)
            }
        }
        .frame(maxWidth: 440)
    }

    private var remainingTime: String {
        let remaining = max(timePublisher.duration - timePublisher.currentTime, 0)
        return "−\(time(remaining))"
    }

    private func addBookmark(at episode: Episode) {
        let bookmark = Bookmark(
            episode: episode,
            position: timePublisher.currentTime,
            note: nil
        )
        modelContext.insert(bookmark)
        try? modelContext.save()
        bookmarkPulse += 1
        TelemetryService.track(
            "bookmark_added",
            metadata: ["episode": episode.title, "position_s": "\(Int(timePublisher.currentTime))"],
            in: modelContext
        )
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

private struct PlayerChapterStrip: View {
    let chapters: [EpisodeChapter]
    @ObservedObject private var timePublisher = PlaybackTimePublisher.shared

    var body: some View {
        // Tuner chapter strip — flat panel with two hairline-square chapter
        // step keys and an instrument-style chapter readout in the middle.
        HStack(spacing: 8) {
            chapterStepButton(systemImage: "backward.end.fill", label: "Previous chapter", target: previousChapterStart)

            VStack(alignment: .leading, spacing: 2) {
                Text("CHAPTER \(currentChapterNumber) / \(chapters.count)")
                    .font(.offscriptTagLabel)
                    .tracking(1.4)
                    .foregroundStyle(Color.offscriptAccentSecondary)
                Text(currentChapter?.title ?? "—")
                    .font(.offscriptCardTitle)
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            chapterStepButton(systemImage: "forward.end.fill", label: "Next chapter", target: nextChapterStart)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.offscriptCard)
        .overlay(
            Rectangle()
                .stroke(Color.offscriptHairline, lineWidth: 0.5)
        )
    }

    private func chapterStepButton(systemImage: String, label: String, target: TimeInterval?) -> some View {
        Button {
            if let target { PlaybackController.shared.seek(to: target) }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(target == nil ? Color.offscriptTextMuted.opacity(0.5) : Color.offscriptTextPrimary)
                .frame(width: 32, height: 32)
                .overlay(
                    Rectangle()
                        .stroke(Color.offscriptHairline, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .accessibilityLabel(label)
    }

    private var currentChapterIndex: Int {
        let now = timePublisher.currentTime
        for index in chapters.indices.reversed() {
            if chapters[index].startTime <= now { return index }
        }
        return 0
    }

    private var currentChapter: EpisodeChapter? {
        chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex] : nil
    }

    private var currentChapterNumber: Int { currentChapterIndex + 1 }

    private var previousChapterStart: TimeInterval? {
        let idx = currentChapterIndex
        guard idx >= 0, idx < chapters.count else { return nil }
        let now = timePublisher.currentTime
        // If we're more than 4 seconds into the current chapter, "previous"
        // restarts the current one — same UX as a CD player.
        if now - chapters[idx].startTime > 4 {
            return chapters[idx].startTime
        }
        return idx > 0 ? chapters[idx - 1].startTime : nil
    }

    private var nextChapterStart: TimeInterval? {
        let next = currentChapterIndex + 1
        guard next < chapters.count else { return nil }
        return chapters[next].startTime
    }
}

private struct SmartTakeStrip: View {
    @Environment(\.modelContext) private var modelContext
    let episode: Episode

    @State private var take: String?
    @State private var generationTask: Task<Void, Never>?

    var body: some View {
        // Tuner OLED Smart Take — flat panel with a cyan eyebrow
        // ("ON-DEVICE TAKE") and the AI commentary in regular sans body.
        // Replaces the serif-italic editorial pull-quote treatment from the
        // previous theme.
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.offscriptAccentSecondary)
                Text("ON-DEVICE TAKE")
                    .font(.offscriptTagLabel)
                    .tracking(1.4)
                    .foregroundStyle(Color.offscriptAccentSecondary)
            }
            Text(take ?? "Reading the room…")
                .font(.offscriptBody)
                .foregroundStyle(take == nil ? Color.offscriptTextMuted : Color.offscriptTextPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.offscriptCard)
        .overlay(
            Rectangle()
                .stroke(Color.offscriptAccentSecondary.opacity(0.32), lineWidth: 0.5)
        )
        .onAppear { kickOffLoad() }
        .onChange(of: episode.id) { _, _ in
            take = nil
            kickOffLoad()
        }
        .onDisappear {
            // Cancel in-flight FoundationModels work when the player is dismissed.
            // Without this, rapid episode-tap cycles stack pending requests.
            generationTask?.cancel()
            generationTask = nil
        }
    }

    private func kickOffLoad() {
        // Cancel any prior request first so only the latest episode's take wins.
        generationTask?.cancel()

        if let cached = SmartTakeService.shared.cached(for: episode) {
            withAnimation(.easeInOut(duration: 0.4)) { take = cached }
            return
        }

        generationTask = Task { @MainActor in
            // Show heuristic immediately so something is visible — then upgrade
            // to the FoundationModels-generated take when it returns.
            let immediate = SmartTakeService.shared.heuristicTakePublic(for: episode)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { take = immediate }

            let generated = await SmartTakeService.shared.generate(for: episode, in: modelContext)
            guard !Task.isCancelled else { return }
            if let generated, generated != immediate {
                withAnimation(.easeInOut(duration: 0.4)) { take = generated }
            }
        }
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
                .background {
                    if isPrimary {
                        Circle()
                            .fill(Color.offscriptAccent)
                            .shadow(color: Color.offscriptAccent.opacity(0.55), radius: 24, y: 10)
                            .shadow(color: Color.offscriptAccent.opacity(0.18), radius: 4, y: 1)
                    } else {
                        Circle()
                            .fill(.clear)
                            .offscriptGlass(in: Circle())
                    }
                }
                .overlay(
                    Circle()
                        .stroke(isPrimary ? Color.clear : Color.offscriptHairline, lineWidth: 0.5)
                )
                .contentTransition(.symbolEffect(.replace.downUp))
                // Phase animator: a quick pulse + counter-rotation when the
                // play/pause symbol changes. Subtle but it makes the primary
                // button feel responsive and alive.
                .modifier(PrimaryButtonPhaseAnimation(systemImage: systemImage, enabled: isPrimary && !reduceMotion))
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

private struct PrimaryButtonPhaseAnimation: ViewModifier {
    let systemImage: String
    let enabled: Bool

    enum Phase: CaseIterable {
        case rest, pulse, settle
    }

    func body(content: Content) -> some View {
        if enabled {
            content
                .phaseAnimator([Phase.rest, .pulse, .settle], trigger: systemImage) { view, phase in
                    view
                        .scaleEffect(phase == .pulse ? 1.08 : (phase == .settle ? 0.97 : 1.0))
                } animation: { phase in
                    switch phase {
                    case .pulse:
                        return .spring(response: 0.22, dampingFraction: 0.5)
                    case .settle:
                        return .spring(response: 0.32, dampingFraction: 0.62)
                    case .rest:
                        return .spring(response: 0.4, dampingFraction: 0.85)
                    }
                }
        } else {
            content
        }
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
    @ObservedObject private var timePublisher = PlaybackTimePublisher.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Chapters")
                    .font(.offscriptSectionTitle)
                    .foregroundStyle(Color.offscriptTextPrimary)
                Spacer()
                Text("\(chapters.count)")
                    .font(.offscriptMicro.weight(.semibold))
                    .foregroundStyle(Color.offscriptAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.offscriptAccentSoft, in: Capsule())
            }

            VStack(spacing: 10) {
                ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                    let isCurrent = currentChapterIndex == index
                    let isPast = currentChapterIndex.map { $0 > index } ?? false
                    let endTime = nextStartTime(after: index) ?? max(timePublisher.duration, chapter.startTime + 60)
                    let progress: Double = isCurrent ? chapterProgress(start: chapter.startTime, end: endTime) : (isPast ? 1.0 : 0.0)

                    Button {
                        PlaybackController.shared.seek(to: chapter.startTime)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .stroke(Color.offscriptHairline, lineWidth: 2)
                                    .frame(width: 28, height: 28)
                                Circle()
                                    .trim(from: 0, to: progress)
                                    .stroke(Color.offscriptAccent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                    .frame(width: 28, height: 28)
                                    .rotationEffect(.degrees(-90))
                                Text("\(index + 1)")
                                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                                    .foregroundStyle(isCurrent ? Color.offscriptAccent : Color.offscriptTextMuted)
                            }
                            .animation(.easeOut(duration: 0.4), value: progress)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(chapter.title)
                                    .font(isCurrent ? .offscriptCardTitle : .offscriptBody)
                                    .foregroundStyle(isCurrent ? Color.offscriptTextPrimary : Color.offscriptTextSecondary)
                                    .multilineTextAlignment(.leading)
                                Text(Self.timestamp(chapter.startTime))
                                    .font(.offscriptMicro)
                                    .foregroundStyle(Color.offscriptTextMuted)
                            }

                            Spacer()

                            Image(systemName: isCurrent ? "waveform" : "play.circle")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(isCurrent ? Color.offscriptAccent : Color.offscriptTextMuted)
                                .symbolEffect(.variableColor.iterative.reversing, options: isCurrent ? .repeating : .nonRepeating)
                        }
                        .padding(14)
                        .background {
                            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.small, style: .continuous)
                                .fill(isCurrent ? Color.offscriptAccentSoft : Color.offscriptCardUtility)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.small, style: .continuous)
                                .stroke(isCurrent ? Color.offscriptAccent.opacity(0.4) : Color.offscriptHairline, lineWidth: isCurrent ? 1.0 : 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Jump to \(chapter.title) at \(Self.timestamp(chapter.startTime))")
                    .accessibilityValue(isCurrent ? "Currently playing" : "")
                }
            }
        }
        .padding(18)
        .offscriptSurface()
    }

    private var currentChapterIndex: Int? {
        let now = timePublisher.currentTime
        for index in chapters.indices.reversed() {
            if chapters[index].startTime <= now {
                return index
            }
        }
        return nil
    }

    private func nextStartTime(after index: Int) -> TimeInterval? {
        let next = index + 1
        guard next < chapters.count else { return nil }
        return chapters[next].startTime
    }

    private func chapterProgress(start: TimeInterval, end: TimeInterval) -> Double {
        let now = timePublisher.currentTime
        guard end > start else { return 0 }
        let raw = (now - start) / (end - start)
        return min(max(raw, 0), 1)
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
    let episodeTitle: String
    @State private var presentedTranscript: EpisodeTranscriptReference?
    @State private var fallbackURL: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Transcript")
                    .font(.offscriptSectionTitle)
                    .foregroundStyle(Color.offscriptTextPrimary)
                Spacer()
                Text("Synced reader")
                    .font(.offscriptMicro.weight(.semibold))
                    .foregroundStyle(Color.offscriptAccent.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.offscriptAccentSoft, in: Capsule())
            }

            VStack(spacing: 10) {
                ForEach(transcripts) { transcript in
                    Button {
                        presentedTranscript = transcript
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "captions.bubble.fill")
                                .font(.body)
                                .foregroundStyle(Color.offscriptAccent)
                                .symbolEffect(.bounce, value: presentedTranscript?.id == transcript.id)

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
                    .accessibilityHint("Opens the synced transcript reader")
                    .contextMenu {
                        Button {
                            fallbackURL = transcript.url
                        } label: {
                            Label("Open in browser", systemImage: "safari")
                        }
                    }
                }
            }
        }
        .padding(18)
        .offscriptSurface()
        .sheet(item: $presentedTranscript) { transcript in
            TranscriptReaderSheet(transcript: transcript, episodeTitle: episodeTitle)
                .presentationDetents([.large])
        }
        .sheet(item: Binding(
            get: { fallbackURL.map { IdentifiableURL(url: $0) } },
            set: { fallbackURL = $0?.url }
        )) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
    }
}

private struct PlayerAtmosphereBackground: View {
    let url: URL?
    @State private var breathe = false
    @State private var meshPhase: CGFloat = 0
    @State private var palette: ArtworkColorExtractor.Palette?

    private let fallbackWarm = Color(red: 0.96, green: 0.52, blue: 0.19)
    private let fallbackCream = Color(red: 0.92, green: 0.84, blue: 0.68)
    private let fallbackPlum = Color(red: 0.30, green: 0.18, blue: 0.32)
    private let fallbackInk = Color(red: 0.04, green: 0.04, blue: 0.06)

    private func animatedMesh(at date: Date) -> some View {
        let t = date.timeIntervalSinceReferenceDate
        let drift = Float(sin(t * 0.18)) * 0.06
        let drift2 = Float(cos(t * 0.21)) * 0.06

        let points: [SIMD2<Float>] = [
            SIMD2(0.0, 0.0),         SIMD2(0.5, 0.0 + drift),  SIMD2(1.0, 0.0),
            SIMD2(0.0 - drift, 0.5), SIMD2(0.5 + drift2, 0.5 + drift), SIMD2(1.0 + drift, 0.5),
            SIMD2(0.0, 1.0),         SIMD2(0.5, 1.0 - drift2), SIMD2(1.0, 1.0)
        ]

        let deep = palette?.deep ?? fallbackInk
        let midA = palette?.midPrimary ?? fallbackPlum
        let midB = palette?.midSecondary ?? fallbackWarm
        let accent = palette?.accent ?? fallbackCream

        let colors: [Color] = [
            deep, midA.opacity(0.55), deep,
            midB.opacity(0.32), accent.opacity(0.18), midB.opacity(0.30),
            deep, deep, deep
        ]

        return MeshGradient(width: 3, height: 3, points: points, colors: colors)
    }

    var body: some View {
        ZStack {
            OffScriptBackgroundView()
                .ignoresSafeArea()

            // Animated mesh gradient — gives the player a living atmosphere
            // even before the blurred artwork loads. Cap to ~12fps; the drift
            // is so subtle the eye can't tell vs 30fps and we save power.
            TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: false)) { context in
                animatedMesh(at: context.date)
                    .ignoresSafeArea()
                    .opacity(0.85)
            }

            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 110)
                        .opacity(0.28)
                        .ignoresSafeArea()
                        .saturation(0.85)
                        .scaleEffect(breathe ? 1.04 : 1.0)
                        .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: breathe)
                        .onAppear { breathe = true }
                        .blendMode(.plusLighter)
                }
            }

            // Bottom wash to anchor controls
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.offscriptBackground.opacity(0.45),
                    Color.offscriptBackground.opacity(0.85),
                    Color.offscriptBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .task(id: url) {
            palette = ArtworkColorExtractor.shared.cached(for: url)
            let extracted = await ArtworkColorExtractor.shared.extract(from: url)
            withAnimation(.easeInOut(duration: 0.8)) {
                palette = extracted
            }
        }
    }
}

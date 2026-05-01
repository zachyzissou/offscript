import OSLog
import SwiftData
import SwiftUI

private let episodeDetailLogger = Logger(subsystem: "com.offscript", category: "EpisodeDetail")

// MARK: - EpisodeDetailView (Tuner spec sheet)
//
// Tuner Blueprint vocabulary — an episode rendered as an instrument spec sheet:
//   ┌── EPISODE · SPECIFICATION ───────────────────────┐
//   │  artwork  HOST tag · DATE tag                     │
//   │           Title (thin display)                    │
//   │           DURATION · POS · STATE readouts         │
//   │           ──── waveform tick rule ────────        │
//   │  PLAY  +QUEUE  ↓DOWNLOAD  ··                      │
//   │  + SUMMARY (mono kicker)                          │
//   │  + CHAPTERS (numbered cassette-track rows)        │
//   │  + TRANSCRIPTS (hairline rows)                    │
//   │  + FEEDBACK (yellow LIKE / dim DISLIKE)           │
//   │  + FROM CHANNEL (hairline channel chip)           │
//   └───────────────────────────────────────────────────┘

struct EpisodeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var player = PlaybackController.shared
    @ObservedObject private var downloadService = DownloadService.shared
    @State private var feedbackGiven: PreferenceSignal.Action? = nil
    let episode: Episode
    let recommendationReason: String?
    let recommendationSignals: [RecommendationSignal]

    init(
        episode: Episode,
        recommendationReason: String? = nil,
        recommendationSignals: [RecommendationSignal] = []
    ) {
        self.episode = episode
        self.recommendationReason = recommendationReason
        self.recommendationSignals = recommendationSignals
    }

    private var progressValue: Double {
        guard let duration = episode.duration, duration > 0 else { return 0 }
        return episode.playedPosition / duration
    }

    private var isCurrentlyPlaying: Bool {
        player.currentEpisode?.id == episode.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TunerInlineBackButton(
                    label: "BACK",
                    accessibilityLabel: "Back to previous screen",
                    accessibilityIdentifier: "EpisodeDetailBackButton"
                ) {
                    dismiss()
                }

                specHeader
                hero
                if progressValue > 0, !episode.isPlayed {
                    progressTickStrip
                }
                actionRow
                recommendationSignalSection
                offlineSection
                summarySection
                // Apple-native AI surfaces — all on-device, all hidden when
                // unavailable for the device/episode. Order intentional:
                // Translation gates the rest if the source language differs
                // from the user's locale; Briefing is the highest-leverage
                // pre-listen surface; SpeechTranscriptionPanel is the
                // power-user fallback for episodes without published transcripts.
                EpisodeTranslationView(episode: episode)
                EpisodeBriefingView(episode: episode)
                SpeechTranscriptionPanel(episode: episode)
                feedbackSection
                channelChip
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
        .accessibilityIdentifier("EpisodeDetailScreen")
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.offscriptStudioBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // ── Spec sheet header ────────────────────────────────────────────
    private var specHeader: some View {
        HStack {
            TunerLabel(text: "EPISODE · SPECIFICATION", color: .offscriptSignalYellow)
            Spacer()
            TunerLabel(text: "REC \(specId)")
        }
        .padding(.bottom, 4)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .bottom
        )
    }

    private var specId: String {
        // Stable 6-char id for the row strip — deterministic from episode UUID.
        let id = episode.id.uuidString
        let trimmed = id.replacingOccurrences(of: "-", with: "")
        return String(trimmed.prefix(6)).uppercased()
    }

    // ── Hero ─────────────────────────────────────────────────────────
    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                OffScriptArtworkView(
                    url: episode.artworkURL ?? episode.podcast.artworkURL,
                    cornerRadius: 3
                )
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        // Podcast title in info-cyan per the function-coded color
                        // system. Was record-red — same bug class fixed across
                        // QueueLeadStrip and PlayerView in 2.3.2 / 2.3.4.
                        TunerLabel(text: episode.podcast.title.uppercased(),
                                   color: .offscriptFnInfo, size: 9)
                        if let dateLabel {
                            TunerLabel(text: dateLabel.uppercased(),
                                       color: .offscriptSoftPaper, size: 9)
                        }
                    }
                    Text(episode.title)
                        .font(.system(size: 22, weight: .light, design: .default))
                        .tracking(0)
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }

            // Three-up readout — like an instrument cluster band
            HStack(alignment: .bottom, spacing: 14) {
                TunerReadout(
                    tag: "DUR",
                    tagColor: .offscriptFnMode,
                    value: durationLabel,
                    size: .md
                )
                TunerReadout(
                    tag: "POS",
                    tagColor: .offscriptSignalYellow,
                    value: "\(Int(progressValue * 100))",
                    unit: "%",
                    size: .md
                )
                TunerReadout(
                    tag: "STATE",
                    tagColor: .offscriptFnInfo,
                    value: stateLabel,
                    size: .sm
                )
            }
        }
    }

    // ── Progress tick strip ──────────────────────────────────────────
    private var progressTickStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Inline Tuner progress rail — signal-yellow fill on hairline
            // track. Was OffScriptProgressBar; inlined when AppTheme dropped
            // legacy chrome.
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
            HStack {
                TunerLabel(text: timeRemaining)
                Spacer()
                TunerLabel(text: "RESUME AVAILABLE", color: .offscriptSignalYellow)
            }
        }
    }

    // ── Action row ───────────────────────────────────────────────────
    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                PlaybackController.shared.play(episode, in: modelContext)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .accessibilityHidden(true)
                    Text(isCurrentlyPlaying ? "NOW PLAYING"
                         : episode.playedPosition > 0 ? "RESUME" : "PLAY")
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Color.offscriptStudioBlack)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isCurrentlyPlaying ? Color.offscriptFnMode : Color.offscriptSignalYellow)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isCurrentlyPlaying)
            .accessibilityLabel(
                isCurrentlyPlaying
                    ? "Now playing \(episode.title)"
                    : (episode.playedPosition > 0 ? "Resume \(episode.title)" : "Play \(episode.title)")
            )

            Button {
                withAnimation {
                    do { try QueueService.add(episode, in: modelContext) }
                    catch { episodeDetailLogger.error("Queue add failed: \(error.localizedDescription, privacy: .public)") }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: episode.isQueued ? "checkmark" : "plus")
                        .font(.system(size: 9))
                        .accessibilityHidden(true)
                    Text(episode.isQueued ? "QUEUED" : "QUEUE")
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(episode.isQueued ? Color.offscriptSoftPaper : Color.offscriptPaperWhite)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(episode.isQueued)
            .accessibilityLabel(episode.isQueued ? "Already queued" : "Add \(episode.title) to queue")

            DownloadButton(episode: episode)

            Spacer()
        }
    }

    // ── Recommendation signal ───────────────────────────────────────
    @ViewBuilder
    private var recommendationSignalSection: some View {
        if let recommendationReason, !recommendationReason.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                TunerLabel(text: "WHY THIS · LOCAL SIGNAL", color: .offscriptSignalYellow)
                TunerTag(text: recommendationReason, color: .offscriptSignalYellow, dim: true, wraps: true)
                RecommendationSignalTraceView(signals: recommendationSignals)
                Text("This comes from local listening, queue, and preference signals on this device.")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(Color.offscriptPaperWhite.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                Rectangle().fill(Color.offscriptHairline).frame(height: 1),
                alignment: .top
            )
            .accessibilityIdentifier("RecommendationSignalSection")
        }
    }

    // ── Offline trust ────────────────────────────────────────────────
    @ViewBuilder
    private var offlineSection: some View {
        if episode.downloadState != .notDownloaded || episode.localFileURL != nil {
            VStack(alignment: .leading, spacing: 8) {
                TunerLabel(text: "OFFLINE · \(offlineStateLabel)", color: offlineStateColor)
                Text(offlineDetail)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(Color.offscriptPaperWhite.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                if episode.downloadState == .failed {
                    Button {
                        downloadService.startDownload(for: episode)
                    } label: {
                        TunerLabel(text: "↻ RETRY DOWNLOAD", color: .offscriptFnRecord, size: 10)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry download for \(episode.title)")
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

    private var offlineStateLabel: String {
        switch episode.downloadState {
        case .notDownloaded:
            return "STREAM ONLY"
        case .queued:
            return "QUEUED"
        case .downloading:
            return "\(Int((episode.downloadProgress * 100).rounded()))%"
        case .downloaded:
            return "READY"
        case .failed:
            return "FAILED"
        }
    }

    private var offlineStateColor: Color {
        switch episode.downloadState {
        case .downloaded:
            return .offscriptFnMode
        case .failed:
            return .offscriptFnRecord
        case .queued, .downloading:
            return .offscriptSignalYellow
        case .notDownloaded:
            return .offscriptSoftPaper
        }
    }

    private var offlineDetail: String {
        switch episode.downloadState {
        case .notDownloaded:
            return "This episode will stream unless you save it first."
        case .queued:
            return "Waiting for an open download slot. Downloads continue in the background."
        case .downloading:
            return "Saving for offline playback. Progress is checkpointed without hammering the local store."
        case .downloaded:
            return "Saved on this device. Playback will use the local file when available."
        case .failed:
            return episode.downloadErrorMessage ?? "The last offline save failed. Retry when connected."
        }
    }

    // ── Summary ──────────────────────────────────────────────────────
    @ViewBuilder
    private var summarySection: some View {
        if let summary = episode.summary, !summary.strippingHTML.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                TunerLabel(text: "SUMMARY", color: .offscriptSignalYellow)
                Text(summary.strippingHTML)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                Rectangle().fill(Color.offscriptHairline).frame(height: 1),
                alignment: .top
            )
        }
    }

    // ── Feedback ─────────────────────────────────────────────────────
    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TunerLabel(text: "FEEDBACK · ON DEVICE", color: .offscriptSignalYellow)
            Text("Help OffScript learn what you like.")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(Color.offscriptPaperWhite)

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if register(.like) {
                            feedbackGiven = .like
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: feedbackGiven == .like ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.system(size: 10))
                            .accessibilityHidden(true)
                        Text("LIKE")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(feedbackGiven == .like ? Color.offscriptStudioBlack : Color.offscriptSignalYellow)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(feedbackGiven == .like ? Color.offscriptSignalYellow : Color.clear)
                    .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(feedbackGiven != nil)
                .accessibilityLabel(
                    feedbackGiven == .like
                        ? "Liked"
                        : (feedbackGiven == .lessLikeThis
                            ? "Feedback already given: marked not for me"
                            : "Like \(episode.title)")
                )

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if register(.lessLikeThis) {
                            feedbackGiven = .lessLikeThis
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: feedbackGiven == .lessLikeThis ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .font(.system(size: 10))
                            .accessibilityHidden(true)
                        Text("NOT FOR ME")
                    }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.offscriptSoftPaper)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(feedbackGiven != nil)
                .accessibilityLabel(
                    feedbackGiven == .lessLikeThis
                        ? "Marked not for me"
                        : (feedbackGiven == .like
                            ? "Feedback already given: liked"
                            : "Not for me — show fewer episodes like \(episode.title)")
                )

                Spacer()
            }

            if let feedback = feedbackGiven {
                Text(feedback == .like ? "GOT IT — MORE LIKE THIS COMING" : "NOTED — WE'LL ADJUST YOUR FEED")
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color.offscriptSoftPaper)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .sensoryFeedback(.success, trigger: feedbackGiven != nil)
    }

    // ── Channel chip ─────────────────────────────────────────────────
    private var channelChip: some View {
        NavigationLink {
            PodcastDetailView(podcast: episode.podcast)
        } label: {
            HStack(spacing: 12) {
                OffScriptArtworkView(url: episode.podcast.artworkURL, cornerRadius: 3)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    TunerLabel(text: "FROM CHANNEL")
                    Text(episode.podcast.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.offscriptSoftPaper)
            }
            .padding(10)
            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var dateLabel: String? {
        let date = episode.pubDate
        guard date > .distantPast else { return nil }
        let f = DateFormatter()
        f.dateFormat = "MM · dd · yy"
        return f.string(from: date)
    }

    private var durationLabel: String {
        if let duration = episode.duration {
            return EpisodeDurationFormatter.short(duration).uppercased()
        }
        return "—"
    }

    private var stateLabel: String {
        if episode.isPlayed { return "DONE" }
        if episode.playedPosition > 0 { return "RESUME" }
        if episode.isQueued { return "QUEUED" }
        return "READY"
    }

    private var timeRemaining: String {
        guard let duration = episode.duration else { return "IN PROGRESS" }
        let remaining = max(0, duration - episode.playedPosition)
        return "\(EpisodeDurationFormatter.short(remaining).uppercased()) LEFT"
    }

    private func register(_ action: PreferenceSignal.Action) -> Bool {
        do {
            try PreferenceFeedbackService.register(action, for: episode, in: modelContext)
            return true
        } catch {
            return false
        }
    }
}

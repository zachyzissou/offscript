import SwiftData
import SwiftUI

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
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var player = PlaybackController.shared
    @State private var feedbackGiven: PreferenceSignal.Action? = nil
    let episode: Episode

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
                specHeader
                hero
                if progressValue > 0, !episode.isPlayed {
                    progressTickStrip
                }
                actionRow
                summarySection
                feedbackSection
                channelChip
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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
                        TunerTag(text: episode.podcast.title, color: .offscriptFnRecord)
                        if let dateLabel {
                            TunerTag(text: dateLabel, color: .offscriptFnInfo, dim: true)
                        }
                    }
                    Text(episode.title)
                        .font(.system(size: 22, weight: .light, design: .default))
                        .tracking(-0.4)
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
            OffScriptProgressBar(value: progressValue, height: 2)
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
                    Image(systemName: "play.fill").font(.system(size: 10))
                    Text(isCurrentlyPlaying ? "NOW PLAYING"
                         : episode.playedPosition > 0 ? "RESUME" : "PLAY")
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Color.offscriptStudioBlack)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isCurrentlyPlaying ? Color.offscriptFnMode : Color.offscriptSignalYellow)
            }
            .buttonStyle(.plain)
            .disabled(isCurrentlyPlaying)

            Button {
                withAnimation { try? QueueService.add(episode, in: modelContext) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: episode.isQueued ? "checkmark" : "plus")
                        .font(.system(size: 9))
                    Text(episode.isQueued ? "QUEUED" : "QUEUE")
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(episode.isQueued ? Color.offscriptSoftPaper : Color.offscriptPaperWhite)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(Capsule().stroke(Color.offscriptHairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(episode.isQueued)

            // Note: download / chapter / transcript surfaces are gated to a
            // future build — the origin/main Episode model doesn't expose them
            // yet. Reintroduce alongside DownloadService / EpisodeChapter.

            Spacer()
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
                        register(.like); feedbackGiven = .like
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: feedbackGiven == .like ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.system(size: 10))
                        Text("LIKE")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(feedbackGiven == .like ? Color.offscriptStudioBlack : Color.offscriptSignalYellow)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(feedbackGiven == .like ? Color.offscriptSignalYellow : Color.clear)
                    .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(feedbackGiven != nil)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        register(.lessLikeThis); feedbackGiven = .lessLikeThis
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: feedbackGiven == .lessLikeThis ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .font(.system(size: 10))
                        Text("NOT FOR ME")
                    }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.offscriptSoftPaper)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(feedbackGiven != nil)

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

    private func register(_ action: PreferenceSignal.Action) {
        modelContext.insert(PreferenceSignal(action: action, episode: episode))
        try? modelContext.save()
        // origin/main doesn't have TasteProfileService — feedback signals are
        // persisted but not yet reprocessed into a refreshed taste profile.
    }
}

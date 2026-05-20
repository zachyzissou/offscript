import SwiftUI

/// Tuner-direction MiniPlayer — flat-black panel with a single hairline at top,
/// signal-yellow play key (sharp 3pt corners, not circle), mono caption, and
/// a thin signal-yellow progress rail. No floating card, no shadow — it docks
/// flush to the bottom of the screen as a strip on the OLED field.
struct MiniPlayer: View {
    @ObservedObject private var player = PlaybackController.shared

    var body: some View {
        if let episode = player.currentEpisode {
            VStack(spacing: 0) {
                // Hairline rule above the strip — the panel divider.
                Rectangle()
                    .fill(Color.offscriptHairline)
                    .frame(height: 1)

                // Progress rail — signal-yellow fill on a hairline track.
                // 2pt height (1pt was visually invisible against the bg).
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

                HStack(spacing: 12) {
                    // Channel readout — TunerLabel mono channel number is the
                    // visual hook the rest of the Tuner UI uses.
                    Button {
                        player.isPlayerPresented = true
                    } label: {
                        HStack(spacing: 12) {
                            // Sharp-cornered artwork, hairline border — cassette tile vocab
                            OffScriptArtworkView(
                                url: episode.artworkURL ?? episode.podcast.artworkURL,
                                cornerRadius: 3
                            )
                            .frame(width: 44, height: 44)
                            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    // Surface a playback fault directly on
                                    // the MiniPlayer status badge — without
                                    // this, a stream stall on cellular reads
                                    // as "● PLAYING" until the user opens
                                    // the full player and sees the error
                                    // strip.
                                    TunerLabel(
                                        text: statusLabel,
                                        color: statusColor,
                                        size: 8
                                    )
                                    TunerLabel(
                                        text: episode.podcast.title.uppercased(),
                                        color: .offscriptFnInfo,
                                        size: 8
                                    )
                                    .lineLimit(1)
                                }

                                Text(episode.title)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(Color.offscriptPaperWhite)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.tunerPress)
                    .accessibilityLabel("Open player")
                    .accessibilityHint("Expand the now-playing screen for \(episode.title)")

                    // Skip-back-15 — hairline transport key. Lives next to the
                    // play key so the most-frequent in-app interactions
                    // (rewind a phrase, skip an ad) don't require opening the
                    // full player. Hidden when there's no real duration so
                    // it doesn't sit dead on a fresh load.
                    if player.duration > 0 {
                        Button {
                            player.seek(by: -15)
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.offscriptPaperWhite)
                                .frame(width: 36, height: 36)
                                .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.tunerPress)
                        .accessibilityLabel("Skip back 15 seconds")
                    }

                    // Tuner play key — sharp signal-yellow square (instrument key),
                    // 44pt hit target per HIG, 36pt visible disc for visual rhythm.
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.offscriptStudioBlack)
                            .frame(width: 36, height: 36)
                            .background(Color.offscriptSignalYellow)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.tunerPress)
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                    // Skip-forward-30 — same vocabulary as skip-back. Used for
                    // ad skipping; 30s is the standard podcast skip-fwd amount
                    // (Overcast / Pocket Casts / Apple Podcasts all default to
                    // it). Mirrors PlayerView's transport row.
                    if player.duration > 0 {
                        Button {
                            player.seek(by: 30)
                        } label: {
                            Image(systemName: "goforward.30")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.offscriptPaperWhite)
                                .frame(width: 36, height: 36)
                                .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.tunerPress)
                        .accessibilityLabel("Skip ahead 30 seconds")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.offscriptStudioBlack)
            }
        }
    }

    /// MiniPlayer status eyebrow: error wins over play state so a
    /// cellular stall doesn't read as `● PLAYING` until the user opens
    /// the full player and sees the error strip.
    private var statusLabel: String {
        if player.playbackError != nil { return "● ERROR" }
        return player.isPlaying ? "● PLAYING" : "❙❙ PAUSED"
    }

    private var statusColor: Color {
        if player.playbackError != nil { return .offscriptFnRecord }
        return player.isPlaying ? .offscriptFnMode : .offscriptSoftPaper
    }

    private var progressValue: Double {
        guard player.duration > 0 else { return 0 }
        return player.currentTime / player.duration
    }
}

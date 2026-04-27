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
                GeometryReader { proxy in
                    let clamped = min(max(progressValue, 0), 1)
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.offscriptHairline)
                        Rectangle()
                            .fill(Color.offscriptSignalYellow)
                            .frame(width: proxy.size.width * clamped)
                    }
                }
                .frame(height: 1)

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
                                    TunerLabel(
                                        text: player.isPlaying ? "● PLAYING" : "❙❙ PAUSED",
                                        color: player.isPlaying ? .offscriptFnMode : .offscriptSoftPaper,
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
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open player")
                    .accessibilityHint("Expand the now-playing screen for \(episode.title)")

                    // Tuner play key — sharp signal-yellow square (instrument key),
                    // 44pt hit target per HIG, 36pt visible disc for visual rhythm.
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 36, height: 36)
                            .background(Color.offscriptSignalYellow)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.offscriptStudioBlack)
            }
        }
    }

    private var progressValue: Double {
        guard player.duration > 0 else { return 0 }
        return player.currentTime / player.duration
    }
}

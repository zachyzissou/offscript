import SwiftUI

struct MiniPlayer: View {
    @ObservedObject private var player = PlaybackController.shared
    @ObservedObject private var timePublisher = PlaybackTimePublisher.shared

    var body: some View {
        if let episode = player.currentEpisode {
            HStack(spacing: 12) {
                // Artwork + text — tapping opens the full player
                Button {
                    player.isPlayerPresented = true
                } label: {
                    HStack(spacing: 12) {
                        OffScriptArtworkView(
                            url: episode.artworkURL ?? episode.podcast.artworkURL,
                            cornerRadius: OffScriptTheme.Radius.small
                        )
                        .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(episode.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.offscriptTextPrimary)
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                Text(episode.podcast.title)
                                    .font(.offscriptMeta)
                                    .foregroundStyle(Color.offscriptTextMuted)
                                    .lineLimit(1)

                                if timePublisher.duration > 0 {
                                    Text("•")
                                        .font(.offscriptMeta)
                                        .foregroundStyle(Color.offscriptTextMuted)
                                    Text(remainingTimeLabel)
                                        .font(.offscriptMeta)
                                        .foregroundStyle(Color.offscriptTextMuted)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open player")
                .accessibilityHint("Expand the now playing screen for \(episode.title)")

                // Play/pause — separate button
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 38, height: 38)
                        .background(Color.offscriptAccent)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(flexibility: .soft), trigger: player.isPlaying)
                .accessibilityLabel(player.isPlaying ? "Pause playback" : "Resume playback")
                .accessibilityValue(episode.title)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .offscriptSurface(radius: OffScriptTheme.Radius.medium)
            // Progress bar overlaid at top edge, clipped by card shape
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    let clamped = min(max(progressValue, 0), 1)
                    Rectangle()
                        .fill(Color.offscriptAccent)
                        .frame(width: proxy.size.width * clamped, height: 5)
                }
                .frame(height: 5)
            }
            .clipShape(RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous))
            .padding(.horizontal, 12)
            .shadow(color: Color.black.opacity(0.22), radius: 16, y: 8)
        }
    }

    private var progressValue: Double {
        guard timePublisher.duration > 0 else { return 0 }
        return timePublisher.currentTime / timePublisher.duration
    }

    private var remainingTimeLabel: String {
        let remaining = max(0, timePublisher.duration - timePublisher.currentTime)
        return "\(EpisodeDurationFormatter.short(remaining)) left"
    }
}

import SwiftUI

struct MiniPlayer: View {
    @ObservedObject private var player = PlaybackController.shared

    var body: some View {
        if let episode = player.currentEpisode {
            VStack(spacing: 0) {
                OffScriptProgressBar(value: progressValue)

                HStack(spacing: 12) {
                    Button {
                        player.isPlayerPresented = true
                    } label: {
                        HStack(spacing: 12) {
                            OffScriptArtworkView(
                                url: episode.artworkURL ?? episode.podcast.artworkURL,
                                cornerRadius: OffScriptTheme.Radius.small
                            )
                            .frame(width: 48, height: 48)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(episode.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.offscriptTextPrimary)
                                    .lineLimit(1)

                                Text(episode.podcast.title)
                                    .font(.offscriptMeta)
                                    .foregroundStyle(Color.offscriptTextMuted)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open player")
                    .accessibilityHint("Expand the now playing screen for \(episode.title)")

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
                    .accessibilityLabel(player.isPlaying ? "Pause playback" : "Resume playback")
                    .accessibilityValue(episode.title)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .offscriptUtilitySurface(radius: OffScriptTheme.Radius.medium)
            .padding(.horizontal, 12)
            .shadow(color: Color.black.opacity(0.2), radius: 14, y: 8)
        }
    }

    private var progressValue: Double {
        guard player.duration > 0 else { return 0 }
        return player.currentTime / player.duration
    }
}

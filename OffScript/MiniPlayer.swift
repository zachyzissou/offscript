import SwiftUI

struct MiniPlayer: View {
    @ObservedObject private var player = PlaybackController.shared

    var body: some View {
        if let episode = player.currentEpisode {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Artwork with progress ring
                    ZStack {
                        Circle()
                            .stroke(Color.offscriptProgressTrack, lineWidth: 3)
                            .frame(width: 54, height: 54)

                        Circle()
                            .trim(from: 0, to: progressValue)
                            .stroke(
                                Color.offscriptAccent,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .frame(width: 54, height: 54)
                            .rotationEffect(.degrees(-90))

                        OffScriptArtworkView(
                            url: episode.artworkURL ?? episode.podcast.artworkURL,
                            cornerRadius: 22
                        )
                        .frame(width: 44, height: 44)
                    }

                    VStack(alignment: .leading, spacing: 3) {
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
            .contentShape(Rectangle())
            .onTapGesture {
                player.isPlayerPresented = true
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Now playing: \(episode.title)")
            .accessibilityHint("Tap to expand the player")
            .offscriptSurface(radius: OffScriptTheme.Radius.medium)
            .padding(.horizontal, 12)
            .shadow(color: Color.black.opacity(0.22), radius: 16, y: 8)
        }
    }

    private var progressValue: Double {
        guard player.duration > 0 else { return 0 }
        return player.currentTime / player.duration
    }
}

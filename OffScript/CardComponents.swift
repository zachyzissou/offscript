import SwiftData
import SwiftUI

// MARK: - Shared Episode Card Components
// Unified card system: EpisodeVerticalCard (rails), EpisodeCompactCard (lists), HeroEpisodeCard (lead).

// MARK: - EpisodeVerticalCard

/// Card for horizontal scroll rails. Fixed 200pt width, artwork on top.
/// Used in: Home rails, Library "Fresh Episodes" rail, Library "Continue Listening" rail.
struct EpisodeVerticalCard: View {
    @Environment(\.modelContext) private var modelContext

    let episode: Episode
    var explanationTag: String? = nil
    var onTap: (() -> Void)? = nil

    @State private var navigateToDetail = false

    private var progressValue: Double {
        guard let duration = episode.duration, duration > 0 else { return 0 }
        return episode.playedPosition / duration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Artwork zone — tappable for navigation
            Button {
                if let onTap {
                    onTap()
                } else {
                    navigateToDetail = true
                }
            } label: {
                OffScriptArtworkView(
                    url: episode.artworkURL ?? episode.podcast.artworkURL,
                    cornerRadius: 0
                )
                .frame(width: 200, height: 150)
            }
            .buttonStyle(.plain)

            // Text + buttons zone
            VStack(alignment: .leading, spacing: 8) {
                if let tag = explanationTag {
                    OffScriptSmartExplanationTag(episodeID: episode.id, fallback: tag)
                }

                Text(episode.podcast.title.uppercased())
                    .font(.offscriptMicro.weight(.semibold))
                    .foregroundStyle(Color.offscriptAccent)
                    .lineLimit(1)

                Button {
                    if let onTap {
                        onTap()
                    } else {
                        navigateToDetail = true
                    }
                } label: {
                    Text(episode.title)
                        .font(.offscriptCardTitle)
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)

                Text(metadata)
                    .font(.offscriptMeta)
                    .foregroundStyle(Color.offscriptTextMuted)

                if progressValue > 0 {
                    OffScriptProgressBar(value: progressValue, height: 4)
                }

                HStack(spacing: 8) {
                    // Play circle
                    Button {
                        PlaybackController.shared.play(episode, in: modelContext)
                    } label: {
                        Image(systemName: playIcon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isCurrentlyPlaying ? Color.offscriptTextPrimary : .black)
                            .frame(width: 36, height: 36)
                            .background(isCurrentlyPlaying ? Color.offscriptFillLight : Color.offscriptAccent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCurrentlyPlaying ? "Pause" : "Play \(episode.title)")

                    // Queue circle
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            try? QueueService.add(episode, in: modelContext)
                        }
                    } label: {
                        Image(systemName: episode.isQueued ? "checkmark" : "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.offscriptTextPrimary)
                            .frame(width: 36, height: 36)
                            .background(Color.offscriptFillLight)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(episode.isQueued)
                    .accessibilityLabel(episode.isQueued ? "Already queued" : "Add to queue")

                    Spacer()
                }
            }
            .padding(12)
        }
        .frame(width: 200, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.offscriptCardRaised, Color.offscriptCardUtility],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                .stroke(Color.offscriptHairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 12, y: 6)
        .navigationDestination(isPresented: $navigateToDetail) {
            EpisodeDetailView(episode: episode)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(episode.title) from \(episode.podcast.title)\(explanationTag.map { ". \($0)" } ?? "")")
    }

    private var metadata: String {
        let dateString = episode.pubDate.formatted(date: .abbreviated, time: .omitted)
        if episode.playedPosition > 0, let duration = episode.duration {
            let remaining = max(0, duration - episode.playedPosition)
            return "\(dateString) · \(EpisodeDurationFormatter.short(remaining)) left"
        }
        if let duration = episode.duration {
            return "\(dateString) · \(EpisodeDurationFormatter.short(duration))"
        }
        return dateString
    }

    private var isCurrentlyPlaying: Bool {
        PlaybackController.shared.currentEpisode?.id == episode.id && PlaybackController.shared.isPlaying
    }

    private var playIcon: String {
        isCurrentlyPlaying ? "pause.fill" : "play.fill"
    }
}

// MARK: - EpisodeCompactCard

/// Card for vertical lists and detail pages. Full width, horizontal layout.
/// Used in: Queue items, podcast detail episode list, search results.
struct EpisodeCompactCard: View {
    @Environment(\.modelContext) private var modelContext

    let episode: Episode
    var onTap: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    var rank: Int? = nil
    var showPodcastTitle: Bool = true

    @State private var navigateToDetail = false

    var body: some View {
        HStack(spacing: 14) {
            if let rank {
                Text("\(rank)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .frame(width: 34, height: 34)
                    .background(Color.offscriptFillLight)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color.offscriptHairline, lineWidth: 1)
                    )
            }

            Button {
                if let onTap {
                    onTap()
                } else {
                    navigateToDetail = true
                }
            } label: {
                OffScriptArtworkView(
                    url: episode.artworkURL ?? episode.podcast.artworkURL,
                    cornerRadius: OffScriptTheme.Radius.small
                )
                .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)

            Button {
                if let onTap {
                    onTap()
                } else {
                    navigateToDetail = true
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    if showPodcastTitle {
                        Text(episode.podcast.title.uppercased())
                            .font(.offscriptMicro.weight(.semibold))
                            .foregroundStyle(Color.offscriptAccent)
                            .lineLimit(1)
                    }

                    Text(episode.title)
                        .font(.offscriptCardTitle)
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(metadata)
                        .font(.offscriptMeta)
                        .foregroundStyle(Color.offscriptTextMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Play circle
            Button {
                PlaybackController.shared.play(episode, in: modelContext)
            } label: {
                Image(systemName: playIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isCurrentlyPlaying ? Color.offscriptTextPrimary : .black)
                    .frame(width: 36, height: 36)
                    .background(isCurrentlyPlaying ? Color.offscriptFillLight : Color.offscriptAccent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCurrentlyPlaying ? "Pause" : "Play \(episode.title)")

            if let onRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.offscriptTextMuted)
                        .frame(width: 28, height: 28)
                        .background(Color.offscriptFillSubtle)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(episode.title)")
            }
        }
        .padding(16)
        .offscriptUtilitySurface()
        .navigationDestination(isPresented: $navigateToDetail) {
            EpisodeDetailView(episode: episode)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(episode.title) from \(episode.podcast.title)")
    }

    private var metadata: String {
        let dateString = episode.pubDate.formatted(date: .abbreviated, time: .omitted)
        if episode.playedPosition > 0, let duration = episode.duration {
            let remaining = max(0, duration - episode.playedPosition)
            return "\(dateString) · \(EpisodeDurationFormatter.short(remaining)) left"
        }
        if let duration = episode.duration {
            return "\(dateString) · \(EpisodeDurationFormatter.short(duration))"
        }
        return dateString
    }

    private var isCurrentlyPlaying: Bool {
        PlaybackController.shared.currentEpisode?.id == episode.id && PlaybackController.shared.isPlaying
    }

    private var playIcon: String {
        isCurrentlyPlaying ? "pause.fill" : "play.fill"
    }
}

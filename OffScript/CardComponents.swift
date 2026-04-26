import SwiftData
import SwiftUI

/// Value-typed wrapper used as the `NavigationLink(value:)` payload for an
/// `Episode`. SwiftData @Model classes are reference types and can become
/// stale across navigation events; carrying the stable UUID instead lets the
/// destination re-fetch from the model context, which is both safer and
/// dramatically faster than mounting one navigationDestination per card.
struct EpisodeNavigation: Hashable {
    let id: UUID
    init(episode: Episode) { self.id = episode.id }
}

extension View {
    /// Registers a single Episode-typed destination on the enclosing
    /// `NavigationStack`. Call this once at the root of each tab's stack so
    /// every card-driven push routes through the same handler instead of
    /// mounting per-card destinations (which is what caused the
    /// podcast-detail tap-to-freeze on devices with large libraries).
    func registerEpisodeNavigation() -> some View {
        navigationDestination(for: EpisodeNavigation.self) { nav in
            EpisodeNavigationDestination(navigation: nav)
        }
    }
}

private struct EpisodeNavigationDestination: View {
    @Environment(\.modelContext) private var modelContext
    let navigation: EpisodeNavigation

    var body: some View {
        let id = navigation.id
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.id == id }
        )
        if let episode = (try? modelContext.fetch(descriptor))?.first {
            EpisodeDetailView(episode: episode)
        } else {
            ContentUnavailableView(
                "Episode not found",
                systemImage: "waveform.slash",
                description: Text("It may have been removed from the feed.")
            )
        }
    }
}

// MARK: - Shared Episode Card Components
// Unified card system: EpisodeVerticalCard (rails), EpisodeCompactCard (lists), HeroEpisodeCard (lead).

// MARK: - EpisodeVerticalCard

/// Card for horizontal scroll rails. Fixed 200pt width, artwork on top.
/// Used in: Home rails, Library "Fresh Episodes" rail, Library "Continue Listening" rail.
struct EpisodeVerticalCard: View, Equatable {
    @Environment(\.modelContext) private var modelContext

    let episode: Episode
    var explanationTag: String? = nil
    var onTap: (() -> Void)? = nil

    /// SwiftUI's diff: two cards are "equal" (skip-redraw eligible) when the
    /// underlying episode identity, progress, and queue/play flags match.
    /// That's what changes most often during a session — anything else (title,
    /// summary, podcast metadata) is effectively stable.
    static func == (lhs: EpisodeVerticalCard, rhs: EpisodeVerticalCard) -> Bool {
        lhs.episode.id == rhs.episode.id
            && lhs.episode.playedPosition == rhs.episode.playedPosition
            && lhs.episode.isPlayed == rhs.episode.isPlayed
            && lhs.episode.isQueued == rhs.episode.isQueued
            && lhs.episode.downloadProgress == rhs.episode.downloadProgress
            && lhs.explanationTag == rhs.explanationTag
    }

    private var progressValue: Double {
        guard let duration = episode.duration, duration > 0 else { return 0 }
        return episode.playedPosition / duration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Artwork zone — tappable for navigation. Uses a value-based
            // NavigationLink so the destination is registered once on the
            // enclosing stack rather than per-card.
            tapTarget {
                OffScriptArtworkView(
                    url: episode.artworkURL ?? episode.podcast.artworkURL,
                    cornerRadius: 0
                )
                .frame(width: 200, height: 150)
            }

            // Text + buttons zone
            VStack(alignment: .leading, spacing: 8) {
                if let tag = explanationTag {
                    OffScriptExplanationTag(text: tag)
                }

                Text(episode.podcast.title.uppercased())
                    .font(.offscriptMicro.weight(.semibold))
                    .foregroundStyle(Color.offscriptAccent)
                    .lineLimit(1)

                tapTarget {
                    Text(episode.title)
                        .font(.offscriptCardTitle)
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

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

                    Menu {
                        Button {
                            registerSignal(.moreLikeThis)
                        } label: {
                            Label("More like this", systemImage: "arrow.up.heart")
                        }
                        Button {
                            registerSignal(.like)
                        } label: {
                            Label("Like", systemImage: "hand.thumbsup")
                        }
                        Button(role: .destructive) {
                            registerSignal(.lessLikeThis)
                        } label: {
                            Label("Less like this", systemImage: "hand.thumbsdown")
                        }
                        Button(role: .destructive) {
                            registerSignal(.notInterested)
                        } label: {
                            Label("Not interested", systemImage: "xmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.offscriptTextMuted)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Adjust this recommendation")
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(episode.title) from \(episode.podcast.title)\(explanationTag.map { ". \($0)" } ?? "")")
    }

    @ViewBuilder
    private func tapTarget<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if let onTap {
            Button {
                onTap()
            } label: { content() }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: EpisodeNavigation(episode: episode)) {
                content()
            }
            .buttonStyle(.plain)
        }
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

    private func registerSignal(_ action: PreferenceSignal.Action) {
        modelContext.insert(PreferenceSignal(action: action, episode: episode))
        try? modelContext.save()
        TelemetryService.track(
            "preference_signal",
            metadata: ["action": "\(action)", "source": "rail_card", "episode": episode.title],
            in: modelContext
        )
        // Refresh the user's taste profile so future recommendations adjust right away.
        try? TasteProfileService.refresh(in: modelContext)
    }
}

// MARK: - EpisodeCompactCard

/// Card for vertical lists and detail pages. Full width, horizontal layout.
/// Used in: Queue items, podcast detail episode list, search results.
struct EpisodeCompactCard: View, Equatable {
    @Environment(\.modelContext) private var modelContext

    let episode: Episode
    var onTap: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    var rank: Int? = nil
    var showPodcastTitle: Bool = true

    static func == (lhs: EpisodeCompactCard, rhs: EpisodeCompactCard) -> Bool {
        lhs.episode.id == rhs.episode.id
            && lhs.episode.playedPosition == rhs.episode.playedPosition
            && lhs.episode.isPlayed == rhs.episode.isPlayed
            && lhs.episode.isQueued == rhs.episode.isQueued
            && lhs.episode.downloadProgress == rhs.episode.downloadProgress
            && lhs.rank == rhs.rank
            && lhs.showPodcastTitle == rhs.showPodcastTitle
    }

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

            tapTarget {
                OffScriptArtworkView(
                    url: episode.artworkURL ?? episode.podcast.artworkURL,
                    cornerRadius: OffScriptTheme.Radius.small
                )
                .frame(width: 56, height: 56)
            }

            tapTarget {
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(episode.title) from \(episode.podcast.title)")
    }

    /// One value-based NavigationLink per card; the destination is registered
    /// once on the enclosing NavigationStack via `.navigationDestination(for:)`.
    /// This avoids creating one navigationDestination modifier per row, which
    /// stalls the main thread when a podcast has dozens of episodes.
    @ViewBuilder
    private func tapTarget<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if let onTap {
            Button {
                onTap()
            } label: { content() }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: EpisodeNavigation(episode: episode)) {
                content()
            }
            .buttonStyle(.plain)
        }
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

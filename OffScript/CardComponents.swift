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

    /// Tuner OLED rail card — square hairline-bordered artwork at top, mono
    /// uppercase show name (cyan) above thin sans episode title, mono date
    /// stamp, hairline progress strip when in progress. Buttons are square
    /// hairline cells: signal-yellow play key + outlined plus, ellipsis on
    /// the right. No gradient, no drop shadow.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tapTarget {
                OffScriptArtworkView(
                    url: episode.artworkURL ?? episode.podcast.artworkURL,
                    cornerRadius: 0
                )
                .frame(width: 200, height: 150)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let tag = explanationTag {
                    TTagPill(label: tag, tone: .signal)
                }

                Text(episode.podcast.title.uppercased())
                    .font(.offscriptTagLabel)
                    .tracking(1.4)
                    .foregroundStyle(Color.offscriptAccentSecondary)
                    .lineLimit(1)

                tapTarget {
                    Text(episode.title)
                        .font(.offscriptCardTitle)
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Text(metadata.uppercased())
                    .font(.offscriptMicro)
                    .tracking(1.2)
                    .foregroundStyle(Color.offscriptTextMuted)

                if progressValue > 0 {
                    OffScriptProgressBar(value: progressValue, height: 1)
                }

                HStack(spacing: 6) {
                    Button {
                        PlaybackController.shared.play(episode, in: modelContext)
                    } label: {
                        Image(systemName: playIcon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isCurrentlyPlaying ? Color.offscriptTextPrimary : .black)
                            .frame(width: 32, height: 32)
                            .background(isCurrentlyPlaying ? Color.offscriptFillLight : Color.offscriptAccent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCurrentlyPlaying ? "Pause" : "Play \(episode.title)")

                    Button {
                        try? QueueService.add(episode, in: modelContext)
                    } label: {
                        Image(systemName: episode.isQueued ? "checkmark" : "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.offscriptTextPrimary)
                            .frame(width: 32, height: 32)
                            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(episode.isQueued)
                    .accessibilityLabel(episode.isQueued ? "Already queued" : "Add to queue")

                    Spacer()

                    Menu {
                        Button { registerSignal(.moreLikeThis) } label: { Label("More like this", systemImage: "arrow.up.heart") }
                        Button { registerSignal(.like) } label: { Label("Like", systemImage: "hand.thumbsup") }
                        Button(role: .destructive) { registerSignal(.lessLikeThis) } label: { Label("Less like this", systemImage: "hand.thumbsdown") }
                        Button(role: .destructive) { registerSignal(.notInterested) } label: { Label("Not interested", systemImage: "xmark.circle") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
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
        .background(Color.offscriptCard)
        .overlay(
            Rectangle().stroke(Color.offscriptHairline, lineWidth: 0.5)
        )
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

    /// Tuner OLED list row — square hairline-bordered artwork + mono cyan
    /// show eyebrow + sans episode title + mono date metadata + square
    /// signal-yellow play key. Optional rank renders as a square hairline
    /// cell with mono numeral.
    var body: some View {
        HStack(spacing: 12) {
            if let rank {
                Text(String(format: "%02d", rank))
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Rectangle().stroke(Color.offscriptHairline, lineWidth: 0.5)
                    )
            }

            tapTarget {
                OffScriptArtworkView(
                    url: episode.artworkURL ?? episode.podcast.artworkURL,
                    cornerRadius: 4
                )
                .frame(width: 48, height: 48)
                .overlay(
                    Rectangle().stroke(Color.offscriptHairline, lineWidth: 0.5)
                )
            }

            tapTarget {
                VStack(alignment: .leading, spacing: 4) {
                    if showPodcastTitle {
                        Text(episode.podcast.title.uppercased())
                            .font(.offscriptTagLabel)
                            .tracking(1.4)
                            .foregroundStyle(Color.offscriptAccentSecondary)
                            .lineLimit(1)
                    }

                    Text(episode.title)
                        .font(.offscriptCardTitle)
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(metadata.uppercased())
                        .font(.offscriptMicro)
                        .tracking(1.2)
                        .foregroundStyle(Color.offscriptTextMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                PlaybackController.shared.play(episode, in: modelContext)
            } label: {
                Image(systemName: playIcon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isCurrentlyPlaying ? Color.offscriptTextPrimary : .black)
                    .frame(width: 32, height: 32)
                    .background(isCurrentlyPlaying ? Color.offscriptFillLight : Color.offscriptAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCurrentlyPlaying ? "Pause" : "Play \(episode.title)")

            if let onRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.offscriptTextMuted)
                        .frame(width: 28, height: 28)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(episode.title)")
            }
        }
        .padding(12)
        .background(Color.offscriptCard)
        .overlay(
            Rectangle().stroke(Color.offscriptHairline, lineWidth: 0.5)
        )
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

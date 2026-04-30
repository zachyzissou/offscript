import OSLog
import SwiftData
import SwiftUI

private let cardLogger = Logger(subsystem: "com.offscript", category: "CardComponents")

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

            // Tuner text + transport zone
            VStack(alignment: .leading, spacing: 8) {
                if let tag = explanationTag {
                    TunerTag(text: tag, color: .offscriptSignalYellow, dim: true, wraps: true)
                }

                // Podcast title in info-cyan per the function-coded color
                // system. Was signal-yellow — yellow is reserved for the
                // primary accent / actionable state, not metadata labels.
                Text(episode.podcast.title.uppercased())
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color.offscriptFnInfo)
                    .lineLimit(1)

                Button {
                    if let onTap {
                        onTap()
                    } else {
                        navigateToDetail = true
                    }
                } label: {
                    Text(episode.title)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .tracking(-0.2)
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)

                Text(metadata.uppercased())
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color.offscriptSoftPaper)
                    .lineLimit(1)

                if progressValue > 0 {
                    // Inline Tuner progress rail — replaces removed OffScriptProgressBar.
                    GeometryReader { proxy in
                        let clamped = min(max(progressValue, 0), 1)
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.offscriptHairline)
                            Rectangle().fill(Color.offscriptSignalYellow)
                                .frame(width: proxy.size.width * clamped)
                        }
                    }
                    .frame(height: 2)
                }

                HStack(spacing: 6) {
                    // Tuner play key — sharp hairline rectangle, signal-yellow
                    // ring. Was Circle (Tuner-vocab violation — sharp rectangles
                    // only). 36pt visible × 44pt hit target per HIG.
                    Button {
                        PlaybackController.shared.play(episode, in: modelContext)
                    } label: {
                        Image(systemName: playIcon)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.offscriptSignalYellow)
                            .frame(width: 30, height: 30)
                            .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1.25))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCurrentlyPlaying ? "Pause" : "Play \(episode.title)")

                    // Tuner queue key — hairline square
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            try? QueueService.add(episode, in: modelContext)
                        }
                    } label: {
                        Image(systemName: episode.isQueued ? "checkmark" : "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(episode.isQueued ? Color.offscriptSoftPaper : Color.offscriptPaperWhite)
                            .frame(width: 30, height: 30)
                            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
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
        .background(Color.offscriptStudioBlack)
        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
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
        HStack(spacing: 12) {
            if let rank {
                Text(String(format: "%02d", rank))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(Color.offscriptSignalYellow)
                    .monospacedDigit()
                    .frame(width: 28, alignment: .leading)
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
                    cornerRadius: 3
                )
                .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)

            Button {
                if let onTap {
                    onTap()
                } else {
                    navigateToDetail = true
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    if showPodcastTitle {
                        // Info-cyan per the function-coded color system.
                        Text(episode.podcast.title.uppercased())
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(Color.offscriptFnInfo)
                            .lineLimit(1)
                    }

                    Text(episode.title)
                        .font(.system(size: 13.5, weight: .semibold, design: .default))
                        .tracking(-0.2)
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(metadata.uppercased())
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Color.offscriptSoftPaper)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Tuner play key — sharp hairline rectangle, signal-yellow ring.
            // Was Circle (Tuner-vocab violation). 32pt visible / 44pt hit.
            Button {
                PlaybackController.shared.play(episode, in: modelContext)
            } label: {
                Image(systemName: playIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.offscriptSignalYellow)
                    .frame(width: 32, height: 32)
                    .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1.25))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCurrentlyPlaying ? "Pause" : "Play \(episode.title)")

            Menu {
                Button(episode.isQueued ? "Already Queued" : "Add to Queue") {
                    do { try QueueService.add(episode, in: modelContext) }
                    catch { cardLogger.error("Queue add failed: \(error.localizedDescription, privacy: .public)") }
                }
                .disabled(episode.isQueued)

                Divider()

                Button(episode.isPlayed ? "Mark Unplayed" : "Mark Played") {
                    togglePlayedState()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .frame(width: 30, height: 30)
                    .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More actions for \(episode.title)")

            if let onRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.offscriptSoftPaper)
                        .frame(width: 26, height: 26)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(episode.title)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
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

    private func togglePlayedState() {
        if episode.isPlayed {
            episode.isPlayed = false
            episode.playedPosition = 0
            episode.lastPlayedAt = nil
        } else {
            episode.isPlayed = true
            episode.playedPosition = episode.duration ?? episode.playedPosition
            episode.lastPlayedAt = .now
        }
        try? modelContext.save()
    }
}

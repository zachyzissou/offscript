import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var sections: [HomeFeedSection] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    let onOpenSettings: () -> Void

    private let recommendationService = RecommendationService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                HomeEditorialHeader()

                if let errorMessage {
                    ContentUnavailableView("Feed unavailable", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                        .padding(.horizontal, OffScriptTheme.pagePadding)
                }

                if isLoading {
                    VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                        SkeletonHeroCard()
                            .padding(.horizontal, OffScriptTheme.pagePadding)

                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.offscriptFillSubtle)
                                    .frame(width: 130, height: 16)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.offscriptFillSubtle)
                                    .frame(width: 200, height: 12)
                            }
                            .padding(.horizontal, OffScriptTheme.pagePadding)
                            .shimmer()

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 18) {
                                    ForEach(0..<3, id: \.self) { _ in
                                        SkeletonRailCard()
                                    }
                                }
                                .padding(.horizontal, OffScriptTheme.pagePadding)
                            }
                        }
                    }
                } else if sections.isEmpty {
                    VStack(spacing: 20) {
                        OffScriptEmptyState(
                            icon: "waveform.badge.magnifyingglass",
                            headline: "Your feed starts here",
                            message: "Add three shows you trust and OffScript will build a feed that feels curated, not algorithmic."
                        )

                        NavigationLink("Browse Search") {
                            SearchView()
                        }
                        .buttonStyle(PrimaryPillButtonStyle())
                    }
                    .padding(.top, 40)
                } else {
                    if let leadSection = sections.first, let leadEpisode = leadSection.episodes.first {
                        HeroRecommendationCard(
                            episode: leadEpisode,
                            reason: leadSection.explanation(for: leadEpisode)
                        )
                        .padding(.horizontal, OffScriptTheme.spaciousPadding)
                        .staggeredEntrance(index: 0)

                        let remainingLeadEpisodes = Array(leadSection.episodes.dropFirst())
                        if !remainingLeadEpisodes.isEmpty {
                            RecommendationRail(
                                title: "Next Best Picks",
                                subtitle: "More picks in the same lane.",
                                episodes: remainingLeadEpisodes,
                                reasonProvider: { leadSection.explanation(for: $0) }
                            )
                            .staggeredEntrance(index: 1)
                        }
                    }

                    ForEach(Array(sections.dropFirst().enumerated()), id: \.element.id) { offset, section in
                        RecommendationRail(
                            title: section.title,
                            subtitle: section.subtitle,
                            episodes: section.episodes,
                            reasonProvider: { section.explanation(for: $0) }
                        )
                        .staggeredEntrance(index: offset + 2)
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .offscriptPageBackground()
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.offscriptBackgroundTop.opacity(0.98), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: onOpenSettings) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.offscriptTextMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open settings")
                .accessibilityHint("Adjust playback and recommendation preferences")
            }
        }
        .task { await loadSections() }
        .refreshable { await loadSections() }
    }

    @MainActor
    private func loadSections() async {
        do {
            let loaded = try recommendationService.homeSections(context: modelContext)
            sections = loaded
            errorMessage = nil
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

}

private struct HomeEditorialHeader: View {
    private var dayString: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ready when you are")
                .font(.offscriptUtilityTitle)
                .foregroundStyle(Color.offscriptTextPrimary)

            Text(dayString.uppercased())
                .font(.offscriptMeta.weight(.semibold))
                .foregroundStyle(Color.offscriptTextMuted)
        }
        .padding(.horizontal, OffScriptTheme.pagePadding)
    }
}

private struct HeroRecommendationCard: View {
    @Environment(\.modelContext) private var modelContext

    let episode: Episode
    let reason: String

    private var progressValue: Double {
        guard let duration = episode.duration, duration > 0 else { return 0 }
        return episode.playedPosition / duration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Artwork hero zone — larger, more dominant
            ZStack(alignment: .bottomLeading) {
                OffScriptArtworkView(
                    url: episode.artworkURL ?? episode.podcast.artworkURL,
                    cornerRadius: 0
                )
                .frame(height: 200)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [.clear, .clear, Color.offscriptCardStrong.opacity(0.7), Color.offscriptCardStrong],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Overlay the explanation tag on the artwork
                VStack(alignment: .leading, spacing: 8) {
                    OffScriptExplanationTag(text: reason)

                    Text(episode.podcast.title)
                        .font(.offscriptMeta.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(Color.offscriptTextSecondary)
                        .lineLimit(1)
                }
                .padding(20)
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: OffScriptTheme.Radius.large,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: OffScriptTheme.Radius.large,
                    style: .continuous
                )
            )

            // Content zone
            VStack(alignment: .leading, spacing: 14) {
                NavigationLink {
                    EpisodeDetailView(episode: episode)
                } label: {
                    Text(episode.title)
                        .font(.system(.title2, design: .serif, weight: .bold))
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)

                HStack(spacing: 12) {
                    Label(metadata, systemImage: "clock")
                    if episode.playedPosition > 0, !episode.isPlayed {
                        Label(timeRemaining, systemImage: "arrow.trianglehead.clockwise")
                    }
                }
                .font(.offscriptMeta)
                .foregroundStyle(Color.offscriptTextMuted)

                if progressValue > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        OffScriptProgressBar(value: progressValue, height: 6)
                        Text("Resume from where you left off")
                            .font(.offscriptMeta)
                            .foregroundStyle(Color.offscriptTextMuted)
                    }
                }

                HStack(spacing: 10) {
                    Button("Play") {
                        TelemetryService.track(
                            "recommendation_opened",
                            metadata: ["source": "home_hero", "episode": episode.title, "podcast": episode.podcast.title],
                            in: modelContext
                        )
                        PlaybackController.shared.play(episode, in: modelContext)
                    }
                    .buttonStyle(PrimaryPillButtonStyle())

                    Button(episode.isQueued ? "Queued" : "Queue") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            try? QueueService.add(episode, in: modelContext)
                        }
                    }
                    .buttonStyle(SecondaryPillButtonStyle())
                    .disabled(episode.isQueued)
                    .sensoryFeedback(.impact(flexibility: .soft), trigger: episode.isQueued)

                    Spacer()

                    Menu {
                        Button("Like") { register(.like) }
                        Button("Less like this") { register(.lessLikeThis) }
                        Button("Not now") { register(.notInterested) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.offscriptTextPrimary)
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("More actions")
                    .accessibilityHint("Like this episode or tune future recommendations")
                }
            }
            .padding(20)
            .padding(.bottom, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.large, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.offscriptCardStrong, Color.offscriptCardRaised],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .offscriptGrain(opacity: 0.035)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.large, style: .continuous)
                .stroke(Color.offscriptHairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: OffScriptTheme.Radius.large, style: .continuous))
        .shadow(color: Color.black.opacity(0.38), radius: 28, y: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(episode.title) from \(episode.podcast.title). \(reason)")
    }

    private var metadata: String {
        let dateString = episode.pubDate.formatted(date: .abbreviated, time: .omitted)
        if let duration = episode.duration {
            return "\(dateString) • \(EpisodeDurationFormatter.short(duration))"
        }
        return dateString
    }

    private var timeRemaining: String {
        guard let duration = episode.duration else { return "In progress" }
        let remaining = max(0, duration - episode.playedPosition)
        return "\(EpisodeDurationFormatter.short(remaining)) left"
    }

    private func register(_ action: PreferenceSignal.Action) {
        modelContext.insert(PreferenceSignal(action: action, episode: episode))
        try? modelContext.save()
    }
}

private struct RecommendationRail: View {
    let title: String
    let subtitle: String
    let episodes: [Episode]
    let reasonProvider: (Episode) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OffScriptSectionHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, OffScriptTheme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(episodes) { episode in
                        EpisodeRailCard(episode: episode, reason: reasonProvider(episode))
                    }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)
            }
        }
    }
}

private struct EpisodeRailCard: View {
    @Environment(\.modelContext) private var modelContext

    let episode: Episode
    let reason: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.offscriptCardRaised, Color.offscriptCardUtility],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 12) {
                NavigationLink {
                    EpisodeDetailView(episode: episode)
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        OffScriptArtworkView(url: episode.artworkURL ?? episode.podcast.artworkURL, cornerRadius: OffScriptTheme.Radius.medium)
                            .frame(width: 190, height: 142)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 6) {
                            OffScriptExplanationTag(text: reason)

                            Text(episode.podcast.title.uppercased())
                                .font(.offscriptMicro.weight(.semibold))
                                .foregroundStyle(Color.offscriptAccent)

                            Text(episode.title)
                                .font(.offscriptCardTitle)
                                .foregroundStyle(Color.offscriptTextPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Text(metadata)
                                .font(.offscriptMeta)
                                .foregroundStyle(Color.offscriptTextMuted)
                        }
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Button("Play") {
                        TelemetryService.track(
                            "recommendation_opened",
                            metadata: ["source": "home_rail", "episode": episode.title, "podcast": episode.podcast.title],
                            in: modelContext
                        )
                        PlaybackController.shared.play(episode, in: modelContext)
                    }
                    .buttonStyle(PrimaryPillButtonStyle())

                    Button {
                        try? QueueService.add(episode, in: modelContext)
                    } label: {
                        Image(systemName: episode.isQueued ? "checkmark" : "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.offscriptTextPrimary)
                            .frame(width: 36, height: 36)
                            .background(Color.offscriptFillLight)
                            .clipShape(Circle())
                    }
                    .disabled(episode.isQueued)

                    Spacer()
                }
            }
            .padding(16)
        }
        .frame(width: 222, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                .stroke(Color.offscriptHairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 12, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(episode.title) from \(episode.podcast.title). \(reason)")
    }

    private var metadata: String {
        let dateString = episode.pubDate.formatted(date: .abbreviated, time: .omitted)
        if let duration = episode.duration {
            return "\(dateString) • \(EpisodeDurationFormatter.short(duration))"
        }
        return dateString
    }
}

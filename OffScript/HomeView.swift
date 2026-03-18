import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var sections: [HomeFeedSection] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var discoveryPreviewResult: PodcastSearchResult?
    @State private var importingDiscoveryID: String?
    let onOpenSettings: () -> Void

    private let recommendationService = RecommendationService()
    private let syncService = FeedSyncService()

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
                            message: "Subscribe to a few shows, listen, and OffScript will learn what you like. The more you play, the sharper your feed gets."
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
                        if section.isDiscoverySection {
                            DiscoveryRail(
                                title: section.title,
                                subtitle: section.subtitle,
                                results: section.discoveryResults,
                                importingID: importingDiscoveryID,
                                onPreview: { scored in discoveryPreviewResult = scored.result },
                                onAdd: { scored in
                                    Task { await addDiscoveryResult(scored.result) }
                                }
                            )
                            .staggeredEntrance(index: offset + 2)
                        } else {
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
        .sheet(item: $discoveryPreviewResult) { result in
            SearchResultDetailView(
                result: result,
                isAdded: isAlreadySubscribed(result),
                isImporting: importingDiscoveryID == result.id,
                onAdd: { Task { await addDiscoveryResult(result) } }
            )
        }
    }

    private func isAlreadySubscribed(_ result: PodcastSearchResult) -> Bool {
        let feedURL = result.feedURL
        let descriptor = FetchDescriptor<Podcast>(
            predicate: #Predicate<Podcast> { $0.feedURL == feedURL && $0.isSubscribed == true }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    @MainActor
    private func addDiscoveryResult(_ result: PodcastSearchResult) async {
        importingDiscoveryID = result.id
        defer { importingDiscoveryID = nil }

        do {
            _ = try await syncService.importPodcast(from: result, into: modelContext)
            try? TasteProfileService.refresh(in: modelContext)
            await recommendationService.discoveryService.invalidateCache()
            TelemetryService.track(
                "discovery_imported",
                metadata: ["podcast": result.title, "source": "home_discovery"],
                in: modelContext
            )
            await loadSections()
        } catch {
            // Import failed — user can retry from the card
        }
    }

    @MainActor
    private func loadSections() async {
        do {
            var loaded = try recommendationService.homeSections(context: modelContext)

            // Append discovery section after existing episode sections
            if let discovery = await recommendationService.discoverySection(context: modelContext) {
                loaded.append(discovery)
            }

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

    @State private var navigateToDetail = false

    private var progressValue: Double {
        guard let duration = episode.duration, duration > 0 else { return 0 }
        return episode.playedPosition / duration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Artwork hero zone — tappable for navigation
            Button {
                navigateToDetail = true
            } label: {
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
            }
            .buttonStyle(.plain)
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
                Button {
                    navigateToDetail = true
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
                    Button(episode.playedPosition > 0 ? "Resume" : "Play") {
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
                        Button { register(.like) } label: {
                            Label("Like", systemImage: "hand.thumbsup")
                        }
                        Button { register(.moreLikeThis) } label: {
                            Label("More like this", systemImage: "arrow.up.heart")
                        }
                        Button { register(.lessLikeThis) } label: {
                            Label("Less like this", systemImage: "hand.thumbsdown")
                        }
                        Button(role: .destructive) { register(.notInterested) } label: {
                            Label("Not interested", systemImage: "xmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.offscriptTextPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Rate this recommendation")
                    .accessibilityHint("Like, dislike, or dismiss this episode")
                }
            }
            .padding(20)
            .padding(.bottom, 4)
        }
        .navigationDestination(isPresented: $navigateToDetail) {
            EpisodeDetailView(episode: episode)
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
                HStack(spacing: OffScriptTheme.itemSpacing) {
                    ForEach(episodes) { episode in
                        EpisodeVerticalCard(
                            episode: episode,
                            explanationTag: reasonProvider(episode)
                        )
                    }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)
            }
        }
    }
}

// MARK: - Discovery Section Views

private struct DiscoveryRail: View {
    let title: String
    let subtitle: String
    let results: [ScoredDiscoveryResult]
    let importingID: String?
    let onPreview: (ScoredDiscoveryResult) -> Void
    let onAdd: (ScoredDiscoveryResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OffScriptSectionHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, OffScriptTheme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(results) { scored in
                        DiscoveryRailCard(
                            scored: scored,
                            isImporting: importingID == scored.id,
                            onPreview: { onPreview(scored) },
                            onAdd: { onAdd(scored) }
                        )
                    }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)
            }
        }
    }
}

private struct DiscoveryRailCard: View {
    let scored: ScoredDiscoveryResult
    let isImporting: Bool
    let onPreview: () -> Void
    let onAdd: () -> Void

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

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    onPreview()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        OffScriptArtworkView(
                            url: scored.result.artworkURL,
                            cornerRadius: 12
                        )
                        .frame(width: 72, height: 72)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(scored.result.title)
                                .font(.offscriptCardTitle)
                                .foregroundStyle(Color.offscriptTextPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Text(scored.result.author)
                                .font(.offscriptMeta)
                                .foregroundStyle(Color.offscriptTextSecondary)
                                .lineLimit(1)

                            if let summary = scored.result.summary {
                                Text(summary)
                                    .font(.offscriptMeta)
                                    .foregroundStyle(Color.offscriptTextMuted)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                OffScriptExplanationTag(text: scored.explanation)

                HStack(spacing: 8) {
                    Button("Preview") {
                        onPreview()
                    }
                    .buttonStyle(SecondaryPillButtonStyle())

                    Button(isImporting ? "Adding..." : "Add") {
                        onAdd()
                    }
                    .buttonStyle(PrimaryPillButtonStyle())
                    .disabled(isImporting)
                }
            }
            .padding(14)
        }
        .frame(width: 260, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                .stroke(Color.offscriptHairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 12, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(scored.result.title) by \(scored.result.author). \(scored.explanation)")
    }
}

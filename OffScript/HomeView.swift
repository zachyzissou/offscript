import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var sections: [HomeFeedSection] = HomeRecommendationCache.shared.sections
    @State private var errorMessage: String?
    @State private var isLoading = HomeRecommendationCache.shared.sections.isEmpty
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
                            message: "Subscribe to a few shows, listen, and OffScript will learn what you like. The more you play, the sharper your feed gets.",
                            generatedCopyKey: "home.empty",
                            generatedCopyPrompt: "Surface: empty Home tab. Write a two-sentence editorial nudge for a podcast app that learns from listening behavior — confident, no apology."
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
        .task {
            // Show whatever's already cached instantly — recompute only if the
            // cache is stale or there's nothing to show.
            if sections.isEmpty || HomeRecommendationCache.shared.isStale {
                await loadSections()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Re-evaluate when app returns to foreground but only if data has
            // changed enough to matter. The cache layer decides.
            if newPhase == .active, HomeRecommendationCache.shared.isStale {
                Task { await loadSections() }
            }
        }
        .refreshable {
            HomeRecommendationCache.shared.invalidate()
            await loadSections()
        }
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

            // Append discovery section after existing episode sections.
            // Discovery hits the network so do it in parallel with the local
            // sections being made visible.
            sections = loaded
            HomeRecommendationCache.shared.update(sections: loaded)
            errorMessage = nil
            isLoading = false

            if let discovery = await recommendationService.discoverySection(context: modelContext) {
                loaded.append(discovery)
                sections = loaded
                HomeRecommendationCache.shared.update(sections: loaded)
            }
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

    /// Tuner station header — mono uppercase eyebrow ("STATION"), big thin
    /// sans display title, and a hairline rule beneath. Replaces the warm
    /// serif "Ready when you are" header.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("STATION")
                    .font(.offscriptTagLabel)
                    .tracking(1.6)
                    .foregroundStyle(Color.offscriptAccent)
                Spacer()
                Text(dayString.uppercased())
                    .font(.offscriptMicro)
                    .tracking(1.4)
                    .foregroundStyle(Color.offscriptTextMuted)
            }

            Text("Tonight's signal")
                .font(.offscriptDisplay)
                .foregroundStyle(Color.offscriptTextPrimary)

            Rectangle()
                .fill(Color.offscriptHairline)
                .frame(height: 0.5)
                .padding(.top, 2)
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

    /// Tuner OLED hero — flat black panel with hairline border, square
    /// artwork at top, episode info as instrument-cluster readouts beneath,
    /// single signal-yellow PLAY key. No gradient overlay, no grain, no
    /// shadow.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: EpisodeNavigation(episode: episode)) {
                OffScriptArtworkView(
                    url: episode.artworkURL ?? episode.podcast.artworkURL,
                    cornerRadius: 0
                )
                .frame(height: 200)
                .clipped()
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 12) {
                // Tag row — show name (cyan) + reasoning (signal yellow).
                HStack(spacing: 6) {
                    TTagPill(label: episode.podcast.title, tone: .info)
                    TTagPill(label: reason, tone: .signal)
                    Spacer()
                }

                // Episode title — thin sans display.
                NavigationLink(value: EpisodeNavigation(episode: episode)) {
                    Text(episode.title)
                        .font(.offscriptDisplay)
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)

                // Mono metadata row — date · duration, plus remaining if in
                // progress.
                HStack(spacing: 8) {
                    Text(metadata.uppercased())
                        .font(.offscriptMeta)
                        .tracking(1.0)
                        .foregroundStyle(Color.offscriptTextMuted)
                    if episode.playedPosition > 0, !episode.isPlayed {
                        Text("·")
                            .font(.offscriptMeta)
                            .foregroundStyle(Color.offscriptTextMuted)
                        Text(timeRemaining.uppercased())
                            .font(.offscriptMeta)
                            .tracking(1.0)
                            .foregroundStyle(Color.offscriptAccent)
                    }
                }

                // In-progress hairline strip.
                if progressValue > 0 {
                    OffScriptProgressBar(value: progressValue, height: 1)
                }

                // Action row — primary signal-yellow PLAY (or RESUME),
                // secondary outlined QUEUE, ellipsis for ratings.
                HStack(spacing: 8) {
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
                        withAnimation(.easeOut(duration: 0.15)) {
                            try? QueueService.add(episode, in: modelContext)
                        }
                    }
                    .buttonStyle(SecondaryPillButtonStyle())
                    .disabled(episode.isQueued)
                    .sensoryFeedback(.impact(flexibility: .soft), trigger: episode.isQueued)

                    Spacer()

                    Menu {
                        Button { register(.like) } label: { Label("Like", systemImage: "hand.thumbsup") }
                        Button { register(.moreLikeThis) } label: { Label("More like this", systemImage: "arrow.up.heart") }
                        Button { register(.lessLikeThis) } label: { Label("Less like this", systemImage: "hand.thumbsdown") }
                        Button(role: .destructive) { register(.notInterested) } label: { Label("Not interested", systemImage: "xmark.circle") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.offscriptTextPrimary)
                            .frame(width: 38, height: 38)
                            .overlay(
                                Rectangle().stroke(Color.offscriptHairline, lineWidth: 0.5)
                            )
                    }
                    .accessibilityLabel("Rate this recommendation")
                }
            }
            .padding(16)
        }
        .background(Color.offscriptCard)
        .overlay(
            Rectangle().stroke(Color.offscriptHairline, lineWidth: 0.5)
        )
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
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1.0 : 0.5)
                                .scaleEffect(phase.isIdentity ? 1.0 : 0.92)
                                .blur(radius: phase.isIdentity ? 0 : 2)
                        }
                    }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            .onAppear {
                // Warm the next several artwork URLs so cards don't pop in.
                ImageCache.shared.prefetch(
                    episodes.prefix(8).map { $0.artworkURL ?? $0.podcast.artworkURL }
                )
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
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1.0 : 0.55)
                                .scaleEffect(phase.isIdentity ? 1.0 : 0.93)
                        }
                    }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
        }
    }
}

private struct DiscoveryRailCard: View {
    let scored: ScoredDiscoveryResult
    let isImporting: Bool
    let onPreview: () -> Void
    let onAdd: () -> Void

    var body: some View {
        Button {
            onPreview()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                OffScriptArtworkView(
                    url: scored.result.artworkURL,
                    cornerRadius: 0
                )
                .frame(width: 200, height: 150)
                .clipped()

                VStack(alignment: .leading, spacing: 8) {
                    OffScriptExplanationTag(text: scored.explanation)

                    Text(scored.result.title)
                        .font(.offscriptCardTitle)
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(scored.result.author)
                        .font(.offscriptMicro)
                        .foregroundStyle(Color.offscriptTextSecondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Button {
                            onAdd()
                        } label: {
                            Image(systemName: isImporting ? "arrow.2.circlepath" : "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(isImporting ? Color.offscriptTextMuted : Color.offscriptAccent)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        .disabled(isImporting)

                        Text(isImporting ? "Adding..." : "Add to Library")
                            .font(.offscriptMeta)
                            .foregroundStyle(Color.offscriptTextMuted)
                    }
                }
                .padding(12)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.offscriptCardRaised, Color.offscriptCard],
                        startPoint: .top,
                        endPoint: .bottom
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
        .accessibilityLabel("\(scored.result.title) by \(scored.result.author). \(scored.explanation)")
    }
}

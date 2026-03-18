import SwiftData
import SwiftUI

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var podcasts: [Podcast]
    @State private var query = ""
    @State private var isSearchActive = false
    @State private var results: [PodcastSearchResult] = []
    @State private var featuredResults: [PodcastSearchResult] = []
    @State private var isSearching = false
    @State private var isLoadingFeatured = false
    @State private var importingID: String?
    @State private var errorMessage: String?
    @State private var selectedGenre: Genre?
    @State private var previewResult: PodcastSearchResult?
    @State private var recentlyImportedPodcast: Podcast?
    @State private var importedRecommendation: Episode?
    @State private var importedRecommendationReason: String?
    @State private var navigatedPodcast: Podcast?

    private let searchService = PodcastSearchService()
    private let syncService = FeedSyncService()
    private let recommendationService = RecommendationService()
    private let allGenres = Genre.allCases

    private var subscribedFeedURLs: Set<String> {
        Set(podcasts.filter(\.isSubscribed).map { $0.feedURL.absoluteString })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                // Inline search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.offscriptTextMuted)
                    TextField("Search podcasts or hosts", text: $query)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            isSearchActive = true
                            storeRecentSearch(query)
                        }
                    if !query.isEmpty {
                        Button {
                            query = ""
                            isSearchActive = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.offscriptTextMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.offscriptHairline, lineWidth: 0.5)
                )
                .padding(.horizontal, OffScriptTheme.pagePadding)

                if !isSearchActive {
                    SearchHeader()
                }

                if query.isEmpty, !isSearchActive {
                    SearchPromptCard()
                        .padding(.horizontal, OffScriptTheme.pagePadding)

                    if !topicTrails.isEmpty {
                        TopicTrailSection(
                            topics: topicTrails,
                            onSelect: { topic in
                                query = topic
                                isSearchActive = true
                            }
                        )
                    }

                    BrowseGenresSection(
                        genres: allGenres,
                        selectedGenre: selectedGenre,
                        onSelect: { genre in
                            selectedGenre = genre
                            Task { await loadFeatured(for: genre) }
                        }
                    )

                    // Show featured results immediately after genre selection — not below the fold
                    if isLoadingFeatured {
                        FeaturedSearchLoadingSection()
                            .transition(.opacity)
                    } else if let selectedGenre, !featuredResults.isEmpty {
                        FeaturedResultsSection(
                            genre: selectedGenre,
                            results: featuredResults,
                            subscribedFeedURLs: subscribedFeedURLs,
                            importingID: importingID,
                            onPreview: {
                                previewResult = $0
                                TelemetryService.track(
                                    "show_preview_opened",
                                    metadata: ["podcast": $0.title, "source": "featured_genre"],
                                    in: modelContext
                                )
                            },
                            onAdd: { result in Task { await add(result, source: "featured_genre") } }
                        )
                        .transition(.opacity)
                    }

                    if !recentSearches.isEmpty {
                        RecentSearchesSection(
                            items: recentSearches,
                            onSelect: { item in query = item }
                        )
                    }
                }

                if let errorMessage {
                    SearchErrorCard(message: errorMessage)
                        .padding(.horizontal, OffScriptTheme.pagePadding)
                }

                if let recentlyImportedPodcast {
                    SearchImportSuccessCard(
                        podcast: recentlyImportedPodcast,
                        recommendedEpisode: importedRecommendation,
                        recommendationReason: importedRecommendationReason,
                        onOpenShow: { navigatedPodcast = recentlyImportedPodcast },
                        onPlayRecommendation: {
                            guard let importedRecommendation else { return }
                            TelemetryService.track(
                                "search_post_import_play_recommendation",
                                metadata: [
                                    "episode": importedRecommendation.title,
                                    "podcast": importedRecommendation.podcast.title
                                ],
                                in: modelContext
                            )
                            PlaybackController.shared.play(importedRecommendation, in: modelContext)
                        },
                        onDismiss: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                self.recentlyImportedPodcast = nil
                                self.importedRecommendation = nil
                                self.importedRecommendationReason = nil
                            }
                        }
                    )
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                }

                if isSearching {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(0..<3, id: \.self) { _ in
                            HStack(spacing: 16) {
                                RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                                    .fill(Color.offscriptFillSubtle)
                                    .frame(width: 76, height: 76)

                                VStack(alignment: .leading, spacing: 8) {
                                    Capsule()
                                        .fill(Color.offscriptFillSubtle)
                                        .frame(width: 80, height: 14)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.offscriptFillSubtle)
                                        .frame(width: 160, height: 16)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.offscriptFillSubtle)
                                        .frame(width: 110, height: 12)
                                }

                                Spacer()
                            }
                            .padding(18)
                            .offscriptUtilitySurface()
                        }
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                    .shimmer()
                } else if results.isEmpty, !query.isEmpty {
                    OffScriptEmptyState(
                        icon: "magnifyingglass",
                        headline: "No matches",
                        message: "Try a different show name, host, or topic. Exact titles work best."
                    )
                        .padding(.horizontal, OffScriptTheme.pagePadding)
                } else if !results.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        OffScriptSectionHeader(
                            title: "Results",
                            subtitle: "Subscribe quickly and let OffScript turn a few good picks into a smarter feed."
                        )
                        .padding(.horizontal, OffScriptTheme.pagePadding)

                        LazyVStack(spacing: 14) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                SearchResultCard(
                                    result: result,
                                    isAdded: subscribedFeedURLs.contains(result.feedURL.absoluteString),
                                    isImporting: importingID == result.id,
                                    onPreview: {
                                        previewResult = result
                                        TelemetryService.track(
                                            "show_preview_opened",
                                            metadata: ["podcast": result.title, "source": "search"],
                                            in: modelContext
                                        )
                                    },
                                    onAdd: { Task { await add(result, source: "search") } }
                                )
                                .padding(.horizontal, OffScriptTheme.pagePadding)
                                .staggeredEntrance(index: index)
                            }
                        }
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 0)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .offscriptPageBackground()
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: query) { _, newValue in
            isSearchActive = !newValue.isEmpty
        }
        .task(id: query) { await search() }
        // Don't auto-load genre results — let the user tap a genre to explore
        .sheet(item: $previewResult) { result in
            SearchResultDetailView(
                result: result,
                isAdded: subscribedFeedURLs.contains(result.feedURL.absoluteString),
                isImporting: importingID == result.id,
                onAdd: { Task { await add(result, source: "detail_preview") } },
                onNavigateToShow: {
                    if let podcast = podcasts.first(where: { $0.feedURL == result.feedURL }) {
                        navigatedPodcast = podcast
                    }
                }
            )
        }
        .navigationDestination(item: $navigatedPodcast) { podcast in
            PodcastDetailView(podcast: podcast)
        }
    }

    private var recentSearches: [String] {
        AppSettings.recentSearchesStorage
            .split(separator: "\u{1F}")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var topicTrails: [String] {
        let sourceGenres = selectedGenre.map { [$0] } ?? (AppSettings.preferredGenres.isEmpty ? Array(allGenres.prefix(3)) : AppSettings.preferredGenres)
        var topics: [String] = []
        for genre in sourceGenres {
            topics.append(contentsOf: SearchTopicCatalog.topics(for: genre))
        }
        return topics.reduce(into: [String]()) { result, topic in
            guard !result.contains(topic) else { return }
            result.append(topic)
        }
    }

    @MainActor
    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            errorMessage = nil
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }

        do {
            results = try await searchService.search(query: trimmed)
            errorMessage = nil
            storeRecentSearch(trimmed)
            TelemetryService.track(
                "search_performed",
                metadata: ["query": trimmed, "results": "\(results.count)"],
                in: modelContext
            )
        } catch {
            errorMessage = "Search failed. Check your connection and try again."
            TelemetryService.track(
                "search_failed",
                metadata: ["query": trimmed, "error": error.localizedDescription],
                in: modelContext
            )
        }
    }

    @MainActor
    private func add(_ result: PodcastSearchResult, source: String) async {
        importingID = result.id
        defer { importingID = nil }

        do {
            let podcast = try await syncService.importPodcast(from: result, into: modelContext)
            try? TasteProfileService.refresh(in: modelContext)
            errorMessage = nil
            storeRecentSearch(result.title)
            recentlyImportedPodcast = podcast
            let recommendation = try? recommendationService.homeSections(context: modelContext, limit: 3).first?.scoredEpisodes.first
            importedRecommendation = recommendation?.episode ?? podcast.episodes.sorted(by: { $0.pubDate > $1.pubDate }).first
            importedRecommendationReason = recommendation?.explanation ?? importedRecommendation.map { _ in "Start here from \(podcast.title)." }
            TelemetryService.track(
                "subscription_imported",
                metadata: ["podcast": result.title, "source": source],
                in: modelContext
            )
        } catch {
            errorMessage = "Couldn’t import \(result.title) yet."
            TelemetryService.track(
                "subscription_import_failed",
                metadata: ["podcast": result.title, "source": source, "error": error.localizedDescription],
                in: modelContext
            )
        }
    }

    @MainActor
    private func loadFeatured(for genre: Genre) async {
        isLoadingFeatured = true
        defer { isLoadingFeatured = false }
        featuredResults = await TopPodcastsService.fetchTop(genre: genre, limit: 8)
        TelemetryService.track(
            "featured_genre_loaded",
            metadata: ["genre": genre.title, "results": "\(featuredResults.count)"],
            in: modelContext
        )
    }

    private func storeRecentSearch(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        items.insert(trimmed, at: 0)
        AppSettings.recentSearchesStorage = Array(items.prefix(6)).joined(separator: "\u{1F}")
    }
}

private enum SearchTopicCatalog {
    static func topics(for genre: Genre) -> [String] {
        switch genre {
        case .technology:
            return ["AI news", "product design", "founder stories", "developer tools"]
        case .cultureAndSociety:
            return ["modern culture", "design criticism", "internet culture", "personal essays"]
        case .business:
            return ["markets", "operators", "strategy", "startups"]
        case .newsAndPolitics:
            return ["daily news", "elections", "policy", "world affairs"]
        case .comedy:
            return ["improv", "interview comedy", "storytelling", "culture banter"]
        case .trueCrime:
            return ["investigations", "courtroom stories", "cold cases", "reporting"]
        case .science:
            return ["space", "human behavior", "biology", "deep science"]
        case .education:
            return ["history", "science explainers", "psychology", "language learning"]
        case .healthAndWellness:
            return ["longevity", "strength", "nutrition", "mental health"]
        case .sports:
            return ["postgame analysis", "league culture", "athlete interviews", "sports business"]
        case .music:
            return ["album breakdowns", "artist interviews", "music history", "songwriting"]
        case .history:
            return ["ancient history", "wars", "political history", "biographies"]
        }
    }
}

private struct SearchHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OffScriptUtilityHeader(
                eyebrow: "Discover",
                title: "Find a signal worth following",
                subtitle: "Start with a show you trust or a topic you want more of. OffScript can work from either."
            )
        }
        .padding(.horizontal, OffScriptTheme.pagePadding)
    }
}

private struct TopicTrailSection: View {
    let topics: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OffScriptSectionHeader(
                title: "Try a Topic Trail",
                subtitle: "If you don’t have a show in mind, start from a topic and let OffScript work outward."
            )
            .padding(.horizontal, OffScriptTheme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(topics, id: \.self) { topic in
                        Button(topic) {
                            onSelect(topic)
                        }
                        .buttonStyle(SecondaryPillButtonStyle())
                    }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)
            }
        }
    }
}

private struct SearchPromptCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.offscriptAccent)
                .frame(width: 34, height: 34)
                .background(Color.offscriptAccentSoft)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text("Good starting point")
                    .font(.headline)
                    .foregroundStyle(Color.offscriptTextPrimary)

                Text("Search for three strong inputs: a favorite show, a reliable host, and one topic you want more of.")
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .offscriptSurface(radius: OffScriptTheme.Radius.medium, prominent: true)
    }
}

private struct BrowseGenresSection: View {
    let genres: [Genre]
    let selectedGenre: Genre?
    let onSelect: (Genre) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OffScriptSectionHeader(
                title: "Browse Genres",
                subtitle: "Pull top shows by genre when you want to explore before searching by name."
            )
            .padding(.horizontal, OffScriptTheme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(genres) { genre in
                        Button {
                            onSelect(genre)
                        } label: {
                            Label(genre.title, systemImage: genre.systemImage)
                        }
                        .modifier(GenreBrowseButtonStyle(isSelected: selectedGenre == genre))
                    }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)
            }
        }
    }
}

private struct GenreBrowseButtonStyle: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.buttonStyle(PrimaryPillButtonStyle())
        } else {
            content.buttonStyle(SecondaryPillButtonStyle())
        }
    }
}

private struct FeaturedSearchLoadingSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OffScriptSectionHeader(
                title: "Loading top shows",
                subtitle: "Pulling a real chart-backed set of podcasts for this genre."
            )
            .padding(.horizontal, OffScriptTheme.pagePadding)

            VStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 120)
                }
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)
            .shimmer()
        }
    }
}

private struct RecentSearchesSection: View {
    let items: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OffScriptSectionHeader(
                title: "Recent Searches",
                subtitle: "Jump back into the topics and shows you were already exploring."
            )
            .padding(.horizontal, OffScriptTheme.pagePadding)

            LazyVStack(spacing: 12) {
                ForEach(items, id: \.self) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(Color.offscriptTextMuted)
                            Text(item)
                                .font(.offscriptBody)
                                .foregroundStyle(Color.offscriptTextPrimary)
                            Spacer()
                        }
                        .padding(16)
                        .offscriptUtilitySurface()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                }
            }
        }
    }
}

private struct SearchErrorCard: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.offscriptBody)
            .foregroundStyle(Color.offscriptTextPrimary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.offscriptDestructiveSoft)
            .clipShape(RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                    .stroke(Color.offscriptDestructive.opacity(0.4), lineWidth: 1)
            )
    }
}

private struct SearchResultCard: View {
    let result: PodcastSearchResult
    let isAdded: Bool
    let isImporting: Bool
    let onPreview: () -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                OffScriptArtworkView(url: result.artworkURL)
                    .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 8) {
                    OffScriptReasonBadge(text: isAdded ? "In Library" : "RSS Import")

                    Text(result.title)
                        .font(.offscriptCardTitle)
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .lineLimit(2)

                    Text(result.author)
                        .font(.offscriptBody)
                        .foregroundStyle(Color.offscriptTextSecondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            if let summary = result.summary {
                Text(summary.strippingHTML)
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Button {
                    onPreview()
                } label: {
                    Label("Preview", systemImage: "play.fill")
                }
                .buttonStyle(SecondaryPillButtonStyle())

                Button(isAdded ? "Added" : (isImporting ? "Adding..." : "Add to Library")) {
                    onAdd()
                }
                .buttonStyle(PrimaryPillButtonStyle())
                .disabled(isImporting || isAdded)

            }

            if isAdded {
                Text("Added to your library. New episodes from this show will now shape your smart feed.")
                    .font(.offscriptMeta)
                    .foregroundStyle(Color.offscriptTextMuted)
            }
        }
        .padding(18)
        .offscriptUtilitySurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(result.title) by \(result.author)\(isAdded ? ", in library" : "")")
    }
}

private struct FeaturedResultsSection: View {
    let genre: Genre
    let results: [PodcastSearchResult]
    let subscribedFeedURLs: Set<String>
    let importingID: String?
    let onPreview: (PodcastSearchResult) -> Void
    let onAdd: (PodcastSearchResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OffScriptSectionHeader(
                title: "Top in \(genre.title)",
                subtitle: "A quick chart-backed way to discover real shows without leaving OffScript."
            )
            .padding(.horizontal, OffScriptTheme.pagePadding)

            LazyVStack(spacing: 14) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    SearchResultCard(
                        result: result,
                        isAdded: subscribedFeedURLs.contains(result.feedURL.absoluteString),
                        isImporting: importingID == result.id,
                        onPreview: { onPreview(result) },
                        onAdd: { onAdd(result) }
                    )
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                    .staggeredEntrance(index: index)
                }
            }
        }
    }
}

struct SearchResultDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var player = PlaybackController.shared

    let result: PodcastSearchResult
    let isAdded: Bool
    let isImporting: Bool
    let onAdd: () -> Void
    var onNavigateToShow: (() -> Void)?

    @State private var preview: PodcastPreviewSnapshot?
    @State private var isLoadingPreview = true
    @State private var previewError: String?

    private var hostLabel: String? {
        (preview?.websiteURL ?? result.websiteURL)?.host
    }

    private var fitReasons: [String] {
        guard let preview else { return [] }
        let preferred = Set(AppSettings.preferredGenres.map { $0.title.lowercased() })
        let matchingCategories = preview.categories.filter { preferred.contains($0.lowercased()) }
        var reasons: [String] = []
        if !matchingCategories.isEmpty {
            reasons.append("Matches your genres: \(matchingCategories.prefix(2).joined(separator: ", "))")
        }
        if let latest = preview.latestEpisodes.first, let duration = latest.duration {
            reasons.append("Recent episode: \(EpisodeDurationFormatter.short(duration))")
        }
        if preview.latestEpisodes.count >= 3 {
            reasons.append("Has a real back catalog you can start from")
        }
        if reasons.isEmpty, let summary = preview.summary ?? result.summary {
            reasons.append(summary)
        }
        return Array(reasons.prefix(3))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                    HStack(alignment: .top, spacing: 18) {
                        OffScriptArtworkView(
                            url: result.artworkURL,
                            cornerRadius: OffScriptTheme.Radius.large
                        )
                        .frame(width: 120, height: 120)

                        VStack(alignment: .leading, spacing: 8) {
                            OffScriptReasonBadge(text: isAdded ? "In Library" : "Ready to import")

                            Text(result.title)
                                .font(.offscriptDisplay)
                                .foregroundStyle(Color.offscriptTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(result.author)
                                .font(.offscriptBody)
                                .foregroundStyle(Color.offscriptTextSecondary)

                            if let hostLabel {
                                Text(hostLabel)
                                    .font(.offscriptMeta)
                                    .foregroundStyle(Color.offscriptTextMuted)
                            }

                            if let preview, !preview.categories.isEmpty {
                                Text(preview.categories.prefix(3).joined(separator: " • "))
                                    .font(.offscriptMeta)
                                    .foregroundStyle(Color.offscriptTextMuted)
                            }
                        }
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    HStack(spacing: 10) {
                        Button(isAdded ? "In Library" : (isImporting ? "Adding..." : "Add to Library")) {
                            onAdd()
                            if !isAdded {
                                dismiss()
                            }
                        }
                        .buttonStyle(PrimaryPillButtonStyle())
                        .disabled(isAdded || isImporting)

                        if isAdded {
                            Button("Open Show") {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    onNavigateToShow?()
                                }
                            }
                            .buttonStyle(SecondaryPillButtonStyle())
                        }
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    if !fitReasons.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Why it might fit")
                                .font(.offscriptSectionTitle)
                                .foregroundStyle(Color.offscriptTextPrimary)

                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(fitReasons, id: \.self) { reason in
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "sparkles")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(Color.offscriptAccent)
                                            .padding(.top, 2)

                                        Text(reason)
                                            .font(.offscriptBody)
                                            .foregroundStyle(Color.offscriptTextSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, OffScriptTheme.pagePadding)
                    }

                    if isLoadingPreview {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Loading recent episodes")
                                .font(.offscriptSectionTitle)
                                .foregroundStyle(Color.offscriptTextPrimary)
                            VStack(spacing: 10) {
                                ForEach(0..<3, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: OffScriptTheme.Radius.small, style: .continuous)
                                        .fill(Color.white.opacity(0.05))
                                        .frame(height: 68)
                                }
                            }
                            .shimmer()
                        }
                        .padding(.horizontal, OffScriptTheme.pagePadding)
                    } else if let preview, !preview.latestEpisodes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Listen before you subscribe")
                                .font(.offscriptSectionTitle)
                                .foregroundStyle(Color.offscriptTextPrimary)

                            ForEach(preview.latestEpisodes.prefix(5)) { episode in
                                PreviewEpisodeRow(
                                    episode: episode,
                                    podcastTitle: result.title,
                                    artworkURL: result.artworkURL,
                                    isCurrentlyPreviewing: player.isPreviewMode && player.previewAudioURL == episode.audioURL
                                )
                            }
                        }
                        .padding(.horizontal, OffScriptTheme.pagePadding)
                    } else if let previewError {
                        Text(previewError)
                            .font(.offscriptMeta)
                            .foregroundStyle(Color.offscriptTextMuted)
                            .padding(.horizontal, OffScriptTheme.pagePadding)
                    }

                }
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .offscriptPageBackground()
            .navigationTitle("Show Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadPreview()
            }
            .onDisappear {
                // Stop any preview playback when the sheet is dismissed
                if player.isPreviewMode {
                    player.stopPreview()
                }
            }
        }
    }

    @MainActor
    private func loadPreview() async {
        guard preview == nil else { return }
        isLoadingPreview = true
        defer { isLoadingPreview = false }
        do {
            let snapshot = try await PodcastPreviewService.preview(for: result)
            preview = snapshot
            TelemetryService.track(
                "show_preview_loaded",
                metadata: ["podcast": snapshot.title, "episodes": "\(snapshot.latestEpisodes.count)"],
                in: modelContext
            )
        } catch {
            previewError = "Couldn’t load recent episodes for this feed yet."
        }
    }
}

private struct SearchImportSuccessCard: View {
    let podcast: Podcast
    let recommendedEpisode: Episode?
    let recommendationReason: String?
    let onOpenShow: () -> Void
    let onPlayRecommendation: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Imported")
                        .font(.offscriptMicro.weight(.semibold))
                        .foregroundStyle(Color.offscriptAccent)
                    Text("\(podcast.title) is in your library")
                        .font(.offscriptSectionTitle)
                        .foregroundStyle(Color.offscriptTextPrimary)
                    Text(recommendedEpisode == nil ? "Open the show or let OffScript start you at the best next episode." : (recommendationReason ?? "A strong starting point is ready."))
                        .font(.offscriptBody)
                        .foregroundStyle(Color.offscriptTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.offscriptTextMuted)
                        .frame(width: 28, height: 28)
                        .background(Color.offscriptFillSubtle)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss import success")
            }

            if let recommendedEpisode {
                HStack(spacing: 12) {
                    OffScriptArtworkView(
                        url: recommendedEpisode.artworkURL ?? recommendedEpisode.podcast.artworkURL,
                        cornerRadius: OffScriptTheme.Radius.small
                    )
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 4) {
                        OffScriptExplanationTag(text: recommendationReason ?? "Best next")
                        Text(recommendedEpisode.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.offscriptTextPrimary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 10) {
                if recommendedEpisode != nil {
                    Button("Play Best Next") {
                        onPlayRecommendation()
                    }
                    .buttonStyle(PrimaryPillButtonStyle())
                }

                Button("Open Show") {
                    onOpenShow()
                }
                .buttonStyle(SecondaryPillButtonStyle())
            }
        }
        .padding(18)
        .offscriptSurface(radius: OffScriptTheme.Radius.medium, prominent: true)
    }
}

// MARK: - Preview Episode Row

private struct PreviewEpisodeRow: View {
    let episode: PodcastPreviewEpisode
    let podcastTitle: String
    let artworkURL: URL?
    let isCurrentlyPreviewing: Bool

    private let player = PlaybackController.shared

    var body: some View {
        Button {
            if isCurrentlyPreviewing {
                player.togglePlayPause()
            } else {
                player.playPreview(
                    title: episode.title,
                    podcastTitle: podcastTitle,
                    audioURL: episode.audioURL,
                    artworkURL: artworkURL
                )
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isCurrentlyPreviewing ? Color.offscriptAccent : Color.white.opacity(0.08))
                        .frame(width: 40, height: 40)

                    Image(systemName: isCurrentlyPreviewing && player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isCurrentlyPreviewing ? .black : Color.offscriptAccent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title)
                        .font(.offscriptBody.weight(.semibold))
                        .foregroundStyle(isCurrentlyPreviewing ? Color.offscriptAccent : Color.offscriptTextPrimary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if let pubDate = episode.pubDate {
                            Text(pubDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.offscriptMeta)
                                .foregroundStyle(Color.offscriptTextMuted)
                        }
                        if let duration = episode.duration {
                            Text("·")
                                .foregroundStyle(Color.offscriptTextMuted)
                            Text(EpisodeDurationFormatter.short(duration))
                                .font(.offscriptMeta)
                                .foregroundStyle(Color.offscriptTextMuted)
                        }
                    }
                }

                Spacer()

                if isCurrentlyPreviewing {
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.offscriptAccent)
                                .frame(width: 3, height: player.isPlaying ? CGFloat.random(in: 8...16) : 6)
                                .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: player.isPlaying)
                        }
                    }
                    .frame(width: 16)
                }
            }
            .padding(12)
            .offscriptUtilitySurface(radius: OffScriptTheme.Radius.small)
        }
        .buttonStyle(.plain)
    }
}

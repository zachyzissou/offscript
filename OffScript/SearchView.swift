import SwiftData
import SwiftUI

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var podcasts: [Podcast]
    @AppStorage("offscript.recentSearches") private var recentSearchesStorage = ""
    @State private var query = ""
    @State private var isSearchActive = false
    @State private var results: [PodcastSearchResult] = []
    @State private var isSearching = false
    @State private var importingID: String?
    @State private var errorMessage: String?

    private let searchService = PodcastSearchService()
    private let syncService = FeedSyncService()
    private let starterTopics = ["Tech", "News", "Comedy", "Design", "Business", "Culture"]

    private var subscribedFeedURLs: Set<String> {
        Set(podcasts.filter(\.isSubscribed).map { $0.feedURL.absoluteString })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                if !isSearchActive {
                    SearchHeader()
                }

                if query.isEmpty, !isSearchActive {
                    SearchPromptCard()
                        .padding(.horizontal, OffScriptTheme.pagePadding)

                    StarterTopicsSection(
                        topics: starterTopics,
                        onSelect: { topic in
                            query = topic
                        }
                    )

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

                if isSearching {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.offscriptAccent)
                        Text("Searching podcasts, hosts, and topics...")
                            .font(.offscriptBody)
                            .foregroundStyle(Color.offscriptTextSecondary)
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                } else if results.isEmpty, !query.isEmpty {
                    ContentUnavailableView("No podcasts found", systemImage: "magnifyingglass", description: Text("Try another show, host, or topic."))
                        .padding(.horizontal, OffScriptTheme.pagePadding)
                } else if !results.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        OffScriptSectionHeader(
                            title: "Results",
                            subtitle: "Subscribe quickly and let OffScript turn a few good picks into a smarter feed."
                        )
                        .padding(.horizontal, OffScriptTheme.pagePadding)

                        LazyVStack(spacing: 14) {
                            ForEach(results) { result in
                                SearchResultCard(
                                    result: result,
                                    isAdded: subscribedFeedURLs.contains(result.feedURL.absoluteString),
                                    isImporting: importingID == result.id,
                                    onAdd: { Task { await add(result) } }
                                )
                                .padding(.horizontal, OffScriptTheme.pagePadding)
                            }
                        }
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 90)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .offscriptPageBackground()
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, isPresented: $isSearchActive, prompt: "Search podcasts or hosts")
        .task(id: query) { await search() }
    }

    private var recentSearches: [String] {
        recentSearchesStorage
            .split(separator: "\u{1F}")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    @MainActor
    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            errorMessage = nil
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            results = try await searchService.search(query: trimmed)
            errorMessage = nil
            storeRecentSearch(trimmed)
        } catch {
            errorMessage = "Search failed. Check your connection and try again."
        }
    }

    @MainActor
    private func add(_ result: PodcastSearchResult) async {
        importingID = result.id
        defer { importingID = nil }

        do {
            _ = try await syncService.importPodcast(from: result, into: modelContext)
            errorMessage = nil
            storeRecentSearch(result.title)
        } catch {
            errorMessage = "Couldn’t import \(result.title) yet."
        }
    }

    private func storeRecentSearch(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        items.insert(trimmed, at: 0)
        recentSearchesStorage = Array(items.prefix(6)).joined(separator: "\u{1F}")
    }
}

private struct SearchHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OffScriptUtilityHeader(
                eyebrow: "Search",
                title: "Find a signal worth following",
                subtitle: "Start with a show you trust or a topic you want more of. OffScript can work from either."
            )
        }
        .padding(.horizontal, OffScriptTheme.pagePadding)
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

private struct StarterTopicsSection: View {
    let topics: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OffScriptSectionHeader(
                title: "Starter Topics",
                subtitle: "A quick way to seed taste without knowing the exact show name yet."
            )
            .padding(.horizontal, OffScriptTheme.pagePadding)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
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
            .background(Color.red.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                    .stroke(Color.red.opacity(0.35), lineWidth: 1)
            )
    }
}

private struct SearchResultCard: View {
    let result: PodcastSearchResult
    let isAdded: Bool
    let isImporting: Bool
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
                Text(summary)
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Button(isAdded ? "Added" : (isImporting ? "Adding..." : "Add to Library")) {
                    onAdd()
                }
                .buttonStyle(PrimaryPillButtonStyle())
                .disabled(isImporting || isAdded)

                if let host = result.websiteURL {
                    Link(destination: host) {
                        Label("Open", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(SecondaryPillButtonStyle())
                }
            }

            if isAdded {
                Text("Added to your library. New episodes from this show will now shape your smart feed.")
                    .font(.offscriptMeta)
                    .foregroundStyle(Color.offscriptTextMuted)
            }
        }
        .padding(18)
        .offscriptUtilitySurface()
    }
}

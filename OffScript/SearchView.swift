import OSLog
import SwiftData
import SwiftUI

private let searchLogger = Logger(subsystem: "com.offscript", category: "Search")

// MARK: - SearchView (Tuner signal scan)

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var podcasts: [Podcast]
    let hidesRootNavigationBar: Bool
    @AppStorage("offscript.recentSearches") private var recentSearchesStorage = ""
    @State private var query = ""
    @State private var isSearchActive = false
    @State private var results: [PodcastSearchResult] = []
    @State private var isSearching = false
    @State private var importingID: String?
    @State private var errorMessage: String?
    @FocusState private var searchFieldFocused: Bool

    private let searchService = PodcastSearchService()
    private let syncService = FeedSyncService()
    private let starterTopics = ["Tech", "News", "Comedy", "Design", "Business", "Culture"]

    init(hidesRootNavigationBar: Bool = true) {
        self.hidesRootNavigationBar = hidesRootNavigationBar
    }

    private var subscribedFeedURLs: Set<String> {
        Set(podcasts.filter(\.isSubscribed).map { $0.feedURL.absoluteString })
    }

    var body: some View {
        // No `.searchable` — that modifier renders a system-default
        // rounded translucent search bar that floats over the page and
        // clashes with everything Tuner. Custom field below puts the
        // search input in the header where it belongs.
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SearchTunerHeader()
                tunerSearchField

                if query.isEmpty {
                    SearchPromptStrip()

                    StarterTopicsSection(
                        topics: starterTopics,
                        onSelect: { topic in query = topic }
                    )

                    if !recentSearches.isEmpty {
                        RecentSearchesSection(
                            items: recentSearches,
                            onSelect: { item in query = item },
                            onClear: { recentSearchesStorage = "" }
                        )
                    }
                }

                if let errorMessage {
                    SearchErrorStrip(message: errorMessage,
                                     onRetry: { Task { await search() } })
                }

                if isSearching {
                    searchSkeleton
                } else if results.isEmpty, !query.isEmpty {
                    emptyState
                } else if !results.isEmpty {
                    resultsSection
                }
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)
            .padding(.top, OffScriptTheme.rootContentTopPadding)
            .padding(.bottom, 90)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
        .accessibilityIdentifier("SearchScreen")
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(hidesRootNavigationBar ? .hidden : .visible, for: .navigationBar)
        .toolbarBackground(Color.offscriptStudioBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: query) { await search() }
        .onReceive(NotificationCenter.default.publisher(for: .offscriptActiveTabChanged)) { note in
            guard let tab = note.userInfo?["tab"] as? String, tab != "search" else { return }
            searchFieldFocused = false
        }
    }

    /// Custom Tuner search input — hairline rectangle with mono prompt,
    /// signal-yellow magnifier glyph, and an inline × clear button when
    /// there's text. Sits in the page header instead of the floating
    /// system search bar.
    private var tunerSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.offscriptSignalYellow)

            TextField("Search podcasts or hosts", text: $query, prompt: Text("SEARCH PODCASTS OR HOSTS")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.offscriptSoftPaper))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFieldFocused)
                .font(.system(size: 13))
                .foregroundStyle(Color.offscriptPaperWhite)
                .accentColor(Color.offscriptSignalYellow)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.offscriptSoftPaper)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
    }

    private var searchSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { idx in
                HStack(spacing: 12) {
                    Rectangle().fill(Color.offscriptFillSubtle).frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 6) {
                        Rectangle().fill(Color.offscriptFillSubtle).frame(width: 70, height: 9)
                        Rectangle().fill(Color.offscriptFillSubtle).frame(width: 160, height: 12)
                        Rectangle().fill(Color.offscriptFillSubtle).frame(width: 110, height: 9)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                if idx < 2 {
                    Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                }
            }
        }
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
        .shimmer()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
            TunerLabel(text: "● NO MATCHES", color: .offscriptSoftPaper)
            Text("No matches")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.offscriptPaperWhite)
            Text("Try a different show name, host, or topic. Exact titles work best.")
                .font(.system(size: 13.5))
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineSpacing(2)
        }
        .padding(.top, 8)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
            HStack {
                TunerLabel(text: "RESULTS · SCAN COMPLETE", color: .offscriptSignalYellow)
                Spacer()
                TunerLabel(text: "\(results.count) FOUND", color: .offscriptFnInfo)
            }

            LazyVStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    SearchResultRow(
                        result: result,
                        rank: index + 1,
                        isAdded: subscribedFeedURLs.contains(result.feedURL.absoluteString),
                        isImporting: importingID == result.id,
                        onAdd: { Task { await add(result) } }
                    )
                    if index < results.count - 1 {
                        Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var recentSearches: [String] {
        // U+001F (UNIT SEPARATOR) is a control char that won't appear in
        // typed search terms. We still defensively reject any item that
        // contains it on store, but parsing here just splits and filters
        // empties.
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
            searchLogger.error("Search failed for query '\(trimmed, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            errorMessage = "Apple Podcasts Search failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func add(_ result: PodcastSearchResult) async {
        importingID = result.id
        defer { importingID = nil }

        do {
            _ = try syncService.subscribeThenHydrate(from: result, into: modelContext)
            errorMessage = nil
            storeRecentSearch(result.title)
        } catch {
            searchLogger.error("Import failed for ‘\(result.title, privacy: .public)’: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn’t import \(result.title): \(error.localizedDescription)"
        }
    }

    private func storeRecentSearch(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Reject queries that contain our delimiter — `split(separator:)`
        // would corrupt the recent-searches list otherwise. U+001F should
        // never appear in real input, but we don't rely on that.
        guard !trimmed.contains("\u{1F}") else { return }
        var items = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        items.insert(trimmed, at: 0)
        recentSearchesStorage = Array(items.prefix(6)).joined(separator: "\u{1F}")
    }
}

// MARK: - Header + sections

private struct SearchTunerHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TunerLabel(text: "SEARCH · SIGNAL SCAN", color: .offscriptSignalYellow)
                Spacer()
                TunerLabel(text: "RSS · ITUNES", color: .offscriptFnInfo)
            }
            Text("Search")
                .font(.system(size: 32, weight: .bold))
                .tracking(0)
                .foregroundStyle(Color.offscriptPaperWhite)
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                .padding(.top, 4)
        }
    }
}

private struct SearchPromptStrip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TunerLabel(text: "● TUNING TIP", color: .offscriptFnInfo)
            Text("Three strong inputs")
                .font(.system(size: 16, weight: .semibold))
                .tracking(0)
                .foregroundStyle(Color.offscriptPaperWhite)
            Text("Search uses Apple Podcasts results and imports RSS feeds. Exact show or host names work best; topics are broader catalog scans.")
                .font(.system(size: 13))
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineSpacing(2)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
    }
}

private struct StarterTopicsSection: View {
    let topics: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
            TunerLabel(text: "STARTER TOPICS", color: .offscriptSignalYellow)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: 6)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(topics, id: \.self) { topic in
                    Button {
                        onSelect(topic)
                    } label: {
                        TunerLabel(text: topic.uppercased(), color: .offscriptPaperWhite, size: 10)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search for \(topic)")
                }
            }
        }
    }
}

private struct RecentSearchesSection: View {
    let items: [String]
    let onSelect: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
            HStack {
                TunerLabel(text: "RECENT SEARCHES", color: .offscriptSignalYellow)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { onClear() }
                } label: {
                    TunerLabel(text: "× CLEAR", color: .offscriptFnRecord, size: 9)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear recent searches")
            }

            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element) { idx, item in
                    Button {
                        onSelect(item)
                    } label: {
                        HStack {
                            Text(String(format: "%02d", idx + 1))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .tracking(1.0)
                                .foregroundStyle(Color.offscriptSignalYellow)
                                .frame(width: 28, alignment: .leading)
                            Text(item)
                                .font(.system(size: 14))
                                .foregroundStyle(Color.offscriptPaperWhite)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.offscriptSoftPaper)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search again for \(item)")
                    if idx < items.count - 1 {
                        Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                    }
                }
            }
        }
    }
}

private struct SearchErrorStrip: View {
    let message: String
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TunerLabel(text: "● SEARCH ERROR", color: .offscriptFnRecord)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.offscriptPaperWhite)

            // Retry key — surfaces a way out for transient network errors
            // without requiring the user to mutate the query.
            if let onRetry {
                Button(action: onRetry) {
                    TunerLabel(text: "↻ RETRY",
                               color: .offscriptSignalYellow, size: 10)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry search")
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptFnRecord).frame(height: 1),
            alignment: .top
        )
    }
}

// MARK: - Result row

private struct SearchResultRow: View {
    let result: PodcastSearchResult
    let rank: Int
    let isAdded: Bool
    let isImporting: Bool
    let onAdd: () -> Void
    @State private var safariURL: IdentifiableURL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(String(format: "%02d", rank))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Color.offscriptSignalYellow)
                    .frame(width: 28, alignment: .leading)
                    .padding(.top, 4)

                OffScriptArtworkView(url: result.artworkURL, cornerRadius: 3)
                    .frame(width: 64, height: 64)
                    .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        TunerLabel(
                            text: isAdded ? "● IN LIBRARY" : "○ RSS IMPORT",
                            color: isAdded ? .offscriptFnMode : .offscriptSoftPaper,
                            size: 8
                        )
                    }
                    Text(result.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .lineLimit(2)
                    TunerLabel(text: result.author.uppercased(), color: .offscriptSoftPaper, size: 8)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let summary = result.summary {
                Text(summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.offscriptPaperWhite.opacity(0.75))
                    .lineLimit(2)
                    .padding(.leading, 28 + 12 + 64 + 12) // align under text column
            }

            HStack(spacing: 8) {
                Spacer().frame(width: 28 + 12 + 64 + 12)
                Button {
                    onAdd()
                } label: {
                    TunerLabel(
                        text: isAdded ? "✓ ADDED" : (isImporting ? "○ ADDING…" : "+ ADD TO LIBRARY"),
                        color: isAdded ? .offscriptFnMode : .offscriptSignalYellow,
                        size: 10
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .overlay(Rectangle().stroke(
                        isAdded ? Color.offscriptFnMode : Color.offscriptSignalYellow,
                        lineWidth: 1
                    ))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isImporting || isAdded)
                .accessibilityLabel(
                    isAdded
                        ? "\(result.title) is already in your library"
                        : (isImporting ? "Adding \(result.title) to library" : "Add \(result.title) to library")
                )

                if let host = result.websiteURL {
                    Button {
                        safariURL = IdentifiableURL(url: host)
                    } label: {
                        TunerLabel(text: "→ WEBSITE", color: .offscriptPaperWhite, size: 10)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(result.title) website")
                }
                Spacer()
            }
        }
        .padding(.vertical, 10)
        .sheet(item: $safariURL) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
                .tunerModalSurface()
        }
    }
}

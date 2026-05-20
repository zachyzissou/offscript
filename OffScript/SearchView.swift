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
    @State private var results: [PodcastSearchResult] = []
    @State private var isSearching = false
    /// Per-row in-flight import set keyed by `PodcastSearchResult.id`.
    /// A `Set` (not a single value) so concurrent imports across rows
    /// don't reset each other's `○ ADDING…` state when a second row is
    /// tapped while the first is still staging/hydrating.
    @State private var importingIDs: Set<String> = []
    @State private var errorMessage: String?
    /// Per-row import error keyed by `PodcastSearchResult.id` so a single
    /// failed `+ ADD TO LIBRARY` tap renders an actionable RETRY on the
    /// row that failed instead of vanishing into the global error strip
    /// (#123 — search subscribe-flow error states).
    @State private var importErrors: [String: String] = [:]
    /// Lazy latest-episode preview cache shared across rows. Rows above the
    /// fold ask for a preview when they appear; everything below the cap
    /// renders the no-preview shape so layout doesn't shift on scroll.
    @State private var previewLoader = SearchPreviewLoader()
    @FocusState private var searchFieldFocused: Bool

    private let searchService = PodcastSearchService()
    private let syncService = FeedSyncService()
    private let starterTopics = ["Tech", "News", "Comedy", "Design", "Business", "Culture"]

    init(hidesRootNavigationBar: Bool = true) {
        self.hidesRootNavigationBar = hidesRootNavigationBar
    }

    private var subscribedFeedURLs: Set<String> {
        Set(podcasts.filter(\.isSubscribed).map { $0.feedURL.normalizedFeedKey })
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
        .refreshable {
            // Pull-to-refresh re-runs the active search so the user can
            // dismiss a stale `SEARCH ERROR` strip or pull in newly
            // catalogued shows without mutating the query. `search()` has
            // its own internal `trimmed.count >= 2` gate, so we don't
            // duplicate the trim here — the gesture is harmless on the
            // starter-topics + recent-searches landing because the gate
            // short-circuits.
            await search()
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
                .accessibilityHidden(true)

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
                .buttonStyle(.tunerPress)
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
        TunerEmptyState(
            status: "● NO MATCHES",
            title: "No shows found",
            message: "Try a different show name, host, or topic. Exact titles work best."
        ) {
            // One-tap reset to the starter-topics + recent-searches
            // landing state. Mirrors the × CLEAR FILTER recovery key on
            // PodcastDetail (#208) and Library directory (#220).
            Button {
                query = ""
            } label: {
                TunerLabel(text: "× CLEAR SEARCH", color: .offscriptSignalYellow, size: 10)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.tunerPress)
            .accessibilityLabel("Clear search query")
            .accessibilityIdentifier("SearchEmptyClearSearch")
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
                    let resultKey = result.feedURL.normalizedFeedKey
                    SearchResultRow(
                        result: result,
                        rank: index + 1,
                        isAdded: subscribedFeedURLs.contains(resultKey),
                        isImporting: importingIDs.contains(resultKey),
                        importError: importErrors[resultKey],
                        // Pull preview state at render-time so the
                        // `@Observable` loader can update individual rows
                        // as fetches complete without re-running the
                        // search query.
                        previewState: previewLoader.state(for: result, rank: index + 1),
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
        // Any query change should cancel in-flight preview fetches that
        // were scheduled for the previous result set. The loader's cache
        // is preserved, so flipping back to a previous query stays
        // instant for rows we already resolved.
        previewLoader.cancelAllInFlight()
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
        let resultKey = result.feedURL.normalizedFeedKey
        importingIDs.insert(resultKey)
        defer { importingIDs.remove(resultKey) }
        // Clear any prior failure for this row before a retry so the
        // button doesn't render the stale `✗ FAILED · RETRY` state
        // while the new attempt is in flight.
        importErrors[resultKey] = nil

        // Stage the subscription synchronously so the row flips to
        // `● IN LIBRARY` immediately, then await the hydration sync so
        // an async feed-fetch failure (e.g. airplane mode mid-import)
        // can surface as a row-scoped FAILED state instead of being
        // swallowed by `subscribeThenHydrate`'s detached `try?` Task.
        let podcast: Podcast
        do {
            podcast = try syncService.subscribeThenHydrate(
                from: result,
                into: modelContext,
                startHydration: false
            )
            storeRecentSearch(result.title)
        } catch {
            searchLogger.error("Stage failed for ‘\(result.title, privacy: .public)’: \(error.localizedDescription, privacy: .public)")
            importErrors[resultKey] = error.localizedDescription
            return
        }

        do {
            try await syncService.sync(
                podcast: podcast,
                in: modelContext,
                options: .singleAddBootstrap(episodeLimit: 12)
            )
        } catch {
            searchLogger.error("Hydrate failed for ‘\(result.title, privacy: .public)’: \(error.localizedDescription, privacy: .public)")
            // Row-scoped error state — the row button now communicates the
            // failure and offers a retry without the user re-typing the
            // query or hunting for which row failed in a long results list.
            importErrors[resultKey] = error.localizedDescription
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
                            // 44pt min-height to meet HIG's tap target —
                            // padding alone (9pt × 2 + ~12pt label) only
                            // gave ~30pt, below the 44pt floor.
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.tunerPress)
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

    @State private var showClearConfirm: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
            HStack {
                TunerLabel(text: "RECENT SEARCHES", color: .offscriptSignalYellow)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showClearConfirm = true }
                } label: {
                    TunerLabel(text: "× CLEAR", color: .offscriptFnRecord, size: 9)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.tunerPress)
                .accessibilityIdentifier("RecentSearchesClear")
                .accessibilityLabel("Clear recent searches")
                .disabled(showClearConfirm)
            }

            if showClearConfirm {
                // Inline confirm strip — same vocabulary as Queue × CLEAR ALL
                // and Library × UNSUBSCRIBE so an accidental tap on × CLEAR
                // doesn't wipe history without a second deliberate tap.
                VStack(alignment: .leading, spacing: 8) {
                    TunerLabel(text: "● CONFIRM CLEAR", color: .offscriptFnRecord)
                    Text("Wipe all \(items.count) recent search\(items.count == 1 ? "" : "es")? This cannot be undone.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.offscriptPaperWhite)
                    // Equal-width CANCEL / × CONFIRM keys at 44pt min-height
                    // matches the established destructive-confirm vocabulary
                    // used by Queue × CLEAR ALL and Library × UNSUBSCRIBE.
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showClearConfirm = false }
                        } label: {
                            TunerLabel(text: "CANCEL", color: .offscriptPaperWhite, size: 11)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.tunerPress)
                        .accessibilityIdentifier("RecentSearchesClearCancel")
                        .accessibilityLabel("Cancel clear recent searches")

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showClearConfirm = false
                                onClear()
                            }
                        } label: {
                            TunerLabel(text: "× CONFIRM", color: .offscriptFnRecord, size: 11)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.tunerPress)
                        .accessibilityIdentifier("RecentSearchesClearConfirm")
                        .accessibilityLabel("Confirm clear recent searches")
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 10)
                .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
            }

            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element) { idx, item in
                    Button {
                        onSelect(item)
                    } label: {
                        HStack {
                            Text(String(format: "%02d", idx + 1))
                                .tunerFont(size: 11, tracking: 1.0)
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
                    .buttonStyle(.tunerPress)
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
        TunerEmptyState(
            status: "● SEARCH ERROR",
            title: "Search unavailable",
            message: message,
            statusColor: .offscriptFnRecord
        ) {
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
                .buttonStyle(.tunerPress)
                .accessibilityLabel("Retry search")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Result row

private struct SearchResultRow: View {
    let result: PodcastSearchResult
    let rank: Int
    let isAdded: Bool
    let isImporting: Bool
    /// Optional row-scoped import error message. When non-nil, the
    /// `+ ADD TO LIBRARY` key flips to `✗ FAILED · RETRY` in the
    /// `offscriptFnRecord` accent and the failure detail renders below
    /// the action row, so a long results list still tells the user
    /// which row failed and gives them a one-tap recovery path.
    let importError: String?
    /// Latest-episode preview state for this row. `nil` means the row was
    /// beyond the loader's preview cap and is intentionally not fetching;
    /// the row renders the no-preview shape, identical to `.failed`.
    let previewState: SearchPreviewLoader.PreviewState?
    let onAdd: () -> Void
    @State private var safariURL: IdentifiableURL?

    /// Leading inset of the row's text/action column — 28pt rank gutter
    /// + 12pt gap + 64pt artwork + 12pt gap. Centralized so the summary
    /// padding, action-row spacer, and inline error strip stay aligned
    /// under one knob (Copilot review on #199).
    private static let contentColumnLeadingInset: CGFloat = 28 + 12 + 64 + 12

    private var hasImportError: Bool { importError != nil && !isImporting && !isAdded }
    private var actionLabel: String {
        if isAdded { return "✓ ADDED" }
        if isImporting { return "○ ADDING…" }
        if hasImportError { return "✗ FAILED · RETRY" }
        return "+ ADD TO LIBRARY"
    }
    private var actionColor: Color {
        if isAdded { return .offscriptFnMode }
        if hasImportError { return .offscriptFnRecord }
        return .offscriptSignalYellow
    }

    /// Single VoiceOver readout for the descriptive zone. Without an
    /// `.accessibilityElement(children: .ignore)` + custom label, VO
    /// walks rank + status chip + title + author as four separate stops
    /// per row, so a 25-result list balloons to ~100 stops before
    /// reaching the action keys. Mirrors the combine pass applied to
    /// LibraryDirectoryRow (#246) and PodcastEpisodeTunerRow.
    /// Author may be an empty string (TopPodcastsService fallback) — we
    /// drop the clause entirely in that case so VO doesn't read a
    /// dangling "by".
    private var rowVoiceOverLabel: String {
        var parts: [String] = ["Result \(rank)"]
        if isAdded { parts.append("in library") }
        parts.append(result.title)
        let trimmedAuthor = result.author.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAuthor.isEmpty {
            parts.append("by \(trimmedAuthor)")
        }
        // Roll the latest-episode preview into the same accessibility
        // element. Without this VO would either skip the preview block or
        // walk it as separate stops (chip, title, duration) per row.
        if case .loaded(let metadata) = previewState {
            parts.append("Latest episode: \(metadata.latestEpisodeTitle)")
            parts.append("posted \(metadata.freshnessSpoken)")
            if !metadata.durationSpoken.isEmpty {
                parts.append(metadata.durationSpoken)
            }
        }
        return parts.joined(separator: ", ")
    }

    /// Latest-episode preview block, rendered between the artwork/title
    /// header and the action row. Three states:
    ///
    /// - `.loaded(metadata)` shows `● LATEST · 3D AGO` chip, the episode
    ///   title in body-weight, and a `3D AGO · 47M` metadata strip.
    /// - `.loading` shows a shimmering skeleton sized to match the loaded
    ///   layout so the row doesn't jump when the fetch completes.
    /// - `.failed` and `nil` render nothing — the row falls back to the
    ///   pre-existing shape. We deliberately don't surface a "preview
    ///   failed" error chip: a stale RSS server isn't the user's problem,
    ///   and the row's main info (title/author/genre) still lets them
    ///   subscribe.
    @ViewBuilder
    private var previewBlock: some View {
        switch previewState {
        case .loaded(let metadata):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    TunerLabel(
                        text: "● LATEST · \(metadata.freshnessLabel)",
                        color: .offscriptFnInfo,
                        size: 8
                    )
                }
                Text(metadata.latestEpisodeTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !metadata.durationLabel.isEmpty {
                    TunerLabel(
                        text: "\(metadata.freshnessLabel) · \(metadata.durationLabel)",
                        color: .offscriptSoftPaper,
                        size: 8
                    )
                }
            }
            .accessibilityHidden(true)
        case .loading:
            VStack(alignment: .leading, spacing: 6) {
                Rectangle().fill(Color.offscriptFillSubtle).frame(width: 90, height: 8)
                Rectangle().fill(Color.offscriptFillSubtle).frame(maxWidth: .infinity, alignment: .leading).frame(height: 12)
                Rectangle().fill(Color.offscriptFillSubtle).frame(width: 110, height: 8)
            }
            .shimmer()
            .accessibilityHidden(true)
        case .failed, .none:
            EmptyView()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(String(format: "%02d", rank))
                    .tunerFont(size: 11, tracking: 1.0)
                    .foregroundStyle(Color.offscriptSignalYellow)
                    .frame(width: 28, alignment: .leading)
                    .padding(.top, 4)

                OffScriptArtworkView(url: result.artworkURL, cornerRadius: 3)
                    .frame(width: 64, height: 64)
                    .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                    .accessibilityHidden(true)

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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rowVoiceOverLabel)

            if let summary = result.summary {
                Text(summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.offscriptPaperWhite.opacity(0.75))
                    .lineLimit(2)
                    .padding(.leading, Self.contentColumnLeadingInset) // align under text column
            }

            // Latest-episode preview — the OffScript pitch made concrete.
            // Before this, a stranger had to subscribe blind based on
            // title + genre alone. Now they see what they'd actually
            // start with, when it dropped, and how long it runs. The
            // block is rolled into the same VO element as the row's
            // descriptive zone (see `rowVoiceOverLabel`) so screen-reader
            // walks don't multiply by 3-4× per result.
            previewBlock
                .padding(.leading, Self.contentColumnLeadingInset)

            HStack(spacing: 8) {
                Spacer().frame(width: Self.contentColumnLeadingInset)
                Button {
                    onAdd()
                } label: {
                    TunerLabel(
                        text: actionLabel,
                        color: actionColor,
                        size: 10
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .overlay(Rectangle().stroke(actionColor, lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.tunerPress)
                .disabled(isImporting || isAdded)
                .accessibilityLabel(
                    isAdded
                        ? "\(result.title) is already in your library"
                        : (isImporting
                            ? "Adding \(result.title) to library"
                            : (hasImportError
                                ? "Retry adding \(result.title) to library"
                                : "Add \(result.title) to library"))
                )
                .accessibilityHint(hasImportError ? (importError ?? "") : "")
                .accessibilityIdentifier(
                    hasImportError ? "SearchResultRow.RetryAdd.\(result.id)" : "SearchResultRow.Add.\(result.id)"
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
                    .buttonStyle(.tunerPress)
                    .accessibilityLabel("Open \(result.title) website")
                }
                Spacer()
            }

            if hasImportError, let importError {
                HStack(alignment: .top, spacing: 8) {
                    Spacer().frame(width: Self.contentColumnLeadingInset)
                    VStack(alignment: .leading, spacing: 4) {
                        TunerLabel(text: "● IMPORT FAILED", color: .offscriptFnRecord, size: 8)
                        Text(importError)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.offscriptPaperWhite.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)
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

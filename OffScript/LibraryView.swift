import OSLog
import SwiftData
import SwiftUI

private let libraryLogger = Logger(subsystem: "com.offscript", category: "Library")

nonisolated enum LibraryDirectoryScope: String, CaseIterable, Identifiable {
    case all
    case unplayed
    case inProgress
    case needsSync

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "ALL"
        case .unplayed: "UNPLAYED"
        case .inProgress: "IN PROGRESS"
        case .needsSync: "NEEDS SYNC"
        }
    }
}

nonisolated enum LibraryDirectorySort: String, CaseIterable, Identifiable {
    case title
    case latest
    case attention

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: "A-Z"
        case .latest: "LATEST"
        case .attention: "ATTN"
        }
    }
}

nonisolated enum LibraryDirectoryDensity: String, CaseIterable, Identifiable {
    case compact
    case artwork

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: "COMPACT"
        case .artwork: "ARTWORK"
        }
    }
}

nonisolated struct LibraryDirectorySection: Identifiable {
    let id: String
    let title: String
    let podcasts: [Podcast]
}

nonisolated struct LibraryDirectorySnapshot {
    let podcasts: [Podcast]
    let sections: [LibraryDirectorySection]
    let numbersByPodcastID: [UUID: Int]

    var visibleCount: Int { podcasts.count }
    var isEmpty: Bool { podcasts.isEmpty }
}

nonisolated enum LibraryDirectoryOrganizer {
    static func snapshot(
        for podcasts: [Podcast],
        query: String,
        scope: LibraryDirectoryScope,
        sort: LibraryDirectorySort,
        unplayedCounts: [UUID: Int],
        inProgressCounts: [UUID: Int]
    ) -> LibraryDirectorySnapshot {
        let filtered = filteredPodcasts(
            podcasts,
            query: query,
            scope: scope,
            sort: sort,
            unplayedCounts: unplayedCounts,
            inProgressCounts: inProgressCounts
        )
        return LibraryDirectorySnapshot(
            podcasts: filtered,
            sections: sections(for: filtered),
            numbersByPodcastID: Dictionary(uniqueKeysWithValues: filtered.enumerated().map { ($0.element.id, $0.offset + 1) })
        )
    }

    static func filteredPodcasts(
        _ podcasts: [Podcast],
        query: String,
        scope: LibraryDirectoryScope,
        sort: LibraryDirectorySort,
        unplayedCounts: [UUID: Int],
        inProgressCounts: [UUID: Int]
    ) -> [Podcast] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = podcasts.filter { podcast in
            if !normalizedQuery.isEmpty {
                let fields = [
                    podcast.title,
                    podcast.author ?? "",
                    podcast.categories.joined(separator: " ")
                ].joined(separator: " ").lowercased()
                guard fields.contains(normalizedQuery) else { return false }
            }

            switch scope {
            case .all:
                return true
            case .unplayed:
                return (unplayedCounts[podcast.id] ?? 0) > 0
            case .inProgress:
                return (inProgressCounts[podcast.id] ?? 0) > 0
            case .needsSync:
                return podcast.syncFailureCount > 0
                    || podcast.syncStatus == "failed"
                    || podcast.syncStatus == "retrying"
            }
        }

        return filtered.sorted { lhs, rhs in
            switch sort {
            case .title:
                return titleSort(lhs, rhs)
            case .latest:
                let lhsDate = lhs.latestPubDate ?? lhs.subscribedAt ?? .distantPast
                let rhsDate = rhs.latestPubDate ?? rhs.subscribedAt ?? .distantPast
                if lhsDate == rhsDate { return titleSort(lhs, rhs) }
                return lhsDate > rhsDate
            case .attention:
                let lhsScore = attentionScore(lhs, unplayedCounts: unplayedCounts, inProgressCounts: inProgressCounts)
                let rhsScore = attentionScore(rhs, unplayedCounts: unplayedCounts, inProgressCounts: inProgressCounts)
                if lhsScore == rhsScore { return titleSort(lhs, rhs) }
                return lhsScore > rhsScore
            }
        }
    }

    static func sections(for podcasts: [Podcast]) -> [LibraryDirectorySection] {
        let grouped = Dictionary(grouping: podcasts) { podcast in
            sectionTitle(for: podcast.title)
        }

        return grouped.keys.sorted(by: sectionSort).map { title in
            LibraryDirectorySection(
                id: "library-section-\(title)",
                title: title,
                podcasts: grouped[title] ?? []
            )
        }
    }

    private static func attentionScore(
        _ podcast: Podcast,
        unplayedCounts: [UUID: Int],
        inProgressCounts: [UUID: Int]
    ) -> Int {
        let syncPenalty = podcast.syncFailureCount > 0 || podcast.syncStatus == "failed" ? 10_000 : 0
        let inProgress = min(inProgressCounts[podcast.id] ?? 0, 99) * 100
        let unplayed = min(unplayedCounts[podcast.id] ?? 0, 99)
        return syncPenalty + inProgress + unplayed
    }

    private static func sectionTitle(for title: String) -> String {
        guard let first = title.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "#"
        }
        let scalar = String(first).uppercased()
        return scalar.range(of: "[A-Z]", options: .regularExpression) == nil ? "#" : scalar
    }

    private static func sectionSort(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == "#" { return false }
        if rhs == "#" { return true }
        return lhs < rhs
    }

    private static func titleSort(_ lhs: Podcast, _ rhs: Podcast) -> Bool {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

private extension BatchImportService.Phase {
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

// MARK: - LibraryView (Tuner channel directory)
//
//   ┌── LIBRARY · CHANNEL DIRECTORY ──────────────────┐
//   │  COUNTS [SHOWS · UNPLAYED · IN PROGRESS]        │
//   │  Library                                        │
//   │  ── CONTINUE LISTENING (rail)                   │
//   │  ── FRESH EPISODES (rail)                       │
//   │  ── SHOWS (hairline-listed channel rows)        │
//   └─────────────────────────────────────────────────┘

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var batchImporter = BatchImportService.shared
    @Query(
        filter: #Predicate<Podcast> { $0.isSubscribed },
        sort: [SortDescriptor(\Podcast.title)]
    )
    private var podcasts: [Podcast]

    // Predicate-filtered query for the small in-progress set. Fresh/unplayed
    // summary data is loaded below with fetch limits and fetchCount so Library
    // does not materialize a full back catalog just to draw the first rail.
    @Query(
        filter: #Predicate<Episode> { $0.podcast.isSubscribed && !$0.isPlayed && $0.playedPosition > 0 },
        sort: [SortDescriptor(\Episode.lastPlayedAt, order: .reverse)]
    )
    private var inProgressEpisodes: [Episode]

    let onOpenSettings: () -> Void

    private let syncService = FeedSyncService()
    @State private var isImportPresented = false
    @State private var directoryQuery = ""
    @State private var effectiveDirectoryQuery = ""
    @State private var directoryScope: LibraryDirectoryScope = .all
    @State private var directorySort: LibraryDirectorySort = .title
    @State private var directoryDensity: LibraryDirectoryDensity = .compact
    @State private var selectedDirectorySectionID: String?
    @State private var freshEpisodes: [Episode] = []
    @State private var unplayedEpisodeCount = 0
    @State private var freshCountsByPodcastID: [UUID: Int] = [:]
    @State private var summaryLoadTask: Task<Void, Never>?
    @State private var directoryQueryTask: Task<Void, Never>?

    private var subscribedPodcasts: [Podcast] {
        podcasts
    }

    private var directorySnapshot: LibraryDirectorySnapshot {
        LibraryDirectoryOrganizer.snapshot(
            for: subscribedPodcasts,
            query: effectiveDirectoryQuery,
            scope: directoryScope,
            sort: directorySort,
            unplayedCounts: freshCountsByPodcastID,
            inProgressCounts: inProgressCountsByPodcastID
        )
    }

    private var isCompactDirectory: Bool {
        directoryDensity == .compact || subscribedPodcasts.count >= 120
    }

    private var inProgressCountsByPodcastID: [UUID: Int] {
        Dictionary(inProgressEpisodes.map { ($0.podcast.id, 1) }, uniquingKeysWith: +)
    }

    private var subscribedPodcastIDs: [UUID] {
        subscribedPodcasts.map(\.id)
    }

    var body: some View {
        let snapshot = directorySnapshot
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LibraryTunerHeader(
                        showCount: subscribedPodcasts.count,
                        visibleCount: snapshot.visibleCount,
                        unplayedCount: unplayedEpisodeCount,
                        inProgressCount: inProgressEpisodes.count,
                        onOpenImport: { isImportPresented = true },
                        onOpenSettings: onOpenSettings
                    )

                    // Background OPML import status — visible whenever the
                    // batch importer is mid-flight or has just finished and
                    // hasn't been dismissed yet.
                    LibraryBatchImportStrip()

                    if subscribedPodcasts.isEmpty {
                        emptyState
                    } else {
                        if !inProgressEpisodes.isEmpty {
                            TunerEpisodeRail(
                                title: "CONTINUE LISTENING",
                                episodes: Array(inProgressEpisodes.prefix(8)),
                                reasonProvider: { ep in
                                    if let dur = ep.duration {
                                        return "\(EpisodeDurationFormatter.short(max(dur - ep.playedPosition, 0))) LEFT"
                                    }
                                    return "IN PROGRESS"
                                }
                            )
                        }

                        if !freshEpisodes.isEmpty {
                            TunerEpisodeRail(
                                title: "FRESH EPISODES",
                                episodes: Array(freshEpisodes.prefix(10)),
                                reasonProvider: { ep in
                                    if let dur = ep.duration {
                                        return "FRESH · \(EpisodeDurationFormatter.short(dur).uppercased())"
                                    }
                                    return "FRESH"
                                }
                            )
                        }

                        LibraryDirectoryControls(
                            query: $directoryQuery,
                            scope: $directoryScope,
                            sort: $directorySort,
                            density: $directoryDensity,
                            isForcedCompact: subscribedPodcasts.count >= 120
                        )

                        showsSection(snapshot: snapshot, scrollProxy: scrollProxy)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OffScriptTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 90)
            }
        }
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
        .accessibilityIdentifier("LibraryScreen")
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.offscriptStudioBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadLibraryEpisodeSummary() }
        .onAppear { effectiveDirectoryQuery = directoryQuery }
        .onChange(of: subscribedPodcastIDs) { _, _ in scheduleLibraryEpisodeSummaryLoad() }
        .onChange(of: directoryQuery) { _, newValue in scheduleDirectoryQuery(newValue) }
        .onChange(of: batchImporter.phase) { _, phase in
            if !phase.isRunning {
                loadLibraryEpisodeSummary()
            }
        }
        .onDisappear {
            summaryLoadTask?.cancel()
            directoryQueryTask?.cancel()
        }
        .refreshable { await syncSubscriptions() }
        // Settings + Import buttons render inline in LibraryTunerHeader, not
        // as toolbar items — iOS 26 wraps toolbar buttons in glass chrome.
        .sheet(isPresented: $isImportPresented) {
            LibraryImportSheet()
                .tunerModalSurface()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            TunerLabel(text: "● NO CHANNELS TUNED", color: .offscriptFnInfo)
            Text("Your library is empty")
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(Color.offscriptPaperWhite)
            Text("Use Search to bring in shows. OffScript keeps them fresh here once you subscribe.")
                .font(.system(size: 13.5))
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineSpacing(2)

            NavigationLink {
                SearchView()
            } label: {
                HStack {
                    TunerLabel(text: "→ FIND SHOWS", color: .offscriptSignalYellow, size: 11)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.top, 16)
    }

    private func showsSection(snapshot: LibraryDirectorySnapshot, scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
            HStack {
                TunerLabel(text: "SHOWS · DIRECTORY", color: .offscriptSignalYellow)
                Spacer()
                TunerLabel(
                    text: snapshot.visibleCount == subscribedPodcasts.count
                        ? "\(subscribedPodcasts.count) VISIBLE"
                        : "\(snapshot.visibleCount)/\(subscribedPodcasts.count) VISIBLE",
                    color: .offscriptSoftPaper,
                    size: 8
                )
            }

            if snapshot.isEmpty {
                LibraryDirectoryEmptyState(query: effectiveDirectoryQuery, scope: directoryScope)
            } else {
                LibraryAlphabetRail(
                    sections: snapshot.sections,
                    selectedSectionID: selectedDirectorySectionID
                ) { sectionID in
                    selectedDirectorySectionID = sectionID
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo(sectionID, anchor: .top)
                    }
                }

                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(snapshot.sections) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                TunerLabel(text: section.title, color: .offscriptSignalYellow, size: 10)
                                    .accessibilityIdentifier("LibrarySectionHeader\(section.title)")
                                Spacer()
                                TunerLabel(text: "\(section.podcasts.count) CH", color: .offscriptSoftPaper, size: 8)
                            }
                            .padding(.top, 12)
                            .padding(.bottom, 6)
                            .id(section.id)

                            ForEach(Array(section.podcasts.enumerated()), id: \.element.id) { idx, podcast in
                                NavigationLink {
                                    PodcastDetailView(podcast: podcast)
                                } label: {
                                    PodcastShelfRow(
                                        podcast: podcast,
                                        channelNumber: snapshot.numbersByPodcastID[podcast.id] ?? (idx + 1),
                                        unplayedCount: freshCountsByPodcastID[podcast.id] ?? 0,
                                        inProgressCount: inProgressCountsByPodcastID[podcast.id] ?? 0,
                                        isCompact: isCompactDirectory
                                    )
                                }
                                .buttonStyle(.plain)

                                if idx < section.podcasts.count - 1 {
                                    Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                                }
                            }
                        }

                        Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    @MainActor
    private func loadLibraryEpisodeSummary() {
        summaryLoadTask?.cancel()
        guard !subscribedPodcasts.isEmpty else {
            freshEpisodes = []
            unplayedEpisodeCount = 0
            freshCountsByPodcastID = [:]
            return
        }

        do {
            let descriptor = FetchDescriptor<Episode>(
                predicate: #Predicate<Episode> { $0.podcast.isSubscribed && !$0.isPlayed },
                sortBy: [SortDescriptor(\Episode.pubDate, order: .reverse)]
            )
            let unplayedEpisodes = try modelContext.fetch(descriptor)
            unplayedEpisodeCount = unplayedEpisodes.count
            freshEpisodes = Array(unplayedEpisodes.prefix(10))
            freshCountsByPodcastID = Dictionary(unplayedEpisodes.map { ($0.podcast.id, 1) }, uniquingKeysWith: +)
        } catch {
            freshEpisodes = []
            unplayedEpisodeCount = 0
            freshCountsByPodcastID = [:]
            libraryLogger.error("Library summary load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func scheduleLibraryEpisodeSummaryLoad() {
        summaryLoadTask?.cancel()
        summaryLoadTask = Task { @MainActor in
            if batchImporter.isRunning {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled, !batchImporter.isRunning else { return }
            }
            loadLibraryEpisodeSummary()
        }
    }

    @MainActor
    private func scheduleDirectoryQuery(_ query: String) {
        directoryQueryTask?.cancel()
        directoryQueryTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            effectiveDirectoryQuery = query
        }
    }

    @MainActor
    private func syncSubscriptions() async {
        for podcast in subscribedPodcasts {
            do {
                try await syncService.sync(podcast: podcast, in: modelContext)
            } catch {
                libraryLogger.error("Pull-to-refresh sync failed for '\(podcast.title, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }
        loadLibraryEpisodeSummary()
    }
}

// MARK: - Header

private struct LibraryTunerHeader: View {
    let showCount: Int
    let visibleCount: Int
    let unplayedCount: Int
    let inProgressCount: Int
    let onOpenImport: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TunerLabel(text: "LIBRARY · CHANNEL DIRECTORY", color: .offscriptSignalYellow)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Library")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Color.offscriptPaperWhite)
                Spacer()
                // Import key — paste URL or import OPML. The most-asked-for
                // missing feature in podcast apps; lives next to settings
                // since both are operational chrome rather than per-content.
                Button(action: onOpenImport) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.offscriptSignalYellow)
                        .frame(width: 36, height: 30)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Import podcasts")

                Button(action: onOpenSettings) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.offscriptSignalYellow)
                        .frame(width: 36, height: 30)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open settings")
            }

            // Inline mono readout — no surface, just hairline bar between
            HStack(spacing: 14) {
                statReadout(label: "SHOWS", value: showCount)
                Rectangle().fill(Color.offscriptHairline).frame(width: 1, height: 24)
                statReadout(label: "VISIBLE", value: visibleCount)
                Rectangle().fill(Color.offscriptHairline).frame(width: 1, height: 24)
                statReadout(label: "UNPLAYED", value: unplayedCount)
                Rectangle().fill(Color.offscriptHairline).frame(width: 1, height: 24)
                statReadout(label: "IN PROGRESS", value: inProgressCount)
                Spacer()
            }
            .padding(.top, 6)

            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func statReadout(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(value))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.offscriptPaperWhite)
                .monospacedDigit()
            TunerLabel(text: label, color: .offscriptSoftPaper, size: 8)
        }
    }
}

// MARK: - Directory controls

private struct LibraryDirectoryControls: View {
    @Binding var query: String
    @Binding var scope: LibraryDirectoryScope
    @Binding var sort: LibraryDirectorySort
    @Binding var density: LibraryDirectoryDensity
    let isForcedCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TunerLabel(text: "DIRECTORY · CONTROL", color: .offscriptSignalYellow)
            tunerSearchField

            VStack(alignment: .leading, spacing: 8) {
                controlRow(label: "SCOPE") {
                    ForEach(LibraryDirectoryScope.allCases) { item in
                        modeButton(item.label, isSelected: scope == item) {
                            scope = item
                        }
                    }
                }

                controlRow(label: "SORT") {
                    ForEach(LibraryDirectorySort.allCases) { item in
                        modeButton(item.label, isSelected: sort == item) {
                            sort = item
                        }
                    }
                }

                controlRow(label: "ROWS") {
                    ForEach(LibraryDirectoryDensity.allCases) { item in
                        modeButton(item.label, isSelected: effectiveDensity == item, isDisabled: isForcedCompact && item == .artwork) {
                            guard !(isForcedCompact && item == .artwork) else { return }
                            density = item
                        }
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .overlay(Rectangle().fill(Color.offscriptHairline).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(Color.offscriptHairline).frame(height: 1), alignment: .bottom)
    }

    private var effectiveDensity: LibraryDirectoryDensity {
        isForcedCompact ? .compact : density
    }

    private var tunerSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.offscriptSignalYellow)

            TextField("Filter shows",
                      text: $query,
                      prompt: Text("FILTER SHOWS BY TITLE, AUTHOR, OR CATEGORY")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.offscriptSoftPaper))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(.system(size: 13))
                .foregroundStyle(Color.offscriptPaperWhite)
                .accentColor(Color.offscriptSignalYellow)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.offscriptSoftPaper)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear library filter")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
    }

    private func controlRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            TunerLabel(text: label, color: .offscriptSoftPaper, size: 8)
                .frame(width: 44, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    content()
                }
            }
        }
    }

    private func modeButton(
        _ title: String,
        isSelected: Bool,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            TunerLabel(
                text: title,
                color: isDisabled ? .offscriptSoftPaper.opacity(0.5) : (isSelected ? .offscriptStudioBlack : .offscriptPaperWhite),
                size: 9
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected && !isDisabled ? Color.offscriptSignalYellow : Color.clear)
            .overlay(
                Rectangle().stroke(
                    isSelected && !isDisabled ? Color.offscriptSignalYellow : Color.offscriptHairline,
                    lineWidth: 1
                )
            )
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct LibraryAlphabetRail: View {
    let sections: [LibraryDirectorySection]
    let selectedSectionID: String?
    let onSelect: (String) -> Void

    private let keys = ["#"] + (UnicodeScalar("A").value...UnicodeScalar("Z").value).compactMap { value in
        UnicodeScalar(value).map { String($0) }
    }

    private var sectionsByTitle: [String: LibraryDirectorySection] {
        Dictionary(uniqueKeysWithValues: sections.map { ($0.title, $0) })
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 44, maximum: 48), spacing: 4)],
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(keys, id: \.self) { key in
                let section = sectionsByTitle[key]
                let isSelected = selectedSectionID == section?.id

                if let section {
                    Button {
                        onSelect(section.id)
                    } label: {
                        letterKey(key, isSelected: isSelected, isDisabled: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Jump to \(key)")
                    .accessibilityIdentifier("LibraryJumpLetter\(key)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                } else {
                    letterKey(key, isSelected: false, isDisabled: true)
                        .accessibilityLabel("No \(key) channels")
                        .accessibilityIdentifier("LibraryJumpLetter\(key)")
                        .accessibilityAddTraits(.isStaticText)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func letterKey(_ key: String, isSelected: Bool, isDisabled: Bool) -> some View {
        Text(key)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(isDisabled ? Color.offscriptTextMuted : Color.offscriptSignalYellow)
            .frame(width: 30, height: 30)
            .background(isSelected ? Color.offscriptSignalYellow.opacity(0.14) : Color.clear)
            .overlay(
                Rectangle()
                    .stroke(
                        isSelected ? Color.offscriptSignalYellow : Color.offscriptHairline,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(isDisabled ? 0.42 : 1)
    }
}

private struct LibraryDirectoryEmptyState: View {
    let query: String
    let scope: LibraryDirectoryScope

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TunerLabel(text: "○ NO DIRECTORY MATCH", color: .offscriptSoftPaper)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.offscriptPaperWhite.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var message: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No subscribed shows match this filter."
        }
        return "No shows in \(scope.label.lowercased()) scope."
    }
}

// MARK: - Tuner episode rail

private struct TunerEpisodeRail: View {
    let title: String
    let episodes: [Episode]
    let reasonProvider: (Episode) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
            TunerLabel(text: title, color: .offscriptSignalYellow)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(episodes) { episode in
                        TunerLibraryCard(episode: episode, reason: reasonProvider(episode))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TunerLibraryCard: View {
    @Environment(\.modelContext) private var modelContext
    let episode: Episode
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                EpisodeDetailView(episode: episode)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    OffScriptArtworkView(
                        url: episode.artworkURL ?? episode.podcast.artworkURL,
                        cornerRadius: 3
                    )
                    .frame(width: 64, height: 64)
                    .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 4) {
                        TunerLabel(text: episode.podcast.title.uppercased(), color: .offscriptFnInfo, size: 8)
                            .lineLimit(1)
                        Text(episode.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.offscriptPaperWhite)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        TunerTag(text: reason, color: .offscriptSignalYellow, dim: true)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Button {
                    PlaybackController.shared.play(episode, in: modelContext)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.offscriptStudioBlack)
                        .frame(width: 30, height: 30)
                        .background(Color.offscriptSignalYellow)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(episode.title)")

                Button {
                    do { try QueueService.add(episode, in: modelContext) }
                    catch { libraryLogger.error("Queue add failed: \(error.localizedDescription, privacy: .public)") }
                } label: {
                    Image(systemName: episode.isQueued ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .frame(width: 30, height: 30)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(episode.isQueued)
                .accessibilityLabel(episode.isQueued ? "Already queued" : "Add \(episode.title) to queue")

                Spacer()
            }
        }
        .padding(10)
        .frame(width: 280, alignment: .leading)
        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
    }
}

// MARK: - Show row

private struct PodcastShelfRow: View {
    let podcast: Podcast
    let channelNumber: Int
    let unplayedCount: Int
    let inProgressCount: Int
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", channelNumber))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.offscriptSignalYellow)
                .frame(width: 28, alignment: .leading)

            if !isCompact {
                OffScriptArtworkView(url: podcast.artworkURL, cornerRadius: 3)
                    .frame(width: 56, height: 56)
                    .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(podcast.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(1)
                if let author = podcast.author {
                    TunerLabel(text: author.uppercased(), color: .offscriptSoftPaper, size: 8)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if inProgressCount > 0 {
                        TunerLabel(text: "● \(inProgressCount) IN PROGRESS", color: .offscriptFnInfo, size: 8)
                    }
                    TunerLabel(text: "\(unplayedCount) UNPLAYED", color: .offscriptSoftPaper, size: 8)
                }
            }

            Spacer()

            if isCompact, unplayedCount > 0 {
                Text("\(unplayedCount)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.offscriptSignalYellow)
                    .monospacedDigit()
                    .frame(minWidth: 24, alignment: .trailing)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.offscriptSignalYellow)
        }
        .padding(.vertical, isCompact ? 7 : 10)
    }
}

// MARK: - PodcastDetailView (Tuner channel detail)

struct PodcastDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let podcast: Podcast
    @State private var filter: EpisodeFilter = .all
    @State private var episodeSearchQuery = ""
    @State private var episodes: [Episode] = []
    @State private var matchingEpisodeCount = 0
    @State private var visibleLimit = 100
    @State private var hasMoreEpisodes = false
    @State private var loadError: String?
    @State private var searchLoadTask: Task<Void, Never>?

    init(podcast: Podcast) {
        self.podcast = podcast
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PodcastDetailTunerHeader(podcast: podcast, episodeCount: matchingEpisodeCount)

                // Custom Tuner search input — `.searchable()` renders a system
                // rounded translucent search bar on iOS 26 that clashes with
                // every other Tuner surface. Same pattern as SearchView's
                // tunerSearchField.
                tunerEpisodeSearchField

                FilterRow(selection: $filter)

                if let loadError {
                    TunerLabel(text: "LOAD ERROR · \(loadError.uppercased())", color: .offscriptFnRecord)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if episodes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        TunerLabel(text: "● NO EPISODES MATCH FILTER", color: .offscriptSoftPaper)
                        Text(episodeSearchQuery.isEmpty
                             ? "Change the filter or sync this feed again later."
                             : "No episodes match \"\(episodeSearchQuery)\".")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Color.offscriptPaperWhite)
                    }
                    .padding(.vertical, 12)
                    .overlay(
                        Rectangle().fill(Color.offscriptHairline).frame(height: 1),
                        alignment: .top
                    )
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(episodes.enumerated()), id: \.element.id) { idx, episode in
                            PodcastEpisodeTunerRow(episode: episode, rank: idx + 1)
                            if idx < episodes.count - 1 {
                                Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                            }
                        }

                        if hasMoreEpisodes {
                            Button {
                                visibleLimit += 100
                                loadEpisodes()
                            } label: {
                                HStack {
                                    Spacer()
                                    TunerLabel(text: "+ LOAD 100 MORE", color: .offscriptSignalYellow, size: 10)
                                        .padding(.vertical, 12)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .overlay(
                                Rectangle().fill(Color.offscriptHairline).frame(height: 1),
                                alignment: .top
                            )
                        }
                    }
                    .overlay(
                        Rectangle().fill(Color.offscriptHairline).frame(height: 1),
                        alignment: .top
                    )
                }
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 90)
        }
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.offscriptStudioBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // No `.searchable` — see tunerEpisodeSearchField for the inline
        // hairline TextField that replaces it.
        .task { loadEpisodes(resetLimit: true) }
        .onChange(of: filter) { _, _ in loadEpisodes(resetLimit: true) }
        .onChange(of: episodeSearchQuery) { _, _ in scheduleEpisodeSearchLoad() }
        .onDisappear { searchLoadTask?.cancel() }
    }

    private func loadEpisodes(resetLimit: Bool = false) {
        if resetLimit {
            visibleLimit = 100
        }

        do {
            let podcastID = podcast.id
            let downloadedRawValue = Episode.DownloadState.downloaded.rawValue
            let baseSort = [SortDescriptor(\Episode.pubDate, order: .reverse)]
            let descriptor: FetchDescriptor<Episode>

            switch filter {
            case .all:
                descriptor = FetchDescriptor<Episode>(
                    predicate: #Predicate<Episode> { $0.podcast.id == podcastID },
                    sortBy: baseSort
                )
            case .unplayed:
                descriptor = FetchDescriptor<Episode>(
                    predicate: #Predicate<Episode> { $0.podcast.id == podcastID && $0.isPlayed == false },
                    sortBy: baseSort
                )
            case .inProgress:
                descriptor = FetchDescriptor<Episode>(
                    predicate: #Predicate<Episode> { $0.podcast.id == podcastID && $0.playedPosition > 0 && $0.isPlayed == false },
                    sortBy: baseSort
                )
            case .downloaded:
                descriptor = FetchDescriptor<Episode>(
                    predicate: #Predicate<Episode> { $0.podcast.id == podcastID && $0.downloadStateRawValue == downloadedRawValue },
                    sortBy: baseSort
                )
            }

            let query = episodeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if query.isEmpty {
                matchingEpisodeCount = (try? modelContext.fetchCount(descriptor)) ?? 0
                var pageDescriptor = descriptor
                pageDescriptor.fetchLimit = visibleLimit + 1
                let fetched = try modelContext.fetch(pageDescriptor)
                episodes = Array(fetched.prefix(visibleLimit))
                hasMoreEpisodes = fetched.count > visibleLimit
            } else {
                let searchResult = try searchEpisodes(
                    descriptor: descriptor,
                    query: query,
                    targetMatchCount: visibleLimit + 1
                )
                episodes = Array(searchResult.matches.prefix(visibleLimit))
                hasMoreEpisodes = searchResult.matches.count > visibleLimit || !searchResult.exhaustedResults
                matchingEpisodeCount = searchResult.exhaustedResults
                    ? searchResult.matches.count
                    : max(searchResult.matches.count, visibleLimit + 1)
            }
            loadError = nil
        } catch {
            episodes = []
            matchingEpisodeCount = 0
            hasMoreEpisodes = false
            loadError = error.localizedDescription
            libraryLogger.error("Podcast detail load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleEpisodeSearchLoad() {
        searchLoadTask?.cancel()
        searchLoadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            loadEpisodes(resetLimit: true)
        }
    }

    private func searchEpisodes(
        descriptor: FetchDescriptor<Episode>,
        query: String,
        targetMatchCount: Int
    ) throws -> (matches: [Episode], exhaustedResults: Bool) {
        let batchSize = max(targetMatchCount * 4, 200)
        var offset = 0
        var matches: [Episode] = []
        var exhaustedResults = false

        while matches.count < targetMatchCount {
            var batchDescriptor = descriptor
            batchDescriptor.fetchOffset = offset
            batchDescriptor.fetchLimit = batchSize

            let batch = try modelContext.fetch(batchDescriptor)
            if batch.isEmpty {
                exhaustedResults = true
                break
            }

            for episode in batch {
                if episode.title.lowercased().contains(query)
                    || (episode.summary?.strippingHTML.lowercased().contains(query) ?? false) {
                    matches.append(episode)
                    if matches.count >= targetMatchCount {
                        break
                    }
                }
            }

            if batch.count < batchSize {
                exhaustedResults = true
                break
            }

            offset += batch.count
        }

        return (matches, exhaustedResults)
    }

    private var tunerEpisodeSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.offscriptSignalYellow)

            TextField("Search episodes",
                      text: $episodeSearchQuery,
                      prompt: Text("SEARCH EPISODES")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.offscriptSoftPaper))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(.system(size: 13))
                .foregroundStyle(Color.offscriptPaperWhite)
                .accentColor(Color.offscriptSignalYellow)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !episodeSearchQuery.isEmpty {
                Button { episodeSearchQuery = "" } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.offscriptSoftPaper)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear episode search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
    }
}

private struct PodcastDetailTunerHeader: View {
    @Environment(\.modelContext) private var modelContext
    let podcast: Podcast
    let episodeCount: Int
    @State private var showUnsubscribeConfirmation = false
    @State private var safariURL: IdentifiableURL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TunerLabel(text: "CHANNEL · DETAIL", color: .offscriptSignalYellow)
                Spacer()
                TunerLabel(text: podcast.isSubscribed ? "● SUBSCRIBED" : "○ UNSUBSCRIBED",
                           color: podcast.isSubscribed ? .offscriptFnMode : .offscriptSoftPaper)
            }

            HStack(alignment: .top, spacing: 14) {
                OffScriptArtworkView(url: podcast.artworkURL, cornerRadius: 3)
                    .frame(width: 96, height: 96)
                    .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

                VStack(alignment: .leading, spacing: 6) {
                    if let author = podcast.author {
                        TunerLabel(text: author.uppercased(), color: .offscriptFnInfo)
                            .lineLimit(1)
                    }
                    TunerLabel(text: "\(episodeCount) EPISODES", color: .offscriptSoftPaper)
                    Spacer(minLength: 0)
                }
                Spacer()
            }

            Text(podcast.title)
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineSpacing(2)

            if let summary = podcast.summary {
                Text(summary)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineSpacing(2)
                    .lineLimit(6)
            }

            HStack(spacing: 8) {
                if podcast.isSubscribed {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showUnsubscribeConfirmation.toggle()
                        }
                    } label: {
                        TunerLabel(text: "× UNSUBSCRIBE", color: .offscriptFnRecord, size: 10)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                if let url = podcast.websiteURL {
                    Button {
                        safariURL = IdentifiableURL(url: url)
                    } label: {
                        TunerLabel(text: "→ WEBSITE", color: .offscriptSignalYellow, size: 10)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.top, 4)
            .sheet(item: $safariURL) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
                    .tunerModalSurface()
            }

            if showUnsubscribeConfirmation {
                unsubscribeConfirmationPanel(for: podcast)
            }

            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                .padding(.top, 6)
        }
    }

    private func unsubscribeConfirmationPanel(for podcast: Podcast) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TunerLabel(text: "CONFIRM · UNSUBSCRIBE", color: .offscriptFnRecord)
            Text("Removes the show from your library, dequeues its episodes, deletes offline downloads, and stops it from appearing in iOS Search. Listening history is preserved.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.offscriptPaperWhite.opacity(0.75))
                .lineSpacing(2)

            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showUnsubscribeConfirmation = false
                    }
                } label: {
                    TunerLabel(text: "CANCEL", color: .offscriptSoftPaper, size: 10)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showUnsubscribeConfirmation = false
                        _ = PodcastUnsubscribeService.unsubscribe(podcast, in: modelContext)
                    }
                } label: {
                    TunerLabel(text: "UNSUBSCRIBE", color: .offscriptFnRecord, size: 10)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

private struct PodcastEpisodeTunerRow: View {
    @Environment(\.modelContext) private var modelContext
    let episode: Episode
    let rank: Int

    private var progressValue: Double {
        guard let duration = episode.duration, duration > 0 else { return 0 }
        return episode.playedPosition / duration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                EpisodeDetailView(episode: episode)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(String(format: "%03d", rank))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Color.offscriptSignalYellow)
                        .frame(width: 32, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(episode.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.offscriptPaperWhite)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)

                        TunerLabel(text: metadata, color: .offscriptSoftPaper, size: 8)

                        if let summary = episode.summary {
                            Text(summary.strippingHTML)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.offscriptPaperWhite.opacity(0.7))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            if progressValue > 0 {
                GeometryReader { proxy in
                    let clamped = min(max(progressValue, 0), 1)
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.offscriptHairline)
                        Rectangle().fill(Color.offscriptSignalYellow)
                            .frame(width: proxy.size.width * clamped)
                    }
                }
                .frame(height: 1)
            }

            HStack(spacing: 6) {
                Button {
                    PlaybackController.shared.play(episode, in: modelContext)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.offscriptStudioBlack)
                        .frame(width: 30, height: 30)
                        .background(Color.offscriptSignalYellow)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    do { try QueueService.add(episode, in: modelContext) }
                    catch { libraryLogger.error("Queue add failed: \(error.localizedDescription, privacy: .public)") }
                } label: {
                    Image(systemName: episode.isQueued ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .frame(width: 30, height: 30)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(episode.isQueued)

                Spacer()
            }
        }
        .padding(.vertical, 10)
    }

    private var metadata: String {
        var parts: [String] = []
        if let s = episode.seasonNumber, let e = episode.episodeNumber {
            parts.append("S\(s) E\(e)")
        } else if let e = episode.episodeNumber {
            parts.append("E\(e)")
        }
        parts.append(episode.pubDate.formatted(date: .abbreviated, time: .omitted))
        if let duration = episode.duration {
            parts.append(EpisodeDurationFormatter.short(duration))
        }
        return parts.joined(separator: " · ").uppercased()
    }
}

// MARK: - Filter row (Tuner mode toggles)

private struct FilterRow: View {
    @Binding var selection: EpisodeFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(EpisodeFilter.allCases) { filter in
                    Button {
                        withAnimation { selection = filter }
                    } label: {
                        TunerLabel(
                            text: filter.title.uppercased(),
                            color: selection == filter ? .offscriptStudioBlack : .offscriptPaperWhite,
                            size: 10
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selection == filter ? Color.offscriptSignalYellow : Color.clear)
                        .overlay(Rectangle().stroke(
                            selection == filter ? Color.offscriptSignalYellow : Color.offscriptHairline,
                            lineWidth: 1
                        ))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == filter ? .isSelected : [])
                }
            }
        }
    }
}

/// Tuner-styled status strip that surfaces background OPML imports.
/// Renders nothing while the importer is idle. While running shows a
/// live count and a hairline progress rail; when finished shows the
/// summary with a dismiss key. Lives at the top of the Library page so
/// the user always sees what's happening once they leave the sheet.
private struct LibraryBatchImportStrip: View {
    @ObservedObject private var importer = BatchImportService.shared

    var body: some View {
        switch importer.phase {
        case .idle:
            EmptyView()
        case .running:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TunerLabel(text: "● IMPORTING IN BACKGROUND",
                               color: .offscriptSignalYellow)
                    Spacer()
                    TunerLabel(text: "\(importer.completedCount)/\(importer.totalCount)",
                               color: .offscriptFnInfo)
                }

                GeometryReader { proxy in
                    let total = max(1, importer.totalCount)
                    let done = importer.completedCount
                    let clamped = min(max(Double(done) / Double(total), 0), 1)
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.offscriptHairline)
                        Rectangle()
                            .fill(Color.offscriptSignalYellow)
                            .frame(width: proxy.size.width * clamped)
                    }
                }
                .frame(height: 2)
            }
            .padding(.vertical, 10)
            .overlay(
                Rectangle().fill(Color.offscriptHairline).frame(height: 1),
                alignment: .top
            )
            .overlay(
                Rectangle().fill(Color.offscriptHairline).frame(height: 1),
                alignment: .bottom
            )

        case .finished(let added, let failed):
            HStack(spacing: 12) {
                TunerLabel(
                    text: failed == 0 ? "✓ IMPORT COMPLETE" : "● IMPORT FINISHED",
                    color: failed == 0 ? .offscriptFnMode : .offscriptSignalYellow
                )
                Text(failed == 0
                     ? "Added \(added) shows"
                     : "Added \(added), \(failed) failed")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.offscriptPaperWhite)
                Spacer()
                Button {
                    importer.dismiss()
                } label: {
                    TunerLabel(text: "× DISMISS",
                               color: .offscriptSoftPaper, size: 9)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss import status")
            }
            .padding(.vertical, 10)
            .overlay(
                Rectangle().fill(Color.offscriptHairline).frame(height: 1),
                alignment: .top
            )
            .overlay(
                Rectangle().fill(Color.offscriptHairline).frame(height: 1),
                alignment: .bottom
            )
        }
    }
}

private enum EpisodeFilter: String, CaseIterable, Identifiable {
    case all
    case unplayed
    case inProgress
    case downloaded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .unplayed: return "Unplayed"
        case .inProgress: return "In Progress"
        case .downloaded: return "Downloaded"
        }
    }

    func matches(_ episode: Episode) -> Bool {
        switch self {
        case .all:
            return true
        case .unplayed:
            return !episode.isPlayed
        case .inProgress:
            return episode.playedPosition > 0 && !episode.isPlayed
        case .downloaded:
            return episode.downloadState == .downloaded
        }
    }
}

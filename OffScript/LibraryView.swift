import OSLog
import SwiftData
import SwiftUI

private let libraryLogger = Logger(subsystem: "com.offscript", category: "Library")

/// Computes the chronological "Episode N" label for the podcast detail row.
///
/// Podcast detail rows display newest-first (matches platform convention),
/// but the rank label must reflect the episode's chronological position
/// in the full feed — otherwise the newest episode reads as Episode 001
/// while the actual first episode in the show shows as the highest number,
/// which is the bug filed in #145.
///
/// Resolution order:
/// 1. The feed-supplied `<itunes:episode>` value when present.
/// 2. The episode's chronological position in the full feed when the
///    detail view is showing the unfiltered list (`filterShowsFullFeed`).
///    Display index 0 (newest in a reverse-chronological list) maps to
///    `totalEpisodeCount`; the oldest episode maps to 1.
/// 3. `nil` when neither is available — the row renders a `—` placeholder
///    rather than a misleading number derived from a filtered subset.
nonisolated enum PodcastDetailRanker {
    static func chronologicalRank(
        explicitEpisodeNumber: Int?,
        displayedIndex: Int,
        totalEpisodeCount: Int,
        filterShowsFullFeed: Bool
    ) -> Int? {
        if let explicit = explicitEpisodeNumber, explicit > 0 {
            return explicit
        }
        guard filterShowsFullFeed,
              totalEpisodeCount > 0,
              displayedIndex >= 0,
              displayedIndex < totalEpisodeCount else {
            return nil
        }
        return totalEpisodeCount - displayedIndex
    }
}

nonisolated enum LibraryDirectoryScope: String, CaseIterable, Identifiable, Sendable {
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

nonisolated enum LibraryDirectorySort: String, CaseIterable, Identifiable, Sendable {
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

nonisolated enum LibraryDirectoryDensity: String, CaseIterable, Identifiable, Sendable {
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

/// Outcome of a user-initiated SYNC, captured so the directory can
/// render a brief `✓ SYNCED N` / `● N FAILED` chip after the spinner
/// stops. Pure value type so the @State binding stays cheap.
struct LibrarySyncResult: Equatable {
    let total: Int
    let failed: Int
    var succeeded: Int { max(0, total - failed) }
}

nonisolated struct LibraryDirectoryRow: Equatable, Identifiable, Sendable {
    var id: UUID { podcastID }
    let podcastID: UUID
    let title: String
    let author: String?
    let artworkURL: URL?
    let channelNumber: Int
    let unplayedCount: Int
    let inProgressCount: Int
    let isLastInSection: Bool
    /// Surface sync failures inline on the directory row so a podcast
    /// whose feed went 404 (host moved, feed renamed) is visibly
    /// flagged without the user having to flip to the `needsSync`
    /// scope or open the detail.
    var syncStatus: String = "idle"
    var syncFailureCount: Int = 0

    /// Single source of truth for "this feed has a sync failure
    /// sighted users should see flagged inline". Centralized here so
    /// PodcastShelfRow's `● SYNC FAILED` chip and the row-level
    /// VoiceOver readout never drift if the failure criteria changes
    /// (e.g. adding a "retrying" state). Copilot review on #264.
    var hasSyncFailure: Bool {
        syncFailureCount > 0 || syncStatus == "failed"
    }
}

nonisolated struct LibraryDirectoryPodcast: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let author: String?
    let artworkURL: URL?
    let categories: [String]
    let latestPubDate: Date?
    let subscribedAt: Date?
    let syncStatus: String
    let syncFailureCount: Int

    init(
        id: UUID,
        title: String,
        author: String? = nil,
        artworkURL: URL? = nil,
        categories: [String] = [],
        latestPubDate: Date? = nil,
        subscribedAt: Date? = nil,
        syncStatus: String = "idle",
        syncFailureCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.artworkURL = artworkURL
        self.categories = categories
        self.latestPubDate = latestPubDate
        self.subscribedAt = subscribedAt
        self.syncStatus = syncStatus
        self.syncFailureCount = syncFailureCount
    }

    init(podcast: Podcast) {
        self.init(
            id: podcast.id,
            title: podcast.title,
            author: podcast.author,
            artworkURL: podcast.artworkURL,
            categories: podcast.categories,
            latestPubDate: podcast.latestPubDate,
            subscribedAt: podcast.subscribedAt,
            syncStatus: podcast.syncStatus,
            syncFailureCount: podcast.syncFailureCount
        )
    }
}

nonisolated struct LibraryDirectorySection: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let rowCount: Int
    let rows: [LibraryDirectoryRow]

    init(id: String, title: String, rowCount: Int, rows: [LibraryDirectoryRow] = []) {
        self.id = id
        self.title = title
        self.rowCount = rowCount
        self.rows = rows
    }
}

nonisolated struct LibraryAlphabetTarget: Equatable, Identifiable, Sendable {
    var id: String { key }
    let key: String
    let sectionID: String?
    let isExact: Bool

    var isReachable: Bool { sectionID != nil }
    var isNearestJump: Bool { isReachable && !isExact }
}

nonisolated struct LibraryDirectorySnapshot: Sendable {
    let podcasts: [LibraryDirectoryPodcast]
    let sections: [LibraryDirectorySection]
    let listItems: [LibraryDirectoryListItem]
    let numbersByPodcastID: [UUID: Int]
    let alphabetTargets: [LibraryAlphabetTarget]

    static let empty = LibraryDirectorySnapshot(
        podcasts: [],
        sections: [],
        listItems: [],
        numbersByPodcastID: [:],
        alphabetTargets: LibraryDirectoryOrganizer.alphabetTargets(for: [])
    )

    var visibleCount: Int { podcasts.count }
    var isEmpty: Bool { podcasts.isEmpty }
}

nonisolated struct LibraryDirectoryCounts: Equatable, Sendable {
    let unplayedByPodcastID: [UUID: Int]
    let inProgressByPodcastID: [UUID: Int]

    static let empty = LibraryDirectoryCounts(unplayedByPodcastID: [:], inProgressByPodcastID: [:])
}

nonisolated struct LibraryEpisodeSummary: Equatable, Sendable {
    let unplayedCount: Int
    let inProgressCount: Int
    let freshEpisodeIDs: [UUID]
    let inProgressEpisodeIDs: [UUID]
    let freshUnplayedCountsByPodcastID: [UUID: Int]
    let freshInProgressCountsByPodcastID: [UUID: Int]

    static let empty = LibraryEpisodeSummary(
        unplayedCount: 0,
        inProgressCount: 0,
        freshEpisodeIDs: [],
        inProgressEpisodeIDs: [],
        freshUnplayedCountsByPodcastID: [:],
        freshInProgressCountsByPodcastID: [:]
    )
}

private struct LibraryDirectorySnapshotInputs: Equatable, Sendable {
    let podcasts: [LibraryDirectoryPodcast]
    let query: String
    let scope: LibraryDirectoryScope
    let sort: LibraryDirectorySort
    let unplayedCounts: [UUID: Int]
    let inProgressCounts: [UUID: Int]
}

nonisolated enum LibraryDirectoryListItem: Identifiable, Sendable {
    case sectionHeader(LibraryDirectorySection)
    case row(LibraryDirectoryRow)
    case sectionSeparator(String)
    case rowSeparator(String)

    var id: String {
        switch self {
        case let .sectionHeader(section):
            return "header-\(section.id)"
        case let .row(row):
            return "row-\(row.id)"
        case let .sectionSeparator(sectionID):
            return "section-separator-\(sectionID)"
        case let .rowSeparator(rowID):
            return "row-separator-\(rowID)"
        }
    }
}

nonisolated enum LibraryDirectoryOrganizer {
    static let alphabetKeys = ["#"] + (UnicodeScalar("A").value...UnicodeScalar("Z").value).compactMap { value in
        UnicodeScalar(value).map { String($0) }
    }

    static func needsPerShowUnplayedCounts(
        scope: LibraryDirectoryScope,
        sort: LibraryDirectorySort
    ) -> Bool {
        scope == .unplayed || sort == .attention
    }

    static func needsPerShowInProgressCounts(
        scope: LibraryDirectoryScope,
        sort: LibraryDirectorySort
    ) -> Bool {
        scope == .inProgress || sort == .attention
    }

    static func hasLoadedRequiredFullCounts(
        scope: LibraryDirectoryScope,
        sort: LibraryDirectorySort,
        didLoadUnplayed: Bool,
        didLoadInProgress: Bool
    ) -> Bool {
        (!needsPerShowUnplayedCounts(scope: scope, sort: sort) || didLoadUnplayed)
            && (!needsPerShowInProgressCounts(scope: scope, sort: sort) || didLoadInProgress)
    }

    static func missingFullCountRequirements(
        scope: LibraryDirectoryScope,
        sort: LibraryDirectorySort,
        didLoadUnplayed: Bool,
        didLoadInProgress: Bool
    ) -> (unplayed: Bool, inProgress: Bool) {
        (
            needsPerShowUnplayedCounts(scope: scope, sort: sort) && !didLoadUnplayed,
            needsPerShowInProgressCounts(scope: scope, sort: sort) && !didLoadInProgress
        )
    }

    static func snapshot(
        for podcasts: [Podcast],
        query: String,
        scope: LibraryDirectoryScope,
        sort: LibraryDirectorySort,
        unplayedCounts: [UUID: Int],
        inProgressCounts: [UUID: Int]
    ) -> LibraryDirectorySnapshot {
        snapshot(
            for: podcasts.map(LibraryDirectoryPodcast.init(podcast:)),
            query: query,
            scope: scope,
            sort: sort,
            unplayedCounts: unplayedCounts,
            inProgressCounts: inProgressCounts
        )
    }

    static func snapshot(
        for podcasts: [LibraryDirectoryPodcast],
        query: String,
        scope: LibraryDirectoryScope,
        sort: LibraryDirectorySort,
        unplayedCounts: [UUID: Int],
        inProgressCounts: [UUID: Int]
    ) -> LibraryDirectorySnapshot {
        let filtered = filteredDirectoryPodcasts(
            podcasts,
            query: query,
            scope: scope,
            sort: sort,
            unplayedCounts: unplayedCounts,
            inProgressCounts: inProgressCounts
        )
        let numbersByPodcastID = Dictionary(uniqueKeysWithValues: filtered.enumerated().map { ($0.element.id, $0.offset + 1) })
        let sections = sections(
            for: filtered,
            numbersByPodcastID: numbersByPodcastID,
            unplayedCounts: unplayedCounts,
            inProgressCounts: inProgressCounts
        )
        return LibraryDirectorySnapshot(
            podcasts: filtered,
            sections: sections,
            listItems: listItems(for: sections),
            numbersByPodcastID: numbersByPodcastID,
            alphabetTargets: alphabetTargets(for: sections)
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
        filteredDirectoryPodcasts(
            podcasts.map(LibraryDirectoryPodcast.init(podcast:)),
            query: query,
            scope: scope,
            sort: sort,
            unplayedCounts: unplayedCounts,
            inProgressCounts: inProgressCounts
        ).compactMap { rowPodcast in
            podcasts.first { $0.id == rowPodcast.id }
        }
    }

    static func filteredDirectoryPodcasts(
        _ podcasts: [LibraryDirectoryPodcast],
        query: String,
        scope: LibraryDirectoryScope,
        sort: LibraryDirectorySort,
        unplayedCounts: [UUID: Int],
        inProgressCounts: [UUID: Int]
    ) -> [LibraryDirectoryPodcast] {
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
        sections(
            for: podcasts.map(LibraryDirectoryPodcast.init(podcast:)),
            numbersByPodcastID: [:],
            unplayedCounts: [:],
            inProgressCounts: [:]
        )
    }

    static func sections(for podcasts: [LibraryDirectoryPodcast]) -> [LibraryDirectorySection] {
        sections(for: podcasts, numbersByPodcastID: [:], unplayedCounts: [:], inProgressCounts: [:])
    }

    static func sectionIDForAlphabetKey(_ key: String, sections: [LibraryDirectorySection]) -> String? {
        guard !sections.isEmpty else { return nil }
        if let exact = sections.first(where: { $0.title == key }) {
            return exact.id
        }

        let sortedSections = sections.sorted { sectionSort($0.title, $1.title) }
        if key == "#" {
            return sortedSections.first?.id
        }
        if let next = sortedSections.first(where: { sectionSort(key, $0.title) }) {
            return next.id
        }
        return sortedSections.last?.id
    }

    static func alphabetTargets(for sections: [LibraryDirectorySection]) -> [LibraryAlphabetTarget] {
        let sectionsByTitle = Dictionary(uniqueKeysWithValues: sections.map { ($0.title, $0) })
        return alphabetKeys.map { key in
            let exactSectionID = sectionsByTitle[key]?.id
            return LibraryAlphabetTarget(
                key: key,
                sectionID: exactSectionID ?? sectionIDForAlphabetKey(key, sections: sections),
                isExact: exactSectionID != nil
            )
        }
    }

    static func listItems(for sections: [LibraryDirectorySection]) -> [LibraryDirectoryListItem] {
        sections.flatMap { section -> [LibraryDirectoryListItem] in
            var items: [LibraryDirectoryListItem] = [.sectionHeader(section)]
            for row in section.rows {
                items.append(.row(row))
                if !row.isLastInSection {
                    items.append(.rowSeparator(row.id.uuidString))
                }
            }
            items.append(.sectionSeparator(section.id))
            return items
        }
    }

    static func sections(
        for podcasts: [LibraryDirectoryPodcast],
        numbersByPodcastID: [UUID: Int],
        unplayedCounts: [UUID: Int],
        inProgressCounts: [UUID: Int]
    ) -> [LibraryDirectorySection] {
        let grouped = Dictionary(grouping: podcasts) { podcast in
            sectionTitle(for: podcast.title)
        }

        return grouped.keys.sorted(by: sectionSort).map { title in
            let podcasts = grouped[title] ?? []
            return LibraryDirectorySection(
                id: "library-section-\(title)",
                title: title,
                rowCount: podcasts.count,
                rows: podcasts.enumerated().map { index, podcast in
                    LibraryDirectoryRow(
                        podcastID: podcast.id,
                        title: podcast.title,
                        author: podcast.author,
                        artworkURL: podcast.artworkURL,
                        channelNumber: numbersByPodcastID[podcast.id] ?? (index + 1),
                        unplayedCount: unplayedCounts[podcast.id] ?? 0,
                        inProgressCount: inProgressCounts[podcast.id] ?? 0,
                        isLastInSection: index == podcasts.count - 1,
                        syncStatus: podcast.syncStatus,
                        syncFailureCount: podcast.syncFailureCount
                    )
                }
            )
        }
    }

    private static func attentionScore(
        _ podcast: LibraryDirectoryPodcast,
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

    static func countsByPodcastID(for episodes: [Episode], limitedTo podcastIDs: Set<UUID>) -> [UUID: Int] {
        episodes.reduce(into: [UUID: Int]()) { counts, episode in
            let podcastID = episode.podcast.id
            guard podcastIDs.contains(podcastID) else { return }
            counts[podcastID, default: 0] += 1
        }
    }

    private static func titleSort(_ lhs: LibraryDirectoryPodcast, _ rhs: LibraryDirectoryPodcast) -> Bool {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

@MainActor
enum LibraryDirectoryCountLoader {
    static func countsByPodcastID(
        podcastIDs: [UUID],
        needsUnplayed: Bool,
        needsInProgress: Bool,
        context: ModelContext
    ) async throws -> LibraryDirectoryCounts {
        let allowedPodcastIDs = Set(podcastIDs)
        guard !allowedPodcastIDs.isEmpty, needsUnplayed || needsInProgress else { return .empty }
        try Task.checkCancellation()

        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> {
                allowedPodcastIDs.contains($0.podcast.id)
                    && $0.podcast.isSubscribed
                    && !$0.isPlayed
                    && (needsUnplayed || $0.playedPosition > 0)
            }
        )
        let episodes = try context.fetch(descriptor)
        await Task.yield()
        try Task.checkCancellation()

        return LibraryDirectoryCountBucketer.counts(
            episodes: episodes,
            allowedPodcastIDs: allowedPodcastIDs,
            needsUnplayed: needsUnplayed,
            needsInProgress: needsInProgress
        )
    }

    static func unplayedCountsByPodcastID(
        podcastIDs: [UUID],
        context: ModelContext
    ) async throws -> [UUID: Int] {
        try await countsByPodcastID(
            podcastIDs: podcastIDs,
            needsUnplayed: true,
            needsInProgress: false,
            context: context
        ).unplayedByPodcastID
    }

    static func inProgressCountsByPodcastID(
        podcastIDs: [UUID],
        context: ModelContext
    ) async throws -> [UUID: Int] {
        try await countsByPodcastID(
            podcastIDs: podcastIDs,
            needsUnplayed: false,
            needsInProgress: true,
            context: context
        ).inProgressByPodcastID
    }
}

@ModelActor
actor LibraryDirectoryCountStore {
    func subscribedPodcasts() throws -> [LibraryDirectoryPodcast] {
        let descriptor = FetchDescriptor<Podcast>(
            predicate: #Predicate<Podcast> { $0.isSubscribed },
            sortBy: [SortDescriptor(\Podcast.title)]
        )
        let podcasts = try modelContext.fetch(descriptor)
        try Task.checkCancellation()
        return podcasts.map(LibraryDirectoryPodcast.init(podcast:))
    }

    func episodeSummary() throws -> LibraryEpisodeSummary {
        let countDescriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.podcast.isSubscribed && !$0.isPlayed }
        )
        var freshDescriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.podcast.isSubscribed && !$0.isPlayed },
            sortBy: [SortDescriptor(\Episode.pubDate, order: .reverse)]
        )
        freshDescriptor.fetchLimit = 10
        let inProgressDescriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.podcast.isSubscribed && !$0.isPlayed && $0.playedPosition > 0 }
        )
        var inProgressPageDescriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.podcast.isSubscribed && !$0.isPlayed && $0.playedPosition > 0 },
            sortBy: [SortDescriptor(\Episode.lastPlayedAt, order: .reverse)]
        )
        inProgressPageDescriptor.fetchLimit = 8

        let unplayedCount = try modelContext.fetchCount(countDescriptor)
        try Task.checkCancellation()
        let freshEpisodes = try modelContext.fetch(freshDescriptor)
        try Task.checkCancellation()
        let inProgressCount = try modelContext.fetchCount(inProgressDescriptor)
        try Task.checkCancellation()
        let inProgressEpisodes = try modelContext.fetch(inProgressPageDescriptor)
        try Task.checkCancellation()

        return LibraryEpisodeSummary(
            unplayedCount: unplayedCount,
            inProgressCount: inProgressCount,
            freshEpisodeIDs: freshEpisodes.map(\.id),
            inProgressEpisodeIDs: inProgressEpisodes.map(\.id),
            freshUnplayedCountsByPodcastID: Dictionary(freshEpisodes.map { ($0.podcast.id, 1) }, uniquingKeysWith: +),
            freshInProgressCountsByPodcastID: Dictionary(inProgressEpisodes.map { ($0.podcast.id, 1) }, uniquingKeysWith: +)
        )
    }

    func countsByPodcastID(
        podcastIDs: [UUID],
        needsUnplayed: Bool,
        needsInProgress: Bool
    ) throws -> LibraryDirectoryCounts {
        let allowedPodcastIDs = Set(podcastIDs)
        guard !allowedPodcastIDs.isEmpty, needsUnplayed || needsInProgress else { return .empty }
        try Task.checkCancellation()

        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> {
                allowedPodcastIDs.contains($0.podcast.id)
                    && $0.podcast.isSubscribed
                    && !$0.isPlayed
                    && (needsUnplayed || $0.playedPosition > 0)
            }
        )
        let episodes = try modelContext.fetch(descriptor)
        try Task.checkCancellation()

        return LibraryDirectoryCountBucketer.counts(
            episodes: episodes,
            allowedPodcastIDs: allowedPodcastIDs,
            needsUnplayed: needsUnplayed,
            needsInProgress: needsInProgress
        )
    }
}

private nonisolated enum LibraryDirectoryCountBucketer {
    static func counts(
        episodes: [Episode],
        allowedPodcastIDs: Set<UUID>,
        needsUnplayed: Bool,
        needsInProgress: Bool
    ) -> LibraryDirectoryCounts {
        var unplayedCounts: [UUID: Int] = [:]
        var inProgressCounts: [UUID: Int] = [:]
        for episode in episodes {
            let podcastID = episode.podcast.id
            guard allowedPodcastIDs.contains(podcastID) else { continue }
            if needsUnplayed {
                unplayedCounts[podcastID, default: 0] += 1
            }
            if needsInProgress, episode.playedPosition > 0 {
                inProgressCounts[podcastID, default: 0] += 1
            }
        }

        return LibraryDirectoryCounts(
            unplayedByPodcastID: needsUnplayed ? unplayedCounts : [:],
            inProgressByPodcastID: needsInProgress ? inProgressCounts : [:]
        )
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

    let isActive: Bool
    let onOpenSettings: () -> Void

    private static let subscriptionIDFetchChunkSize = 400

    private let syncService = FeedSyncService()
    @State private var isImportPresented = false
    @State private var directoryQuery = ""
    @State private var effectiveDirectoryQuery = ""
    @State private var directoryScope: LibraryDirectoryScope = .all
    @State private var directorySort: LibraryDirectorySort = .title
    @State private var directoryDensity: LibraryDirectoryDensity = .compact
    @State private var selectedDirectorySectionID: String?
    @State private var selectedDirectoryKey: String?
    @State private var inProgressEpisodes: [Episode] = []
    @State private var inProgressEpisodeCount = 0
    @State private var freshInProgressCountsByPodcastID: [UUID: Int] = [:]
    @State private var fullInProgressCountsByPodcastID: [UUID: Int] = [:]
    @State private var freshEpisodes: [Episode] = []
    @State private var unplayedEpisodeCount = 0
    @State private var freshUnplayedCountsByPodcastID: [UUID: Int] = [:]
    @State private var fullUnplayedCountsByPodcastID: [UUID: Int] = [:]
    @State private var didLoadFullUnplayedCounts = false
    @State private var didLoadFullInProgressCounts = false
    @State private var isLoadingFullDirectoryCounts = false
    @State private var summaryLoadTask: Task<Void, Never>?
    @State private var fullCountLoadTask: Task<Void, Never>?
    @State private var directoryPodcastLoadTask: Task<Void, Never>?
    @State private var directorySnapshotTask: Task<Void, Never>?
    @State private var directoryQueryTask: Task<Void, Never>?
    @State private var selectedPodcastID: UUID?
    @State private var directoryPodcasts: [LibraryDirectoryPodcast] = []
    @State private var didLoadDirectoryPodcasts = false
    @State private var cachedDirectorySnapshot = LibraryDirectorySnapshot.empty
    @State private var didBuildDirectorySnapshot = false
    @State private var isSyncingLibrary = false
    /// Latest user-initiated SYNC outcome — surfaced as a brief inline
    /// chip below the header so a user who taps SYNC and sees the
    /// spinner stop knows whether 5 of 50 feeds failed without flipping
    /// to the `needsSync` filter scope. Cleared on the next manual SYNC.
    @State private var lastSyncResult: LibrarySyncResult?
    @State private var lastSyncResultClearTask: Task<Void, Never>?
    @State private var shouldReloadDirectoryOnAppear = false
    @State private var isLibraryTabActive = false

    private var directoryNeedsFullUnplayedCounts: Bool {
        LibraryDirectoryOrganizer.needsPerShowUnplayedCounts(scope: directoryScope, sort: directorySort)
    }

    private var directoryNeedsFullInProgressCounts: Bool {
        LibraryDirectoryOrganizer.needsPerShowInProgressCounts(scope: directoryScope, sort: directorySort)
    }

    private var directoryNeedsFullCounts: Bool {
        directoryNeedsFullUnplayedCounts || directoryNeedsFullInProgressCounts
    }

    private var didLoadRequiredFullDirectoryCounts: Bool {
        LibraryDirectoryOrganizer.hasLoadedRequiredFullCounts(
            scope: directoryScope,
            sort: directorySort,
            didLoadUnplayed: didLoadFullUnplayedCounts,
            didLoadInProgress: didLoadFullInProgressCounts
        )
    }

    private var directoryUnplayedCountsByPodcastID: [UUID: Int] {
        directoryNeedsFullUnplayedCounts ? fullUnplayedCountsByPodcastID : freshUnplayedCountsByPodcastID
    }

    private var directoryInProgressCountsByPodcastID: [UUID: Int] {
        directoryNeedsFullInProgressCounts ? fullInProgressCountsByPodcastID : freshInProgressCountsByPodcastID
    }

    private var isCompactDirectory: Bool {
        directoryDensity == .compact || directoryPodcasts.count >= 120
    }

    private var subscribedPodcastIDs: [UUID] {
        directoryPodcasts.map(\.id)
    }

    private var directorySnapshotInputs: LibraryDirectorySnapshotInputs {
        LibraryDirectorySnapshotInputs(
            podcasts: directoryPodcasts,
            query: effectiveDirectoryQuery,
            scope: directoryScope,
            sort: directorySort,
            unplayedCounts: directoryUnplayedCountsByPodcastID,
            inProgressCounts: directoryInProgressCountsByPodcastID
        )
    }

    var body: some View {
        Group {
            if isActive {
                activeLibraryContent
            } else {
                Color.offscriptStudioBlack
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
        }
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
        .accessibilityIdentifier("LibraryScreen")
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(Color.offscriptStudioBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(item: $selectedPodcastID) { podcastID in
            if let podcast = podcast(withID: podcastID) {
                PodcastDetailView(podcast: podcast)
            } else {
                LibraryDirectoryMissingShowView()
            }
        }
        .task(id: isActive) {
            guard isActive else { return }
            activateLibraryTab()
            loadDirectoryPodcastsIfNeeded()
            loadLibraryEpisodeSummary()
        }
        .onAppear {
            guard isActive else { return }
            activateLibraryTab()
            // Consume any pending `offscript://podcast/<uuid>` deep link
            // that fired before `LibraryView` was instantiated. The
            // notification path covers the warm case (Library already
            // loaded); this `.onAppear` consumption covers the cold one.
            if let pending = DeepLinkRouter.pendingPodcastDeepLink {
                selectedPodcastID = pending
                DeepLinkRouter.pendingPodcastDeepLink = nil
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                activateLibraryTab()
            } else {
                isLibraryTabActive = false
                cancelDeferredLibraryWork()
            }
        }
        .onChange(of: subscribedPodcastIDs) { _, _ in
            guard isActive && isLibraryTabActive else { return }
            scheduleLibraryEpisodeSummaryLoad()
        }
        .onChange(of: directoryQuery) { _, newValue in
            guard isActive && isLibraryTabActive else { return }
            scheduleDirectoryQuery(newValue)
        }
        .onChange(of: directorySnapshotInputs) { _, _ in
            guard isActive && isLibraryTabActive else { return }
            rebuildDirectorySnapshot()
        }
        .onChange(of: selectedPodcastID) { _, _ in
            guard isActive && isLibraryTabActive else { return }
            reloadDirectoryAfterSubscriptionChangeIfPossible()
        }
        .onChange(of: directoryScope) { _, _ in
            guard isActive && isLibraryTabActive else { return }
            ensureFullDirectoryCountsIfNeeded()
        }
        .onChange(of: directorySort) { _, _ in
            guard isActive && isLibraryTabActive else { return }
            ensureFullDirectoryCountsIfNeeded()
        }
        .onDisappear {
            isLibraryTabActive = false
            cancelDeferredLibraryWork()
        }
        .onReceive(NotificationCenter.default.publisher(for: .offscriptLibrarySubscriptionsChanged)) { _ in
            shouldReloadDirectoryOnAppear = true
            if isActive {
                reloadDirectoryAfterSubscriptionChangeIfPossible()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .offscriptActiveTabChanged)) { note in
            handleActiveTabChanged(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: .offscriptOpenPodcast)) { note in
            // `offscript://podcast/<uuid>` deep link landed. `DeepLinkRouter`
            // already verified the UUID exists in store and posted the
            // tab-switch to Library before this notification, so we can
            // bind directly to the existing `selectedPodcastID` state and
            // let `.navigationDestination` push the detail view.
            guard let podcastID = note.userInfo?["podcastID"] as? UUID else {
                libraryLogger.warning(".offscriptOpenPodcast missing or wrong-typed podcastID userInfo: \(String(describing: note.userInfo), privacy: .public)")
                return
            }
            selectedPodcastID = podcastID
            DeepLinkRouter.pendingPodcastDeepLink = nil
        }
        // Settings + Import buttons render inline in LibraryTunerHeader, not
        // as toolbar items — iOS 26 wraps toolbar buttons in glass chrome.
        .sheet(isPresented: $isImportPresented) {
            LibraryImportSheet()
                .tunerModalSurface()
        }
    }

    private var activeLibraryContent: some View {
        let snapshot = cachedDirectorySnapshot
        return ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LibraryTunerHeader(
                        showCount: directoryPodcasts.count,
                        visibleCount: didBuildDirectorySnapshot ? snapshot.visibleCount : directoryPodcasts.count,
                        unplayedCount: unplayedEpisodeCount,
                        inProgressCount: inProgressEpisodeCount,
                        onOpenImport: { isImportPresented = true },
                        isSyncing: isSyncingLibrary,
                        onSync: {
                            Task { await syncSubscriptions() }
                        },
                        onOpenSettings: onOpenSettings
                    )

                    // Background OPML import status — visible whenever the
                    // batch importer is mid-flight or has just finished and
                    // hasn't been dismissed yet.
                    LibraryBatchImportStrip(onFinished: {
                        refreshDirectoryAfterBatchImportIfActive()
                    })

                    // Brief inline summary of the latest manual SYNC.
                    // Auto-clears after ~6s; a fresh tap on SYNC clears
                    // it immediately. Companion to the inline `● SYNC
                    // FAILED` chips on individual rows so the user can
                    // see at a glance whether the sync was clean.
                    if let result = lastSyncResult {
                        LibrarySyncResultStrip(result: result) {
                            lastSyncResult = nil
                            lastSyncResultClearTask?.cancel()
                        }
                    }

                    if didLoadDirectoryPodcasts && directoryPodcasts.isEmpty {
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
                            isForcedCompact: directoryPodcasts.count >= 120
                        )

                        showsSection(snapshot: snapshot, scrollProxy: scrollProxy)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OffScriptTheme.pagePadding)
                .padding(.top, OffScriptTheme.rootContentTopPadding)
                .padding(.bottom, 90)
            }
            // Pull-to-refresh — native iOS gesture for re-syncing
            // every subscribed feed. Reuses the same path as the SYNC
            // header key, so the LibrarySyncResult chip surfaces the
            // outcome consistently regardless of which trigger fired.
            .refreshable {
                await syncSubscriptions()
            }
        }
    }

    @MainActor
    private func activateLibraryTab() {
        isLibraryTabActive = true
        effectiveDirectoryQuery = directoryQuery
        reloadDirectoryAfterSubscriptionChangeIfPossible()
        if !shouldReloadDirectoryOnAppear {
            loadDirectoryPodcastsIfNeeded()
        }
    }

    @MainActor
    private func rebuildDirectorySnapshot() {
        directorySnapshotTask?.cancel()
        let inputs = directorySnapshotInputs
        let interval = OffScriptPerformanceLog.begin(
            "library.snapshot",
            metadata: "podcasts=\(inputs.podcasts.count) scope=\(inputs.scope.rawValue) sort=\(inputs.sort.rawValue)"
        )
        directorySnapshotTask = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else {
                await MainActor.run {
                    OffScriptPerformanceLog.end(
                        interval,
                        metadata: "podcasts=\(inputs.podcasts.count) scope=\(inputs.scope.rawValue) sort=\(inputs.sort.rawValue) cancelled=true"
                    )
                }
                return
            }
            let snapshot = LibraryDirectoryOrganizer.snapshot(
                for: inputs.podcasts,
                query: inputs.query,
                scope: inputs.scope,
                sort: inputs.sort,
                unplayedCounts: inputs.unplayedCounts,
                inProgressCounts: inputs.inProgressCounts
            )
            await MainActor.run {
                guard !Task.isCancelled else {
                    OffScriptPerformanceLog.end(
                        interval,
                        metadata: "podcasts=\(inputs.podcasts.count) scope=\(inputs.scope.rawValue) sort=\(inputs.sort.rawValue) cancelled=true"
                    )
                    return
                }
                cachedDirectorySnapshot = snapshot
                didBuildDirectorySnapshot = true
                reconcileSelectedDirectoryTarget(with: snapshot)
                OffScriptPerformanceLog.end(
                    interval,
                    metadata: "podcasts=\(inputs.podcasts.count) visible=\(snapshot.visibleCount) scope=\(inputs.scope.rawValue) sort=\(inputs.sort.rawValue)"
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            TunerLabel(text: "● NO CHANNELS TUNED", color: .offscriptFnInfo)
            Text("Your library is empty")
                .font(.system(size: 22, weight: .semibold))
                .tracking(0)
                .foregroundStyle(Color.offscriptPaperWhite)
            Text("Use Search to bring in shows. OffScript keeps them fresh here once you subscribe.")
                .font(.system(size: 13.5))
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineSpacing(2)

            NavigationLink {
                SearchView(hidesRootNavigationBar: false)
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
                    text: snapshot.visibleCount == directoryPodcasts.count
                        ? "\(directoryPodcasts.count) VISIBLE"
                        : "\(snapshot.visibleCount)/\(directoryPodcasts.count) VISIBLE",
                    color: .offscriptSoftPaper,
                    size: 8
                )
            }

            if !didBuildDirectorySnapshot && !directoryPodcasts.isEmpty {
                TunerLabel(text: "● BUILDING DIRECTORY INDEX", color: .offscriptSignalYellow, size: 8)
                    .padding(.top, 2)
            } else if snapshot.isEmpty {
                LibraryDirectoryEmptyState(
                    query: effectiveDirectoryQuery,
                    scope: directoryScope,
                    onClear: {
                        directoryQuery = ""
                        directoryScope = .all
                    }
                )
            } else {
                if isLoadingFullDirectoryCounts && directoryNeedsFullCounts {
                    TunerLabel(text: "● LOADING DIRECTORY COUNTS", color: .offscriptSignalYellow, size: 8)
                        .padding(.top, 2)
                }

                LibraryAlphabetRail(
                    targets: snapshot.alphabetTargets,
                    selectedSectionID: selectedDirectorySectionID,
                    selectedKey: selectedDirectoryKey
                ) { key, sectionID in
                    selectedDirectoryKey = key
                    selectedDirectorySectionID = sectionID
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo(sectionID, anchor: .top)
                    }
                }

                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(snapshot.listItems) { item in
                        switch item {
                        case let .sectionHeader(section):
                            HStack {
                                TunerLabel(text: section.title, color: .offscriptSignalYellow, size: 10)
                                    .accessibilityIdentifier("LibrarySectionHeader\(section.title)")
                                Spacer()
                                TunerLabel(text: "\(section.rowCount) CH", color: .offscriptSoftPaper, size: 8)
                            }
                            .padding(.top, 12)
                            .padding(.bottom, 6)
                            .id(section.id)

                        case let .row(row):
                            Button {
                                selectedPodcastID = row.podcastID
                            } label: {
                                PodcastShelfRow(
                                    row: row,
                                    channelNumber: row.channelNumber,
                                    unplayedCount: row.unplayedCount,
                                    inProgressCount: row.inProgressCount,
                                    isCompact: isCompactDirectory
                                )
                                .equatable()
                            }
                            .buttonStyle(.plain)
                            // Rich VoiceOver label folds the channel
                            // number, author, in-progress count,
                            // unplayed count, and sync-failure chip
                            // into the "Open ... channel" stop. Without
                            // this the parent button's label
                            // ("Open <title> channel") clobbers every
                            // child — VO loses the metadata sighted
                            // users see right next to the title.
                            .accessibilityLabel(libraryShelfRowAccessibilityLabel(for: row))

                        case .rowSeparator, .sectionSeparator:
                            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    @MainActor
    private func loadDirectoryPodcastsIfNeeded() {
        guard !didLoadDirectoryPodcasts else { return }
        loadDirectoryPodcasts()
    }

    @MainActor
    private func loadDirectoryPodcasts(force: Bool = false) {
        guard force || !didLoadDirectoryPodcasts else { return }
        directoryPodcastLoadTask?.cancel()
        let modelContainer = modelContext.container
        let interval = OffScriptPerformanceLog.begin(
            "library.directory.fetch",
            metadata: "force=\(force)"
        )
        directoryPodcastLoadTask = Task { @MainActor in
            do {
                let store = LibraryDirectoryCountStore(modelContainer: modelContainer)
                let podcasts = try await store.subscribedPodcasts()
                guard !Task.isCancelled else {
                    OffScriptPerformanceLog.end(
                        interval,
                        metadata: "force=\(force) cancelled=true"
                    )
                    return
                }
                directoryPodcasts = podcasts
                didLoadDirectoryPodcasts = true
                rebuildDirectorySnapshot()
                OffScriptPerformanceLog.end(
                    interval,
                    metadata: "podcasts=\(directoryPodcasts.count) force=\(force)"
                )
            } catch {
                directoryPodcasts = []
                didLoadDirectoryPodcasts = true
                cachedDirectorySnapshot = .empty
                didBuildDirectorySnapshot = true
                OffScriptPerformanceLog.end(
                    interval,
                    metadata: "podcasts=0 force=\(force) failed=true"
                )
                libraryLogger.error("Library directory snapshot load failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @MainActor
    private func reloadDirectoryAfterSubscriptionChangeIfPossible() {
        guard isLibraryTabActive, shouldReloadDirectoryOnAppear, selectedPodcastID == nil else { return }
        shouldReloadDirectoryOnAppear = false
        loadDirectoryPodcasts(force: true)
        loadLibraryEpisodeSummary()
    }

    @MainActor
    private func refreshDirectoryAfterBatchImportIfActive() {
        guard isLibraryTabActive else {
            shouldReloadDirectoryOnAppear = true
            return
        }
        loadDirectoryPodcasts(force: true)
        scheduleLibraryEpisodeSummaryLoad()
    }

    @MainActor
    private func handleActiveTabChanged(_ note: Notification) {
        guard let tab = note.userInfo?["tab"] as? String else { return }
        if tab == "library" {
            isLibraryTabActive = true
            reloadDirectoryAfterSubscriptionChangeIfPossible()
        } else {
            isLibraryTabActive = false
            cancelDeferredLibraryWork()
        }
    }

    @MainActor
    private func cancelDeferredLibraryWork() {
        summaryLoadTask?.cancel()
        fullCountLoadTask?.cancel()
        directoryPodcastLoadTask?.cancel()
        directorySnapshotTask?.cancel()
        directoryQueryTask?.cancel()
    }

    private func podcast(withID id: UUID) -> Podcast? {
        do {
            var descriptor = FetchDescriptor<Podcast>(
                predicate: #Predicate<Podcast> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            return try modelContext.fetch(descriptor).first
        } catch {
            libraryLogger.error("Library selected podcast lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @MainActor
    private func subscribedPodcasts(withIDs ids: [UUID]) throws -> [Podcast] {
        var podcastsByID: [UUID: Podcast] = [:]
        var startIndex = ids.startIndex
        while startIndex < ids.endIndex {
            let endIndex = ids.index(
                startIndex,
                offsetBy: Self.subscriptionIDFetchChunkSize,
                limitedBy: ids.endIndex
            ) ?? ids.endIndex
            let chunkIDs = Set(ids[startIndex..<endIndex])
            if !chunkIDs.isEmpty {
                let descriptor = FetchDescriptor<Podcast>(
                    predicate: #Predicate<Podcast> {
                        chunkIDs.contains($0.id) && $0.isSubscribed
                    }
                )
                let chunkPodcasts = try modelContext.fetch(descriptor)
                for podcast in chunkPodcasts {
                    podcastsByID[podcast.id] = podcast
                }
            }
            startIndex = endIndex
        }
        return ids.compactMap { podcastsByID[$0] }
    }

    @MainActor
    private func loadLibraryEpisodeSummary() {
        startLibraryEpisodeSummaryLoad(deferWhileImporting: false)
    }

    @MainActor
    private func scheduleLibraryEpisodeSummaryLoad() {
        startLibraryEpisodeSummaryLoad(deferWhileImporting: true)
    }

    @MainActor
    private func startLibraryEpisodeSummaryLoad(deferWhileImporting: Bool) {
        summaryLoadTask?.cancel()
        fullCountLoadTask?.cancel()
        fullUnplayedCountsByPodcastID = [:]
        fullInProgressCountsByPodcastID = [:]
        didLoadFullUnplayedCounts = false
        didLoadFullInProgressCounts = false
        isLoadingFullDirectoryCounts = false
        let podcastIDs = subscribedPodcastIDs
        guard !podcastIDs.isEmpty else {
            freshEpisodes = []
            inProgressEpisodes = []
            inProgressEpisodeCount = 0
            freshInProgressCountsByPodcastID = [:]
            unplayedEpisodeCount = 0
            freshUnplayedCountsByPodcastID = [:]
            fullUnplayedCountsByPodcastID = [:]
            fullInProgressCountsByPodcastID = [:]
            didLoadFullUnplayedCounts = false
            didLoadFullInProgressCounts = false
            fullCountLoadTask?.cancel()
            isLoadingFullDirectoryCounts = false
            return
        }

        summaryLoadTask = Task { @MainActor in
            if deferWhileImporting, BatchImportService.shared.isRunning {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled, !BatchImportService.shared.isRunning else { return }
            }
            await refreshLibraryEpisodeSummary(
                podcastIDs: podcastIDs,
                modelContainer: modelContext.container
            )
        }
    }

    @MainActor
    private func refreshLibraryEpisodeSummary(
        podcastIDs: [UUID],
        modelContainer: ModelContainer
    ) async {
        let interval = OffScriptPerformanceLog.begin(
            "library.summary",
            metadata: "podcasts=\(podcastIDs.count)"
        )
        do {
            let countStore = LibraryDirectoryCountStore(modelContainer: modelContainer)
            let summary = try await countStore.episodeSummary()
            guard !Task.isCancelled else {
                OffScriptPerformanceLog.end(
                    interval,
                    metadata: "podcasts=\(podcastIDs.count) cancelled=true"
                )
                return
            }

            var combinedEpisodeIDs = summary.freshEpisodeIDs
            var seenEpisodeIDs = Set(combinedEpisodeIDs)
            for episodeID in summary.inProgressEpisodeIDs where seenEpisodeIDs.insert(episodeID).inserted {
                combinedEpisodeIDs.append(episodeID)
            }
            let hydratedEpisodes = try episodes(withIDs: combinedEpisodeIDs)
            let episodesByID = Dictionary(uniqueKeysWithValues: hydratedEpisodes.map { ($0.id, $0) })
            let hydratedFreshEpisodes = summary.freshEpisodeIDs.compactMap { episodesByID[$0] }
            let hydratedInProgressEpisodes = summary.inProgressEpisodeIDs.compactMap { episodesByID[$0] }
            guard !Task.isCancelled else {
                OffScriptPerformanceLog.end(
                    interval,
                    metadata: "podcasts=\(podcastIDs.count) cancelled=true"
                )
                return
            }

            unplayedEpisodeCount = summary.unplayedCount
            freshEpisodes = hydratedFreshEpisodes
            inProgressEpisodeCount = summary.inProgressCount
            inProgressEpisodes = hydratedInProgressEpisodes
            freshUnplayedCountsByPodcastID = summary.freshUnplayedCountsByPodcastID
            freshInProgressCountsByPodcastID = summary.freshInProgressCountsByPodcastID
            if directoryNeedsFullCounts {
                startFullDirectoryCountLoad(
                    podcastIDs: podcastIDs,
                    needsUnplayed: directoryNeedsFullUnplayedCounts,
                    needsInProgress: directoryNeedsFullInProgressCounts
                )
            }
            OffScriptPerformanceLog.end(
                interval,
                metadata: "podcasts=\(podcastIDs.count) unplayed=\(unplayedEpisodeCount) inProgress=\(inProgressEpisodeCount)"
            )
        } catch {
            freshEpisodes = []
            inProgressEpisodes = []
            inProgressEpisodeCount = 0
            freshInProgressCountsByPodcastID = [:]
            unplayedEpisodeCount = 0
            freshUnplayedCountsByPodcastID = [:]
            fullUnplayedCountsByPodcastID = [:]
            fullInProgressCountsByPodcastID = [:]
            didLoadFullUnplayedCounts = false
            didLoadFullInProgressCounts = false
            OffScriptPerformanceLog.end(
                interval,
                metadata: "podcasts=\(podcastIDs.count) failed=true"
            )
            libraryLogger.error("Library summary load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func episodes(withIDs ids: [UUID]) throws -> [Episode] {
        guard !ids.isEmpty else { return [] }
        let requestedIDs = Set(ids)
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { requestedIDs.contains($0.id) }
        )
        let episodes = try modelContext.fetch(descriptor)
        let episodesByID = Dictionary(uniqueKeysWithValues: episodes.map { ($0.id, $0) })
        return ids.compactMap { episodesByID[$0] }
    }

    @MainActor
    private func ensureFullDirectoryCountsIfNeeded() {
        guard directoryNeedsFullCounts else { return }
        guard !subscribedPodcastIDs.isEmpty else { return }
        guard !didLoadRequiredFullDirectoryCounts else { return }
        let missingCounts = LibraryDirectoryOrganizer.missingFullCountRequirements(
            scope: directoryScope,
            sort: directorySort,
            didLoadUnplayed: didLoadFullUnplayedCounts,
            didLoadInProgress: didLoadFullInProgressCounts
        )
        startFullDirectoryCountLoad(
            podcastIDs: subscribedPodcastIDs,
            needsUnplayed: missingCounts.unplayed,
            needsInProgress: missingCounts.inProgress
        )
    }

    @MainActor
    private func startFullDirectoryCountLoad(
        podcastIDs: [UUID],
        needsUnplayed: Bool,
        needsInProgress: Bool
    ) {
        guard needsUnplayed || needsInProgress else { return }
        fullCountLoadTask?.cancel()
        isLoadingFullDirectoryCounts = true
        let modelContainer = modelContext.container
        fullCountLoadTask = Task { @MainActor in
            await refreshFullDirectoryCounts(
                podcastIDs: podcastIDs,
                needsUnplayed: needsUnplayed,
                needsInProgress: needsInProgress,
                modelContainer: modelContainer
            )
        }
    }

    @MainActor
    private func refreshFullDirectoryCounts(
        podcastIDs: [UUID],
        needsUnplayed: Bool,
        needsInProgress: Bool,
        modelContainer: ModelContainer
    ) async {
        let interval = OffScriptPerformanceLog.begin(
            "library.fullCounts",
            metadata: "podcasts=\(podcastIDs.count) unplayed=\(needsUnplayed) inProgress=\(needsInProgress)"
        )
        do {
            guard !Task.isCancelled else {
                isLoadingFullDirectoryCounts = false
                OffScriptPerformanceLog.end(
                    interval,
                    metadata: "podcasts=\(podcastIDs.count) unplayed=\(needsUnplayed) inProgress=\(needsInProgress) cancelled=true"
                )
                return
            }
            let countStore = LibraryDirectoryCountStore(modelContainer: modelContainer)
            let counts = try await countStore.countsByPodcastID(
                podcastIDs: podcastIDs,
                needsUnplayed: needsUnplayed,
                needsInProgress: needsInProgress
            )

            guard !Task.isCancelled else {
                isLoadingFullDirectoryCounts = false
                OffScriptPerformanceLog.end(
                    interval,
                    metadata: "podcasts=\(podcastIDs.count) unplayed=\(needsUnplayed) inProgress=\(needsInProgress) cancelled=true"
                )
                return
            }
            if needsUnplayed {
                fullUnplayedCountsByPodcastID = counts.unplayedByPodcastID
                didLoadFullUnplayedCounts = true
            }
            if needsInProgress {
                fullInProgressCountsByPodcastID = counts.inProgressByPodcastID
                didLoadFullInProgressCounts = true
            }
            isLoadingFullDirectoryCounts = false
            OffScriptPerformanceLog.end(
                interval,
                metadata: "podcasts=\(podcastIDs.count) unplayed=\(needsUnplayed) inProgress=\(needsInProgress)"
            )
        } catch {
            if needsUnplayed {
                fullUnplayedCountsByPodcastID = [:]
                didLoadFullUnplayedCounts = false
            }
            if needsInProgress {
                fullInProgressCountsByPodcastID = [:]
                didLoadFullInProgressCounts = false
            }
            isLoadingFullDirectoryCounts = false
            OffScriptPerformanceLog.end(
                interval,
                metadata: "podcasts=\(podcastIDs.count) failed=true"
            )
            libraryLogger.error("Library per-show directory count load failed: \(error.localizedDescription, privacy: .public)")
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
    private func reconcileSelectedDirectoryTarget(with snapshot: LibraryDirectorySnapshot) {
        guard let selectedKey = selectedDirectoryKey else {
            if let selectedDirectorySectionID,
               !snapshot.sections.contains(where: { $0.id == selectedDirectorySectionID }) {
                self.selectedDirectorySectionID = nil
            }
            return
        }
        guard let target = snapshot.alphabetTargets.first(where: { $0.key == selectedKey }),
              let sectionID = target.sectionID else {
            self.selectedDirectoryKey = nil
            self.selectedDirectorySectionID = nil
            return
        }
        selectedDirectorySectionID = sectionID
    }

    @MainActor
    private func syncSubscriptions() async {
        guard !isSyncingLibrary else { return }
        isSyncingLibrary = true
        // Clear any prior summary chip while a new sync runs so the
        // user doesn't see a stale "✓ SYNCED 50" while a fresh pass is
        // mid-flight.
        lastSyncResult = nil
        lastSyncResultClearTask?.cancel()
        defer { isSyncingLibrary = false }
        let podcastIDs = subscribedPodcastIDs
        guard !podcastIDs.isEmpty else { return }
        let interval = OffScriptPerformanceLog.begin(
            "library.sync",
            metadata: "podcasts=\(podcastIDs.count)"
        )
        do {
            let podcasts = try subscribedPodcasts(withIDs: podcastIDs)
            let results = await syncService.sync(
                podcasts: podcasts,
                in: modelContext,
                options: .standard()
            )
            let failures = results.filter { !$0.isSuccess }
            for result in failures {
                if let error = result.error {
                    libraryLogger.error("Pull-to-refresh sync failed for '\(result.podcast.title, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                }
            }
            OffScriptPerformanceLog.end(
                interval,
                metadata: "podcasts=\(podcasts.count) failed=\(failures.count)"
            )
            recordSyncResult(LibrarySyncResult(total: podcasts.count, failed: failures.count))
        } catch {
            OffScriptPerformanceLog.end(
                interval,
                metadata: "podcasts=\(podcastIDs.count) failed=true"
            )
            libraryLogger.error("Pull-to-refresh sync setup failed: \(error.localizedDescription, privacy: .public)")
            recordSyncResult(LibrarySyncResult(total: podcastIDs.count, failed: podcastIDs.count))
        }
        loadDirectoryPodcasts(force: true)
        loadLibraryEpisodeSummary()
    }

    /// Capture the latest sync outcome and schedule auto-clear so the
    /// chip doesn't linger forever — the user gets ~6s of feedback,
    /// then the chip dismisses on its own. The next manual SYNC also
    /// clears it immediately (via `syncSubscriptions`'s reset).
    private func recordSyncResult(_ result: LibrarySyncResult) {
        lastSyncResult = result
        lastSyncResultClearTask?.cancel()
        lastSyncResultClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled {
                lastSyncResult = nil
            }
        }
    }
}

// MARK: - Header

private struct LibraryTunerHeader: View {
    let showCount: Int
    let visibleCount: Int
    let unplayedCount: Int
    let inProgressCount: Int
    let onOpenImport: () -> Void
    let isSyncing: Bool
    let onSync: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TunerLabel(text: "LIBRARY · CHANNEL DIRECTORY", color: .offscriptSignalYellow)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Library")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                // Import key — paste URL or import OPML. The most-asked-for
                // missing feature in podcast apps; lives next to settings
                // since both are operational chrome rather than per-content.
                Button(action: onOpenImport) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 7) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 12, weight: .semibold))
                            TunerLabel(text: "IMPORT", color: .offscriptSignalYellow, size: 9)
                        }
                        .foregroundStyle(Color.offscriptSignalYellow)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.offscriptSignalYellow)
                            .frame(width: 36, height: 30)
                            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Import podcasts")

                // Sync + Tune match the IMPORT key's icon+label hairline-
                // rectangle pattern so the right-aligned trio reads as one
                // uniform key bank instead of one big button next to two
                // small icon-only squares (#187). ViewThatFits drops the
                // labels under width pressure (large Dynamic Type, narrow
                // devices) without breaking the layout.
                Button(action: onSync) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 7) {
                            Image(systemName: isSyncing ? "waveform.path" : "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                            TunerLabel(
                                text: "SYNC",
                                color: isSyncing ? .offscriptFnInfo : .offscriptSignalYellow,
                                size: 9
                            )
                        }
                        .foregroundStyle(isSyncing ? Color.offscriptFnInfo : Color.offscriptSignalYellow)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

                        Image(systemName: isSyncing ? "waveform.path" : "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSyncing ? Color.offscriptFnInfo : Color.offscriptSignalYellow)
                            .frame(width: 36, height: 30)
                            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSyncing)
                .accessibilityLabel(isSyncing ? "Syncing library" : "Sync library")

                Button(action: onOpenSettings) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 7) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 12, weight: .semibold))
                            TunerLabel(text: "TUNE", color: .offscriptSignalYellow, size: 9)
                        }
                        .foregroundStyle(Color.offscriptSignalYellow)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.offscriptSignalYellow)
                            .frame(width: 36, height: 30)
                            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open settings")
            }

            // Inline mono readout — hidden when the library is empty so a
            // fresh-install user doesn't see "0 / 0 / 0 / 0" above the
            // empty-state copy. The same vertical band is then absorbed by
            // the empty-state padding, centering the message instead of
            // pushing it down past redundant zeros.
            if showCount > 0 {
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
            }

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
        // Combine the value+label so VoiceOver reads "12 shows" once
        // instead of "12, SHOWS" as two separate stops. Same fix as
        // the Settings stats row (#245).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label.lowercased())")
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
            .tunerRailEdgeFade()
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
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct LibraryAlphabetRail: View {
    let targets: [LibraryAlphabetTarget]
    let selectedSectionID: String?
    let selectedKey: String?
    let onSelect: (String, String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(targets) { target in
                        let isSelected = selectedKey == target.key
                            || (selectedKey == nil && selectedSectionID == target.sectionID && target.isExact)

                        if let targetSectionID = target.sectionID {
                            Button {
                                onSelect(target.key, targetSectionID)
                            } label: {
                                letterKey(
                                    target.key,
                                    isSelected: isSelected,
                                    isNearestJump: target.isNearestJump,
                                    isReachable: true
                                )
                            }
                            .id(target.key)
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(target.isNearestJump ? "Jump near \(target.key)" : "Jump to \(target.key)")
                            .accessibilityIdentifier("LibraryJumpLetter\(target.key)")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        } else {
                            letterKey(target.key, isSelected: false, isNearestJump: false, isReachable: false)
                                .id(target.key)
                                .accessibilityLabel("No \(target.key) channels")
                                .accessibilityIdentifier("LibraryJumpLetter\(target.key)")
                                .accessibilityAddTraits(.isStaticText)
                        }
                    }
                }
                .padding(.vertical, 4)
                .onChange(of: selectedSectionID) { _, newValue in
                    guard let key = selectedKey ?? newValue.flatMap({ sectionID in
                        targets.first(where: { $0.sectionID == sectionID && $0.isExact })?.key
                    }) else { return }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(key, anchor: .center)
                    }
                }
            }
            .accessibilityIdentifier("LibraryAlphabetCarousel")
        }
    }

    private func letterKey(
        _ key: String,
        isSelected: Bool,
        isNearestJump: Bool,
        isReachable: Bool
    ) -> some View {
        Text(key)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(letterColor(isSelected: isSelected, isNearestJump: isNearestJump, isReachable: isReachable))
            .frame(width: 30, height: 30)
            .background(isSelected ? Color.offscriptSignalYellow.opacity(0.16) : Color.clear)
            .overlay(
                Rectangle()
                    .stroke(
                        isSelected ? Color.offscriptSignalYellow : (isNearestJump ? Color.offscriptSoftPaper.opacity(0.72) : Color.offscriptHairline),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(isReachable ? 1 : 0.42)
    }

    private func letterColor(
        isSelected: Bool,
        isNearestJump: Bool,
        isReachable: Bool
    ) -> Color {
        guard isReachable else { return .offscriptTextMuted }
        if isSelected { return .offscriptSignalYellow }
        return isNearestJump ? .offscriptSoftPaper : .offscriptSignalYellow
    }
}

private struct LibraryDirectoryEmptyState: View {
    let query: String
    let scope: LibraryDirectoryScope
    var onClear: (() -> Void)? = nil

    private var hasActiveFilter: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || scope != .all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TunerLabel(text: "○ NO DIRECTORY MATCH", color: .offscriptSoftPaper)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.offscriptPaperWhite.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            // Recovery key — without this, a user who narrowed scope
            // to NEEDS SYNC and got 0 results had to scroll up and
            // manually flip back to ALL. One-tap reset matches the
            // PodcastDetail × CLEAR FILTER affordance.
            if hasActiveFilter, let onClear {
                Button(action: onClear) {
                    TunerLabel(text: "× CLEAR FILTER", color: .offscriptSignalYellow, size: 10)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear directory filter and search")
                .accessibilityIdentifier("LibraryDirectoryClearFilter")
            }
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
            .tunerRailEdgeFade()
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
                        cornerRadius: 3,
                        size: 64
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
                        TunerTag(text: reason, color: .offscriptSignalYellow, dim: true, wraps: true)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            // Combine artwork + podcast eyebrow + title + reason into
            // one VoiceOver stop. Sibling Play / Queue keys keep their
            // own a11y elements. Mirrors PodcastEpisodeTunerRow (#265)
            // and SearchResultRow (#261).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Open \(episode.title) from \(episode.podcast.title), \(reason)")

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
                .accessibilityLabel(episode.isQueued ? "\(episode.title) already queued" : "Add \(episode.title) to queue")

                Spacer()
            }
        }
        .padding(10)
        .frame(width: 280, alignment: .leading)
        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
    }
}

// MARK: - Show row

/// Build the rich VoiceOver label for a directory row's "Open …
/// channel" button. Folds the channel number, author, in-progress /
/// unplayed counts, and sync-failure flag into a single readout so VO
/// users get the same context sighted users see next to the title.
private func libraryShelfRowAccessibilityLabel(for row: LibraryDirectoryRow) -> String {
    // Speak the zero-padded channel number ("Open channel 03") so the
    // readout matches what sighted users see in the mono gutter (#264
    // review).
    let channel = String(format: "%02d", row.channelNumber)
    var parts: [String] = ["Open channel \(channel)", row.title]
    if let author = row.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
        parts.append("by \(author)")
    }
    if row.inProgressCount > 0 {
        parts.append("\(row.inProgressCount) in progress")
    }
    parts.append("\(row.unplayedCount) unplayed")
    if row.hasSyncFailure {
        parts.append("sync failed")
    }
    return parts.joined(separator: ", ")
}

private struct PodcastShelfRow: View {
    let row: LibraryDirectoryRow
    let channelNumber: Int
    let unplayedCount: Int
    let inProgressCount: Int
    let isCompact: Bool

    /// Surface a `● SYNC FAILED` chip on the row when the feed has
    /// failed to refresh — without it, a podcast whose feed went 404
    /// (host moved, feed renamed, episode source dropped) looks
    /// identical to a healthy one in the directory until the user
    /// opens it. The `needsSync` filter scope already collects these,
    /// but the chip flags them inline so users notice without
    /// changing scope. Predicate centralized on
    /// `LibraryDirectoryRow.hasSyncFailure` so this chip and the
    /// row-level VoiceOver readout never drift (#264 review).
    private var hasSyncFailure: Bool { row.hasSyncFailure }

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", channelNumber))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.offscriptSignalYellow)
                .frame(width: 28, alignment: .leading)

            if !isCompact {
                OffScriptArtworkView(url: row.artworkURL, cornerRadius: 3, size: 56)
                    .frame(width: 56, height: 56)
                    .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(1)
                if let author = row.author {
                    TunerLabel(text: author.uppercased(), color: .offscriptSoftPaper, size: 8)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if inProgressCount > 0 {
                        TunerLabel(text: "● \(inProgressCount) IN PROGRESS", color: .offscriptFnInfo, size: 8)
                    }
                    TunerLabel(text: "\(unplayedCount) UNPLAYED", color: .offscriptSoftPaper, size: 8)
                    if hasSyncFailure {
                        TunerLabel(text: "● SYNC FAILED", color: .offscriptFnRecord, size: 8)
                            .accessibilityIdentifier("PodcastShelfRow.SyncFailed")
                    }
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
                .accessibilityHidden(true)
        }
        .padding(.vertical, isCompact ? 7 : 10)
    }
}

extension PodcastShelfRow: Equatable {
    static func == (lhs: PodcastShelfRow, rhs: PodcastShelfRow) -> Bool {
        lhs.row == rhs.row
            && lhs.channelNumber == rhs.channelNumber
            && lhs.unplayedCount == rhs.unplayedCount
            && lhs.inProgressCount == rhs.inProgressCount
            && lhs.isCompact == rhs.isCompact
    }
}

private struct LibraryDirectoryMissingShowView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TunerLabel(text: "● CHANNEL UNAVAILABLE", color: .offscriptFnRecord)
            Text("This show is no longer in your library.")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.offscriptPaperWhite)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, OffScriptTheme.pagePadding)
        .padding(.top, OffScriptTheme.detailContentTopPadding)
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
    }
}

// MARK: - PodcastDetailView (Tuner channel detail)

struct PodcastDetailView: View {
    @Environment(\.dismiss) private var dismiss
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
    private let syncService = FeedSyncService()

    init(podcast: Podcast) {
        self.podcast = podcast
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TunerInlineBackButton(
                    label: "BACK",
                    accessibilityLabel: "Back to library",
                    accessibilityIdentifier: "PodcastDetailBackButton"
                ) {
                    dismiss()
                }

                PodcastDetailTunerHeader(podcast: podcast, episodeCount: matchingEpisodeCount)

                // Custom Tuner search input — `.searchable()` renders a system
                // rounded translucent search bar on iOS 26 that clashes with
                // every other Tuner surface. Same pattern as SearchView's
                // tunerSearchField.
                tunerEpisodeSearchField

                FilterRow(selection: $filter)

                if let loadError {
                    VStack(alignment: .leading, spacing: 8) {
                        TunerLabel(text: "LOAD ERROR · \(loadError.uppercased())", color: .offscriptFnRecord)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            loadEpisodes(resetLimit: true)
                        } label: {
                            TunerLabel(text: "↻ RETRY", color: .offscriptSignalYellow, size: 10)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Retry loading episodes")
                    }
                }

                if episodes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        TunerLabel(text: "● NO EPISODES MATCH FILTER", color: .offscriptSoftPaper)
                        Text(episodeSearchQuery.isEmpty
                             ? "Change the filter or sync this feed again later."
                             : "No episodes match \"\(episodeSearchQuery)\".")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Color.offscriptPaperWhite)

                        // Inline recovery key — tapping the filter back to
                        // ALL or clearing the search query is otherwise a
                        // two-step manual undo (find the filter row, find
                        // the right chip). Surface it inline so the user
                        // doesn't have to re-orient.
                        if filter != .all || !episodeSearchQuery.isEmpty {
                            Button {
                                filter = .all
                                episodeSearchQuery = ""
                            } label: {
                                TunerLabel(text: "× CLEAR FILTER", color: .offscriptSignalYellow, size: 10)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(minHeight: 44)
                                    .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear episode filter and search")
                            .accessibilityIdentifier("PodcastDetailClearFilter")
                        }
                    }
                    .padding(.vertical, 12)
                    .overlay(
                        Rectangle().fill(Color.offscriptHairline).frame(height: 1),
                        alignment: .top
                    )
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(episodes.enumerated()), id: \.element.id) { idx, episode in
                            PodcastEpisodeTunerRow(
                                episode: episode,
                                rank: PodcastDetailRanker.chronologicalRank(
                                    explicitEpisodeNumber: episode.episodeNumber,
                                    displayedIndex: idx,
                                    totalEpisodeCount: matchingEpisodeCount,
                                    filterShowsFullFeed: filter == .all
                                )
                            )
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
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Load 100 more episodes")
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
        // Pull-to-refresh — native iOS gesture for re-syncing this
        // single feed without bouncing back to Library. Companion to
        // the new ↻ REFRESH key in the PodcastDetail header from #238.
        .refreshable {
            do {
                try await syncService.sync(
                    podcast: podcast,
                    in: modelContext,
                    options: .standard()
                )
            } catch {
                libraryLogger.error("PodcastDetail pull-to-refresh failed for '\(podcast.title, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
            loadEpisodes(resetLimit: false)
        }
        .accessibilityIdentifier("PodcastDetailScreen")
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
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

        let interval = OffScriptPerformanceLog.begin(
            "podcast.detail.loadEpisodes",
            metadata: "podcast=\(podcast.title) limit=\(visibleLimit) reset=\(resetLimit)"
        )

        do {
            let query = episodeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var descriptor = episodeFetchDescriptor(searchQuery: query)
            matchingEpisodeCount = (try? modelContext.fetchCount(descriptor)) ?? 0
            descriptor.fetchLimit = visibleLimit + 1
            let fetched = try modelContext.fetch(descriptor)
            episodes = Array(fetched.prefix(visibleLimit))
            hasMoreEpisodes = fetched.count > visibleLimit
            loadError = nil
            OffScriptPerformanceLog.end(interval, metadata: "rows=\(episodes.count) total=\(matchingEpisodeCount) more=\(hasMoreEpisodes)")
        } catch {
            episodes = []
            matchingEpisodeCount = 0
            hasMoreEpisodes = false
            loadError = error.localizedDescription
            libraryLogger.error("Podcast detail load failed: \(error.localizedDescription, privacy: .public)")
            OffScriptPerformanceLog.end(interval, metadata: "error=\(error.localizedDescription)")
        }
    }

    private func episodeFetchDescriptor(searchQuery query: String) -> FetchDescriptor<Episode> {
        let podcastID = podcast.id
        let downloadedRawValue = Episode.DownloadState.downloaded.rawValue
        let baseSort = [SortDescriptor(\Episode.pubDate, order: .reverse)]
        let hasQuery = !query.isEmpty

        switch filter {
        case .all:
            return FetchDescriptor<Episode>(
                predicate: #Predicate<Episode> {
                    $0.podcast.id == podcastID
                        && (!hasQuery
                            || $0.title.localizedStandardContains(query)
                            || ($0.summary?.localizedStandardContains(query) ?? false))
                },
                sortBy: baseSort
            )
        case .unplayed:
            return FetchDescriptor<Episode>(
                predicate: #Predicate<Episode> {
                    $0.podcast.id == podcastID
                        && $0.isPlayed == false
                        && (!hasQuery
                            || $0.title.localizedStandardContains(query)
                            || ($0.summary?.localizedStandardContains(query) ?? false))
                },
                sortBy: baseSort
            )
        case .inProgress:
            return FetchDescriptor<Episode>(
                predicate: #Predicate<Episode> {
                    $0.podcast.id == podcastID
                        && $0.playedPosition > 0
                        && $0.isPlayed == false
                        && (!hasQuery
                            || $0.title.localizedStandardContains(query)
                            || ($0.summary?.localizedStandardContains(query) ?? false))
                },
                sortBy: baseSort
            )
        case .downloaded:
            return FetchDescriptor<Episode>(
                predicate: #Predicate<Episode> {
                    $0.podcast.id == podcastID
                        && $0.downloadStateRawValue == downloadedRawValue
                        && (!hasQuery
                            || $0.title.localizedStandardContains(query)
                            || ($0.summary?.localizedStandardContains(query) ?? false))
                },
                sortBy: baseSort
            )
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
    @State private var isRefreshing = false
    private let syncService = FeedSyncService()

    /// Same definition as LibraryDirectoryRow.hasSyncFailure (#206).
    /// Either a failure count > 0 or a `failed` syncStatus flips the
    /// chip on so the user knows the feed went bad without having to
    /// flip Library scope to NEEDS SYNC.
    private var hasSyncFailure: Bool {
        podcast.syncFailureCount > 0 || podcast.syncStatus == "failed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TunerLabel(text: "CHANNEL · DETAIL", color: .offscriptSignalYellow)
                Spacer()
                if hasSyncFailure {
                    // Mirror the Library directory `● SYNC FAILED`
                    // chip (#206). Surfacing it on the detail header
                    // tells the user the feed went bad even when the
                    // subscription is technically still active.
                    TunerLabel(text: "● SYNC FAILED", color: .offscriptFnRecord)
                        .accessibilityIdentifier("PodcastDetailSyncFailed")
                }
                TunerLabel(text: podcast.isSubscribed ? "● SUBSCRIBED" : "○ UNSUBSCRIBED",
                           color: podcast.isSubscribed ? .offscriptFnMode : .offscriptSoftPaper)
            }

            HStack(alignment: .top, spacing: 14) {
                OffScriptArtworkView(url: podcast.artworkURL, cornerRadius: 3, size: 96)
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
                .tracking(0)
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
                    .accessibilityLabel("Unsubscribe from \(podcast.title)")
                    .accessibilityIdentifier("PodcastDetailUnsubscribeButton")
                }

                if let url = podcast.websiteURL {
                    Button {
                        safariURL = IdentifiableURL(url: url)
                    } label: {
                        // Bumped to 44pt min-height alongside the new
                        // ↻ REFRESH key so the row reads as a uniform
                        // action bar.
                        TunerLabel(text: "→ WEBSITE", color: .offscriptSignalYellow, size: 10)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(minHeight: 44)
                            .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(podcast.title) website")
                }

                // Per-feed refresh — pull-to-refresh on Library only
                // works from that tab, and the SYNC key on Library
                // refreshes EVERY feed. A user looking at one show who
                // wants the latest episodes shouldn't have to bounce
                // back to Library and re-sync 50 feeds.
                Button {
                    Task { await refreshFeed() }
                } label: {
                    TunerLabel(
                        text: isRefreshing ? "○ REFRESHING…" : "↻ REFRESH",
                        color: .offscriptSignalYellow,
                        size: 10
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(minHeight: 44)
                    .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh \(podcast.title) feed")
                .accessibilityIdentifier("PodcastDetailRefreshFeed")

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

    @MainActor
    private func refreshFeed() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await syncService.sync(
                podcast: podcast,
                in: modelContext,
                options: .standard()
            )
        } catch {
            libraryLogger.error("PodcastDetail refresh feed failed for '\(podcast.title, privacy: .public)': \(error.localizedDescription, privacy: .public)")
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
                    // Match Queue × CLEAR ALL / Settings × RESET confirm
                    // panels: 44pt min height, equal-weight CANCEL/×
                    // CONFIRM, paperWhite Cancel for the same vocabulary
                    // across destructive bulk actions.
                    TunerLabel(text: "CANCEL", color: .offscriptPaperWhite, size: 11)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel unsubscribe")

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showUnsubscribeConfirmation = false
                        _ = PodcastUnsubscribeService.unsubscribe(podcast, in: modelContext)
                    }
                } label: {
                    TunerLabel(text: "× UNSUBSCRIBE", color: .offscriptFnRecord, size: 11)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Confirm unsubscribe")
                .accessibilityIdentifier("PodcastDetailConfirmUnsubscribeButton")
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
    let rank: Int?

    private var progressValue: Double {
        guard let duration = episode.duration, duration > 0 else { return 0 }
        return episode.playedPosition / duration
    }

    private var rankLabel: String {
        if let rank { return String(format: "%03d", rank) }
        return "—"
    }

    /// VoiceOver readout for the row's NavigationLink. Conditionally
    /// includes the chronological rank when the metadata won't already
    /// announce an episode number (feeds without <itunes:episode> still
    /// get a computed `chronologicalRank` and surface the `%03d` glyph
    /// to sighted users). Appends the stripped summary so VO users get
    /// the description text sighted users see (#265 review).
    fileprivate var rowAccessibilityLabel: String {
        var parts: [String] = ["Open \(episode.title)"]
        if episode.episodeNumber == nil, let rank {
            parts.append("rank \(rank)")
        }
        if !voiceOverMetadata.isEmpty { parts.append(voiceOverMetadata) }
        if let summary = episode.summary {
            let stripped = summary.strippingHTML
            if !stripped.isEmpty {
                parts.append(stripped)
            }
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                EpisodeDetailView(episode: episode)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(rankLabel)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(rank == nil ? Color.offscriptSoftPaper : Color.offscriptSignalYellow)
                        .frame(width: 32, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(episode.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.offscriptPaperWhite)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)

                        TunerLabel(text: metadata, color: .offscriptSoftPaper, size: 8)

                        // Skip the row's summary `Text` entirely when the
                        // stripped form is empty — feeds with HTML-only
                        // boilerplate (`<p>&nbsp;</p>`) used to render an
                        // invisible Text on every row, paying the
                        // `strippingHTML` cost on each scroll-recycle for
                        // no visible output (#169).
                        if let summary = episode.summary {
                            let stripped = summary.strippingHTML
                            if !stripped.isEmpty {
                                Text(stripped)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Color.offscriptPaperWhite.opacity(0.7))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            // Combine the NavigationLink into a single VoiceOver stop
            // so each row reads as one navigation, not three. Sibling
            // Play / Queue / More keys stay their own a11y elements.
            // Build label inline so we can:
            //   - conditionally include rankLabel when the metadata
            //     readout would NOT already encode it (i.e. when the
            //     feed lacks <itunes:episode> so metadata won't have
            //     "E<n>"). Otherwise rank would double-announce.
            //   - append the stripped summary when present so VO users
            //     don't lose the description text the row shows
            //     sighted users (#265 review).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rowAccessibilityLabel)

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
                .accessibilityLabel(episode.isQueued ? "\(episode.title) already queued" : "Add \(episode.title) to queue")

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

    /// VoiceOver-friendly metadata variant — drops uppercasing and the
    /// "·" separator so VO doesn't speak the punctuation literally,
    /// and expands "S2 E5" to "Season 2 Episode 5" so the readout
    /// pronounces sensibly. The visible mono `metadata` is unchanged.
    /// Same pattern as HomeView TunerRailCard's voiceOverMetadata
    /// (#267 review).
    private var voiceOverMetadata: String {
        var parts: [String] = []
        if let s = episode.seasonNumber, let e = episode.episodeNumber {
            parts.append("Season \(s) Episode \(e)")
        } else if let e = episode.episodeNumber {
            parts.append("Episode \(e)")
        }
        parts.append(episode.pubDate.formatted(date: .abbreviated, time: .omitted))
        if let duration = episode.duration {
            parts.append(EpisodeDurationFormatter.short(duration))
        }
        return parts.joined(separator: ", ")
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
                    .accessibilityLabel("Filter episodes by \(filter.title)")
                    .accessibilityAddTraits(selection == filter ? .isSelected : [])
                }
            }
        }
        .tunerRailEdgeFade()
    }
}

/// Tuner-styled status strip that surfaces background OPML imports.
/// Renders nothing while the importer is idle. While running shows a
/// live count and a hairline progress rail; when finished shows the
/// summary with a dismiss key. Lives at the top of the Library page so
/// the user always sees what's happening once they leave the sheet.
private struct LibrarySyncResultStrip: View {
    let result: LibrarySyncResult
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            if result.failed == 0 {
                TunerLabel(text: "✓ SYNCED \(result.succeeded)", color: .offscriptFnMode)
                    .accessibilityIdentifier("LibrarySyncResult.AllSucceeded")
            } else if result.succeeded == 0 {
                TunerLabel(text: "● SYNC FAILED", color: .offscriptFnRecord)
                    .accessibilityIdentifier("LibrarySyncResult.AllFailed")
                Text("\(result.failed) feeds failed to refresh.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.offscriptPaperWhite)
            } else {
                TunerLabel(text: "● SYNCED \(result.succeeded) · \(result.failed) FAILED", color: .offscriptFnRecord)
                    .accessibilityIdentifier("LibrarySyncResult.PartialFailure")
                Text("Filter to NEEDS SYNC to see which.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onDismiss) {
                TunerLabel(text: "× DISMISS", color: .offscriptSoftPaper, size: 9)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss sync result")
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
        .transition(.opacity)
    }
}

private struct LibraryBatchImportStrip: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var importer = BatchImportService.shared
    var onFinished: () -> Void = {}

    var body: some View {
        Group {
            switch importer.phase {
            case .idle:
                EmptyView()
            case .running:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        // Combined into a single VoiceOver element so
                        // it reads "Importing 12 of 50 feeds in
                        // background" instead of two separate stops.
                        // Cancel button stays its own a11y element.
                        HStack(spacing: 10) {
                            TunerLabel(text: "● IMPORTING IN BACKGROUND",
                                       color: .offscriptSignalYellow)
                            Spacer()
                            TunerLabel(text: "\(importer.completedCount)/\(importer.totalCount)",
                                       color: .offscriptFnInfo)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Importing \(importer.completedCount) of \(importer.totalCount) \(importer.totalCount == 1 ? "feed" : "feeds") in background")

                        // Cancel key — once a long OPML batch is running
                        // there was no way to abort it short of force-
                        // quitting the app. Existing work is preserved
                        // (already-imported feeds stay), pending rows
                        // get marked .cancelled.
                        Button {
                            importer.cancel()
                        } label: {
                            TunerLabel(text: "× CANCEL", color: .offscriptFnRecord, size: 9)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel import")
                        .accessibilityIdentifier("LibraryBatchImportCancel")
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
                    Text(finishedSummary(added: added, failed: failed))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.offscriptPaperWhite)
                    Spacer()
                    if failed > 0 {
                        Button {
                            importer.retryFailed(modelContext: modelContext)
                        } label: {
                            TunerLabel(text: "↻ RETRY \(failed)",
                                       color: .offscriptSignalYellow, size: 9)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Retry \(failed) failed feed imports")
                        .accessibilityIdentifier("LibraryBatchImportRetryFailed")
                    }
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
        .onChange(of: importer.phase) { oldPhase, phase in
            if oldPhase.isRunning && !phase.isRunning {
                onFinished()
            }
        }
    }

    private func finishedSummary(added: Int, failed: Int) -> String {
        let skipped = importer.skippedCount
        if failed == 0, skipped == 0 {
            return "Added \(added) shows"
        }
        if failed == 0 {
            return "Added \(added), \(skipped) already tuned"
        }
        if skipped == 0 {
            return "Added \(added), \(failed) failed"
        }
        return "Added \(added), \(skipped) already tuned, \(failed) failed"
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

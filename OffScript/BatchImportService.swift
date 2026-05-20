import Combine
import Foundation
import OSLog
import SwiftData
import SwiftUI

private let batchImportLogger = Logger(subsystem: "com.offscript", category: "BatchImport")

/// App-lifetime singleton that runs OPML-batch imports in the background
/// so the user can dismiss the import sheet (or close the Library tab)
/// and the work keeps going. The Library renders a status strip bound
/// to `progress` / `phase` so progress is always visible somewhere
/// without blocking interaction with the rest of the app.
@MainActor
final class BatchImportService: ObservableObject {
    static let shared = BatchImportService()
    private static let feedURLLookupChunkSize = 96

    enum Phase: Equatable {
        case idle
        case running
        case finished(added: Int, failed: Int)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: [URL: ImportRowStatus] = [:]
    @Published private(set) var entries: [OPMLFeedEntry] = []

    /// True while an import is running. Library uses this to render a
    /// toast / status strip; the sheet uses it to disable the kick-off
    /// button while a previous batch is still finishing.
    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    var addedCount: Int {
        progress.values.filter { if case .added = $0 { true } else { false } }.count
    }

    var failedCount: Int {
        progress.values.filter { if case .failed = $0 { true } else { false } }.count
    }

    var skippedCount: Int {
        progress.values.filter { if case .skipped = $0 { true } else { false } }.count
    }

    var cancelledCount: Int {
        progress.values.filter { if case .cancelled = $0 { true } else { false } }.count
    }

    var completedCount: Int { addedCount + skippedCount + failedCount + cancelledCount }

    var totalCount: Int { entries.count }

    private let syncService = FeedSyncService()
    private var task: Task<Void, Never>?
    private var activeModelContext: ModelContext?

    private struct FetchOutcome: Sendable {
        let entry: OPMLFeedEntry
        let result: Result<FeedSyncService.ParsedFeedFetch, Error>
    }

    private init() {}

    #if DEBUG
    /// Drop singleton state that would otherwise leak across in-memory
    /// `ModelContainer`s in the test suite. The running `task` calls
    /// into `syncService.importPodcast` which inserts/updates `Podcast`
    /// + `Episode` rows via the cached `activeModelContext`; if that
    /// context was torn down by a previous test, the next `save()` or
    /// `fetch()` crashes inside SwiftData. Cancelling the task and
    /// dropping the context here prevents that cross-test crash class.
    /// Mirrors the lurking-crash playbook in `docs/TEST_MATRIX.md`.
    func debugResetForTesting() {
        task?.cancel()
        task = nil
        activeModelContext = nil
        progress = [:]
        entries = []
        phase = .idle
    }
    #endif

    /// Kick off a batch import and return immediately. Caller is free to
    /// dismiss the sheet — work continues. Re-calling while a batch is
    /// running is a no-op (so a stray double-tap doesn't restart).
    func start(entries: [OPMLFeedEntry], modelContext: ModelContext) {
        guard !isRunning else { return }

        let uniqueEntries = Self.deduplicated(entries)
        let existingFeedKeys = Self.subscribedFeedKeys(in: modelContext)
        let plan = Self.importPlan(for: uniqueEntries, existingFeedKeys: existingFeedKeys)
        self.entries = uniqueEntries
        activeModelContext = modelContext
        progress = plan.initialProgress
        phase = .running

        guard !plan.entriesToImport.isEmpty else {
            phase = .finished(added: addedCount, failed: failedCount)
            activeModelContext = nil
            return
        }

        do {
            _ = try Self.stageSubscriptions(for: plan.entriesToImport, in: modelContext)
        } catch {
            batchImportLogger.error("OPML subscription staging failed: \(error.localizedDescription, privacy: .public)")
        }

        task = Task { [weak self] in
            await self?.runBatch(entries: plan.entriesToImport, modelContext: modelContext)
        }
    }

    /// Cancel the running batch. Already-imported feeds stay imported; no new
    /// rows are enqueued after cancellation, and cooperative network tasks get
    /// a cancellation signal through the parent task.
    func cancel() {
        task?.cancel()
        task = nil
        if isRunning {
            let unfinishedEntries = entries.filter { entry in
                let status = progress[entry.feedURL]
                return status == .pending || status == .importing
            }
            markUnfinishedRowsCancelled()
            if let activeModelContext {
                Self.markStagedSubscriptionsCancelled(for: unfinishedEntries, in: activeModelContext)
            }
            phase = .finished(added: addedCount, failed: failedCount)
            activeModelContext = nil
        }
    }

    /// Acknowledge a finished batch and reset to idle. Called by the
    /// status strip's "× DISMISS" affordance.
    func dismiss() {
        guard !isRunning else { return }
        phase = .idle
        progress = [:]
        entries = []
    }

    /// Re-run a finished batch against just the failed entries. Common
    /// case is a flaky network: 5 of 50 feeds 404'd transiently, the
    /// user wants to retry only those without re-importing the full
    /// OPML and re-skipping the 45 that already landed. Already-added
    /// rows stay added; cancelled rows stay cancelled.
    func retryFailed(modelContext: ModelContext) {
        guard !isRunning else { return }
        let failedEntries = entries.filter { entry in
            if case .failed = progress[entry.feedURL] { return true }
            return false
        }
        guard !failedEntries.isEmpty else { return }
        // Reset just the failed rows back to pending so the strip's
        // running progress reflects the retry-only count instead of
        // re-counting the whole batch.
        for entry in failedEntries {
            progress[entry.feedURL] = .pending
        }
        // Replace `entries` with the retry-only set so totalCount /
        // completedCount drive the progress rail correctly.
        entries = failedEntries
        activeModelContext = modelContext
        phase = .running

        do {
            _ = try Self.stageSubscriptions(for: failedEntries, in: modelContext)
        } catch {
            batchImportLogger.error("OPML retry staging failed: \(error.localizedDescription, privacy: .public)")
        }

        task = Task { [weak self] in
            await self?.runBatch(entries: failedEntries, modelContext: modelContext)
        }
    }

    // MARK: - Internals

    private func runBatch(entries: [OPMLFeedEntry], modelContext: ModelContext) async {
        // Bounded parallelism overlaps slow feed hosts, but completed feeds
        // are applied back into SwiftData serially on the main actor.
        let concurrency = 6
        await withTaskGroup(of: FetchOutcome.self) { group in
            var iterator = entries.makeIterator()
            var inFlight = 0

            while !Task.isCancelled, inFlight < concurrency, let entry = iterator.next() {
                progress[entry.feedURL] = .importing
                inFlight += 1
                Self.addFetchTask(for: entry, to: &group)
            }

            while let outcome = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    markUnfinishedRowsCancelled()
                    break
                }
                progress[outcome.entry.feedURL] = await apply(outcome: outcome, modelContext: modelContext)
                if !Task.isCancelled, let nextEntry = iterator.next() {
                    progress[nextEntry.feedURL] = .importing
                    Self.addFetchTask(for: nextEntry, to: &group)
                }
            }
        }

        guard !Task.isCancelled else {
            markUnfinishedRowsCancelled()
            phase = .finished(added: addedCount, failed: failedCount)
            activeModelContext = nil
            return
        }
        phase = .finished(added: addedCount, failed: failedCount)
        activeModelContext = nil
    }

    private static func addFetchTask(for entry: OPMLFeedEntry, to group: inout TaskGroup<FetchOutcome>) {
        group.addTask {
            do {
                try Task.checkCancellation()
                let fetched = try await FeedSyncService.fetchParsedOPMLFeed(
                    for: entry,
                    options: .opmlBootstrap()
                )
                return FetchOutcome(entry: entry, result: .success(fetched))
            } catch {
                return FetchOutcome(entry: entry, result: .failure(error))
            }
        }
    }

    private func apply(outcome: FetchOutcome, modelContext: ModelContext) async -> ImportRowStatus {
        switch outcome.result {
        case let .success(fetched):
            do {
                try Task.checkCancellation()
                _ = try await syncService.importPodcast(
                    from: outcome.entry,
                    parsedFeed: fetched.parsed,
                    httpResponse: fetched.httpResponse,
                    into: modelContext,
                    options: .opmlBootstrap()
                )
                try Task.checkCancellation()
                return .added
            } catch is CancellationError {
                Self.markStagedSubscriptionCancelled(entry: outcome.entry, in: modelContext)
                return .cancelled
            } catch {
                Self.markStagedSubscriptionFailed(entry: outcome.entry, error: error, in: modelContext)
                batchImportLogger.error("OPML row apply failed for \(outcome.entry.feedURL.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return .failed
            }
        case let .failure(error):
            if error is CancellationError {
                Self.markStagedSubscriptionCancelled(entry: outcome.entry, in: modelContext)
                return .cancelled
            }
            Self.markStagedSubscriptionFailed(entry: outcome.entry, error: error, in: modelContext)
            batchImportLogger.error("OPML row fetch failed for \(outcome.entry.feedURL.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    private func markUnfinishedRowsCancelled() {
        for (feedURL, status) in progress {
            if status == .pending || status == .importing {
                progress[feedURL] = .cancelled
            }
        }
    }

    static func deduplicated(_ entries: [OPMLFeedEntry]) -> [OPMLFeedEntry] {
        var seen = Set<String>()
        var result: [OPMLFeedEntry] = []
        for entry in entries {
            let key = entry.feedURL.normalizedFeedKey
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(entry)
        }
        return result
    }

    static func importPlan(
        for entries: [OPMLFeedEntry],
        existingFeedKeys: Set<String>
    ) -> (entriesToImport: [OPMLFeedEntry], initialProgress: [URL: ImportRowStatus]) {
        var entriesToImport: [OPMLFeedEntry] = []
        var initialProgress: [URL: ImportRowStatus] = [:]

        for entry in entries {
            if existingFeedKeys.contains(entry.feedURL.normalizedFeedKey) {
                initialProgress[entry.feedURL] = .skipped
            } else {
                initialProgress[entry.feedURL] = .pending
                entriesToImport.append(entry)
            }
        }

        return (entriesToImport, initialProgress)
    }

    @discardableResult
    static func stageSubscriptions(
        for entries: [OPMLFeedEntry],
        in modelContext: ModelContext
    ) throws -> Int {
        guard !entries.isEmpty else { return 0 }

        let existingPodcasts = try podcasts(matching: entries, in: modelContext)
        var podcastByFeedKey = Dictionary(
            existingPodcasts.map { ($0.feedURL.normalizedFeedKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var stagedCount = 0
        let now = Date()

        for entry in entries {
            let key = entry.feedURL.normalizedFeedKey
            let title = entry.title.flatMap(Self.trimmedNonEmpty)
                ?? entry.feedURL.host
                ?? entry.feedURL.absoluteString
            let author = entry.author.flatMap(Self.trimmedNonEmpty)

            if let podcast = podcastByFeedKey[key] {
                podcast.feedURL = entry.feedURL
                podcast.isSubscribed = true
                podcast.title = title
                podcast.author = author ?? podcast.author
                if podcast.subscribedAt == nil {
                    podcast.subscribedAt = now
                }
                podcast.lastSyncAttemptAt = now
                podcast.syncStatus = "syncing"
                podcast.syncErrorMessage = nil
            } else {
                let podcast = Podcast(
                    title: title,
                    author: author,
                    feedURL: entry.feedURL,
                    isSubscribed: true
                )
                podcast.subscribedAt = now
                podcast.lastSyncAttemptAt = now
                podcast.syncStatus = "syncing"
                modelContext.insert(podcast)
                podcastByFeedKey[key] = podcast
            }

            stagedCount += 1
        }

        try modelContext.save()
        return stagedCount
    }

    static func markStagedSubscriptionFailed(
        entry: OPMLFeedEntry,
        error: Error,
        in modelContext: ModelContext
    ) {
        do {
            guard let podcast = try stagedPodcast(for: entry, in: modelContext) else { return }
            let failureCount = podcast.syncFailureCount + 1
            podcast.syncStatus = "failed"
            podcast.syncFailureCount = failureCount
            podcast.syncErrorMessage = error.localizedDescription
            podcast.nextRetryAt = FeedSyncRetryPolicy.nextRetryDate(afterFailureCount: failureCount)
            try modelContext.save()
        } catch {
            batchImportLogger.error("Failed to mark staged OPML row failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func markStagedSubscriptionCancelled(
        entry: OPMLFeedEntry,
        in modelContext: ModelContext
    ) {
        do {
            guard let podcast = try stagedPodcast(for: entry, in: modelContext) else { return }
            podcast.syncStatus = "idle"
            podcast.syncErrorMessage = nil
            podcast.nextRetryAt = nil
            try modelContext.save()
        } catch {
            batchImportLogger.error("Failed to mark staged OPML row cancelled: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func markStagedSubscriptionsCancelled(
        for entries: [OPMLFeedEntry],
        in modelContext: ModelContext
    ) {
        do {
            let feedKeys = Set(entries.map { $0.feedURL.normalizedFeedKey })
            guard !feedKeys.isEmpty else { return }
            let podcasts = try podcasts(matching: entries, in: modelContext)
                .filter { feedKeys.contains($0.feedURL.normalizedFeedKey) }
            for podcast in podcasts {
                podcast.syncStatus = "idle"
                podcast.syncErrorMessage = nil
                podcast.nextRetryAt = nil
            }
            try modelContext.save()
        } catch {
            batchImportLogger.error("Failed to mark staged OPML rows cancelled: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func stagedPodcast(
        for entry: OPMLFeedEntry,
        in modelContext: ModelContext
    ) throws -> Podcast? {
        let feedURL = entry.feedURL
        var descriptor = FetchDescriptor<Podcast>(
            predicate: #Predicate<Podcast> { $0.feedURL == feedURL }
        )
        descriptor.fetchLimit = 1
        if let exact = try modelContext.fetch(descriptor).first {
            return exact
        }

        let feedKey = entry.feedURL.normalizedFeedKey
        return try podcasts(matching: [entry], in: modelContext)
            .first { $0.feedURL.normalizedFeedKey == feedKey }
    }

    private static func podcasts(
        matching entries: [OPMLFeedEntry],
        in modelContext: ModelContext
    ) throws -> [Podcast] {
        let lookupURLs = Array(Set(entries.flatMap { feedURLLookupVariants(for: $0.feedURL) }))
        guard !lookupURLs.isEmpty else { return [] }

        var podcasts: [Podcast] = []
        var seenIDs = Set<UUID>()
        var startIndex = lookupURLs.startIndex
        while startIndex < lookupURLs.endIndex {
            // Keep each SwiftData `contains` predicate well below SQLite's
            // parameter ceiling after URL variant expansion.
            let endIndex = lookupURLs.index(
                startIndex,
                offsetBy: feedURLLookupChunkSize,
                limitedBy: lookupURLs.endIndex
            ) ?? lookupURLs.endIndex
            let chunk = Array(lookupURLs[startIndex..<endIndex])
            let matches = try modelContext.fetch(FetchDescriptor<Podcast>(
                predicate: #Predicate<Podcast> { chunk.contains($0.feedURL) }
            ))
            for podcast in matches where !seenIDs.contains(podcast.id) {
                seenIDs.insert(podcast.id)
                podcasts.append(podcast)
            }
            startIndex = endIndex
        }

        let requestedFeedKeys = Set(entries.map { $0.feedURL.normalizedFeedKey })
        let matchedFeedKeys = Set(podcasts.map { $0.feedURL.normalizedFeedKey })
        let missingFeedKeys = requestedFeedKeys.subtracting(matchedFeedKeys)
        if !missingFeedKeys.isEmpty, entries.count == 1 {
            let fallbackMatches = try modelContext.fetch(FetchDescriptor<Podcast>())
                .filter { missingFeedKeys.contains($0.feedURL.normalizedFeedKey) }
            for podcast in fallbackMatches where !seenIDs.contains(podcast.id) {
                seenIDs.insert(podcast.id)
                podcasts.append(podcast)
            }
        }
        return podcasts
    }

    private static func feedURLLookupVariants(for feedURL: URL) -> Set<URL> {
        guard var components = URLComponents(url: feedURL, resolvingAgainstBaseURL: false) else {
            return [feedURL]
        }

        let originalScheme = components.scheme?.lowercased()
        let normalized = URL(string: feedURL.normalizedFeedKey) ?? feedURL
        let normalizedPath = URLComponents(url: normalized, resolvingAgainstBaseURL: false)?.path ?? components.path
        let trimmedPath = normalizedPath.hasSuffix("/") && normalizedPath != "/"
            ? String(normalizedPath.dropLast())
            : normalizedPath
        let slashPath = trimmedPath.isEmpty || trimmedPath == "/" ? "/" : "\(trimmedPath)/"
        var schemes: Set<String> = ["https", "http", "feed"]
        if let originalScheme {
            schemes.insert(originalScheme)
        }
        let paths = Set([components.path, normalizedPath, trimmedPath, slashPath])

        components.fragment = nil
        components.host = components.host?.lowercased()
        if components.port == 80 || components.port == 443 {
            components.port = nil
        }

        var variants: Set<URL> = [feedURL, normalized]
        for scheme in schemes {
            for path in paths {
                var variantComponents = components
                variantComponents.scheme = scheme
                variantComponents.path = path
                if let url = variantComponents.url {
                    variants.insert(url)
                }
            }
        }
        return variants
    }

    private static func trimmedNonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func subscribedFeedKeys(in modelContext: ModelContext) -> Set<String> {
        do {
            let descriptor = FetchDescriptor<Podcast>(
                predicate: #Predicate<Podcast> { $0.isSubscribed }
            )
            return Set(try modelContext.fetch(descriptor).map { $0.feedURL.normalizedFeedKey })
        } catch {
            batchImportLogger.error("Existing feed preflight failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

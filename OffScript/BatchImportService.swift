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

    private init() {}

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

    // MARK: - Internals

    private func runBatch(entries: [OPMLFeedEntry], modelContext: ModelContext) async {
        // Bounded parallelism — 6 in flight is enough to overlap the
        // slow rows without tripping rate limits or hammering the device.
        let concurrency = 6
        await withTaskGroup(of: (URL, ImportRowStatus).self) { group in
            var iterator = entries.makeIterator()
            var inFlight = 0

            while !Task.isCancelled, inFlight < concurrency, let entry = iterator.next() {
                progress[entry.feedURL] = .importing
                inFlight += 1
                group.addTask { [syncService] in
                    await Self.runOne(entry: entry,
                                      syncService: syncService,
                                      modelContext: modelContext)
                }
            }

            while let (feedURL, status) = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    markUnfinishedRowsCancelled()
                    break
                }
                progress[feedURL] = status
                if !Task.isCancelled, let nextEntry = iterator.next() {
                    progress[nextEntry.feedURL] = .importing
                    group.addTask { [syncService] in
                        await Self.runOne(entry: nextEntry,
                                          syncService: syncService,
                                          modelContext: modelContext)
                    }
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

    private func markUnfinishedRowsCancelled() {
        for (feedURL, status) in progress {
            if status == .pending || status == .importing {
                progress[feedURL] = .cancelled
            }
        }
    }

    private static func runOne(entry: OPMLFeedEntry,
                               syncService: FeedSyncService,
                               modelContext: ModelContext) async -> (URL, ImportRowStatus) {
        do {
            try Task.checkCancellation()
            _ = try await syncService.importPodcast(from: entry,
                                                    into: modelContext,
                                                    options: .opmlBootstrap())
            try Task.checkCancellation()
            return (entry.feedURL, .added)
        } catch is CancellationError {
            await markStagedSubscriptionCancelled(entry: entry, in: modelContext)
            return (entry.feedURL, .cancelled)
        } catch {
            await markStagedSubscriptionFailed(entry: entry, error: error, in: modelContext)
            batchImportLogger.error("OPML row failed for \(entry.feedURL.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return (entry.feedURL, .failed)
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

        let existingPodcasts = try modelContext.fetch(FetchDescriptor<Podcast>())
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
            podcast.nextRetryAt = Date().addingTimeInterval(min(pow(2.0, Double(failureCount)) * 60, 60 * 60 * 6))
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
            podcast.syncErrorMessage = "Import cancelled."
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
        for entry in entries {
            markStagedSubscriptionCancelled(entry: entry, in: modelContext)
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
        return try modelContext.fetch(FetchDescriptor<Podcast>())
            .first { $0.feedURL.normalizedFeedKey == feedKey }
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

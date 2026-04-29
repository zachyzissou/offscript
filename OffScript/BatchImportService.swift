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

    var completedCount: Int { addedCount + failedCount }

    var totalCount: Int { entries.count }

    private let syncService = FeedSyncService()
    private var task: Task<Void, Never>?

    private init() {}

    /// Kick off a batch import and return immediately. Caller is free to
    /// dismiss the sheet — work continues. Re-calling while a batch is
    /// running is a no-op (so a stray double-tap doesn't restart).
    func start(entries: [OPMLFeedEntry], modelContext: ModelContext) {
        guard !isRunning else { return }

        let uniqueEntries = Self.deduplicated(entries)
        self.entries = uniqueEntries
        progress = Dictionary(uniqueKeysWithValues: uniqueEntries.map { ($0.feedURL, ImportRowStatus.pending) })
        phase = .running

        task = Task { [weak self] in
            await self?.runBatch(entries: uniqueEntries, modelContext: modelContext)
        }
    }

    /// Cancel the running batch. Already-imported feeds stay imported; no new
    /// rows are enqueued after cancellation, and cooperative network tasks get
    /// a cancellation signal through the parent task.
    func cancel() {
        task?.cancel()
        task = nil
        if isRunning {
            phase = .finished(added: addedCount, failed: failedCount)
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

        guard !Task.isCancelled else { return }
        phase = .finished(added: addedCount, failed: failedCount)
    }

    private static func runOne(entry: OPMLFeedEntry,
                               syncService: FeedSyncService,
                               modelContext: ModelContext) async -> (URL, ImportRowStatus) {
        do {
            try Task.checkCancellation()
            _ = try await syncService.importPodcast(from: entry,
                                                    into: modelContext,
                                                    options: .fastBatchImport(episodeLimit: 25))
            try Task.checkCancellation()
            return (entry.feedURL, .added)
        } catch is CancellationError {
            return (entry.feedURL, .failed)
        } catch {
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
}

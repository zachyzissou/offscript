import Combine
import Foundation
import SwiftData

@MainActor
final class SyncCoordinator: ObservableObject {
    static let shared = SyncCoordinator()

    struct Snapshot {
        let isSyncing: Bool
        let lastError: String?
        let nextRetryAt: Date?
        let failureCount: Int
    }

    @Published private(set) var snapshots: [UUID: Snapshot] = [:]

    private let service = FeedSyncService()
    private var modelContext: ModelContext?
    private var refreshTask: Task<Void, Never>?

    private init() {}

    func configure(context: ModelContext) {
        modelContext = context
        DownloadService.shared.configure(context: context)
    }

    func refreshSubscriptions(_ podcasts: [Podcast], force: Bool = false) async {
        refreshTask?.cancel()
        let maxConcurrency = 4
        refreshTask = Task { @MainActor in
            let eligible = podcasts.filter { $0.isSubscribed && (force || shouldRefresh($0)) }
            await withTaskGroup(of: Void.self) { group in
                var running = 0
                var index = eligible.startIndex
                while index < eligible.endIndex {
                    guard !Task.isCancelled else { return }
                    if running < maxConcurrency {
                        let podcast = eligible[index]
                        group.addTask { @MainActor in
                            await self.refresh(podcast: podcast, force: force)
                        }
                        running += 1
                        index = eligible.index(after: index)
                    } else {
                        await group.next()
                        running -= 1
                    }
                }
                await group.waitForAll()
            }
        }
        await refreshTask?.value
    }

    func refresh(podcast: Podcast, force: Bool = false) async {
        guard let modelContext else { return }
        guard force || shouldRefresh(podcast) else { return }

        updateSnapshot(for: podcast, isSyncing: true)
        podcast.lastSyncAttemptAt = .now
        podcast.syncStatus = "syncing"
        modelContext.saveOrLog("SyncCoordinator")

        do {
            try await service.sync(podcast: podcast, in: modelContext)
            podcast.syncFailureCount = 0
            podcast.syncErrorMessage = nil
            podcast.nextRetryAt = nil
            updateSnapshot(for: podcast, isSyncing: false)
            modelContext.saveOrLog("SyncCoordinator")
        } catch {
            let failureCount = podcast.syncFailureCount + 1
            podcast.syncFailureCount = failureCount
            podcast.syncErrorMessage = error.localizedDescription
            let retryDelay = min(pow(2.0, Double(failureCount)) * 60, 60 * 60 * 6)
            podcast.nextRetryAt = Date().addingTimeInterval(retryDelay)
            updateSnapshot(for: podcast, isSyncing: false, errorMessage: error.localizedDescription)
            modelContext.saveOrLog("SyncCoordinator")
        }
    }

    func scheduleForegroundRefreshIfNeeded() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<Podcast>(
            predicate: #Predicate<Podcast> { $0.isSubscribed == true }
        )
        guard let podcasts = try? modelContext.fetch(descriptor) else { return }

        Task {
            await refreshSubscriptions(podcasts)
        }
    }

    func snapshot(for podcast: Podcast) -> Snapshot {
        snapshots[podcast.id] ?? Snapshot(
            isSyncing: podcast.syncStatus == "syncing",
            lastError: podcast.syncErrorMessage,
            nextRetryAt: podcast.nextRetryAt,
            failureCount: podcast.syncFailureCount
        )
    }

    private func shouldRefresh(_ podcast: Podcast) -> Bool {
        if podcast.syncStatus == "syncing" { return false }
        if let nextRetryAt = podcast.nextRetryAt, nextRetryAt > .now { return false }
        if podcast.lastSyncAt == nil { return true }
        return podcast.lastSyncAt?.addingTimeInterval(60 * 45) ?? .distantPast <= .now
    }

    private func updateSnapshot(for podcast: Podcast, isSyncing: Bool, errorMessage: String? = nil) {
        snapshots[podcast.id] = Snapshot(
            isSyncing: isSyncing,
            lastError: errorMessage ?? podcast.syncErrorMessage,
            nextRetryAt: podcast.nextRetryAt,
            failureCount: podcast.syncFailureCount
        )
    }
}

import Foundation
import OSLog
import SwiftData

/// Lazily enriches episodes with FoundationModels NLP off the critical path.
/// Onboarding queues newly-imported episode IDs here; this service drains the
/// queue with bounded concurrency so the user's feed appears instantly while
/// AI summaries / tags fill in over the next few seconds.
@MainActor
final class BackgroundEnrichmentService {
    static let shared = BackgroundEnrichmentService()

    private let logger = Logger(subsystem: "OffScript", category: "Enrichment")
    private let extractor = TopicExtractionService()
    private var queued: [UUID] = []
    private var inFlight: Set<UUID> = []
    private var task: Task<Void, Never>?
    private let maxConcurrent = 2

    private init() {}

    func queue(episodeIDs: [UUID]) {
        for id in episodeIDs where !inFlight.contains(id) && !queued.contains(id) {
            queued.append(id)
        }
        startIfNeeded()
    }

    /// Drains episodes that don't yet have an EpisodeProfile.summary. Useful
    /// to call on app launch in case prior enrichment got cut off.
    func backfill(in context: ModelContext) {
        // `fetchLimit` lives on FetchDescriptor so the underlying SQL
        // returns at most 20 rows. Previously we fetched every unenriched
        // episode (potentially tens of thousands) just to take the first 20.
        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.profile == nil || $0.profile?.summary == nil },
            sortBy: [SortDescriptor(\Episode.pubDate, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        guard let unenriched = try? context.fetch(descriptor) else { return }
        queue(episodeIDs: unenriched.map(\.id))
    }

    private func startIfNeeded() {
        guard task == nil, !queued.isEmpty else { return }
        // Run at .utility QoS so we never preempt the user's interactions.
        task = Task(priority: .utility) { [weak self] in
            await self?.run()
            await MainActor.run { self?.task = nil }
        }
    }

    private func run() async {
        while !queued.isEmpty {
            let batch = takeBatch()
            await withTaskGroup(of: Void.self) { group in
                for id in batch {
                    group.addTask { [weak self] in
                        await self?.enrich(id: id)
                    }
                }
            }
        }
    }

    private func takeBatch() -> [UUID] {
        let batch = Array(queued.prefix(maxConcurrent))
        queued.removeFirst(min(maxConcurrent, queued.count))
        for id in batch {
            inFlight.insert(id)
        }
        return batch
    }

    private func enrich(id: UUID) async {
        defer { inFlight.remove(id) }
        guard let context = ModelContainerRef.shared?.mainContext else { return }
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.id == id }
        )
        guard let episode = try? context.fetch(descriptor).first else { return }
        do {
            try await extractor.enrich(episode: episode, in: context)
            try? context.save()
        } catch {
            logger.error("Enrich failed for \(id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}

import OSLog
import SwiftData
import SwiftUI

private let importLogger = Logger(subsystem: "com.offscript", category: "Import")

struct ImportProgressView: View {
    @Environment(\.modelContext) private var modelContext

    let podcasts: [PodcastSearchResult]
    let selectedGenres: Set<Genre>
    let onComplete: () -> Void

    @State private var statuses: [URL: ImportStatus] = [:]
    @State private var isComplete = false

    enum ImportStatus {
        case pending
        case importing
        case done
        case failed
    }

    private let syncService = FeedSyncService()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 14) {
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.offscriptAccent)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Color.offscriptAccent)
                }

                Text(isComplete ? "Your feed is ready" : "Building your feed...")
                    .font(.offscriptDisplay)
                    .foregroundStyle(Color.offscriptTextPrimary)

                Text(isComplete ? "Head in — your recommendations are waiting." : "Fetching episodes and learning your taste...")
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                ForEach(podcasts, id: \.feedURL) { podcast in
                    ImportRow(
                        podcast: podcast,
                        status: statuses[podcast.feedURL] ?? .pending
                    )
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .task {
            await runImports()
        }
    }

    // Onboarding-time tuning. We deliberately import only the most recent
    // episodes per podcast so first-launch isn't waiting on a 500-episode
    // back catalog (common for shows like NPR, etc). Background sync can
    // backfill the rest later.
    private let onboardingEpisodeLimit = 15
    private let maxConcurrentImports = 4

    @MainActor
    private func runImports() async {
        // Persist genre preferences immediately — doesn't depend on imports.
        UserDefaults.standard.set(selectedGenres.map(\.rawValue), forKey: "offscript.preferredGenres")

        // Mark all selected podcasts as importing up front so the UI shows
        // every row pulsing — better feedback than rows lighting up serially.
        for podcast in podcasts {
            statuses[podcast.feedURL] = .importing
        }

        // Bounded-concurrency parallel imports. TaskGroup with `maxConcurrentImports`
        // keeps us from saturating the network or the SwiftData write queue
        // while still cutting wall time roughly N× for N selected podcasts.
        await withTaskGroup(of: (URL, Result<Podcast, Error>).self) { group in
            var inFlight = 0
            var iterator = podcasts.makeIterator()

            func enqueueNext() {
                guard let podcast = iterator.next() else { return }
                inFlight += 1
                group.addTask { [syncService, modelContext, onboardingEpisodeLimit] in
                    do {
                        let imported = try await syncService.importPodcast(
                            from: podcast,
                            into: modelContext,
                            episodeLimit: onboardingEpisodeLimit
                        )
                        return (podcast.feedURL, .success(imported))
                    } catch {
                        return (podcast.feedURL, .failure(error))
                    }
                }
            }

            // Seed the pipeline.
            for _ in 0..<min(maxConcurrentImports, podcasts.count) {
                enqueueNext()
            }

            // Drain results, enqueueing the next podcast each time one finishes.
            while let (feedURL, result) = await group.next() {
                inFlight -= 1
                switch result {
                case .success(let imported):
                    // Seed taste signal off-main since SwiftData inserts can stall the
                    // main thread when there are many models in flight.
                    if let newestEpisode = imported.episodes
                        .sorted(by: { $0.pubDate > $1.pubDate })
                        .first {
                        modelContext.insert(PreferenceSignal(action: .like, episode: newestEpisode))
                    }
                    statuses[feedURL] = .done
                case .failure(let error):
                    importLogger.error("Onboarding import failed for \(feedURL, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    statuses[feedURL] = .failed
                }
                enqueueNext()
            }
        }

        // Single batched save at the end — far cheaper than saving after each
        // import (every save runs migration checks + flushes the WAL).
        do {
            try modelContext.save()
        } catch {
            importLogger.error("Failed to save imported feed: \(error.localizedDescription, privacy: .public)")
        }

        // Done. No artificial sleep — we already showed live progress; the
        // user wants to get to their feed, not watch a checkmark for 2.7s.
        isComplete = true
        onComplete()
    }
}

private struct ImportRow: View {
    let podcast: PodcastSearchResult
    let status: ImportProgressView.ImportStatus

    var body: some View {
        HStack(spacing: 14) {
            OffScriptArtworkView(
                url: podcast.artworkURL,
                cornerRadius: OffScriptTheme.Radius.small
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(podcast.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .lineLimit(1)

                Text(podcast.author)
                    .font(.offscriptMeta)
                    .foregroundStyle(Color.offscriptTextMuted)
                    .lineLimit(1)
            }

            Spacer()

            Group {
                switch status {
                case .pending:
                    Circle()
                        .fill(Color.offscriptSurfaceLight)
                        .frame(width: 24, height: 24)
                case .importing:
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.offscriptAccent)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.offscriptAccent)
                        .font(.title3)
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.offscriptDestructive)
                        .font(.title3)
                }
            }
            .frame(width: 24, height: 24)
        }
        .padding(12)
        .background(Color.offscriptSurfaceFaint)
        .clipShape(RoundedRectangle(cornerRadius: OffScriptTheme.Radius.small, style: .continuous))
    }
}

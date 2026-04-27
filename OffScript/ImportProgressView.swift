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
        // Tuner-direction onboarding step 03 — instrument-cluster spec
        // sheet showing live import status per channel. Eyebrow tells the
        // user where they are in the flow (03 of 03). Each ImportRow shows
        // mono status badges (○ STANDBY / ● TUNING / ✓ TUNED / ✕ FAILED)
        // synced to function-coded colors.
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TunerLabel(text: "03 · TUNING", color: .offscriptSignalYellow)
                    Spacer()
                    TunerLabel(
                        text: isComplete ? "● COMPLETE" : "● TUNING \(doneCount)/\(podcasts.count)",
                        color: isComplete ? .offscriptFnMode : .offscriptSignalYellow
                    )
                }

                Text(isComplete ? "Channels tuned." : "Tuning channels…")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Color.offscriptPaperWhite)

                Text(isComplete
                     ? "Your feed is ready. Recommendations build as you listen."
                     : "Fetching the most recent episodes for each channel. This won't pull the full back catalog — background sync handles that later.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineSpacing(2)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)

                Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                    .padding(.top, 8)
            }

            VStack(spacing: 0) {
                ForEach(Array(podcasts.enumerated()), id: \.element.feedURL) { idx, podcast in
                    ImportRow(
                        podcast: podcast,
                        rank: idx + 1,
                        status: statuses[podcast.feedURL] ?? .pending
                    )
                    if idx < podcasts.count - 1 {
                        Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, OffScriptTheme.pagePadding)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
        .task {
            await runImports()
        }
    }

    private var doneCount: Int {
        statuses.values.filter { $0 == .done }.count
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
    let rank: Int
    let status: ImportProgressView.ImportStatus

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", rank))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.offscriptSignalYellow)
                .frame(width: 28, alignment: .leading)

            OffScriptArtworkView(url: podcast.artworkURL, cornerRadius: 3)
                .frame(width: 40, height: 40)
                .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(podcast.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(1)

                TunerLabel(text: podcast.author.uppercased(), color: .offscriptSoftPaper, size: 8)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statusBadge
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .pending:
            TunerLabel(text: "○ STANDBY", color: .offscriptSoftPaper, size: 9)
        case .importing:
            TunerLabel(text: "● TUNING", color: .offscriptSignalYellow, size: 9)
        case .done:
            TunerLabel(text: "✓ TUNED", color: .offscriptFnMode, size: 9)
        case .failed:
            TunerLabel(text: "✕ FAILED", color: .offscriptFnRecord, size: 9)
        }
    }
}

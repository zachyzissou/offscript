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
    @State private var hasFinishedAttempt = false
    @State private var isImporting = false

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
                        text: statusReadout,
                        color: statusReadoutColor
                    )
                }

                Text(headerTitle)
                    .font(.system(size: 32, weight: .bold))
                    .tracking(0)
                    .foregroundStyle(Color.offscriptPaperWhite)

                Text(headerCopy)
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

            if hasFailures {
                HStack(spacing: 10) {
                    Button {
                        Task { await runImports(onlyFailed: true) }
                    } label: {
                        TunerLabel(text: "↻ RETRY FAILED", color: .offscriptSignalYellow, size: 10)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(isImporting)

                    if doneCount > 0 {
                        Button {
                            isComplete = true
                            onComplete()
                        } label: {
                            TunerLabel(text: "→ CONTINUE", color: .offscriptFnInfo, size: 10)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
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

    private var failedCount: Int {
        statuses.values.filter { $0 == .failed }.count
    }

    private var hasFailures: Bool {
        hasFinishedAttempt && failedCount > 0 && !isComplete
    }

    private var statusReadout: String {
        if isComplete { return "● COMPLETE" }
        if hasFailures { return "● \(failedCount) FAILED" }
        return "● TUNING \(doneCount)/\(podcasts.count)"
    }

    private var statusReadoutColor: Color {
        if isComplete { return .offscriptFnMode }
        if hasFailures { return .offscriptFnRecord }
        return .offscriptSignalYellow
    }

    private var headerTitle: String {
        if isComplete { return "Channels tuned." }
        if hasFailures { return "Some channels missed." }
        return "Tuning channels..."
    }

    private var headerCopy: String {
        if isComplete {
            return "Your feed is ready. Recommendations build as you listen."
        }
        if hasFailures {
            return "Retry failed channels or continue with the feeds that tuned successfully."
        }
        return "Subscribing now. Starter episodes tune in behind the scenes so you can get into the app without waiting on feed hydration."
    }

    // Onboarding should commit selected subscriptions immediately. Starter
    // feed hydration runs after the app opens so first launch is not gated by
    // XML parsing, enrichment, external chapter fetches, or slow feed hosts.
    @MainActor
    private func runImports(onlyFailed: Bool = false) async {
        guard !isImporting else { return }
        isImporting = true

        // Persist genre preferences immediately — doesn't depend on imports.
        UserDefaults.standard.set(selectedGenres.map(\.rawValue), forKey: "offscript.preferredGenres")

        let selectedPodcasts = onlyFailed
            ? podcasts.filter { statuses[$0.feedURL] == .failed }
            : podcasts

        // Mark all selected podcasts as importing up front so the UI shows
        // every row pulsing while the local subscription rows are committed.
        for podcast in selectedPodcasts {
            statuses[podcast.feedURL] = .importing
        }

        let stagedPodcasts: [Podcast]
        do {
            stagedPodcasts = try syncService.stagePodcastSubscriptions(from: selectedPodcasts, into: modelContext)
            for podcast in selectedPodcasts {
                statuses[podcast.feedURL] = .done
            }
        } catch {
            importLogger.error("Onboarding subscription staging failed: \(error.localizedDescription, privacy: .public)")
            stagedPodcasts = []
            for podcast in selectedPodcasts {
                statuses[podcast.feedURL] = .failed
            }
        }

        hasFinishedAttempt = true
        if failedCount == 0 {
            isComplete = true
            isImporting = false
            onComplete()
        } else {
            isImporting = false
        }

        Task { @MainActor in
            await OnboardingHydrationScheduler.waitForPostOnboardingPaintGap()
            guard !Task.isCancelled else { return }
            await syncStagedPodcastsInBackground(stagedPodcasts)
        }
    }

    @MainActor
    private func syncStagedPodcastsInBackground(_ podcasts: [Podcast]) async {
        guard !podcasts.isEmpty else { return }

        let results = await syncService.sync(
            podcasts: podcasts,
            in: modelContext,
            options: .onboardingBootstrap()
        )
        for result in results {
            if result.isSuccess {
                if let newestEpisode = OnboardingPreferenceSignalService.newestEpisode(
                    for: result.podcast,
                    in: modelContext
                ) {
                    modelContext.insert(PreferenceSignal(action: .like, episode: newestEpisode))
                    modelContext.saveOrLog("OnboardingPreferenceSignal")
                }
            } else if let error = result.error {
                let failureCount = result.podcast.syncFailureCount + 1
                result.podcast.syncStatus = "failed"
                result.podcast.syncFailureCount = failureCount
                result.podcast.syncErrorMessage = error.localizedDescription
                result.podcast.nextRetryAt = FeedSyncRetryPolicy.nextRetryDate(afterFailureCount: failureCount)
                modelContext.saveOrLog("OnboardingBackgroundSync")
                importLogger.error("Onboarding background sync failed for \(result.podcast.feedURL, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

enum OnboardingHydrationScheduler {
    nonisolated static let defaultDelayNanoseconds: UInt64 = 1_200_000_000

    /// Applies a fixed post-onboarding yield plus sleep before applying feed
    /// hydration writes on the main SwiftData context. This is a timing
    /// heuristic only; it does not detect a completed Home render.
    @MainActor
    static func waitForPostOnboardingPaintGap(delayNanoseconds: UInt64 = defaultDelayNanoseconds) async {
        await Task.yield()
        guard delayNanoseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: delayNanoseconds)
    }
}

enum OnboardingPreferenceSignalService {
    @MainActor
    static func newestEpisode(for podcast: Podcast, in context: ModelContext) -> Episode? {
        let podcastID = podcast.id
        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.podcast.id == podcastID },
            sortBy: [SortDescriptor(\Episode.pubDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
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

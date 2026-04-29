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
                    .tracking(-0.5)
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
        return "Fetching the most recent episodes for each channel. This will not pull the full back catalog; background sync handles that later."
    }

    // Onboarding-time tuning. We deliberately import only the most recent
    // episodes per podcast so first-launch isn't waiting on a 500-episode
    // back catalog (common for shows like NPR, etc). Background sync can
    // backfill the rest later.
    private let onboardingEpisodeLimit = 15
    @MainActor
    private func runImports(onlyFailed: Bool = false) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        // Persist genre preferences immediately — doesn't depend on imports.
        UserDefaults.standard.set(selectedGenres.map(\.rawValue), forKey: "offscript.preferredGenres")

        let selectedPodcasts = onlyFailed
            ? podcasts.filter { statuses[$0.feedURL] == .failed }
            : podcasts

        // Mark all selected podcasts as importing up front so the UI shows
        // every row pulsing — better feedback than rows lighting up serially.
        for podcast in selectedPodcasts {
            statuses[podcast.feedURL] = .importing
        }

        // Keep SwiftData writes on the main actor. This onboarding path imports
        // a small selected starter set; the heavy OPML path uses BatchImportService.
        for podcast in selectedPodcasts {
            do {
                let imported = try await syncService.importPodcast(
                    from: podcast,
                    into: modelContext,
                    episodeLimit: onboardingEpisodeLimit
                )
                if let newestEpisode = imported.episodes
                    .sorted(by: { $0.pubDate > $1.pubDate })
                    .first {
                    modelContext.insert(PreferenceSignal(action: .like, episode: newestEpisode))
                }
                statuses[podcast.feedURL] = .done
            } catch {
                importLogger.error("Onboarding import failed for \(podcast.feedURL, privacy: .public): \(error.localizedDescription, privacy: .public)")
                statuses[podcast.feedURL] = .failed
            }
        }

        // Single batched save at the end — far cheaper than saving after each
        // import (every save runs migration checks + flushes the WAL).
        do {
            try modelContext.save()
        } catch {
            importLogger.error("Failed to save imported feed: \(error.localizedDescription, privacy: .public)")
        }

        hasFinishedAttempt = true
        if failedCount == 0 {
            isComplete = true
            onComplete()
        }
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

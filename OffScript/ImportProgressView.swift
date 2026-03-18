import SwiftData
import SwiftUI

struct ImportProgressView: View {
    @Environment(\.modelContext) private var modelContext

    let podcasts: [PodcastSearchResult]
    let selectedGenres: Set<Genre>
    let onComplete: () -> Void

    @State private var statuses: [URL: ImportStatus] = [:]
    @State private var errorMessages: [URL: String] = [:]
    @State private var isComplete = false
    @State private var isImporting = false
    @State private var recommendedEpisode: Episode?
    @State private var recommendedExplanation: String?

    enum ImportStatus {
        case pending
        case importing
        case done
        case failed
    }

    private let syncService = FeedSyncService()
    private let recommendationService = RecommendationService()

    var body: some View {
        ScrollView {
        VStack(spacing: 32) {
            Spacer(minLength: 40)

            VStack(spacing: 14) {
                if isComplete {
                    Image(systemName: failedPodcasts.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(failedPodcasts.isEmpty ? Color.offscriptAccent : Color.offscriptDestructive)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Color.offscriptAccent)
                }

                Text(titleText)
                    .font(.system(.title2, design: .serif, weight: .bold))
                    .foregroundStyle(Color.offscriptTextPrimary)

                Text(subtitleText)
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

            if isComplete {
                VStack(spacing: 12) {
                    if !failedPodcasts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Some feeds need another pass")
                                .font(.headline)
                                .foregroundStyle(Color.offscriptTextPrimary)

                            ForEach(failedPodcasts, id: \.feedURL) { podcast in
                                Text("\(podcast.title): \(errorMessages[podcast.feedURL] ?? "This feed timed out or returned invalid data.")")
                                    .font(.offscriptMeta)
                                    .foregroundStyle(Color.offscriptTextMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offscriptUtilitySurface()
                        .padding(.horizontal, 24)

                        HStack(spacing: 10) {
                            Button(isImporting ? "Retrying..." : "Retry failed") {
                                Task { await retryFailedImports() }
                            }
                            .buttonStyle(PrimaryPillButtonStyle())
                            .disabled(isImporting)

                            Button("Continue anyway") {
                                finishOnboarding()
                            }
                            .buttonStyle(SecondaryPillButtonStyle())
                        }
                    } else {
                        VStack(spacing: 10) {
                            if let recommendedEpisode {
                                FirstRecommendationCard(
                                    episode: recommendedEpisode,
                                    explanation: recommendedExplanation ?? "Start here."
                                )
                                .padding(.horizontal, 24)
                            } else {
                                Text("\(successfulImportCount) shows are in. Your first recommendations are ready.")
                                    .font(.offscriptBody)
                                    .foregroundStyle(Color.offscriptTextSecondary)
                                    .multilineTextAlignment(.center)
                            }

                            HStack(spacing: 10) {
                                if recommendedEpisode != nil {
                                    Button("Play Best Next") {
                                        playRecommendationAndFinish()
                                    }
                                    .buttonStyle(PrimaryPillButtonStyle())
                                }

                                if recommendedEpisode == nil {
                                    Button("Open OffScript") {
                                        finishOnboarding()
                                    }
                                    .buttonStyle(PrimaryPillButtonStyle())
                                } else {
                                    Button("Open Library") {
                                        finishOnboarding()
                                    }
                                    .buttonStyle(SecondaryPillButtonStyle())
                                }
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 40)
        }
        }
        .task {
            await runImports()
        }
    }

    @MainActor
    private func runImports() async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        TelemetryService.track(
            "onboarding_import_started",
            metadata: [
                "selected_genres": "\(selectedGenres.count)",
                "selected_podcasts": "\(podcasts.count)"
            ],
            in: modelContext
        )

        await importPodcasts(podcasts)

        AppSettings.preferredGenres = Array(selectedGenres).sorted { $0.title < $1.title }
        try? TasteProfileService.refresh(in: modelContext)
        let recommendation = bestRecommendationCandidate()
        recommendedEpisode = recommendation?.episode ?? fallbackRecommendationEpisode()
        recommendedExplanation = recommendation?.explanation ?? recommendedEpisode.map { "A strong first listen from \($0.podcast.title)." }

        TelemetryService.track(
            "onboarding_import_completed",
            metadata: [
                "successful": "\(successfulImportCount)",
                "failed": "\(failedPodcasts.count)"
            ],
            in: modelContext
        )

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isComplete = true
        }
    }

    @MainActor
    private func retryFailedImports() async {
        let failures = failedPodcasts
        guard !failures.isEmpty else { return }
        await importPodcasts(failures)
        try? TasteProfileService.refresh(in: modelContext)
        TelemetryService.track(
            "onboarding_import_retry_completed",
            metadata: [
                "remaining_failed": "\(failedPodcasts.count)",
                "successful": "\(successfulImportCount)"
            ],
            in: modelContext
        )
    }

    @MainActor
    private func importPodcasts(_ podcasts: [PodcastSearchResult]) async {
        for podcast in podcasts {
            statuses[podcast.feedURL] = .importing
            errorMessages[podcast.feedURL] = nil

            do {
                let imported = try await withThrowingTimeout(seconds: 45) {
                    try await syncService.importPodcast(from: podcast, into: modelContext, episodeLimit: 15)
                }

                if let newestEpisode = imported.episodes
                    .sorted(by: { $0.pubDate > $1.pubDate })
                    .first {
                    let signal = PreferenceSignal(action: .like, episode: newestEpisode)
                    modelContext.insert(signal)
                    try? modelContext.save()
                }

                TelemetryService.track(
                    "subscription_imported",
                    metadata: ["podcast": podcast.title, "source": "onboarding"],
                    in: modelContext
                )

                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    statuses[podcast.feedURL] = .done
                }
            } catch {
                let message = error is CancellationError
                    ? "This feed took too long to respond."
                    : error.localizedDescription
                errorMessages[podcast.feedURL] = message
                TelemetryService.track(
                    "subscription_import_failed",
                    metadata: ["podcast": podcast.title, "source": "onboarding", "error": message],
                    in: modelContext
                )
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    statuses[podcast.feedURL] = .failed
                }
            }
        }
    }

    private var failedPodcasts: [PodcastSearchResult] {
        podcasts.filter { statuses[$0.feedURL] == .failed }
    }

    private var successfulImportCount: Int {
        statuses.values.filter { $0 == .done }.count
    }

    private var titleText: String {
        if !isComplete { return "Building your feed..." }
        return failedPodcasts.isEmpty ? "Your feed is ready" : "Almost there"
    }

    private var subtitleText: String {
        if !isComplete { return "Fetching episodes and learning your taste..." }
        if failedPodcasts.isEmpty { return "Head in — your recommendations are waiting." }
        return "Most of your picks made it in. Retry the feeds that stalled, or keep going and fix them later."
    }

    private func finishOnboarding() {
        AppSettings.hasSeenOnboarding = true
        onComplete()
    }

    private func playRecommendationAndFinish() {
        guard let recommendedEpisode else {
            finishOnboarding()
            return
        }
        TelemetryService.track(
            "onboarding_recommendation_started",
            metadata: ["episode": recommendedEpisode.title, "podcast": recommendedEpisode.podcast.title],
            in: modelContext
        )
        PlaybackController.shared.play(recommendedEpisode, in: modelContext)
        finishOnboarding()
    }

    private func bestRecommendationCandidate() -> ScoredEpisode? {
        try? recommendationService.homeSections(context: modelContext, limit: 3).first?.scoredEpisodes.first
    }

    private func fallbackRecommendationEpisode() -> Episode? {
        let importedShows = (try? modelContext.fetch(FetchDescriptor<Podcast>()))?
            .filter { podcast in
                podcasts.contains { $0.feedURL == podcast.feedURL }
            } ?? []

        return importedShows
            .flatMap(\.episodes)
            .sorted { $0.pubDate > $1.pubDate }
            .first
    }

    private func withThrowingTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CancellationError()
            }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }
}

private struct FirstRecommendationCard: View {
    let episode: Episode
    let explanation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Start here")
                .font(.headline)
                .foregroundStyle(Color.offscriptTextPrimary)

            HStack(spacing: 12) {
                OffScriptArtworkView(
                    url: episode.artworkURL ?? episode.podcast.artworkURL,
                    cornerRadius: OffScriptTheme.Radius.small
                )
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 6) {
                    OffScriptExplanationTag(text: explanation)

                    Text(episode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .lineLimit(2)

                    Text(episode.podcast.title)
                        .font(.offscriptMeta)
                        .foregroundStyle(Color.offscriptTextMuted)
                        .lineLimit(1)
                }

                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offscriptUtilitySurface()
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
                        .fill(Color.offscriptFillLight)
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
        .padding(14)
        .background(Color.offscriptFillSubtle.opacity(0.67))
        .clipShape(RoundedRectangle(cornerRadius: OffScriptTheme.Radius.small, style: .continuous))
    }
}

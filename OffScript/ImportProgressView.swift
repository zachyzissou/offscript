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

    @MainActor
    private func runImports() async {
        for podcast in podcasts {
            statuses[podcast.feedURL] = .importing

            do {
                let imported = try await syncService.importPodcast(from: podcast, into: modelContext)

                // Seed taste: like the most recent episode
                if let newestEpisode = imported.episodes
                    .sorted(by: { $0.pubDate > $1.pubDate })
                    .first {
                    let signal = PreferenceSignal(action: .like, episode: newestEpisode)
                    modelContext.insert(signal)
                    do { try modelContext.save() } catch { importLogger.error("Failed to save taste seed signal for '\(podcast.title, privacy: .public)': \(error.localizedDescription, privacy: .public)") }
                }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    statuses[podcast.feedURL] = .done
                }
            } catch {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    statuses[podcast.feedURL] = .failed
                }
            }
        }

        // Persist genre preferences
        let genreStrings = selectedGenres.map(\.rawValue)
        UserDefaults.standard.set(genreStrings, forKey: "offscript.preferredGenres")

        // Brief pause to show completion state
        try? await Task.sleep(for: .seconds(1.2))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isComplete = true
        }

        // Auto-advance after a beat — notify parent to set hasSeenOnboarding
        try? await Task.sleep(for: .seconds(1.5))
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

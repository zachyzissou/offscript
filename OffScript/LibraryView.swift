import OSLog
import SwiftData
import SwiftUI

private let libraryLogger = Logger(subsystem: "com.offscript", category: "Library")

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var podcasts: [Podcast]
    @Query(sort: [SortDescriptor(\Episode.pubDate, order: .reverse)]) private var episodes: [Episode]
    let onOpenSettings: () -> Void

    private let syncService = FeedSyncService()

    private var subscribedPodcasts: [Podcast] {
        podcasts
            .filter(\.isSubscribed)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var inProgressEpisodes: [Episode] {
        episodes
            .filter { $0.podcast.isSubscribed && $0.playedPosition > 0 && !$0.isPlayed }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
    }

    private var freshEpisodes: [Episode] {
        episodes
            .filter { $0.podcast.isSubscribed && !$0.isPlayed }
            .sorted { $0.pubDate > $1.pubDate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                LibraryHeader(
                    showCount: subscribedPodcasts.count,
                    unplayedCount: freshEpisodes.count,
                    inProgressCount: inProgressEpisodes.count
                )

                if subscribedPodcasts.isEmpty {
                    VStack(spacing: 20) {
                        ContentUnavailableView("Your library is empty", systemImage: "books.vertical", description: Text("Use Search to bring in shows, then OffScript will keep them fresh here."))

                        NavigationLink("Find Shows") {
                            SearchView()
                        }
                        .buttonStyle(PrimaryPillButtonStyle())
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                    .padding(.top, 24)
                } else {
                    if !inProgressEpisodes.isEmpty {
                        LibraryEpisodeRail(
                            title: "Continue Listening",
                            subtitle: "Pick up where you left off.",
                            episodes: Array(inProgressEpisodes.prefix(8)),
                            reasonProvider: { episode in
                                if let duration = episode.duration {
                                    return "\(EpisodeDurationFormatter.short(max(duration - episode.playedPosition, 0))) left"
                                }
                                return "In progress"
                            }
                        )
                    }

                    if !freshEpisodes.isEmpty {
                        LibraryEpisodeRail(
                            title: "Fresh Episodes",
                            subtitle: "Recent drops from the shows you already trust.",
                            episodes: Array(freshEpisodes.prefix(10)),
                            reasonProvider: { episode in
                                if let duration = episode.duration {
                                    return "Fresh • \(EpisodeDurationFormatter.short(duration))"
                                }
                                return "Fresh"
                            }
                        )
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        OffScriptSectionHeader(
                            title: "Shows",
                            subtitle: "Your subscribed collection."
                        )
                        .padding(.horizontal, OffScriptTheme.pagePadding)

                        LazyVStack(spacing: 14) {
                            ForEach(subscribedPodcasts) { podcast in
                                NavigationLink {
                                    PodcastDetailView(podcast: podcast)
                                } label: {
                                    PodcastShelfCard(
                                        podcast: podcast,
                                        unplayedCount: freshEpisodes.filter { $0.podcast.id == podcast.id }.count,
                                        inProgressCount: inProgressEpisodes.filter { $0.podcast.id == podcast.id }.count
                                    )
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, OffScriptTheme.pagePadding)
                            }
                        }
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 90)
        }
        .offscriptPageBackground()
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.offscriptBackgroundTop.opacity(0.98), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .refreshable { await syncSubscriptions() }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: onOpenSettings) {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Open settings")
                .accessibilityHint("Adjust playback and recommendation preferences")
            }
        }
    }

    @MainActor
    private func syncSubscriptions() async {
        for podcast in subscribedPodcasts {
            do {
                try await syncService.sync(podcast: podcast, in: modelContext)
            } catch {
                libraryLogger.error("Pull-to-refresh sync failed for '\(podcast.title, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

struct PodcastDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let podcast: Podcast
    @Query(sort: [SortDescriptor(\Episode.pubDate, order: .reverse)]) private var allEpisodes: [Episode]
    @State private var filter: EpisodeFilter = .all
    @State private var episodeSearchQuery = ""

    private var episodes: [Episode] {
        let filtered = allEpisodes
            .filter { $0.podcast.id == podcast.id }
            .filter { filter.matches($0) }

        if episodeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return filtered
        }

        let query = episodeSearchQuery.lowercased()
        return filtered.filter { episode in
            episode.title.lowercased().contains(query) ||
            (episode.summary?.lowercased().contains(query) ?? false)
        }
    }

    init(podcast: Podcast) {
        self.podcast = podcast
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                PodcastDetailHeader(podcast: podcast, episodeCount: episodes.count)

                FilterRow(selection: $filter)
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                if episodes.isEmpty {
                    ContentUnavailableView("Nothing here yet", systemImage: "waveform.badge.minus", description: Text(episodeSearchQuery.isEmpty ? "Change the filter or sync this feed again later." : "No episodes match \"\(episodeSearchQuery)\"."))
                        .padding(.horizontal, OffScriptTheme.pagePadding)
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(episodes) { episode in
                            PodcastEpisodeCard(episode: episode)
                                .padding(.horizontal, OffScriptTheme.pagePadding)
                        }
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 90)
        }
        .offscriptPageBackground()
        .navigationTitle(podcast.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $episodeSearchQuery, prompt: "Search episodes")
    }
}

private struct LibraryHeader: View {
    let showCount: Int
    let unplayedCount: Int
    let inProgressCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OffScriptUtilityHeader(
                eyebrow: "Library",
                title: "Your listening shelf",
                subtitle: "Shows, unfinished episodes, and fresh drops."
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 116), spacing: 10, alignment: .leading)],
                alignment: .leading,
                spacing: 10
            ) {
                LibraryStatPill(label: "Shows", value: "\(showCount)")
                LibraryStatPill(label: "Unplayed", value: "\(unplayedCount)")
                LibraryStatPill(label: "In Progress", value: "\(inProgressCount)")
            }
        }
        .padding(.horizontal, OffScriptTheme.pagePadding)
    }
}

private struct LibraryStatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.offscriptTextPrimary)
            Text(label.uppercased())
                .font(.offscriptMicro.weight(.semibold))
                .foregroundStyle(Color.offscriptTextMuted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .offscriptUtilitySurface(radius: OffScriptTheme.Radius.small)
    }
}

private struct LibraryEpisodeRail: View {
    let title: String
    let subtitle: String
    let episodes: [Episode]
    let reasonProvider: (Episode) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OffScriptSectionHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, OffScriptTheme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(episodes) { episode in
                        LibraryEpisodeCard(episode: episode, reason: reasonProvider(episode))
                    }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)
            }
        }
    }
}

private struct LibraryEpisodeCard: View {
    @Environment(\.modelContext) private var modelContext
    let episode: Episode
    let reason: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.offscriptCardRaised, Color.offscriptCardUtility],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 12) {
                NavigationLink {
                    EpisodeDetailView(episode: episode)
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        OffScriptArtworkView(
                            url: episode.artworkURL ?? episode.podcast.artworkURL,
                            cornerRadius: 18
                        )
                        .frame(width: 90, height: 90)

                        VStack(alignment: .leading, spacing: 8) {
                            OffScriptReasonBadge(text: reason)

                            Text(episode.title)
                                .font(.offscriptCardTitle)
                                .foregroundStyle(Color.offscriptTextPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Text(episode.podcast.title)
                                .font(.offscriptBody)
                                .foregroundStyle(Color.offscriptTextSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Button("Play") {
                        PlaybackController.shared.play(episode, in: modelContext)
                    }
                    .buttonStyle(PrimaryPillButtonStyle())

                    Button(episode.isQueued ? "Queued" : "Queue") {
                        do { try QueueService.add(episode, in: modelContext) } catch { libraryLogger.error("Failed to add episode to queue: \(error.localizedDescription, privacy: .public)") }
                    }
                    .buttonStyle(SecondaryPillButtonStyle())
                    .disabled(episode.isQueued)
                }
            }
            .padding(16)
        }
        .frame(width: 286, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                .stroke(Color.offscriptHairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 12, y: 6)
    }
}

private struct PodcastShelfCard: View {
    let podcast: Podcast
    let unplayedCount: Int
    let inProgressCount: Int

    var body: some View {
        HStack(spacing: 16) {
            OffScriptArtworkView(url: podcast.artworkURL)
                .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 8) {
                Text(podcast.title)
                    .font(.offscriptCardTitle)
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .lineLimit(2)

                if let author = podcast.author {
                    Text(author)
                        .font(.offscriptBody)
                        .foregroundStyle(Color.offscriptTextSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if inProgressCount > 0 {
                        OffScriptReasonBadge(text: "\(inProgressCount) in progress")
                    }
                    OffScriptReasonBadge(text: "\(unplayedCount) unplayed")
                }

                if let latestPubDate = podcast.latestPubDate {
                    Text("Updated \(latestPubDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.offscriptMeta)
                        .foregroundStyle(Color.offscriptTextMuted)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.offscriptTextMuted)
        }
        .padding(18)
        .offscriptSurface()
    }
}

private struct PodcastDetailHeader: View {
    @Environment(\.modelContext) private var modelContext
    let podcast: Podcast
    let episodeCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                OffScriptArtworkView(url: podcast.artworkURL, cornerRadius: OffScriptTheme.Radius.large)
                    .frame(width: 122, height: 122)

                VStack(alignment: .leading, spacing: 10) {
                    Text(podcast.title)
                        .font(.offscriptDisplay)
                        .foregroundStyle(Color.offscriptTextPrimary)

                    if let author = podcast.author {
                        Text(author)
                            .font(.headline)
                            .foregroundStyle(Color.offscriptTextSecondary)
                    }

                    HStack(spacing: 8) {
                        OffScriptReasonBadge(text: "\(episodeCount) episodes")
                        if podcast.isSubscribed {
                            OffScriptReasonBadge(text: "Subscribed")
                        }
                    }
                }
            }

            if let summary = podcast.summary {
                Text(summary)
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextSecondary)
            }

            if podcast.isSubscribed {
                Button("Unsubscribe") {
                    withAnimation {
                        podcast.isSubscribed = false
                        do { try modelContext.save() } catch { libraryLogger.error("Failed to save unsubscribe: \(error.localizedDescription, privacy: .public)") }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.red.opacity(0.85))
            }
        }
        .padding(.horizontal, OffScriptTheme.pagePadding)
    }
}

private struct PodcastEpisodeCard: View {
    @Environment(\.modelContext) private var modelContext
    let episode: Episode

    private var progressValue: Double {
        guard let duration = episode.duration, duration > 0 else { return 0 }
        return episode.playedPosition / duration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink {
                EpisodeDetailView(episode: episode)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(episode.title)
                        .font(.headline)
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .multilineTextAlignment(.leading)

                    Text(metadata)
                        .font(.offscriptMeta)
                        .foregroundStyle(Color.offscriptTextMuted)

                    if let summary = episode.summary {
                        Text(summary)
                            .font(.offscriptBody)
                            .foregroundStyle(Color.offscriptTextSecondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if progressValue > 0 {
                OffScriptProgressBar(value: progressValue, height: 5)
            }

            HStack(spacing: 10) {
                Button("Play") {
                    PlaybackController.shared.play(episode, in: modelContext)
                }
                .buttonStyle(PrimaryPillButtonStyle())

                Button(episode.isQueued ? "Queued" : "Queue") {
                    do { try QueueService.add(episode, in: modelContext) } catch { libraryLogger.error("Failed to add episode to queue: \(error.localizedDescription, privacy: .public)") }
                }
                .buttonStyle(SecondaryPillButtonStyle())
                .disabled(episode.isQueued)
            }
        }
        .padding(18)
        .offscriptSurface()
    }

    private var metadata: String {
        let date = episode.pubDate.formatted(date: .abbreviated, time: .omitted)
        if let duration = episode.duration {
            return "\(date) • \(EpisodeDurationFormatter.short(duration))"
        }
        return date
    }
}

private struct FilterRow: View {
    @Binding var selection: EpisodeFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(EpisodeFilter.allCases) { filter in
                    Button(filter.title) {
                        withAnimation { selection = filter }
                    }
                    .buttonStyle(FilterChipStyle(isSelected: selection == filter))
                    .accessibilityAddTraits(selection == filter ? .isSelected : [])
                }
            }
        }
    }
}

private struct FilterChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? Color.black : Color.offscriptTextPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color.offscriptAccent : Color.white.opacity(configuration.isPressed ? 0.12 : 0.08))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.offscriptHairline, lineWidth: 1)
            )
    }
}

private enum EpisodeFilter: String, CaseIterable, Identifiable {
    case all
    case unplayed
    case inProgress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .unplayed: return "Unplayed"
        case .inProgress: return "In Progress"
        }
    }

    func matches(_ episode: Episode) -> Bool {
        switch self {
        case .all:
            return true
        case .unplayed:
            return !episode.isPlayed
        case .inProgress:
            return episode.playedPosition > 0 && !episode.isPlayed
        }
    }
}

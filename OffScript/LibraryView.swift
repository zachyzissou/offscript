import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var podcasts: [Podcast]
    // Scope to subscribed podcasts at the database level to avoid loading all episodes
    @Query(
        filter: #Predicate<Episode> { $0.podcast.isSubscribed == true },
        sort: [SortDescriptor(\Episode.pubDate, order: .reverse)]
    ) private var episodes: [Episode]
    @State private var showDownloadedOnly = AppSettings.libraryShowDownloadedOnly
    @State private var sortMode = AppSettings.LibrarySortMode.newest
    @State private var syncError: String?
    let onOpenSettings: () -> Void

    private var subscribedPodcasts: [Podcast] {
        podcasts
            .filter(\.isSubscribed)
            .sorted(by: comparePodcasts)
    }

    private var inProgressEpisodes: [Episode] {
        episodes
            .filter { $0.playedPosition > 0 && !$0.isPlayed }
            .filter { !showDownloadedOnly || $0.downloadState == .downloaded }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
    }

    private var freshEpisodes: [Episode] {
        episodes
            .filter { !$0.isPlayed }
            .filter { !showDownloadedOnly || $0.downloadState == .downloaded }
            .sorted { $0.pubDate > $1.pubDate }
    }

    private var downloadedEpisodes: [Episode] {
        episodes
            .filter { $0.downloadState == .downloaded }
            .sorted { ($0.downloadCompletedAt ?? .distantPast) > ($1.downloadCompletedAt ?? .distantPast) }
    }

    private var downloadActivityEpisodes: [Episode] {
        episodes
            .filter { $0.downloadState == .queued || $0.downloadState == .downloading || $0.downloadState == .failed }
            .sorted { lhs, rhs in
                let lhsDate = lhs.downloadRequestedAt ?? lhs.pubDate
                let rhsDate = rhs.downloadRequestedAt ?? rhs.pubDate
                return lhsDate > rhsDate
            }
    }

    /// Pre-computed podcast-to-count dictionaries so the ForEach below is O(1) per row
    /// instead of O(podcasts * episodes).
    private var unplayedCountByPodcast: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for episode in freshEpisodes {
            counts[episode.podcast.id, default: 0] += 1
        }
        return counts
    }

    private var inProgressCountByPodcast: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for episode in inProgressEpisodes {
            counts[episode.podcast.id, default: 0] += 1
        }
        return counts
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                LibraryHeader(
                    showCount: subscribedPodcasts.count,
                    unplayedCount: freshEpisodes.count,
                    inProgressCount: inProgressEpisodes.count,
                    downloadedCount: downloadedEpisodes.count,
                    showDownloadedOnly: showDownloadedOnly
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

                    if !downloadActivityEpisodes.isEmpty {
                        LibraryDownloadActivitySection(episodes: downloadActivityEpisodes)
                    }

                    if !downloadedEpisodes.isEmpty {
                        LibraryEpisodeRail(
                            title: "Downloaded",
                            subtitle: "Ready when the signal drops.",
                            episodes: Array(downloadedEpisodes.prefix(10)),
                            reasonProvider: { episode in
                                if let duration = episode.duration {
                                    return "Offline • \(EpisodeDurationFormatter.short(duration))"
                                }
                                return "Offline"
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
                                        unplayedCount: unplayedCountByPodcast[podcast.id] ?? 0,
                                        inProgressCount: inProgressCountByPodcast[podcast.id] ?? 0
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
            .padding(.bottom, 0)
        }
        .offscriptPageBackground()
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.offscriptBackgroundTop.opacity(0.98), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .refreshable { await syncSubscriptions() }
        .overlay(alignment: .top) {
            if let syncError {
                Text(syncError)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.offscriptDestructive.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: syncError != nil)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: onOpenSettings) {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Open settings")
                .accessibilityHint("Adjust playback and recommendation preferences")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Downloaded only", isOn: $showDownloadedOnly)

                    Picker("Sort library", selection: $sortMode) {
                        Text("Newest").tag(AppSettings.LibrarySortMode.newest)
                        Text("Oldest").tag(AppSettings.LibrarySortMode.oldest)
                        Text("Recently Played").tag(AppSettings.LibrarySortMode.recentlyPlayed)
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter library")
            }
        }
        .task {
            sortMode = AppSettings.librarySortMode
        }
        .onChange(of: showDownloadedOnly) { _, newValue in
            AppSettings.libraryShowDownloadedOnly = newValue
        }
        .onChange(of: sortMode) { _, newValue in
            AppSettings.librarySortMode = newValue
        }
    }

    @MainActor
    private func syncSubscriptions() async {
        syncError = nil
        await SyncCoordinator.shared.refreshSubscriptions(subscribedPodcasts, force: true)

        // Check for any sync failures after refresh completes
        let failedPodcasts = subscribedPodcasts.filter { $0.syncStatus == "failed" }
        if !failedPodcasts.isEmpty {
            let names = failedPodcasts.prefix(2).map(\.title).joined(separator: ", ")
            let suffix = failedPodcasts.count > 2 ? " and \(failedPodcasts.count - 2) more" : ""
            syncError = "Sync failed for \(names)\(suffix)"

            Task {
                try? await Task.sleep(for: .seconds(3))
                syncError = nil
            }
        }
    }

    private func comparePodcasts(_ lhs: Podcast, _ rhs: Podcast) -> Bool {
        switch sortMode {
        case .newest:
            return (lhs.latestPubDate ?? .distantPast) > (rhs.latestPubDate ?? .distantPast)
        case .oldest:
            return (lhs.latestPubDate ?? .distantFuture) < (rhs.latestPubDate ?? .distantFuture)
        case .recentlyPlayed:
            return lastPlayedDate(for: lhs) > lastPlayedDate(for: rhs)
        }
    }

    private func lastPlayedDate(for podcast: Podcast) -> Date {
        episodes
            .filter { $0.podcast.id == podcast.id }
            .compactMap(\.lastPlayedAt)
            .max() ?? .distantPast
    }
}

struct PodcastDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let podcast: Podcast
    @Query private var podcastEpisodes: [Episode]
    @State private var filter: EpisodeFilter = .all
    @State private var episodeSearchQuery = ""

    private var episodes: [Episode] {
        let filtered = podcastEpisodes
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

    private var latestUnplayedEpisode: Episode? {
        podcastEpisodes
            .filter { !$0.isPlayed }
            .sorted { $0.pubDate > $1.pubDate }
            .first
    }

    init(podcast: Podcast) {
        self.podcast = podcast
        // Scope the @Query to only episodes belonging to this podcast
        // instead of fetching ALL episodes and filtering in memory.
        let podcastModelID = podcast.persistentModelID
        _podcastEpisodes = Query(
            filter: #Predicate<Episode> { $0.podcast.persistentModelID == podcastModelID },
            sort: [SortDescriptor(\Episode.pubDate, order: .reverse)]
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                PodcastDetailHeader(podcast: podcast, episodeCount: episodes.count)

                if let latest = latestUnplayedEpisode {
                    HStack(spacing: 10) {
                        Button(latest.playedPosition > 0 ? "Resume Latest" : "Play Latest") {
                            PlaybackController.shared.play(latest, in: modelContext)
                        }
                        .buttonStyle(PrimaryPillButtonStyle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(latest.title)
                                .font(.offscriptMeta)
                                .foregroundStyle(Color.offscriptTextSecondary)
                                .lineLimit(1)
                            if let duration = latest.duration {
                                let timeLabel = latest.playedPosition > 0
                                    ? "\(EpisodeDurationFormatter.short(max(0, duration - latest.playedPosition))) left"
                                    : EpisodeDurationFormatter.short(duration)
                                Text(timeLabel)
                                    .font(.offscriptMicro)
                                    .foregroundStyle(Color.offscriptTextMuted)
                            }
                        }
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                }

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
            .padding(.bottom, 0)
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
    let downloadedCount: Int
    let showDownloadedOnly: Bool

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
                LibraryStatPill(label: "Downloads", value: "\(downloadedCount)")
            }

            if showDownloadedOnly {
                OffScriptReasonBadge(text: "Downloaded only")
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
    @ObservedObject private var downloadService = DownloadService.shared
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

                            if let downloadStatus = downloadService.statusText(for: episode) {
                                Text(downloadStatus)
                                    .font(.offscriptMeta)
                                    .foregroundStyle(episode.downloadState == .failed ? Color.offscriptDestructive : Color.offscriptTextMuted)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)

                if episode.playedPosition > 0, let duration = episode.duration, duration > 0 {
                    OffScriptProgressBar(value: episode.playedPosition / duration, height: 4)
                }

                HStack(spacing: 10) {
                    Button(episode.playedPosition > 0 ? "Resume" : "Play") {
                        PlaybackController.shared.play(episode, in: modelContext)
                    }
                    .buttonStyle(PrimaryPillButtonStyle())

                    Button(episode.isQueued ? "Queued" : "Queue") {
                        try? QueueService.add(episode, in: modelContext)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(episode.title), \(episode.podcast.title), \(reason)")
    }
}

private struct LibraryDownloadActivitySection: View {
    let episodes: [Episode]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OffScriptSectionHeader(
                title: "Download Activity",
                subtitle: "Watch offline saves finish, or retry anything that got interrupted."
            )
            .padding(.horizontal, OffScriptTheme.pagePadding)

            LazyVStack(spacing: 12) {
                ForEach(episodes) { episode in
                    LibraryDownloadStatusCard(episode: episode)
                        .padding(.horizontal, OffScriptTheme.pagePadding)
                }
            }
        }
    }
}

private struct LibraryDownloadStatusCard: View {
    @ObservedObject private var downloadService = DownloadService.shared
    let episode: Episode

    var body: some View {
        HStack(spacing: 14) {
            OffScriptArtworkView(url: episode.artworkURL ?? episode.podcast.artworkURL, cornerRadius: OffScriptTheme.Radius.small)
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    OffScriptReasonBadge(text: stateLabel)

                    if let duration = episode.duration {
                        Text(EpisodeDurationFormatter.short(duration))
                            .font(.offscriptMeta)
                            .foregroundStyle(Color.offscriptTextMuted)
                    }
                }

                Text(episode.title)
                    .font(.headline)
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .lineLimit(2)

                Text(downloadService.statusText(for: episode) ?? "Offline status unknown")
                    .font(.offscriptMeta)
                    .foregroundStyle(episode.downloadState == .failed ? Color.offscriptDestructive : Color.offscriptTextSecondary)
                    .lineLimit(2)
            }

            Spacer()

            DownloadButton(episode: episode)
        }
        .padding(16)
        .offscriptUtilitySurface()
    }

    private var stateLabel: String {
        switch episode.downloadState {
        case .queued:
            return "Queued"
        case .downloading:
            return "Downloading"
        case .failed:
            return "Needs Retry"
        case .downloaded:
            return "Offline"
        case .notDownloaded:
            return "Not Saved"
        }
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
                    if podcast.syncStatus == "failed" {
                        OffScriptReasonBadge(text: "Sync issue")
                    }
                }

                if let latestPubDate = podcast.latestPubDate {
                    Text("Updated \(latestPubDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.offscriptMeta)
                        .foregroundStyle(Color.offscriptTextMuted)
                }

                if let syncErrorMessage = podcast.syncErrorMessage, podcast.syncStatus == "failed" {
                    Text(syncErrorMessage)
                        .font(.offscriptMeta)
                        .foregroundStyle(Color.offscriptDestructive)
                        .lineLimit(2)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.offscriptTextMuted)
        }
        .padding(18)
        .offscriptSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(podcast.title)\(podcast.author.map { ", by \($0)" } ?? ""), \(unplayedCount) unplayed")
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
                    .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 8) {
                    if let author = podcast.author {
                        Text(author)
                            .font(.offscriptMeta)
                            .foregroundStyle(Color.offscriptTextMuted)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        OffScriptReasonBadge(text: "\(episodeCount) episodes")
                        if podcast.isSubscribed {
                            OffScriptReasonBadge(text: "Subscribed")
                        }
                    }
                }
            }

            Text(podcast.title)
                .font(.offscriptDisplay)
                .foregroundStyle(Color.offscriptTextPrimary)
                .lineLimit(3)

            if let summary = podcast.summary {
                Text(summary.strippingHTML)
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextSecondary)
                    .lineLimit(4)
            }

            if podcast.isSubscribed {
                Button("Unsubscribe") {
                    withAnimation {
                        podcast.isSubscribed = false
                        try? modelContext.save()
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
    @ObservedObject private var downloadService = DownloadService.shared
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
                        Text(summary.strippingHTML)
                            .font(.offscriptBody)
                            .foregroundStyle(Color.offscriptTextSecondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }

                    if let downloadStatus = downloadService.statusText(for: episode) {
                        Text(downloadStatus)
                            .font(.offscriptMeta)
                            .foregroundStyle(episode.downloadState == .failed ? Color.offscriptDestructive : Color.offscriptTextMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if progressValue > 0 {
                OffScriptProgressBar(value: progressValue, height: 5)
            }

            HStack(spacing: 10) {
                Button(episode.playedPosition > 0 ? "Resume" : "Play") {
                    PlaybackController.shared.play(episode, in: modelContext)
                }
                .buttonStyle(PrimaryPillButtonStyle())

                Button(episode.isQueued ? "Queued" : "Queue") {
                    try? QueueService.add(episode, in: modelContext)
                }
                .buttonStyle(SecondaryPillButtonStyle())
                .disabled(episode.isQueued)

                DownloadButton(episode: episode)
            }
        }
        .padding(18)
        .offscriptSurface()
    }

    private var metadata: String {
        let date = episode.pubDate.formatted(date: .abbreviated, time: .omitted)
        if episode.playedPosition > 0, let duration = episode.duration {
            let remaining = max(0, duration - episode.playedPosition)
            return "\(date) • \(EpisodeDurationFormatter.short(remaining)) left"
        }
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

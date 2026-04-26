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
    @State private var focusFilter: LibraryFocusFilter = .all
    @State private var librarySearch = ""
    @State private var librarySearchMatches: [Episode] = []
    // Derived state — populated in `recomputeDerived()`. Computing these in
    // `var body` forced an O(n) scan over every @Query refresh × every render,
    // which became the main launch hitch at 500+ podcasts / 100k episodes.
    @State private var subscribedPodcasts: [Podcast] = []
    @State private var inProgressEpisodes: [Episode] = []
    @State private var freshEpisodes: [Episode] = []
    @State private var downloadedEpisodes: [Episode] = []
    @State private var downloadActivityEpisodes: [Episode] = []
    @State private var unplayedCountByPodcast: [UUID: Int] = [:]
    @State private var inProgressCountByPodcast: [UUID: Int] = [:]
    let onOpenSettings: () -> Void

    enum LibraryFocusFilter: String, CaseIterable, Identifiable {
        case all, fresh, inProgress, downloads
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .fresh: return "Fresh"
            case .inProgress: return "In Progress"
            case .downloads: return "Downloads"
            }
        }
        var systemImage: String {
            switch self {
            case .all: return "circle.grid.2x2.fill"
            case .fresh: return "sparkles"
            case .inProgress: return "play.circle.fill"
            case .downloads: return "arrow.down.circle.fill"
            }
        }
    }

    /// Single pass over `episodes` + `podcasts`, called from `.task` and from
    /// `onChange` of the inputs. Replaces six body-time computed properties
    /// that each scanned the full episode list every render.
    private func recomputeDerived() {
        // Pre-bucket episodes by podcast.id once. The library sort below uses
        // this for O(1) lookups instead of filtering the full episode array
        // inside the comparator (previously O(n²) when sorting by recently
        // played).
        var episodesByPodcast: [UUID: [Episode]] = [:]
        var lastPlayedByPodcast: [UUID: Date] = [:]
        var inProgress: [Episode] = []
        var fresh: [Episode] = []
        var downloaded: [Episode] = []
        var downloadActivity: [Episode] = []
        var unplayedCounts: [UUID: Int] = [:]
        var inProgressCounts: [UUID: Int] = [:]

        for episode in episodes {
            let podcastID = episode.podcast.id
            episodesByPodcast[podcastID, default: []].append(episode)

            if let played = episode.lastPlayedAt {
                if played > (lastPlayedByPodcast[podcastID] ?? .distantPast) {
                    lastPlayedByPodcast[podcastID] = played
                }
            }

            let passesDownloadFilter = !showDownloadedOnly || episode.downloadState == .downloaded

            if !episode.isPlayed && passesDownloadFilter {
                fresh.append(episode)
                unplayedCounts[podcastID, default: 0] += 1
            }

            if episode.playedPosition > 0 && !episode.isPlayed && passesDownloadFilter {
                inProgress.append(episode)
                inProgressCounts[podcastID, default: 0] += 1
            }

            switch episode.downloadState {
            case .downloaded:
                downloaded.append(episode)
            case .queued, .downloading, .failed:
                downloadActivity.append(episode)
            case .notDownloaded:
                break
            }
        }

        // Sorts are over already-filtered subsets, not the whole episode list.
        inProgress.sort { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        fresh.sort { $0.pubDate > $1.pubDate }
        downloaded.sort { ($0.downloadCompletedAt ?? .distantPast) > ($1.downloadCompletedAt ?? .distantPast) }
        downloadActivity.sort { lhs, rhs in
            let lhsDate = lhs.downloadRequestedAt ?? lhs.pubDate
            let rhsDate = rhs.downloadRequestedAt ?? rhs.pubDate
            return lhsDate > rhsDate
        }

        let subscribed = podcasts.filter(\.isSubscribed)
        let sorted = subscribed.sorted { lhs, rhs in
            switch sortMode {
            case .newest:
                return (lhs.latestPubDate ?? .distantPast) > (rhs.latestPubDate ?? .distantPast)
            case .oldest:
                return (lhs.latestPubDate ?? .distantFuture) < (rhs.latestPubDate ?? .distantFuture)
            case .recentlyPlayed:
                let l = lastPlayedByPodcast[lhs.id] ?? .distantPast
                let r = lastPlayedByPodcast[rhs.id] ?? .distantPast
                return l > r
            }
        }

        self.subscribedPodcasts = sorted
        self.inProgressEpisodes = inProgress
        self.freshEpisodes = fresh
        self.downloadedEpisodes = downloaded
        self.downloadActivityEpisodes = downloadActivity
        self.unplayedCountByPodcast = unplayedCounts
        self.inProgressCountByPodcast = inProgressCounts
    }

    /// Recompute the search matches from the episodes list. Called from
    /// onChange of the search query — not from `var body`. Computing in body
    /// turns each keystroke into an O(n) scan plus per-render redundant work.
    private func refreshLibrarySearchMatches() {
        let q = librarySearch.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            librarySearchMatches = []
            return
        }
        var collected: [Episode] = []
        for episode in episodes {
            if collected.count >= 40 { break }
            if episode.title.lowercased().contains(q) {
                collected.append(episode); continue
            }
            if let summary = episode.summary?.lowercased(), summary.contains(q) {
                collected.append(episode); continue
            }
            if episode.podcast.title.lowercased().contains(q) {
                collected.append(episode)
            }
        }
        librarySearchMatches = collected
    }

    @ViewBuilder
    private var librarySearchResults: some View {
        let matches = librarySearchMatches
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Matches")
                    .font(.offscriptSectionTitle)
                    .foregroundStyle(Color.offscriptTextPrimary)
                Spacer()
                Text("\(matches.count)")
                    .font(.offscriptMicro.weight(.semibold))
                    .foregroundStyle(Color.offscriptAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.offscriptAccentSoft, in: Capsule())
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)

            if matches.isEmpty {
                Text("No episodes in your library mention \"\(librarySearch)\".")
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextMuted)
                    .padding(.horizontal, OffScriptTheme.pagePadding)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(matches) { episode in
                        EpisodeCompactCard(episode: episode)
                            .padding(.horizontal, OffScriptTheme.pagePadding)
                    }
                }
            }
        }
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

                LibraryFocusChips(selection: $focusFilter)
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                LibrarySearchField(query: $librarySearch)
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                if !librarySearch.trimmingCharacters(in: .whitespaces).isEmpty {
                    librarySearchResults
                }

                if subscribedPodcasts.isEmpty {
                    emptyLibraryState
                } else {
                    librarySectionsForCurrentFilter
                    shelfSection
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
        .onChange(of: librarySearch) { _, _ in
            refreshLibrarySearchMatches()
        }
        .onChange(of: episodes) { _, _ in
            // If the underlying library changes while a search is active,
            // re-run the filter so the matches list stays in sync.
            if !librarySearch.trimmingCharacters(in: .whitespaces).isEmpty {
                refreshLibrarySearchMatches()
            }
        }
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
            recomputeDerived()
        }
        .onChange(of: episodes) { _, _ in recomputeDerived() }
        .onChange(of: podcasts) { _, _ in recomputeDerived() }
        .onChange(of: showDownloadedOnly) { _, newValue in
            AppSettings.libraryShowDownloadedOnly = newValue
            recomputeDerived()
        }
        .onChange(of: sortMode) { _, newValue in
            AppSettings.librarySortMode = newValue
            recomputeDerived()
        }
    }

    // MARK: - Body subviews
    // Splitting the body into named computed views keeps the SwiftUI
    // type-checker under its complexity budget — the original chained
    // if/else over four filter modes ran out of solver budget after the
    // @State refactor.

    @ViewBuilder
    private var emptyLibraryState: some View {
        VStack(spacing: 20) {
            ContentUnavailableView(
                "Your library is empty",
                systemImage: "books.vertical",
                description: Text("Use Search to bring in shows, then OffScript will keep them fresh here.")
            )
            NavigationLink("Find Shows") { SearchView() }
                .buttonStyle(PrimaryPillButtonStyle())
        }
        .padding(.horizontal, OffScriptTheme.pagePadding)
        .padding(.top, 24)
    }

    @ViewBuilder
    private var librarySectionsForCurrentFilter: some View {
        if focusFilter == .all || focusFilter == .inProgress, !inProgressEpisodes.isEmpty {
            inProgressRail
        }
        if focusFilter == .all || focusFilter == .fresh, !freshEpisodes.isEmpty {
            freshRail
        }
        if focusFilter == .all || focusFilter == .downloads {
            downloadsSections
        }
    }

    private var inProgressLimit: Int { focusFilter == .inProgress ? 30 : 8 }
    private var freshLimit: Int { focusFilter == .fresh ? 30 : 10 }
    private var downloadsLimit: Int { focusFilter == .downloads ? 30 : 10 }

    private var inProgressRail: some View {
        LibraryEpisodeRail(
            title: "Continue Listening",
            subtitle: "Pick up where you left off.",
            episodes: Array(inProgressEpisodes.prefix(inProgressLimit)),
            reasonProvider: inProgressReason
        )
    }

    private var freshRail: some View {
        LibraryEpisodeRail(
            title: "Fresh Episodes",
            subtitle: "Recent drops from the shows you already trust.",
            episodes: Array(freshEpisodes.prefix(freshLimit)),
            reasonProvider: freshReason
        )
    }

    @ViewBuilder
    private var downloadsSections: some View {
        if !downloadActivityEpisodes.isEmpty {
            LibraryDownloadActivitySection(episodes: downloadActivityEpisodes)
        }
        if !downloadedEpisodes.isEmpty {
            LibraryEpisodeRail(
                title: "Downloaded",
                subtitle: "Ready when the signal drops.",
                episodes: Array(downloadedEpisodes.prefix(downloadsLimit)),
                reasonProvider: downloadedReason
            )
        }
        if focusFilter == .downloads, downloadedEpisodes.isEmpty, downloadActivityEpisodes.isEmpty {
            OffScriptEmptyState(
                icon: "arrow.down.circle",
                headline: "Nothing downloaded yet",
                message: "Tap the download icon on any episode to keep it offline.",
                generatedCopyKey: "library.downloads.empty",
                generatedCopyPrompt: "Surface: empty Downloads filter on a podcast app's Library tab. Write a two-sentence prompt to download something for offline listening."
            )
            .padding(.horizontal, OffScriptTheme.pagePadding)
        }
    }

    private func inProgressReason(_ episode: Episode) -> String {
        if let duration = episode.duration {
            let remaining = max(duration - episode.playedPosition, 0)
            return "\(EpisodeDurationFormatter.short(remaining)) left"
        }
        return "In progress"
    }

    private func freshReason(_ episode: Episode) -> String {
        if let duration = episode.duration {
            return "Fresh • \(EpisodeDurationFormatter.short(duration))"
        }
        return "Fresh"
    }

    private func downloadedReason(_ episode: Episode) -> String {
        if let duration = episode.duration {
            return "Offline • \(EpisodeDurationFormatter.short(duration))"
        }
        return "Offline"
    }

    private var shelfSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            OffScriptSectionHeader(
                title: "Shows",
                subtitle: "Your subscribed collection."
            )
            .padding(.horizontal, OffScriptTheme.pagePadding)

            LazyVStack(spacing: 14) {
                ForEach(subscribedPodcasts) { podcast in
                    shelfRow(for: podcast)
                }
            }
        }
    }

    private func shelfRow(for podcast: Podcast) -> some View {
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
        .contextMenu { shelfContextMenu(for: podcast) }
    }

    @ViewBuilder
    private func shelfContextMenu(for podcast: Podcast) -> some View {
        Button { markAllPlayed(podcast) } label: {
            Label("Mark all played", systemImage: "checkmark.circle")
        }
        Button { Task { await syncSingle(podcast) } } label: {
            Label("Refresh feed", systemImage: "arrow.clockwise")
        }
        ShareLink(item: podcast.feedURL) {
            Label("Share feed URL", systemImage: "square.and.arrow.up")
        }
        Divider()
        Button(role: .destructive) { unsubscribe(podcast) } label: {
            Label("Unsubscribe", systemImage: "xmark.bin")
        }
    }

    @MainActor
    private func markAllPlayed(_ podcast: Podcast) {
        let podcastID = podcast.id
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.podcast.id == podcastID && $0.isPlayed == false }
        )
        let unplayed = (try? modelContext.fetch(descriptor)) ?? []
        for episode in unplayed {
            episode.isPlayed = true
            episode.playedPosition = episode.duration ?? episode.playedPosition
        }
        try? modelContext.save()
        TelemetryService.track(
            "podcast_marked_all_played",
            metadata: ["podcast": podcast.title, "count": "\(unplayed.count)"],
            in: modelContext
        )
    }

    @MainActor
    private func syncSingle(_ podcast: Podcast) async {
        await SyncCoordinator.shared.refreshSubscriptions([podcast], force: true)
    }

    @MainActor
    private func unsubscribe(_ podcast: Podcast) {
        podcast.isSubscribed = false
        try? modelContext.save()
        TelemetryService.track(
            "podcast_unsubscribed",
            metadata: ["podcast": podcast.title],
            in: modelContext
        )
        OffScriptNotifications.shared.cancelPendingNotifications(forPodcastID: podcast.id, in: modelContext)
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

}

struct PodcastDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let podcast: Podcast
    @Query private var podcastEpisodes: [Episode]
    @State private var filter: EpisodeFilter = .all
    @State private var episodeSearchQuery = ""
    @State private var showPreferences = false

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
        // Scope the @Query to only episodes belonging to this podcast.
        // Use the stable UUID instead of persistentModelID, which SwiftData
        // cannot always translate into a reliable SQLite predicate.
        let podcastID = podcast.id
        _podcastEpisodes = Query(
            filter: #Predicate<Episode> { $0.podcast.id == podcastID },
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
                            EpisodeCompactCard(
                                episode: episode,
                                showPodcastTitle: false
                            )
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showPreferences = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Show preferences")
            }
        }
        .sheet(isPresented: $showPreferences) {
            PodcastPreferencesSheet(podcast: podcast)
                .presentationDetents([.medium, .large])
        }
    }
}

struct PodcastPreferencesSheet: View {
    let podcast: Podcast
    @Environment(\.dismiss) private var dismiss

    @State private var introSeconds: Double = 0
    @State private var outroSeconds: Double = 0
    @State private var rateOverride: Double = 0  // 0 = none
    @State private var notify: Bool = false

    var body: some View {
        navigationContent
            .onAppear { load() }
            .modifier(PodcastPreferencesPersister(
                podcastID: podcast.id,
                introSeconds: introSeconds,
                outroSeconds: outroSeconds,
                rateOverride: rateOverride,
                notify: notify
            ))
    }

    private var navigationContent: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.vertical, 16)
            }
            .offscriptPageBackground()
            .navigationTitle("Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .tint(Color.offscriptAccent)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
            OffScriptUtilityHeader(
                eyebrow: podcast.title.uppercased(),
                title: "Show preferences",
                subtitle: "Tune how OffScript handles episodes from this show — without changing your defaults."
            )
            .padding(.horizontal, OffScriptTheme.pagePadding)

            introCard
                .padding(.horizontal, OffScriptTheme.pagePadding)

            outroCard
                .padding(.horizontal, OffScriptTheme.pagePadding)

            rateCard
                .padding(.horizontal, OffScriptTheme.pagePadding)

            notifyCard
                .padding(.horizontal, OffScriptTheme.pagePadding)

            Spacer(minLength: 32)
        }
    }

    private var introCard: some View {
        let detail: String = introSeconds == 0
            ? "Off — start from the very beginning."
            : "Skip the first \(Int(introSeconds))s of every new episode."
        return sliderCard(title: "Skip intro", detail: detail, value: $introSeconds, range: 0...120, step: 5, unit: "s")
    }

    private var outroCard: some View {
        let detail: String = outroSeconds == 0
            ? "Off — play to the end."
            : "Treat the last \(Int(outroSeconds))s as outro and surface what's next early."
        return sliderCard(title: "Skip outro", detail: detail, value: $outroSeconds, range: 0...180, step: 5, unit: "s")
    }

    private func load() {
        introSeconds = Double(PodcastPreferences.skipIntroSeconds(for: podcast.id))
        outroSeconds = Double(PodcastPreferences.skipOutroSeconds(for: podcast.id))
        rateOverride = Double(PodcastPreferences.playbackRate(for: podcast.id) ?? 0)
        notify = PodcastPreferences.notificationsEnabled(for: podcast.id)
    }

    private func sliderCard(title: String, detail: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.offscriptCardTitle)
                    .foregroundStyle(Color.offscriptTextPrimary)
                Spacer()
                Text("\(Int(value.wrappedValue))\(unit)")
                    .font(.system(.subheadline, design: .monospaced).monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.offscriptAccent)
            }
            Text(detail)
                .font(.offscriptMeta)
                .foregroundStyle(Color.offscriptTextMuted)
            Slider(value: value, in: range, step: step) {
                Text(title)
            }
            .tint(Color.offscriptAccent)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offscriptUtilitySurface()
    }

    private var rateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            rateCardHeader
            Text("Lock a specific speed for this show, regardless of your global setting.")
                .font(.offscriptMeta)
                .foregroundStyle(Color.offscriptTextMuted)
            rateChips
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offscriptUtilitySurface()
    }

    private var rateCardHeader: some View {
        HStack {
            Text("Playback speed override")
                .font(.offscriptCardTitle)
                .foregroundStyle(Color.offscriptTextPrimary)
            Spacer()
            Text(rateOverride == 0 ? "Default" : String(format: "%.2gx", rateOverride))
                .font(.system(.subheadline, design: .monospaced).monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.offscriptAccent)
        }
    }

    private var rateChips: some View {
        HStack(spacing: 8) {
            ForEach([0.0, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                rateChip(for: rate)
            }
        }
    }

    private func rateChip(for rate: Double) -> some View {
        let isSelected = rate == rateOverride
        let label: String = rate == 0 ? "Default" : String(format: "%.2gx", rate)
        return Button {
            rateOverride = rate
        } label: {
            Text(label)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(isSelected ? Color.black : Color.offscriptTextPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Capsule().fill(isSelected ? Color.offscriptAccent : Color.offscriptFillLight))
        }
        .buttonStyle(.plain)
    }

    private var notifyCard: some View {
        Toggle(isOn: $notify) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notify on new episodes")
                    .font(.offscriptCardTitle)
                    .foregroundStyle(Color.offscriptTextPrimary)
                Text("OffScript pings you when this show drops a new episode.")
                    .font(.offscriptMeta)
                    .foregroundStyle(Color.offscriptTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color.offscriptAccent)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offscriptUtilitySurface()
    }
}

/// Persists podcast prefs as the sliders / toggles change. Splits each
/// onChange into its own tiny modifier so the type-checker doesn't choke on
/// the chained closures.
private struct PodcastPreferencesPersister: ViewModifier {
    let podcastID: UUID
    let introSeconds: Double
    let outroSeconds: Double
    let rateOverride: Double
    let notify: Bool

    func body(content: Content) -> some View {
        content
            .modifier(PrefIntChange(value: introSeconds) { v in
                PodcastPreferences.setSkipIntroSeconds(Int(v), for: podcastID)
            })
            .modifier(PrefIntChange(value: outroSeconds) { v in
                PodcastPreferences.setSkipOutroSeconds(Int(v), for: podcastID)
            })
            .modifier(PrefDoubleChange(value: rateOverride) { v in
                PodcastPreferences.setPlaybackRate(v > 0 ? Float(v) : nil, for: podcastID)
            })
            .modifier(PrefBoolChange(value: notify) { v in
                PodcastPreferences.setNotificationsEnabled(v, for: podcastID)
                if v {
                    Task { await OffScriptNotifications.shared.requestPermissionIfNeeded() }
                }
            })
    }
}

private struct PrefIntChange: ViewModifier {
    let value: Double
    let onChange: (Double) -> Void
    func body(content: Content) -> some View {
        content.onChange(of: value) { _, v in onChange(v) }
    }
}

private struct PrefDoubleChange: ViewModifier {
    let value: Double
    let onChange: (Double) -> Void
    func body(content: Content) -> some View {
        content.onChange(of: value) { _, v in onChange(v) }
    }
}

private struct PrefBoolChange: ViewModifier {
    let value: Bool
    let onChange: (Bool) -> Void
    func body(content: Content) -> some View {
        content.onChange(of: value) { _, v in onChange(v) }
    }
}

private struct LibrarySearchField: View {
    @Binding var query: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.offscriptTextMuted)
            TextField("Search inside your library", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(Color.offscriptTextPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focused)
            if !query.isEmpty {
                Button {
                    query = ""
                    focused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.offscriptTextMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.offscriptCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.offscriptHairline, lineWidth: 0.5)
        )
    }
}

private struct LibraryFocusChips: View {
    @Binding var selection: LibraryView.LibraryFocusFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryView.LibraryFocusFilter.allCases) { filter in
                    let isSelected = selection == filter
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            selection = filter
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.systemImage)
                                .font(.caption.weight(.semibold))
                                .symbolEffect(.bounce, value: isSelected)
                            Text(filter.title)
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(isSelected ? Color.black : Color.offscriptTextPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.offscriptAccent)
                                    .shadow(color: Color.offscriptAccent.opacity(0.35), radius: 10, y: 4)
                            } else {
                                Capsule().fill(.clear).offscriptGlass(in: Capsule())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: isSelected)
                }
            }
        }
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
                HStack(spacing: OffScriptTheme.itemSpacing) {
                    ForEach(episodes) { episode in
                        EpisodeVerticalCard(
                            episode: episode,
                            explanationTag: reasonProvider(episode)
                        )
                    }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)
            }
        }
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

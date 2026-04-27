import OSLog
import SwiftData
import SwiftUI

private let libraryLogger = Logger(subsystem: "com.offscript", category: "Library")

// MARK: - LibraryView (Tuner channel directory)
//
//   ┌── LIBRARY · CHANNEL DIRECTORY ──────────────────┐
//   │  COUNTS [SHOWS · UNPLAYED · IN PROGRESS]        │
//   │  Library                                        │
//   │  ── CONTINUE LISTENING (rail)                   │
//   │  ── FRESH EPISODES (rail)                       │
//   │  ── SHOWS (hairline-listed channel rows)        │
//   └─────────────────────────────────────────────────┘

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
            VStack(alignment: .leading, spacing: 16) {
                LibraryTunerHeader(
                    showCount: subscribedPodcasts.count,
                    unplayedCount: freshEpisodes.count,
                    inProgressCount: inProgressEpisodes.count
                )

                if subscribedPodcasts.isEmpty {
                    emptyState
                } else {
                    if !inProgressEpisodes.isEmpty {
                        TunerEpisodeRail(
                            title: "CONTINUE LISTENING",
                            episodes: Array(inProgressEpisodes.prefix(8)),
                            reasonProvider: { ep in
                                if let dur = ep.duration {
                                    return "\(EpisodeDurationFormatter.short(max(dur - ep.playedPosition, 0))) LEFT"
                                }
                                return "IN PROGRESS"
                            }
                        )
                    }

                    if !freshEpisodes.isEmpty {
                        TunerEpisodeRail(
                            title: "FRESH EPISODES",
                            episodes: Array(freshEpisodes.prefix(10)),
                            reasonProvider: { ep in
                                if let dur = ep.duration {
                                    return "FRESH · \(EpisodeDurationFormatter.short(dur).uppercased())"
                                }
                                return "FRESH"
                            }
                        )
                    }

                    showsSection
                }
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 90)
        }
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.offscriptStudioBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .refreshable { await syncSubscriptions() }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: onOpenSettings) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.offscriptSignalYellow)
                }
                .accessibilityLabel("Open settings")
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            TunerLabel(text: "● NO CHANNELS TUNED", color: .offscriptFnInfo)
            Text("Your library is empty")
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(Color.offscriptPaperWhite)
            Text("Use Search to bring in shows. OffScript keeps them fresh here once you subscribe.")
                .font(.system(size: 13.5))
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineSpacing(2)

            NavigationLink {
                SearchView()
            } label: {
                HStack {
                    TunerLabel(text: "→ FIND SHOWS", color: .offscriptSignalYellow, size: 11)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.top, 16)
    }

    private var showsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
            TunerLabel(text: "SHOWS · SUBSCRIBED", color: .offscriptSignalYellow)

            LazyVStack(spacing: 0) {
                ForEach(Array(subscribedPodcasts.enumerated()), id: \.element.id) { idx, podcast in
                    NavigationLink {
                        PodcastDetailView(podcast: podcast)
                    } label: {
                        PodcastShelfRow(
                            podcast: podcast,
                            channelNumber: idx + 1,
                            unplayedCount: freshEpisodes.filter { $0.podcast.id == podcast.id }.count,
                            inProgressCount: inProgressEpisodes.filter { $0.podcast.id == podcast.id }.count
                        )
                    }
                    .buttonStyle(.plain)
                    if idx < subscribedPodcasts.count - 1 {
                        Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                    }
                }
            }
            .padding(.top, 4)
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

// MARK: - Header

private struct LibraryTunerHeader: View {
    let showCount: Int
    let unplayedCount: Int
    let inProgressCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TunerLabel(text: "LIBRARY · CHANNEL DIRECTORY", color: .offscriptSignalYellow)
                Spacer()
                TunerLabel(text: "\(showCount) CH", color: .offscriptFnInfo)
            }

            Text("Library")
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Color.offscriptPaperWhite)

            // Inline mono readout — no surface, just hairline bar between
            HStack(spacing: 14) {
                statReadout(label: "SHOWS", value: showCount)
                Rectangle().fill(Color.offscriptHairline).frame(width: 1, height: 24)
                statReadout(label: "UNPLAYED", value: unplayedCount)
                Rectangle().fill(Color.offscriptHairline).frame(width: 1, height: 24)
                statReadout(label: "IN PROGRESS", value: inProgressCount)
                Spacer()
            }
            .padding(.top, 6)

            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func statReadout(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(value))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.offscriptPaperWhite)
                .monospacedDigit()
            TunerLabel(text: label, color: .offscriptSoftPaper, size: 8)
        }
    }
}

// MARK: - Tuner episode rail

private struct TunerEpisodeRail: View {
    let title: String
    let episodes: [Episode]
    let reasonProvider: (Episode) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
            TunerLabel(text: title, color: .offscriptSignalYellow)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(episodes) { episode in
                        TunerLibraryCard(episode: episode, reason: reasonProvider(episode))
                    }
                }
            }
        }
    }
}

private struct TunerLibraryCard: View {
    @Environment(\.modelContext) private var modelContext
    let episode: Episode
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                EpisodeDetailView(episode: episode)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    OffScriptArtworkView(
                        url: episode.artworkURL ?? episode.podcast.artworkURL,
                        cornerRadius: 3
                    )
                    .frame(width: 64, height: 64)
                    .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 4) {
                        TunerLabel(text: episode.podcast.title.uppercased(), color: .offscriptFnInfo, size: 8)
                            .lineLimit(1)
                        Text(episode.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.offscriptPaperWhite)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        TunerTag(text: reason, color: .offscriptSignalYellow, dim: true)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Button {
                    PlaybackController.shared.play(episode, in: modelContext)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 30, height: 30)
                        .background(Color.offscriptSignalYellow)
                }
                .buttonStyle(.plain)

                Button {
                    do { try QueueService.add(episode, in: modelContext) }
                    catch { libraryLogger.error("Queue add failed: \(error.localizedDescription, privacy: .public)") }
                } label: {
                    Image(systemName: episode.isQueued ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .frame(width: 30, height: 30)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(episode.isQueued)

                Spacer()
            }
        }
        .padding(10)
        .frame(width: 280, alignment: .leading)
        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
    }
}

// MARK: - Show row

private struct PodcastShelfRow: View {
    let podcast: Podcast
    let channelNumber: Int
    let unplayedCount: Int
    let inProgressCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", channelNumber))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.offscriptSignalYellow)
                .frame(width: 28, alignment: .leading)

            OffScriptArtworkView(url: podcast.artworkURL, cornerRadius: 3)
                .frame(width: 56, height: 56)
                .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(podcast.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(1)
                if let author = podcast.author {
                    TunerLabel(text: author.uppercased(), color: .offscriptSoftPaper, size: 8)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if inProgressCount > 0 {
                        TunerLabel(text: "● \(inProgressCount) IN PROGRESS", color: .offscriptFnInfo, size: 8)
                    }
                    TunerLabel(text: "\(unplayedCount) UNPLAYED", color: .offscriptSoftPaper, size: 8)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.offscriptSignalYellow)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - PodcastDetailView (Tuner channel detail)

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
            VStack(alignment: .leading, spacing: 16) {
                PodcastDetailTunerHeader(podcast: podcast, episodeCount: episodes.count)

                FilterRow(selection: $filter)

                if episodes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        TunerLabel(text: "● NO EPISODES MATCH FILTER", color: .offscriptSoftPaper)
                        Text(episodeSearchQuery.isEmpty
                             ? "Change the filter or sync this feed again later."
                             : "No episodes match \"\(episodeSearchQuery)\".")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Color.offscriptPaperWhite)
                    }
                    .padding(.vertical, 12)
                    .overlay(
                        Rectangle().fill(Color.offscriptHairline).frame(height: 1),
                        alignment: .top
                    )
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(episodes.enumerated()), id: \.element.id) { idx, episode in
                            PodcastEpisodeTunerRow(episode: episode, rank: idx + 1)
                            if idx < episodes.count - 1 {
                                Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                            }
                        }
                    }
                    .overlay(
                        Rectangle().fill(Color.offscriptHairline).frame(height: 1),
                        alignment: .top
                    )
                }
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 90)
        }
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.offscriptStudioBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .searchable(text: $episodeSearchQuery, prompt: "Search episodes")
    }
}

private struct PodcastDetailTunerHeader: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    let podcast: Podcast
    let episodeCount: Int
    @State private var showUnsubscribeConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TunerLabel(text: "CHANNEL · DETAIL", color: .offscriptSignalYellow)
                Spacer()
                TunerLabel(text: podcast.isSubscribed ? "● SUBSCRIBED" : "○ UNSUBSCRIBED",
                           color: podcast.isSubscribed ? .offscriptFnMode : .offscriptSoftPaper)
            }

            HStack(alignment: .top, spacing: 14) {
                OffScriptArtworkView(url: podcast.artworkURL, cornerRadius: 3)
                    .frame(width: 96, height: 96)
                    .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

                VStack(alignment: .leading, spacing: 6) {
                    if let author = podcast.author {
                        TunerLabel(text: author.uppercased(), color: .offscriptFnInfo)
                            .lineLimit(1)
                    }
                    TunerLabel(text: "\(episodeCount) EPISODES", color: .offscriptSoftPaper)
                    Spacer(minLength: 0)
                }
                Spacer()
            }

            Text(podcast.title)
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineSpacing(2)

            if let summary = podcast.summary {
                Text(summary)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineSpacing(2)
                    .lineLimit(6)
            }

            HStack(spacing: 8) {
                if podcast.isSubscribed {
                    Button {
                        showUnsubscribeConfirmation = true
                    } label: {
                        TunerLabel(text: "× UNSUBSCRIBE", color: .offscriptFnRecord, size: 10)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog(
                        "Unsubscribe from \(podcast.title)?",
                        isPresented: $showUnsubscribeConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Unsubscribe", role: .destructive) {
                            withAnimation {
                                podcast.isSubscribed = false
                                do {
                                    let queueItems = try QueueService.orderedItems(in: modelContext)
                                    for item in queueItems where item.episode.podcast.id == podcast.id {
                                        try QueueService.remove(item, in: modelContext)
                                    }
                                    try modelContext.save()
                                } catch {
                                    libraryLogger.error("Failed to unsubscribe: \(error.localizedDescription, privacy: .public)")
                                }
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This removes the show from your library and dequeues its episodes.")
                    }
                }

                if let url = podcast.websiteURL {
                    Button {
                        openURL(url)
                    } label: {
                        TunerLabel(text: "→ WEBSITE", color: .offscriptSignalYellow, size: 10)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.top, 4)

            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                .padding(.top, 6)
        }
    }
}

private struct PodcastEpisodeTunerRow: View {
    @Environment(\.modelContext) private var modelContext
    let episode: Episode
    let rank: Int

    private var progressValue: Double {
        guard let duration = episode.duration, duration > 0 else { return 0 }
        return episode.playedPosition / duration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                EpisodeDetailView(episode: episode)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(String(format: "%03d", rank))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Color.offscriptSignalYellow)
                        .frame(width: 32, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(episode.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.offscriptPaperWhite)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)

                        TunerLabel(text: metadata, color: .offscriptSoftPaper, size: 8)

                        if let summary = episode.summary {
                            Text(summary.strippingHTML)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.offscriptPaperWhite.opacity(0.7))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            if progressValue > 0 {
                GeometryReader { proxy in
                    let clamped = min(max(progressValue, 0), 1)
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.offscriptHairline)
                        Rectangle().fill(Color.offscriptSignalYellow)
                            .frame(width: proxy.size.width * clamped)
                    }
                }
                .frame(height: 1)
            }

            HStack(spacing: 6) {
                Button {
                    PlaybackController.shared.play(episode, in: modelContext)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 30, height: 30)
                        .background(Color.offscriptSignalYellow)
                }
                .buttonStyle(.plain)

                Button {
                    do { try QueueService.add(episode, in: modelContext) }
                    catch { libraryLogger.error("Queue add failed: \(error.localizedDescription, privacy: .public)") }
                } label: {
                    Image(systemName: episode.isQueued ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .frame(width: 30, height: 30)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(episode.isQueued)

                Spacer()
            }
        }
        .padding(.vertical, 10)
    }

    private var metadata: String {
        var parts: [String] = []
        if let s = episode.seasonNumber, let e = episode.episodeNumber {
            parts.append("S\(s) E\(e)")
        } else if let e = episode.episodeNumber {
            parts.append("E\(e)")
        }
        parts.append(episode.pubDate.formatted(date: .abbreviated, time: .omitted))
        if let duration = episode.duration {
            parts.append(EpisodeDurationFormatter.short(duration))
        }
        return parts.joined(separator: " · ").uppercased()
    }
}

// MARK: - Filter row (Tuner mode toggles)

private struct FilterRow: View {
    @Binding var selection: EpisodeFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(EpisodeFilter.allCases) { filter in
                    Button {
                        withAnimation { selection = filter }
                    } label: {
                        TunerLabel(
                            text: filter.title.uppercased(),
                            color: selection == filter ? .black : .offscriptPaperWhite,
                            size: 10
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selection == filter ? Color.offscriptSignalYellow : Color.clear)
                        .overlay(Rectangle().stroke(
                            selection == filter ? Color.offscriptSignalYellow : Color.offscriptHairline,
                            lineWidth: 1
                        ))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == filter ? .isSelected : [])
                }
            }
        }
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

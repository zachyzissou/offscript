import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var sections: [HomeFeedSection] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    let onOpenSettings: () -> Void

    private let recommendationService = RecommendationService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                HomeEditorialHeader()

                if let errorMessage {
                    ContentUnavailableView("Feed unavailable", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                        .padding(.horizontal, OffScriptTheme.pagePadding)
                }

                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(Color.offscriptAccent)
                        Text("Building your feed...")
                            .font(.offscriptBody)
                            .foregroundStyle(Color.offscriptTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if sections.isEmpty {
                    VStack(spacing: 20) {
                        ContentUnavailableView("No recommendations yet", systemImage: "waveform.badge.magnifyingglass", description: Text("Add a few shows in Search and OffScript will build your smart feed."))

                        NavigationLink("Browse Search") {
                            SearchView()
                        }
                        .buttonStyle(PrimaryPillButtonStyle())
                    }
                    .padding(.top, 40)
                } else {
                    if let leadSection = sections.first, let leadEpisode = leadSection.episodes.first {
                        HeroRecommendationCard(
                            episode: leadEpisode,
                            reason: recommendationReason(for: leadSection.title, episode: leadEpisode)
                        )
                        .padding(.horizontal, OffScriptTheme.pagePadding)

                        let remainingLeadEpisodes = Array(leadSection.episodes.dropFirst())
                        if !remainingLeadEpisodes.isEmpty {
                            RecommendationRail(
                                title: "Next Best Picks",
                                subtitle: "More picks in the same lane.",
                                episodes: remainingLeadEpisodes,
                                reasonProvider: { recommendationReason(for: leadSection.title, episode: $0) }
                            )
                        }
                    }

                    ForEach(Array(sections.dropFirst())) { section in
                        RecommendationRail(
                            title: section.title,
                            subtitle: section.subtitle,
                            episodes: section.episodes,
                            reasonProvider: { recommendationReason(for: section.title, episode: $0) }
                        )
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .offscriptPageBackground()
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.offscriptBackgroundTop.opacity(0.98), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: onOpenSettings) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.offscriptTextMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open settings")
                .accessibilityHint("Adjust playback and recommendation preferences")
            }
        }
        .task { await loadSections() }
        .refreshable { await loadSections() }
    }

    @MainActor
    private func loadSections() async {
        do {
            let loaded = try recommendationService.homeSections(context: modelContext)
            withAnimation(.easeInOut(duration: 0.3)) {
                sections = loaded
                errorMessage = nil
                isLoading = false
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func recommendationReason(for sectionTitle: String, episode: Episode) -> String {
        if episode.playedPosition > 0, !episode.isPlayed {
            return "Continue listening"
        }

        switch sectionTitle {
        case "Quick Wins":
            if let duration = episode.duration {
                return "Fits \(EpisodeDurationFormatter.short(duration))"
            }
            return "Short listen"
        case "Fresh From Library":
            return "Fresh from your library"
        case "Because You Liked":
            return "Because you liked similar topics"
        case "Best Next":
            if let duration = episode.duration, duration / 60 <= 35 {
                return "High fit for \(EpisodeDurationFormatter.short(duration))"
            }
            return "Best next listen"
        default:
            return "Picked for you"
        }
    }
}

private struct HomeEditorialHeader: View {
    private var dayString: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ready when you are")
                .font(.offscriptUtilityTitle)
                .foregroundStyle(Color.offscriptTextPrimary)

            Text(dayString.uppercased())
                .font(.offscriptMeta.weight(.semibold))
                .foregroundStyle(Color.offscriptTextMuted)
        }
        .padding(.horizontal, OffScriptTheme.pagePadding)
    }
}

private struct HeroRecommendationCard: View {
    @Environment(\.modelContext) private var modelContext

    let episode: Episode
    let reason: String

    private var progressValue: Double {
        guard let duration = episode.duration, duration > 0 else { return 0 }
        return episode.playedPosition / duration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                EpisodeDetailView(episode: episode)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    OffScriptArtworkView(url: episode.artworkURL ?? episode.podcast.artworkURL, cornerRadius: OffScriptTheme.Radius.medium)
                        .frame(width: 76, height: 76)

                    VStack(alignment: .leading, spacing: 4) {
                        OffScriptReasonBadge(text: reason)

                        Text(episode.podcast.title)
                            .font(.offscriptMeta.weight(.semibold))
                            .foregroundStyle(Color.offscriptTextMuted)
                            .lineLimit(1)

                        Text(episode.title)
                            .font(.system(.title3, design: .serif, weight: .bold))
                            .foregroundStyle(Color.offscriptTextPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button("Play") {
                    PlaybackController.shared.play(episode, in: modelContext)
                }
                .buttonStyle(PrimaryPillButtonStyle())

                Button(episode.isQueued ? "Queued" : "Queue") {
                    withAnimation { try? QueueService.add(episode, in: modelContext) }
                }
                .buttonStyle(SecondaryPillButtonStyle())
                .disabled(episode.isQueued)

                Spacer()

                Menu {
                    Button("Like") { register(.like) }
                    Button("Less like this") { register(.lessLikeThis) }
                    Button("Not now") { register(.notInterested) }
                } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.offscriptTextPrimary)
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Circle())
                }
                .accessibilityLabel("More actions")
                .accessibilityHint("Like this episode or tune future recommendations")
            }

            HStack(spacing: 12) {
                Label(metadata, systemImage: "clock")
                if episode.playedPosition > 0, !episode.isPlayed {
                    Label(timeRemaining, systemImage: "arrow.trianglehead.clockwise")
                }
            }
            .font(.offscriptMeta)
            .foregroundStyle(Color.offscriptTextMuted)

            if progressValue > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    OffScriptProgressBar(value: progressValue, height: 6)
                    Text("Resume from where you left off")
                        .font(.offscriptMeta)
                        .foregroundStyle(Color.offscriptTextMuted)
                }
            }

        }
        .padding(20)
        .padding(.bottom, 4)
        .offscriptSurface(radius: OffScriptTheme.Radius.large, prominent: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(episode.title) from \(episode.podcast.title). \(reason)")
    }

    private var metadata: String {
        let dateString = episode.pubDate.formatted(date: .abbreviated, time: .omitted)
        if let duration = episode.duration {
            return "\(dateString) • \(EpisodeDurationFormatter.short(duration))"
        }
        return dateString
    }

    private var timeRemaining: String {
        guard let duration = episode.duration else { return "In progress" }
        let remaining = max(0, duration - episode.playedPosition)
        return "\(EpisodeDurationFormatter.short(remaining)) left"
    }

    private func register(_ action: PreferenceSignal.Action) {
        modelContext.insert(PreferenceSignal(action: action, episode: episode))
        try? modelContext.save()
    }
}

private struct RecommendationRail: View {
    let title: String
    let subtitle: String
    let episodes: [Episode]
    let reasonProvider: (Episode) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OffScriptSectionHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, OffScriptTheme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(episodes) { episode in
                        EpisodeRailCard(episode: episode, reason: reasonProvider(episode))
                    }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)
            }
        }
    }
}

private struct EpisodeRailCard: View {
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
                    VStack(alignment: .leading, spacing: 12) {
                        OffScriptArtworkView(url: episode.artworkURL ?? episode.podcast.artworkURL, cornerRadius: 20)
                            .frame(width: 160, height: 160)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 6) {
                            OffScriptReasonBadge(text: reason)

                            Text(episode.podcast.title.uppercased())
                                .font(.offscriptMicro.weight(.semibold))
                                .foregroundStyle(Color.offscriptAccent)

                            Text(episode.title)
                                .font(.offscriptCardTitle)
                                .foregroundStyle(Color.offscriptTextPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Text(metadata)
                                .font(.offscriptMeta)
                                .foregroundStyle(Color.offscriptTextMuted)
                        }
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Button("Play") {
                        PlaybackController.shared.play(episode, in: modelContext)
                    }
                    .buttonStyle(PrimaryPillButtonStyle())

                    Button {
                        try? QueueService.add(episode, in: modelContext)
                    } label: {
                        Image(systemName: episode.isQueued ? "checkmark" : "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.offscriptTextPrimary)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .disabled(episode.isQueued)

                    Spacer()
                }
            }
            .padding(16)
        }
        .frame(width: 196, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                .stroke(Color.offscriptHairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 12, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(episode.title) from \(episode.podcast.title). \(reason)")
    }

    private var metadata: String {
        let dateString = episode.pubDate.formatted(date: .abbreviated, time: .omitted)
        if let duration = episode.duration {
            return "\(dateString) • \(EpisodeDurationFormatter.short(duration))"
        }
        return dateString
    }
}

import SwiftUI

struct PodcastPickerView: View {
    let selectedGenres: Set<Genre>
    let onContinue: ([PodcastSearchResult]) -> Void
    let onBack: () -> Void

    @State private var selectedFeeds: Set<URL> = []
    @State private var livePodcasts: [Genre: [PodcastSearchResult]] = [:]
    @State private var allPodcasts: [PodcastSearchResult] = []

    private var prioritizedGenres: [Genre] {
        let selected = Genre.allCases.filter { selectedGenres.contains($0) }
        let rest = Genre.allCases.filter { !selectedGenres.contains($0) }
        return selected + rest
    }

    private var canContinue: Bool { selectedFeeds.count >= 3 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pick 3+ shows to build your feed")
                            .font(.system(.title, design: .serif, weight: .bold))
                            .foregroundStyle(Color.offscriptTextPrimary)

                        Text("We'll subscribe you and start learning your taste.")
                            .font(.offscriptBody)
                            .foregroundStyle(Color.offscriptTextSecondary)
                    }
                    .padding(.horizontal, 24)

                    ForEach(prioritizedGenres) { genre in
                        let podcasts = mergedPodcasts(for: genre)
                        if !podcasts.isEmpty {
                            PodcastGenreRail(
                                genre: genre,
                                podcasts: podcasts,
                                selectedFeeds: $selectedFeeds,
                                showExploreHeader: !selectedGenres.isEmpty && !selectedGenres.contains(genre)
                            )
                        }
                    }
                }
                .padding(.top, 32)
                .padding(.bottom, 120)
            }

            VStack(spacing: 12) {
                Button {
                    let selected = allPodcasts.filter { selectedFeeds.contains($0.feedURL) }
                    onContinue(selected)
                } label: {
                    HStack {
                        Text("Continue")
                        if !selectedFeeds.isEmpty {
                            Text("(\(selectedFeeds.count))")
                                .fontWeight(.bold)
                        }
                    }
                }
                .buttonStyle(OnboardingContinueButtonStyle())
                .disabled(!canContinue)
                .opacity(canContinue ? 1.0 : 0.5)

                if !canContinue {
                    Text("Pick \(max(0, 3 - selectedFeeds.count)) more")
                        .font(.offscriptMeta)
                        .foregroundStyle(Color.offscriptTextMuted)
                }

                Button("Back") { onBack() }
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextMuted)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                Color.offscriptBackground.opacity(0.95)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .task { await loadLivePodcasts() }
    }

    private func mergedPodcasts(for genre: Genre) -> [PodcastSearchResult] {
        let curated = CuratedPodcastCatalog.podcasts(for: genre)
        let live = livePodcasts[genre] ?? []
        let curatedURLs = Set(curated.map(\.feedURL))
        let deduped = live.filter { !curatedURLs.contains($0.feedURL) }
        return curated + deduped
    }

    @MainActor
    private func loadLivePodcasts() async {
        allPodcasts = CuratedPodcastCatalog.all

        for genre in prioritizedGenres {
            let results = await TopPodcastsService.fetchTop(genre: genre, limit: 8)
            if !results.isEmpty {
                livePodcasts[genre] = results
                let existingURLs = Set(allPodcasts.map(\.feedURL))
                let newEntries = results.filter { !existingURLs.contains($0.feedURL) }
                allPodcasts.append(contentsOf: newEntries)
            }
        }
    }
}

private struct PodcastGenreRail: View {
    let genre: Genre
    let podcasts: [PodcastSearchResult]
    @Binding var selectedFeeds: Set<URL>
    let showExploreHeader: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showExploreHeader {
                Text("Explore More")
                    .font(.offscriptMicro.weight(.semibold))
                    .foregroundStyle(Color.offscriptTextMuted)
                    .padding(.horizontal, 24)
            }

            Text(genre.title)
                .font(.offscriptSectionTitle)
                .foregroundStyle(Color.offscriptTextPrimary)
                .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(podcasts, id: \.feedURL) { podcast in
                        OnboardingPodcastCard(
                            podcast: podcast,
                            isSelected: selectedFeeds.contains(podcast.feedURL),
                            onTap: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                    if selectedFeeds.contains(podcast.feedURL) {
                                        selectedFeeds.remove(podcast.feedURL)
                                    } else {
                                        selectedFeeds.insert(podcast.feedURL)
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

private struct OnboardingPodcastCard: View {
    let podcast: PodcastSearchResult
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    OffScriptArtworkView(
                        url: podcast.artworkURL,
                        cornerRadius: OffScriptTheme.Radius.medium
                    )
                    .frame(width: 120, height: 120)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.offscriptAccent)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                            .padding(6)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                        .stroke(isSelected ? Color.offscriptAccent : Color.clear, lineWidth: 2)
                )

                Text(podcast.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(podcast.author)
                    .font(.caption2)
                    .foregroundStyle(Color.offscriptTextMuted)
                    .lineLimit(1)
            }
            .frame(width: 120)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isSelected)
        .accessibilityLabel("\(podcast.title) by \(podcast.author)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

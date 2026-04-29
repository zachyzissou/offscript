import SwiftUI

// MARK: - PodcastPickerView (Tuner)
//
// "02 · CHANNELS / Tune the bank" — pick channels from each band.
// Header is the Tuner instrument cluster vocabulary; rails are 3-up channel
// selection cards with hairline borders, mono captions, signal-yellow
// confirmations.
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

    private var selectedGenreCount: Int {
        let selectedPodcasts = allPodcasts.filter { selectedFeeds.contains($0.feedURL) }
        var genresRepresented = Set<String>()
        for podcast in selectedPodcasts {
            for genre in Genre.allCases {
                let genrePodcasts = mergedPodcasts(for: genre)
                if genrePodcasts.contains(where: { $0.feedURL == podcast.feedURL }) {
                    genresRepresented.insert(genre.title)
                }
            }
        }
        return genresRepresented.count
    }

    private var canContinue: Bool { selectedFeeds.count >= 3 && selectedGenreCount >= 2 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        TunerLabel(text: "02 · CHANNELS", color: .offscriptSignalYellow, size: 10)
                        Text("Tune the bank")
                            .font(.system(size: 32, weight: .bold, design: .default))
                            .tracking(-0.6)
                            .foregroundStyle(Color.offscriptPaperWhite)
                        Text("PICK 3+ CHANNELS · 2+ BANDS · WE'LL LEARN FROM HERE")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(Color.offscriptSoftPaper)
                    }
                    .padding(.horizontal, 20)

                    HStack {
                        TunerLabel(
                            text: "\(selectedFeeds.count) PICKED",
                            color: selectedFeeds.isEmpty ? .offscriptSoftPaper : .offscriptSignalYellow
                        )
                        Spacer()
                        TunerLabel(text: "\(selectedGenreCount) BANDS")
                    }
                    .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(prioritizedGenres) { genre in
                            let podcasts = mergedPodcasts(for: genre)
                            if !podcasts.isEmpty {
                                PodcastGenreRail(
                                    genre: genre,
                                    podcasts: podcasts,
                                    selectedFeeds: $selectedFeeds,
                                    isExplore: !selectedGenres.isEmpty && !selectedGenres.contains(genre)
                                )
                            }
                        }
                    }
                }
                .padding(.top, 28)
                .padding(.bottom, 140)
            }

            // Bottom CTA bar
            VStack(spacing: 10) {
                Button {
                    let selected = allPodcasts.filter { selectedFeeds.contains($0.feedURL) }
                    onContinue(selected)
                } label: {
                    HStack {
                        Spacer()
                        Text(canContinue
                             ? "CONTINUE → (\(selectedFeeds.count))"
                             : selectedFeeds.count >= 3
                                ? "PICK FROM 2+ BANDS"
                                : "PICK \(max(0, 3 - selectedFeeds.count)) MORE")
                            .font(.system(size: 13, weight: .bold, design: .default))
                            .tracking(2)
                            .foregroundStyle(canContinue ? Color.offscriptStudioBlack : Color.offscriptSoftPaper)
                            .monospacedDigit()
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .background(canContinue ? Color.offscriptSignalYellow : Color.clear)
                    .overlay(
                        Rectangle().stroke(
                            canContinue ? Color.clear : Color.offscriptHairline,
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canContinue)

                Button(action: onBack) {
                    TunerLabel(text: "← BACK")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.offscriptStudioBlack.ignoresSafeArea(edges: .bottom))
            .overlay(
                Rectangle().fill(Color.offscriptHairline).frame(height: 1),
                alignment: .top
            )
        }
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
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
        // origin/main removed TopPodcastsService — fall back to the curated
        // catalog only. Reintroducing live top-by-genre is a follow-up.
        allPodcasts = CuratedPodcastCatalog.all
    }
}

private struct PodcastGenreRail: View {
    let genre: Genre
    let podcasts: [PodcastSearchResult]
    @Binding var selectedFeeds: Set<URL>
    let isExplore: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(genre.title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .default))
                    .tracking(1.4)
                    .foregroundStyle(Color.offscriptPaperWhite)

                if isExplore {
                    TunerLabel(text: "CURATED", color: .offscriptFnInfo)
                }
                Spacer()
                TunerLabel(text: "\(podcasts.count) STARTERS")
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
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
                .padding(.horizontal, 20)
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
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    OffScriptArtworkView(url: podcast.artworkURL, cornerRadius: 3)
                        .frame(width: 120, height: 120)

                    if isSelected {
                        ZStack {
                            Rectangle()
                                .fill(Color.offscriptSignalYellow)
                                .frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.offscriptStudioBlack)
                        }
                        .padding(6)
                    }
                }
                .overlay(
                    Rectangle().stroke(
                        isSelected ? Color.offscriptSignalYellow : Color.offscriptHairline,
                        lineWidth: 1
                    )
                )

                Text(podcast.title)
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .tracking(-0.1)
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(podcast.author.uppercased())
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Color.offscriptSoftPaper)
                    .lineLimit(1)
            }
            .frame(width: 120, alignment: .leading)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isSelected)
        .accessibilityLabel("\(podcast.title) by \(podcast.author)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

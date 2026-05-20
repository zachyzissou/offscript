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
    @State private var openedCollection: EditorialCollection?

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
                            .tracking(0)
                            .foregroundStyle(Color.offscriptPaperWhite)
                        Text("PICK 3+ CHANNELS · 2+ BANDS · WE'LL LEARN FROM HERE")
                            .tunerFont(size: 9)
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

                    EditorialCollectionsStrip(
                        collections: nonEmptyCollections,
                        onOpen: { openedCollection = $0 }
                    )

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
        .sheet(item: $openedCollection) { collection in
            EditorialCollectionDetailView(
                collection: collection,
                entries: CuratedPodcastCatalog.resolve(collection),
                selectedFeeds: $selectedFeeds
            )
        }
    }

    /// Collections with at least one resolved entry. We never render a
    /// shelf that points to an empty list — that would lie to the user
    /// about what's behind the tap.
    private var nonEmptyCollections: [EditorialCollection] {
        CuratedPodcastCatalog.editorialCollections.filter {
            !CuratedPodcastCatalog.resolve($0).isEmpty
        }
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
                    .tracking(0)
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(podcast.author.uppercased())
                    .tunerFont(size: 8, tracking: 1.2)
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

// MARK: - Editorial collections strip
//
// Horizontal rail of collection cards above the genre bank. Each card is a
// hand-curated viewpoint (e.g. "Just under an hour") rendered with the
// Tuner vocabulary — hairline border, tracked tuner label header, sample
// artwork stack, optional curator italic, and a "N INSIDE" mono count.

private struct EditorialCollectionsStrip: View {
    let collections: [EditorialCollection]
    let onOpen: (EditorialCollection) -> Void

    var body: some View {
        if collections.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    TunerLabel(text: "EDITORIAL · CURATED", color: .offscriptFnInfo)
                    Spacer()
                    TunerLabel(text: "\(collections.count) SHELVES")
                }
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(collections) { collection in
                            EditorialCollectionCard(
                                collection: collection,
                                entries: CuratedPodcastCatalog.resolve(collection),
                                onTap: { onOpen(collection) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}

private struct EditorialCollectionCard: View {
    let collection: EditorialCollection
    let entries: [CuratedEntry]
    let onTap: () -> Void

    private let cardWidth: CGFloat = 240
    private let thumbnailSize: CGFloat = 44

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(entries.prefix(4), id: \.result.feedURL) { entry in
                        OffScriptArtworkView(url: entry.result.artworkURL, cornerRadius: 3)
                            .frame(width: thumbnailSize, height: thumbnailSize)
                            .overlay(
                                Rectangle().stroke(Color.offscriptHairline, lineWidth: 1)
                            )
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.title)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .tracking(0)
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .lineLimit(1)

                    if let subtitle = collection.subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.offscriptSoftPaper)
                            .lineLimit(1)
                    }
                }

                if let note = collection.curatorNote {
                    Text(note)
                        .font(.system(size: 11, weight: .regular, design: .default).italic())
                        .foregroundStyle(Color.offscriptFadedPaper)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    TunerLabel(text: "\(entries.count) INSIDE", color: .offscriptSoftPaper)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.offscriptSoftPaper)
                        .accessibilityHidden(true)
                }
            }
            .padding(12)
            .frame(width: cardWidth, alignment: .leading)
            .background(Color.offscriptStudioBlack)
            .overlay(
                Rectangle().stroke(Color.offscriptHairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        var parts: [String] = [collection.title]
        if let subtitle = collection.subtitle {
            parts.append(subtitle)
        }
        parts.append("\(entries.count) \(entries.count == 1 ? "podcast" : "podcasts") inside")
        return parts.joined(separator: ". ")
    }
}

// MARK: - Editorial collection detail
//
// Sheet that opens when a collection card is tapped. Lists every entry the
// filter resolved to; tapping a row toggles selection in the parent
// picker so the user can add a whole viewpoint's-worth of shows in one
// sitting without losing what they already picked from the genre bank.

private struct EditorialCollectionDetailView: View {
    let collection: EditorialCollection
    let entries: [CuratedEntry]
    @Binding var selectedFeeds: Set<URL>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    TunerLabel(text: "EDITORIAL · CURATED", color: .offscriptFnInfo)
                    Text(collection.title)
                        .font(.system(size: 28, weight: .bold, design: .default))
                        .tracking(0)
                        .foregroundStyle(Color.offscriptPaperWhite)
                    if let subtitle = collection.subtitle {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color.offscriptSoftPaper)
                    }
                    if let note = collection.curatorNote {
                        Text(note)
                            .font(.system(size: 13, weight: .regular).italic())
                            .foregroundStyle(Color.offscriptFadedPaper)
                            .padding(.top, 4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)

                HStack {
                    TunerLabel(text: "\(entries.count) \(entries.count == 1 ? "CHANNEL" : "CHANNELS")")
                    Spacer()
                    TunerLabel(
                        text: "\(selectedCountInsideCollection) PICKED",
                        color: selectedCountInsideCollection > 0 ? .offscriptSignalYellow : .offscriptSoftPaper
                    )
                }
                .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    ForEach(entries, id: \.result.feedURL) { entry in
                        EditorialDetailRow(
                            entry: entry,
                            isSelected: selectedFeeds.contains(entry.result.feedURL),
                            onTap: { toggleSelection(entry.result.feedURL) }
                        )
                        Rectangle()
                            .fill(Color.offscriptHairline)
                            .frame(height: 1)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 24)
            .padding(.bottom, 80)
        }
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            Button(action: { dismiss() }) {
                HStack {
                    Spacer()
                    Text("DONE")
                        .font(.system(size: 13, weight: .bold, design: .default))
                        .tracking(2)
                        .foregroundStyle(Color.offscriptStudioBlack)
                    Spacer()
                }
                .padding(.vertical, 16)
                .background(Color.offscriptSignalYellow)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private var selectedCountInsideCollection: Int {
        entries.filter { selectedFeeds.contains($0.result.feedURL) }.count
    }

    private func toggleSelection(_ feedURL: URL) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            if selectedFeeds.contains(feedURL) {
                selectedFeeds.remove(feedURL)
            } else {
                selectedFeeds.insert(feedURL)
            }
        }
    }
}

private struct EditorialDetailRow: View {
    let entry: CuratedEntry
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                OffScriptArtworkView(url: entry.result.artworkURL, cornerRadius: 3)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Rectangle().stroke(
                            isSelected ? Color.offscriptSignalYellow : Color.offscriptHairline,
                            lineWidth: 1
                        )
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.result.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .lineLimit(1)

                    Text(entry.result.author.uppercased())
                        .tunerFont(size: 8, tracking: 1.2)
                        .foregroundStyle(Color.offscriptSoftPaper)
                        .lineLimit(1)

                    if let durationLabel = durationLabel {
                        TunerLabel(text: durationLabel, color: .offscriptFadedPaper)
                    }
                }

                Spacer()

                ZStack {
                    Rectangle()
                        .fill(isSelected ? Color.offscriptSignalYellow : Color.clear)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Rectangle().stroke(
                                isSelected ? Color.offscriptSignalYellow : Color.offscriptHairline,
                                lineWidth: 1
                            )
                        )
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.offscriptStudioBlack)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isSelected)
        .accessibilityLabel("\(entry.result.title) by \(entry.result.author)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Curator's duration estimate as a mono tuner chip, e.g. "45–65 MIN".
    /// Stays present until the runtime preview loader's measured duration
    /// can replace it (deferred — `SearchPreviewLoader` exists but its
    /// metadata isn't threaded into the picker yet).
    private var durationLabel: String? {
        guard let range = entry.typicalDuration else { return nil }
        let lower = Int(range.lowerBound / 60)
        let upper = Int(range.upperBound / 60)
        if lower == upper { return "\(lower) MIN" }
        return "\(lower)–\(upper) MIN"
    }
}

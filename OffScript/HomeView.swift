import OSLog
import SwiftData
import SwiftUI

private let homeLogger = Logger(subsystem: "com.offscript", category: "Home")

// MARK: - HomeView (Tuner instrument cluster)
//
// Tuner vocabulary for the launch screen:
//   ┌── TODAY · MON · APR 27 ────────────────────────┐
//   │  HOME · CHANNEL FEED                            │
//   │  ─── HEADLINE ────────────────────────────      │
//   │  [hero panel: artwork tile + readouts]          │
//   │                                                 │
//   │  ── SECTION NAME ─────────────────────          │
//   │  [horizontal rail of channel cards]             │
//   └─────────────────────────────────────────────────┘

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("offscript.recommendationMode") private var recommendationModeRaw = AppSettings.RecommendationMode.balanced.rawValue
    @State private var sections: [HomeFeedSection] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isLoadingDiscovery = false
    @State private var isRetuning = false
    @State private var loadGeneration = 0
    @State private var feedbackRetuneTask: Task<Void, Never>?
    let onOpenSettings: () -> Void

    private let recommendationService = RecommendationService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HomeTunerHeader(
                    isRetuning: isRetuning,
                    onRetune: {
                        Task { await loadSections(manual: true) }
                    },
                    onOpenSettings: onOpenSettings
                )

                if let errorMessage {
                    HomeErrorRow(message: errorMessage)
                }

                if isLoading {
                    HomeSkeletonStack()
                } else if sections.isEmpty {
                    // Cold start — show curated starter picks instead of a
                    // dead-end "go search" empty state. Once the user has
                    // three subscriptions and recommendations have any data
                    // to work with, `sections` populates and this hides.
                    HomeStarterRail()
                } else {
                    let episodeSections = sections.filter { !$0.isDiscoverySection }
                    let discoverySections = sections.filter(\.isDiscoverySection)
                    let leadScoredEpisode = RecommendationService.headlineCandidate(from: episodeSections)

                    if let leadScoredEpisode {
                        HeroTunerCard(
                            episode: leadScoredEpisode.episode,
                            reason: leadScoredEpisode.explanation,
                            signals: leadScoredEpisode.signalTrace
                        )
                        .padding(.horizontal, OffScriptTheme.pagePadding)
                        .padding(.bottom, 6)
                    }

                    let railSections = Self.sections(episodeSections, excluding: leadScoredEpisode?.episode.id)
                    ForEach(Array(railSections.enumerated()), id: \.element.id) { _, section in
                        TunerRail(
                            title: section.title.uppercased(),
                            episodes: section.episodes,
                            reasonProvider: { section.explanation(for: $0) },
                            signalProvider: { section.signalTrace(for: $0) }
                        )
                    }

                    ForEach(discoverySections) { section in
                        TunerDiscoveryRail(section: section)
                    }

                    if isLoadingDiscovery {
                        HomeDiscoveryLoadingStrip()
                            .padding(.horizontal, OffScriptTheme.pagePadding)
                    }
                }
            }
            .padding(.top, OffScriptTheme.rootContentTopPadding)
            .padding(.bottom, 28)
        }
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
        .accessibilityIdentifier("HomeScreen")
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.offscriptStudioBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // No `.toolbar` ToolbarItem here. iOS 26's NavigationStack wraps any
        // toolbar Button in a Liquid Glass capsule that ignores `.plain`
        // styling and our color tokens — that's the gray-circle chrome we
        // saw in the screenshot. The settings affordance is rendered inline
        // in HomeTunerHeader instead, where we have full control.
        .task(id: recommendationModeRaw) { await loadSections() }
        .onReceive(NotificationCenter.default.publisher(for: .offscriptRecommendationFeedbackChanged)) { _ in
            feedbackRetuneTask?.cancel()
            feedbackRetuneTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 180_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await retuneAfterExplicitFeedback()
            }
        }
        .onDisappear { feedbackRetuneTask?.cancel() }
    }

    @MainActor
    private func loadSections(manual: Bool = false) async {
        if manual {
            guard !isRetuning else { return }
            isRetuning = true
        }
        loadGeneration += 1
        let generation = loadGeneration
        isLoadingDiscovery = false
        defer {
            if manual, generation == loadGeneration {
                isRetuning = false
            }
        }
        do {
            let mode = AppSettings.recommendationMode
            let loaded = try recommendationService.homeSections(context: modelContext, mode: mode)
            guard generation == loadGeneration else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                sections = loaded
                errorMessage = nil
                isLoading = false
                isLoadingDiscovery = false
            }
            await loadDiscovery(mode: mode, existingSections: loaded, generation: generation)
        } catch {
            guard generation == loadGeneration else { return }
            homeLogger.error("loadSections failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            isLoading = false
            isLoadingDiscovery = false
        }
    }

    private static func sections(_ sections: [HomeFeedSection], excluding leadEpisodeID: UUID?) -> [HomeFeedSection] {
        guard let leadEpisodeID else { return sections }
        return sections.compactMap { section in
            let remaining = section.scoredEpisodes.filter { $0.episode.id != leadEpisodeID }
            guard !remaining.isEmpty else { return nil }
            return HomeFeedSection(title: section.title, subtitle: section.subtitle, scoredEpisodes: remaining)
        }
    }

    @MainActor
    private func loadDiscovery(mode: AppSettings.RecommendationMode, existingSections: [HomeFeedSection], generation: Int) async {
        guard mode.allowsDiscovery else { return }
        guard generation == loadGeneration else { return }
        isLoadingDiscovery = true
        defer {
            if generation == loadGeneration {
                isLoadingDiscovery = false
            }
        }

        if let discovery = await recommendationService.discoverySection(context: modelContext, mode: mode) {
            guard !Task.isCancelled,
                  AppSettings.recommendationMode == mode,
                  generation == loadGeneration else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                sections = existingSections + [discovery]
            }
        }
    }

    @MainActor
    private func retuneAfterExplicitFeedback() async {
        // `homeSections` reads fresh PreferenceSignal rows directly, so this
        // updates visible recommendations without forcing a full taste-profile
        // rebuild on the tap path.
        await loadSections()
    }
}

// MARK: - Header

private struct HomeTunerHeader: View {
    let isRetuning: Bool
    let onRetune: () -> Void
    let onOpenSettings: () -> Void

    private var dayString: String {
        Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Both eyebrows lock to a single line — at larger Dynamic
                // Type sizes the right-hand "OFFSCRIPT · CHANNEL FEED" used
                // to wrap and collide with the "Home" title rendered just
                // below it. lineLimit(1) keeps each on one row; truncation
                // is preferable to overlap.
                TunerLabel(text: "TODAY · \(dayString.uppercased())", color: .offscriptSoftPaper)
                    .lineLimit(1)
                Spacer()
                TunerLabel(text: "OFFSCRIPT · CHANNEL FEED", color: .offscriptFnInfo)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline) {
                // Big spec-sheet headline
                Text("Home")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(0)
                    .foregroundStyle(Color.offscriptPaperWhite)

                Spacer()

                Button(action: onRetune) {
                    Image(systemName: isRetuning ? "waveform.path" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isRetuning ? Color.offscriptFnInfo : Color.offscriptSignalYellow)
                        .frame(width: 36, height: 30)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRetuning)
                .accessibilityLabel(isRetuning ? "Retuning recommendations" : "Retune recommendations")

                // Tuner config button — sharp hairline rectangle, signal-yellow
                // glyph. Replaces the toolbar gear which iOS 26 was wrapping in
                // a foreign glass-capsule chrome.
                Button(action: onOpenSettings) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.offscriptSignalYellow)
                        .frame(width: 36, height: 30)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open settings")
            }

            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                .padding(.top, 4)
        }
        .padding(.horizontal, OffScriptTheme.pagePadding)
        .padding(.top, 4)
    }
}

// MARK: - Error / Empty / Skeleton

private struct HomeErrorRow: View {
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TunerLabel(text: "● FEED UNAVAILABLE", color: .offscriptFnRecord)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.offscriptPaperWhite)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, OffScriptTheme.pagePadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
    }
}

/// Cold-start rail rendered when the user has zero subscriptions and the
/// recommendation engine has nothing to work with. Hand-curated picks
/// grouped by category, with one-tap subscribe through the same
/// `FeedSyncService.importPodcast` pipeline used by Search and OPML
/// import. Replaces the prior dead-end "go to Search" empty state.
private struct HomeStarterRail: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var subscribed: [Podcast]
    @State private var importingID: String?
    @State private var addedIDs: Set<String> = []
    @State private var errorMessage: String?
    private let syncService = FeedSyncService()

    private var subscribedFeedURLs: Set<String> {
        Set(subscribed.filter(\.isSubscribed).map { $0.feedURL.absoluteString })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            ForEach(StarterRailService.groupedPicks, id: \.0) { category, picks in
                section(category: category, picks: picks)
            }
            if let errorMessage {
                errorStrip(message: errorMessage)
            }
        }
        .padding(.horizontal, OffScriptTheme.pagePadding)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TunerLabel(text: "● START HERE", color: .offscriptSignalYellow)
                Spacer()
                TunerLabel(text: "\(subscribed.count(where: \.isSubscribed)) TUNED",
                           color: .offscriptFnInfo)
            }
            Text("Pick a few well-liked channels")
                .font(.system(size: 22, weight: .semibold))
                .tracking(0)
                .foregroundStyle(Color.offscriptPaperWhite)
            Text("These are widely-loved podcasts to seed your library. Subscribe to a few that look interesting — OffScript will start tailoring your feed once it has signal to work with.")
                .font(.system(size: 13))
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineSpacing(2)
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                .padding(.top, 4)
        }
    }

    private func section(category: StarterCategory, picks: [StarterPick]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TunerLabel(text: category.label, color: .offscriptSignalYellow)
            LazyVStack(spacing: 0) {
                ForEach(Array(picks.enumerated()), id: \.element.id) { idx, pick in
                    pickRow(idx: idx, pick: pick)
                    if idx < picks.count - 1 {
                        Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
    }

    private func pickRow(idx: Int, pick: StarterPick) -> some View {
        let isAdded = addedIDs.contains(pick.id)
            || subscribedFeedURLs.contains(pick.feedURL.absoluteString)
        let isImporting = importingID == pick.id

        return HStack(alignment: .top, spacing: 12) {
            Text(String(format: "%02d", idx + 1))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.offscriptSignalYellow)
                .frame(width: 28, alignment: .leading)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(pick.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(1)
                TunerLabel(text: pick.author.uppercased(),
                           color: .offscriptFnInfo, size: 8)
                    .lineLimit(1)
                Text(pick.summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.offscriptPaperWhite.opacity(0.75))
                    .lineSpacing(2)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await add(pick) }
            } label: {
                TunerLabel(
                    text: isAdded ? "✓ ADDED"
                        : (isImporting ? "○ ADDING…" : "+ ADD"),
                    color: isAdded ? .offscriptFnMode : .offscriptSignalYellow,
                    size: 10
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .overlay(Rectangle().stroke(
                    isAdded ? Color.offscriptFnMode : Color.offscriptSignalYellow,
                    lineWidth: 1
                ))
            }
            .buttonStyle(.plain)
            .disabled(isAdded || isImporting)
        }
        .padding(.vertical, 10)
    }

    private func errorStrip(message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TunerLabel(text: "● COULDN'T ADD", color: .offscriptFnRecord)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.offscriptPaperWhite)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptFnRecord).frame(height: 1),
            alignment: .top
        )
    }

    @MainActor
    private func add(_ pick: StarterPick) async {
        importingID = pick.id
        defer { importingID = nil }
        errorMessage = nil

        do {
            let result = StarterRailService.searchResult(for: pick)
            _ = try syncService.subscribeThenHydrate(
                from: result,
                into: modelContext,
                episodeLimit: 25
            )
            addedIDs.insert(pick.id)
        } catch {
            homeLogger.error("Starter add failed for \(pick.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't add \(pick.title) — try Search instead."
        }
    }
}

// Legacy empty state — kept for reference but no longer rendered. Cold
// start now uses HomeStarterRail above.
private struct HomeEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TunerLabel(text: "● NO CHANNELS TUNED", color: .offscriptFnInfo)
            Text("Add three shows you trust")
                .font(.system(size: 22, weight: .semibold))
                .tracking(0)
                .foregroundStyle(Color.offscriptPaperWhite)
            Text("OffScript will build a feed that feels curated, not algorithmic. Open Search to find your first three.")
                .font(.system(size: 13.5))
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineSpacing(2)

            NavigationLink {
                SearchView()
            } label: {
                HStack {
                    TunerLabel(text: "→ BROWSE SEARCH", color: .offscriptSignalYellow, size: 11)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, OffScriptTheme.pagePadding)
        .padding(.top, 24)
    }
}

private struct HomeSkeletonStack: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Hero placeholder
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(Color.offscriptFillSubtle)
                    .frame(height: 200)
                VStack(alignment: .leading, spacing: 8) {
                    Rectangle().fill(Color.offscriptFillSubtle).frame(height: 14)
                    Rectangle().fill(Color.offscriptFillSubtle).frame(width: 240, height: 14)
                }
                .padding(14)
            }
            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
            .padding(.horizontal, OffScriptTheme.pagePadding)
            .shimmer()

            // Rail header placeholder
            VStack(alignment: .leading, spacing: 10) {
                Rectangle().fill(Color.offscriptFillSubtle).frame(width: 130, height: 9)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.offscriptFillSubtle)
                                .frame(width: 180, height: 200)
                                .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                }
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)
            .shimmer()
        }
        .padding(.top, 8)
    }
}

private struct HomeDiscoveryLoadingStrip: View {
    var body: some View {
        HStack(spacing: 8) {
            TunerLabel(text: "○ SCANNING NEW FREQUENCIES", color: .offscriptSoftPaper, size: 9)
            Spacer()
        }
        .padding(.vertical, 12)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
    }
}

private struct TunerDiscoveryRail: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var subscribed: [Podcast]
    @State private var importingID: String?
    @State private var addedIDs: Set<String> = []
    @State private var errorMessage: String?

    let section: HomeFeedSection
    private let syncService = FeedSyncService()

    private var subscribedFeedURLs: Set<String> {
        Set(subscribed.filter(\.isSubscribed).map { $0.feedURL.normalizedFeedKey })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                HStack {
                    TunerLabel(text: section.title.uppercased(), color: .offscriptFnInfo)
                    Spacer()
                    TunerLabel(text: "NEW CHANNELS", color: .offscriptSoftPaper, size: 8)
                }
                Text(section.subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.offscriptPaperWhite.opacity(0.72))
                    .lineSpacing(2)
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(section.discoveryResults) { scored in
                        discoveryCard(scored)
                    }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.offscriptFnRecord)
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                    .transition(.opacity)
            }
        }
    }

    private func discoveryCard(_ scored: ScoredDiscoveryResult) -> some View {
        let result = scored.result
        let key = result.feedURL.normalizedFeedKey
        let isAdded = addedIDs.contains(key) || subscribedFeedURLs.contains(key)
        let isImporting = importingID == key
        let displayReason = RecommendationExplainer.authoredReason(
            fallback: scored.explanation,
            signals: scored.signalTrace
        )

        return VStack(alignment: .leading, spacing: 8) {
            OffScriptArtworkView(url: result.artworkURL, cornerRadius: 3)
                .frame(width: 168, height: 168)
                .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

            TunerLabel(text: result.author.uppercased(), color: .offscriptFnInfo, size: 8)
                .lineLimit(1)

            Text(result.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 168, alignment: .leading)

            TunerRailReasonTag(text: displayReason, color: .offscriptFnInfo)
            RecommendationSignalTraceView(signals: scored.signalTrace, limit: 1, color: .offscriptSoftPaper)

            Button {
                Task { await add(scored.result) }
            } label: {
                TunerLabel(
                    text: isAdded ? "✓ TUNED" : (isImporting ? "○ TUNING…" : "+ TUNE"),
                    color: isAdded ? .offscriptFnMode : .offscriptSignalYellow,
                    size: 10
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .overlay(
                    Rectangle().stroke(isAdded ? Color.offscriptFnMode : Color.offscriptSignalYellow, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isAdded || isImporting)
            .padding(.top, 2)
        }
        .frame(width: 168, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.title) from \(result.author). \(displayReason)")
    }

    @MainActor
    private func add(_ result: PodcastSearchResult) async {
        let key = result.feedURL.normalizedFeedKey
        importingID = key
        defer { importingID = nil }
        errorMessage = nil

        do {
            _ = try syncService.subscribeThenHydrate(from: result, into: modelContext, episodeLimit: 25)
            addedIDs.insert(key)
        } catch {
            homeLogger.error("Discovery add failed for \(result.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't tune \(result.title). Try Search if the feed moved."
        }
    }
}

// MARK: - Hero card

private struct HeroTunerCard: View {
    @Environment(\.modelContext) private var modelContext

    let episode: Episode
    let reason: String
    let signals: [RecommendationSignal]
    @State private var feedbackStatusMessage: String?
    @State private var feedbackClearTask: Task<Void, Never>?
    @State private var showsFeedbackActions = false

    private var progressValue: Double {
        guard let duration = episode.duration, duration > 0 else { return 0 }
        return episode.playedPosition / duration
    }

    private var displayReason: String {
        RecommendationExplainer.authoredReason(fallback: reason, signals: signals)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header strip — two TunerLabels mirroring the spec-sheet header
            HStack(spacing: 8) {
                TunerLabel(text: "● HEADLINE", color: .offscriptSignalYellow)
                Spacer()
                TunerLabel(text: episode.podcast.title.uppercased(), color: .offscriptFnInfo)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // Artwork — flat, sharp corners (3pt), hairline border
            OffScriptArtworkView(
                url: episode.artworkURL ?? episode.podcast.artworkURL,
                cornerRadius: 3
            )
            .frame(height: 200)
            .clipped()
            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
            .padding(.horizontal, 14)

            // Title + reason
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink {
                    EpisodeDetailView(
                        episode: episode,
                        recommendationReason: displayReason,
                        recommendationSignals: signals
                    )
                } label: {
                    Text(episode.title)
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(0)
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)

                // Reason as a TunerTag with signal yellow accent
                TunerTag(text: displayReason, color: .offscriptSignalYellow, dim: true, wraps: true)
                RecommendationSignalTraceView(signals: signals)
                HomePreferenceStatusRow(message: feedbackStatusMessage)

                // Mono metadata — date · duration. The "X LEFT" remaining
                // time used to render here AND in the explanation tag above
                // (`reason`), which produced two adjacent rows both saying
                // "15M LEFT" — visual overlap of meaning. The tag already
                // covers remaining-time when there's progress, so this row
                // sticks to date + duration only.
                HStack(spacing: 10) {
                    TunerLabel(text: metadata, color: .offscriptSoftPaper)
                        .lineLimit(1)
                    Spacer()
                }

                if progressValue > 0 {
                    GeometryReader { proxy in
                        let clamped = min(max(progressValue, 0), 1)
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.offscriptHairline)
                            Rectangle()
                                .fill(Color.offscriptSignalYellow)
                                .frame(width: proxy.size.width * clamped)
                        }
                    }
                    .frame(height: 1)
                }

                // Tuner action keys — flat hairline-bordered, mono labels
                HStack(spacing: 8) {
                    tunerKey(
                        title: episode.playedPosition > 0 ? "→ RESUME" : "→ PLAY",
                        color: .offscriptSignalYellow
                    ) {
                        PlaybackController.shared.play(episode, in: modelContext)
                    }

                    tunerKey(
                        title: episode.isQueued ? "✓ QUEUED" : "+ QUEUE",
                        color: episode.isQueued ? .offscriptSoftPaper : .offscriptPaperWhite,
                        disabled: episode.isQueued
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            do { try QueueService.add(episode, in: modelContext) }
                            catch { homeLogger.error("Failed to queue: \(error.localizedDescription, privacy: .public)") }
                        }
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            showsFeedbackActions.toggle()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.offscriptSignalYellow)
                            .frame(width: 38, height: 32)
                            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                    }
                    .accessibilityLabel("More actions")
                    .accessibilityHint(showsFeedbackActions ? "Double-tap to hide feedback actions." : "Double-tap to show feedback actions.")
                }
                .padding(.top, 4)

                if showsFeedbackActions {
                    HStack(spacing: 8) {
                        preferenceKey("LIKE", color: .offscriptSignalYellow) { registerAndCollapse(.like) }
                        preferenceKey("MORE", color: .offscriptFnInfo) { registerAndCollapse(.moreLikeThis) }
                        preferenceKey("LESS", color: .offscriptSoftPaper) { registerAndCollapse(.lessLikeThis) }
                        preferenceKey("HIDE", color: .offscriptFnRecord) { registerAndCollapse(.notInterested) }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(14)
        }
        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(episode.title) from \(episode.podcast.title). \(displayReason)")
        .onChange(of: episode.id) { _, _ in
            showsFeedbackActions = false
        }
        .onDisappear { feedbackClearTask?.cancel() }
    }

    @ViewBuilder
    private func tunerKey(
        title: String,
        color: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            TunerLabel(text: title, color: color.opacity(disabled ? 0.5 : 1.0), size: 10)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .overlay(Rectangle().stroke(color.opacity(disabled ? 0.3 : 1.0), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var metadata: String {
        let dateString = episode.pubDate.formatted(date: .abbreviated, time: .omitted)
        if let duration = episode.duration {
            return "\(dateString) · \(EpisodeDurationFormatter.short(duration))".uppercased()
        }
        return dateString.uppercased()
    }

    private var timeRemaining: String {
        guard let duration = episode.duration else { return "IN PROGRESS" }
        let remaining = max(0, duration - episode.playedPosition)
        return "\(EpisodeDurationFormatter.short(remaining)) LEFT".uppercased()
    }

    private func register(_ action: PreferenceSignal.Action) {
        let signal = PreferenceSignal(action: action, episode: episode)
        modelContext.insert(signal)
        do {
            try modelContext.save()
            withAnimation(.easeInOut(duration: 0.18)) {
                feedbackStatusMessage = statusMessage(for: action)
            }
            scheduleFeedbackStatusClear()
            NotificationCenter.default.post(name: .offscriptRecommendationFeedbackChanged, object: nil)
        } catch {
            modelContext.delete(signal)
            homeLogger.error("Failed to save preference: \(error.localizedDescription, privacy: .public)")
            withAnimation(.easeInOut(duration: 0.18)) {
                feedbackStatusMessage = "COULDN'T SAVE SIGNAL"
            }
            scheduleFeedbackStatusClear(delay: 3_000_000_000)
        }
    }

    private func registerAndCollapse(_ action: PreferenceSignal.Action) {
        register(action)
        withAnimation(.easeInOut(duration: 0.16)) {
            showsFeedbackActions = false
        }
    }

    private func preferenceKey(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TunerLabel(text: title, color: color, size: 9)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(minHeight: 44)
                .overlay(Rectangle().stroke(color.opacity(0.65), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusMessage(for action: PreferenceSignal.Action) -> String {
        switch action {
        case .like: "LIKED · RETUNING"
        case .moreLikeThis: "MORE LIKE THIS · RETUNING"
        case .lessLikeThis: "LESS LIKE THIS · RETUNING"
        case .notInterested: "HIDDEN FROM SIGNAL · RETUNING"
        }
    }

    private func scheduleFeedbackStatusClear(delay: UInt64 = 2_000_000_000) {
        feedbackClearTask?.cancel()
        feedbackClearTask = Task {
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) {
                    feedbackStatusMessage = nil
                }
            }
        }
    }
}

private struct HomePreferenceStatusRow: View {
    let message: String?

    var body: some View {
        if let message {
            TunerLabel(text: message, color: .offscriptFnMode, size: 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - Tuner rail

private struct TunerRail: View {
    let title: String
    let episodes: [Episode]
    let reasonProvider: (Episode) -> String
    let signalProvider: (Episode) -> [RecommendationSignal]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Hairline rule + TunerLabel header
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                TunerLabel(text: title, color: .offscriptSignalYellow)
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(episodes) { episode in
                        TunerRailCard(
                            episode: episode,
                            reason: reasonProvider(episode),
                            signals: signalProvider(episode)
                        )
                    }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)
            }
        }
    }
}

private struct TunerRailCard: View {
    @Environment(\.modelContext) private var modelContext
    let episode: Episode
    let reason: String
    let signals: [RecommendationSignal]

    private var displayReason: String {
        RecommendationExplainer.authoredReason(fallback: reason, signals: signals)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                EpisodeDetailView(
                    episode: episode,
                    recommendationReason: displayReason,
                    recommendationSignals: signals
                )
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    OffScriptArtworkView(url: episode.artworkURL ?? episode.podcast.artworkURL, cornerRadius: 3)
                        .frame(width: 168, height: 168)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

                    TunerLabel(text: episode.podcast.title.uppercased(), color: .offscriptFnInfo, size: 8)
                        .lineLimit(1)

                    Text(episode.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(width: 168, alignment: .leading)

                    TunerRailReasonTag(text: displayReason, color: .offscriptSignalYellow)
                    RecommendationSignalTraceView(signals: signals, limit: 1, color: .offscriptSoftPaper)

                    TunerLabel(text: metadata, color: .offscriptSoftPaper, size: 8)
                }
            }
            .buttonStyle(.plain)

            // Sharp action row — single signal-yellow play key + queue toggle
            HStack(spacing: 6) {
                Button {
                    PlaybackController.shared.play(episode, in: modelContext)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.offscriptStudioBlack)
                        .frame(width: 30, height: 30)
                        .background(Color.offscriptSignalYellow)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(episode.title)")

                Button {
                    do { try QueueService.add(episode, in: modelContext) }
                    catch { homeLogger.error("Queue add failed: \(error.localizedDescription, privacy: .public)") }
                } label: {
                    Image(systemName: episode.isQueued ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .frame(width: 30, height: 30)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(episode.isQueued)
                .accessibilityLabel(episode.isQueued ? "Already queued" : "Add to queue")

                Spacer()
            }
            .padding(.top, 8)
        }
        .padding(10)
        .frame(width: 188, alignment: .leading)
        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(episode.title) from \(episode.podcast.title). \(displayReason)")
    }

    private var metadata: String {
        let dateString = episode.pubDate.formatted(date: .abbreviated, time: .omitted).uppercased()
        if let duration = episode.duration {
            return "\(dateString) · \(EpisodeDurationFormatter.short(duration).uppercased())"
        }
        return dateString
    }
}

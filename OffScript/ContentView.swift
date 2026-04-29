import CoreSpotlight
import OSLog
import SwiftData
import SwiftUI

private let appLogger = Logger(subsystem: "com.offscript", category: "App")

// MARK: - Tab identity (typed enum, not raw Int)

private enum AppTab: Int, CaseIterable, Identifiable {
    case home, library, queue, search

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .home:    return "HOME"
        case .library: return "LIBRARY"
        case .queue:   return "QUEUE"
        case .search:  return "SEARCH"
        }
    }

    var systemImage: String {
        switch self {
        case .home:    return "waveform.path.ecg"
        case .library: return "books.vertical"
        case .queue:   return "text.badge.plus"
        case .search:  return "magnifyingglass"
        }
    }

    /// Match the name encoded in `offscript://tab/<name>` deep links.
    static func from(deepLinkName: String) -> AppTab? {
        switch deepLinkName.lowercased() {
        case "home":    return .home
        case "library": return .library
        case "queue":   return .queue
        case "search":  return .search
        default:        return nil
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var player = PlaybackController.shared
    @AppStorage("offscript.hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var selectedTab: AppTab = .home
    @State private var isSettingsPresented = false
    @Query private var queueItems: [QueueItem]

    var body: some View {
        Group {
            if hasSeenOnboarding {
                // Custom Tuner shell — replaces SwiftUI's TabView. iOS 26's
                // TabView ignores UITabBarAppearance and forces the floating
                // Liquid Glass capsule, which clashes hard with the Tuner
                // instrument-cluster vocabulary every other surface uses.
                // Going custom keeps full control of the tab bar's shape,
                // colors, hairlines, and how it docks against MiniPlayer.
                VStack(spacing: 0) {
                    activeTabContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if player.currentEpisode != nil {
                        MiniPlayer()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    TunerTabBar(
                        selection: $selectedTab,
                        queueBadge: queueItems.count
                    )
                }
                .background(Color.offscriptStudioBlack.ignoresSafeArea())
                .animation(.easeInOut(duration: 0.2), value: player.currentEpisode != nil)
                .fullScreenCover(isPresented: $player.isPlayerPresented) {
                    PlayerView()
                        .tunerModalSurface()
                }
                .sheet(isPresented: $isSettingsPresented) {
                    SettingsView()
                        .tunerModalSurface()
                }
            } else {
                OnboardingFlowView {
                    hasSeenOnboarding = true
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            PlaybackController.shared.configure(context: modelContext)

            SpotlightIndexer.indexEpisodes(in: modelContext)
            NowPlayingPublisher.shared.start()
            BackgroundTranscriptionService.shared.configure(context: modelContext)

            #if DEBUG
            configureDebugSeedDataIfNeeded()
            configureDebugSelectedTabIfNeeded()
            configureDebugPlaybackIfNeeded()
            #endif
        }
        .onOpenURL { url in
            DeepLinkRouter.handle(url, in: modelContext)
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let uniqueID = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let url = URL(string: "offscript://episode/\(uniqueID)") else { return }
            DeepLinkRouter.handle(url, in: modelContext)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Fire sleep timer immediately if its deadline passed while
            // the app was suspended. The Task.sleep loop inside the timer
            // pauses with the app, so a 5-minute timer set, then 6 minutes
            // of background later, would otherwise wait until the loop
            // wakes up to act.
            if newPhase == .active {
                player.reevaluateSleepTimerOnForeground()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .offscriptSwitchTab)) { note in
            // offscript://tab/<name> deep links land here. The router posts
            // the notification; ContentView is the only piece that knows
            // which tab is selected, so the routing happens at this layer.
            guard let name = note.userInfo?["tab"] as? String,
                  let tab = AppTab.from(deepLinkName: name) else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        }
    }

    /// Switch on the typed tab so the compiler enforces exhaustive routing.
    /// Each tab gets its own NavigationStack so back-stacks survive tab
    /// switches.
    @ViewBuilder
    private var activeTabContent: some View {
        switch selectedTab {
        case .home:
            NavigationStack {
                HomeView(onOpenSettings: { isSettingsPresented = true })
            }
        case .library:
            NavigationStack {
                LibraryView(onOpenSettings: { isSettingsPresented = true })
            }
        case .queue:
            NavigationStack {
                QueueView()
            }
        case .search:
            NavigationStack {
                SearchView()
            }
        }
    }
}

// MARK: - Tuner tab bar

/// Replaces SwiftUI's TabView with a flat instrument-cluster-style tab bar.
/// Top hairline rule, sharp 0pt corners, mono labels via TunerLabel,
/// signal-yellow active state, soft-paper inactive. Queue tab gets a small
/// signal-yellow stacked-count badge above the icon when items are queued.
private struct TunerTabBar: View {
    @Binding var selection: AppTab
    let queueBadge: Int

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.offscriptHairline)
                .frame(height: 1)

            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    Button {
                        selection = tab
                    } label: {
                        tabContent(for: tab)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(tab.label.capitalized)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
            .background(Color.offscriptStudioBlack)
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        let isActive = (selection == tab)
        let color: Color = isActive ? .offscriptSignalYellow : .offscriptSoftPaper

        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 22)

                if tab == .queue, queueBadge > 0 {
                    Text("\(min(queueBadge, 99))")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.offscriptStudioBlack)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.offscriptSignalYellow)
                        .offset(x: 12, y: -4)
                        .accessibilityLabel("\(queueBadge) queued")
                }
            }

            TunerLabel(text: tab.label, color: color, size: 8)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if isActive {
                // 1px signal-yellow active indicator at the top of the cell —
                // matches the function-coded eyebrow rules used everywhere else.
                Rectangle()
                    .fill(Color.offscriptSignalYellow)
                    .frame(width: 36, height: 1)
                    .offset(y: -6)
            }
        }
    }
}

#if DEBUG
private extension ContentView {
    /// One-shot seeder for sim/dev: launch with -offscript.debugSeedSampleData YES
    /// (and optionally -offscript.debugSeedLibrarySize 250) to populate a
    /// deterministic library for visual/performance audits without onboarding.
    /// No-ops once data exists.
    func configureDebugSeedDataIfNeeded() {
        let defaults = UserDefaults.standard
        let requestedLibrarySize = max(0, defaults.integer(forKey: "offscript.debugSeedLibrarySize"))
        guard defaults.bool(forKey: "offscript.debugSeedSampleData") || requestedLibrarySize > 0 else { return }

        if requestedLibrarySize > 0 {
            let episodesPerShow = max(1, defaults.integer(forKey: "offscript.debugSeedEpisodesPerShow"))
            let existingEpisodes = (try? modelContext.fetchCount(FetchDescriptor<Episode>())) ?? 0
            guard debugLargeLibraryNeedsReset(
                requestedLibrarySize: requestedLibrarySize,
                expectedEpisodes: requestedLibrarySize * episodesPerShow,
                existingEpisodes: existingEpisodes
            ) else { return }
            resetDebugLibrary()
            seedLargeDebugLibrary(
                showCount: requestedLibrarySize,
                episodesPerShow: episodesPerShow
            )
            return
        }

        let existing = (try? modelContext.fetchCount(FetchDescriptor<Podcast>())) ?? 0
        guard existing == 0 else { return }

        let samples: [(title: String, author: String, summary: String, feed: String, art: String, categories: [String])] = [
            ("Conan O'Brien Needs A Friend", "Team Coco", "Long-form chats with Conan and friends.",
             "https://feeds.simplecast.com/dHoohVNH", "https://image.simplecastcdn.com/images/conan.jpg",
             ["Comedy", "Interviews"]),
            ("Lex Fridman Podcast", "Lex Fridman", "Conversations on AI, science, and consciousness.",
             "https://lexfridman.com/feed/podcast/", "https://image.simplecastcdn.com/images/lex.jpg",
             ["Science", "Tech"]),
            ("Radiolab", "WNYC Studios", "Investigating a strange world.",
             "https://feeds.simplecast.com/EmVW7VGp", "https://image.simplecastcdn.com/images/radiolab.jpg",
             ["Science", "Storytelling"])
        ]

        for sample in samples {
            let pod = Podcast(
                title: sample.title,
                author: sample.author,
                summary: sample.summary,
                feedURL: URL(string: sample.feed) ?? URL(string: "https://placeholder.invalid")!,
                artworkURL: URL(string: sample.art),
                categories: sample.categories,
                isSubscribed: true
            )
            modelContext.insert(pod)

            for i in 0..<3 {
                let ep = Episode(
                    guid: "\(sample.title)-\(i)",
                    title: "\(sample.title) — Episode \(i + 1)",
                    summary: "Sample episode \(i + 1) for \(sample.title). "
                        + String(repeating: "Body text. ", count: 12),
                    pubDate: Calendar.current.date(byAdding: .day, value: -i * 3, to: Date()) ?? Date(),
                    duration: TimeInterval(1500 + i * 600),
                    audioURL: URL(string: "https://placeholder.invalid/sample/\(i).mp3")!,
                    artworkURL: URL(string: sample.art),
                    podcast: pod
                )
                modelContext.insert(ep)

                if i == 0 {
                    ep.playedPosition = 600
                    ep.lastPlayedAt = Date()
                }
            }
        }

        try? modelContext.save()
    }

    private func debugLargeLibraryNeedsReset(
        requestedLibrarySize: Int,
        expectedEpisodes: Int,
        existingEpisodes: Int
    ) -> Bool {
        let podcastDescriptor = FetchDescriptor<Podcast>(
            sortBy: [SortDescriptor(\Podcast.title)]
        )
        guard let existingPodcasts = try? modelContext.fetch(podcastDescriptor) else {
            return true
        }
        guard existingPodcasts.count == requestedLibrarySize, existingEpisodes == expectedEpisodes else {
            return true
        }
        return existingPodcasts.first?.title != "A Channel 001"
    }

    private func resetDebugLibrary() {
        for episode in (try? modelContext.fetch(FetchDescriptor<Episode>())) ?? [] {
            modelContext.delete(episode)
        }
        for podcast in (try? modelContext.fetch(FetchDescriptor<Podcast>())) ?? [] {
            modelContext.delete(podcast)
        }
        try? modelContext.save()
    }

    private func seedLargeDebugLibrary(showCount: Int, episodesPerShow: Int) {
        let categories = ["News", "Tech", "Comedy", "Science", "Culture", "Storytelling"]
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        for index in 0..<showCount {
            let channel = "\(alphabet[index % alphabet.count]) Channel \(String(format: "%03d", index + 1))"
            let pod = Podcast(
                title: channel,
                author: "Debug Network \(index % 12 + 1)",
                summary: "Deterministic large-library seed for scroll, search, sort, and alphabet jump QA.",
                feedURL: URL(string: "https://debug.offscript.invalid/feeds/\(index + 1).xml")!,
                artworkURL: nil,
                categories: [categories[index % categories.count]],
                isSubscribed: true
            )
            modelContext.insert(pod)

            for episodeIndex in 0..<episodesPerShow {
                let episode = Episode(
                    guid: "debug-\(index + 1)-\(episodeIndex + 1)",
                    title: "\(channel) Episode \(episodeIndex + 1)",
                    summary: "Synthetic episode for large-library UI validation.",
                    pubDate: Calendar.current.date(byAdding: .hour, value: -(index * episodesPerShow + episodeIndex), to: Date()) ?? Date(),
                    duration: TimeInterval(900 + (episodeIndex % 6) * 300),
                    audioURL: URL(string: "https://debug.offscript.invalid/audio/\(index + 1)-\(episodeIndex + 1).mp3")!,
                    artworkURL: nil,
                    podcast: pod
                )
                if episodeIndex == 0, index % 5 == 0 {
                    episode.playedPosition = 300
                    episode.lastPlayedAt = Date()
                }
                modelContext.insert(episode)
            }
        }
        try? modelContext.save()
    }

    /// Read launch args / UserDefaults that may arrive as Int, NSNumber,
    /// or String depending on how iOS bridged the `-key value` pair.
    /// Returns the AppTab or nil. Without this fallback chain, args set
    /// via `xcrun simctl launch ... -offscript.debugLaunchTab 1` were
    /// silently ignored because `as? Int` against an NSNumber-bridged
    /// UserDefault sometimes fails.
    private func tabFromLaunchArg(key: String) -> AppTab? {
        let defaults = UserDefaults.standard
        let raw = defaults.object(forKey: key)
        let asInt: Int?
        if let i = raw as? Int { asInt = i }
        else if let n = raw as? NSNumber { asInt = n.intValue }
        else if let s = raw as? String, let i = Int(s) { asInt = i }
        else { asInt = nil }
        guard let i = asInt else { return nil }
        return AppTab(rawValue: i)
    }

    func configureDebugSelectedTabIfNeeded() {
        if let tab = tabFromLaunchArg(key: "offscript.debugSelectedTab") {
            selectedTab = tab
        }
    }

    func configureDebugPlaybackIfNeeded() {
        let defaults = UserDefaults.standard
        if let tab = tabFromLaunchArg(key: "offscript.debugLaunchTab") {
            selectedTab = tab
        }

        guard defaults.bool(forKey: "offscript.debugBootPlayback") else { return }
        guard PlaybackController.shared.currentEpisode == nil else { return }

        var descriptor = FetchDescriptor<Episode>(
            sortBy: [SortDescriptor(\Episode.pubDate, order: .reverse)]
        )
        descriptor.fetchLimit = 4

        guard let episodes = try? modelContext.fetch(descriptor), let leadEpisode = episodes.first else { return }

        for episode in episodes.dropFirst().prefix(2) where !episode.isQueued {
            try? QueueService.add(episode, in: modelContext)
        }

        let targetDuration = leadEpisode.duration ?? 2_400
        let targetPosition = min(max(targetDuration * 0.36, 240), targetDuration * 0.85)

        PlaybackController.shared.debugPrimePlayback(
            episode: leadEpisode,
            duration: targetDuration,
            currentTime: targetPosition,
            isPlaying: defaults.object(forKey: "offscript.debugBootIsPlaying") as? Bool ?? true,
            presentPlayer: defaults.bool(forKey: "offscript.debugPresentPlayer")
        )
    }
}
#endif

#Preview {
    ContentView()
        .modelContainer(for: [
            Podcast.self,
            Episode.self,
            EpisodeProfile.self,
            PlaybackEvent.self,
            PreferenceSignal.self,
            QueueItem.self,
            EpisodeTranscriptCache.self
        ], inMemory: true)
}

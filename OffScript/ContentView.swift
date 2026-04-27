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
                }
                .sheet(isPresented: $isSettingsPresented) {
                    SettingsView()
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
                        .foregroundStyle(.black)
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
    func configureDebugSelectedTabIfNeeded() {
        let defaults = UserDefaults.standard
        guard let value = defaults.object(forKey: "offscript.debugSelectedTab") as? Int else { return }
        guard let tab = AppTab(rawValue: value) else { return }
        selectedTab = tab
    }

    func configureDebugPlaybackIfNeeded() {
        let defaults = UserDefaults.standard
        if let tabValue = defaults.object(forKey: "offscript.debugLaunchTab") as? Int,
           let tab = AppTab(rawValue: tabValue) {
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

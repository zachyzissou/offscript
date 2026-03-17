import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var player = PlaybackController.shared
    @AppStorage("offscript.hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var selectedTab = 0
    @State private var isSettingsPresented = false
    @State private var miniPlayerHeight: CGFloat = 0
    @Query private var queueItems: [QueueItem]

    var body: some View {
        Group {
            if hasSeenOnboarding {
                GeometryReader { proxy in
                    let bottomSafeArea = proxy.safeAreaInsets.bottom
                    let miniPlayerInset = player.currentEpisode != nil ? miniPlayerHeight + 20 : 0

                    TabView(selection: $selectedTab) {
                        NavigationStack {
                            HomeView(onOpenSettings: { isSettingsPresented = true })
                        }
                        .tag(0)
                        .tabItem {
                            Label("Home", systemImage: "waveform.path.ecg")
                        }

                        NavigationStack {
                            LibraryView(onOpenSettings: { isSettingsPresented = true })
                        }
                        .tag(1)
                        .tabItem {
                            Label("Library", systemImage: "books.vertical")
                        }

                        NavigationStack {
                            QueueView()
                        }
                        .tag(2)
                        .tabItem {
                            Label("Queue", systemImage: "text.badge.plus")
                        }
                        .badge(queueItems.count > 0 ? queueItems.count : 0)

                        NavigationStack {
                            SearchView()
                        }
                        .tag(3)
                        .tabItem {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                    }
                    .tint(Color.offscriptAccent)
                    .background(alignment: .bottom) {
                        Color.offscriptBackgroundBottom
                            .frame(height: player.currentEpisode != nil ? miniPlayerHeight + bottomSafeArea + 36 : bottomSafeArea + 96)
                            .ignoresSafeArea(edges: .bottom)
                    }
                    .toolbarBackground(Color.offscriptCardUtility.opacity(0.98), for: .tabBar)
                    .toolbarBackground(.visible, for: .tabBar)
                    .toolbarColorScheme(.dark, for: .tabBar)
                    .safeAreaInset(edge: .bottom) {
                        if player.currentEpisode != nil {
                            Color.clear.frame(height: miniPlayerInset + 12)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if player.currentEpisode != nil {
                            MiniPlayer()
                                .measureHeight($miniPlayerHeight)
                                .padding(.bottom, bottomSafeArea + 8)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.86), value: player.currentEpisode != nil)
                    .sheet(isPresented: $player.isPlayerPresented) {
                        PlayerView()
                    }
                    .sheet(isPresented: $isSettingsPresented) {
                        SettingsView()
                    }
                }
            } else {
                OnboardingFlowView()
            }
        }
        .preferredColorScheme(.dark)
        .task {
            PlaybackController.shared.configure(context: modelContext)
            #if DEBUG
            configureDebugSelectedTabIfNeeded()
            configureDebugPlaybackIfNeeded()
            #endif
        }
    }
}

#if DEBUG
private extension ContentView {
    func configureDebugSelectedTabIfNeeded() {
        let defaults = UserDefaults.standard
        guard let value = defaults.object(forKey: "offscript.debugSelectedTab") as? Int else { return }
        guard (0...3).contains(value) else { return }
        selectedTab = value
    }

    func configureDebugPlaybackIfNeeded() {
        let defaults = UserDefaults.standard
        if let tabValue = defaults.object(forKey: "offscript.debugLaunchTab") as? Int {
            selectedTab = min(max(tabValue, 0), 3)
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
            QueueItem.self
        ], inMemory: true)
}

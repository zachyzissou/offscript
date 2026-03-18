import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var player = PlaybackController.shared
    @State private var hasSeenOnboarding = AppSettings.hasSeenOnboarding
    @State private var selectedTab = 0
    @State private var isSettingsPresented = false
    @State private var miniPlayerHeight: CGFloat = 0
    @State private var networkMonitor = NetworkMonitor.shared
    @Query private var queueItems: [QueueItem]

    var body: some View {
        Group {
            if hasSeenOnboarding {
                GeometryReader { proxy in
                    let bottomSafeArea = proxy.safeAreaInsets.bottom
                    let miniPlayerInset = player.currentEpisode != nil ? miniPlayerHeight + 28 : 0

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
                            .frame(height: player.currentEpisode != nil ? miniPlayerHeight + bottomSafeArea + 72 : bottomSafeArea + 96)
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
                                .contentShape(Rectangle())
                                .measureHeight($miniPlayerHeight)
                                .padding(.bottom, bottomSafeArea + 56)
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
                OnboardingFlowView {
                    hasSeenOnboarding = true
                }
            }
        }
        .overlay(alignment: .top) {
            if !networkMonitor.isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.caption.weight(.semibold))
                    Text("No connection")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.offscriptTextPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.offscriptDestructive.opacity(0.9))
                .clipShape(Capsule())
                .padding(.top, 52)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.35), value: networkMonitor.isConnected)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            PlaybackController.shared.configure(context: modelContext)
            SyncCoordinator.shared.configure(context: modelContext)
            DownloadService.shared.configure(context: modelContext)
            #if DEBUG
            configureDebugSelectedTabIfNeeded()
            configureDebugPlaybackIfNeeded()
            #endif
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active, hasSeenOnboarding else { return }
            SyncCoordinator.shared.scheduleForegroundRefreshIfNeeded()
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
            QueueItem.self,
            UserTasteProfile.self,
            TelemetryEvent.self
        ], inMemory: true)
}

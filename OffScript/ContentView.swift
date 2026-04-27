import OSLog
import SwiftData
import SwiftUI

private let appLogger = Logger(subsystem: "com.offscript", category: "App")

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var player = PlaybackController.shared
    @AppStorage("offscript.hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var selectedTab = 0
    @State private var isSettingsPresented = false
    @Query private var queueItems: [QueueItem]

    var body: some View {
        Group {
            if hasSeenOnboarding {
                // Previously this whole tree was wrapped in a GeometryReader so we
                // could push a tinted background behind the tab bar at exactly the
                // right safe-area height. The trade was bad: GeometryReader at the
                // root invalidates the entire TabView (and every child screen) on
                // every layout pass, making tab-switching feel sluggish once the
                // library has any real content.
                //
                // Replaced with native primitives:
                //   - .safeAreaInset(edge: .bottom) for the MiniPlayer slot
                //   - SwiftUI's own safe-area for the tab bar tint
                // No more root-level GeometryReader.
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        HomeView(onOpenSettings: { isSettingsPresented = true })
                    }
                    .tag(0)
                    .tabItem { Label("Home", systemImage: "waveform.path.ecg") }

                    NavigationStack {
                        LibraryView(onOpenSettings: { isSettingsPresented = true })
                    }
                    .tag(1)
                    .tabItem { Label("Library", systemImage: "books.vertical") }

                    NavigationStack {
                        QueueView()
                    }
                    .tag(2)
                    .tabItem { Label("Queue", systemImage: "text.badge.plus") }
                    .badge(queueItems.count > 0 ? queueItems.count : 0)

                    NavigationStack {
                        SearchView()
                    }
                    .tag(3)
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                }
                .tint(Color.offscriptAccent)
                .toolbarBackground(Color.offscriptCardUtility.opacity(0.98), for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarColorScheme(.dark, for: .tabBar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // MiniPlayer slot — empty when nothing is playing so the tab
                    // bar takes its natural height.
                    if player.currentEpisode != nil {
                        MiniPlayer()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: player.currentEpisode != nil)
                .fullScreenCover(isPresented: $player.isPlayerPresented) {
                    PlayerView()
                }
                .sheet(isPresented: $isSettingsPresented) {
                    SettingsView()
                }
            } else {
                // Local renamed OnboardingView -> OnboardingFlowView (commit f314adf:
                // "remove old OnboardingView") and the new flow doesn't have a
                // jump-to-search affordance — onComplete is parameterless.
                OnboardingFlowView {
                    hasSeenOnboarding = true
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            PlaybackController.shared.configure(context: modelContext)
            // SampleDataSeeder was removed in local commit 7ab11e8
            // ("wire up OnboardingFlowView and remove SampleDataSeeder").
            // Real onboarding flow now seeds via Genre + Podcast picker.
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

        guard let episodes = try? modelContext.fetch(descriptor), let leadEpisode = episodes.first else { return } // debug-only fetch, safe to ignore

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

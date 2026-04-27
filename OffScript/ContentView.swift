import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var player = PlaybackController.shared
    @State private var hasSeenOnboarding = AppSettings.hasSeenOnboarding
    @State private var selectedTab = 0
    @State private var isSettingsPresented = false
    @State private var networkMonitor = NetworkMonitor.shared
    @Query private var queueItems: [QueueItem]

    var body: some View {
        Group {
            if hasSeenOnboarding {
                VStack(spacing: 0) {
                    // Content area — only the active tab is mounted
                    Group {
                        switch selectedTab {
                        case 0:
                            NavigationStack {
                                HomeView(onOpenSettings: { isSettingsPresented = true })
                            }
                        case 1:
                            NavigationStack {
                                LibraryView(onOpenSettings: { isSettingsPresented = true })
                            }
                        case 2:
                            NavigationStack {
                                QueueView()
                            }
                        case 3:
                            NavigationStack {
                                SearchView()
                            }
                        default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Custom tab bar
                    OffScriptTabBar(
                        selectedTab: $selectedTab,
                        queueCount: queueItems.count
                    )

                    // MiniPlayer docked at very bottom, extending into safe area
                    if player.currentEpisode != nil {
                        VStack(spacing: 0) {
                            MiniPlayer()
                            // Extend background color through the home indicator area
                            Color.offscriptCardRaised.opacity(0.98)
                                .frame(height: 34) // home indicator safe area
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .ignoresSafeArea(.container, edges: .bottom)
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: player.currentEpisode != nil)
                .sheet(isPresented: $player.isPlayerPresented) {
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
            // Donate subscribed-show episodes to Spotlight so iOS system
            // search and Siri Suggestions can surface them. Idempotent.
            SpotlightIndexer.indexEpisodes(in: modelContext)
            // Bridge PlaybackController → widgets + Live Activity. Idempotent.
            NowPlayingPublisher.shared.start()
            #if DEBUG
            configureDebugSelectedTabIfNeeded()
            configureDebugPlaybackIfNeeded()
            #endif
        }
        .onChange(of: scenePhase) { _, newValue in
            switch newValue {
            case .active:
                guard hasSeenOnboarding else { return }
                SyncCoordinator.shared.scheduleForegroundRefreshIfNeeded()
            case .background:
                BackgroundFeedRefresh.scheduleNextRefresh()
                // Cancel any pending taste-profile refresh so it doesn't fire
                // against a suspended context when the OS resumes the app.
                TasteProfileService.cancelPendingRefresh()
            default:
                break
            }
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

private struct OffScriptTabBar: View {
    @Binding var selectedTab: Int
    let queueCount: Int

    private let tabs: [(icon: String, label: String, tag: Int)] = [
        ("waveform.path.ecg", "Home", 0),
        ("books.vertical", "Library", 1),
        ("text.badge.plus", "Queue", 2),
        ("sparkle.magnifyingglass", "Discover", 3)
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.tag) { tab in
                Button {
                    selectedTab = tab.tag
                } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 18, weight: .medium))

                            if tab.tag == 2 && queueCount > 0 {
                                Text("\(queueCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.offscriptAccent)
                                    .clipShape(Capsule())
                                    .offset(x: 10, y: -6)
                            }
                        }

                        Text(tab.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == tab.tag ? Color.offscriptAccent : Color.offscriptTextMuted)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.offscriptHairline)
                .frame(height: 0.5)
        }
        .environment(\.colorScheme, .dark)
    }
}

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
            TelemetryEvent.self,
            EpisodeTranscriptCache.self
        ], inMemory: true)
}

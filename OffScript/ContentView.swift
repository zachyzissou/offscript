import CoreSpotlight
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var player = PlaybackController.shared
    @State private var hasSeenOnboarding = AppSettings.hasSeenOnboarding
    @State private var selectedTab = 0
    @State private var isSettingsPresented = false
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var pendingOPMLImport: PendingOPMLImport?
    @Query private var queueItems: [QueueItem]

    var body: some View {
        Group {
            if hasSeenOnboarding {
                if horizontalSizeClass == .regular {
                    splitLayout
                } else {
                    compactLayout
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
            DebugSeedData.seedIfNeeded(in: modelContext)
            configureDebugSelectedTabIfNeeded()
            configureDebugPlaybackIfNeeded()
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .offscriptIntentSelectTab)) { note in
            if let tab = note.userInfo?["tab"] as? Int, (0...3).contains(tab) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    selectedTab = tab
                }
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                handleSpotlightIdentifier(identifier)
            }
        }
        .onContinueUserActivity("com.offscript.app.playing") { activity in
            guard let episodeIDString = activity.userInfo?["episodeID"] as? String,
                  let episodeID = UUID(uuidString: episodeIDString) else { return }
            playEpisode(id: episodeID)
        }
        .onChange(of: scenePhase) { _, newValue in
            switch newValue {
            case .active:
                guard hasSeenOnboarding else { return }
                SyncCoordinator.shared.scheduleForegroundRefreshIfNeeded()
            case .background:
                BackgroundFeedRefresh.scheduleNextRefresh()
            default:
                break
            }
        }
        .sheet(item: $pendingOPMLImport) { item in
            OPMLImportView(initialURL: item.url)
        }
    }
}

/// Lightweight wrapper so `.sheet(item:)` has a stable `Identifiable` to track
/// (URL itself is not Identifiable in stdlib and we don't want to retroactively
/// conform it across the app).
private struct PendingOPMLImport: Identifiable {
    let id = UUID()
    let url: URL
}

private extension ContentView {
    func handleDeepLink(_ url: URL) {
        // OPML files shared from other podcast apps (Apple Podcasts, Overcast,
        // Pocket Casts, Castro) come in as `file://…/something.opml`. Route
        // them straight into the import sheet so the user lands on the
        // dedupe-aware review screen, not the file picker.
        if url.isFileURL,
           url.pathExtension.lowercased() == "opml" || (url.pathExtension.lowercased() == "xml" && url.lastPathComponent.lowercased().contains("subscriptions")) {
            pendingOPMLImport = PendingOPMLImport(url: url)
            return
        }

        guard url.scheme == "offscript" else { return }
        let host = url.host()
        let pathComponent = url.pathComponents.dropFirst().first

        switch host {
        case "podcast":
            if let component = pathComponent, let id = UUID(uuidString: component) {
                openPodcast(id: id)
            }
        case "episode":
            if let component = pathComponent, let id = UUID(uuidString: component) {
                playEpisode(id: id)
            }
        case "queue":
            selectedTab = 2
        case "discover":
            selectedTab = 3
        default:
            break
        }
    }

    func handleSpotlightIdentifier(_ identifier: String) {
        let parts = identifier.split(separator: ":")
        guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return }
        switch parts[0] {
        case "episode":
            playEpisode(id: id)
        case "podcast":
            openPodcast(id: id)
        default:
            break
        }
    }

    func playEpisode(id: UUID) {
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.id == id }
        )
        guard let episode = try? modelContext.fetch(descriptor).first else { return }
        PlaybackController.shared.play(episode, in: modelContext)
    }

    func openPodcast(id: UUID) {
        selectedTab = 1
    }
}

private extension ContentView {
    var compactLayout: some View {
        VStack(spacing: 0) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            OffScriptTabBar(
                selectedTab: $selectedTab,
                queueCount: queueItems.count
            )

            if player.currentEpisode != nil {
                VStack(spacing: 0) {
                    MiniPlayer()
                    Color.offscriptCardRaised.opacity(0.98)
                        .frame(height: 34)
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
    }

    /// iPad / wide layout: persistent sidebar on the leading edge, with the
    /// MiniPlayer docked across the bottom of the detail area.
    var splitLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if player.currentEpisode != nil {
                    Divider().background(Color.offscriptHairline)
                    MiniPlayer()
                }
            }
        }
        .sheet(isPresented: $player.isPlayerPresented) {
            PlayerView()
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
    }

    var sidebar: some View {
        List {
            Section("Library") {
                sidebarRow(0, label: "Home", systemImage: "waveform.path.ecg")
                sidebarRow(1, label: "Library", systemImage: "books.vertical")
                sidebarRow(2, label: "Queue", systemImage: "text.badge.plus", badge: queueItems.count)
                sidebarRow(3, label: "Discover", systemImage: "sparkle.magnifyingglass")
            }
        }
        .navigationTitle("OffScript")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isSettingsPresented = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Open settings")
            }
        }
    }

    func sidebarRow(_ tag: Int, label: String, systemImage: String, badge: Int = 0) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                selectedTab = tag
            }
        } label: {
            HStack {
                Label(label, systemImage: systemImage)
                    .foregroundStyle(selectedTab == tag ? Color.offscriptAccent : Color.offscriptTextPrimary)
                if badge > 0 {
                    Spacer()
                    Text("\(badge)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.offscriptAccent, in: Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(selectedTab == tag ? Color.offscriptAccentSoft : Color.clear)
    }

    @ViewBuilder
    var tabContent: some View {
        switch selectedTab {
        case 0:
            NavigationStack {
                HomeView(onOpenSettings: { isSettingsPresented = true })
                    .registerEpisodeNavigation()
            }
        case 1:
            NavigationStack {
                LibraryView(onOpenSettings: { isSettingsPresented = true })
                    .registerEpisodeNavigation()
            }
        case 2:
            NavigationStack {
                QueueView()
                    .registerEpisodeNavigation()
            }
        case 3:
            NavigationStack {
                SearchView()
                    .registerEpisodeNavigation()
            }
        default:
            EmptyView()
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
    @Namespace private var tabIndicator

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
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selectedTab = tab.tag
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 18, weight: .medium))
                                .symbolEffect(.bounce, value: selectedTab == tab.tag)

                            if tab.tag == 2 && queueCount > 0 {
                                Text("\(queueCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.offscriptAccent, in: Capsule())
                                    .offset(x: 10, y: -6)
                                    .contentTransition(.numericText())
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }

                        Text(tab.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == tab.tag ? Color.offscriptAccent : Color.offscriptTextMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background {
                        if selectedTab == tab.tag {
                            Capsule(style: .continuous)
                                .fill(Color.offscriptAccent.opacity(0.12))
                                .matchedGeometryEffect(id: "tab.indicator", in: tabIndicator)
                                .padding(.horizontal, 8)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
                .sensoryFeedback(.selection, trigger: selectedTab == tab.tag)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background {
            Rectangle()
                .fill(.clear)
                .offscriptGlass(in: Rectangle())
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.offscriptBackgroundTop.opacity(0.32),
                            Color.offscriptBackgroundBottom.opacity(0.55)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
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
            Bookmark.self
        ], inMemory: true)
}

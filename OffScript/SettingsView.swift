import CloudKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var podcasts: [Podcast]
    // Cap at 50 most-recent so the diagnostics card never pulls thousands of
    // rows just to render six. SwiftData's fetchLimit lives on FetchDescriptor
    // not @Query, so this uses a sliced sort + manual prefix at the call site.
    @Query(sort: [SortDescriptor(\TelemetryEvent.createdAt, order: .reverse)], animation: .default) private var telemetryEvents: [TelemetryEvent]
    @State private var autoPlayNext = AppSettings.autoPlayNext
    @State private var preferShortEpisodes = AppSettings.preferShortEpisodes
    @State private var downloadedOnly = AppSettings.libraryShowDownloadedOnly
    @State private var trueBlack = AppSettings.trueBlackMode
    @State private var showGenreEditor = false
    @State private var editingGenres: Set<Genre> = Set(AppSettings.preferredGenres)
    @State private var tasteProfile: UserTasteProfile?
    @State private var showOPMLImport = false
    @State private var showInsights = false
    @State private var signOutConfirmPresented = false
    // Cached counts. Computing these in `var body` triggered a SwiftData
    // `fetchCount` (or, worse, a full `fetch`) on every render — including
    // every keystroke in any TextField on this screen. Now they refresh once
    // on appear and on `podcasts` change.
    @State private var subscribedCount = 0
    @State private var episodeCount = 0
    @State private var unplayedCount = 0
    @State private var queuedCount = 0
    @State private var syncIssueCount = 0
    @State private var failedDownloadCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                    OffScriptUtilityHeader(
                        eyebrow: "Settings",
                        title: "Tune how OffScript behaves",
                        subtitle: "These switches change what gets surfaced, what plays next, and how much momentum the app keeps while you listen."
                    )
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        statCard("Subscribed", value: "\(subscribedCount)")
                        statCard("Episodes", value: "\(episodeCount)")
                        statCard("Unplayed", value: "\(unplayedCount)")
                        statCard("Queued", value: "\(queuedCount)")
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    VStack(alignment: .leading, spacing: 14) {
                        OffScriptSectionHeader(
                            title: "Playback",
                            subtitle: "Keep the queue moving or bias recommendations toward shorter openings in your day."
                        )

                        settingsToggleCard(
                            title: "Auto-play next queued episode",
                            detail: "When an episode finishes, keep listening by moving straight into the next queued item.",
                            isOn: $autoPlayNext
                        )

                        settingsToggleCard(
                            title: "Prefer short listens",
                            detail: "Push compact episodes and quick wins a little higher in your recommendations.",
                            isOn: $preferShortEpisodes
                        )

                        settingsToggleCard(
                            title: "Library defaults to downloads",
                            detail: "Start the library in download-focused mode so offline listening stays one tap away.",
                            isOn: $downloadedOnly
                        )

                        settingsToggleCard(
                            title: "True black background",
                            detail: "Replace the warm gradient with pure black — saves power on OLED screens and lets the artwork glow.",
                            isOn: $trueBlack
                        )
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    // MARK: - Your Taste
                    VStack(alignment: .leading, spacing: 14) {
                        OffScriptSectionHeader(
                            title: "Your Taste",
                            subtitle: "A snapshot of what OffScript thinks you like, built from your listening and preferences."
                        )

                        // Preferred Genres
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Preferred Genres")
                                    .font(.headline)
                                    .foregroundStyle(Color.offscriptTextPrimary)
                                Spacer()
                                Button("Edit") { showGenreEditor = true }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.offscriptAccent)
                            }

                            if AppSettings.preferredGenres.isEmpty {
                                Text("No genres selected yet. Tap Edit to choose what you like.")
                                    .font(.offscriptBody)
                                    .foregroundStyle(Color.offscriptTextMuted)
                            } else {
                                WrappingHStack(items: AppSettings.preferredGenres, spacing: 8) { genre in
                                    Label(genre.title, systemImage: genre.systemImage)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.offscriptAccent)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.offscriptAccentSoft)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offscriptUtilitySurface()

                        // Top Tags
                        if let profile = tasteProfile, !profile.topTags.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Top Tags")
                                    .font(.headline)
                                    .foregroundStyle(Color.offscriptTextPrimary)

                                Text("Derived from episodes you liked or marked as \"more like this.\"")
                                    .font(.offscriptMeta)
                                    .foregroundStyle(Color.offscriptTextMuted)

                                WrappingHStack(items: profile.topTags, spacing: 8) { tag in
                                    Text(tag)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.offscriptTextSecondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.offscriptFillSubtle)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .offscriptUtilitySurface()
                        }

                        // Show Affinity
                        if let profile = tasteProfile, !profile.showAffinity.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Shows You Keep Finishing")
                                    .font(.headline)
                                    .foregroundStyle(Color.offscriptTextPrimary)

                                Text("The shows where you consistently listen through.")
                                    .font(.offscriptMeta)
                                    .foregroundStyle(Color.offscriptTextMuted)

                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(profile.showAffinity, id: \.self) { show in
                                        HStack(spacing: 10) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Color.offscriptAccent)
                                                .font(.footnote)
                                            Text(show)
                                                .font(.offscriptBody)
                                                .foregroundStyle(Color.offscriptTextPrimary)
                                        }
                                    }
                                }
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .offscriptUtilitySurface()
                        }

                        // Duration Preference
                        if let profile = tasteProfile {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Duration Preference")
                                    .font(.headline)
                                    .foregroundStyle(Color.offscriptTextPrimary)

                                HStack(spacing: 14) {
                                    Image(systemName: profile.prefersShortEpisodes ? "hare" : "tortoise")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(Color.offscriptAccent)
                                        .frame(width: 34, height: 34)
                                        .background(Color.offscriptAccentSoft)
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile.prefersShortEpisodes ? "Leans short" : "Leans long")
                                            .font(.offscriptBody.weight(.semibold))
                                            .foregroundStyle(Color.offscriptTextPrimary)

                                        Text("Average completed episode: \(Int(profile.averageCompletedDurationMinutes)) min")
                                            .font(.offscriptMeta)
                                            .foregroundStyle(Color.offscriptTextMuted)
                                    }
                                }
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .offscriptUtilitySurface()
                        }

                        // Reset Taste Profile
                        Button {
                            resetTasteProfile()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                    .foregroundStyle(Color.offscriptDestructive)
                                Text("Reset Taste Profile")
                                    .font(.headline)
                                    .foregroundStyle(Color.offscriptDestructive)
                                Spacer()
                            }
                            .padding(18)
                            .offscriptUtilitySurface()
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    VStack(alignment: .leading, spacing: 14) {
                        OffScriptSectionHeader(
                            title: "About",
                            subtitle: "The current build is local-first, RSS-backed, and still evolving toward a fuller listening system."
                        )

                        Text("OffScript currently runs as a local-first prototype with RSS-backed subscriptions and on-device recommendation logic.")
                            .font(.offscriptBody)
                            .foregroundStyle(Color.offscriptTextSecondary)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .offscriptUtilitySurface()

                        if let displayName = AppSettings.displayName ?? AppSettings.currentUserID {
                            Text("Signed in as \(displayName)")
                                .font(.offscriptBody)
                                .foregroundStyle(Color.offscriptTextSecondary)
                                .padding(18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .offscriptUtilitySurface()
                        }
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    // MARK: - iCloud Sync
                    VStack(alignment: .leading, spacing: 14) {
                        OffScriptSectionHeader(
                            title: "iCloud Sync",
                            subtitle: "Keep your library, queue, and listening history in sync across all your devices."
                        )

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 14) {
                                Image(systemName: cloudSyncActive ? "icloud.fill" : "icloud.slash")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(cloudSyncActive ? Color.offscriptAccent : Color.offscriptTextMuted)
                                    .frame(width: 34, height: 34)
                                    .background(cloudSyncActive ? Color.offscriptAccentSoft : Color.offscriptFillSubtle)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(cloudSyncActive ? "iCloud Sync: Active" : "iCloud Sync: Off")
                                        .font(.offscriptBody.weight(.semibold))
                                        .foregroundStyle(Color.offscriptTextPrimary)

                                    if cloudSyncActive, let lastSync = AppSettings.lastCloudSyncDate {
                                        Text("Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.offscriptMeta)
                                            .foregroundStyle(Color.offscriptTextMuted)
                                    } else if !cloudSyncActive {
                                        Text("Sign in with Apple to sync across devices")
                                            .font(.offscriptMeta)
                                            .foregroundStyle(Color.offscriptTextMuted)
                                    }
                                }
                                Spacer()
                            }

                            if cloudSyncActive {
                                HStack(spacing: 16) {
                                    Button {
                                        triggerCloudSync()
                                    } label: {
                                        HStack {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                            Text("Sync Now")
                                                .font(.subheadline.weight(.semibold))
                                        }
                                        .foregroundStyle(Color.offscriptAccent)
                                    }
                                    .buttonStyle(.plain)

                                    Spacer()

                                    Button(role: .destructive) {
                                        signOutConfirmPresented = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                            Text("Sign Out")
                                                .font(.subheadline.weight(.semibold))
                                        }
                                        .foregroundStyle(Color.offscriptDestructive)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offscriptUtilitySurface()
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    VStack(alignment: .leading, spacing: 14) {
                        OffScriptSectionHeader(
                            title: "Your listening",
                            subtitle: "How OffScript has been showing up for you lately."
                        )

                        Button {
                            showInsights = true
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "chart.bar.fill")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Color.offscriptAccent)
                                    .frame(width: 34, height: 34)
                                    .background(Color.offscriptAccentSoft, in: Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Open the listening recap")
                                        .font(.offscriptBody.weight(.semibold))
                                        .foregroundStyle(Color.offscriptTextPrimary)
                                    Text("Last 30 days — minutes, top shows, recurring topics, what stalled out.")
                                        .font(.offscriptMeta)
                                        .foregroundStyle(Color.offscriptTextMuted)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.offscriptTextMuted)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .offscriptUtilitySurface()
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    VStack(alignment: .leading, spacing: 14) {
                        OffScriptSectionHeader(
                            title: "Bring your library over",
                            subtitle: "Import subscriptions exported as OPML from Apple Podcasts, Pocket Casts, Overcast, Castro, or Spotify."
                        )

                        Button {
                            showOPMLImport = true
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "tray.and.arrow.down.fill")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Color.offscriptAccent)
                                    .frame(width: 34, height: 34)
                                    .background(Color.offscriptAccentSoft, in: Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Import an OPML file")
                                        .font(.offscriptBody.weight(.semibold))
                                        .foregroundStyle(Color.offscriptTextPrimary)
                                    Text("Already follow shows elsewhere? Drop the export here. We'll skip duplicates.")
                                        .font(.offscriptMeta)
                                        .foregroundStyle(Color.offscriptTextMuted)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.offscriptTextMuted)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .offscriptUtilitySurface()
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    VStack(alignment: .leading, spacing: 14) {
                        OffScriptSectionHeader(
                            title: "Storage",
                            subtitle: "Manage downloaded episodes and free up space."
                        )

                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Downloads")
                                    .font(.offscriptCardTitle)
                                    .foregroundStyle(Color.offscriptTextPrimary)
                                Text(downloadStorageLabel)
                                    .font(.offscriptMeta)
                                    .foregroundStyle(Color.offscriptTextMuted)
                            }
                            Spacer()
                            if downloadStorageBytes > 0 {
                                Button("Clear All") {
                                    DownloadService.shared.deleteAllDownloads()
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.offscriptDestructive)
                            }
                        }
                        .padding(18)
                        .offscriptUtilitySurface()
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    VStack(alignment: .leading, spacing: 14) {
                        OffScriptSectionHeader(
                            title: "Diagnostics",
                            subtitle: "A quick read on sync health, offline readiness, and the event trail from this build."
                        )

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)],
                            alignment: .leading,
                            spacing: 12
                        ) {
                            statCard("Sync Issues", value: "\(syncIssueCount)")
                            statCard("Download Failures", value: "\(failedDownloadCount)")
                            statCard("Offline Ready", value: "\(offlineReadyCount)")
                            statCard("Events", value: "\(telemetryEvents.count)")
                        }

                        if telemetryEvents.isEmpty {
                            Text("No recent events yet. Start listening, importing, or downloading and OffScript will record activity here.")
                                .font(.offscriptBody)
                                .foregroundStyle(Color.offscriptTextSecondary)
                                .padding(18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .offscriptUtilitySurface()
                        } else {
                            VStack(spacing: 10) {
                                ForEach(Array(telemetryEvents.prefix(6))) { event in
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(event.name.replacingOccurrences(of: "_", with: " ").capitalized)
                                                .font(.headline)
                                                .foregroundStyle(Color.offscriptTextPrimary)

                                            Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.offscriptMeta)
                                                .foregroundStyle(Color.offscriptTextMuted)

                                            if !event.metadata.isEmpty {
                                                Text(event.metadata
                                                    .sorted { $0.key < $1.key }
                                                    .map { "\($0.key): \($0.value)" }
                                                    .joined(separator: " • "))
                                                    .font(.offscriptMeta)
                                                    .foregroundStyle(Color.offscriptTextSecondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }

                                        Spacer()
                                    }
                                    .padding(16)
                                    .offscriptUtilitySurface(radius: OffScriptTheme.Radius.small)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
            .offscriptPageBackground()
            .navigationTitle("Settings")
            .sheet(isPresented: $showOPMLImport) {
                OPMLImportView()
            }
            .sheet(isPresented: $showInsights) {
                ListeningInsightsView()
            }
            .confirmationDialog(
                "Sign out of OffScript?",
                isPresented: $signOutConfirmPresented,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    AppSettings.clearCredential()
                    AppSettings.cloudSyncEnabled = false
                    AppSettings.lastCloudSyncDate = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your library stays on this device. iCloud sync stops until you sign in again.")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: autoPlayNext) { _, newValue in
            AppSettings.autoPlayNext = newValue
        }
        .onChange(of: preferShortEpisodes) { _, newValue in
            AppSettings.preferShortEpisodes = newValue
        }
        .onChange(of: downloadedOnly) { _, newValue in
            AppSettings.libraryShowDownloadedOnly = newValue
        }
        .onChange(of: trueBlack) { _, newValue in
            AppSettings.trueBlackMode = newValue
        }
        .task {
            loadTasteProfile()
            refreshCounts()
        }
        .onChange(of: podcasts) { _, _ in refreshCounts() }
        .sheet(isPresented: $showGenreEditor) {
            GenreEditorSheet(
                selectedGenres: $editingGenres,
                onSave: {
                    AppSettings.preferredGenres = Array(editingGenres).sorted { $0.title < $1.title }
                    try? TasteProfileService.refresh(in: modelContext)
                    loadTasteProfile()
                }
            )
        }
    }

    private var cloudSyncActive: Bool {
        AppSettings.cloudSyncEnabled && AppSettings.currentUserID != nil
    }

    private func triggerCloudSync() {
        AppSettings.lastCloudSyncDate = Date()
    }

    private func loadTasteProfile() {
        tasteProfile = try? TasteProfileService.loadOrCreate(in: modelContext)
        editingGenres = Set(AppSettings.preferredGenres)
    }

    private func resetTasteProfile() {
        let signals = (try? modelContext.fetch(FetchDescriptor<PreferenceSignal>())) ?? []
        for signal in signals {
            modelContext.delete(signal)
        }
        try? modelContext.save()
        try? TasteProfileService.refresh(in: modelContext)
        loadTasteProfile()
    }

    private func statCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.offscriptTextPrimary)
            Text(title.uppercased())
                .font(.offscriptMicro.weight(.semibold))
                .foregroundStyle(Color.offscriptTextMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .offscriptUtilitySurface()
    }

    private func settingsToggleCard(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.offscriptTextPrimary)
                Text(detail)
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color.offscriptAccent)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offscriptUtilitySurface()
    }

    /// Refresh the cached stat counts. Called from `.task` and from
    /// `onChange(of: podcasts)` — never from body. Uses `fetchCount` so we
    /// pay for a SQL COUNT, not a full row materialization.
    private func refreshCounts() {
        subscribedCount = podcasts.lazy.filter(\.isSubscribed).count
        syncIssueCount = podcasts.lazy.filter { $0.syncStatus == "failed" || $0.syncErrorMessage != nil }.count

        episodeCount = (try? modelContext.fetchCount(FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.podcast.isSubscribed == true }
        ))) ?? 0

        unplayedCount = (try? modelContext.fetchCount(FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.isPlayed == false && $0.podcast.isSubscribed == true }
        ))) ?? 0

        queuedCount = (try? modelContext.fetchCount(FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.isQueued == true }
        ))) ?? 0

        // `downloadState` is a computed wrapper over a private raw String, so
        // we can't express `== .failed` in #Predicate. Cap the fetch at 1000
        // so a 100k-episode store never reads its whole episode table for a
        // diagnostics tile that lives offscreen most of the time.
        var failedDescriptor = FetchDescriptor<Episode>()
        failedDescriptor.fetchLimit = 1000
        let sample = (try? modelContext.fetch(failedDescriptor)) ?? []
        failedDownloadCount = sample.lazy.filter { $0.downloadState == .failed }.count
    }

    private var offlineReadyCount: Int {
        (try? modelContext.fetchCount(FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.isDownloaded == true }
        ))) ?? 0
    }

    private var downloadStorageBytes: Int64 {
        DownloadService.shared.totalDownloadSizeBytes
    }

    private var downloadStorageLabel: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return downloadStorageBytes > 0
            ? "\(offlineReadyCount) episodes, \(formatter.string(fromByteCount: downloadStorageBytes))"
            : "No downloads"
    }
}

// MARK: - Genre Editor Sheet

private struct GenreEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedGenres: Set<Genre>
    let onSave: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Pick the genres that match how you actually listen. OffScript uses these to weight recommendations.")
                        .font(.offscriptBody)
                        .foregroundStyle(Color.offscriptTextSecondary)
                        .padding(.horizontal, OffScriptTheme.pagePadding)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Genre.allCases) { genre in
                            Button {
                                toggleGenre(genre)
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: genre.systemImage)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(selectedGenres.contains(genre) ? Color.offscriptAccent : Color.offscriptTextSecondary)

                                    Text(genre.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(selectedGenres.contains(genre) ? Color.offscriptTextPrimary : Color.offscriptTextSecondary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 90)
                                .background(selectedGenres.contains(genre) ? Color.offscriptAccentSoft : Color.offscriptFillSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                                        .stroke(selectedGenres.contains(genre) ? Color.offscriptAccent : Color.offscriptHairline, lineWidth: selectedGenres.contains(genre) ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .sensoryFeedback(.impact(flexibility: .soft), trigger: selectedGenres.contains(genre))
                        }
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                }
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .offscriptPageBackground()
            .navigationTitle("Edit Genres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func toggleGenre(_ genre: Genre) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            if selectedGenres.contains(genre) {
                selectedGenres.remove(genre)
            } else {
                selectedGenres.insert(genre)
            }
        }
    }
}

// MARK: - Wrapping HStack

private struct WrappingHStack<Item: Hashable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    @ViewBuilder let content: (Item) -> Content

    @State private var totalHeight: CGFloat = .zero

    var body: some View {
        GeometryReader { geometry in
            self.generateContent(in: geometry)
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in geometry: GeometryProxy) -> some View {
        var width: CGFloat = 0
        var height: CGFloat = 0

        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item)
                    .padding(.trailing, spacing)
                    .padding(.bottom, spacing)
                    .alignmentGuide(.leading) { dimension in
                        if abs(width - dimension.width) > geometry.size.width {
                            width = 0
                            height -= dimension.height + spacing
                        }
                        let result = width
                        if item == items.last {
                            width = 0
                        } else {
                            width -= dimension.width
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == items.last {
                            height = 0
                        }
                        return result
                    }
            }
        }
        .background(viewHeightReader($totalHeight))
    }

    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: HeightPreferenceKey.self, value: geometry.size.height)
        }
        .onPreferenceChange(HeightPreferenceKey.self) { binding.wrappedValue = $0 }
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

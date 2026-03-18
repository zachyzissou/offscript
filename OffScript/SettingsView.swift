import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var podcasts: [Podcast]
    @Query(sort: [SortDescriptor(\TelemetryEvent.createdAt, order: .reverse)]) private var telemetryEvents: [TelemetryEvent]
    @State private var autoPlayNext = AppSettings.autoPlayNext
    @State private var preferShortEpisodes = AppSettings.preferShortEpisodes
    @State private var downloadedOnly = AppSettings.libraryShowDownloadedOnly

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
                        statCard("Subscribed", value: "\(podcasts.filter(\.isSubscribed).count)")
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

    // Use fetchCount to avoid loading all episodes into memory just for stats
    private var episodeCount: Int {
        (try? modelContext.fetchCount(FetchDescriptor<Episode>())) ?? 0
    }

    private var unplayedCount: Int {
        (try? modelContext.fetchCount(FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.isPlayed == false }
        ))) ?? 0
    }

    private var queuedCount: Int {
        (try? modelContext.fetchCount(FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.isQueued == true }
        ))) ?? 0
    }

    private var syncIssueCount: Int {
        podcasts.filter { $0.syncStatus == "failed" || $0.syncErrorMessage != nil }.count
    }

    // TODO: downloadState is a computed property over private downloadStateRawValue,
    // so we cannot express download state filters (failed/downloaded) via #Predicate.
    // We use the isDownloaded stored Bool for offline-ready count.
    // For failed downloads, we fall back to fetching all episodes (N+1 remains here).
    private var failedDownloadCount: Int {
        let allEpisodes = (try? modelContext.fetch(FetchDescriptor<Episode>())) ?? []
        return allEpisodes.filter { $0.downloadState == .failed }.count
    }

    private var offlineReadyCount: Int {
        (try? modelContext.fetchCount(FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.isDownloaded == true }
        ))) ?? 0
    }
}

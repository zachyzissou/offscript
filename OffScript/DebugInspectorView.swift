import OSLog
import SwiftData
import SwiftUI

private let debugInspectorLogger = Logger(subsystem: "com.offscript", category: "DebugInspector")

// MARK: - DebugInspectorView (Tuner diagnostics panel)

/// Phase 27 - Unified Debug Inspector.
///
/// Phase 23's dead-code sweep found `TelemetryEvent` had 16 emit sites and
/// zero consumers; Phase 25 deferred the delete-vs-consume decision. This
/// view consumes them: a debug-only diagnostics panel that surfaces dormant
/// telemetry alongside sync history, download state, and runtime metadata
/// so engineers can introspect the live store without running a debugger.
///
/// Presented as a sheet from Settings, mirroring the modal vocabulary used
/// elsewhere in the app (no NavigationStack to avoid Liquid Glass chrome).
struct DebugInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var telemetryEvents: [TelemetryEvent] = []
    @State private var inspectedTelemetry: TelemetryEvent?
    @State private var isConfirmingClearTelemetry = false

    @State private var podcasts: [Podcast] = []

    @State private var downloadingEpisodes: [Episode] = []
    @State private var queuedEpisodes: [Episode] = []
    @State private var failedEpisodes: [Episode] = []
    @State private var downloadedEpisodes: [Episode] = []

    @State private var transcriptCacheCount: Int = 0
    @State private var totalDownloadBytes: Int64 = 0
    @State private var pendingBackgroundTaskAt: Date?

    private static let listLimitTelemetry = 100
    private static let listLimitSync = 50
    private static let listLimitDownloaded = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                inspectorHeader
                telemetrySection
                syncHistorySection
                downloadStateSection
                runtimeMetadataSection
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)
            .padding(.top, OffScriptTheme.modalContentTopPadding)
            .padding(.bottom, 32)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
        .task {
            refreshAll()
        }
        .sheet(item: $inspectedTelemetry) { event in
            TelemetryDetailSheet(event: event)
                .tunerModalSurface()
        }
    }

    // MARK: header

    private var inspectorHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TunerLabel(text: "DEBUG · INSPECTOR", color: .offscriptSignalYellow)
                    .lineLimit(1)
                Spacer()
                TunerLabel(text: "● LIVE", color: .offscriptFnMode)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Debug Inspector")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    TunerLabel(text: "DONE", color: .offscriptSignalYellow, size: 11)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close debug inspector")
            }
            Text("Debug-only diagnostics. Surfaces dormant telemetry, per-podcast sync state, download queues, and runtime metadata.")
                .font(.system(size: 12))
                .foregroundStyle(Color.offscriptSoftPaper)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                .padding(.top, 4)
        }
    }

    // MARK: - Section A: Telemetry

    private var telemetrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TunerLabel(text: "TELEMETRY · LAST \(Self.listLimitTelemetry)", color: .offscriptSignalYellow)
                Spacer()
                TunerLabel(text: "\(telemetryEvents.count) EVENTS", color: .offscriptFnInfo, size: 8)
            }

            if telemetryEvents.isEmpty {
                emptyRow(text: "No telemetry events recorded yet.")
            } else {
                if isConfirmingClearTelemetry {
                    clearTelemetryConfirmStrip
                } else {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            isConfirmingClearTelemetry = true
                        }
                    } label: {
                        TunerLabel(text: "× CLEAR ALL", color: .offscriptFnRecord, size: 10)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(minHeight: 44)
                            .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear all telemetry events")
                    .accessibilityHint("Asks for confirmation before deleting every recorded event.")
                }

                VStack(spacing: 0) {
                    ForEach(telemetryEvents) { event in
                        telemetryRow(event: event)
                        Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
    }

    private func telemetryRow(event: TelemetryEvent) -> some View {
        Button {
            inspectedTelemetry = event
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .lineLimit(1)
                    Text(event.metadata.isEmpty ? "no metadata" : metadataSummary(event.metadata))
                        .tunerFont(size: 10, weight: .regular, tracking: 0.4)
                        .foregroundStyle(Color.offscriptFnInfo)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                TunerLabel(
                    text: timestampLabel(event.createdAt),
                    color: .offscriptSoftPaper,
                    size: 9
                )
                .lineLimit(1)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Telemetry event \(event.name), \(timestampLabel(event.createdAt))")
        .accessibilityHint("Double-tap to inspect full payload.")
    }

    private var clearTelemetryConfirmStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            TunerLabel(text: "● CONFIRM CLEAR", color: .offscriptFnRecord)
            Text("Delete every recorded telemetry event? This wipes the dormant log this inspector reads from.")
                .font(.system(size: 13))
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineSpacing(2)
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isConfirmingClearTelemetry = false
                    }
                } label: {
                    TunerLabel(text: "CANCEL", color: .offscriptPaperWhite, size: 11)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel clear telemetry")

                Button {
                    clearAllTelemetry()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isConfirmingClearTelemetry = false
                    }
                } label: {
                    TunerLabel(text: "× CONFIRM", color: .offscriptFnRecord, size: 11)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Confirm clear telemetry")
            }
        }
        .padding(12)
        .overlay(Rectangle().stroke(Color.offscriptFnRecord.opacity(0.6), lineWidth: 1))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Section B: Sync history

    private var syncHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TunerLabel(text: "SYNC HISTORY · LAST \(Self.listLimitSync)", color: .offscriptSignalYellow)
                Spacer()
                TunerLabel(text: "\(podcasts.count) PODCASTS", color: .offscriptFnInfo, size: 8)
            }

            if podcasts.isEmpty {
                emptyRow(text: "No subscribed podcasts to sync.")
            } else {
                VStack(spacing: 0) {
                    ForEach(podcasts) { podcast in
                        syncHistoryRow(podcast: podcast)
                        Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
    }

    private func syncHistoryRow(podcast: Podcast) -> some View {
        let statusColor = SyncHistoryService.statusColor(for: podcast)
        let statusLabel = SyncHistoryService.statusLabel(for: podcast)
        let attemptedAt = podcast.lastSyncAttemptAt
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(podcast.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(1)
                Spacer(minLength: 8)
                TunerLabel(text: statusLabel, color: statusColor, size: 9)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Text(attemptedAt.map { "ATTEMPT  \(timestampLabel($0))" } ?? "ATTEMPT  —")
                    .tunerFont(size: 9.5, weight: .regular, tracking: 1.2)
                    .foregroundStyle(Color.offscriptSoftPaper)
                if podcast.syncFailureCount > 0 {
                    TunerLabel(text: "FAIL ×\(podcast.syncFailureCount)", color: .offscriptFnRecord, size: 9)
                }
                Spacer()
            }
            if let message = podcast.syncErrorMessage, !message.isEmpty {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.offscriptFnRecord)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(podcast.title), sync status \(statusLabel.lowercased())\(podcast.syncFailureCount > 0 ? ", failure count \(podcast.syncFailureCount)" : "")")
    }

    // MARK: - Section C: Download state

    private var downloadStateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TunerLabel(text: "DOWNLOADS · STATE", color: .offscriptSignalYellow)

            downloadGroupHeader(
                title: "DOWNLOADING",
                color: .offscriptSignalYellow,
                count: downloadingEpisodes.count
            )
            if downloadingEpisodes.isEmpty {
                emptyRow(text: "Nothing downloading.")
            } else {
                ForEach(downloadingEpisodes) { downloadingRow(episode: $0) }
            }
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)

            downloadGroupHeader(
                title: "QUEUED",
                color: .offscriptFnInfo,
                count: queuedEpisodes.count
            )
            if queuedEpisodes.isEmpty {
                emptyRow(text: "No queued downloads.")
            } else {
                ForEach(queuedEpisodes) { plainDownloadRow(episode: $0) }
            }
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)

            downloadGroupHeader(
                title: "FAILED",
                color: .offscriptFnRecord,
                count: failedEpisodes.count
            )
            if failedEpisodes.isEmpty {
                emptyRow(text: "No failed downloads.")
            } else {
                ForEach(failedEpisodes) { failedDownloadRow(episode: $0) }
            }
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)

            downloadGroupHeader(
                title: "DOWNLOADED · LAST \(Self.listLimitDownloaded)",
                color: .offscriptFnMode,
                count: downloadedEpisodes.count
            )
            if downloadedEpisodes.isEmpty {
                emptyRow(text: "No downloaded episodes.")
            } else {
                ForEach(downloadedEpisodes) { downloadedRow(episode: $0) }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
    }

    private func downloadGroupHeader(title: String, color: Color, count: Int) -> some View {
        HStack {
            TunerLabel(text: title, color: color, size: 9)
            Spacer()
            TunerLabel(text: "\(count)", color: color, size: 9)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title.lowercased()), \(count) episodes")
    }

    private func plainDownloadRow(episode: Episode) -> some View {
        downloadRowContent(episode: episode, trailing: nil, action: nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(episode.title), \(episode.podcast.title)")
    }

    private func downloadingRow(episode: Episode) -> some View {
        let percent = Int((episode.downloadProgress * 100).rounded())
        return downloadRowContent(
            episode: episode,
            trailing: AnyView(
                TunerLabel(text: "\(percent)%", color: .offscriptSignalYellow, size: 10)
            ),
            action: nil
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(episode.title), downloading \(percent) percent")
    }

    private func failedDownloadRow(episode: Episode) -> some View {
        let message = episode.downloadErrorMessage ?? "unknown error"
        return Button {
            DownloadService.shared.startDownload(for: episode)
            refreshDownloads()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                downloadRowContent(
                    episode: episode,
                    trailing: AnyView(
                        TunerLabel(text: "↻ RETRY", color: .offscriptFnRecord, size: 10)
                    ),
                    action: nil
                )
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.offscriptFnRecord)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(episode.title), download failed: \(message). Double-tap to retry.")
    }

    private func downloadedRow(episode: Episode) -> some View {
        let completedAt = episode.downloadCompletedAt
        return downloadRowContent(
            episode: episode,
            trailing: AnyView(
                TunerLabel(
                    text: completedAt.map { timestampLabel($0) } ?? "—",
                    color: .offscriptFnMode,
                    size: 9
                )
            ),
            action: nil
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(episode.title), \(episode.podcast.title), downloaded\(completedAt.map { " \(timestampLabel($0))" } ?? "")")
    }

    @ViewBuilder
    private func downloadRowContent(
        episode: Episode,
        trailing: AnyView?,
        action: (() -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(episode.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(1)
                Text(episode.podcast.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.offscriptSoftPaper)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let trailing {
                trailing
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Section D: Runtime metadata

    private var runtimeMetadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TunerLabel(text: "RUNTIME · METADATA", color: .offscriptSignalYellow)

            VStack(spacing: 0) {
                metadataRow(label: "VERSION", value: buildVersionString, valueColor: .offscriptFnMode)
                Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                metadataRow(label: "STORE", value: storeStateLabel, valueColor: storeStateColor)
                Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                metadataRow(label: "ICLOUD ENABLED", value: AppSettings.cloudSyncEnabled ? "YES" : "NO", valueColor: AppSettings.cloudSyncEnabled ? .offscriptFnMode : .offscriptSoftPaper)
                Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                metadataRow(label: "DOWNLOAD CACHE", value: byteString(totalDownloadBytes), valueColor: .offscriptFnInfo)
                Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                metadataRow(label: "TRANSCRIPT CACHE", value: "\(transcriptCacheCount) ROWS", valueColor: .offscriptFnInfo)
                Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                metadataRow(
                    label: "NEXT BG REFRESH",
                    value: pendingBackgroundTaskAt.map { timestampLabel($0) } ?? "UNSCHEDULED",
                    valueColor: pendingBackgroundTaskAt == nil ? .offscriptSoftPaper : .offscriptFnInfo
                )
                Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                metadataRow(label: "WI-FI ONLY", value: AppSettings.downloadsWiFiOnly ? "ON" : "OFF", valueColor: AppSettings.downloadsWiFiOnly ? .offscriptSignalYellow : .offscriptSoftPaper)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
    }

    private func metadataRow(label: String, value: String, valueColor: Color) -> some View {
        HStack {
            TunerLabel(text: label, color: .offscriptSoftPaper, size: 9)
            Spacer()
            Text(value)
                .tunerFont(size: 11, weight: .semibold, tracking: 1.2)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.lowercased()) \(value.lowercased())")
    }

    private var storeStateLabel: String {
        switch AppSettings.cloudSyncRuntimeState {
        case .cloudBacked: return "CLOUD-BACKED"
        case .localOnly: return "LOCAL ONLY"
        case .fallbackFailed: return "IN-MEMORY FALLBACK"
        }
    }

    private var storeStateColor: Color {
        switch AppSettings.cloudSyncRuntimeState {
        case .cloudBacked: return .offscriptFnMode
        case .localOnly: return .offscriptFnInfo
        case .fallbackFailed: return .offscriptFnRecord
        }
    }

    private var buildVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    // MARK: - shared row helpers

    private func emptyRow(text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Color.offscriptSoftPaper)
            .padding(.vertical, 10)
    }

    private func timestampLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour(.defaultDigits(amPM: .abbreviated)).minute()).uppercased()
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func metadataSummary(_ metadata: [String: String]) -> String {
        metadata
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " · ")
    }

    // MARK: - data loading

    private func refreshAll() {
        refreshTelemetry()
        refreshSyncHistory()
        refreshDownloads()
        refreshRuntimeMetadata()
    }

    private func refreshTelemetry() {
        var descriptor = FetchDescriptor<TelemetryEvent>(
            sortBy: [SortDescriptor(\TelemetryEvent.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.listLimitTelemetry
        telemetryEvents = (try? modelContext.fetch(descriptor)) ?? []
        debugInspectorLogger.info("Telemetry events loaded: count=\(telemetryEvents.count, privacy: .public)")
    }

    private func refreshSyncHistory() {
        podcasts = SyncHistoryService.recentlyAttempted(
            in: modelContext,
            limit: Self.listLimitSync
        )
        debugInspectorLogger.info("Sync history loaded: podcasts=\(podcasts.count, privacy: .public)")
    }

    private func refreshDownloads() {
        let downloadingState = Episode.DownloadState.downloading.rawValue
        let queuedState = Episode.DownloadState.queued.rawValue
        let failedState = Episode.DownloadState.failed.rawValue
        let downloadedState = Episode.DownloadState.downloaded.rawValue

        downloadingEpisodes = fetchEpisodes(
            predicate: #Predicate<Episode> { $0.downloadStateRawValue == downloadingState },
            sort: [SortDescriptor(\Episode.downloadRequestedAt, order: .reverse)]
        )
        queuedEpisodes = fetchEpisodes(
            predicate: #Predicate<Episode> { $0.downloadStateRawValue == queuedState },
            sort: [SortDescriptor(\Episode.downloadRequestedAt, order: .reverse)]
        )
        failedEpisodes = fetchEpisodes(
            predicate: #Predicate<Episode> { $0.downloadStateRawValue == failedState },
            sort: [SortDescriptor(\Episode.downloadRequestedAt, order: .reverse)]
        )
        downloadedEpisodes = fetchEpisodes(
            predicate: #Predicate<Episode> { $0.downloadStateRawValue == downloadedState },
            sort: [SortDescriptor(\Episode.downloadCompletedAt, order: .reverse)],
            limit: Self.listLimitDownloaded
        )
    }

    private func fetchEpisodes(
        predicate: Predicate<Episode>,
        sort: [SortDescriptor<Episode>],
        limit: Int? = nil
    ) -> [Episode] {
        var descriptor = FetchDescriptor<Episode>(predicate: predicate, sortBy: sort)
        if let limit { descriptor.fetchLimit = limit }
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func refreshRuntimeMetadata() {
        totalDownloadBytes = DownloadService.shared.totalDownloadSizeBytes
        transcriptCacheCount = (try? modelContext.fetchCount(FetchDescriptor<EpisodeTranscriptCache>())) ?? 0
        SyncHistoryService.fetchNextBackgroundRefresh { date in
            Task { @MainActor in
                self.pendingBackgroundTaskAt = date
            }
        }
    }

    private func clearAllTelemetry() {
        do {
            try modelContext.delete(model: TelemetryEvent.self)
            modelContext.saveOrLog("DebugInspector.clearTelemetry")
            telemetryEvents = []
            debugInspectorLogger.info("Cleared all telemetry events")
        } catch {
            debugInspectorLogger.error("Failed to clear telemetry: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - TelemetryDetailSheet

/// Full-payload inspector for a single telemetry event. Read-only.
private struct TelemetryDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: TelemetryEvent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    TunerLabel(text: "TELEMETRY · EVENT", color: .offscriptSignalYellow)
                    Spacer()
                    Button { dismiss() } label: {
                        TunerLabel(text: "DONE", color: .offscriptSignalYellow, size: 11)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close telemetry event detail")
                }

                Text(event.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .fixedSize(horizontal: false, vertical: true)

                TunerLabel(
                    text: event.createdAt.formatted(.iso8601).uppercased(),
                    color: .offscriptFnInfo,
                    size: 10
                )

                Rectangle().fill(Color.offscriptHairline).frame(height: 1)

                if event.metadata.isEmpty {
                    Text("No metadata.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.offscriptSoftPaper)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(event.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            VStack(alignment: .leading, spacing: 4) {
                                TunerLabel(text: key, color: .offscriptSoftPaper, size: 9)
                                Text(value)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(Color.offscriptPaperWhite)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                        }
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)
            .padding(.top, OffScriptTheme.modalContentTopPadding)
            .padding(.bottom, 32)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
    }
}

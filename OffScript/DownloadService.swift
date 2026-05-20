import Combine
import Foundation
import Network
import OSLog
import SwiftData

private let downloadLogger = Logger(subsystem: "com.offscript", category: "DownloadService")

@MainActor
final class DownloadService: NSObject, ObservableObject {
    static let shared = DownloadService()
    private static let backgroundSessionIdentifier = "com.offscript.downloads"
    private let maximumConcurrentDownloads = 2

    let objectWillChange = ObservableObjectPublisher()

    /// Set by the app delegate when the system wakes the app to handle background URL session events.
    var backgroundCompletionHandler: (() -> Void)?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    private var modelContext: ModelContext?
    private var taskToEpisodeID: [Int: UUID] = [:]
    private var episodeIDToTask: [UUID: URLSessionDownloadTask] = [:]
    private var hasReconciledPersistedState = false
    private var lastPersistedProgressByEpisodeID: [UUID: Double] = [:]
    private var lastProgressSaveDateByEpisodeID: [UUID: Date] = [:]

    private override init() {
        super.init()
        // Access session lazily on first use; just trigger it here to reconnect background tasks.
        _ = session
    }

    func configure(context: ModelContext) {
        modelContext = context
        guard !hasReconciledPersistedState else { return }
        reconcilePersistedDownloads()
        sweepOrphanDownloadFiles()
        hasReconciledPersistedState = true
    }

    /// Test-only hook to force a re-run of the launch reconciliation against a
    /// freshly-injected context. Production callers go through `configure`,
    /// which guards on a one-shot flag.
    func reconcileForTesting(context: ModelContext) {
        modelContext = context
        reconcilePersistedDownloads()
        sweepOrphanDownloadFiles()
    }

    func startDownload(for episode: Episode) {
        objectWillChange.send()
        guard episode.downloadState != .downloading, episode.downloadState != .queued else { return }

        if let existingURL = localURL(for: episode) {
            episode.localFileURL = existingURL
            episode.downloadState = .downloaded
            episode.downloadProgress = 1
            episode.downloadCompletedAt = .now
            episode.downloadErrorMessage = nil
            episode.isDownloaded = true
            modelContext?.saveOrLog("DownloadService")
            TelemetryService.track(
                "download_resolved_from_disk",
                metadata: ["episode": episode.title, "podcast": episode.podcast.title],
                in: modelContext
            )
            return
        }

        episode.downloadRequestedAt = .now
        episode.downloadCompletedAt = nil
        episode.downloadErrorMessage = nil
        episode.downloadProgress = 0
        episode.downloadState = .queued
        episode.isDownloaded = false
        modelContext?.saveOrLog("DownloadService")

        if activeDownloadCount < maximumConcurrentDownloads, isAllowedOnCurrentNetwork {
            beginDownload(for: episode)
        } else {
            TelemetryService.track(
                "download_queued",
                metadata: [
                    "episode": episode.title,
                    "podcast": episode.podcast.title,
                    "reason": isAllowedOnCurrentNetwork ? "concurrency" : "wifi_only"
                ],
                in: modelContext
            )
        }
    }

    /// Returns `false` when the user has Wi-Fi-only downloads enabled AND the
    /// device is currently on cellular (or has no resolved interface yet).
    /// `URLSessionConfiguration.allowsCellularAccess` would also enforce this,
    /// but checking up front lets us keep episodes visibly `.queued` rather
    /// than spinning up a background task that immediately fails or stalls.
    private var isAllowedOnCurrentNetwork: Bool {
        guard AppSettings.downloadsWiFiOnly else { return true }
        // If the monitor hasn't resolved yet (`nil`), defer to be safe — we'll
        // pick the queued episode back up once the network monitor fires.
        return NetworkMonitor.shared.connectionType == .wifi
    }

    /// Called from a `NetworkMonitor` observer so freshly-allowed downloads
    /// kick off when the device joins Wi-Fi. Public for the test suite.
    func networkConditionsChanged() {
        guard isAllowedOnCurrentNetwork else { return }
        resumeQueuedDownloadsIfNeeded()
    }

    func cancelDownload(for episode: Episode) {
        objectWillChange.send()
        if episode.downloadState == .queued, episodeIDToTask[episode.id] == nil {
            episode.downloadState = .notDownloaded
            episode.downloadProgress = 0
            episode.downloadErrorMessage = nil
            episode.downloadRequestedAt = nil
            episode.isDownloaded = false
            clearProgressThrottle(for: episode.id)
            modelContext?.saveOrLog("DownloadService")
            TelemetryService.track(
                "download_cancelled",
                metadata: ["episode": episode.title, "podcast": episode.podcast.title],
                in: modelContext
            )
            return
        }

        episodeIDToTask[episode.id]?.cancel()
        episodeIDToTask[episode.id] = nil
        clearProgressThrottle(for: episode.id)
        episode.downloadState = episode.localFileURL == nil ? .notDownloaded : .downloaded
        episode.downloadProgress = episode.localFileURL == nil ? 0 : 1
        episode.isDownloaded = episode.localFileURL != nil
        modelContext?.saveOrLog("DownloadService")
        TelemetryService.track(
            "download_cancelled",
            metadata: ["episode": episode.title, "podcast": episode.podcast.title],
            in: modelContext
        )
        resumeQueuedDownloadsIfNeeded()
    }

    func deleteDownload(for episode: Episode) {
        objectWillChange.send()
        cancelDownload(for: episode)
        if let url = episode.localFileURL {
            removeFileIfPresent(at: url)
        }
        episode.localFileURL = nil
        episode.downloadState = .notDownloaded
        episode.downloadProgress = 0
        episode.downloadCompletedAt = nil
        episode.downloadErrorMessage = nil
        episode.isDownloaded = false
        clearProgressThrottle(for: episode.id)
        modelContext?.saveOrLog("DownloadService")
        TelemetryService.track(
            "download_deleted",
            metadata: ["episode": episode.title, "podcast": episode.podcast.title],
            in: modelContext
        )
        resumeQueuedDownloadsIfNeeded()
    }

    func deleteAllDownloads() {
        guard let modelContext else { return }
        objectWillChange.send()
        let descriptor = FetchDescriptor<Episode>(predicate: #Predicate<Episode> { $0.isDownloaded == true })
        let downloaded: [Episode]
        do {
            downloaded = try modelContext.fetch(descriptor)
        } catch {
            downloadLogger.error("deleteAllDownloads fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        for episode in downloaded {
            deleteDownload(for: episode)
        }
    }

    var totalDownloadSizeBytes: Int64 {
        let supportURL = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        guard let downloadsURL = supportURL?.appending(path: "Downloads") else { return 0 }
        guard let files = try? FileManager.default.contentsOfDirectory(at: downloadsURL, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + Int64(size)
        }
    }

    func localURL(for episode: Episode) -> URL? {
        guard let localFileURL = episode.localFileURL else { return nil }
        if FileManager.default.fileExists(atPath: localFileURL.path) {
            return localFileURL
        }

        episode.localFileURL = nil
        episode.downloadState = .notDownloaded
        episode.downloadProgress = 0
        episode.isDownloaded = false
        modelContext?.saveOrLog("DownloadService")
        return nil
    }

    func statusText(for episode: Episode) -> String? {
        switch episode.downloadState {
        case .notDownloaded:
            return nil
        case .queued:
            return "Queued for offline"
        case .downloading:
            let percentage = Int((episode.downloadProgress * 100).rounded())
            return percentage > 0 ? "Downloading \(percentage)%" : "Downloading for offline"
        case .downloaded:
            if let completedAt = episode.downloadCompletedAt {
                return "Saved offline \(completedAt.formatted(date: .abbreviated, time: .shortened))"
            }
            return "Saved offline"
        case .failed:
            return episode.downloadErrorMessage ?? "Download failed"
        }
    }

    private func destinationURL(for episodeID: UUID, originalURL: URL?) throws -> URL {
        let supportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let downloadsURL = supportURL.appending(path: "Downloads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        // Use the original URL's pathExtension if it's present and non-empty;
        // otherwise default to mp3. The previous form
        // `originalURL?.pathExtension.isEmpty == false ? originalURL! : "mp3"`
        // crashed when originalURL was nil because the false branch of the
        // optional-equality fell through to a force-unwrap.
        let ext: String = {
            guard let pathExt = originalURL?.pathExtension, !pathExt.isEmpty else { return "mp3" }
            return pathExt
        }()
        return downloadsURL.appending(path: "\(episodeID.uuidString).\(ext)")
    }

    private func episode(for id: UUID) -> Episode? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<Episode>(predicate: #Predicate<Episode> { episode in
            episode.id == id
        })
        return try? modelContext.fetch(descriptor).first
    }

    private var activeDownloadCount: Int {
        episodeIDToTask.count
    }

    /// Test-only mirror of the in-flight task count. The production code
    /// reads `activeDownloadCount` directly; tests reach in through this to
    /// assert that cancel/delete drained the dictionaries.
    var activeDownloadCountForTesting: Int { activeDownloadCount }
    var trackedEpisodeIDsForTesting: Set<UUID> { Set(episodeIDToTask.keys) }

    #if DEBUG
    /// Drop singleton state that would otherwise leak across in-memory
    /// `ModelContainer`s in the test suite. The URLSession delegate
    /// callbacks (`didWriteData`, `didFinishDownloadingTo`, etc.) all
    /// hop to the main actor and look up an `Episode` through the
    /// cached `modelContext`; if that context was torn down by a
    /// previous test, the fetch crashes inside SwiftData. Cancelling
    /// every in-flight task and nil-ing the context here prevents that
    /// cross-test crash class. Mirrors the lurking-crash playbook in
    /// `docs/TEST_MATRIX.md`.
    @MainActor
    func debugResetForTesting() {
        // 1. Cancel every in-flight URLSession download task before we
        //    drop the dictionaries — without this the task's completion
        //    callback would still fire and try to use the (now nil)
        //    modelContext / the previous test's context.
        for task in episodeIDToTask.values {
            task.cancel()
        }
        episodeIDToTask.removeAll()
        taskToEpisodeID.removeAll()
        lastPersistedProgressByEpisodeID.removeAll()
        lastProgressSaveDateByEpisodeID.removeAll()
        hasReconciledPersistedState = false
        backgroundCompletionHandler = nil
        // 2. Drop the model context last — other steps may want to log
        //    or read it on the way out.
        modelContext = nil
    }
    #endif

    private func beginDownload(for episode: Episode) {
        let task = session.downloadTask(with: episode.audioURL)
        task.taskDescription = episode.id.uuidString
        taskToEpisodeID[task.taskIdentifier] = episode.id
        episodeIDToTask[episode.id] = task
        episode.downloadState = .downloading
        episode.downloadErrorMessage = nil
        modelContext?.saveOrLog("DownloadService")
        TelemetryService.track(
            "download_requested",
            metadata: ["episode": episode.title, "podcast": episode.podcast.title],
            in: modelContext
        )
        task.resume()
    }

    private func resumeQueuedDownloadsIfNeeded() {
        guard activeDownloadCount < maximumConcurrentDownloads, let modelContext else { return }
        guard isAllowedOnCurrentNetwork else { return }
        let queuedState = Episode.DownloadState.queued.rawValue
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.downloadStateRawValue == queuedState },
            sortBy: [SortDescriptor(\Episode.downloadRequestedAt)]
        )
        let queuedEpisodes: [Episode]
        do {
            queuedEpisodes = try modelContext.fetch(descriptor)
        } catch {
            downloadLogger.error("resumeQueuedDownloadsIfNeeded fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        let availableSlots = max(maximumConcurrentDownloads - activeDownloadCount, 0)
        for episode in queuedEpisodes.prefix(availableSlots) {
            beginDownload(for: episode)
        }
    }

    func reconcilePersistedDownloads() {
        guard let modelContext else { return }
        let downloadedState = Episode.DownloadState.downloaded.rawValue
        let queuedState = Episode.DownloadState.queued.rawValue
        let downloadingState = Episode.DownloadState.downloading.rawValue
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> {
                $0.downloadStateRawValue == downloadedState
                    || $0.downloadStateRawValue == queuedState
                    || $0.downloadStateRawValue == downloadingState
            }
        )
        let storedEpisodes: [Episode]
        do {
            storedEpisodes = try modelContext.fetch(descriptor)
        } catch {
            downloadLogger.error("reconcilePersistedDownloads fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        for episode in storedEpisodes {
            switch episode.downloadState {
            case .downloaded:
                _ = localURL(for: episode)
            case .queued, .downloading:
                if localURL(for: episode) != nil {
                    episode.downloadState = .downloaded
                    episode.downloadProgress = 1
                    episode.isDownloaded = true
                    episode.downloadErrorMessage = nil
                } else {
                    episode.downloadState = .failed
                    episode.downloadProgress = 0
                    episode.isDownloaded = false
                    episode.downloadErrorMessage = "Download was interrupted. Retry to save this episode offline."
                }
            case .failed, .notDownloaded:
                break
            }
        }

        modelContext.saveOrLog("DownloadService")
    }

    /// Sweep the Downloads directory for files that no `Episode` claims.
    ///
    /// Orphans happen when:
    ///   - The user unsubscribed mid-download and the URLSession landed the
    ///     file after the model row was already gone.
    ///   - SwiftData cascade-deletion ran but the file delete failed (low-
    ///     disk, file system error, etc).
    ///   - An upgrade path renamed the destination scheme and old files were
    ///     left behind.
    ///
    /// Filenames are `<episodeUUID>.<ext>`, so we can match each file to a
    /// live Episode by parsing the basename. Anything that doesn't resolve
    /// gets deleted.
    func sweepOrphanDownloadFiles() {
        guard let modelContext else { return }
        let supportURL = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        guard let downloadsURL = supportURL?.appending(path: "Downloads", directoryHint: .isDirectory) else { return }
        guard FileManager.default.fileExists(atPath: downloadsURL.path) else { return }

        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: downloadsURL, includingPropertiesForKeys: nil)
        } catch {
            downloadLogger.error("sweepOrphanDownloadFiles list failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        var removedCount = 0
        for fileURL in files {
            let basename = fileURL.deletingPathExtension().lastPathComponent
            guard let episodeID = UUID(uuidString: basename) else {
                // Unknown file format in the Downloads dir — leave it alone.
                continue
            }

            let descriptor = FetchDescriptor<Episode>(
                predicate: #Predicate<Episode> { $0.id == episodeID }
            )
            let owner = try? modelContext.fetch(descriptor).first
            if owner == nil {
                removeFileIfPresent(at: fileURL)
                removedCount += 1
            }
        }

        if removedCount > 0 {
            downloadLogger.info("Removed \(removedCount) orphan download file(s)")
        }
    }

    private func removeFileIfPresent(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            downloadLogger.error("Failed to remove downloaded file at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func shouldPersistProgress(_ progress: Double, for episodeID: UUID) -> Bool {
        if progress >= 1 { return true }
        let lastProgress = lastPersistedProgressByEpisodeID[episodeID] ?? 0
        let progressedEnough = progress - lastProgress >= 0.05
        let lastSave = lastProgressSaveDateByEpisodeID[episodeID] ?? .distantPast
        let waitedEnough = Date().timeIntervalSince(lastSave) >= 3
        return progressedEnough || waitedEnough
    }

    private func markProgressPersisted(_ progress: Double, for episodeID: UUID) {
        lastPersistedProgressByEpisodeID[episodeID] = progress
        lastProgressSaveDateByEpisodeID[episodeID] = .now
    }

    private func clearProgressThrottle(for episodeID: UUID) {
        lastPersistedProgressByEpisodeID.removeValue(forKey: episodeID)
        lastProgressSaveDateByEpisodeID.removeValue(forKey: episodeID)
    }
}

extension DownloadService: URLSessionDownloadDelegate, URLSessionTaskDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }

        let progress = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1)
        Task { @MainActor in
            guard let episodeID = self.taskToEpisodeID[downloadTask.taskIdentifier] else { return }
            self.objectWillChange.send()
            guard let episode = self.episode(for: episodeID) else {
                // Episode was deleted mid-download (e.g., user
                // unsubscribed). Cancel the task and drop the dictionary
                // entries so we don't leak references for the lifetime
                // of the app.
                downloadTask.cancel()
                self.taskToEpisodeID.removeValue(forKey: downloadTask.taskIdentifier)
                self.episodeIDToTask.removeValue(forKey: episodeID)
                self.clearProgressThrottle(for: episodeID)
                return
            }
            episode.downloadState = .downloading
            episode.downloadProgress = progress
            guard self.shouldPersistProgress(progress, for: episodeID) else { return }
            self.markProgressPersisted(progress, for: episodeID)
            self.modelContext?.saveOrLog("DownloadService")
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        Task { @MainActor in
            guard let episodeID = self.taskToEpisodeID[downloadTask.taskIdentifier] else { return }
            self.objectWillChange.send()
            guard let episode = self.episode(for: episodeID) else {
                // Episode disappeared between download start and finish
                // (unsubscribe). Drop the task entries and remove any
                // file that already landed.
                self.taskToEpisodeID.removeValue(forKey: downloadTask.taskIdentifier)
                self.episodeIDToTask.removeValue(forKey: episodeID)
                self.clearProgressThrottle(for: episodeID)
                self.removeFileIfPresent(at: location)
                return
            }
            do {
                let destinationURL = try self.destinationURL(for: episodeID, originalURL: episode.audioURL)
                self.removeFileIfPresent(at: destinationURL)
                try FileManager.default.moveItem(at: location, to: destinationURL)
                episode.localFileURL = destinationURL
                episode.downloadState = .downloaded
                episode.downloadProgress = 1
                episode.downloadCompletedAt = .now
                episode.downloadErrorMessage = nil
                episode.isDownloaded = true
                self.modelContext?.saveOrLog("DownloadService")
                TelemetryService.track(
                    "download_completed",
                    metadata: ["episode": episode.title, "podcast": episode.podcast.title],
                    in: self.modelContext
                )
                // Opportunistic background transcription. Service decides
                // whether to actually run based on Wi-Fi + power state.
                BackgroundTranscriptionService.shared.didFinishDownload(episodeID: episodeID)
            } catch {
                episode.downloadState = .failed
                episode.downloadErrorMessage = error.localizedDescription
                episode.isDownloaded = false
                self.modelContext?.saveOrLog("DownloadService")
                TelemetryService.track(
                    "download_failed",
                    metadata: [
                        "episode": episode.title,
                        "podcast": episode.podcast.title,
                        "error": error.localizedDescription
                    ],
                    in: self.modelContext
                )
            }

            self.episodeIDToTask[episodeID] = nil
            self.taskToEpisodeID[downloadTask.taskIdentifier] = nil
            self.clearProgressThrottle(for: episodeID)
            self.resumeQueuedDownloadsIfNeeded()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }

        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled {
            Task { @MainActor in
                guard let episodeID = self.taskToEpisodeID[task.taskIdentifier] else { return }
                self.taskToEpisodeID[task.taskIdentifier] = nil
                self.episodeIDToTask[episodeID] = nil
                self.clearProgressThrottle(for: episodeID)
                self.resumeQueuedDownloadsIfNeeded()
            }
            return
        }

        Task { @MainActor in
            guard let episodeID = self.taskToEpisodeID[task.taskIdentifier] else { return }
            self.objectWillChange.send()
            guard let episode = self.episode(for: episodeID) else {
                // Episode was deleted while the download was in flight.
                // Drop the dict entries so they don't pin the IDs forever.
                self.taskToEpisodeID.removeValue(forKey: task.taskIdentifier)
                self.episodeIDToTask.removeValue(forKey: episodeID)
                self.clearProgressThrottle(for: episodeID)
                self.resumeQueuedDownloadsIfNeeded()
                return
            }
            episode.downloadState = .failed
            episode.downloadErrorMessage = error.localizedDescription
            episode.downloadProgress = 0
            episode.isDownloaded = false
            self.episodeIDToTask[episodeID] = nil
            self.taskToEpisodeID[task.taskIdentifier] = nil
            self.clearProgressThrottle(for: episodeID)
            self.modelContext?.saveOrLog("DownloadService")
            TelemetryService.track(
                "download_failed",
                metadata: [
                    "episode": episode.title,
                    "podcast": episode.podcast.title,
                    "error": error.localizedDescription
                ],
                in: self.modelContext
            )
            self.resumeQueuedDownloadsIfNeeded()
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}

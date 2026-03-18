import Combine
import Foundation
import SwiftData

@MainActor
final class DownloadService: NSObject, ObservableObject {
    static let shared = DownloadService()
    private let maximumConcurrentDownloads = 2

    let objectWillChange = ObservableObjectPublisher()

    private var session: URLSession!
    private var modelContext: ModelContext?
    private var taskToEpisodeID: [Int: UUID] = [:]
    private var episodeIDToTask: [UUID: URLSessionDownloadTask] = [:]
    private var hasReconciledPersistedState = false

    private override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func configure(context: ModelContext) {
        modelContext = context
        guard !hasReconciledPersistedState else { return }
        reconcilePersistedDownloads()
        hasReconciledPersistedState = true
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
            try? modelContext?.save()
            TelemetryService.track(
                "download_resolved_from_disk",
                metadata: ["episode": episode.title, "podcast": episode.podcast.title],
                in: modelContext
            )
            return
        }

        let task = session.downloadTask(with: episode.audioURL)
        taskToEpisodeID[task.taskIdentifier] = episode.id
        episodeIDToTask[episode.id] = task
        episode.downloadRequestedAt = .now
        episode.downloadCompletedAt = nil
        episode.downloadErrorMessage = nil
        episode.downloadProgress = 0
        episode.downloadState = .queued
        episode.isDownloaded = false
        try? modelContext?.save()

        if activeDownloadCount < maximumConcurrentDownloads {
            beginDownload(for: episode)
        } else {
            TelemetryService.track(
                "download_queued",
                metadata: ["episode": episode.title, "podcast": episode.podcast.title],
                in: modelContext
            )
        }
    }

    func cancelDownload(for episode: Episode) {
        objectWillChange.send()
        if episode.downloadState == .queued, episodeIDToTask[episode.id] == nil {
            episode.downloadState = .notDownloaded
            episode.downloadProgress = 0
            episode.downloadErrorMessage = nil
            episode.downloadRequestedAt = nil
            episode.isDownloaded = false
            try? modelContext?.save()
            TelemetryService.track(
                "download_cancelled",
                metadata: ["episode": episode.title, "podcast": episode.podcast.title],
                in: modelContext
            )
            return
        }

        episodeIDToTask[episode.id]?.cancel()
        episodeIDToTask[episode.id] = nil
        episode.downloadState = episode.localFileURL == nil ? .notDownloaded : .downloaded
        episode.downloadProgress = episode.localFileURL == nil ? 0 : 1
        episode.isDownloaded = episode.localFileURL != nil
        try? modelContext?.save()
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
            try? FileManager.default.removeItem(at: url)
        }
        episode.localFileURL = nil
        episode.downloadState = .notDownloaded
        episode.downloadProgress = 0
        episode.downloadCompletedAt = nil
        episode.downloadErrorMessage = nil
        episode.isDownloaded = false
        try? modelContext?.save()
        TelemetryService.track(
            "download_deleted",
            metadata: ["episode": episode.title, "podcast": episode.podcast.title],
            in: modelContext
        )
        resumeQueuedDownloadsIfNeeded()
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
        try? modelContext?.save()
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
        let ext = originalURL?.pathExtension.isEmpty == false ? originalURL!.pathExtension : "mp3"
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

    private func beginDownload(for episode: Episode) {
        let task = session.downloadTask(with: episode.audioURL)
        task.taskDescription = episode.id.uuidString
        taskToEpisodeID[task.taskIdentifier] = episode.id
        episodeIDToTask[episode.id] = task
        episode.downloadState = .downloading
        episode.downloadErrorMessage = nil
        try? modelContext?.save()
        TelemetryService.track(
            "download_requested",
            metadata: ["episode": episode.title, "podcast": episode.podcast.title],
            in: modelContext
        )
        task.resume()
    }

    private func resumeQueuedDownloadsIfNeeded() {
        guard activeDownloadCount < maximumConcurrentDownloads, let modelContext else { return }
        let descriptor = FetchDescriptor<Episode>()
        guard let queuedEpisodes = try? modelContext.fetch(descriptor)
            .filter({ $0.downloadState == .queued }) else { return }

        let availableSlots = max(maximumConcurrentDownloads - activeDownloadCount, 0)
        for episode in queuedEpisodes.prefix(availableSlots) {
            beginDownload(for: episode)
        }
    }

    func reconcilePersistedDownloads() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<Episode>()
        guard let storedEpisodes = try? modelContext.fetch(descriptor) else { return }

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

        try? modelContext.save()
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
            guard let episode = self.episode(for: episodeID) else { return }
            episode.downloadState = .downloading
            episode.downloadProgress = progress
            try? self.modelContext?.save()
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
            guard let episode = self.episode(for: episodeID) else { return }
            do {
                let destinationURL = try self.destinationURL(for: episodeID, originalURL: episode.audioURL)
                try? FileManager.default.removeItem(at: destinationURL)
                try FileManager.default.moveItem(at: location, to: destinationURL)
                episode.localFileURL = destinationURL
                episode.downloadState = .downloaded
                episode.downloadProgress = 1
                episode.downloadCompletedAt = .now
                episode.downloadErrorMessage = nil
                episode.isDownloaded = true
                try? self.modelContext?.save()
                TelemetryService.track(
                    "download_completed",
                    metadata: ["episode": episode.title, "podcast": episode.podcast.title],
                    in: self.modelContext
                )
            } catch {
                episode.downloadState = .failed
                episode.downloadErrorMessage = error.localizedDescription
                episode.isDownloaded = false
                try? self.modelContext?.save()
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
                self.resumeQueuedDownloadsIfNeeded()
            }
            return
        }

        Task { @MainActor in
            guard let episodeID = self.taskToEpisodeID[task.taskIdentifier] else { return }
            self.objectWillChange.send()
            guard let episode = self.episode(for: episodeID) else { return }
            episode.downloadState = .failed
            episode.downloadErrorMessage = error.localizedDescription
            episode.downloadProgress = 0
            episode.isDownloaded = false
            self.episodeIDToTask[episodeID] = nil
            self.taskToEpisodeID[task.taskIdentifier] = nil
            try? self.modelContext?.save()
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
}

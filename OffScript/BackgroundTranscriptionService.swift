import Foundation
import Network
import OSLog
import SwiftData
import UIKit

private let bgTranscribeLogger = Logger(subsystem: "com.offscript", category: "BackgroundTranscription")

/// Opportunistically transcribes recently-downloaded episodes in the
/// background, so by the time the user opens EpisodeDetailView the transcript
/// is already there.
///
/// Policy:
///   - Only run when on Wi-Fi and plugged in (or `.isLowPowerModeEnabled == false`)
///   - Process at most 1 episode at a time — Speech is CPU-heavy
///   - Skip episodes that already have a persisted transcript
///   - Skip episodes longer than 90 minutes (Speech struggles with long-form
///     in a single shot; a future SpeechAnalyzer-based path will handle these)
///   - Each transcription respects the same on-device privacy guarantees as
///     the foreground path
@MainActor
final class BackgroundTranscriptionService {
    static let shared = BackgroundTranscriptionService()

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.offscript.bgtranscribe.monitor")
    private var modelContext: ModelContext?
    private var workTask: Task<Void, Never>?
    private var isOnWiFi = false

    private let maxDurationSeconds: TimeInterval = 90 * 60

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isOnWiFi = path.usesInterfaceType(.wifi) && path.status == .satisfied
                self?.scheduleScanIfPossible()
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func configure(context: ModelContext) {
        modelContext = context
        scheduleScanIfPossible()
    }

    /// Hook from DownloadService — called after a successful download so we
    /// can immediately consider the episode for transcription.
    func didFinishDownload(episodeID: UUID) {
        scheduleScanIfPossible()
    }

    private var canRun: Bool {
        let device = UIDevice.current
        let isCharging = device.batteryState == .charging || device.batteryState == .full
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        return isOnWiFi && (isCharging || !lowPower)
    }

    private func scheduleScanIfPossible() {
        guard workTask == nil, canRun, modelContext != nil else { return }
        workTask = Task { @MainActor [weak self] in
            await self?.runScanLoop()
            self?.workTask = nil
        }
    }

    private func runScanLoop() async {
        guard let context = modelContext else { return }

        UIDevice.current.isBatteryMonitoringEnabled = true

        while canRun, let next = nextCandidate(in: context) {
            guard let localURL = DownloadService.shared.localURL(for: next) else {
                bgTranscribeLogger.info("Skipping \(next.title, privacy: .public) — local file vanished")
                continue
            }

            bgTranscribeLogger.info("Transcribing in background: \(next.title, privacy: .public)")
            do {
                _ = try await SpeechTranscriptionService.shared.transcribe(
                    episode: next,
                    localAudioURL: localURL,
                    persistTo: context
                )
            } catch {
                bgTranscribeLogger.error("Background transcription failed for \(next.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
                // Don't mark the episode as failed — let the user retry
                // foreground. Just bail this loop iteration.
                break
            }

            // Yield between episodes so we don't monopolize the main actor.
            await Task.yield()
        }
    }

    /// Returns the next downloaded episode that has no persisted transcript.
    /// Bounded fetch — checks at most 25 newest downloads per scan.
    private func nextCandidate(in context: ModelContext) -> Episode? {
        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.isDownloaded == true },
            sortBy: [SortDescriptor(\Episode.downloadCompletedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 25
        guard let downloaded = try? context.fetch(descriptor) else { return nil }

        for episode in downloaded {
            // Filter on duration in-memory — duration is optional so it can't
            // be expressed as a #Predicate cleanly.
            if let duration = episode.duration, duration > maxDurationSeconds { continue }
            // Skip if already transcribed (persisted).
            if SpeechTranscriptionService.shared.persistedTranscript(for: episode.id, in: context) != nil {
                continue
            }
            return episode
        }
        return nil
    }
}

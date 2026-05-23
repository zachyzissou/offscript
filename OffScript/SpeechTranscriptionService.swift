import AVFoundation
import Foundation
import OSLog
import Speech
import SwiftData

private let speechLogger = Logger(subsystem: "com.offscript", category: "SpeechTranscription")

private final class SpeechRecognitionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var task: SFSpeechRecognitionTask?

    nonisolated func set(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    nonisolated func cancel() {
        lock.lock()
        let task = task
        self.task = nil
        lock.unlock()
        task?.cancel()
    }
}

/// On-device transcription via Apple's Speech framework. We use this as a
/// fallback when an episode has no published transcript URL — common for
/// indie shows and most legacy back-catalogs.
///
/// Strategy:
/// - Requires `SFSpeechRecognizer.requestAuthorization(.authorized)` at first use
/// - Forces `requiresOnDeviceRecognition = true` — never sends audio to Apple servers
/// - Streams the local audio file in chunks; emits progress + final text
/// - Caches by episode ID (process lifetime)
///
/// **Not yet wired to UI.** This service is the foundation; the next pass
/// will add a "Generate Transcript" button on EpisodeDetailView that runs
/// this and persists the output to a new `EpisodeTranscriptCache` model.
@MainActor
final class SpeechTranscriptionService {
    static let shared = SpeechTranscriptionService()

    private var cache: [UUID: String] = [:]
    /// Insertion-order tracking for LRU eviction. We keep at most `maxCachedTranscripts`
    /// entries — a full-episode transcript can easily be 100 KB, so an unbounded
    /// process-lifetime cache is a real memory-pressure risk.
    private var cacheOrder: [UUID] = []
    private let maxCachedTranscripts = 5

    private init() {}

    /// Stores a transcript, evicting the oldest entry if the cap is exceeded.
    private func storeTranscript(_ text: String, for id: UUID) {
        if cache[id] != nil {
            // Already present — refresh position in order list.
            if let idx = cacheOrder.firstIndex(of: id) {
                cacheOrder.remove(at: idx)
            }
        } else if cache.count >= maxCachedTranscripts, let oldest = cacheOrder.first {
            cache.removeValue(forKey: oldest)
            cacheOrder.removeFirst()
        }
        cache[id] = text
        cacheOrder.append(id)
    }

    enum TranscriptionError: Error {
        case notAuthorized
        case onDeviceUnavailable
        case noLocalAudio
        case recognitionFailed(String)
    }

    /// Returns cached transcript if present in either the in-memory cache
    /// or persisted via SwiftData. Synchronous — safe for view bodies.
    func cachedTranscript(for episodeID: UUID) -> String? {
        cache[episodeID]
    }

    /// Persisted transcript lookup. Hits SQLite via a scoped FetchDescriptor;
    /// fast (single uniqueIdentifier match). Hydrates the in-memory cache so
    /// subsequent view body calls take the synchronous fast path.
    func persistedTranscript(for episodeID: UUID, in context: ModelContext) -> String? {
        if let inMemory = cache[episodeID] { return inMemory }

        var descriptor = FetchDescriptor<EpisodeTranscriptCache>(
            predicate: #Predicate<EpisodeTranscriptCache> { $0.episodeID == episodeID }
        )
        descriptor.fetchLimit = 1

        let entry: EpisodeTranscriptCache?
        do {
            entry = try context.fetch(descriptor).first
        } catch {
            speechLogger.error("Failed to fetch cached transcript for episode \(episodeID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let entry else { return nil }
        // Hydrate via LRU-aware path so the cap stays honoured.
        storeTranscript(entry.text, for: episodeID)
        return entry.text
    }

    /// Request Speech permission. Idempotent — ok to call repeatedly.
    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Transcribe a local audio file end-to-end on-device. Episode must already
    /// be downloaded via DownloadService (we don't stream — too slow for
    /// long-form). Persists to `EpisodeTranscriptCache` if a context is
    /// supplied so the result survives app restarts. Throws if the user
    /// declined permission or device can't do on-device recognition for the
    /// locale.
    func transcribe(
        episode: Episode,
        localAudioURL: URL,
        persistTo context: ModelContext? = nil
    ) async throws -> String {
        if let cached = cache[episode.id] { return cached }

        // Persisted hit — return it without burning Speech cycles.
        if let context, let stored = persistedTranscript(for: episode.id, in: context) {
            return stored
        }
        try Task.checkCancellation()

        // If the feed publishes an authoritative transcript, prefer that
        // over running Speech recognition. Publisher transcripts are faster
        // to obtain (single HTTP fetch), more accurate (publisher-edited),
        // and may carry speaker labels Speech can't produce. See
        // PublishedTranscriptLoader for format/locale selection rules.
        if !episode.transcriptReferences.isEmpty,
           let loaded = await PublishedTranscriptLoader.fetchPublishedTranscript(
                for: episode,
                persistTo: context
           ) {
            storeTranscript(loaded.plainText, for: episode.id)
            return loaded.plainText
        }

        let status = await requestAuthorization()
        guard status == .authorized else {
            throw TranscriptionError.notAuthorized
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            speechLogger.warning("SFSpeechRecognizer init failed for locale=en-US — Speech framework refused locale")
            throw TranscriptionError.onDeviceUnavailable
        }
        guard recognizer.isAvailable else {
            speechLogger.warning("SFSpeechRecognizer unavailable (likely network/state) — refusing to fall back to cloud")
            throw TranscriptionError.onDeviceUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            // Critical privacy guardrail: without on-device support, the
            // Speech framework would otherwise ship audio to Apple servers.
            // CLAUDE.md says "No cloud round-trip; no third-party API keys
            // touch listening data" — surface this loudly rather than
            // silently falling over.
            speechLogger.warning("On-device Speech recognition not supported on this device/locale — aborting (no cloud fallback by policy)")
            throw TranscriptionError.onDeviceUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: localAudioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        let cancellation = SpeechRecognitionCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var didResume = false
            let resume: (Result<String, Error>) -> Void = { result in
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let error {
                    speechLogger.error("Recognition failed: \(error.localizedDescription, privacy: .public)")
                    resume(.failure(TranscriptionError.recognitionFailed(error.localizedDescription)))
                    return
                }

                guard let result, result.isFinal else { return }

                let text = result.bestTranscription.formattedString
                Task { @MainActor [weak self] in
                    // LRU-bounded in-memory cache (Copilot review fix) + the
                    // SwiftData persistence layer added in push 3 — keep both.
                    self?.storeTranscript(text, for: episode.id)
                    if let context {
                        let entry = EpisodeTranscriptCache(
                            episodeID: episode.id,
                            text: text,
                            generatedAt: .now,
                            source: "speech",
                            coverageSeconds: episode.duration
                        )
                        context.insert(entry)
                        do {
                            try context.save()
                        } catch {
                            speechLogger.error("Failed to persist transcript: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                }
                resume(.success(text))
            }
            cancellation.set(task)
        }
        } onCancel: {
            cancellation.cancel()
        }
    }
}

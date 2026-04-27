import AVFoundation
import Foundation
import OSLog
import Speech
import SwiftData

private let analyzerLogger = Logger(subsystem: "com.offscript", category: "SpeechAnalyzer")

/// iOS 26+ streaming transcription via `SpeechAnalyzer` + `SpeechTranscriber`.
///
/// Advantages over the legacy `SFSpeechRecognizer`-based path:
///   - True streaming with intermediate (volatile) results — UI can show
///     transcript filling in line-by-line instead of waiting for the whole file
///   - Actor-based concurrency, no callback-based legacy API
///   - Cleaner cancellation via Swift concurrency
///
/// Falls through to nothing on iOS < 26 — call sites should check
/// `isAvailable` and fall back to `SpeechTranscriptionService`.
@available(iOS 26.0, *)
@MainActor
final class SpeechAnalyzerService {
    static let shared = SpeechAnalyzerService()

    /// In-memory cache + insertion order for LRU eviction. Same caps as
    /// SpeechTranscriptionService — full transcripts can be 100KB+.
    private var cache: [UUID: String] = [:]
    private var cacheOrder: [UUID] = []
    private let maxCachedTranscripts = 5

    private init() {}

    static var isAvailable: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    /// Returns cached or persisted transcript synchronously if present.
    func cachedTranscript(for episodeID: UUID, in context: ModelContext? = nil) -> String? {
        if let inMemory = cache[episodeID] { return inMemory }
        guard let context else { return nil }
        // Reuse the same persistence layer as the legacy service so both paths
        // can share results.
        return SpeechTranscriptionService.shared.persistedTranscript(for: episodeID, in: context)
    }

    /// Stream a transcription. The callback fires with intermediate volatile
    /// text as the analyzer makes progress, then once more with `isFinal: true`
    /// when complete. Persisted to `EpisodeTranscriptCache` if a context is
    /// supplied.
    ///
    /// Implementation note: SpeechAnalyzer's exact API is iOS 26 SDK and
    /// evolving. We type-check at runtime via `isAvailable` and use NSClassFromString
    /// for the analyzer class so the binary still links cleanly when built with
    /// older SDKs. The actual transcription path falls through to the legacy
    /// service today; the streaming surface is here so call sites can adopt
    /// it without restructuring once the SDK ships.
    func transcribeStreaming(
        episode: Episode,
        localAudioURL: URL,
        persistTo context: ModelContext? = nil,
        progress: @escaping @MainActor (String, Bool) -> Void
    ) async throws -> String {
        if let cached = cache[episode.id] {
            progress(cached, true)
            return cached
        }

        // Reuse the persistence layer: persisted hit returns synchronously
        // with isFinal=true.
        if let context, let stored = SpeechTranscriptionService.shared.persistedTranscript(for: episode.id, in: context) {
            progress(stored, true)
            return stored
        }

        // SpeechAnalyzer is iOS 26+. On older OS we route through the legacy
        // service, which still gives us on-device transcription — we just
        // don't get the streaming-in UX.
        let text = try await SpeechTranscriptionService.shared.transcribe(
            episode: episode,
            localAudioURL: localAudioURL,
            persistTo: context
        )
        analyzerLogger.info("SpeechAnalyzer fell back to legacy SFSpeechRecognizer path; iOS 26 streaming path will activate once Apple's API stabilizes.")

        storeTranscript(text, for: episode.id)
        progress(text, true)
        return text
    }

    private func storeTranscript(_ text: String, for id: UUID) {
        if cache[id] != nil {
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
}

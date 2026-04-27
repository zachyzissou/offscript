import AVFoundation
import Foundation
import OSLog
import Speech

private let speechLogger = Logger(subsystem: "com.offscript", category: "SpeechTranscription")

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
    private var inFlightTask: Task<String?, Error>?

    private init() {}

    enum TranscriptionError: Error {
        case notAuthorized
        case onDeviceUnavailable
        case noLocalAudio
        case recognitionFailed(String)
    }

    /// Returns cached transcript if present, otherwise nil. Synchronous —
    /// safe for view bodies.
    func cachedTranscript(for episodeID: UUID) -> String? {
        cache[episodeID]
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
    /// long-form). Throws if the user declined permission or device can't do
    /// on-device recognition for the locale.
    func transcribe(episode: Episode, localAudioURL: URL) async throws -> String {
        if let cached = cache[episode.id] { return cached }

        let status = await requestAuthorization()
        guard status == .authorized else {
            throw TranscriptionError.notAuthorized
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.onDeviceUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: localAudioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var didResume = false
            let resume: (Result<String, Error>) -> Void = { result in
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let error {
                    speechLogger.error("Recognition failed: \(error.localizedDescription, privacy: .public)")
                    resume(.failure(TranscriptionError.recognitionFailed(error.localizedDescription)))
                    return
                }

                guard let result, result.isFinal else { return }

                let text = result.bestTranscription.formattedString
                Task { @MainActor [weak self] in
                    self?.cache[episode.id] = text
                }
                resume(.success(text))
            }
        }
    }
}

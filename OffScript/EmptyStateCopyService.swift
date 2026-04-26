import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels

@Generable(description: "An editorial one-liner for an empty UI state in a podcast app")
struct EmptyStateCopy {
    @Guide(description: "Two short sentences (max 22 words total). Confident, editorial voice. No emojis. No exclamation points.")
    var message: String
}
#endif

/// Generates contextual empty-state copy variants on device. Falls back to
/// curated lines when FoundationModels isn't available.
@MainActor
final class EmptyStateCopyService {
    static let shared = EmptyStateCopyService()

    private let logger = Logger(subsystem: "OffScript", category: "EmptyState")
    private var cache: [String: String] = [:]

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?

    private func makeSession() -> LanguageModelSession? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }
        if let session { return session }
        let s = LanguageModelSession(
            instructions: """
            You write editorial empty-state copy for a podcast app. Tone:
            confident, dry, never apologetic, no marketing speak. Reference the
            specific surface (queue, library, downloads) when given.
            """
        )
        session = s
        return s
    }
    #endif

    private init() {}

    func copy(for key: String, fallback: String, prompt: String) async -> String {
        if let cached = cache[key] { return cached }

        #if canImport(FoundationModels)
        if let session = makeSession() {
            do {
                let response = try await session.respond(
                    to: prompt,
                    generating: EmptyStateCopy.self,
                    options: GenerationOptions(temperature: 0.7)
                )
                let message = response.content.message.trimmingCharacters(in: .whitespacesAndNewlines)
                if !message.isEmpty {
                    cache[key] = message
                    return message
                }
            } catch {
                logger.warning("Empty state copy generation failed for \(key, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        #endif

        cache[key] = fallback
        return fallback
    }
}

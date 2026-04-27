import Foundation

#if canImport(FoundationModels)
import FoundationModels

@Generable(description: "A short, plain-English reason this episode was recommended.")
private struct GeneratedReason {
    @Guide(description: "One concrete sentence explaining why this episode was picked, ≤ 18 words. No marketing words. Reference the actual signal in plural-friendly second-person voice.")
    var reason: String
}
#endif

/// Generates the WHY copy under each recommendation.
///
/// The static templated copy ("Connects to \"\(tag)\" from episodes you liked")
/// works but reads like a CSV row. When Apple Intelligence is available we
/// replace it with one fluid sentence that actually justifies the pick using
/// the same signals (matching tags, show affinity, recency, duration fit).
///
/// - Strict latency budget: generation runs async; we never block the rail
///   render. Falls back to the static reason for the synchronous path.
/// - Per-episode cache for the lifetime of the process.
/// - Hidden completely on devices without Apple Intelligence — the existing
///   templated copy keeps showing.
enum RecommendationExplainer {
    private static var cache: [UUID: String] = [:]

    /// Returns a cached AI reason if one exists, nil otherwise. Synchronous —
    /// safe to call from view bodies for the cache hit path.
    static func cachedReason(for episodeID: UUID) -> String? {
        cache[episodeID]
    }

    /// Async on-device generation. The signals dictionary is the same set the
    /// templated explainer was using — we just hand them to the model and let
    /// it write a sentence.
    static func generateReason(
        episodeID: UUID,
        episodeTitle: String,
        showTitle: String,
        signals: [String: String]
    ) async -> String? {
        if let cached = cache[episodeID] { return cached }

        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        let signalLines = signals
            .sorted { $0.key < $1.key }
            .map { "- \($0.key): \($0.value)" }
            .joined(separator: "\n")

        let session = LanguageModelSession(
            instructions: """
            You write recommendation explanations for a podcast app.
            Be concrete and specific. Reference the actual signal you were given.
            Never use words like "fascinating," "compelling," "must-listen," "perfect for you."
            Speak in second person, ≤ 18 words, one sentence.
            """
        )

        let prompt = """
        Episode: \(episodeTitle)
        Show: \(showTitle)
        Signals that triggered this recommendation:
        \(signalLines)
        """

        do {
            let response = try await session.respond(
                to: "Explain in one sentence why this episode was picked:\n\(prompt)",
                generating: GeneratedReason.self,
                options: GenerationOptions(temperature: 0.4)
            )
            let trimmed = response.content.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count >= 12 else { return nil }
            cache[episodeID] = trimmed
            return trimmed
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}

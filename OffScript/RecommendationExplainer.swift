import Foundation

#if canImport(FoundationModels)
import FoundationModels

@Generable(description: "A short, plain-English reason this episode was recommended.")
private struct GeneratedReason {
    @Guide(description: "One concrete sentence explaining why this episode was picked, ≤ 18 words. No marketing words. Reference the actual signal in plural-friendly second-person voice.")
    var reason: String
}
#endif

#if canImport(FoundationModels)
@Generable(description: "A natural-sounding rewrite of a templated recommendation reason.")
private struct RephraseResult {
    @Guide(description: "One short sentence (≤ 15 words). Keep the meaning. Sound like a friend, not a CSV row. No marketing words.")
    var phrase: String
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

    /// Returns a cached AI reason if one exists (from either the full
    /// generator or the rephraser), nil otherwise. Synchronous — safe to call
    /// from view bodies for the cache-hit path.
    static func cachedReason(for episodeID: UUID) -> String? {
        if let direct = cache[episodeID] { return direct }
        // Best-effort match against the rephrase cache — it's keyed by
        // episodeID|fallbackHash, so any entry whose key starts with the
        // episode ID is valid.
        let prefix = "\(episodeID.uuidString)|"
        return rephraseCache.first(where: { $0.key.hasPrefix(prefix) })?.value
    }

    /// Lightweight rephrase of an existing templated reason. Cheap path used
    /// from rail cards — we just hand the model the static string and let it
    /// rewrite for cadence. Caches by episode ID + fallback hash so toggling
    /// rails doesn't re-spend cycles.
    static func rephrase(episodeID: UUID, fallback: String) async -> String? {
        let cacheKey = "\(episodeID.uuidString)|\(fallback.hashValue)"
        if let cached = rephraseCache[cacheKey] { return cached }

        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        // Don't burn cycles rewriting trivial tags.
        guard fallback.count >= 14 else { return nil }

        let session = LanguageModelSession(
            instructions: """
            You rephrase short recommendation labels for a podcast app.
            Keep the meaning. Make it sound like a friend recommending, not a database.
            Never invent new facts. Stay ≤ 15 words. One sentence.
            """
        )

        do {
            let response = try await session.respond(
                to: "Rephrase this recommendation reason in plain language:\n\(fallback)",
                generating: RephraseResult.self,
                options: GenerationOptions(temperature: 0.5)
            )
            let rewritten = response.content.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rewritten.isEmpty, rewritten.count >= 12, rewritten.count <= 90 else { return nil }
            rephraseCache[cacheKey] = rewritten
            return rewritten
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    private static var rephraseCache: [String: String] = [:]

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

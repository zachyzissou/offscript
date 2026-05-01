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

    /// Deterministic copy pass for the synchronous UI path. This uses the
    /// same signal trace that produced the score, so Home and Player can show
    /// authored WHY copy without waiting on FoundationModels availability.
    ///
    /// Pass `avoidingSource` to skip a specific source bucket when the caller
    /// has already rendered a card with that bucket — used by the Home
    /// discovery rail to vary copy across adjacent cards (#179).
    static func authoredReason(
        fallback: String,
        signals: [RecommendationSignal],
        avoidingSource: String? = nil
    ) -> String {
        var lookup: [String: String] = [:]
        for signal in signals {
            let key = signal.label.lowercased()
            if lookup[key] == nil {
                lookup[key] = signal.value
            }
        }
        let sources = signals
            .filter { $0.label.caseInsensitiveCompare("source") == .orderedSame }
            .map { $0.value.lowercased() }
        let source = authoredSource(from: sources, excluding: avoidingSource?.lowercased())

        if sources.contains("explicit signal"),
           sources.contains("show intent"),
           let tags = lookup["tags"],
           let show = lookup["show"],
           !tags.isEmpty,
           !show.isEmpty {
            return clipped("More from \(show), matching your \(joinedList(tags)) signal", maxCharacters: 72)
        }

        if sources.contains("completion"),
           sources.contains("tag match"),
           let tags = lookup["tags"],
           let show = lookup["show"],
           !tags.isEmpty,
           !show.isEmpty {
            return clipped("\(show) plus your \(joinedList(tags)) signal", maxCharacters: 72)
        }

        switch source {
        case "queue":
            if let position = lookup["position"] {
                return "Queued \(position) because you chose it"
            }
            return "Queued because you chose it"
        case "resume":
            if let left = lookup["left"] {
                return "\(left) left from your last session"
            }
            return "Ready to pick up from your last session"
        case "completion":
            if let show = lookup["show"], !show.isEmpty {
                return clipped("More from \(show), a show you keep finishing", maxCharacters: 72)
            }
            return "More from a show you keep finishing"
        case "show intent":
            if let show = lookup["show"], !show.isEmpty {
                return clipped("More from \(show), because you asked for it", maxCharacters: 72)
            }
            return "More from a show you chose"
        case "show affinity":
            if let show = lookup["show"], !show.isEmpty {
                return clipped("More from \(show), a show you already trust", maxCharacters: 72)
            }
            return "Similar to shows you keep finishing"
        case "same show":
            if let show = lookup["show"], !show.isEmpty {
                return clipped("More from \(show)", maxCharacters: 72)
            }
            return "More from the show already playing"
        case "tag match":
            if let tags = lookup["tags"], !tags.isEmpty {
                return clipped("Tuned to your saved \(joinedList(tags)) signal\(isPluralList(tags) ? "s" : "")", maxCharacters: 72)
            }
            return "Tuned to your saved listening signals"
        case "taste tag":
            if let tags = lookup["tags"], !tags.isEmpty {
                return clipped("Covers your \(joinedList(tags)) signal\(isPluralList(tags) ? "s" : "")", maxCharacters: 72)
            }
            return "Covers topics you keep choosing"
        case "topic overlap":
            if let tags = lookup["tags"], !tags.isEmpty {
                return clipped("Multiple topic matches: \(joinedList(tags))", maxCharacters: 72)
            }
            return "Multiple topic matches from your listens"
        case "recent interest":
            if let tag = lookup["tag"], !tag.isEmpty {
                return clipped("Fits your recent \(tag) signal", maxCharacters: 72)
            }
            return "Fits your recent listening signal"
        case "liked episode":
            if let tag = lookup["tag"], !tag.isEmpty {
                return clipped("Connects to \(tag) from episodes you liked", maxCharacters: 72)
            }
            return "Connects to episodes you liked"
        case "now playing":
            if let tag = lookup["tag"], !tag.isEmpty {
                return clipped("Pairs with your current \(tag) listen", maxCharacters: 72)
            }
            return "Pairs with what is playing now"
        case "genre":
            if let lane = lookup["lane"], !lane.isEmpty {
                if lookup["evidence"] != "local" {
                    return "A \(lane) lane pick to sample"
                }
                return "A \(lane) lane pick with local evidence behind it"
            }
            if lookup["evidence"] != "local" {
                return "A genre-lane pick to sample"
            }
            return "A genre-lane pick with local evidence behind it"
        case "fresh":
            if let show = lookup["show"], !show.isEmpty {
                return clipped("Fresh from \(show)", maxCharacters: 72)
            }
            if let age = lookup["age"] {
                return "Fresh episode, \(age) old"
            }
            return "Fresh from your subscribed channels"
        case "duration":
            if fallback.localizedCaseInsensitiveContains("quick"),
               let window = lookup["window"],
               !window.isEmpty {
                return "Quick \(window) listen"
            }
            if !fallback.localizedCaseInsensitiveContains("short-listen setting") {
                return clipped(fallback, maxCharacters: 72)
            }
            return "Fits your short-listen setting"
        case "latest episode":
            if let tags = lookup["tags"], !tags.isEmpty {
                return clipped("Latest episodes overlap your \(joinedList(tags)) signal", maxCharacters: 72)
            }
            return "Latest episodes overlap your saved signals"
        case "subscription":
            if let show = lookup["show"], !show.isEmpty {
                return clipped("From your subscribed show \(show)", maxCharacters: 72)
            }
            return "From a show in your library"
        case "available":
            if let show = lookup["show"], !show.isEmpty {
                return clipped("Available from \(show)", maxCharacters: 72)
            }
            return "Available from your library"
        case "discovery":
            return "Discovery match from your saved signals"
        default:
            return clipped(fallback, maxCharacters: 72)
        }
    }

    /// Picks the highest-priority source bucket present in `sources`, with an
    /// optional `excluding` parameter that skips a specific bucket so the
    /// discovery rail can vary copy across adjacent cards.
    static func authoredSource(from sources: [String], excluding: String? = nil) -> String? {
        let priority = [
            "queue",
            "resume",
            "latest episode",
            "explicit signal",
            "show intent",
            "tag match",
            "taste tag",
            "topic overlap",
            "recent interest",
            "liked episode",
            "now playing",
            "completion",
            "show affinity",
            "same show",
            "genre",
            "duration",
            "fresh",
            "subscription",
            "available",
            "discovery"
        ]
        if let chosen = priority.first(where: { sources.contains($0) && $0 != excluding }) {
            return chosen
        }
        // Either every priority match was excluded, or no priority match
        // exists. Fall back to the next non-excluded source, then the first
        // raw source if even that is empty.
        return sources.first(where: { $0 != excluding }) ?? sources.first
    }

    private static func joinedList(_ value: String) -> String {
        let parts = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count > 1 else { return parts.first ?? value }
        return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
    }

    private static func clipped(_ value: String, maxCharacters: Int) -> String {
        guard value.count > maxCharacters else { return value }
        let boundary = value.index(value.startIndex, offsetBy: max(0, maxCharacters - 1))
        let prefix = value[..<boundary]
        if let lastSpace = prefix.lastIndex(where: { $0 == " " }), lastSpace > value.startIndex {
            return String(prefix[..<lastSpace]) + "…"
        }
        return String(prefix) + "…"
    }

    private static func isPluralList(_ value: String) -> Bool {
        value.split(separator: ",").count > 1
    }

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

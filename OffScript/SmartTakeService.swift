import Foundation
import OSLog
import SwiftData

#if canImport(FoundationModels)
import FoundationModels

@Generable(description: "A short, opinionated reason this episode is worth a listen for the user")
struct SmartTake {
    @Guide(description: "1–2 sentence editor's pitch in active voice — concrete and confident, no hedging")
    var pitch: String
}
#endif

/// Generates an editorial "why this matters for you" line per episode using
/// FoundationModels grounded in the user's taste profile. Cached on
/// EpisodeProfile.summary so it only runs once per episode.
@MainActor
final class SmartTakeService {
    static let shared = SmartTakeService()

    private let logger = Logger(subsystem: "OffScript", category: "SmartTake")

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?

    private func makeSession() -> LanguageModelSession? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }
        if let session { return session }
        let session = LanguageModelSession(
            instructions: """
            You are an editorial podcast curator writing for a single reader.
            Speak in their voice — confident, concrete, never hedging.
            Cap responses to 1–2 short sentences. No emojis. No exclamation points.
            Reference the show name only if it adds context.
            """
        )
        self.session = session
        return session
    }
    #endif

    private init() {}

    /// Returns a cached take immediately if available; otherwise nil.
    func cached(for episode: Episode) -> String? {
        guard let summary = episode.profile?.summary, !summary.isEmpty else { return nil }
        return summary
    }

    /// Generates a take and caches it on EpisodeProfile.summary.
    func generate(for episode: Episode, in context: ModelContext) async -> String? {
        if let cached = cached(for: episode) {
            return cached
        }

        let prompt = await buildPrompt(for: episode, in: context)
        let take = await runModel(prompt: prompt, fallback: heuristicTake(for: episode))

        // Persist on EpisodeProfile so the next open is instant.
        let targetID = episode.id
        var descriptor = FetchDescriptor<EpisodeProfile>(
            predicate: #Predicate<EpisodeProfile> { $0.episodeID == targetID }
        )
        descriptor.fetchLimit = 1

        let profile: EpisodeProfile
        if let existing = try? context.fetch(descriptor).first {
            profile = existing
        } else {
            profile = EpisodeProfile(episodeID: episode.id)
            profile.episode = episode
            context.insert(profile)
        }
        profile.summary = take
        try? context.save()
        return take
    }

    // MARK: - Prompt + model

    private func buildPrompt(for episode: Episode, in context: ModelContext) async -> String {
        let podcast = episode.podcast
        let summary = (episode.summary ?? "").strippingHTML
        let trimmedSummary = String(summary.prefix(800))
        let tags = episode.profile?.tags.joined(separator: ", ") ?? ""

        // Pull the user's taste signals so the take can lean on what they
        // actually like, not just generic editorial vibes.
        let profile = (try? TasteProfileService.loadOrCreate(in: context))
        let topTags = profile?.topTags.prefix(6).joined(separator: ", ") ?? ""
        let preferredGenres = profile?.preferredGenres.prefix(4).joined(separator: ", ") ?? ""
        let avgMinutes = profile.map { Int($0.averageCompletedDurationMinutes) } ?? 0

        return """
        Show: \(podcast.title)
        Episode: \(episode.title)
        Tags: \(tags)
        Description: \(trimmedSummary)

        About this listener:
        - Recurring interests: \(topTags.isEmpty ? "—" : topTags)
        - Preferred genres: \(preferredGenres.isEmpty ? "—" : preferredGenres)
        - Typical episode length they finish: \(avgMinutes) minutes

        Write 1–2 sentences telling this listener why this specific episode is worth their time.
        Lead with the angle, not "this episode is about". Be specific to the topic, not generic.
        """
    }

    private func runModel(prompt: String, fallback: String) async -> String {
        #if canImport(FoundationModels)
        guard let session = makeSession() else {
            return fallback
        }
        do {
            let response = try await session.respond(
                to: prompt,
                generating: SmartTake.self,
                options: GenerationOptions(temperature: 0.5)
            )
            let pitch = response.content.pitch.trimmingCharacters(in: .whitespacesAndNewlines)
            return pitch.isEmpty ? fallback : pitch
        } catch {
            logger.warning("SmartTake generation failed: \(String(describing: error), privacy: .public)")
            return fallback
        }
        #else
        return fallback
        #endif
    }

    /// Public accessor so PlayerView can show *something* immediately while the
    /// FoundationModels-generated take resolves in the background.
    func heuristicTakePublic(for episode: Episode) -> String {
        heuristicTake(for: episode)
    }

    private func heuristicTake(for episode: Episode) -> String {
        let podcast = episode.podcast.title
        if let duration = episode.duration, duration > 0 {
            let minutes = Int(duration / 60)
            return "From \(podcast) — fits a \(minutes)-minute window with the kind of conversation you keep coming back to."
        }
        return "From \(podcast) — picked because it lines up with what you've been finishing lately."
    }
}

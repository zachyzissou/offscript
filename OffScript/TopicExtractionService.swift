import Foundation
import SwiftData
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels

@Generable(description: "Key topics, entities, and a short summary for a podcast episode")
struct EpisodeNLP {
    @Guide(description: "3–7 concise lowercase tags without punctuation", .count(3...7))
    var tags: [String]

    @Guide(description: "Important named entities like people, brands, or places", .count(0...6))
    var entities: [String]

    @Guide(description: "A brief, neutral 1–2 sentence summary")
    var summary: String
}
#endif

final class TopicExtractionService {
    #if canImport(FoundationModels)
    private let session: LanguageModelSession? = LanguageModelSession(
        instructions: """
        You analyze podcast episode titles and descriptions.
        Return concise, useful tags and entities. Avoid duplicates and junk.
        Keep output stable and deterministic.
        """
    )
    #else
    private let session: Any? = nil
    #endif

    func enrich(episode: Episode, in context: ModelContext) async throws {
        // Upsert profile
        let existing = try context.fetch(FetchDescriptor<EpisodeProfile>())
            .first(where: { $0.episodeID == episode.id })
        let profile = existing ?? {
            let p = EpisodeProfile(episodeID: episode.id)
            p.episode = episode
            return p
        }()

        let baseText = """
        Title: \(episode.title)
        Description: \(episode.summary ?? "")
        """

        var tags: [String] = []
        var entities: [String] = []
        var summary: String? = nil

        #if canImport(FoundationModels)
        if let session {
            do {
                let response = try await session.respond(
                    to: "Extract tags, entities, and a summary:\n\(baseText)",
                    generating: EpisodeNLP.self,
                    options: GenerationOptions(temperature: 0.2)
                )
                tags = response.content.tags
                entities = response.content.entities
                summary = response.content.summary
            } catch {
                // Fall back to heuristics on failure
                (tags, entities) = Self.heuristicTagsAndEntities(from: baseText)
            }
        } else {
            (tags, entities) = Self.heuristicTagsAndEntities(from: baseText)
        }
        #else
        (tags, entities) = Self.heuristicTagsAndEntities(from: baseText)
        #endif

        profile.tags = tags
        profile.entities = entities
        if summary != nil { profile.summary = summary }
        profile.confidenceScore = summary == nil ? 0.45 : 0.8
        profile.freshnessBucket = freshnessBucket(for: episode.pubDate)
        profile.estimatedListeningContext = listeningContext(for: episode.duration)

        if existing == nil { context.insert(profile) }
    }

    static func heuristicTags(from text: String) -> [String] {
        heuristicTagsAndEntities(from: text).0
    }

    static func heuristicTagsAndEntities(from text: String) -> ([String], [String]) {
        var tagCounts: [String: Int] = [:]
        var entities: Set<String> = []

        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = text
        let range = text.startIndex..<text.endIndex
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .omitOther]

        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            if tag == .personalName || tag == .organizationName || tag == .placeName {
                let token = String(text[tokenRange])
                entities.insert(token)
            }
            return true
        }

        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
            if tag == .noun {
                let token = String(text[tokenRange]).lowercased()
                if token.count > 2 { tagCounts[token, default: 0] += 1 }
            }
            return true
        }

        let tags = tagCounts.sorted { $0.value > $1.value }.prefix(7).map { $0.key }
        return (tags, Array(entities))
    }

    private func freshnessBucket(for date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        switch days {
        case ..<3: return "fresh"
        case ..<14: return "recent"
        default: return "catalog"
        }
    }

    private func listeningContext(for duration: TimeInterval?) -> String {
        guard let duration else { return "anytime" }
        switch duration / 60 {
        case ..<20: return "quick"
        case ..<45: return "commute"
        default: return "deep-focus"
        }
    }
}

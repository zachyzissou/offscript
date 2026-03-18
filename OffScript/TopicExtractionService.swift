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
    private var cachedSession: LanguageModelSession?

    private func getSession() -> LanguageModelSession? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        if let cachedSession { return cachedSession }

        let session = LanguageModelSession(
            instructions: """
            You analyze podcast episode titles and descriptions.
            Return concise, useful tags and entities. Avoid duplicates and junk.
            Keep output stable and deterministic.
            """
        )
        return session
    }
    #endif

    func enrich(episode: Episode, in context: ModelContext) async throws {
        // Upsert profile — scoped fetch instead of loading ALL profiles
        let targetID = episode.id
        var profileDescriptor = FetchDescriptor<EpisodeProfile>(
            predicate: #Predicate<EpisodeProfile> { $0.episodeID == targetID }
        )
        profileDescriptor.fetchLimit = 1
        let existing = try context.fetch(profileDescriptor).first
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
        if let session = getSession() {
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

        if existing == nil { context.insert(profile) }
    }

    static func heuristicTags(from text: String) -> [String] {
        heuristicTagsAndEntities(from: text).0
    }

    private static let stopwords: Set<String> = [
        "episode", "show", "time", "way", "people", "thing", "year", "day",
        "week", "world", "part", "number", "point", "place", "case", "group",
        "problem", "fact", "lot", "kind", "stuff", "something", "anything",
        "everything", "nothing", "someone", "everyone", "title", "description",
        "question", "answer", "idea", "end", "start", "bit", "sort", "couple",
        "today", "tonight", "tomorrow", "yesterday", "morning", "afternoon",
        "evening", "life", "man", "woman", "guy", "hand", "head", "side",
        "room", "home", "word", "line", "example", "area", "moment", "reason",
        // HTML/URL noise
        "href", "https", "http", "www", "com", "org", "net", "html", "htm",
        "div", "span", "class", "img", "src", "alt", "rel", "target", "blank",
        "nofollow", "noopener", "noreferrer", "stylesheet", "type", "text",
        "link", "meta", "charset", "utf", "content", "width", "height",
        "style", "font", "color", "size", "padding", "margin", "border",
        "amp", "nbsp", "quot", "apos", "xml", "rss", "url", "uri"
    ]

    private static func stripHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&\\w+;", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func heuristicTagsAndEntities(from text: String) -> ([String], [String]) {
        let cleanText = stripHTML(text)
        var tagCounts: [String: Int] = [:]
        var entities: Set<String> = []

        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = cleanText
        let range = cleanText.startIndex..<cleanText.endIndex
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .omitOther]

        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            if tag == .personalName || tag == .organizationName || tag == .placeName {
                let token = String(cleanText[tokenRange])
                entities.insert(token)
            }
            return true
        }

        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
            if tag == .noun {
                let token = String(cleanText[tokenRange]).lowercased()
                if token.count > 2, !stopwords.contains(token) {
                    tagCounts[token, default: 0] += 1
                }
            }
            return true
        }

        let tags = tagCounts.sorted { $0.value > $1.value }.prefix(7).map { $0.key }
        return (tags, Array(entities))
    }

}

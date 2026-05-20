import Foundation
import NaturalLanguage
import OSLog
import SwiftData

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

/// "What you'll learn" briefing — three concrete bullet takeaways, written in
/// the second person, no marketing fluff, no spoilers framed as questions.
/// Generated on-device via Apple Intelligence so the user never sees a network
/// spinner and we never leak the episode summary off-device.
@Generable(description: "A pre-listen briefing for a podcast episode")
struct EpisodeBriefing {
    @Guide(description: "Three concrete bullet takeaways the listener will get from this episode. Each bullet is one short sentence, second-person, no marketing language.", .count(3))
    var bullets: [String]

    @Guide(description: "A single-sentence hook (≤ 20 words) that captures the central idea.")
    var hook: String
}
#endif

final class TopicExtractionService {
    private let logger = Logger(subsystem: "com.offscript", category: "TopicExtraction")
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
                logger.warning("FoundationModels extraction failed for episode \(episode.title, privacy: .public), falling back to heuristics: \(error.localizedDescription, privacy: .public)")
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
        profile.confidenceScore = Self.confidenceScore(tags: tags, entities: entities)

        if existing == nil { context.insert(profile) }
    }

    /// Heuristic [0,1] confidence in the extraction output for an episode.
    ///
    /// Higher when the extractor produced a richer, more diverse signal. The
    /// formula caps each axis independently so a noisy tag stream can't
    /// dominate, and gives entities a slight premium since named-entity
    /// extraction is harder than noun extraction.
    ///
    /// Floor of 0.0 when there is no signal at all (empty extraction). This is
    /// the only `EpisodeProfile` scoring field that has a cheap, honest,
    /// on-device producer today — see Models.swift dormancy notes on the
    /// other fields.
    static func confidenceScore(tags: [String], entities: [String]) -> Double {
        // Distinct, non-trivial signals only.
        let distinctTags = Set(tags.map { $0.lowercased() }).filter { $0.count > 2 }
        let distinctEntities = Set(entities.map { $0.lowercased() }).filter { $0.count > 1 }
        if distinctTags.isEmpty && distinctEntities.isEmpty { return 0 }
        // 7 tags = saturated tag axis (matches the Generable `.count(3...7)`
        // upper bound). 4 entities = saturated entity axis (slightly under the
        // Generable `.count(0...6)` cap; rare to see >4 distinct named entities
        // in a one-paragraph episode description).
        let tagAxis = min(Double(distinctTags.count) / 7.0, 1.0)
        let entityAxis = min(Double(distinctEntities.count) / 4.0, 1.0)
        // Tags weighted 0.6, entities 0.4 — entities are harder signal but
        // tags are the primary recommendation input.
        return min(1.0, tagAxis * 0.6 + entityAxis * 0.4)
    }

    func enrichHeuristically(episode: Episode, in context: ModelContext) throws {
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
        let (tags, entities) = Self.heuristicTagsAndEntities(from: baseText)
        profile.tags = tags
        profile.entities = entities
        profile.confidenceScore = Self.confidenceScore(tags: tags, entities: entities)

        if existing == nil { context.insert(profile) }
    }

    /// Generate a pre-listen briefing using on-device Apple Intelligence.
    /// Returns nil when FoundationModels is unavailable (older devices, region
    /// not enabled, model still downloading) — callers should hide the section.
    /// Cache by episode ID at the call site; this method does no caching.
    func briefing(for episode: Episode) async -> (bullets: [String], hook: String)? {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        let session = LanguageModelSession(
            instructions: """
            You write pre-listen briefings for podcast episodes.
            Be concrete. No marketing words like "fascinating," "incredible," "must-listen."
            Use second person. No spoilers framed as cliffhanger questions.
            """
        )

        let prompt = """
        Title: \(episode.title)
        Show: \(episode.podcast.title)
        Description: \(episode.summary?.strippingHTML ?? "")
        """

        do {
            let response = try await session.respond(
                to: "Write a pre-listen briefing:\n\(prompt)",
                generating: EpisodeBriefing.self,
                options: GenerationOptions(temperature: 0.3)
            )
            return (response.content.bullets, response.content.hook)
        } catch {
            logger.warning("FoundationModels briefing generation failed for \(episode.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        #else
        return nil
        #endif
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

        let range = cleanText.startIndex..<cleanText.endIndex
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = cleanText
        // Explicitly bind the language; on the iOS simulator (and on devices
        // where the on-device lexical-class / name-type models are missing or
        // not yet downloaded) NLTagger will silently emit no tags otherwise.
        tagger.setLanguage(.english, range: range)
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .omitOther]

        // `availableTagSchemes` tells us whether the on-device model is loaded.
        // On the simulator only Language/Script/TokenType are available for
        // .word, so we have to fall back to a tokenizer-based heuristic that
        // does not depend on lexical-class classification.
        let wordSchemes = NLTagger.availableTagSchemes(for: .word, language: .english)
        let hasLexicalClass = wordSchemes.contains(.lexicalClass)
        let hasNameType = wordSchemes.contains(.nameType)

        if hasNameType {
            tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
                if tag == .personalName || tag == .organizationName || tag == .placeName {
                    let token = String(cleanText[tokenRange])
                    entities.insert(token)
                }
                return true
            }
        }

        if hasLexicalClass {
            tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
                if tag == .noun {
                    let token = String(cleanText[tokenRange]).lowercased()
                    if token.count > 2, !stopwords.contains(token) {
                        tagCounts[token, default: 0] += 1
                    }
                }
                return true
            }
        } else {
            // Fallback: tokenize words and count anything that isn't a stopword
            // and isn't obviously a function word. This is dumber than the
            // lexical-class path but produces *something* useful so downstream
            // recommendation/topic plumbing has signal to work with.
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = cleanText
            tokenizer.setLanguage(.english)
            tokenizer.enumerateTokens(in: range) { tokenRange, _ in
                let raw = String(cleanText[tokenRange]).lowercased()
                // Strip trailing punctuation that the tokenizer leaves in.
                let token = raw.trimmingCharacters(in: .punctuationCharacters)
                if token.count > 2,
                   !stopwords.contains(token),
                   !Self.heuristicFunctionWords.contains(token),
                   token.rangeOfCharacter(from: .letters) != nil {
                    tagCounts[token, default: 0] += 1
                }
                return true
            }
        }

        let tags = tagCounts.sorted { $0.value > $1.value }.prefix(7).map { $0.key }
        return (tags, Array(entities))
    }

    /// Closed-class English words to exclude from the tokenizer fallback when
    /// the lexical-class model isn't available (e.g. iOS simulator). Keep this
    /// list short — these are very common function words that would otherwise
    /// dominate the tag count.
    private static let heuristicFunctionWords: Set<String> = [
        "the", "and", "but", "for", "with", "from", "this", "that", "these",
        "those", "you", "your", "yours", "they", "them", "their", "theirs",
        "have", "has", "had", "was", "were", "are", "been", "being", "will",
        "would", "could", "should", "shall", "may", "might", "must", "can",
        "cannot", "about", "into", "onto", "over", "under", "after", "before",
        "between", "through", "during", "while", "until", "since", "because",
        "where", "when", "what", "which", "who", "whom", "whose", "why", "how",
        "all", "any", "both", "each", "few", "more", "most", "some", "such",
        "only", "own", "same", "than", "too", "very", "just", "also", "then",
        "there", "here", "him", "her", "his", "she", "out", "off", "got",
        "get", "make", "made", "take", "took", "give", "gave", "going", "went",
        "say", "said", "says", "let", "lets", "way", "ways", "thing", "things",
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "yes", "yeah", "okay", "ok", "now", "still", "even", "back",
        "well", "much", "many", "lot", "lots", "really"
    ]

}

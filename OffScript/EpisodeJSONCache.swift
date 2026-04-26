import Foundation

/// Tiny in-memory LRU caching layer for the JSON-encoded blobs we keep on the
/// `Episode` model (chapters, transcripts). Computed-property accesses on
/// SwiftData models go through these closures every render — without caching,
/// each Home rail tile triggers a fresh JSONDecoder pass.
enum EpisodeJSONCache {
    private static let chapterCache = NSCache<NSString, NSArray>()
    private static let transcriptCache = NSCache<NSString, NSArray>()

    /// One shared decoder; JSONDecoder is thread-safe for `decode` calls and
    /// allocating a fresh one per call is measurable overhead in our hot path.
    static let sharedDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// One shared encoder for the inverse. Same threading guarantee.
    static let sharedEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static func chapters(forKey key: String) -> [EpisodeChapter] {
        guard !key.isEmpty else { return [] }
        let nsKey = key as NSString
        if let cached = chapterCache.object(forKey: nsKey) as? [EpisodeChapter] {
            return cached
        }
        guard let data = key.data(using: .utf8),
              let decoded = try? sharedDecoder.decode([EpisodeChapter].self, from: data) else {
            return []
        }
        chapterCache.setObject(decoded as NSArray, forKey: nsKey)
        return decoded
    }

    static func transcripts(forKey key: String) -> [EpisodeTranscriptReference] {
        guard !key.isEmpty else { return [] }
        let nsKey = key as NSString
        if let cached = transcriptCache.object(forKey: nsKey) as? [EpisodeTranscriptReference] {
            return cached
        }
        guard let data = key.data(using: .utf8),
              let decoded = try? sharedDecoder.decode([EpisodeTranscriptReference].self, from: data) else {
            return []
        }
        transcriptCache.setObject(decoded as NSArray, forKey: nsKey)
        return decoded
    }

    static func cacheChapters(_ chapters: [EpisodeChapter], forKey key: String) {
        guard !key.isEmpty else { return }
        chapterCache.setObject(chapters as NSArray, forKey: key as NSString)
    }

    static func cacheTranscripts(_ refs: [EpisodeTranscriptReference], forKey key: String) {
        guard !key.isEmpty else { return }
        transcriptCache.setObject(refs as NSArray, forKey: key as NSString)
    }
}

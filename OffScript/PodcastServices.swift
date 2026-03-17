import Foundation
import SwiftData

protocol PodcastSearchProviding {
    func search(query: String) async throws -> [PodcastSearchResult]
}

protocol FeedSyncProviding {
    func importPodcast(from result: PodcastSearchResult, into context: ModelContext) async throws -> Podcast
    func sync(podcast: Podcast, in context: ModelContext) async throws
}

struct PodcastSearchService: PodcastSearchProviding {
    func search(query: String) async throws -> [PodcastSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: "25")
        ]

        guard let url = components?.url else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(ItunesSearchResponse.self, from: data)
        return response.results.compactMap { item in
            guard let feedURL = item.feedURL else { return nil }
            return PodcastSearchResult(
                title: item.collectionName,
                author: item.artistName,
                feedURL: feedURL,
                artworkURL: item.artworkURL,
                websiteURL: item.collectionViewURL,
                summary: item.primaryGenreName
            )
        }
    }
}

final class FeedSyncService: FeedSyncProviding {
    private let topicExtractionService = TopicExtractionService()

    @MainActor
    func importPodcast(from result: PodcastSearchResult, into context: ModelContext) async throws -> Podcast {
        let existing = try context.fetch(FetchDescriptor<Podcast>())
            .first(where: { $0.feedURL == result.feedURL })

        let podcast: Podcast
        if let existing {
            podcast = existing
            podcast.isSubscribed = true
            podcast.title = result.title
            podcast.author = result.author
            podcast.artworkURL = result.artworkURL
            podcast.websiteURL = result.websiteURL
            podcast.summary = result.summary
            if podcast.subscribedAt == nil {
                podcast.subscribedAt = Date()
            }
        } else {
            podcast = Podcast(
                title: result.title,
                author: result.author,
                summary: result.summary,
                feedURL: result.feedURL,
                websiteURL: result.websiteURL,
                artworkURL: result.artworkURL,
                isSubscribed: true
            )
            podcast.subscribedAt = Date()
            context.insert(podcast)
        }

        try context.save()
        try await sync(podcast: podcast, in: context)
        return podcast
    }

    @MainActor
    func sync(podcast: Podcast, in context: ModelContext) async throws {
        podcast.syncStatus = "syncing"
        var request = URLRequest(url: podcast.feedURL)
        request.timeoutInterval = 20
        if let eTag = podcast.feedETag {
            request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = podcast.feedLastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                podcast.syncStatus = "failed"
                try context.save()
                return
            }

            if httpResponse.statusCode == 304 {
                podcast.lastSyncAt = Date()
                podcast.syncStatus = "idle"
                try context.save()
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                podcast.syncStatus = "failed"
                try context.save()
                return
            }

            podcast.feedETag = httpResponse.value(forHTTPHeaderField: "Etag")
            podcast.feedLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")

            let parsed = try RSSFeedParser().parse(data: data)
            podcast.title = parsed.title ?? podcast.title
            podcast.author = parsed.author ?? podcast.author
            podcast.summary = parsed.summary ?? podcast.summary
            podcast.websiteURL = parsed.websiteURL ?? podcast.websiteURL
            podcast.artworkURL = parsed.artworkURL ?? podcast.artworkURL
            podcast.categories = parsed.categories
            podcast.latestPubDate = parsed.items.compactMap(\.pubDate).max()
            podcast.lastSyncAt = Date()
            podcast.syncStatus = "idle"

            let existingEpisodes = try context.fetch(FetchDescriptor<Episode>())
                .filter { $0.podcast.id == podcast.id }

            for item in parsed.items {
                let guid = item.guid ?? item.audioURL.absoluteString
                if let existing = existingEpisodes.first(where: { $0.guid == guid || $0.audioURL == item.audioURL }) {
                    existing.title = item.title
                    existing.summary = item.summary
                    existing.pubDate = item.pubDate ?? existing.pubDate
                    existing.duration = item.duration ?? existing.duration
                    existing.artworkURL = item.artworkURL ?? existing.artworkURL
                    existing.seasonNumber = item.seasonNumber ?? existing.seasonNumber
                    existing.episodeNumber = item.episodeNumber ?? existing.episodeNumber
                } else {
                    let episode = Episode(
                        guid: guid,
                        title: item.title,
                        summary: item.summary,
                        pubDate: item.pubDate ?? Date(),
                        duration: item.duration,
                        audioURL: item.audioURL,
                        artworkURL: item.artworkURL ?? podcast.artworkURL,
                        seasonNumber: item.seasonNumber,
                        episodeNumber: item.episodeNumber,
                        podcast: podcast
                    )
                    context.insert(episode)
                    try await topicExtractionService.enrich(episode: episode, in: context)
                }
            }

            try context.save()
        } catch {
            podcast.syncStatus = "failed"
            try? context.save()
            throw error
        }
    }
}

enum QueueService {
    static func orderedItems(in context: ModelContext) throws -> [QueueItem] {
        let items = try context.fetch(FetchDescriptor<QueueItem>())
        return items.sorted { lhs, rhs in
            if lhs.position == rhs.position {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.position < rhs.position
        }
    }

    static func add(_ episode: Episode, in context: ModelContext) throws {
        let existing = try orderedItems(in: context)
        guard !existing.contains(where: { $0.episode.id == episode.id }) else { return }
        let nextPosition = (existing.last?.position ?? -1) + 1
        let item = QueueItem(episode: episode, position: nextPosition)
        episode.isQueued = true
        context.insert(item)
        try context.save()
    }

    static func remove(_ item: QueueItem, in context: ModelContext) throws {
        item.episode.isQueued = false
        context.delete(item)
        try reorder(in: context)
    }

    static func move(from offsets: IndexSet, to destination: Int, in context: ModelContext) throws {
        var items = try orderedItems(in: context)
        let movingItems = offsets.sorted().map { items[$0] }
        for index in offsets.sorted(by: >) {
            items.remove(at: index)
        }
        let targetIndex = min(destination, items.count)
        items.insert(contentsOf: movingItems, at: targetIndex)
        for (index, item) in items.enumerated() {
            item.position = index
        }
        try context.save()
    }

    static func popNextEpisode(in context: ModelContext) throws -> Episode? {
        guard let first = try orderedItems(in: context).first else { return nil }
        let episode = first.episode
        try remove(first, in: context)
        return episode
    }

    private static func reorder(in context: ModelContext) throws {
        let items = try orderedItems(in: context)
        for (index, item) in items.enumerated() {
            item.position = index
        }
        try context.save()
    }
}

enum SampleDataSeeder {
    @MainActor
    static func seedIfNeeded(context: ModelContext) async throws {
        let existingPodcasts = try context.fetch(FetchDescriptor<Podcast>())
        guard existingPodcasts.isEmpty else { return }

        let tech = Podcast(
            title: "Signal Path",
            author: "OffScript Studio",
            summary: "Field notes on technology, media, and creative work.",
            feedURL: URL(string: "https://example.com/signal-path.xml")!,
            artworkURL: URL(string: "https://images.unsplash.com/photo-1516280440614-37939bbacd81?auto=format&fit=crop&w=800&q=80"),
            categories: ["technology", "media", "creativity"],
            isSubscribed: true
        )
        tech.subscribedAt = .now

        let culture = Podcast(
            title: "Late Checkout",
            author: "OffScript Studio",
            summary: "Design, travel, and the rituals behind interesting work.",
            feedURL: URL(string: "https://example.com/late-checkout.xml")!,
            artworkURL: URL(string: "https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&w=800&q=80"),
            categories: ["design", "culture", "travel"],
            isSubscribed: true
        )
        culture.subscribedAt = .now

        context.insert(tech)
        context.insert(culture)

        let episodes = [
            Episode(
                guid: "signal-1",
                title: "Why great podcasts feel edited, not optimized",
                summary: "A sharp breakdown of pacing, narrative tension, and what makes spoken audio addictive.",
                pubDate: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now,
                duration: 32 * 60,
                audioURL: URL(string: "https://example.com/audio/signal-1.mp3")!,
                artworkURL: tech.artworkURL,
                podcast: tech
            ),
            Episode(
                guid: "signal-2",
                title: "The return of deliberate software",
                summary: "What users mean when they say an app has taste.",
                pubDate: Calendar.current.date(byAdding: .day, value: -4, to: .now) ?? .now,
                duration: 48 * 60,
                audioURL: URL(string: "https://example.com/audio/signal-2.mp3")!,
                artworkURL: tech.artworkURL,
                podcast: tech
            ),
            Episode(
                guid: "checkout-1",
                title: "A city guide for people who love quiet corners",
                summary: "A travel episode built around bookstores, coffee, and long walks.",
                pubDate: Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now,
                duration: 24 * 60,
                audioURL: URL(string: "https://example.com/audio/checkout-1.mp3")!,
                artworkURL: culture.artworkURL,
                podcast: culture
            ),
            Episode(
                guid: "checkout-2",
                title: "How designers actually gather inspiration",
                summary: "Less moodboards, more field notes and obsessive collecting.",
                pubDate: Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now,
                duration: 41 * 60,
                audioURL: URL(string: "https://example.com/audio/checkout-2.mp3")!,
                artworkURL: culture.artworkURL,
                podcast: culture
            )
        ]

        for episode in episodes {
            context.insert(episode)
            let profile = EpisodeProfile(episodeID: episode.id)
            profile.tags = TopicExtractionService.heuristicTags(from: "\(episode.title) \(episode.summary ?? "")")
            profile.summary = episode.summary
            profile.confidenceScore = 0.55
            profile.freshnessBucket = "recent"
            context.insert(profile)
        }

        let signal = PreferenceSignal(action: .like, episode: episodes[0])
        context.insert(signal)
        try QueueService.add(episodes[2], in: context)
        try context.save()
    }
}

private struct ItunesSearchResponse: Decodable {
    let results: [ItunesPodcast]
}

private struct ItunesPodcast: Decodable {
    let collectionName: String
    let artistName: String
    let feedURL: URL?
    let artworkURL: URL?
    let collectionViewURL: URL?
    let primaryGenreName: String?

    enum CodingKeys: String, CodingKey {
        case collectionName
        case artistName
        case feedURL = "feedUrl"
        case artworkURL = "artworkUrl600"
        case collectionViewURL = "collectionViewUrl"
        case primaryGenreName
    }
}

struct ParsedFeed {
    var title: String?
    var author: String?
    var summary: String?
    var websiteURL: URL?
    var artworkURL: URL?
    var categories: [String] = []
    var items: [ParsedFeedItem] = []
}

struct ParsedFeedItem {
    var guid: String?
    var title: String
    var summary: String?
    var pubDate: Date?
    var duration: TimeInterval?
    var audioURL: URL
    var artworkURL: URL?
    var seasonNumber: Int?
    var episodeNumber: Int?
}

final class RSSFeedParser: NSObject, XMLParserDelegate {
    private var feed = ParsedFeed()
    private var currentItem: ParsedFeedItem?
    private var currentElement = ""
    private var currentText = ""
    private var insideItem = false

    func parse(data: Data) throws -> ParsedFeed {
        feed = ParsedFeed()
        currentItem = nil
        currentElement = ""
        currentText = ""
        insideItem = false

        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? URLError(.cannotParseResponse)
        }
        return feed
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = qName ?? elementName
        currentText = ""

        if currentElement == "item" {
            insideItem = true
        }

        if insideItem, currentElement == "enclosure", let urlString = attributeDict["url"], let url = URL(string: urlString) {
            if currentItem == nil {
                currentItem = ParsedFeedItem(title: "", audioURL: url)
            } else {
                currentItem?.audioURL = url
            }
        }

        if currentElement == "itunes:image", let href = attributeDict["href"], let url = URL(string: href) {
            if insideItem {
                currentItem?.artworkURL = url
            } else {
                feed.artworkURL = url
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = qName ?? elementName
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            currentText = ""
            currentElement = ""
        }

        if insideItem {
            switch element {
            case "title":
                if currentItem == nil {
                    currentItem = ParsedFeedItem(title: text, audioURL: URL(string: "https://example.com/unset.mp3")!)
                } else {
                    currentItem?.title = text
                }
            case "description", "content:encoded":
                if currentItem?.summary?.isEmpty != false {
                    currentItem?.summary = text
                }
            case "pubDate":
                currentItem?.pubDate = Self.dateFormatter.date(from: text)
            case "guid":
                currentItem?.guid = text
            case "itunes:duration":
                currentItem?.duration = Self.duration(from: text)
            case "itunes:season":
                currentItem?.seasonNumber = Int(text)
            case "itunes:episode":
                currentItem?.episodeNumber = Int(text)
            case "item":
                insideItem = false
                if let item = currentItem, item.title.isEmpty == false, item.audioURL.absoluteString.contains("unset") == false {
                    feed.items.append(item)
                }
                currentItem = nil
            default:
                break
            }
        } else {
            switch element {
            case "title":
                if feed.title == nil { feed.title = text }
            case "description":
                if feed.summary == nil { feed.summary = text }
            case "itunes:author", "managingEditor":
                if feed.author == nil { feed.author = text }
            case "link":
                if feed.websiteURL == nil { feed.websiteURL = URL(string: text) }
            case "itunes:category":
                if !text.isEmpty, !feed.categories.contains(text) {
                    feed.categories.append(text)
                }
            default:
                break
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    private static func duration(from rawValue: String) -> TimeInterval? {
        let parts = rawValue.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        return parts[0]
    }
}

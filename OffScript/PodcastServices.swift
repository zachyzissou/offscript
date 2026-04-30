import Foundation
import SwiftData

struct PodcastPreviewEpisode: Identifiable, Hashable {
    let id: String
    let title: String
    let pubDate: Date?
    let duration: TimeInterval?
    let summary: String?
    let audioURL: URL
    let artworkURL: URL?

    init(
        id: String,
        title: String,
        pubDate: Date?,
        duration: TimeInterval?,
        summary: String?,
        audioURL: URL,
        artworkURL: URL?
    ) {
        self.id = id
        self.title = title
        self.pubDate = pubDate
        self.duration = duration
        self.summary = summary
        self.audioURL = audioURL
        self.artworkURL = artworkURL
    }

    init(item: ParsedFeedItem) {
        self.id = item.guid ?? item.audioURL.absoluteString
        self.title = item.title
        self.pubDate = item.pubDate
        self.duration = item.duration
        self.summary = item.summary
        self.audioURL = item.audioURL
        self.artworkURL = item.artworkURL
    }
}

struct PodcastPreviewSnapshot {
    let title: String
    let author: String
    let summary: String?
    let categories: [String]
    let websiteURL: URL?
    let latestEpisodes: [PodcastPreviewEpisode]
}

enum PodcastPreviewService {
    static func preview(for result: PodcastSearchResult, episodeLimit: Int = 5) async throws -> PodcastPreviewSnapshot {
        var request = URLRequest(url: result.feedURL)
        request.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: request)
        let parsed = try RSSFeedParser().parse(data: data)
        let latestEpisodes = parsed.items
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            .prefix(episodeLimit)
            .map(PodcastPreviewEpisode.init)

        return PodcastPreviewSnapshot(
            title: parsed.title ?? result.title,
            author: parsed.author ?? result.author,
            summary: parsed.summary ?? result.summary,
            categories: parsed.categories,
            websiteURL: parsed.websiteURL ?? result.websiteURL,
            latestEpisodes: latestEpisodes
        )
    }
}

nonisolated struct PodcastSearchService {
    nonisolated func search(query: String) async throws -> [PodcastSearchResult] {
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
                websiteURL: nil, // collectionViewURL is an Apple Podcasts deep link, not a website
                summary: item.primaryGenreName
            )
        }
    }
}

enum TopPodcastsService {
    static func fetchTop(genre: Genre, limit: Int = 10) async -> [PodcastSearchResult] {
        // Primary: iTunes Search API (reliable, always available)
        let searchQuery = genre.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? genre.title
        let itunesURL = URL(string: "https://itunes.apple.com/search?term=\(searchQuery)+podcast&media=podcast&entity=podcast&genreId=\(genre.appleGenreID)&limit=\(limit)")

        if let url = itunesURL {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(ItunesSearchResponse.self, from: data)
                let results = response.results.compactMap { item -> PodcastSearchResult? in
                    guard let feedURL = item.feedURL else { return nil }
                    return PodcastSearchResult(
                        title: item.collectionName,
                        author: item.artistName,
                        feedURL: feedURL,
                        artworkURL: item.artworkURL,
                        websiteURL: nil,
                        summary: item.primaryGenreName
                    )
                }
                if !results.isEmpty { return results }
            } catch {
                // Fall through to RSS API
            }
        }

        // Fallback: Apple RSS Feed Generator (may be deprecated)
        let urlString = "https://rss.marketingtools.apple.com/api/v2/us/podcasts/top/\(limit)/genre=\(genre.appleGenreID)/json"
        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(AppleRSSFeedResponse.self, from: data)

            var results: [PodcastSearchResult] = []
            for item in response.feed.results {
                guard let id = item.id else { continue }
                if let resolved = await lookupFeedURL(itunesID: id, fallback: item) {
                    results.append(resolved)
                }
            }
            return results
        } catch {
            return []
        }
    }

    private static func lookupFeedURL(itunesID: String, fallback item: AppleRSSPodcast) async -> PodcastSearchResult? {
        let lookupURL = URL(string: "https://itunes.apple.com/lookup?id=\(itunesID)&entity=podcast")!
        do {
            let (data, _) = try await URLSession.shared.data(from: lookupURL)
            let lookup = try JSONDecoder().decode(ItunesLookupResponse.self, from: data)
            guard let result = lookup.results.first, let feedURL = result.feedUrl.flatMap({ URL(string: $0) }) else {
                return nil
            }
            return PodcastSearchResult(
                title: result.collectionName ?? item.name,
                author: result.artistName ?? item.artistName ?? "",
                feedURL: feedURL,
                artworkURL: result.artworkUrl600.flatMap { URL(string: $0) } ?? URL(string: item.artworkUrl100 ?? ""),
                websiteURL: nil,
                summary: nil
            )
        } catch {
            return nil
        }
    }
}

private struct AppleRSSFeedResponse: Decodable {
    let feed: AppleRSSFeed
}

private struct AppleRSSFeed: Decodable {
    let results: [AppleRSSPodcast]
}

private struct AppleRSSPodcast: Decodable {
    let id: String?
    let name: String
    let artistName: String?
    let url: String
    let artworkUrl100: String?
}

private struct ItunesLookupResponse: Decodable {
    let results: [ItunesLookupResult]
}

private struct ItunesLookupResult: Decodable {
    let collectionName: String?
    let artistName: String?
    let feedUrl: String?
    let artworkUrl600: String?
}

enum EpisodeEnrichmentMode {
    case full
    case heuristic
    case skip
}

struct FeedSyncOptions {
    let episodeLimit: Int?
    let enrichmentMode: EpisodeEnrichmentMode
    let resolveExternalChapters: Bool

    static func standard(episodeLimit: Int? = nil) -> FeedSyncOptions {
        FeedSyncOptions(
            episodeLimit: episodeLimit,
            enrichmentMode: .full,
            resolveExternalChapters: true
        )
    }

    static func fastBatchImport(episodeLimit: Int? = nil) -> FeedSyncOptions {
        FeedSyncOptions(
            episodeLimit: episodeLimit,
            enrichmentMode: .heuristic,
            resolveExternalChapters: false
        )
    }

    static func opmlBootstrap(episodeLimit: Int? = 3) -> FeedSyncOptions {
        FeedSyncOptions(
            episodeLimit: episodeLimit,
            enrichmentMode: .skip,
            resolveExternalChapters: false
        )
    }

    static func onboardingBootstrap(episodeLimit: Int? = 3) -> FeedSyncOptions {
        opmlBootstrap(episodeLimit: episodeLimit)
    }
}

enum FeedSyncRetryPolicy {
    static func delay(afterFailureCount failureCount: Int) -> TimeInterval {
        min(pow(2.0, Double(failureCount)) * 60, 60 * 60 * 6)
    }

    static func nextRetryDate(afterFailureCount failureCount: Int, from date: Date = Date()) -> Date {
        date.addingTimeInterval(delay(afterFailureCount: failureCount))
    }
}

final class FeedSyncService {
    private let topicExtractionService = TopicExtractionService()

    struct PodcastSyncResult {
        let podcast: Podcast
        let error: Error?

        var isSuccess: Bool {
            error == nil
        }
    }

    private struct FeedSyncRequest: Sendable {
        let feedURL: URL
        let eTag: String?
        let lastModified: String?
    }

    private struct FeedSyncFetchOutcome: Sendable {
        let feedURL: URL
        let result: FeedSyncFetchResult
    }

    private enum FeedSyncFetchResult: Sendable {
        case success(FeedFetchResult)
        case failure(String)
    }

    @MainActor
    func importPodcast(from result: PodcastSearchResult, into context: ModelContext, episodeLimit: Int? = nil) async throws -> Podcast {
        let podcast = try upsertPodcast(from: result, into: context)
        try context.save()
        try await sync(podcast: podcast, in: context, options: .standard(episodeLimit: episodeLimit))
        return podcast
    }

    @MainActor
    func importPodcast(from opmlEntry: OPMLFeedEntry, into context: ModelContext, episodeLimit: Int? = nil) async throws -> Podcast {
        try await importPodcast(from: opmlEntry, into: context, options: .standard(episodeLimit: episodeLimit))
    }

    @MainActor
    func importPodcast(from opmlEntry: OPMLFeedEntry, into context: ModelContext, options: FeedSyncOptions) async throws -> Podcast {
        let fetched = try await Self.fetchParsedFeed(feedURL: opmlEntry.feedURL)
        guard case let .feed(parsed, httpResponse) = fetched else {
            throw PodcastImportError.feedParseFailed
        }
        let result = try PodcastImportService.searchResult(opmlEntry: opmlEntry, parsedFeed: parsed)
        let podcast = try upsertPodcast(from: result, into: context)
        podcast.syncStatus = "syncing"
        podcast.lastSyncAttemptAt = .now
        podcast.syncErrorMessage = nil
        try await apply(parsed: parsed, httpResponse: httpResponse, to: podcast, in: context, options: options)
        return podcast
    }

    @MainActor
    private func upsertPodcast(from result: PodcastSearchResult, into context: ModelContext) throws -> Podcast {
        let feedURL = result.feedURL
        var podcastDescriptor = FetchDescriptor<Podcast>(
            predicate: #Predicate<Podcast> { $0.feedURL == feedURL }
        )
        podcastDescriptor.fetchLimit = 1
        let existing = try context.fetch(podcastDescriptor).first

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

        return podcast
    }

    @MainActor
    func stagePodcastSubscription(from result: PodcastSearchResult, into context: ModelContext) throws -> Podcast {
        let podcast = try upsertPodcast(from: result, into: context)
        podcast.syncStatus = "idle"
        podcast.lastSyncAttemptAt = .now
        podcast.syncErrorMessage = nil
        try context.save()
        return podcast
    }

    @MainActor
    func stagePodcastSubscriptions(from results: [PodcastSearchResult], into context: ModelContext) throws -> [Podcast] {
        guard !results.isEmpty else { return [] }

        let feedURLs = Set(results.map(\.feedURL))
        let existingPodcasts = try context.fetch(FetchDescriptor<Podcast>(
            predicate: #Predicate<Podcast> {
                feedURLs.contains($0.feedURL)
            }
        ))
        var podcastByFeedKey = Dictionary(
            existingPodcasts.map { ($0.feedURL, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let now = Date()
        var stagedPodcasts: [Podcast] = []

        for result in results {
            let podcast: Podcast
            if let existing = podcastByFeedKey[result.feedURL] {
                podcast = existing
                podcast.isSubscribed = true
                podcast.title = result.title
                podcast.author = result.author
                podcast.feedURL = result.feedURL
                podcast.artworkURL = result.artworkURL
                podcast.websiteURL = result.websiteURL
                podcast.summary = result.summary
                if podcast.subscribedAt == nil {
                    podcast.subscribedAt = now
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
                podcast.subscribedAt = now
                context.insert(podcast)
                podcastByFeedKey[result.feedURL] = podcast
            }

            podcast.syncStatus = "idle"
            podcast.lastSyncAttemptAt = now
            podcast.syncErrorMessage = nil
            stagedPodcasts.append(podcast)
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return stagedPodcasts
    }

    @MainActor
    func sync(podcast: Podcast, in context: ModelContext, episodeLimit: Int? = nil) async throws {
        try await sync(podcast: podcast, in: context, options: .standard(episodeLimit: episodeLimit))
    }

    @MainActor
    func sync(podcast: Podcast, in context: ModelContext, options: FeedSyncOptions) async throws {
        podcast.syncStatus = "syncing"
        podcast.lastSyncAttemptAt = .now
        podcast.syncErrorMessage = nil
        do {
            let fetched = try await Self.fetchParsedFeed(
                feedURL: podcast.feedURL,
                eTag: podcast.feedETag,
                lastModified: podcast.feedLastModified
            )
            switch fetched {
            case .notModified:
                podcast.lastSyncAt = Date()
                podcast.syncStatus = "idle"
                podcast.syncFailureCount = 0
                podcast.nextRetryAt = nil
                try context.save()
                return
            case let .feed(parsed, httpResponse):
                try await apply(parsed: parsed, httpResponse: httpResponse, to: podcast, in: context, options: options)
            }
        } catch {
            podcast.syncStatus = "failed"
            podcast.syncErrorMessage = error.localizedDescription
            try? context.save()
            throw error
        }
    }

    @MainActor
    func sync(podcasts: [Podcast], in context: ModelContext, options: FeedSyncOptions) async -> [PodcastSyncResult] {
        guard !podcasts.isEmpty else { return [] }

        let podcastByFeedURL = Dictionary(
            podcasts.map { ($0.feedURL, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let requests = podcasts.map {
            $0.syncStatus = "syncing"
            $0.lastSyncAttemptAt = .now
            $0.syncErrorMessage = nil
            return FeedSyncRequest(
                feedURL: $0.feedURL,
                eTag: $0.feedETag,
                lastModified: $0.feedLastModified
            )
        }
        context.saveOrLog("FeedSyncService.batchSyncStarted")

        var syncResults: [PodcastSyncResult] = []
        await withTaskGroup(of: FeedSyncFetchOutcome.self) { group in
            let maxConcurrentFetches = 3
            var iterator = requests.makeIterator()
            var inFlight = 0

            func addFetch(_ request: FeedSyncRequest) {
                inFlight += 1
                group.addTask {
                    do {
                        let fetched = try await Self.fetchParsedFeed(
                            feedURL: request.feedURL,
                            eTag: request.eTag,
                            lastModified: request.lastModified
                        )
                        return FeedSyncFetchOutcome(feedURL: request.feedURL, result: .success(fetched))
                    } catch {
                        return FeedSyncFetchOutcome(feedURL: request.feedURL, result: .failure(error.localizedDescription))
                    }
                }
            }

            while inFlight < maxConcurrentFetches, let request = iterator.next() {
                addFetch(request)
            }

            while let outcome = await group.next() {
                inFlight -= 1
                guard let podcast = podcastByFeedURL[outcome.feedURL] else { continue }
                switch outcome.result {
                case .success(.notModified):
                    podcast.lastSyncAt = Date()
                    podcast.syncStatus = "idle"
                    podcast.syncFailureCount = 0
                    podcast.nextRetryAt = nil
                    do {
                        try context.save()
                        syncResults.append(PodcastSyncResult(podcast: podcast, error: nil))
                    } catch {
                        context.rollback()
                        podcast.syncStatus = "failed"
                        podcast.syncErrorMessage = error.localizedDescription
                        context.saveOrLog("FeedSyncService.batchNotModifiedSaveFailure")
                        syncResults.append(PodcastSyncResult(podcast: podcast, error: error))
                    }
                case let .success(.feed(parsed, httpResponse)):
                    do {
                        try await apply(parsed: parsed, httpResponse: httpResponse, to: podcast, in: context, options: options)
                        syncResults.append(PodcastSyncResult(podcast: podcast, error: nil))
                    } catch {
                        podcast.syncStatus = "failed"
                        podcast.syncErrorMessage = error.localizedDescription
                        context.saveOrLog("FeedSyncService.batchApplyFailure")
                        syncResults.append(PodcastSyncResult(podcast: podcast, error: error))
                    }
                case let .failure(errorMessage):
                    podcast.syncStatus = "failed"
                    podcast.syncErrorMessage = errorMessage
                    context.saveOrLog("FeedSyncService.batchFetchFailure")
                    syncResults.append(PodcastSyncResult(
                        podcast: podcast,
                        error: PodcastImportError.feedFetchFailed(errorMessage)
                    ))
                }

                if let nextRequest = iterator.next() {
                    addFetch(nextRequest)
                }
            }
        }

        return syncResults
    }

    @MainActor
    func importPodcast(
        from result: PodcastSearchResult,
        parsedFeed parsed: ParsedFeed,
        httpResponse: HTTPURLResponse? = nil,
        into context: ModelContext,
        episodeLimit: Int? = nil
    ) async throws -> Podcast {
        try await importPodcast(
            from: result,
            parsedFeed: parsed,
            httpResponse: httpResponse,
            into: context,
            options: .standard(episodeLimit: episodeLimit)
        )
    }

    @MainActor
    func importPodcast(
        from result: PodcastSearchResult,
        parsedFeed parsed: ParsedFeed,
        httpResponse: HTTPURLResponse? = nil,
        into context: ModelContext,
        options: FeedSyncOptions
    ) async throws -> Podcast {
        let podcast = try upsertPodcast(from: result, into: context)
        podcast.syncStatus = "syncing"
        podcast.lastSyncAttemptAt = .now
        podcast.syncErrorMessage = nil
        try await apply(parsed: parsed, httpResponse: httpResponse, to: podcast, in: context, options: options)
        return podcast
    }

    @MainActor
    private func apply(
        parsed: ParsedFeed,
        httpResponse: HTTPURLResponse?,
        to podcast: Podcast,
        in context: ModelContext,
        options: FeedSyncOptions
    ) async throws {
        podcast.feedETag = httpResponse?.value(forHTTPHeaderField: "Etag") ?? podcast.feedETag
        podcast.feedLastModified = httpResponse?.value(forHTTPHeaderField: "Last-Modified") ?? podcast.feedLastModified
        podcast.title = parsed.title ?? podcast.title
        podcast.author = parsed.author ?? podcast.author
        podcast.summary = parsed.summary ?? podcast.summary
        podcast.websiteURL = parsed.websiteURL ?? podcast.websiteURL
        podcast.artworkURL = parsed.artworkURL ?? podcast.artworkURL
        podcast.categories = parsed.categories
        podcast.latestPubDate = parsed.items.compactMap(\.pubDate).max()
        podcast.lastSyncAt = Date()
        podcast.syncStatus = "idle"
        podcast.syncFailureCount = 0
        podcast.nextRetryAt = nil

        let itemsToProcess = Self.itemsToProcess(from: parsed.items, limit: options.episodeLimit)
        let podcastID = podcast.id
        let lookupKeys = Self.episodeLookupKeys(for: itemsToProcess)
        let existingEpisodes = try Self.fetchExistingEpisodes(
            for: podcastID,
            lookupKeys: lookupKeys,
            in: context
        )
        let existingByGUID = Dictionary(existingEpisodes.map { ($0.guid, $0) }, uniquingKeysWith: { first, _ in first })
        let existingByAudioURL = Dictionary(existingEpisodes.map { ($0.audioURL, $0) }, uniquingKeysWith: { first, _ in first })

        for item in itemsToProcess {
            let guid = item.guid ?? item.audioURL.absoluteString
            let resolvedChapters = await resolvedChapters(for: item, resolveExternalChapters: options.resolveExternalChapters)
            if let existing = existingByGUID[guid] ?? existingByAudioURL[item.audioURL] {
                existing.title = item.title
                existing.summary = item.summary
                existing.pubDate = item.pubDate ?? existing.pubDate
                existing.duration = item.duration ?? existing.duration
                existing.artworkURL = item.artworkURL ?? existing.artworkURL
                existing.seasonNumber = item.seasonNumber ?? existing.seasonNumber
                existing.episodeNumber = item.episodeNumber ?? existing.episodeNumber
                existing.chapters = resolvedChapters
                existing.transcriptReferences = item.transcriptReferences
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
                episode.chapters = resolvedChapters
                episode.transcriptReferences = item.transcriptReferences
                context.insert(episode)
                switch options.enrichmentMode {
                case .full:
                    try await topicExtractionService.enrich(episode: episode, in: context)
                case .heuristic:
                    try topicExtractionService.enrichHeuristically(episode: episode, in: context)
                case .skip:
                    break
                }
            }
        }

        try context.save()
    }

    private struct EpisodeLookupKeys {
        static let maxPredicateKeyCount = 800

        let guids: Set<String>
        let audioURLs: Set<URL>

        var count: Int {
            guids.count + audioURLs.count
        }
    }

    static func itemsToProcess(from items: [ParsedFeedItem], limit: Int?) -> [ParsedFeedItem] {
        guard let limit else {
            return items.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        }
        guard limit > 0 else { return [] }

        var newestItems: [ParsedFeedItem] = []
        newestItems.reserveCapacity(min(limit, items.count))

        for item in items {
            let itemDate = item.pubDate ?? .distantPast
            let insertionIndex = newestItems.firstIndex {
                itemDate > ($0.pubDate ?? .distantPast)
            } ?? newestItems.endIndex

            if insertionIndex < limit {
                newestItems.insert(item, at: insertionIndex)
                if newestItems.count > limit {
                    newestItems.removeLast()
                }
            }
        }

        return newestItems
    }

    private static func episodeLookupKeys(for items: [ParsedFeedItem]) -> EpisodeLookupKeys {
        EpisodeLookupKeys(
            guids: Set(items.map { $0.guid ?? $0.audioURL.absoluteString }),
            audioURLs: Set(items.map(\.audioURL))
        )
    }

    @MainActor
    private static func fetchExistingEpisodes(
        for podcastID: UUID,
        lookupKeys: EpisodeLookupKeys,
        in context: ModelContext
    ) throws -> [Episode] {
        guard !lookupKeys.guids.isEmpty || !lookupKeys.audioURLs.isEmpty else { return [] }
        if lookupKeys.count > EpisodeLookupKeys.maxPredicateKeyCount {
            return try context.fetch(FetchDescriptor<Episode>(
                predicate: #Predicate<Episode> {
                    $0.podcast.id == podcastID
                }
            ))
        }
        let guids = lookupKeys.guids
        let audioURLs = lookupKeys.audioURLs
        return try context.fetch(FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> {
                $0.podcast.id == podcastID && (guids.contains($0.guid) || audioURLs.contains($0.audioURL))
            }
        ))
    }

    private enum FeedFetchResult: Sendable {
        case notModified(HTTPURLResponse)
        case feed(ParsedFeed, HTTPURLResponse)
    }

    private static func fetchParsedFeed(feedURL: URL, eTag: String? = nil, lastModified: String? = nil) async throws -> FeedFetchResult {
        var request = URLRequest(url: feedURL)
        request.timeoutInterval = 20
        request.setValue("application/rss+xml,application/xml,text/xml;q=0.9,*/*;q=0.8",
                         forHTTPHeaderField: "Accept")
        if let eTag {
            request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PodcastImportError.feedFetchFailed("Unexpected feed response.")
        }

        if httpResponse.statusCode == 304 {
            return .notModified(httpResponse)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PodcastImportError.feedFetchFailed("HTTP \(httpResponse.statusCode)")
        }

        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("text/html") {
            throw PodcastImportError.feedParseFailed
        }

        let parsed = try RSSFeedParser().parse(data: data)
        return .feed(parsed, httpResponse)
    }

    private func resolvedChapters(for item: ParsedFeedItem, resolveExternalChapters: Bool) async -> [EpisodeChapter] {
        let embedded = EpisodeChapterParser.normalize(item.chapters, duration: item.duration)
        if !embedded.isEmpty {
            return embedded
        }
        guard resolveExternalChapters else { return [] }
        guard let externalChapterURL = item.externalChapterURL else { return [] }
        return (try? await ExternalChapterLoader.load(from: externalChapterURL, duration: item.duration)) ?? []
    }
}

enum QueueService {
    static func orderedItems(in context: ModelContext) throws -> [QueueItem] {
        let items = try context.fetch(FetchDescriptor<QueueItem>(
            sortBy: [
                SortDescriptor(\QueueItem.position),
                SortDescriptor(\QueueItem.createdAt)
            ]
        ))
        return items
    }

    static func add(_ episode: Episode, in context: ModelContext) throws {
        try addToEnd(episode, in: context)
    }

    static func addToEnd(_ episode: Episode, in context: ModelContext) throws {
        let existing = try orderedItems(in: context)
        guard !existing.contains(where: { $0.episode.id == episode.id }) else { return }
        let nextPosition = (existing.last?.position ?? -1) + 1
        let item = QueueItem(episode: episode, position: nextPosition)
        episode.isQueued = true
        context.insert(item)
        try context.save()
        TelemetryService.track(
            "queue_add_to_end",
            metadata: ["episode": episode.title, "podcast": episode.podcast.title],
            in: context
        )
    }

    static func playNext(_ episode: Episode, in context: ModelContext) throws {
        let existing = try orderedItems(in: context)
        if let current = existing.first(where: { $0.episode.id == episode.id }) {
            current.position = 0
            try reorder(in: context)
            return
        }

        for item in existing {
            item.position += 1
        }
        let item = QueueItem(episode: episode, position: 0)
        episode.isQueued = true
        context.insert(item)
        try reorder(in: context)
        TelemetryService.track(
            "queue_play_next",
            metadata: ["episode": episode.title, "podcast": episode.podcast.title],
            in: context
        )
    }

    static func remove(_ item: QueueItem, in context: ModelContext) throws {
        item.episode.isQueued = false
        context.delete(item)
        try reorder(in: context)
        TelemetryService.track(
            "queue_remove",
            metadata: ["episode": item.episode.title, "podcast": item.episode.podcast.title],
            in: context
        )
    }

    static func removeEpisode(id episodeID: UUID, in context: ModelContext) throws {
        guard let item = try orderedItems(in: context).first(where: { $0.episode.id == episodeID }) else { return }
        try remove(item, in: context)
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
        TelemetryService.track(
            "queue_reorder",
            metadata: ["count": "\(items.count)"],
            in: context
        )
    }

    static func popNextEpisode(in context: ModelContext) throws -> Episode? {
        guard let first = try orderedItems(in: context).first else { return nil }
        let episode = first.episode
        try remove(first, in: context)
        TelemetryService.track(
            "queue_pop_next",
            metadata: ["episode": episode.title, "podcast": episode.podcast.title],
            in: context
        )
        return episode
    }

    static func popNextEpisode(skipping episodeID: UUID?, in context: ModelContext) throws -> Episode? {
        while let first = try orderedItems(in: context).first {
            if first.episode.id == episodeID {
                try remove(first, in: context)
                continue
            }
            let episode = first.episode
            try remove(first, in: context)
            TelemetryService.track(
                "queue_pop_next",
                metadata: ["episode": episode.title, "podcast": episode.podcast.title],
                in: context
            )
            return episode
        }
        return nil
    }

    private static func reorder(in context: ModelContext) throws {
        let items = try orderedItems(in: context)
        for (index, item) in items.enumerated() {
            item.position = index
        }
        try context.save()
    }
}


nonisolated private struct ItunesSearchResponse: Decodable {
    let results: [ItunesPodcast]
}

nonisolated private struct ItunesPodcast: Decodable {
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

struct ParsedFeed: Sendable {
    var title: String?
    var author: String?
    var summary: String?
    var websiteURL: URL?
    var artworkURL: URL?
    var categories: [String] = []
    var items: [ParsedFeedItem] = []
}

struct ParsedFeedItem: Sendable {
    var guid: String?
    var title: String
    var summary: String?
    var pubDate: Date?
    var duration: TimeInterval?
    var audioURL: URL
    var artworkURL: URL?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var chapters: [EpisodeChapter] = []
    var externalChapterURL: URL?
    var transcriptReferences: [EpisodeTranscriptReference] = []
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
            ensureCurrentItem(audioURL: url)
            currentItem?.audioURL = url
        }

        if currentElement == "itunes:image", let href = attributeDict["href"], let url = URL(string: href) {
            if insideItem {
                ensureCurrentItem()
                currentItem?.artworkURL = url
            } else {
                feed.artworkURL = url
            }
        }

        if !insideItem, currentElement == "itunes:category", let category = attributeDict["text"], !category.isEmpty {
            if !feed.categories.contains(category) {
                feed.categories.append(category)
            }
        }

        if insideItem, currentElement == "psc:chapter" {
            ensureCurrentItem()
            let startText = attributeDict["start"] ?? attributeDict["startTime"] ?? attributeDict["time"]
            let title = attributeDict["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let startText, let startTime = EpisodeChapterParser.seconds(from: startText), !title.isEmpty {
                currentItem?.chapters.append(EpisodeChapter(title: title, startTime: startTime))
            }
        }

        if insideItem, currentElement == "podcast:chapters", let urlString = attributeDict["url"], let url = URL(string: urlString) {
            ensureCurrentItem()
            currentItem?.externalChapterURL = url
        }

        if insideItem, currentElement == "podcast:transcript", let urlString = attributeDict["url"], let url = URL(string: urlString) {
            ensureCurrentItem()
            currentItem?.transcriptReferences.append(
                EpisodeTranscriptReference(
                    url: url,
                    mimeType: attributeDict["type"],
                    language: attributeDict["language"],
                    rel: attributeDict["rel"]
                )
            )
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
                ensureCurrentItem()
                currentItem?.title = text
            case "description", "content:encoded":
                ensureCurrentItem()
                if currentItem?.summary?.isEmpty != false {
                    currentItem?.summary = text
                }
            case "pubDate":
                ensureCurrentItem()
                currentItem?.pubDate = Self.dateFormatter.date(from: text)
            case "guid":
                ensureCurrentItem()
                currentItem?.guid = text
            case "itunes:duration":
                ensureCurrentItem()
                currentItem?.duration = Self.duration(from: text)
            case "itunes:season":
                ensureCurrentItem()
                currentItem?.seasonNumber = Int(text)
            case "itunes:episode":
                ensureCurrentItem()
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

    private func ensureCurrentItem(audioURL: URL = URL(string: "https://example.com/unset.mp3")!) {
        if currentItem == nil {
            currentItem = ParsedFeedItem(title: "", audioURL: audioURL)
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

enum ExternalChapterLoader {
    static func load(from url: URL, duration: TimeInterval?) async throws -> [EpisodeChapter] {
        let (data, _) = try await URLSession.shared.data(from: url)
        if let response = try? JSONDecoder().decode(ExternalChapterEnvelope.self, from: data) {
            return EpisodeChapterParser.normalize(response.chapters.map(\.chapter), duration: duration)
        }
        if let response = try? JSONDecoder().decode([ExternalChapterRecord].self, from: data) {
            return EpisodeChapterParser.normalize(response.map(\.chapter), duration: duration)
        }
        return []
    }
}

private struct ExternalChapterEnvelope: Decodable {
    let chapters: [ExternalChapterRecord]
}

private struct ExternalChapterRecord: Decodable {
    let title: String
    let startSeconds: TimeInterval

    var chapter: EpisodeChapter {
        EpisodeChapter(title: title, startTime: startSeconds)
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case startTime
        case start
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)

        if let raw = try? container.decode(String.self, forKey: .startTime),
           let seconds = EpisodeChapterParser.seconds(from: raw) ?? Double(raw) {
            self.startSeconds = seconds
            return
        }

        if let raw = try? container.decode(Double.self, forKey: .startTime) {
            self.startSeconds = raw
            return
        }

        if let raw = try? container.decode(String.self, forKey: .start),
           let seconds = EpisodeChapterParser.seconds(from: raw) ?? Double(raw) {
            self.startSeconds = seconds
            return
        }

        if let raw = try? container.decode(Double.self, forKey: .start) {
            self.startSeconds = raw
            return
        }

        throw DecodingError.dataCorruptedError(forKey: .startTime, in: container, debugDescription: "Missing chapter start time")
    }
}

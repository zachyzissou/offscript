import Foundation
import OSLog
import SwiftData

/// Imports podcast subscriptions exported as OPML from Apple Podcasts,
/// Pocket Casts, Overcast, Spotify (via third-party tools), Castro, and
/// any other major podcast app. Handles duplicates by feed URL and by
/// fuzzy title match so the user can re-import from a second source
/// without ending up with two copies of every show.
@MainActor
final class OPMLImportService {
    private let logger = Logger(subsystem: "OffScript", category: "OPML")
    private let syncService = FeedSyncService()

    struct ParsedFeed: Identifiable, Hashable {
        var id: URL { feedURL }
        let title: String
        let feedURL: URL
        let websiteURL: URL?
        let author: String?
    }

    enum DuplicateState: Equatable {
        case fresh                      // not yet in library
        case alreadySubscribed(UUID)    // exact feed URL match
        case fuzzyTitleMatch(UUID)      // similar title to an existing show
    }

    struct CandidateFeed: Identifiable {
        let id = UUID()
        var feed: ParsedFeed
        var duplicate: DuplicateState
        var include: Bool

        var isDuplicate: Bool {
            switch duplicate {
            case .fresh: return false
            case .alreadySubscribed, .fuzzyTitleMatch: return true
            }
        }
    }

    struct ImportSummary {
        var imported: Int
        var skipped: Int
        var failed: [(ParsedFeed, String)]
    }

    // MARK: - Parsing

    func parse(data: Data) -> [ParsedFeed] {
        let parser = OPMLParser()
        return parser.parse(data: data)
    }

    func parse(fileURL: URL) throws -> [ParsedFeed] {
        let data = try Data(contentsOf: fileURL)
        return parse(data: data)
    }

    // MARK: - Duplicate detection

    func resolveDuplicates(_ feeds: [ParsedFeed], in context: ModelContext) -> [CandidateFeed] {
        let existing = (try? context.fetch(FetchDescriptor<Podcast>())) ?? []

        return feeds.map { feed in
            let duplicate = detectDuplicate(for: feed, existing: existing)
            return CandidateFeed(
                feed: feed,
                duplicate: duplicate,
                include: duplicate == .fresh   // pre-check only the fresh ones
            )
        }
    }

    private func detectDuplicate(for feed: ParsedFeed, existing: [Podcast]) -> DuplicateState {
        // Exact feed URL match (canonicalised — strip trailing slash + lowercased host).
        let candidate = canonicalize(feed.feedURL)
        if let match = existing.first(where: { canonicalize($0.feedURL) == candidate }) {
            return .alreadySubscribed(match.id)
        }

        // Fuzzy title match.
        let normalizedTitle = normalize(title: feed.title)
        if let match = existing.first(where: { normalize(title: $0.title) == normalizedTitle && !normalizedTitle.isEmpty }) {
            return .fuzzyTitleMatch(match.id)
        }

        return .fresh
    }

    private func canonicalize(_ url: URL) -> String {
        var s = url.absoluteString.lowercased()
        if s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func normalize(title: String) -> String {
        title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    // MARK: - Import

    func importSelected(_ candidates: [CandidateFeed], into context: ModelContext, progress: @MainActor @escaping (Int, Int) -> Void) async -> ImportSummary {
        let toImport = candidates.filter { $0.include && !$0.isDuplicate }
        var imported = 0
        var failed: [(ParsedFeed, String)] = []
        let total = toImport.count

        // OPML files often hold dozens of subscriptions — parallelise to keep
        // the user out of a 5-minute spinner. Same 3-concurrent budget the
        // onboarding flow uses.
        syncService.enrichesInline = false
        defer { syncService.enrichesInline = true }

        let maxConcurrent = 3
        var iter = toImport.makeIterator()

        await withTaskGroup(of: (ParsedFeed, Result<Void, Error>).self) { group in
            for _ in 0..<maxConcurrent {
                guard let next = iter.next() else { break }
                group.addTask { @MainActor in
                    await self.runImport(next.feed, into: context)
                }
            }
            while let result = await group.next() {
                switch result.1 {
                case .success: imported += 1
                case .failure(let err): failed.append((result.0, err.localizedDescription))
                }
                progress(imported + failed.count, total)
                if let next = iter.next() {
                    group.addTask { @MainActor in
                        await self.runImport(next.feed, into: context)
                    }
                }
            }
        }

        let skipped = candidates.filter { $0.isDuplicate || !$0.include }.count
        return ImportSummary(imported: imported, skipped: skipped, failed: failed)
    }

    @MainActor
    private func runImport(_ feed: ParsedFeed, into context: ModelContext) async -> (ParsedFeed, Result<Void, Error>) {
        let result = PodcastSearchResult(
            title: feed.title,
            author: feed.author ?? "",
            feedURL: feed.feedURL,
            artworkURL: nil,
            websiteURL: feed.websiteURL,
            summary: nil
        )
        do {
            _ = try await syncService.importPodcast(from: result, into: context, episodeLimit: 4)
            return (feed, .success(()))
        } catch {
            logger.error("OPML import failed for \(feed.title, privacy: .public): \(String(describing: error), privacy: .public)")
            return (feed, .failure(error))
        }
    }
}

// MARK: - OPML Parser

private final class OPMLParser: NSObject, XMLParserDelegate {
    private var feeds: [OPMLImportService.ParsedFeed] = []

    func parse(data: Data) -> [OPMLImportService.ParsedFeed] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return feeds
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "outline" else { return }

        // Apple Podcasts + Overcast + Pocket Casts + Castro all use:
        //   <outline type="rss" text="Show Title" xmlUrl="https://feed/url" htmlUrl="https://show/site"/>
        // Some emit type="link" with `xmlUrl`.
        // Our parse is permissive: any outline with an `xmlUrl` is a feed.
        let attrs = attributeDict.reduce(into: [String: String]()) { partial, pair in
            partial[pair.key.lowercased()] = pair.value
        }

        guard let xmlUrl = attrs["xmlurl"], let url = URL(string: xmlUrl) else { return }

        let title = attrs["text"] ?? attrs["title"] ?? url.host ?? "Untitled"
        let html = attrs["htmlurl"].flatMap(URL.init(string:))
        let author = attrs["itunes:author"] ?? attrs["author"]

        feeds.append(OPMLImportService.ParsedFeed(
            title: title,
            feedURL: url,
            websiteURL: html,
            author: author
        ))
    }
}

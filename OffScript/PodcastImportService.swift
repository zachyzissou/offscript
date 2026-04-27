import Foundation
import OSLog
import SwiftData

private let importLogger = Logger(subsystem: "com.offscript", category: "PodcastImport")

// MARK: - Errors

enum PodcastImportError: LocalizedError {
    case invalidURL
    case feedFetchFailed(String)
    case feedParseFailed
    case opmlParseFailed
    case noFeedsInOPML

    var errorDescription: String? {
        switch self {
        case .invalidURL: "That doesn't look like a feed URL."
        case .feedFetchFailed(let message): "Couldn't fetch the feed: \(message)"
        case .feedParseFailed: "That URL doesn't return a podcast feed."
        case .opmlParseFailed: "Couldn't parse the OPML file."
        case .noFeedsInOPML: "No podcast feeds found in that OPML."
        }
    }
}

// MARK: - URL → PodcastSearchResult

/// Resolves raw user-pasted URLs and OPML files into the same
/// `PodcastSearchResult` shape that `FeedSyncService.importPodcast(...)`
/// already accepts. Lets URL-paste / OPML import reuse the entire existing
/// import + sync pipeline instead of duplicating it.
enum PodcastImportService {

    /// Fetch a feed from a raw URL string and resolve it to a
    /// `PodcastSearchResult` ready for `FeedSyncService.importPodcast`.
    /// Tolerates URLs without a scheme (defaults to https://) and trims
    /// whitespace.
    static func resolve(urlString: String) async throws -> PodcastSearchResult {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = normalizeFeedURL(trimmed) else {
            throw PodcastImportError.invalidURL
        }
        return try await resolve(feedURL: url)
    }

    /// Fetch a feed from a known-good URL and resolve it to a
    /// `PodcastSearchResult`. The fetched metadata wins over the URL string
    /// so the library surfaces the show's actual title — not the host name.
    static func resolve(feedURL: URL) async throws -> PodcastSearchResult {
        var request = URLRequest(url: feedURL)
        request.timeoutInterval = 20
        request.setValue("application/rss+xml,application/xml,text/xml;q=0.9,*/*;q=0.8",
                         forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw PodcastImportError.feedFetchFailed(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                throw PodcastImportError.feedFetchFailed("HTTP \(http.statusCode)")
            }
            // Reject HTML responses — a 200 OK from a misconfigured server
            // serving a landing page at a feed URL would otherwise parse
            // as an empty ParsedFeed and look like "we found a feed but
            // it has no episodes" instead of "this isn't a feed."
            if let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
               contentType.contains("text/html") {
                throw PodcastImportError.feedParseFailed
            }
        }

        let parsed: ParsedFeed
        do {
            parsed = try RSSFeedParser().parse(data: data)
        } catch {
            importLogger.error("Feed parse failed for \(feedURL.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw PodcastImportError.feedParseFailed
        }

        // A valid feed must at minimum have a title. A page that returns 200 OK
        // but no title is almost always an HTML page at a feed-shaped URL.
        guard let title = parsed.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            throw PodcastImportError.feedParseFailed
        }

        return PodcastSearchResult(
            title: title,
            author: parsed.author ?? "Unknown",
            feedURL: feedURL,
            artworkURL: parsed.artworkURL,
            websiteURL: parsed.websiteURL,
            summary: parsed.summary
        )
    }

    /// Strip whitespace, infer a scheme if missing, and reject obvious
    /// non-feed inputs (search queries, single words, etc.).
    static func normalizeFeedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Reject anything that doesn't look at least vaguely like a host.
        // Without a dot it's almost certainly a search term, not a URL.
        guard trimmed.contains(".") else { return nil }
        guard !trimmed.contains(" ") else { return nil }

        let withScheme: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("feed://") {
            withScheme = trimmed.replacingOccurrences(of: "feed://", with: "https://")
        } else {
            withScheme = "https://" + trimmed
        }

        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        return url
    }

    // MARK: - OPML

    /// Parse an OPML file and yield the list of feed URLs it contains.
    /// Tolerates the slight format variations across Apple Podcasts,
    /// Pocket Casts, Overcast, AntennaPod, and gPodder exports — they all
    /// agree on `<outline xmlUrl="..." text="..." />` even when the
    /// surrounding structure differs.
    static func extractFeedURLs(fromOPML data: Data) throws -> [OPMLFeedEntry] {
        let parser = OPMLParser()
        let entries = try parser.parse(data: data)
        guard !entries.isEmpty else { throw PodcastImportError.noFeedsInOPML }
        return entries
    }

    /// Resolve an OPML entry into a `PodcastSearchResult`, using the title
    /// from the OPML as a fallback if the feed itself doesn't return one
    /// quickly. Network failures here surface so the importer UI can show
    /// per-row status — one bad feed shouldn't fail the whole batch.
    static func resolve(opmlEntry: OPMLFeedEntry) async throws -> PodcastSearchResult {
        do {
            return try await resolve(feedURL: opmlEntry.feedURL)
        } catch {
            // If the feed itself failed but we have a title from the OPML,
            // build a minimal result and let `sync()` retry the network
            // fetch with podcast.feedURL — same pipeline as Search-import.
            if let title = opmlEntry.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                return PodcastSearchResult(
                    title: title,
                    author: opmlEntry.author ?? "Unknown",
                    feedURL: opmlEntry.feedURL,
                    artworkURL: nil,
                    websiteURL: nil,
                    summary: nil
                )
            }
            throw error
        }
    }
}

// MARK: - OPML export

enum PodcastOPMLExporter {
    /// Generate an OPML 2.0 document listing every subscribed podcast.
    /// Format matches what Apple Podcasts / Pocket Casts / Overcast /
    /// AntennaPod export, so an OffScript export imports cleanly into
    /// any of them. Each `<outline>` carries `xmlUrl`, `text`, `title`,
    /// and `type="rss"` — the union of attributes the major importers
    /// actually look at.
    static func export(podcasts: [Podcast]) -> Data {
        let formatter = ISO8601DateFormatter()
        let dateCreated = formatter.string(from: Date())

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
        <head>
            <title>OffScript Subscriptions</title>
            <dateCreated>\(dateCreated)</dateCreated>
        </head>
        <body>
            <outline text="feeds" title="feeds">

        """

        for podcast in podcasts {
            let title = escape(podcast.title)
            let url = escape(podcast.feedURL.absoluteString)
            let author = escape(podcast.author ?? "")
            xml += "        <outline type=\"rss\" text=\"\(title)\" title=\"\(title)\" xmlUrl=\"\(url)\""
            if !author.isEmpty {
                xml += " author=\"\(author)\""
            }
            xml += " />\n"
        }

        xml += """
            </outline>
        </body>
        </opml>
        """

        return Data(xml.utf8)
    }

    /// Minimal XML attribute escaping — covers the five reserved
    /// characters that XML parsers care about. Podcast titles routinely
    /// contain `&` and quotes; without escaping the OPML wouldn't parse
    /// in the destination app.
    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - OPML

struct OPMLFeedEntry: Hashable, Identifiable {
    var id: URL { feedURL }
    let feedURL: URL
    let title: String?
    let author: String?
}

private final class OPMLParser: NSObject, XMLParserDelegate {
    private var entries: [OPMLFeedEntry] = []
    private var parseError: Error?

    func parse(data: Data) throws -> [OPMLFeedEntry] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parseError ?? PodcastImportError.opmlParseFailed
        }
        return entries
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        guard elementName.lowercased() == "outline" else { return }

        // The xmlUrl attribute is the only thing every podcast app's OPML
        // export agrees on. text and title are interchangeable across
        // exporters; type=rss is sometimes set, sometimes not.
        let urlString = attributeDict["xmlUrl"]
            ?? attributeDict["xmlurl"]
            ?? attributeDict["xmlURL"]
        guard let urlString,
              let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.host != nil else {
            return
        }

        let title = attributeDict["text"]
            ?? attributeDict["title"]
        let author = attributeDict["author"]

        entries.append(OPMLFeedEntry(feedURL: url, title: title, author: author))
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }
}

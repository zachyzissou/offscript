import Foundation
import OSLog
import SwiftData

struct ScoredDiscoveryResult: Identifiable {
    let id: String
    let result: PodcastSearchResult
    let score: Double
    let explanation: String
    let signalTrace: [RecommendationSignal]

    nonisolated init(result: PodcastSearchResult, score: Double, explanation: String, signalTrace: [RecommendationSignal]) {
        self.id = result.feedURL.absoluteString
        self.result = result
        self.score = score
        self.explanation = explanation
        self.signalTrace = signalTrace
    }
}

actor DiscoveryService {
    private let logger = Logger(subsystem: "com.offscript", category: "Discovery")
    private var cachedResults: [ScoredDiscoveryResult] = []
    private var cacheTimestamp: Date = .distantPast
    private var cacheSignature = ""

    private let cacheDuration: TimeInterval = 3600 // 1 hour

    func discoverPodcasts(
        tasteProfile: UserTasteProfile,
        subscribedFeedURLs: Set<String>,
        limit: Int = 10
    ) async -> [ScoredDiscoveryResult] {
        let normalizedSubscribedFeedURLs = Set(subscribedFeedURLs.map(Self.normalizedFeedKey))
        let signature = Self.cacheSignature(for: tasteProfile, subscribedFeedURLs: normalizedSubscribedFeedURLs)

        // Return cached results if fresh
        if signature == cacheSignature,
           Date().timeIntervalSince(cacheTimestamp) < cacheDuration,
           !cachedResults.isEmpty {
            // Filter out any results the user has since subscribed to
            let stillRelevant = cachedResults.filter { !normalizedSubscribedFeedURLs.contains(Self.normalizedFeedKey($0.result.feedURL.absoluteString)) }
            if !stillRelevant.isEmpty {
                return Array(stillRelevant.prefix(limit))
            }
        }

        let queries = buildQueries(from: tasteProfile)
        guard !queries.isEmpty else { return [] }

        let searchService = PodcastSearchService()
        var allResults: [PodcastSearchResult] = []
        var seenFeedURLs = Set<String>()

        for query in queries {
            let results: [PodcastSearchResult]
            do {
                results = try await searchService.search(query: query)
            } catch {
                logger.error("Discovery search failed for query '\(query, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                continue
            }
            for result in results {
                let feedKey = Self.normalizedFeedKey(result.feedURL.absoluteString)
                guard !normalizedSubscribedFeedURLs.contains(feedKey),
                      !seenFeedURLs.contains(feedKey) else { continue }
                seenFeedURLs.insert(feedKey)
                allResults.append(result)
            }
        }

        let baselineScored = allResults.map { result in
            Self.score(result: result, tasteProfile: tasteProfile)
        }
        .sorted { $0.score > $1.score }

        let previewLimit = min(max(limit * 2, 6), 10, baselineScored.count)
        let previewCandidates = Array(baselineScored.prefix(previewLimit).map(\.result))
        let previewScored = await scorePreviewCandidates(previewCandidates, tasteProfile: tasteProfile)
        let previewScoredByID = Dictionary(uniqueKeysWithValues: previewScored.map { ($0.id, $0) })
        let scored = baselineScored
            .map { previewScoredByID[$0.id] ?? $0 }
            .sorted { $0.score > $1.score }

        let cacheLimit = max(limit, AppSettings.RecommendationMode.discovery.discoveryLimit)
        let topResults = Array(scored.prefix(cacheLimit))
        cachedResults = topResults
        cacheTimestamp = Date()
        cacheSignature = signature
        return Array(topResults.prefix(limit))
    }

    func invalidateCache() {
        cachedResults = []
        cacheTimestamp = .distantPast
        cacheSignature = ""
    }

    // MARK: - Query Generation

    private func buildQueries(from profile: UserTasteProfile) -> [String] {
        var queries: [String] = []

        // Query from top tags (most specific signal)
        let topTags = profile.topTags
        if topTags.count >= 2 {
            queries.append(topTags.prefix(2).joined(separator: " "))
        } else if let first = topTags.first {
            queries.append(first)
        }

        // Query from preferred genres
        let genres = profile.preferredGenres
        if let genre = genres.first {
            queries.append("\(genre) podcast")
        }

        // Cross-signal: combine a tag with a genre for more targeted results
        if let tag = topTags.first, let genre = genres.first {
            queries.append("\(tag) \(genre)")
        }

        // Show affinity: find shows similar to favorites
        if let favoriteShow = profile.showAffinity.first {
            queries.append("podcasts like \(favoriteShow)")
        }

        // Cap at 4 queries
        return Array(queries.prefix(4))
    }

    // MARK: - Scoring

    private func scorePreviewCandidates(
        _ candidates: [PodcastSearchResult],
        tasteProfile: UserTasteProfile
    ) async -> [ScoredDiscoveryResult] {
        await withTaskGroup(of: ScoredDiscoveryResult?.self) { group in
            for result in candidates {
                group.addTask {
                    do {
                        let preview = try await PodcastPreviewService.preview(for: result, episodeLimit: 3)
                        return Self.score(result: result, tasteProfile: tasteProfile, preview: preview)
                    } catch {
                        return nil
                    }
                }
            }

            var scored: [ScoredDiscoveryResult] = []
            for await result in group {
                if let result {
                    scored.append(result)
                }
            }
            return scored
        }
    }

    nonisolated static func score(
        result: PodcastSearchResult,
        tasteProfile: UserTasteProfile,
        preview: PodcastPreviewSnapshot? = nil
    ) -> ScoredDiscoveryResult {
        var score: Double = 0.0
        var explanations: [String] = []
        var signals: [RecommendationSignal] = []

        let titleLower = result.title.lowercased()
        let summaryLower = (result.summary ?? "").lowercased()
        let previewSummaryLower = (preview?.summary ?? "").lowercased()
        let categoryText = (preview?.categories ?? []).joined(separator: " ").lowercased()
        let episodeText = (preview?.latestEpisodes ?? [])
            .map { "\($0.title) \($0.summary ?? "")" }
            .joined(separator: " ")
            .lowercased()
        let searchableText = "\(titleLower) \(summaryLower) \(previewSummaryLower) \(categoryText)"

        // Genre match — iTunes returns primaryGenreName in summary field
        let preferredGenresLower = Set(tasteProfile.preferredGenres.map { $0.lowercased() })
        let resultGenres = Set(([result.summary] + (preview?.categories ?? []).map(Optional.some))
            .compactMap { $0?.lowercased() })
        if let resultGenre = resultGenres.intersection(preferredGenresLower).sorted().first {
            score += 0.35
            explanations.append("Matches your saved \(resultGenre) lane")
            signals.append(RecommendationSignal(label: "source", value: "genre"))
            signals.append(RecommendationSignal(label: "lane", value: resultGenre))
        }

        // Tag overlap
        var matchedTags: [String] = []
        var latestEpisodeMatchedTags: [String] = []
        for tag in tasteProfile.topTags {
            let normalizedTag = tag.lowercased()
            if episodeText.contains(normalizedTag) {
                score += 0.24
                latestEpisodeMatchedTags.append(tag)
                matchedTags.append(tag)
            } else if searchableText.contains(normalizedTag) {
                score += 0.15
                matchedTags.append(tag)
            }
        }
        if !latestEpisodeMatchedTags.isEmpty {
            let sample = latestEpisodeMatchedTags.prefix(2).joined(separator: ", ")
            explanations.insert("Latest episodes overlap your \(sample) signal", at: 0)
            signals.append(RecommendationSignal(label: "source", value: "latest episode"))
            signals.append(RecommendationSignal(label: "tags", value: sample))
            if let title = preview?.latestEpisodes.first(where: { episode in
                latestEpisodeMatchedTags.contains(where: { tag in
                    "\(episode.title) \(episode.summary ?? "")".localizedCaseInsensitiveContains(tag)
                })
            })?.title {
                signals.append(RecommendationSignal(label: "episode", value: Self.truncated(title, limit: 42)))
            }
        } else if !matchedTags.isEmpty {
            let sample = matchedTags.prefix(2).joined(separator: ", ")
            explanations.append("Covers topics you like: \(sample)")
            signals.append(RecommendationSignal(label: "source", value: "taste tag"))
            signals.append(RecommendationSignal(label: "tags", value: sample))
        }

        // Show affinity: boost if title resembles a favorite show
        for show in tasteProfile.showAffinity {
            let showWords = Set(show.lowercased().split(separator: " ").map(String.init))
            let titleWords = Set(titleLower.split(separator: " ").map(String.init))
            let overlap = showWords.intersection(titleWords)
            if !overlap.isEmpty {
                score += 0.10
                explanations.append("Similar to shows you finish")
                signals.append(RecommendationSignal(label: "source", value: "show affinity"))
                break
            }
        }

        if let freshestEpisode = preview?.latestEpisodes.compactMap(\.pubDate).max() {
            let days = max(0, Date().timeIntervalSince(freshestEpisode) / 86_400)
            switch days {
            case ..<14:
                score += 0.08
                signals.append(RecommendationSignal(label: "freshness", value: "active feed"))
            case ..<45:
                score += 0.04
                signals.append(RecommendationSignal(label: "freshness", value: "recent feed"))
            default:
                break
            }
        }

        // Novelty baseline
        score += 0.05

        // Build final explanation
        let explanation: String
        if let first = explanations.first {
            explanation = first
        } else if let genre = result.summary {
            explanation = "Explore \(genre) podcasts"
        } else {
            explanation = "Discovery match from your saved signals"
        }

        if signals.isEmpty {
            signals.append(RecommendationSignal(label: "source", value: "discovery"))
        }

        return ScoredDiscoveryResult(result: result, score: score, explanation: explanation, signalTrace: signals)
    }

    private nonisolated static func normalizedFeedKey(_ raw: String) -> String {
        guard var components = URLComponents(string: raw) else {
            return raw.lowercased()
        }
        let scheme = components.scheme?.lowercased()
        components.scheme = (scheme == "http" || scheme == "feed") ? "https" : scheme
        components.host = components.host?.lowercased()
        if components.port == 80 || components.port == 443 {
            components.port = nil
        }
        components.fragment = nil
        if components.path == "/" {
            components.path = ""
        } else {
            while components.path.hasSuffix("/") {
                components.path.removeLast()
            }
        }
        return components.url?.absoluteString.lowercased() ?? raw.lowercased()
    }

    private nonisolated static func cacheSignature(for profile: UserTasteProfile, subscribedFeedURLs: Set<String>) -> String {
        [
            profile.topTags.map { $0.lowercased() }.joined(separator: "|"),
            profile.preferredGenres.map { $0.lowercased() }.joined(separator: "|"),
            profile.showAffinity.map { $0.lowercased() }.joined(separator: "|"),
            subscribedFeedURLs.sorted().joined(separator: "|")
        ].joined(separator: "||")
    }

    private nonisolated static func truncated(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit - 1)) + "…"
    }
}

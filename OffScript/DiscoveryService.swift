import Foundation
import SwiftData

struct ScoredDiscoveryResult: Identifiable {
    var id: String { result.id }
    let result: PodcastSearchResult
    let score: Double
    let explanation: String
}

actor DiscoveryService {
    private var cachedResults: [ScoredDiscoveryResult] = []
    private var cacheTimestamp: Date = .distantPast

    private let cacheDuration: TimeInterval = 3600 // 1 hour

    func discoverPodcasts(
        tasteProfile: UserTasteProfile,
        subscribedFeedURLs: Set<String>
    ) async -> [ScoredDiscoveryResult] {
        // Return cached results if fresh, filtering out newly subscribed shows
        if Date().timeIntervalSince(cacheTimestamp) < cacheDuration, !cachedResults.isEmpty {
            let stillRelevant = cachedResults.filter { !subscribedFeedURLs.contains($0.result.feedURL.absoluteString) }
            if !stillRelevant.isEmpty {
                return stillRelevant
            }
        }

        let queries = buildQueries(from: tasteProfile)
        guard !queries.isEmpty else { return [] }

        let searchService = await MainActor.run { PodcastSearchService() }
        var allResults: [PodcastSearchResult] = []
        var seenFeedURLs = Set<String>()

        for query in queries {
            guard let results = try? await searchService.search(query: query) else { continue }
            for result in results {
                let feedKey = result.feedURL.absoluteString
                guard !subscribedFeedURLs.contains(feedKey),
                      !seenFeedURLs.contains(feedKey) else { continue }
                seenFeedURLs.insert(feedKey)
                allResults.append(result)
            }
        }

        let scored = allResults.map { result in
            scoreResult(result, tasteProfile: tasteProfile)
        }
        .sorted { $0.score > $1.score }

        let topResults = Array(scored.prefix(10))
        cachedResults = topResults
        cacheTimestamp = Date()
        return topResults
    }

    func invalidateCache() {
        cachedResults = []
        cacheTimestamp = .distantPast
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

        // Query from ALL preferred genres, not just the first
        let genres = profile.preferredGenres
        for genre in genres.prefix(3) {
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

        // Cap at 6 queries to cover more genre diversity
        return Array(queries.prefix(6))
    }

    // MARK: - Scoring

    private func scoreResult(
        _ result: PodcastSearchResult,
        tasteProfile: UserTasteProfile
    ) -> ScoredDiscoveryResult {
        var score: Double = 0.0
        var explanations: [String] = []

        let titleLower = result.title.lowercased()
        let summaryLower = (result.summary ?? "").lowercased()
        let searchableText = "\(titleLower) \(summaryLower)"

        // Genre match — iTunes returns primaryGenreName in the summary field
        let preferredGenresLower = Set(tasteProfile.preferredGenres.map { $0.lowercased() })
        if let resultGenre = result.summary?.lowercased(),
           preferredGenresLower.contains(resultGenre) {
            score += 0.35
            explanations.append("Matches your interest in \(result.summary ?? "")")
        }

        // Tag overlap — check if the podcast title/summary contains user's top tags
        var matchedTags: [String] = []
        for tag in tasteProfile.topTags {
            if searchableText.contains(tag.lowercased()) {
                score += 0.15
                matchedTags.append(tag)
            }
        }
        if !matchedTags.isEmpty {
            explanations.append("Covers topics you like: \(matchedTags.prefix(2).joined(separator: ", "))")
        }

        // Show affinity: boost if title resembles a favorite show
        for show in tasteProfile.showAffinity {
            let showWords = Set(show.lowercased().split(separator: " ").map(String.init))
            let titleWords = Set(titleLower.split(separator: " ").map(String.init))
            let overlap = showWords.intersection(titleWords)
            if !overlap.isEmpty {
                score += 0.10
                explanations.append("Similar to shows you finish")
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
            explanation = "Picked for you based on your taste"
        }

        return ScoredDiscoveryResult(result: result, score: score, explanation: explanation)
    }
}

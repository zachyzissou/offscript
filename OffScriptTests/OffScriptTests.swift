import Foundation
import SwiftData
import Testing
@testable import OffScript

struct OffScriptTests {
    @Test
    func recommendationScoreRewardsBetterFit() {
        let strongFit = RecommendationScorer.score(
            RecommendationScoreInputs(
                recencyDays: 1,
                durationMinutes: 28,
                topicOverlap: 3,
                isFromSubscribedPodcast: true,
                isUnfinished: true
            )
        )
        let weakFit = RecommendationScorer.score(
            RecommendationScoreInputs(
                recencyDays: 21,
                durationMinutes: 95,
                topicOverlap: 0,
                isFromSubscribedPodcast: false,
                isUnfinished: false
            )
        )

        #expect(strongFit > weakFit)
    }

    @Test
    func rssParserExtractsCoreEpisodeFields() throws {
        let xml = """
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
          <channel>
            <title>Signal Path</title>
            <itunes:author>OffScript Studio</itunes:author>
            <description>Studio notes on podcast craft.</description>
            <itunes:image href="https://example.com/show.jpg" />
            <item>
              <title>Episode One</title>
              <guid>ep-1</guid>
              <description>Hello world</description>
              <pubDate>Mon, 16 Mar 2026 12:00:00 +0000</pubDate>
              <itunes:duration>00:42:30</itunes:duration>
              <enclosure url="https://example.com/ep1.mp3" type="audio/mpeg" />
            </item>
          </channel>
        </rss>
        """

        let parsed = try RSSFeedParser().parse(data: Data(xml.utf8))

        #expect(parsed.title == "Signal Path")
        #expect(parsed.author == "OffScript Studio")
        #expect(parsed.items.count == 1)
        #expect(parsed.items.first?.guid == "ep-1")
        #expect(parsed.items.first?.audioURL.absoluteString == "https://example.com/ep1.mp3")
        #expect(parsed.items.first?.duration == 2550)
    }

    @Test
    @MainActor
    func queueServiceMovesItemsAndPersistsOrder() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let podcast = Podcast(title: "Test Show", feedURL: URL(string: "https://example.com/feed.xml")!)
        let first = Episode(title: "First", pubDate: .now, audioURL: URL(string: "https://example.com/1.mp3")!, podcast: podcast)
        let second = Episode(title: "Second", pubDate: .now, audioURL: URL(string: "https://example.com/2.mp3")!, podcast: podcast)
        let third = Episode(title: "Third", pubDate: .now, audioURL: URL(string: "https://example.com/3.mp3")!, podcast: podcast)

        context.insert(podcast)
        context.insert(first)
        context.insert(second)
        context.insert(third)

        try QueueService.add(first, in: context)
        try QueueService.add(second, in: context)
        try QueueService.add(third, in: context)

        try QueueService.move(from: IndexSet(integer: 2), to: 0, in: context)
        let ordered = try QueueService.orderedItems(in: context)

        #expect(ordered.map(\.episode.title) == ["Third", "First", "Second"])
        #expect(ordered.map(\.position) == [0, 1, 2])
    }

    @Test
    func genreCarriesAppleGenreID() {
        #expect(Genre.technology.appleGenreID == 1318)
        #expect(Genre.comedy.appleGenreID == 1303)
        #expect(Genre.trueCrime.appleGenreID == 1488)
    }

    @Test
    func genreHasHumanReadableTitle() {
        #expect(Genre.healthAndWellness.title == "Health & Wellness")
        #expect(Genre.newsAndPolitics.title == "News & Politics")
    }

    @Test
    func allGenresHaveCuratedPodcasts() {
        for genre in Genre.allCases {
            let podcasts = CuratedPodcastCatalog.podcasts(for: genre)
            #expect(!podcasts.isEmpty, "Genre \(genre.title) has no curated podcasts")
        }
    }

    @Test
    func curatedPodcastsHaveValidURLs() {
        let all = CuratedPodcastCatalog.all
        for podcast in all {
            #expect(podcast.feedURL.scheme == "https", "\(podcast.title) has non-https feed URL")
        }
    }

    @Test
    func noDuplicateFeedURLsInCatalog() {
        let all = CuratedPodcastCatalog.all
        let urls = all.map(\.feedURL)
        let unique = Set(urls)
        #expect(urls.count == unique.count, "Duplicate feed URLs found in catalog")
    }

    @Test
    func userProfileServiceRoundTrips() throws {
        UserProfileService.deleteCredential()

        #expect(UserProfileService.currentUserID == nil)
        #expect(UserProfileService.displayName == nil)

        try UserProfileService.saveCredential(userID: "test-user-123", displayName: "Zach")

        #expect(UserProfileService.currentUserID == "test-user-123")
        #expect(UserProfileService.displayName == "Zach")

        UserProfileService.deleteCredential()
        #expect(UserProfileService.currentUserID == nil)
    }

    @Test
    func genrePreferenceBoostIncreasesScore() {
        let base = RecommendationScorer.score(
            RecommendationScoreInputs(
                recencyDays: 5,
                durationMinutes: 30,
                topicOverlap: 1,
                isFromSubscribedPodcast: true,
                isUnfinished: false
            )
        )
        let boosted = RecommendationScorer.score(
            RecommendationScoreInputs(
                recencyDays: 5,
                durationMinutes: 30,
                topicOverlap: 1,
                isFromSubscribedPodcast: true,
                isUnfinished: false
            )
        ) + RecommendationScorer.genreBoost(podcastCategories: ["technology"], preferredGenres: ["technology"])

        #expect(boosted > base)
    }

    @Test
    func genreBoostIsZeroWithNoOverlap() {
        let boost = RecommendationScorer.genreBoost(
            podcastCategories: ["comedy", "entertainment"],
            preferredGenres: ["technology", "science"]
        )
        #expect(boost == 0)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Podcast.self,
            Episode.self,
            EpisodeProfile.self,
            PlaybackEvent.self,
            PreferenceSignal.self,
            QueueItem.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

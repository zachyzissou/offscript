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
    @MainActor
    func queueServicePlayNextPromotesEpisodeToFront() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let podcast = Podcast(title: "Queue Show", feedURL: URL(string: "https://example.com/queue.xml")!)
        let first = Episode(title: "First", pubDate: .now, audioURL: URL(string: "https://example.com/1.mp3")!, podcast: podcast)
        let second = Episode(title: "Second", pubDate: .now, audioURL: URL(string: "https://example.com/2.mp3")!, podcast: podcast)
        let third = Episode(title: "Third", pubDate: .now, audioURL: URL(string: "https://example.com/3.mp3")!, podcast: podcast)

        context.insert(podcast)
        context.insert(first)
        context.insert(second)
        context.insert(third)

        try QueueService.addToEnd(first, in: context)
        try QueueService.addToEnd(second, in: context)
        try QueueService.playNext(third, in: context)

        let ordered = try QueueService.orderedItems(in: context)
        #expect(ordered.map(\.episode.title) == ["Third", "First", "Second"])
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

    @Test
    @MainActor
    func appSettingsRoundTripsPreferences() {
        let originalAutoPlay = AppSettings.autoPlayNext
        let originalPreferShort = AppSettings.preferShortEpisodes
        let originalDownloadedOnly = AppSettings.libraryShowDownloadedOnly
        let originalSortMode = AppSettings.librarySortMode
        let originalGenres = AppSettings.preferredGenres

        AppSettings.autoPlayNext = false
        AppSettings.preferShortEpisodes = true
        AppSettings.libraryShowDownloadedOnly = true
        AppSettings.librarySortMode = .recentlyPlayed
        AppSettings.preferredGenres = [.technology, .newsAndPolitics]

        #expect(AppSettings.autoPlayNext == false)
        #expect(AppSettings.preferShortEpisodes == true)
        #expect(AppSettings.libraryShowDownloadedOnly == true)
        #expect(AppSettings.librarySortMode == .recentlyPlayed)
        #expect(AppSettings.preferredGenres == [.technology, .newsAndPolitics])

        AppSettings.autoPlayNext = originalAutoPlay
        AppSettings.preferShortEpisodes = originalPreferShort
        AppSettings.libraryShowDownloadedOnly = originalDownloadedOnly
        AppSettings.librarySortMode = originalSortMode
        AppSettings.preferredGenres = originalGenres
    }

    @Test
    @MainActor
    func tasteProfileRefreshAggregatesSignals() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let originalGenres = AppSettings.preferredGenres
        AppSettings.preferredGenres = [.technology]

        let podcast = Podcast(
            title: "Signal Path",
            author: "OffScript",
            feedURL: URL(string: "https://example.com/feed.xml")!,
            categories: ["Technology"]
        )
        let episode = Episode(
            title: "Latency and Feel",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/episode.mp3")!,
            podcast: podcast
        )
        let profile = EpisodeProfile(episodeID: episode.id)
        profile.tags = ["latency", "design"]

        context.insert(podcast)
        context.insert(episode)
        context.insert(profile)
        context.insert(PreferenceSignal(action: .like, episode: episode))
        context.insert(PlaybackEvent(kind: .completed, position: 1_800, episode: episode))
        try context.save()

        try TasteProfileService.refresh(in: context)
        let tasteProfile = try context.fetch(FetchDescriptor<UserTasteProfile>()).first

        #expect(tasteProfile?.preferredGenres == ["Technology"])
        #expect(tasteProfile?.topTags.contains("latency") == true)
        #expect(tasteProfile?.showAffinity.contains("Signal Path") == true)
        #expect(tasteProfile?.averageCompletedDurationMinutes == 30)

        AppSettings.preferredGenres = originalGenres
    }

    @Test
    @MainActor
    func downloadServiceDeletesLocalFilesAndResetsEpisodeState() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let podcast = Podcast(title: "Offline Show", feedURL: URL(string: "https://example.com/offline.xml")!)
        let episode = Episode(
            title: "Tunnel Mode",
            pubDate: .now,
            audioURL: URL(string: "https://example.com/offline.mp3")!,
            podcast: podcast
        )

        context.insert(podcast)
        context.insert(episode)
        try context.save()

        let fileURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp3")
        try Data("offline".utf8).write(to: fileURL)
        episode.localFileURL = fileURL
        episode.downloadState = .downloaded
        episode.downloadProgress = 1
        try context.save()

        DownloadService.shared.configure(context: context)
        DownloadService.shared.deleteDownload(for: episode)

        #expect(episode.localFileURL == nil)
        #expect(episode.downloadState == .notDownloaded)
        #expect(episode.downloadProgress == 0)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test
    func chapterParserExtractsTimestampedShowNotes() {
        let summary = """
        00:00 Cold open
        03:42 Why podcast pacing matters
        12:15 Editing for tension
        1:02:03 Closing notes
        """

        let chapters = EpisodeChapterParser.chapters(from: summary, duration: 4_000)

        #expect(chapters.map(\.title) == [
            "Cold open",
            "Why podcast pacing matters",
            "Editing for tension",
            "Closing notes"
        ])
        #expect(chapters.map(\.startTime) == [0, 222, 735, 3723])
    }

    @Test
    func rssParserExtractsFeedMetadataChaptersAndTranscripts() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"
             xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
             xmlns:psc="http://podlove.org/simple-chapters"
             xmlns:podcast="https://podcastindex.org/namespace/1.0">
          <channel>
            <title>Signal Path</title>
            <item>
              <title>Episode 42</title>
              <description>Fallback show notes</description>
              <enclosure url="https://example.com/episode-42.mp3" type="audio/mpeg" />
              <itunes:duration>00:48:10</itunes:duration>
              <podcast:transcript url="https://example.com/episode-42.vtt" type="text/vtt" language="en" rel="captions" />
              <podcast:chapters url="https://example.com/episode-42.json" type="application/json+chapters" />
              <psc:chapters version="1.2">
                <psc:chapter start="00:00:00.000" title="Cold open" />
                <psc:chapter start="00:12:15.000" title="Editing for tension" />
              </psc:chapters>
            </item>
          </channel>
        </rss>
        """

        let parsed = try RSSFeedParser().parse(data: Data(xml.utf8))
        let item = try #require(parsed.items.first)

        #expect(item.chapters.map(\.title) == ["Cold open", "Editing for tension"])
        #expect(item.chapters.map(\.startTime) == [0, 735])
        #expect(item.externalChapterURL?.absoluteString == "https://example.com/episode-42.json")
        #expect(item.transcriptReferences.first?.url.absoluteString == "https://example.com/episode-42.vtt")
        #expect(item.transcriptReferences.first?.mimeType == "text/vtt")
        #expect(item.transcriptReferences.first?.language == "en")
    }

    @Test
    @MainActor
    func episodeResolvedChaptersPreferPersistedMetadata() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let podcast = Podcast(title: "Signal Path", feedURL: URL(string: "https://example.com/feed.xml")!)
        let episode = Episode(
            title: "Metadata First",
            summary: "00:00 Summary chapter\n02:00 Another summary chapter",
            pubDate: .now,
            duration: 600,
            audioURL: URL(string: "https://example.com/episode.mp3")!,
            podcast: podcast
        )

        episode.chapters = [EpisodeChapter(title: "Embedded chapter", startTime: 30)]
        context.insert(podcast)
        context.insert(episode)
        try context.save()

        #expect(episode.resolvedChapters.map(\.title) == ["Embedded chapter"])
        #expect(episode.resolvedChapters.map(\.startTime) == [30])
    }

    @Test
    @MainActor
    func telemetryServicePersistsEvents() throws {
        let container = try makeContainer()
        let context = container.mainContext

        TelemetryService.track(
            "subscription_imported",
            metadata: ["podcast": "Signal Path", "source": "search"],
            in: context
        )

        let events = try context.fetch(FetchDescriptor<TelemetryEvent>())
        #expect(events.count == 1)
        #expect(events.first?.name == "subscription_imported")
        #expect(events.first?.metadata["podcast"] == "Signal Path")
    }

    @Test
    @MainActor
    func downloadServiceReconcilesInterruptedDownloadsOnConfigure() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let podcast = Podcast(title: "Offline Recovery", feedURL: URL(string: "https://example.com/recovery.xml")!)
        let episode = Episode(
            title: "Interrupted Save",
            pubDate: .now,
            audioURL: URL(string: "https://example.com/recovery.mp3")!,
            podcast: podcast
        )

        context.insert(podcast)
        context.insert(episode)
        episode.downloadState = .downloading
        episode.downloadProgress = 0.42
        episode.downloadRequestedAt = .now
        try context.save()

        DownloadService.shared.configure(context: context)
        DownloadService.shared.reconcilePersistedDownloads()

        #expect(episode.downloadState == .failed)
        #expect(episode.downloadProgress == 0)
        #expect(episode.downloadErrorMessage?.contains("interrupted") == true)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Podcast.self,
            Episode.self,
            EpisodeProfile.self,
            PlaybackEvent.self,
            PreferenceSignal.self,
            QueueItem.self,
            UserTasteProfile.self,
            TelemetryEvent.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

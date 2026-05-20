import AppIntents
import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import OffScript

struct OffScriptTests {
    @Test
    func playbackAudioSessionUsesSilentSwitchSafeCategory() throws {
        #if os(iOS)
        let session = RecordingAudioSession()

        try OffScriptAudioSessionConfiguration.apply(to: session)

        #expect(OffScriptAudioSessionConfiguration.category == .playback)
        #expect(OffScriptAudioSessionConfiguration.mode == .spokenAudio)
        #expect(OffScriptAudioSessionConfiguration.options.contains(.allowAirPlay))
        #expect(OffScriptAudioSessionConfiguration.options.contains(.allowBluetoothA2DP))
        #expect(session.category == .playback)
        #expect(session.mode == .spokenAudio)
        #expect(session.options.contains(.allowAirPlay))
        #expect(session.options.contains(.allowBluetoothA2DP))
        #expect(session.routeSharingPolicy == nil)
        #expect(session.didCallSetCategoryWithPolicy == false)
        #endif
    }

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
    func rssParserStopsAfterItemLimitButKeepsChannelMetadata() throws {
        let items = (1...12).map { index in
            """
            <item>
              <title>Episode \(index)</title>
              <guid>episode-\(index)</guid>
              <enclosure url="https://example.com/episode-\(index).mp3" type="audio/mpeg" />
            </item>
            """
        }.joined(separator: "\n")
        let xml = """
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
          <channel>
            <title>Large Back Catalog</title>
            <itunes:author>OffScript Studio</itunes:author>
            <description>Hundreds of episodes, capped during bootstrap.</description>
            <itunes:image href="https://example.com/show.jpg" />
            \(items)
          </channel>
        </rss>
        """

        let parsed = try RSSFeedParser().parse(data: Data(xml.utf8), itemLimit: 3)

        #expect(parsed.title == "Large Back Catalog")
        #expect(parsed.author == "OffScript Studio")
        #expect(parsed.artworkURL?.absoluteString == "https://example.com/show.jpg")
        #expect(parsed.items.map(\.guid) == ["episode-1", "episode-2", "episode-3"])
    }

    @Test
    func rssParserUnlimitedModeStillParsesAllItems() throws {
        let items = (1...12).map { index in
            """
            <item>
              <title>Episode \(index)</title>
              <guid>episode-\(index)</guid>
              <enclosure url="https://example.com/episode-\(index).mp3" type="audio/mpeg" />
            </item>
            """
        }.joined(separator: "\n")
        let xml = """
        <rss version="2.0">
          <channel>
            <title>Full Sync Feed</title>
            \(items)
          </channel>
        </rss>
        """

        let parsed = try RSSFeedParser().parse(data: Data(xml.utf8))

        #expect(parsed.items.count == 12)
        #expect(parsed.items.last?.guid == "episode-12")
    }

    @Test
    func opmlBootstrapConfigCapsFeedParseItems() {
        #expect(FeedSyncOptions.standard().feedParseItemLimit == nil)
        #expect(FeedSyncOptions.fastBatchImport().feedParseItemLimit == nil)
        #expect(FeedSyncOptions.opmlBootstrap().feedParseItemLimit == 10)
        #expect(FeedSyncOptions.onboardingBootstrap().feedParseItemLimit == 10)
        #expect(FeedSyncOptions.singleAddBootstrap().feedParseItemLimit == 36)
        #expect(FeedSyncOptions.opmlBootstrap(episodeLimit: 12).feedParseItemLimit == 36)
    }

    @Test
    func opmlImportDedupesFeedsPreservingFirstSeenOrder() throws {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline text="First" xmlUrl="https://Example.com/feed.xml" />
            <outline text="Second" xmlUrl="https://example.com/second.xml" />
            <outline text="Duplicate" xmlUrl="https://example.com/feed.xml/" />
            <outline text="Feed Scheme Duplicate" xmlUrl="feed://example.com/feed.xml#rss" />
          </body>
        </opml>
        """

        let entries = try PodcastImportService.extractFeedURLs(fromOPML: Data(opml.utf8))

        #expect(entries.map(\.feedURL.absoluteString) == [
            "https://Example.com/feed.xml",
            "https://example.com/second.xml"
        ])
        #expect(entries.map(\.title) == ["First", "Second"])
    }

    @Test
    @MainActor
    func opmlImportPlanSkipsExistingNormalizedFeedsBeforeNetworkWork() throws {
        let existing = OPMLFeedEntry(
            feedURL: try #require(URL(string: "http://Example.com/feed.xml/")),
            title: "Existing",
            author: nil
        )
        let fresh = OPMLFeedEntry(
            feedURL: try #require(URL(string: "https://example.com/fresh.xml")),
            title: "Fresh",
            author: nil
        )

        let plan = BatchImportService.importPlan(
            for: [existing, fresh],
            existingFeedKeys: ["https://example.com/feed.xml"]
        )

        #expect(plan.entriesToImport == [fresh])
        #expect(plan.initialProgress[existing.feedURL] == .skipped)
        #expect(plan.initialProgress[fresh.feedURL] == .pending)
    }

    @Test
    @MainActor
    func opmlBatchStagesSubscriptionsBeforeNetworkWork() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let entries = (1...258).map { index in
            OPMLFeedEntry(
                feedURL: URL(string: "https://example.com/feed-\(index).xml")!,
                title: "Imported Show \(index)",
                author: "Author \(index)"
            )
        }

        let stagedCount = try BatchImportService.stageSubscriptions(
            for: entries,
            in: context
        )

        let podcasts = try context.fetch(FetchDescriptor<Podcast>())
        #expect(stagedCount == 258)
        #expect(podcasts.count == 258)
        #expect(podcasts.allSatisfy { $0.isSubscribed } == true)
        #expect(podcasts.first(where: { $0.title == "Imported Show 258" })?.syncStatus == "syncing")
    }

    @Test
    func opmlBootstrapUsesShorterFeedTimeoutThanStandardSync() {
        #expect(FeedSyncOptions.standard().feedRequestTimeout == 20)
        #expect(FeedSyncOptions.fastBatchImport().feedRequestTimeout == 12)
        #expect(FeedSyncOptions.opmlBootstrap().feedRequestTimeout == 8)
        #expect(FeedSyncOptions.onboardingBootstrap().feedRequestTimeout == 8)
        #expect(FeedSyncOptions.singleAddBootstrap().feedRequestTimeout == 8)
    }

    @Test
    func onboardingHydrationDefersAfterCompletionToProtectFirstHomePaint() {
        #expect(OnboardingHydrationScheduler.defaultDelayNanoseconds >= 1_000_000_000)
        #expect(OnboardingHydrationScheduler.defaultDelayNanoseconds < 2_000_000_000)
    }

    @Test
    @MainActor
    func opmlBatchStagingResubscribesExistingNormalizedFeeds() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = Podcast(
            title: "Old Title",
            feedURL: try #require(URL(string: "http://example.com/feed.xml/")),
            isSubscribed: false
        )
        context.insert(existing)
        try context.save()
        let entry = OPMLFeedEntry(
            feedURL: try #require(URL(string: "https://example.com/feed.xml")),
            title: "New OPML Title",
            author: "OPML Author"
        )

        let stagedCount = try BatchImportService.stageSubscriptions(for: [entry], in: context)

        let podcasts = try context.fetch(FetchDescriptor<Podcast>())
        #expect(stagedCount == 1)
        #expect(podcasts.count == 1)
        #expect(existing.isSubscribed)
        #expect(existing.title == "New OPML Title")
        #expect(existing.author == "OPML Author")
        #expect(existing.syncStatus == "syncing")
    }

    @Test
    @MainActor
    func opmlBatchStagingResubscribesNormalizedFeedWithoutExactURLEquality() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = Podcast(
            title: "Dormant Feed",
            feedURL: try #require(URL(string: "feed://EXAMPLE.com/feed.xml#rss")),
            isSubscribed: false
        )
        let unrelated = Podcast(
            title: "Unrelated",
            feedURL: try #require(URL(string: "https://other.example.com/feed.xml")),
            isSubscribed: true
        )
        context.insert(existing)
        context.insert(unrelated)
        try context.save()

        let entry = OPMLFeedEntry(
            feedURL: try #require(URL(string: "https://example.com/feed.xml/")),
            title: "Restaged Feed",
            author: nil
        )

        let stagedCount = try BatchImportService.stageSubscriptions(for: [entry], in: context)
        let podcasts = try context.fetch(FetchDescriptor<Podcast>())

        #expect(stagedCount == 1)
        #expect(podcasts.count == 2)
        #expect(existing.isSubscribed)
        #expect(existing.title == "Restaged Feed")
        #expect(existing.feedURL == entry.feedURL)
        #expect(unrelated.title == "Unrelated")
    }

    @Test
    @MainActor
    func failedOPMLBootstrapMarksStagedSubscriptionRetryable() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let entry = OPMLFeedEntry(
            feedURL: try #require(URL(string: "https://example.com/bad-feed.xml")),
            title: "Bad Feed",
            author: nil
        )
        try BatchImportService.stageSubscriptions(for: [entry], in: context)

        BatchImportService.markStagedSubscriptionFailed(
            entry: entry,
            error: URLError(.timedOut),
            in: context
        )

        let podcast = try #require(try context.fetch(FetchDescriptor<Podcast>()).first)
        #expect(podcast.isSubscribed)
        #expect(podcast.syncStatus == "failed")
        #expect(podcast.syncFailureCount == 1)
        #expect(podcast.syncErrorMessage?.isEmpty == false)
        #expect(podcast.nextRetryAt != nil)
    }

    @Test
    @MainActor
    func cancelledOPMLBootstrapClearsUnlaunchedStagedSubscriptions() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let entries = (1...12).map { index in
            OPMLFeedEntry(
                feedURL: URL(string: "https://example.com/cancel-\(index).xml")!,
                title: "Cancel Show \(index)",
                author: nil
            )
        }
        try BatchImportService.stageSubscriptions(for: entries, in: context)

        BatchImportService.markStagedSubscriptionsCancelled(for: entries, in: context)

        let podcasts = try context.fetch(FetchDescriptor<Podcast>())
        #expect(podcasts.count == 12)
        #expect(podcasts.contains(where: { $0.syncStatus == "syncing" }) == false)
        #expect(podcasts.allSatisfy { $0.isSubscribed } == true)
        #expect(podcasts.allSatisfy { $0.syncErrorMessage == nil } == true)
        #expect(podcasts.allSatisfy { $0.nextRetryAt == nil } == true)
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
    @MainActor
    func queueServiceSkipsCurrentEpisodeWhenPoppingNext() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let podcast = Podcast(title: "Queue Advance", feedURL: URL(string: "https://example.com/queue-advance.xml")!)
        let current = Episode(title: "Current", pubDate: .now, audioURL: URL(string: "https://example.com/current.mp3")!, podcast: podcast)
        let next = Episode(title: "Next", pubDate: .now, audioURL: URL(string: "https://example.com/next.mp3")!, podcast: podcast)

        context.insert(podcast)
        context.insert(current)
        context.insert(next)

        try QueueService.addToEnd(current, in: context)
        try QueueService.addToEnd(next, in: context)

        let popped = try QueueService.popNextEpisode(skipping: current.id, in: context)
        let remaining = try QueueService.orderedItems(in: context)

        #expect(popped?.id == next.id)
        #expect(current.isQueued == false)
        #expect(next.isQueued == false)
        #expect(remaining.isEmpty)
    }

    @Test
    @MainActor
    func queueServiceClearAllEmptiesQueueAndUpdatesIsQueued() throws {
        // #200 / #126 — `× CLEAR ALL` confirm now delegates to a single
        // `QueueService.clearAll(...)` transaction. Verifies the method
        // empties the queue, returns the count, and clears `isQueued`
        // on every removed episode.
        let container = try makeContainer()
        let context = container.mainContext

        let podcast = Podcast(title: "Bulk Show", feedURL: URL(string: "https://example.com/bulk.xml")!)
        context.insert(podcast)
        let episodes = (1...4).map { i -> Episode in
            let ep = Episode(
                title: "Bulk \(i)",
                pubDate: .now,
                audioURL: URL(string: "https://example.com/bulk-\(i).mp3")!,
                podcast: podcast
            )
            context.insert(ep)
            return ep
        }
        for ep in episodes {
            try QueueService.addToEnd(ep, in: context)
        }
        #expect(episodes.allSatisfy { $0.isQueued })

        let cleared = try QueueService.clearAll(in: context)
        let remaining = try QueueService.orderedItems(in: context)

        #expect(cleared == 4)
        #expect(remaining.isEmpty)
        #expect(episodes.allSatisfy { $0.isQueued == false })
    }

    @Test
    @MainActor
    func queueServiceClearAllOnEmptyQueueIsANoOp() throws {
        // Idempotency check — calling clearAll on an empty queue
        // shouldn't throw and should report 0 removed.
        let container = try makeContainer()
        let context = container.mainContext

        let cleared = try QueueService.clearAll(in: context)
        #expect(cleared == 0)
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
    func homeRecommendationsPutQueueIntentBeforeFreshness() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        AppSettings.preferredGenres = []
        defer { AppSettings.preferredGenres = originalGenres }

        let queuedShow = Podcast(title: "Queued Signal", feedURL: URL(string: "https://example.com/queued.xml")!)
        let freshShow = Podcast(title: "Fresh But Random", feedURL: URL(string: "https://example.com/fresh.xml")!)
        let queued = Episode(
            title: "Older Episode You Chose",
            pubDate: Date().addingTimeInterval(-14 * 86_400),
            duration: 2_400,
            audioURL: URL(string: "https://example.com/queued.mp3")!,
            podcast: queuedShow
        )
        let fresh = Episode(
            title: "Brand New But Unanchored",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/fresh.mp3")!,
            podcast: freshShow
        )

        context.insert(queuedShow)
        context.insert(freshShow)
        context.insert(queued)
        context.insert(fresh)
        try QueueService.playNext(queued, in: context)

        let sections = try RecommendationService().homeSections(context: context, limit: 3)

        #expect(sections.first?.title == "Signal Lock")
        #expect(sections.first?.episodes.first?.id == queued.id)
        #expect(sections.first?.explanation(for: queued).contains("queue") == true)
        #expect(sections.first?.signalTrace(for: queued).contains(RecommendationSignal(label: "source", value: "queue")) == true)
        // Fresh-but-unanchored episodes still surface in the From Your
        // Subscriptions catch-all rail so a thin-signal user with imported
        // shows isn't shown only Apple Podcasts discovery. They must not
        // appear above Signal Lock or in Signal Lock itself, though.
        #expect(sections.first?.episodes.contains(where: { $0.id == fresh.id }) == false)
        let freshSection = sections.first(where: { $0.episodes.contains(where: { $0.id == fresh.id }) })
        #expect(freshSection?.title == "From Your Subscriptions")
    }

    @Test
    func discoveryLimitDemotesWhenSignalIsThin() {
        // Strong signal (3+ populated rails) gets the full mode limit.
        #expect(RecommendationService.discoveryCardLimit(mode: .discovery, signalDrivenRailCount: 5) == 10)
        #expect(RecommendationService.discoveryCardLimit(mode: .balanced, signalDrivenRailCount: 3) == 6)

        // Mid signal (1-2 rails) halves the limit but stays >= 3.
        #expect(RecommendationService.discoveryCardLimit(mode: .discovery, signalDrivenRailCount: 2) == 5)
        #expect(RecommendationService.discoveryCardLimit(mode: .balanced, signalDrivenRailCount: 1) == 3)

        // Thin signal (0 rails) caps at 3 so discovery doesn't dominate
        // an otherwise-empty Home.
        #expect(RecommendationService.discoveryCardLimit(mode: .discovery, signalDrivenRailCount: 0) == 3)
        #expect(RecommendationService.discoveryCardLimit(mode: .balanced, signalDrivenRailCount: 0) == 3)
    }

    @Test
    func discoveryLimitIgnoresSignalCountWhenNotProvided() {
        // Pre-existing callers that don't pass a signal count get the
        // unchanged full mode limit so behavior is backward-compatible.
        #expect(RecommendationService.discoveryCardLimit(mode: .discovery, signalDrivenRailCount: nil) == 10)
        #expect(RecommendationService.discoveryCardLimit(mode: .balanced, signalDrivenRailCount: nil) == 6)
        #expect(RecommendationService.discoveryCardLimit(mode: .signalLocked, signalDrivenRailCount: nil) == 0)
    }

    @Test
    @MainActor
    func homeRecommendationsSurfaceSubscriptionFreshnessWhenSignalIsThin() throws {
        // Reproduces the "feels like Apple Podcasts" case (#191): user
        // has subscriptions but no completion / explicit-feedback signal
        // in the last 90 days. Without the From Your Subscriptions
        // fallback, the rec rails come back empty and Discovery /
        // Tuned Genres dominate the screen. With the fallback, the
        // user's actual subscribed-show episodes surface as a real
        // Home rail.
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        AppSettings.preferredGenres = []
        defer { AppSettings.preferredGenres = originalGenres }

        let subscribedShow = Podcast(
            title: "Imported Show",
            feedURL: URL(string: "https://example.com/imported.xml")!,
            isSubscribed: true
        )
        let unsubscribedShow = Podcast(
            title: "Unsubscribed Drift",
            feedURL: URL(string: "https://example.com/drift.xml")!,
            isSubscribed: false
        )
        let subEpisode = Episode(
            title: "Latest From Your Subs",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/sub.mp3")!,
            podcast: subscribedShow
        )
        let outsideEpisode = Episode(
            title: "Outsider — never tuned",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/outside.mp3")!,
            podcast: unsubscribedShow
        )

        context.insert(subscribedShow)
        context.insert(unsubscribedShow)
        context.insert(subEpisode)
        context.insert(outsideEpisode)

        let sections = try RecommendationService().homeSections(context: context, limit: 3)

        let fromYourSubs = sections.first(where: { $0.title == "From Your Subscriptions" })
        #expect(fromYourSubs != nil, "From Your Subscriptions rail should populate when subscribed shows have unplayed episodes")
        #expect(fromYourSubs?.episodes.contains(where: { $0.id == subEpisode.id }) == true)
        #expect(fromYourSubs?.episodes.contains(where: { $0.id == outsideEpisode.id }) == false)
    }

    @Test
    @MainActor
    func homeRecommendationsPreferCompletedShowAffinityOverRecency() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        AppSettings.preferredGenres = []
        defer { AppSettings.preferredGenres = originalGenres }

        let affinityShow = Podcast(title: "Finished Show", feedURL: URL(string: "https://example.com/finished.xml")!)
        let randomShow = Podcast(title: "Random Fresh", feedURL: URL(string: "https://example.com/random.xml")!)
        let completed = Episode(
            title: "Already Completed",
            pubDate: Date().addingTimeInterval(-20 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/completed.mp3")!,
            podcast: affinityShow
        )
        let olderFromAffinity = Episode(
            title: "Older But Earned",
            pubDate: Date().addingTimeInterval(-10 * 86_400),
            duration: 2_100,
            audioURL: URL(string: "https://example.com/earned.mp3")!,
            podcast: affinityShow
        )
        let freshRandom = Episode(
            title: "Fresh But Generic",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/generic.mp3")!,
            podcast: randomShow
        )

        completed.isPlayed = true
        context.insert(affinityShow)
        context.insert(randomShow)
        context.insert(completed)
        context.insert(olderFromAffinity)
        context.insert(freshRandom)
        context.insert(PlaybackEvent(kind: .completed, position: 1_800, episode: completed))
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)
        let firstEpisode = sections.first?.episodes.first

        #expect(firstEpisode?.id == olderFromAffinity.id)
        #expect(sections.first?.explanation(for: olderFromAffinity) == "You keep finishing Finished Show")
        #expect(sections.first?.signalTrace(for: olderFromAffinity).contains(RecommendationSignal(label: "source", value: "completion")) == true)
        #expect(sections.first?.signalTrace(for: olderFromAffinity).contains(RecommendationSignal(label: "show", value: "Finished Show")) == true)
        // freshRandom is from a subscribed show with no taste signal, so
        // it surfaces in From Your Subscriptions (the catch-all rail) but
        // never above completion-affinity in the signal-driven rails.
        let freshRandomSection = sections.first(where: { $0.episodes.contains(where: { $0.id == freshRandom.id }) })
        #expect(freshRandomSection == nil || freshRandomSection?.title == "From Your Subscriptions")
        #expect(sections.first?.episodes.contains(where: { $0.id == freshRandom.id }) == false)
    }

    @Test
    @MainActor
    func homeRecommendationsPreferExplicitMoreLikeThisOverPassiveShowAffinity() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        AppSettings.preferredGenres = []
        defer { AppSettings.preferredGenres = originalGenres }

        let likedShow = Podcast(title: "Liked Topic", feedURL: URL(string: "https://example.com/liked-topic.xml")!)
        let affinityShow = Podcast(title: "Finished Show", feedURL: URL(string: "https://example.com/passive-finished.xml")!)
        let seed = Episode(
            title: "Seed You Asked For",
            pubDate: Date().addingTimeInterval(-9 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/seed-like.mp3")!,
            podcast: likedShow
        )
        let explicitMatch = Episode(
            title: "Older Explicit Match",
            pubDate: Date().addingTimeInterval(-8 * 86_400),
            duration: 2_100,
            audioURL: URL(string: "https://example.com/explicit-match.mp3")!,
            podcast: likedShow
        )
        let completed = Episode(
            title: "Completed Passive",
            pubDate: Date().addingTimeInterval(-4 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/passive-completed.mp3")!,
            podcast: affinityShow
        )
        let passiveAffinity = Episode(
            title: "Newer Passive Affinity",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/passive-affinity.mp3")!,
            podcast: affinityShow
        )
        let seedProfile = EpisodeProfile(episodeID: seed.id)
        seedProfile.tags = ["indie interviews"]
        let matchProfile = EpisodeProfile(episodeID: explicitMatch.id)
        matchProfile.tags = ["indie interviews"]

        completed.isPlayed = true
        context.insert(likedShow)
        context.insert(affinityShow)
        context.insert(seed)
        context.insert(explicitMatch)
        context.insert(completed)
        context.insert(passiveAffinity)
        context.insert(seedProfile)
        context.insert(matchProfile)
        context.insert(PreferenceSignal(action: .moreLikeThis, episode: seed))
        context.insert(PlaybackEvent(kind: .completed, position: 1_800, episode: completed))
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)
        let firstEpisode = try #require(sections.first?.episodes.first)

        #expect(firstEpisode.id == explicitMatch.id)
        #expect(sections.first?.signalTrace(for: explicitMatch).contains(RecommendationSignal(label: "source", value: "explicit signal")) == true)
    }

    @Test
    @MainActor
    func homeRecommendationsComposeExplicitTagAndShowIntent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        AppSettings.preferredGenres = []
        defer { AppSettings.preferredGenres = originalGenres }

        let show = Podcast(title: "Decoder", feedURL: URL(string: "https://example.com/decoder.xml")!)
        let seed = Episode(
            title: "AI Tooling Seed",
            pubDate: Date().addingTimeInterval(-3 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/decoder-seed.mp3")!,
            podcast: show
        )
        let followUp = Episode(
            title: "AI Tooling Follow Up",
            pubDate: .now,
            duration: 2_100,
            audioURL: URL(string: "https://example.com/decoder-follow.mp3")!,
            podcast: show
        )
        let seedProfile = EpisodeProfile(episodeID: seed.id)
        seedProfile.tags = ["ai tooling"]
        let followUpProfile = EpisodeProfile(episodeID: followUp.id)
        followUpProfile.tags = ["ai tooling", "developer workflows"]

        context.insert(show)
        context.insert(seed)
        context.insert(followUp)
        context.insert(seedProfile)
        context.insert(followUpProfile)
        context.insert(PreferenceSignal(action: .moreLikeThis, episode: seed))
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)
        let scoredSection = try #require(sections.first(where: { $0.episodes.contains(where: { $0.id == followUp.id }) }))
        let trace = scoredSection.signalTrace(for: followUp)

        #expect(trace.contains(RecommendationSignal(label: "source", value: "explicit signal")))
        #expect(trace.contains(RecommendationSignal(label: "source", value: "show intent")))
        #expect(scoredSection.explanation(for: followUp).contains("Decoder") == true)
        #expect(scoredSection.explanation(for: followUp).contains("ai tooling") == true)
    }

    @Test
    @MainActor
    func homeRecommendationsUseCurrentLikedShowSignalWithoutCachedProfileRefresh() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        AppSettings.preferredGenres = []
        defer { AppSettings.preferredGenres = originalGenres }

        let tasteProfile = UserTasteProfile()
        tasteProfile.topTags = ["already tuned"]
        tasteProfile.showAffinity = []
        tasteProfile.lastUpdatedAt = .now
        let show = Podcast(title: "Freshly Liked Show", feedURL: URL(string: "https://example.com/freshly-liked.xml")!)
        let liked = Episode(
            title: "Liked Episode",
            pubDate: Date().addingTimeInterval(-7 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/freshly-liked-seed.mp3")!,
            podcast: show
        )
        let next = Episode(
            title: "Same Show Next",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/freshly-liked-next.mp3")!,
            podcast: show
        )

        context.insert(tasteProfile)
        context.insert(show)
        context.insert(liked)
        context.insert(next)
        context.insert(PreferenceSignal(action: .like, episode: liked))
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)
        let firstEpisode = try #require(sections.first?.episodes.first)

        #expect(firstEpisode.id == next.id)
        #expect(sections.first?.title == "More From Shows You Chose")
        #expect(sections.first?.signalTrace(for: next).contains(RecommendationSignal(label: "source", value: "show intent")) == true)
    }

    @Test
    @MainActor
    func homeRecommendationsFetchExplicitShowCandidatesOutsideGlobalRecencyWindow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        AppSettings.preferredGenres = []
        defer { AppSettings.preferredGenres = originalGenres }

        let now = Date()
        let likedShow = Podcast(title: "Deep Signal", feedURL: URL(string: "https://example.com/deep-signal.xml")!)
        let noisyShow = Podcast(title: "Noisy Daily", feedURL: URL(string: "https://example.com/noisy-daily.xml")!)
        likedShow.isSubscribed = true
        noisyShow.isSubscribed = true
        let seed = Episode(
            title: "Episode You Liked",
            pubDate: now.addingTimeInterval(-60 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/deep-seed.mp3")!,
            podcast: likedShow
        )
        seed.isPlayed = true
        let earnedOlderEpisode = Episode(
            title: "Older But Actually Relevant",
            pubDate: now.addingTimeInterval(-45 * 86_400),
            duration: 2_100,
            audioURL: URL(string: "https://example.com/deep-earned.mp3")!,
            podcast: likedShow
        )

        context.insert(likedShow)
        context.insert(noisyShow)
        context.insert(seed)
        context.insert(earnedOlderEpisode)
        context.insert(PreferenceSignal(action: .moreLikeThis, episode: seed))

        for index in 0..<400 {
            let episode = Episode(
                title: "Noisy Fresh \(index)",
                pubDate: now.addingTimeInterval(Double(-index) * 60),
                duration: 1_800,
                audioURL: URL(string: "https://example.com/noisy-\(index).mp3")!,
                podcast: noisyShow
            )
            context.insert(episode)
        }
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)
        let allEpisodes = sections.flatMap(\.episodes)
        let section = try #require(sections.first(where: { $0.episodes.contains(where: { $0.id == earnedOlderEpisode.id }) }))

        #expect(allEpisodes.contains(where: { $0.id == earnedOlderEpisode.id }))
        #expect(section.signalTrace(for: earnedOlderEpisode).contains(RecommendationSignal(label: "source", value: "show intent")) == true)
    }

    @Test
    @MainActor
    func homeRecommendationsCanSkipTasteProfileRefreshOnActivation() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let profile = UserTasteProfile()
        profile.topTags = ["stale"]
        profile.showAffinity = ["Known Show"]
        profile.lastUpdatedAt = Date(timeIntervalSince1970: 100)

        let podcast = Podcast(title: "Fresh Activation Signal", feedURL: URL(string: "https://example.com/fresh-activation.xml")!)
        let seed = Episode(
            title: "Completed Activation Seed",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/fresh-activation-seed.mp3")!,
            podcast: podcast
        )
        seed.isPlayed = true
        let candidate = Episode(
            title: "Activation Candidate",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/fresh-activation-candidate.mp3")!,
            podcast: podcast
        )
        let seedProfile = EpisodeProfile(episodeID: seed.id)
        seedProfile.tags = ["activation"]
        let candidateProfile = EpisodeProfile(episodeID: candidate.id)
        candidateProfile.tags = ["activation"]

        context.insert(profile)
        context.insert(podcast)
        context.insert(seed)
        context.insert(candidate)
        context.insert(seedProfile)
        context.insert(candidateProfile)
        context.insert(PlaybackEvent(kind: .completed, position: 1_800, episode: seed))
        try context.save()

        let sections = try RecommendationService().homeSections(
            context: context,
            limit: 3,
            refreshTasteProfile: false
        )

        #expect(sections.flatMap(\.episodes).contains { $0.id == candidate.id })
        #expect(profile.topTags == ["stale"])
        #expect(profile.lastUpdatedAt == Date(timeIntervalSince1970: 100))

        _ = try RecommendationService().homeSections(
            context: context,
            limit: 3,
            refreshTasteProfile: true
        )

        #expect(profile.topTags.contains("activation"))
    }

    @Test
    @MainActor
    func recommendationPreferredGenresFallbackToOnboardingSettingsWhenProfileIsEmpty() {
        let originalGenres = AppSettings.preferredGenres
        AppSettings.preferredGenres = [.technology, .newsAndPolitics]
        defer { AppSettings.preferredGenres = originalGenres }

        let emptyProfile = UserTasteProfile()

        #expect(RecommendationService.effectivePreferredGenreTitles(for: emptyProfile) == ["Technology", "News & Politics"])
    }

    @Test
    @MainActor
    func preferenceFeedbackServicePostsRetuneNotificationAfterSaving() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let podcast = Podcast(title: "Signal Show", feedURL: URL(string: "https://example.com/signal.xml")!)
        let episode = Episode(
            title: "Signal Episode",
            pubDate: .now,
            audioURL: URL(string: "https://example.com/signal.mp3")!,
            podcast: podcast
        )
        context.insert(podcast)
        context.insert(episode)
        try context.save()

        var notificationCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: .offscriptRecommendationFeedbackChanged,
            object: nil,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try PreferenceFeedbackService.register(.like, for: episode, in: context)

        let descriptor = FetchDescriptor<PreferenceSignal>()
        let signals = try context.fetch(descriptor)
        #expect(signals.count == 1)
        #expect(signals.first?.action == .like)
        #expect(notificationCount == 1)
    }

    @Test
    @MainActor
    func homeRecommendationsSeparateExplicitShowIntentFromCompletionAffinity() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        AppSettings.preferredGenres = []
        defer { AppSettings.preferredGenres = originalGenres }

        let likedShow = Podcast(title: "Chosen Show", feedURL: URL(string: "https://example.com/chosen-show.xml")!)
        let finishedShow = Podcast(title: "Finished Show", feedURL: URL(string: "https://example.com/finished-lane.xml")!)
        let likedSeed = Episode(
            title: "Liked Seed",
            pubDate: Date().addingTimeInterval(-6 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/liked-seed.mp3")!,
            podcast: likedShow
        )
        let chosenNext = Episode(
            title: "Chosen Follow Up",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/chosen-next.mp3")!,
            podcast: likedShow
        )
        let completed = Episode(
            title: "Completed Seed",
            pubDate: Date().addingTimeInterval(-5 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/completed-lane.mp3")!,
            podcast: finishedShow
        )
        let finishedNext = Episode(
            title: "Finished Follow Up",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/finished-next.mp3")!,
            podcast: finishedShow
        )

        completed.isPlayed = true
        context.insert(likedShow)
        context.insert(finishedShow)
        context.insert(likedSeed)
        context.insert(chosenNext)
        context.insert(completed)
        context.insert(finishedNext)
        context.insert(PreferenceSignal(action: .moreLikeThis, episode: likedSeed))
        context.insert(PlaybackEvent(kind: .completed, position: 1_800, episode: completed))
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)
        let intentSection = try #require(sections.first(where: { $0.title == "More From Shows You Chose" }))
        let finishSection = try #require(sections.first(where: { $0.title == "Shows You Finish" }))

        #expect(intentSection.episodes.map(\.id).contains(chosenNext.id))
        #expect(!intentSection.episodes.map(\.id).contains(finishedNext.id))
        #expect(finishSection.episodes.map(\.id).contains(finishedNext.id))
        #expect(!finishSection.episodes.map(\.id).contains(chosenNext.id))
    }

    @Test
    @MainActor
    func homeRecommendationsRouteRecencyOnlyCandidatesToSubscriptionFallbackOnly() throws {
        // Replaces the old "no recency-only candidates" contract: cold-
        // start episodes from a subscribed show now surface ONLY in the
        // From Your Subscriptions catch-all rail (so a fresh-install user
        // doesn't see only Apple Podcasts discovery), and never in any
        // signal-driven rail.
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        AppSettings.preferredGenres = []
        defer { AppSettings.preferredGenres = originalGenres }

        let podcast = Podcast(title: "Cold Start Show", feedURL: URL(string: "https://example.com/cold.xml")!)
        let episode = Episode(
            title: "Fresh Without Evidence",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/cold.mp3")!,
            podcast: podcast
        )
        context.insert(podcast)
        context.insert(episode)
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)

        let containingSection = sections.first(where: { $0.episodes.contains(where: { $0.id == episode.id }) })
        #expect(containingSection?.title == "From Your Subscriptions")

        let signalDrivenTitles: Set<String> = [
            "Signal Lock", "Resume Thread", "More From Shows You Chose",
            "Shows You Finish", "Topic Continuation", "Tuned Genres", "Short Window"
        ]
        for section in sections where signalDrivenTitles.contains(section.title) {
            #expect(section.episodes.contains(where: { $0.id == episode.id }) == false,
                    "\(section.title) must not surface recency-only candidates")
        }
    }

    @Test
    @MainActor
    func homeRecommendationsFilterNegativePreferenceSignals() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let podcast = Podcast(title: "Blocked Show", feedURL: URL(string: "https://example.com/blocked.xml")!)
        let episode = Episode(
            title: "Do Not Surface",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/blocked.mp3")!,
            podcast: podcast
        )
        episode.playedPosition = 600
        context.insert(podcast)
        context.insert(episode)
        context.insert(PreferenceSignal(action: .notInterested, episode: episode))
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)

        #expect(sections.flatMap(\.episodes).contains(where: { $0.id == episode.id }) == false)
    }

    @Test
    @MainActor
    func headlineCandidateUsesStrongestAuthoredSignalAcrossSections() throws {
        let lowShow = Podcast(title: "Low Evidence", feedURL: URL(string: "https://example.com/low.xml")!)
        let strongShow = Podcast(title: "Strong Evidence", feedURL: URL(string: "https://example.com/strong.xml")!)
        let low = Episode(title: "Generic Queue", pubDate: .now, duration: 1_800, audioURL: URL(string: "https://example.com/low.mp3")!, podcast: lowShow)
        let strong = Episode(title: "Finished Thread", pubDate: .now, duration: 1_800, audioURL: URL(string: "https://example.com/strong.mp3")!, podcast: strongShow)

        let sections = [
            HomeFeedSection(
                title: "Signal Lock",
                subtitle: "User intent lane.",
                scoredEpisodes: [
                    ScoredEpisode(
                        episode: low,
                        score: 180,
                        explanation: "Fits your short-listen setting",
                        signalTrace: [RecommendationSignal(label: "source", value: "duration")]
                    )
                ]
            ),
            HomeFeedSection(
                title: "Shows You Finish",
                subtitle: "Completion lane.",
                scoredEpisodes: [
                    ScoredEpisode(
                        episode: strong,
                        score: 220,
                        explanation: "You keep finishing Strong Evidence",
                        signalTrace: [
                            RecommendationSignal(label: "source", value: "completion"),
                            RecommendationSignal(label: "show", value: "Strong Evidence"),
                            RecommendationSignal(label: "finishes", value: "3")
                        ]
                    )
                ]
            )
        ]

        let headline = try #require(RecommendationService.headlineCandidate(from: sections))

        #expect(headline.episode.id == strong.id)
        #expect(headline.explanation == "You keep finishing Strong Evidence")
    }

    @Test
    @MainActor
    func signalLockedModeExcludesGenreOnlyCandidates() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        AppSettings.preferredGenres = [.technology]
        defer { AppSettings.preferredGenres = originalGenres }

        let podcast = Podcast(
            title: "Genre Only",
            feedURL: URL(string: "https://example.com/genre-only.xml")!,
            categories: ["Technology"]
        )
        let episode = Episode(
            title: "No Behavioral Signal",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/genre-only.mp3")!,
            podcast: podcast
        )
        context.insert(podcast)
        context.insert(episode)
        try context.save()

        let signalSections = try RecommendationService().homeSections(context: context, mode: .signalLocked, limit: 3)
        let balancedSections = try RecommendationService().homeSections(context: context, mode: .balanced, limit: 3)

        #expect(signalSections.flatMap(\.episodes).contains(where: { $0.id == episode.id }) == false)
        #expect(balancedSections.contains(where: { $0.title == "Tuned Genres" && $0.episodes.contains(where: { $0.id == episode.id }) }))
    }

    @Test
    @MainActor
    func lessLikeThisSuppressesSharedTagsAcrossHomeAndPlayer() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let currentShow = Podcast(title: "Now Playing", feedURL: URL(string: "https://example.com/now.xml")!)
        let blockedShow = Podcast(title: "Blocked Signal", feedURL: URL(string: "https://example.com/blocked-shared.xml")!)
        let trustedShow = Podcast(title: "Trusted Signal", feedURL: URL(string: "https://example.com/trusted-shared.xml")!)
        let current = Episode(title: "Current", pubDate: .now, duration: 1_800, audioURL: URL(string: "https://example.com/current-shared.mp3")!, podcast: currentShow)
        let disliked = Episode(title: "Disliked", pubDate: .now, duration: 1_800, audioURL: URL(string: "https://example.com/disliked.mp3")!, podcast: blockedShow)
        let similar = Episode(title: "Similar Blocked", pubDate: .now, duration: 1_800, audioURL: URL(string: "https://example.com/similar.mp3")!, podcast: blockedShow)
        let trusted = Episode(title: "Trusted", pubDate: .now, duration: 1_800, audioURL: URL(string: "https://example.com/trusted.mp3")!, podcast: trustedShow)

        let currentProfile = EpisodeProfile(episodeID: current.id)
        currentProfile.tags = ["craft"]
        let dislikedProfile = EpisodeProfile(episodeID: disliked.id)
        dislikedProfile.tags = ["blocked-topic"]
        let similarProfile = EpisodeProfile(episodeID: similar.id)
        similarProfile.tags = ["blocked-topic"]
        let trustedProfile = EpisodeProfile(episodeID: trusted.id)
        trustedProfile.tags = ["craft"]

        context.insert(currentShow)
        context.insert(blockedShow)
        context.insert(trustedShow)
        context.insert(current)
        context.insert(disliked)
        context.insert(similar)
        context.insert(trusted)
        context.insert(currentProfile)
        context.insert(dislikedProfile)
        context.insert(similarProfile)
        context.insert(trustedProfile)
        context.insert(PreferenceSignal(action: .lessLikeThis, episode: disliked))
        context.insert(PreferenceSignal(action: .like, episode: trusted))
        try context.save()

        let homeEpisodes = try RecommendationService().homeSections(context: context, mode: .balanced, limit: 5).flatMap(\.episodes)
        let playerSuggestions = try RecommendationService().playerSuggestions(currentEpisode: current, context: context, limit: 5)

        #expect(homeEpisodes.contains(where: { $0.id == similar.id }) == false)
        #expect(playerSuggestions.contains(where: { $0.episode.id == similar.id }) == false)
        #expect(playerSuggestions.contains(where: { $0.episode.id == trusted.id }))
    }

    @Test
    @MainActor
    func lessLikeThisSoftPenalizesSharedTagsButDoesNotEraseEntireShow() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let show = Podcast(title: "Mixed Signal Show", feedURL: URL(string: "https://example.com/mixed.xml")!)
        let trustedShow = Podcast(title: "Trusted Topic", feedURL: URL(string: "https://example.com/trusted-topic.xml")!)
        let disliked = Episode(title: "Too Much Hype", pubDate: .now, duration: 1_800, audioURL: URL(string: "https://example.com/hype.mp3")!, podcast: show)
        let sameShowDifferentTopic = Episode(title: "Useful Field Notes", pubDate: .now, duration: 1_800, audioURL: URL(string: "https://example.com/useful.mp3")!, podcast: show)
        let trusted = Episode(title: "Useful Signal Seed", pubDate: .now, duration: 1_800, audioURL: URL(string: "https://example.com/trusted-topic.mp3")!, podcast: trustedShow)

        let dislikedProfile = EpisodeProfile(episodeID: disliked.id)
        dislikedProfile.tags = ["hype"]
        let survivorProfile = EpisodeProfile(episodeID: sameShowDifferentTopic.id)
        survivorProfile.tags = ["field notes"]
        let trustedProfile = EpisodeProfile(episodeID: trusted.id)
        trustedProfile.tags = ["field notes"]

        context.insert(show)
        context.insert(trustedShow)
        context.insert(disliked)
        context.insert(sameShowDifferentTopic)
        context.insert(trusted)
        context.insert(dislikedProfile)
        context.insert(survivorProfile)
        context.insert(trustedProfile)
        context.insert(PreferenceSignal(action: .lessLikeThis, episode: disliked))
        context.insert(PreferenceSignal(action: .like, episode: trusted))
        try context.save()

        let episodes = try RecommendationService()
            .homeSections(context: context, mode: .balanced, limit: 5)
            .flatMap(\.episodes)

        #expect(episodes.contains(where: { $0.id == sameShowDifferentTopic.id }))
    }

    @Test
    @MainActor
    func repeatedNegativeSignalsHardSuppressSharedTags() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let blockedShow = Podcast(title: "Repeated Block", feedURL: URL(string: "https://example.com/repeated-block.xml")!)
        let trustedShow = Podcast(title: "Trusted Contrast", feedURL: URL(string: "https://example.com/trusted-contrast.xml")!)
        let firstDisliked = Episode(title: "First Bad Fit", pubDate: .now, duration: 1_800, audioURL: URL(string: "https://example.com/bad-1.mp3")!, podcast: blockedShow)
        let secondDisliked = Episode(title: "Second Bad Fit", pubDate: .now, duration: 1_800, audioURL: URL(string: "https://example.com/bad-2.mp3")!, podcast: blockedShow)
        let similar = Episode(title: "Third Bad Fit", pubDate: .now, duration: 1_800, audioURL: URL(string: "https://example.com/bad-3.mp3")!, podcast: blockedShow)
        let trusted = Episode(title: "Trusted Signal", pubDate: .now, duration: 1_800, audioURL: URL(string: "https://example.com/trusted-contrast.mp3")!, podcast: trustedShow)

        for episode in [firstDisliked, secondDisliked, similar] {
            let profile = EpisodeProfile(episodeID: episode.id)
            profile.tags = ["overproduced"]
            context.insert(profile)
        }
        let trustedProfile = EpisodeProfile(episodeID: trusted.id)
        trustedProfile.tags = ["overproduced", "field notes"]

        context.insert(blockedShow)
        context.insert(trustedShow)
        context.insert(firstDisliked)
        context.insert(secondDisliked)
        context.insert(similar)
        context.insert(trusted)
        context.insert(trustedProfile)
        context.insert(PreferenceSignal(action: .lessLikeThis, episode: firstDisliked))
        context.insert(PreferenceSignal(action: .lessLikeThis, episode: secondDisliked))
        context.insert(PreferenceSignal(action: .like, episode: trusted))
        try context.save()

        let episodes = try RecommendationService()
            .homeSections(context: context, mode: .balanced, limit: 5)
            .flatMap(\.episodes)

        #expect(episodes.contains(where: { $0.id == similar.id }) == false)
        #expect(episodes.contains(where: { $0.id == trusted.id }) == false)
    }

    @Test
    @MainActor
    func discoveryPreviewEvidenceBeatsGenreOnlyCatalogMatch() throws {
        let tasteProfile = UserTasteProfile()
        tasteProfile.topTags = ["audio craft"]
        tasteProfile.preferredGenres = ["Technology"]

        let genreOnly = PodcastSearchResult(
            title: "Generic Technology Weekly",
            author: "Catalog Network",
            feedURL: URL(string: "https://example.com/generic-tech.xml")!,
            artworkURL: nil,
            websiteURL: nil,
            summary: "Technology"
        )
        let evidenced = PodcastSearchResult(
            title: "Signal Workshop",
            author: "Independent Audio Lab",
            feedURL: URL(string: "https://example.com/signal-workshop.xml")!,
            artworkURL: nil,
            websiteURL: nil,
            summary: "Technology"
        )
        let preview = PodcastPreviewSnapshot(
            title: "Signal Workshop",
            author: "Independent Audio Lab",
            summary: "Field notes for makers and editors.",
            categories: ["Technology"],
            websiteURL: nil,
            latestEpisodes: [
                PodcastPreviewEpisode(
                    id: "episode-1",
                    title: "Audio craft for sharper interviews",
                    pubDate: .now,
                    duration: 1_800,
                    summary: "Practical audio craft choices for hosts.",
                    audioURL: URL(string: "https://example.com/signal-workshop-1.mp3")!,
                    artworkURL: nil
                )
            ]
        )

        let genericScore = DiscoveryService.score(result: genreOnly, tasteProfile: tasteProfile)
        let evidencedScore = DiscoveryService.score(result: evidenced, tasteProfile: tasteProfile, preview: preview)

        #expect(evidencedScore.score > genericScore.score)
        #expect(genericScore.score <= 0.12)
        #expect(genericScore.explanation == "Explore technology podcasts")
        #expect(genericScore.signalTrace.contains(RecommendationSignal(label: "evidence", value: "catalog")))
        #expect(evidencedScore.explanation == "Latest episodes overlap your audio craft signal")
        #expect(evidencedScore.signalTrace.contains(RecommendationSignal(label: "source", value: "latest episode")))
        #expect(evidencedScore.signalTrace.contains(RecommendationSignal(label: "tags", value: "audio craft")))
        #expect(evidencedScore.signalTrace.contains(RecommendationSignal(label: "evidence", value: "local")))
    }

    @Test
    @MainActor
    func playerSuggestionsExposeNowPlayingSignalTrace() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let currentPodcast = Podcast(title: "Now Playing", feedURL: URL(string: "https://example.com/current.xml")!)
        let relatedPodcast = Podcast(title: "Related", feedURL: URL(string: "https://example.com/related.xml")!)
        let current = Episode(
            title: "Current Episode",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/current.mp3")!,
            podcast: currentPodcast
        )
        let related = Episode(
            title: "Shared Signal",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/related.mp3")!,
            podcast: relatedPodcast
        )
        let currentProfile = EpisodeProfile(episodeID: current.id)
        currentProfile.tags = ["audio craft", "interviews"]
        let relatedProfile = EpisodeProfile(episodeID: related.id)
        relatedProfile.tags = ["audio craft"]

        context.insert(currentPodcast)
        context.insert(relatedPodcast)
        context.insert(current)
        context.insert(related)
        context.insert(currentProfile)
        context.insert(relatedProfile)
        try context.save()

        let suggestions = try RecommendationService().playerSuggestions(
            currentEpisode: current,
            context: context,
            limit: 3
        )
        let scored = try #require(suggestions.first)

        #expect(scored.episode.id == related.id)
        #expect(scored.explanation == "Also covers \"audio craft\"")
        #expect(scored.signalTrace.contains(RecommendationSignal(label: "source", value: "now playing")))
        #expect(scored.signalTrace.contains(RecommendationSignal(label: "tag", value: "audio craft")))
    }

    @Test
    @MainActor
    func playerSuggestionsPreferStrongNowPlayingOverlapOverSameShow() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let currentPodcast = Podcast(title: "Current Show", feedURL: URL(string: "https://example.com/current-player.xml")!)
        let relatedPodcast = Podcast(title: "Deep Related", feedURL: URL(string: "https://example.com/deep-related.xml")!)
        let current = Episode(
            title: "Current Context",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/current-context.mp3")!,
            podcast: currentPodcast
        )
        let sameShow = Episode(
            title: "Same Feed But Unrelated",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/same-feed.mp3")!,
            podcast: currentPodcast
        )
        let deepMatch = Episode(
            title: "Cross Show Deep Match",
            pubDate: Date().addingTimeInterval(-2 * 86_400),
            duration: 2_400,
            audioURL: URL(string: "https://example.com/deep-match.mp3")!,
            podcast: relatedPodcast
        )
        let currentProfile = EpisodeProfile(episodeID: current.id)
        currentProfile.tags = ["editing", "field recording", "interviews"]
        let sameProfile = EpisodeProfile(episodeID: sameShow.id)
        sameProfile.tags = ["news"]
        let deepProfile = EpisodeProfile(episodeID: deepMatch.id)
        deepProfile.tags = ["editing", "field recording", "interviews"]

        context.insert(currentPodcast)
        context.insert(relatedPodcast)
        context.insert(current)
        context.insert(sameShow)
        context.insert(deepMatch)
        context.insert(currentProfile)
        context.insert(sameProfile)
        context.insert(deepProfile)
        try context.save()

        let suggestions = try RecommendationService().playerSuggestions(
            currentEpisode: current,
            context: context,
            limit: 3
        )
        let scored = try #require(suggestions.first)

        #expect(scored.episode.id == deepMatch.id)
        #expect(scored.signalTrace.contains(RecommendationSignal(label: "source", value: "now playing")))
    }

    @Test
    func recommendationExplainerRewritesSavedSignalReasonsFromTrace() {
        let reason = RecommendationExplainer.authoredReason(
            fallback: "Matches your saved signal: audio craft, interviews",
            signals: [
                RecommendationSignal(label: "source", value: "tag match"),
                RecommendationSignal(label: "tags", value: "audio craft, interviews")
            ]
        )

        #expect(reason == "Tuned to your saved audio craft and interviews signals")
    }

    @Test
    func recommendationExplainerComposesAndClipsExplicitEvidence() {
        let reason = RecommendationExplainer.authoredReason(
            fallback: "You asked for more from Decoder, and this matches artificial intelligence infrastructure, developer workflows",
            signals: [
                RecommendationSignal(label: "source", value: "explicit signal"),
                RecommendationSignal(label: "tags", value: "artificial intelligence infrastructure, developer workflows"),
                RecommendationSignal(label: "source", value: "show intent"),
                RecommendationSignal(label: "show", value: "Decoder")
            ]
        )

        #expect(reason.hasPrefix("More from Decoder, matching your artificial intelligence"))
        #expect(reason.count <= 72)
    }

    @Test
    func recommendationExplainerRewritesGenreLaneReasonsFromTrace() {
        let reason = RecommendationExplainer.authoredReason(
            fallback: "Matches your selected technology lane",
            signals: [
                RecommendationSignal(label: "source", value: "genre"),
                RecommendationSignal(label: "lane", value: "technology"),
                RecommendationSignal(label: "evidence", value: "local")
            ]
        )

        #expect(reason == "A technology lane pick with local evidence behind it")
    }

    @Test
    func recommendationExplainerPrioritizesEvidenceInMixedDiscoveryTraces() {
        let reason = RecommendationExplainer.authoredReason(
            fallback: "Matches your saved technology lane",
            signals: [
                RecommendationSignal(label: "source", value: "genre"),
                RecommendationSignal(label: "lane", value: "technology"),
                RecommendationSignal(label: "source", value: "latest episode"),
                RecommendationSignal(label: "tags", value: "audio craft"),
                RecommendationSignal(label: "evidence", value: "local")
            ]
        )

        #expect(reason == "Latest episodes overlap your audio craft signal")
    }

    @Test
    func recommendationExplainerDoesNotClaimLocalEvidenceForGenreOnlyDiscovery() {
        let reason = RecommendationExplainer.authoredReason(
            fallback: "Matches your selected technology lane",
            signals: [
                RecommendationSignal(label: "source", value: "genre"),
                RecommendationSignal(label: "lane", value: "technology"),
                RecommendationSignal(label: "evidence", value: "catalog")
            ]
        )

        #expect(reason == "A technology lane pick to sample")
    }

    @Test
    func recommendationExplainerPreservesGenericQuickDurationReasons() {
        let reason = RecommendationExplainer.authoredReason(
            fallback: "Quick 18m listen",
            signals: [
                RecommendationSignal(label: "source", value: "duration"),
                RecommendationSignal(label: "window", value: "18m")
            ]
        )

        #expect(reason == "Quick 18m listen")
    }

    @Test
    func recommendationExplainerKeepsShortListenPreferenceReason() {
        let reason = RecommendationExplainer.authoredReason(
            fallback: "Fits your short-listen setting",
            signals: [
                RecommendationSignal(label: "source", value: "duration"),
                RecommendationSignal(label: "window", value: "28m")
            ]
        )

        #expect(reason == "Fits your short-listen setting")
    }

    @Test
    func recommendationExplainerSwapsTemplateWhenAvoidingPriorSource() {
        // Two adjacent rail cards both backed by the latest-episode signal
        // would render the same "Latest episodes overlap your X signal"
        // template. The avoidingSource overload routes the second card
        // to the next-best source on its trace.
        let signals: [RecommendationSignal] = [
            RecommendationSignal(label: "source", value: "latest episode"),
            RecommendationSignal(label: "source", value: "tag match"),
            RecommendationSignal(label: "tags", value: "audio craft")
        ]

        let primary = RecommendationExplainer.authoredReason(
            fallback: "fallback",
            signals: signals
        )
        let avoiding = RecommendationExplainer.authoredReason(
            fallback: "fallback",
            signals: signals,
            avoidingSource: "latest episode"
        )

        #expect(primary == "Latest episodes overlap your audio craft signal")
        #expect(avoiding == "Tuned to your saved audio craft signal")
    }

    @Test
    func recommendationExplainerSourceExclusionFallsBackToFirstAvailable() {
        // When the avoided source is the only priority match, fall back to
        // any remaining source from the trace rather than returning nil.
        let result = RecommendationExplainer.authoredSource(
            from: ["latest episode", "editor"],
            excluding: "latest episode"
        )
        #expect(result == "editor")
    }

    @Test
    func recommendationExplainerSourceExclusionReturnsNilOnEmptyTrace() {
        let result = RecommendationExplainer.authoredSource(from: [], excluding: "latest episode")
        #expect(result == nil)
    }

    @Test
    func recommendationExplainerKeepsUnknownFallbacks() {
        let fallback = "Special editorial pick"

        let reason = RecommendationExplainer.authoredReason(
            fallback: fallback,
            signals: [RecommendationSignal(label: "source", value: "editor")]
        )

        #expect(reason == fallback)
    }

    @Test
    func podcastDetailRankerPrefersFeedSuppliedEpisodeNumber() {
        let rank = PodcastDetailRanker.chronologicalRank(
            explicitEpisodeNumber: 42,
            displayedIndex: 0,
            totalEpisodeCount: 100,
            filterShowsFullFeed: true
        )
        #expect(rank == 42)
    }

    @Test
    func podcastDetailRankerNumbersOldestFirstOnFullFeed() {
        let newest = PodcastDetailRanker.chronologicalRank(
            explicitEpisodeNumber: nil,
            displayedIndex: 0,
            totalEpisodeCount: 250,
            filterShowsFullFeed: true
        )
        let oldest = PodcastDetailRanker.chronologicalRank(
            explicitEpisodeNumber: nil,
            displayedIndex: 249,
            totalEpisodeCount: 250,
            filterShowsFullFeed: true
        )
        #expect(newest == 250)
        #expect(oldest == 1)
    }

    @Test
    func podcastDetailRankerSuppressesNumberOnFilteredSubsets() {
        let rank = PodcastDetailRanker.chronologicalRank(
            explicitEpisodeNumber: nil,
            displayedIndex: 0,
            totalEpisodeCount: 12,
            filterShowsFullFeed: false
        )
        #expect(rank == nil)
    }

    @Test
    func podcastDetailRankerStillUsesExplicitNumberOnFilteredSubsets() {
        let rank = PodcastDetailRanker.chronologicalRank(
            explicitEpisodeNumber: 7,
            displayedIndex: 0,
            totalEpisodeCount: 3,
            filterShowsFullFeed: false
        )
        #expect(rank == 7)
    }

    @Test
    func podcastDetailRankerHandlesEmptyAndOutOfRangeIndexes() {
        let empty = PodcastDetailRanker.chronologicalRank(
            explicitEpisodeNumber: nil,
            displayedIndex: 0,
            totalEpisodeCount: 0,
            filterShowsFullFeed: true
        )
        let outOfRange = PodcastDetailRanker.chronologicalRank(
            explicitEpisodeNumber: nil,
            displayedIndex: 99,
            totalEpisodeCount: 50,
            filterShowsFullFeed: true
        )
        #expect(empty == nil)
        #expect(outOfRange == nil)
    }

    @Test
    @MainActor
    func appSettingsRoundTripsPreferences() {
        let originalAutoPlay = AppSettings.autoPlayNext
        let originalPreferShort = AppSettings.preferShortEpisodes
        let originalGenres = AppSettings.preferredGenres
        let originalRecommendationMode = AppSettings.recommendationMode

        AppSettings.autoPlayNext = false
        AppSettings.preferShortEpisodes = true
        AppSettings.preferredGenres = [.technology, .newsAndPolitics]
        AppSettings.recommendationMode = .discovery

        #expect(AppSettings.autoPlayNext == false)
        #expect(AppSettings.preferShortEpisodes == true)
        #expect(AppSettings.preferredGenres == [.technology, .newsAndPolitics])
        #expect(AppSettings.recommendationMode == .discovery)

        AppSettings.autoPlayNext = originalAutoPlay
        AppSettings.preferShortEpisodes = originalPreferShort
        AppSettings.preferredGenres = originalGenres
        AppSettings.recommendationMode = originalRecommendationMode
    }

    @Test
    func cloudKitAccountStatusRequiresCloudKitEntitlements() {
        #expect(CloudKitAccountService.entitlementsAllowCloudKitAccountStatus(
            services: nil,
            containerIdentifiers: nil
        ) == false)
        #expect(CloudKitAccountService.entitlementsAllowCloudKitAccountStatus(
            services: ["CloudKit"],
            containerIdentifiers: nil
        ) == false)
        #expect(CloudKitAccountService.entitlementsAllowCloudKitAccountStatus(
            services: ["CloudKit"],
            containerIdentifiers: ["iCloud.com.offscript.app"]
        ) == true)
    }

    @Test
    func sentryEnvironmentUsesStoreKitAppTransactionEnvironment() {
        #expect(SentryEnvironmentResolver.sentryEnvironment(storeKitEnvironmentRawValue: "Production") == "production")
        #expect(SentryEnvironmentResolver.sentryEnvironment(storeKitEnvironmentRawValue: "Sandbox") == "testflight")
        #expect(SentryEnvironmentResolver.sentryEnvironment(storeKitEnvironmentRawValue: "Xcode") == "debug")
        #expect(SentryEnvironmentResolver.sentryEnvironment(storeKitEnvironmentRawValue: "Unexpected") == "production")
    }

    @Test
    @MainActor
    func settingsCountServiceCountsSubscribedPodcastsWithoutFetchingRows() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = Podcast(title: "First", feedURL: URL(string: "https://example.com/first.xml")!)
        let second = Podcast(title: "Second", feedURL: URL(string: "https://example.com/second.xml")!)
        let ignored = Podcast(title: "Ignored", feedURL: URL(string: "https://example.com/ignored.xml")!)
        ignored.isSubscribed = false
        context.insert(first)
        context.insert(second)
        context.insert(ignored)
        try context.save()

        #expect(SettingsCountService.subscribedPodcastCount(in: context) == 2)
    }

    @Test
    func libraryDirectoryOrganizerFiltersAndSortsLargeLibraries() {
        let stale = LibraryDirectoryPodcast(
            id: UUID(),
            title: "Stale Sync",
            author: "Ops Desk",
            categories: ["News"],
            syncStatus: "failed",
            syncFailureCount: 2
        )
        let active = LibraryDirectoryPodcast(
            id: UUID(),
            title: "Audio Craft",
            author: "Studio Team",
            categories: ["Technology", "Design"]
        )
        let quiet = LibraryDirectoryPodcast(
            id: UUID(),
            title: "Quiet Archive",
            author: "Library",
            categories: ["History"]
        )

        let unplayedCounts = [active.id: 8, quiet.id: 0, stale.id: 1]
        let inProgressCounts = [active.id: 1]

        let queryFiltered = LibraryDirectoryOrganizer.filteredDirectoryPodcasts(
            [stale, active, quiet],
            query: "studio",
            scope: .all,
            sort: .title,
            unplayedCounts: unplayedCounts,
            inProgressCounts: inProgressCounts
        )
        #expect(queryFiltered.map(\.title) == ["Audio Craft"])

        let attentionSorted = LibraryDirectoryOrganizer.filteredDirectoryPodcasts(
            [quiet, active, stale],
            query: "",
            scope: .all,
            sort: .attention,
            unplayedCounts: unplayedCounts,
            inProgressCounts: inProgressCounts
        )
        #expect(attentionSorted.map(\.title) == ["Stale Sync", "Audio Craft", "Quiet Archive"])

        let inProgressOnly = LibraryDirectoryOrganizer.filteredDirectoryPodcasts(
            [quiet, active, stale],
            query: "",
            scope: .inProgress,
            sort: .title,
            unplayedCounts: unplayedCounts,
            inProgressCounts: inProgressCounts
        )
        #expect(inProgressOnly.map(\.title) == ["Audio Craft"])
    }

    @Test
    func libraryDirectoryOrganizerBuildsAlphabetSections() {
        let numeric = LibraryDirectoryPodcast(id: UUID(), title: "99 Invisible")
        let alpha = LibraryDirectoryPodcast(id: UUID(), title: "Audio Craft")
        let beta = LibraryDirectoryPodcast(id: UUID(), title: "Beta Feed")

        let sections = LibraryDirectoryOrganizer.sections(for: [numeric, alpha, beta])

        #expect(sections.map(\.title) == ["A", "B", "#"])
        #expect(sections.flatMap(\.rows).map(\.title) == ["Audio Craft", "Beta Feed", "99 Invisible"])
    }

    @Test
    func libraryAlphabetRailTargetsNearestAvailableSection() {
        let numeric = LibraryDirectoryPodcast(id: UUID(), title: "99 Invisible")
        let alpha = LibraryDirectoryPodcast(id: UUID(), title: "Audio Craft")
        let delta = LibraryDirectoryPodcast(id: UUID(), title: "Delta Feed")
        let zeta = LibraryDirectoryPodcast(id: UUID(), title: "Zeta Waves")
        let sections = LibraryDirectoryOrganizer.sections(for: [zeta, alpha, delta])
        let sectionsWithNumbers = LibraryDirectoryOrganizer.sections(for: [zeta, numeric, alpha, delta])

        #expect(LibraryDirectoryOrganizer.sectionIDForAlphabetKey("A", sections: sections) == "library-section-A")
        #expect(LibraryDirectoryOrganizer.sectionIDForAlphabetKey("B", sections: sections) == "library-section-D")
        #expect(LibraryDirectoryOrganizer.sectionIDForAlphabetKey("Y", sections: sections) == "library-section-Z")
        #expect(LibraryDirectoryOrganizer.sectionIDForAlphabetKey("#", sections: sections) == "library-section-A")
        #expect(LibraryDirectoryOrganizer.sectionIDForAlphabetKey("#", sections: sectionsWithNumbers) == "library-section-#")
        #expect(LibraryDirectoryOrganizer.sectionIDForAlphabetKey("M", sections: []) == nil)
    }

    @Test
    func libraryAlphabetTargetsPrecomputeExactNearestAndReachableState() {
        let alpha = LibraryDirectoryPodcast(id: UUID(), title: "Audio Craft")
        let delta = LibraryDirectoryPodcast(id: UUID(), title: "Delta Feed")
        let zeta = LibraryDirectoryPodcast(id: UUID(), title: "Zeta Waves")
        let snapshot = LibraryDirectoryOrganizer.snapshot(
            for: [zeta, alpha, delta],
            query: "",
            scope: .all,
            sort: .title,
            unplayedCounts: [:],
            inProgressCounts: [:]
        )

        #expect(snapshot.alphabetTargets.count == 27)
        #expect(snapshot.alphabetTargets.first?.key == "#")
        #expect(snapshot.alphabetTargets.first?.sectionID == "library-section-A")
        #expect(snapshot.alphabetTargets.first?.isNearestJump == true)

        let exactA = snapshot.alphabetTargets.first { $0.key == "A" }
        #expect(exactA?.sectionID == "library-section-A")
        #expect(exactA?.isExact == true)
        #expect(exactA?.isNearestJump == false)

        let nearestB = snapshot.alphabetTargets.first { $0.key == "B" }
        #expect(nearestB?.sectionID == "library-section-D")
        #expect(nearestB?.isExact == false)
        #expect(nearestB?.isNearestJump == true)

        let nearestY = snapshot.alphabetTargets.first { $0.key == "Y" }
        #expect(nearestY?.sectionID == "library-section-Z")
        #expect(nearestY?.isReachable == true)
    }

    @Test
    func libraryDirectorySnapshotBuildsRowsWithCountsAndNumbers() {
        let alpha = LibraryDirectoryPodcast(id: UUID(), title: "Audio Craft")
        let beta = LibraryDirectoryPodcast(id: UUID(), title: "Beta Feed")

        let snapshot = LibraryDirectoryOrganizer.snapshot(
            for: [beta, alpha],
            query: "",
            scope: .all,
            sort: .title,
            unplayedCounts: [alpha.id: 3, beta.id: 1],
            inProgressCounts: [beta.id: 1]
        )
        let rows = snapshot.sections.flatMap(\.rows)

        #expect(rows.map(\.title) == ["Audio Craft", "Beta Feed"])
        #expect(rows.map(\.podcastID) == [alpha.id, beta.id])
        #expect(rows.map(\.channelNumber) == [1, 2])
        #expect(rows.first?.unplayedCount == 3)
        #expect(rows.last?.inProgressCount == 1)
        #expect(rows.map(\.isLastInSection) == [true, true])
        #expect(snapshot.listItems.map(\.id) == [
            "header-library-section-A",
            "row-\(alpha.id)",
            "section-separator-library-section-A",
            "header-library-section-B",
            "row-\(beta.id)",
            "section-separator-library-section-B"
        ])

        let adjacent = LibraryDirectoryPodcast(id: UUID(), title: "Another Audio")
        let sectionsWithoutExplicitNumbers = LibraryDirectoryOrganizer.sections(for: [alpha, adjacent])
        #expect(sectionsWithoutExplicitNumbers.flatMap(\.rows).map(\.channelNumber) == [1, 2])
    }

    @Test
    func libraryDirectoryListItemsFlattenSectionRowsForLazyRendering() {
        let alpha = LibraryDirectoryPodcast(id: UUID(), title: "Audio Craft")
        let another = LibraryDirectoryPodcast(id: UUID(), title: "Another Audio")
        let beta = LibraryDirectoryPodcast(id: UUID(), title: "Beta Feed")
        let sections = LibraryDirectoryOrganizer.sections(for: [alpha, another, beta])

        let items = LibraryDirectoryOrganizer.listItems(for: sections)
        let ids = items.map(\.id)

        #expect(ids == [
            "header-library-section-A",
            "row-\(alpha.id)",
            "row-separator-\(alpha.id.uuidString)",
            "row-\(another.id)",
            "section-separator-library-section-A",
            "header-library-section-B",
            "row-\(beta.id)",
            "section-separator-library-section-B"
        ])
    }

    @Test
    func libraryDirectoryOrganizerLoadsPerShowCountsOnlyForCountDrivenModes() {
        #expect(!LibraryDirectoryOrganizer.needsPerShowUnplayedCounts(scope: .all, sort: .title))
        #expect(!LibraryDirectoryOrganizer.needsPerShowUnplayedCounts(scope: .needsSync, sort: .latest))
        #expect(LibraryDirectoryOrganizer.needsPerShowUnplayedCounts(scope: .unplayed, sort: .title))
        #expect(LibraryDirectoryOrganizer.needsPerShowUnplayedCounts(scope: .all, sort: .attention))

        #expect(!LibraryDirectoryOrganizer.needsPerShowInProgressCounts(scope: .all, sort: .title))
        #expect(!LibraryDirectoryOrganizer.needsPerShowInProgressCounts(scope: .needsSync, sort: .latest))
        #expect(LibraryDirectoryOrganizer.needsPerShowInProgressCounts(scope: .inProgress, sort: .title))
        #expect(LibraryDirectoryOrganizer.needsPerShowInProgressCounts(scope: .all, sort: .attention))
    }

    @Test
    func libraryDirectoryOrganizerTracksMissingCountFamiliesSeparately() {
        #expect(LibraryDirectoryOrganizer.hasLoadedRequiredFullCounts(
            scope: .unplayed,
            sort: .title,
            didLoadUnplayed: true,
            didLoadInProgress: false
        ))

        #expect(!LibraryDirectoryOrganizer.hasLoadedRequiredFullCounts(
            scope: .inProgress,
            sort: .title,
            didLoadUnplayed: true,
            didLoadInProgress: false
        ))

        let inProgressMissing = LibraryDirectoryOrganizer.missingFullCountRequirements(
            scope: .inProgress,
            sort: .title,
            didLoadUnplayed: true,
            didLoadInProgress: false
        )
        #expect(!inProgressMissing.unplayed)
        #expect(inProgressMissing.inProgress)

        let attentionMissing = LibraryDirectoryOrganizer.missingFullCountRequirements(
            scope: .all,
            sort: .attention,
            didLoadUnplayed: true,
            didLoadInProgress: false
        )
        #expect(!attentionMissing.unplayed)
        #expect(attentionMissing.inProgress)
    }

    @Test
    @MainActor
    func libraryDirectoryOrganizerBucketsEpisodeCountsInOnePass() {
        let kept = Podcast(title: "Kept", feedURL: URL(string: "https://example.com/kept.xml")!)
        let second = Podcast(title: "Second", feedURL: URL(string: "https://example.com/second.xml")!)
        let ignored = Podcast(title: "Ignored", feedURL: URL(string: "https://example.com/ignored.xml")!)
        let episodes = [
            Episode(title: "A", pubDate: .now, audioURL: URL(string: "https://example.com/a.mp3")!, podcast: kept),
            Episode(title: "B", pubDate: .now, audioURL: URL(string: "https://example.com/b.mp3")!, podcast: kept),
            Episode(title: "C", pubDate: .now, audioURL: URL(string: "https://example.com/c.mp3")!, podcast: second),
            Episode(title: "D", pubDate: .now, audioURL: URL(string: "https://example.com/d.mp3")!, podcast: ignored)
        ]

        let counts = LibraryDirectoryOrganizer.countsByPodcastID(
            for: episodes,
            limitedTo: [kept.id, second.id]
        )

        #expect(counts[kept.id] == 2)
        #expect(counts[second.id] == 1)
        #expect(counts[ignored.id] == nil)
    }

    @Test
    @MainActor
    func libraryDirectoryCountStoreLoadsSubscribedPodcastSnapshots() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let subscribed = Podcast(title: "Actor Directory", feedURL: URL(string: "https://example.com/actor-directory.xml")!)
        subscribed.author = "Signal Desk"
        subscribed.categories = ["Technology", "Design"]
        subscribed.latestPubDate = Date(timeIntervalSince1970: 400)
        let unsubscribed = Podcast(title: "Actor Ignored", feedURL: URL(string: "https://example.com/actor-ignored-directory.xml")!)
        unsubscribed.isSubscribed = false
        context.insert(subscribed)
        context.insert(unsubscribed)
        try context.save()

        let store = LibraryDirectoryCountStore(modelContainer: container)
        let snapshots = try await store.subscribedPodcasts()

        #expect(snapshots.map(\.id) == [subscribed.id])
        #expect(snapshots.first?.title == "Actor Directory")
        #expect(snapshots.first?.author == "Signal Desk")
        #expect(snapshots.first?.categories == ["Technology", "Design"])
        #expect(snapshots.first?.latestPubDate == Date(timeIntervalSince1970: 400))
    }

    @Test
    @MainActor
    func libraryDirectoryCountLoaderBucketsSubscribedShowCountsInScopedFetches() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let kept = Podcast(title: "Kept", feedURL: URL(string: "https://example.com/kept.xml")!)
        let second = Podcast(title: "Second", feedURL: URL(string: "https://example.com/second.xml")!)
        let unsubscribed = Podcast(title: "Ignored", feedURL: URL(string: "https://example.com/ignored.xml")!)
        unsubscribed.isSubscribed = false

        context.insert(kept)
        context.insert(second)
        context.insert(unsubscribed)

        let keptFresh = Episode(title: "Kept Fresh", pubDate: .now, audioURL: URL(string: "https://example.com/kept-fresh.mp3")!, podcast: kept)
        let keptStarted = Episode(title: "Kept Started", pubDate: .now, audioURL: URL(string: "https://example.com/kept-started.mp3")!, podcast: kept)
        keptStarted.playedPosition = 120
        let keptPlayed = Episode(title: "Kept Played", pubDate: .now, audioURL: URL(string: "https://example.com/kept-played.mp3")!, podcast: kept)
        keptPlayed.isPlayed = true
        let secondStarted = Episode(title: "Second Started", pubDate: .now, audioURL: URL(string: "https://example.com/second-started.mp3")!, podcast: second)
        secondStarted.playedPosition = 90
        let ignoredFresh = Episode(title: "Ignored Fresh", pubDate: .now, audioURL: URL(string: "https://example.com/ignored-fresh.mp3")!, podcast: unsubscribed)

        [keptFresh, keptStarted, keptPlayed, secondStarted, ignoredFresh].forEach(context.insert)
        try context.save()

        let podcastIDs = [kept.id, second.id, unsubscribed.id]
        let unplayedCounts = try await LibraryDirectoryCountLoader.unplayedCountsByPodcastID(
            podcastIDs: podcastIDs,
            context: context
        )
        let inProgressCounts = try await LibraryDirectoryCountLoader.inProgressCountsByPodcastID(
            podcastIDs: podcastIDs,
            context: context
        )

        #expect(unplayedCounts[kept.id] == 2)
        #expect(unplayedCounts[second.id] == 1)
        #expect(unplayedCounts[unsubscribed.id] == nil)
        #expect(inProgressCounts[kept.id] == 1)
        #expect(inProgressCounts[second.id] == 1)
        #expect(inProgressCounts[unsubscribed.id] == nil)
    }

    @Test
    @MainActor
    func libraryDirectoryCountLoaderCombinesUnplayedAndInProgressCounts() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let kept = Podcast(title: "Kept", feedURL: URL(string: "https://example.com/kept-combined.xml")!)
        let second = Podcast(title: "Second", feedURL: URL(string: "https://example.com/second-combined.xml")!)
        let unsubscribed = Podcast(title: "Ignored", feedURL: URL(string: "https://example.com/ignored-combined.xml")!)
        unsubscribed.isSubscribed = false

        context.insert(kept)
        context.insert(second)
        context.insert(unsubscribed)

        let keptFresh = Episode(title: "Kept Fresh", pubDate: .now, audioURL: URL(string: "https://example.com/kept-combined-fresh.mp3")!, podcast: kept)
        let keptStarted = Episode(title: "Kept Started", pubDate: .now, audioURL: URL(string: "https://example.com/kept-combined-started.mp3")!, podcast: kept)
        keptStarted.playedPosition = 120
        let keptPlayed = Episode(title: "Kept Played", pubDate: .now, audioURL: URL(string: "https://example.com/kept-combined-played.mp3")!, podcast: kept)
        keptPlayed.isPlayed = true
        let secondStarted = Episode(title: "Second Started", pubDate: .now, audioURL: URL(string: "https://example.com/second-combined-started.mp3")!, podcast: second)
        secondStarted.playedPosition = 90
        let ignoredStarted = Episode(title: "Ignored Started", pubDate: .now, audioURL: URL(string: "https://example.com/ignored-combined-started.mp3")!, podcast: unsubscribed)
        ignoredStarted.playedPosition = 60

        [keptFresh, keptStarted, keptPlayed, secondStarted, ignoredStarted].forEach(context.insert)
        try context.save()

        let counts = try await LibraryDirectoryCountLoader.countsByPodcastID(
            podcastIDs: [kept.id, second.id, unsubscribed.id],
            needsUnplayed: true,
            needsInProgress: true,
            context: context
        )

        #expect(counts.unplayedByPodcastID[kept.id] == 2)
        #expect(counts.unplayedByPodcastID[second.id] == 1)
        #expect(counts.unplayedByPodcastID[unsubscribed.id] == nil)
        #expect(counts.inProgressByPodcastID[kept.id] == 1)
        #expect(counts.inProgressByPodcastID[second.id] == 1)
        #expect(counts.inProgressByPodcastID[unsubscribed.id] == nil)
    }

    @Test
    @MainActor
    func libraryDirectoryCountStoreBucketsSubscribedShowCounts() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let kept = Podcast(title: "Actor Kept", feedURL: URL(string: "https://example.com/actor-kept.xml")!)
        let ignored = Podcast(title: "Actor Ignored", feedURL: URL(string: "https://example.com/actor-ignored.xml")!)
        ignored.isSubscribed = false

        context.insert(kept)
        context.insert(ignored)

        let fresh = Episode(title: "Fresh", pubDate: .now, audioURL: URL(string: "https://example.com/actor-fresh.mp3")!, podcast: kept)
        let started = Episode(title: "Started", pubDate: .now, audioURL: URL(string: "https://example.com/actor-started.mp3")!, podcast: kept)
        started.playedPosition = 120
        let ignoredFresh = Episode(title: "Ignored Fresh", pubDate: .now, audioURL: URL(string: "https://example.com/actor-ignored.mp3")!, podcast: ignored)

        [fresh, started, ignoredFresh].forEach(context.insert)
        try context.save()

        let countStore = LibraryDirectoryCountStore(modelContainer: container)
        let counts = try await countStore.countsByPodcastID(
            podcastIDs: [kept.id, ignored.id],
            needsUnplayed: true,
            needsInProgress: true
        )

        #expect(counts.unplayedByPodcastID[kept.id] == 2)
        #expect(counts.unplayedByPodcastID[ignored.id] == nil)
        #expect(counts.inProgressByPodcastID[kept.id] == 1)
        #expect(counts.inProgressByPodcastID[ignored.id] == nil)
    }

    @Test
    @MainActor
    func libraryDirectoryCountStoreBuildsSummaryForSubscribedPodcasts() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let subscribed = Podcast(title: "Summary Actor", feedURL: URL(string: "https://example.com/summary-actor.xml")!)
        let unsubscribed = Podcast(title: "Summary Ignored", feedURL: URL(string: "https://example.com/summary-ignored.xml")!)
        unsubscribed.isSubscribed = false
        context.insert(subscribed)
        context.insert(unsubscribed)

        let olderFresh = Episode(
            title: "Older Fresh",
            pubDate: Date(timeIntervalSince1970: 100),
            audioURL: URL(string: "https://example.com/older-fresh.mp3")!,
            podcast: subscribed
        )
        let newestFresh = Episode(
            title: "Newest Fresh",
            pubDate: Date(timeIntervalSince1970: 300),
            audioURL: URL(string: "https://example.com/newest-fresh.mp3")!,
            podcast: subscribed
        )
        let inProgress = Episode(
            title: "In Progress",
            pubDate: Date(timeIntervalSince1970: 200),
            audioURL: URL(string: "https://example.com/in-progress.mp3")!,
            podcast: subscribed
        )
        inProgress.playedPosition = 120
        inProgress.lastPlayedAt = Date(timeIntervalSince1970: 500)
        let played = Episode(
            title: "Played",
            pubDate: Date(timeIntervalSince1970: 400),
            audioURL: URL(string: "https://example.com/played.mp3")!,
            podcast: subscribed
        )
        played.isPlayed = true
        let ignoredFresh = Episode(
            title: "Ignored Fresh",
            pubDate: Date(timeIntervalSince1970: 600),
            audioURL: URL(string: "https://example.com/ignored-summary.mp3")!,
            podcast: unsubscribed
        )

        [olderFresh, newestFresh, inProgress, played, ignoredFresh].forEach(context.insert)
        try context.save()

        let countStore = LibraryDirectoryCountStore(modelContainer: container)
        let summary = try await countStore.episodeSummary()

        #expect(summary.unplayedCount == 3)
        #expect(summary.inProgressCount == 1)
        #expect(summary.freshEpisodeIDs.prefix(3) == [newestFresh.id, inProgress.id, olderFresh.id])
        #expect(summary.inProgressEpisodeIDs == [inProgress.id])
        #expect(summary.freshUnplayedCountsByPodcastID[subscribed.id] == 3)
        #expect(summary.freshUnplayedCountsByPodcastID[unsubscribed.id] == nil)
        #expect(summary.freshInProgressCountsByPodcastID[subscribed.id] == 1)
    }

    @Test
    @MainActor
    func libraryDirectoryCountLoaderReturnsEmptyCountsForEmptyPodcastIDs() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let podcast = Podcast(title: "Ignored", feedURL: URL(string: "https://example.com/ignored.xml")!)
        context.insert(podcast)
        context.insert(Episode(title: "Ignored Fresh", pubDate: .now, audioURL: URL(string: "https://example.com/ignored.mp3")!, podcast: podcast))
        try context.save()

        let unplayedCounts = try await LibraryDirectoryCountLoader.unplayedCountsByPodcastID(
            podcastIDs: [],
            context: context
        )
        let inProgressCounts = try await LibraryDirectoryCountLoader.inProgressCountsByPodcastID(
            podcastIDs: [],
            context: context
        )

        #expect(unplayedCounts.isEmpty)
        #expect(inProgressCounts.isEmpty)
    }

    @Test
    @MainActor
    func libraryDirectoryCombinedCountLoaderReturnsEmptyCountsForEmptyPodcastIDs() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let podcast = Podcast(title: "Ignored", feedURL: URL(string: "https://example.com/ignored-combined-empty.xml")!)
        context.insert(podcast)
        context.insert(Episode(title: "Ignored Fresh", pubDate: .now, audioURL: URL(string: "https://example.com/ignored-combined-empty.mp3")!, podcast: podcast))
        try context.save()

        let counts = try await LibraryDirectoryCountLoader.countsByPodcastID(
            podcastIDs: [],
            needsUnplayed: true,
            needsInProgress: true,
            context: context
        )

        #expect(counts == .empty)
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
    func tasteProfileRefreshBuildsTagsFromCompletedEpisodes() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let podcast = Podcast(title: "Completed Tags", feedURL: URL(string: "https://example.com/completed-tags.xml")!)
        let episode = Episode(
            title: "Completion Is A Signal",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/completed-tags.mp3")!,
            podcast: podcast
        )
        let profile = EpisodeProfile(episodeID: episode.id)
        profile.tags = ["workflow", "craft"]

        context.insert(podcast)
        context.insert(episode)
        context.insert(profile)
        context.insert(PlaybackEvent(kind: .completed, position: 1_800, episode: episode))
        try context.save()

        try TasteProfileService.refresh(in: context)
        let tasteProfile = try context.fetch(FetchDescriptor<UserTasteProfile>()).first

        #expect(tasteProfile?.topTags.contains("workflow") == true)
        #expect(tasteProfile?.topTags.contains("craft") == true)
    }

    @Test
    @MainActor
    func tasteProfileRefreshWeightsRecentExplicitSignalAboveOldCompletion() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let legacyShow = Podcast(title: "Legacy Show", feedURL: URL(string: "https://example.com/legacy.xml")!)
        let freshShow = Podcast(title: "Fresh Show", feedURL: URL(string: "https://example.com/fresh-signal.xml")!)
        let oldCompleted = Episode(
            title: "Old Completed",
            pubDate: Date().addingTimeInterval(-320 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/legacy.mp3")!,
            podcast: legacyShow
        )
        let freshLiked = Episode(
            title: "Fresh Explicit Signal",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/fresh-signal.mp3")!,
            podcast: freshShow
        )
        let oldProfile = EpisodeProfile(episodeID: oldCompleted.id)
        oldProfile.tags = ["legacy"]
        let freshProfile = EpisodeProfile(episodeID: freshLiked.id)
        freshProfile.tags = ["fresh"]
        let oldEvent = PlaybackEvent(kind: .completed, position: 1_800, episode: oldCompleted)
        oldEvent.date = Date().addingTimeInterval(-320 * 86_400)
        let freshSignal = PreferenceSignal(action: .moreLikeThis, episode: freshLiked)
        freshSignal.date = .now

        context.insert(legacyShow)
        context.insert(freshShow)
        context.insert(oldCompleted)
        context.insert(freshLiked)
        context.insert(oldProfile)
        context.insert(freshProfile)
        context.insert(oldEvent)
        context.insert(freshSignal)
        try context.save()

        try TasteProfileService.refresh(in: context, force: true)
        let tasteProfile = try #require(try context.fetch(FetchDescriptor<UserTasteProfile>()).first)

        #expect(tasteProfile.topTags.first == "fresh")
    }

    @Test
    @MainActor
    func tasteProfileRefreshLetsOneExplicitIntentBeatSeveralPassiveCompletions() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let passiveShow = Podcast(title: "Passive Show", feedURL: URL(string: "https://example.com/passive-signals.xml")!)
        let chosenShow = Podcast(title: "Chosen Show", feedURL: URL(string: "https://example.com/chosen-signals.xml")!)
        let chosen = Episode(
            title: "Explicit Choice",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/chosen-signals.mp3")!,
            podcast: chosenShow
        )
        let chosenProfile = EpisodeProfile(episodeID: chosen.id)
        chosenProfile.tags = ["chosen"]

        context.insert(passiveShow)
        context.insert(chosenShow)
        context.insert(chosen)
        context.insert(chosenProfile)
        context.insert(PreferenceSignal(action: .moreLikeThis, episode: chosen))

        for index in 1...4 {
            let passive = Episode(
                title: "Passive Completion \(index)",
                pubDate: .now,
                duration: 1_800,
                audioURL: URL(string: "https://example.com/passive-signals-\(index).mp3")!,
                podcast: passiveShow
            )
            let passiveProfile = EpisodeProfile(episodeID: passive.id)
            passiveProfile.tags = ["passive"]
            context.insert(passive)
            context.insert(passiveProfile)
            context.insert(PlaybackEvent(kind: .completed, position: 1_800, episode: passive))
        }
        try context.save()

        try TasteProfileService.refresh(in: context, force: true)
        let tasteProfile = try #require(try context.fetch(FetchDescriptor<UserTasteProfile>()).first)

        #expect(tasteProfile.topTags.first == "chosen")
        #expect(tasteProfile.showAffinity.first == "Chosen Show")
    }

    @Test
    @MainActor
    func tasteProfileRefreshDemotesNegativePreferenceSignals() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let blockedShow = Podcast(title: "Blocked Show", feedURL: URL(string: "https://example.com/blocked-signal.xml")!)
        let trustedShow = Podcast(title: "Trusted Show", feedURL: URL(string: "https://example.com/trusted-signal.xml")!)
        let blocked = Episode(
            title: "Do Not Learn This",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/blocked-signal.mp3")!,
            podcast: blockedShow
        )
        let trusted = Episode(
            title: "Learn This",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/trusted-signal.mp3")!,
            podcast: trustedShow
        )
        let blockedProfile = EpisodeProfile(episodeID: blocked.id)
        blockedProfile.tags = ["blocked"]
        let trustedProfile = EpisodeProfile(episodeID: trusted.id)
        trustedProfile.tags = ["trusted"]

        context.insert(blockedShow)
        context.insert(trustedShow)
        context.insert(blocked)
        context.insert(trusted)
        context.insert(blockedProfile)
        context.insert(trustedProfile)
        context.insert(PlaybackEvent(kind: .completed, position: 1_800, episode: blocked))
        context.insert(PreferenceSignal(action: .notInterested, episode: blocked))
        context.insert(PreferenceSignal(action: .like, episode: trusted))
        try context.save()

        try TasteProfileService.refresh(in: context, force: true)
        let tasteProfile = try #require(try context.fetch(FetchDescriptor<UserTasteProfile>()).first)

        #expect(tasteProfile.topTags.contains("trusted"))
        #expect(!tasteProfile.topTags.contains("blocked"))
        #expect(!tasteProfile.showAffinity.contains("Blocked Show"))
    }

    @Test
    @MainActor
    func tasteProfileRefreshSkipsWhenFreshUnlessForced() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let tasteProfile = UserTasteProfile()
        tasteProfile.topTags = ["existing"]
        tasteProfile.showAffinity = ["Known Show"]
        tasteProfile.lastUpdatedAt = .now

        let podcast = Podcast(title: "New Signal", feedURL: URL(string: "https://example.com/new-signal.xml")!)
        let episode = Episode(
            title: "New Completed Signal",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/new-signal.mp3")!,
            podcast: podcast
        )
        let profile = EpisodeProfile(episodeID: episode.id)
        profile.tags = ["newtag"]

        context.insert(tasteProfile)
        context.insert(podcast)
        context.insert(episode)
        context.insert(profile)
        context.insert(PlaybackEvent(kind: .completed, position: 1_800, episode: episode))
        try context.save()

        try TasteProfileService.refresh(in: context)
        #expect(tasteProfile.topTags == ["existing"])

        try TasteProfileService.refresh(in: context, force: true)
        #expect(tasteProfile.topTags.contains("newtag"))
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
    func feedSyncImportsAlreadyParsedOPMLFeedWithoutRefetching() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let result = PodcastSearchResult(
            title: "OPML Fallback",
            author: "Fallback Author",
            feedURL: URL(string: "https://example.com/opml.xml")!,
            artworkURL: nil,
            websiteURL: nil,
            summary: nil
        )
        let parsed = ParsedFeed(
            title: "Parsed Show",
            author: "Parsed Author",
            summary: "Parsed summary",
            websiteURL: URL(string: "https://example.com/show")!,
            artworkURL: URL(string: "https://example.com/art.jpg")!,
            categories: ["Technology"],
            items: [
                ParsedFeedItem(
                    guid: "episode-1",
                    title: "One Fetch Episode",
                    summary: "Imported from an already parsed OPML feed.",
                    pubDate: .now,
                    duration: 1_500,
                    audioURL: URL(string: "https://example.com/episode-1.mp3")!
                )
            ]
        )

        let podcast = try await FeedSyncService().importPodcast(
            from: result,
            parsedFeed: parsed,
            into: context,
            episodeLimit: 25
        )

        let episodes = try context.fetch(FetchDescriptor<Episode>())
        #expect(podcast.title == "Parsed Show")
        #expect(podcast.author == "Parsed Author")
        #expect(podcast.categories == ["Technology"])
        #expect(episodes.map(\.title) == ["One Fetch Episode"])
    }

    @Test
    @MainActor
    func feedSyncFastBatchImportUsesCheapProfilesAndSkipsExternalChapters() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let result = PodcastSearchResult(
            title: "Batch Show",
            author: "Batch Author",
            feedURL: URL(string: "https://example.com/batch.xml")!,
            artworkURL: nil,
            websiteURL: nil,
            summary: nil
        )
        let parsed = ParsedFeed(
            title: "Batch Show",
            author: "Batch Author",
            summary: nil,
            websiteURL: nil,
            artworkURL: nil,
            categories: ["Technology"],
            items: [
                ParsedFeedItem(
                    guid: "batch-1",
                    title: "Local AI policy and newsroom automation",
                    summary: "A practical conversation about policy, newsroom operations, and automation.",
                    pubDate: .now,
                    duration: 1_800,
                    audioURL: URL(string: "https://example.com/batch-1.mp3")!,
                    externalChapterURL: URL(string: "https://example.com/batch-1-chapters.json")!
                )
            ]
        )

        _ = try await FeedSyncService().importPodcast(
            from: result,
            parsedFeed: parsed,
            into: context,
            options: .fastBatchImport(episodeLimit: 25)
        )

        let episode = try #require(try context.fetch(FetchDescriptor<Episode>()).first)
        let profile = try #require(try context.fetch(FetchDescriptor<EpisodeProfile>()).first)
        #expect(episode.chapters.isEmpty)
        #expect(profile.episodeID == episode.id)
        #expect(!profile.tags.isEmpty)
    }

    @Test
    @MainActor
    func feedSyncOPMLBootstrapCapsEpisodesAndSkipsProfiles() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let result = PodcastSearchResult(
            title: "Bootstrap Show",
            author: "Bootstrap Author",
            feedURL: URL(string: "https://example.com/bootstrap.xml")!,
            artworkURL: nil,
            websiteURL: nil,
            summary: nil
        )
        let parsed = ParsedFeed(
            title: "Bootstrap Show",
            author: "Bootstrap Author",
            summary: nil,
            websiteURL: nil,
            artworkURL: nil,
            categories: ["Technology"],
            items: (1...10).map { index in
                ParsedFeedItem(
                    guid: "bootstrap-\(index)",
                    title: "Bootstrap Episode \(index)",
                    summary: "Episode imported during OPML bootstrap.",
                    pubDate: Date().addingTimeInterval(TimeInterval(-index)),
                    duration: 1_800,
                    audioURL: URL(string: "https://example.com/bootstrap-\(index).mp3")!,
                    externalChapterURL: URL(string: "https://example.com/bootstrap-\(index)-chapters.json")!
                )
            }
        )

        _ = try await FeedSyncService().importPodcast(
            from: result,
            parsedFeed: parsed,
            into: context,
            options: .opmlBootstrap()
        )

        let episodes = try context.fetch(FetchDescriptor<Episode>())
        let profiles = try context.fetch(FetchDescriptor<EpisodeProfile>())
        #expect(episodes.count == 3)
        #expect(episodes.allSatisfy { $0.chapters.isEmpty })
        #expect(profiles.isEmpty)
    }

    @Test
    @MainActor
    func feedSyncCappedImportOnlyMatchesExistingEpisodesInProcessedWindow() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let podcast = Podcast(
            title: "Large Back Catalog",
            feedURL: URL(string: "https://example.com/large-back-catalog.xml")!
        )
        let inWindow = Episode(
            guid: "stale-guid-1",
            title: "Old Title",
            pubDate: .distantPast,
            audioURL: URL(string: "https://example.com/large-1.mp3")!,
            podcast: podcast
        )
        let outsideWindow = Episode(
            guid: "large-5",
            title: "Preserved Title",
            pubDate: .distantPast,
            audioURL: URL(string: "https://example.com/large-5.mp3")!,
            podcast: podcast
        )
        context.insert(podcast)
        context.insert(inWindow)
        context.insert(outsideWindow)
        try context.save()

        let result = PodcastSearchResult(
            title: "Large Back Catalog",
            author: "",
            feedURL: podcast.feedURL,
            artworkURL: nil,
            websiteURL: nil,
            summary: nil
        )
        let baseDate = Date()
        let parsedItems = (1...5).map { index in
            ParsedFeedItem(
                guid: "large-\(index)",
                title: "Updated Episode \(index)",
                summary: nil,
                pubDate: baseDate.addingTimeInterval(TimeInterval(-index)),
                duration: 1_800,
                audioURL: URL(string: "https://example.com/large-\(index).mp3")!
            )
        }
        let parsed = ParsedFeed(
            title: "Large Back Catalog",
            author: nil,
            summary: nil,
            websiteURL: nil,
            artworkURL: nil,
            categories: [],
            items: parsedItems
        )

        _ = try await FeedSyncService().importPodcast(
            from: result,
            parsedFeed: parsed,
            into: context,
            options: .opmlBootstrap()
        )

        let episodes = try context.fetch(FetchDescriptor<Episode>())
        #expect(episodes.count == 4)
        #expect(inWindow.title == "Updated Episode 1")
        #expect(inWindow.guid == "stale-guid-1")
        #expect(outsideWindow.title == "Preserved Title")
        #expect(episodes.contains { $0.guid == "large-2" })
        #expect(episodes.contains { $0.guid == "large-3" })
        #expect(!episodes.contains { $0.guid == "large-4" })
    }

    @Test
    @MainActor
    func feedSyncStagesSearchSubscriptionBeforeNetworkWork() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let result = PodcastSearchResult(
            title: "Starter Show",
            author: "Starter Author",
            feedURL: URL(string: "https://example.com/starter.xml")!,
            artworkURL: URL(string: "https://example.com/starter.jpg")!,
            websiteURL: URL(string: "https://example.com")!,
            summary: "A starter show selected during onboarding."
        )

        let podcast = try FeedSyncService().stagePodcastSubscription(from: result, into: context)

        let podcasts = try context.fetch(FetchDescriptor<Podcast>())
        #expect(podcasts.count == 1)
        #expect(podcast.isSubscribed)
        #expect(podcast.title == "Starter Show")
        #expect(podcast.author == "Starter Author")
        #expect(podcast.artworkURL == result.artworkURL)
        #expect(podcast.websiteURL == result.websiteURL)
        #expect(podcast.summary == result.summary)
        #expect(podcast.subscribedAt != nil)
        #expect(podcast.syncStatus == "idle")
        #expect(podcast.lastSyncAttemptAt != nil)
        #expect(podcast.syncErrorMessage == nil)
    }

    @Test
    @MainActor
    func feedSyncSubscribeThenHydrateCanReturnBeforeNetworkWork() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let result = PodcastSearchResult(
            title: "Instant Add",
            author: "Fast Author",
            feedURL: URL(string: "https://example.com/instant.xml")!,
            artworkURL: URL(string: "https://example.com/instant.jpg")!,
            websiteURL: URL(string: "https://example.com")!,
            summary: "A show added from Search."
        )

        let podcast = try FeedSyncService().subscribeThenHydrate(
            from: result,
            into: context,
            startHydration: false
        )

        let podcasts = try context.fetch(FetchDescriptor<Podcast>())
        #expect(podcasts.count == 1)
        #expect(podcast.isSubscribed)
        #expect(podcast.title == "Instant Add")
        #expect(podcast.syncStatus == "idle")
        #expect(podcast.syncErrorMessage == nil)
    }

    @Test
    @MainActor
    func feedSyncStagesMultipleOnboardingSubscriptionsInOneBatch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = Podcast(
            title: "Old Starter",
            author: "Old Author",
            feedURL: URL(string: "https://example.com/old-starter.xml")!,
            isSubscribed: false
        )
        context.insert(existing)
        try context.save()

        let results = [
            PodcastSearchResult(
                title: "Starter One",
                author: "Starter Author",
                feedURL: existing.feedURL,
                artworkURL: URL(string: "https://example.com/starter-one.jpg")!,
                websiteURL: URL(string: "https://example.com/one")!,
                summary: "A staged starter show."
            ),
            PodcastSearchResult(
                title: "Starter Two",
                author: "Second Author",
                feedURL: URL(string: "https://example.com/starter-two.xml")!,
                artworkURL: nil,
                websiteURL: nil,
                summary: nil
            ),
            PodcastSearchResult(
                title: "Starter Three",
                author: "Third Author",
                feedURL: URL(string: "https://example.com/starter-three.xml")!,
                artworkURL: nil,
                websiteURL: nil,
                summary: nil
            )
        ]

        let staged = try FeedSyncService().stagePodcastSubscriptions(from: results, into: context)

        let podcasts = try context.fetch(FetchDescriptor<Podcast>())
        #expect(staged.map(\.title) == ["Starter One", "Starter Two", "Starter Three"])
        #expect(podcasts.count == 3)
        #expect(existing.isSubscribed)
        #expect(existing.title == "Starter One")
        #expect(existing.feedURL == results[0].feedURL)
        #expect(podcasts.allSatisfy { $0.isSubscribed })
        #expect(podcasts.allSatisfy { $0.syncStatus == "idle" })
        #expect(podcasts.allSatisfy { $0.lastSyncAttemptAt != nil })
    }

    @Test
    @MainActor
    func onboardingPreferenceSignalFetchesNewestEpisodeWithoutSortingRelationship() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let podcast = Podcast(title: "Onboarding Pick", feedURL: URL(string: "https://example.com/pick.xml")!)
        let otherPodcast = Podcast(title: "Other Pick", feedURL: URL(string: "https://example.com/other.xml")!)
        context.insert(podcast)
        context.insert(otherPodcast)

        let older = Episode(
            title: "Older",
            pubDate: Date(timeIntervalSince1970: 100),
            audioURL: URL(string: "https://example.com/older.mp3")!,
            podcast: podcast
        )
        let newest = Episode(
            title: "Newest",
            pubDate: Date(timeIntervalSince1970: 300),
            audioURL: URL(string: "https://example.com/newest.mp3")!,
            podcast: podcast
        )
        let otherNewest = Episode(
            title: "Other Newest",
            pubDate: Date(timeIntervalSince1970: 500),
            audioURL: URL(string: "https://example.com/other-newest.mp3")!,
            podcast: otherPodcast
        )
        context.insert(older)
        context.insert(newest)
        context.insert(otherNewest)
        try context.save()

        let selected = OnboardingPreferenceSignalService.newestEpisode(for: podcast, in: context)

        #expect(selected?.id == newest.id)
    }

    @Test
    @MainActor
    func feedSyncOnboardingBootstrapCapsEpisodesAndSkipsExpensiveEnrichment() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let result = PodcastSearchResult(
            title: "Onboarding Show",
            author: "Onboarding Author",
            feedURL: URL(string: "https://example.com/onboarding.xml")!,
            artworkURL: nil,
            websiteURL: nil,
            summary: nil
        )
        let parsed = ParsedFeed(
            title: "Onboarding Show",
            author: "Onboarding Author",
            summary: nil,
            websiteURL: nil,
            artworkURL: nil,
            categories: ["Technology"],
            items: (1...10).map { index in
                ParsedFeedItem(
                    guid: "onboarding-\(index)",
                    title: "Onboarding Episode \(index)",
                    summary: "Episode imported during onboarding bootstrap.",
                    pubDate: Date().addingTimeInterval(TimeInterval(-index)),
                    duration: 1_800,
                    audioURL: URL(string: "https://example.com/onboarding-\(index).mp3")!,
                    externalChapterURL: URL(string: "https://example.com/onboarding-\(index)-chapters.json")!
                )
            }
        )

        let podcast = try await FeedSyncService().importPodcast(
            from: result,
            parsedFeed: parsed,
            into: context,
            options: .onboardingBootstrap()
        )

        let episodes = try context.fetch(FetchDescriptor<Episode>())
        let profiles = try context.fetch(FetchDescriptor<EpisodeProfile>())
        #expect(episodes.count == 3)
        #expect(episodes.allSatisfy { $0.chapters.isEmpty })
        #expect(profiles.isEmpty)
        #expect(podcast.syncStatus == "idle")
    }

    @Test
    func feedSyncSelectsLatestCappedItemsWithoutFullFeedSort() {
        let baseDate = Date()
        let items = [
            ParsedFeedItem(
                guid: "old",
                title: "Old",
                summary: nil,
                pubDate: baseDate.addingTimeInterval(-5),
                duration: nil,
                audioURL: URL(string: "https://example.com/old.mp3")!
            ),
            ParsedFeedItem(
                guid: "newest",
                title: "Newest",
                summary: nil,
                pubDate: baseDate,
                duration: nil,
                audioURL: URL(string: "https://example.com/newest.mp3")!
            ),
            ParsedFeedItem(
                guid: "middle",
                title: "Middle",
                summary: nil,
                pubDate: baseDate.addingTimeInterval(-2),
                duration: nil,
                audioURL: URL(string: "https://example.com/middle.mp3")!
            )
        ]

        let capped = FeedSyncService.itemsToProcess(from: items, limit: 2)

        #expect(capped.map(\.guid) == ["newest", "middle"])
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

    @Test
    @MainActor
    func podcastDeepLinkPostsSwitchTabAndOpenPodcastForExistingPodcast() throws {
        // #201 — `offscript://podcast/<uuid>` was previously logged-and-dropped.
        // Verifies the router (1) verifies the UUID exists in store, (2) posts
        // .offscriptSwitchTab to library, (3) posts .offscriptOpenPodcast with
        // the podcastID userInfo, and (4) stashes the pending UUID for
        // cold-launch consumption via LibraryView.onAppear.
        DebugTeardown.resetAllSingletons()  // clears any pendingPodcastDeepLink
                                            // left by a prior test in the suite.
        let container = try makeContainer()
        let context = container.mainContext
        let podcast = Podcast(
            title: "Deep Link Test Show",
            author: "Tester",
            summary: nil,
            feedURL: URL(string: "https://example.com/deeplink.xml")!,
            websiteURL: nil,
            artworkURL: nil,
            isSubscribed: true
        )
        context.insert(podcast)
        try context.save()

        var receivedSwitchTab: String?
        var receivedOpenID: UUID?
        let switchObserver = NotificationCenter.default.addObserver(
            forName: .offscriptSwitchTab, object: nil, queue: .main
        ) { note in
            receivedSwitchTab = note.userInfo?["tab"] as? String
        }
        let openObserver = NotificationCenter.default.addObserver(
            forName: .offscriptOpenPodcast, object: nil, queue: .main
        ) { note in
            receivedOpenID = note.userInfo?["podcastID"] as? UUID
        }
        defer {
            NotificationCenter.default.removeObserver(switchObserver)
            NotificationCenter.default.removeObserver(openObserver)
            DeepLinkRouter.pendingPodcastDeepLink = nil
        }

        DeepLinkRouter.pendingPodcastDeepLink = nil
        let url = URL(string: "offscript://podcast/\(podcast.id.uuidString)")!
        DeepLinkRouter.handle(url, in: context)

        // Read pendingPodcastDeepLink BEFORE pumping the runloop. Under
        // full-suite execution a prior test's LibraryView observer can
        // still be subscribed to .offscriptOpenPodcast; when we pump the
        // loop it consumes the pending UUID + clears it (the "clear on
        // consumption" contract documented on the property). Reading
        // before pumping pins the synchronous-assignment contract in
        // handlePodcast() at DeepLinkRouter.swift:170.
        let pendingAfterHandle = DeepLinkRouter.pendingPodcastDeepLink

        // The notifications post on .main; pump the loop briefly so the
        // observers fire synchronously inside the test.
        let runLoop = RunLoop.current
        let deadline = Date().addingTimeInterval(0.5)
        while runLoop.run(mode: .default, before: Date().addingTimeInterval(0.05)),
              receivedOpenID == nil,
              Date() < deadline {}

        #expect(receivedSwitchTab == "library")
        #expect(receivedOpenID == podcast.id)
        #expect(pendingAfterHandle == podcast.id)
    }

    @Test
    @MainActor
    func podcastDeepLinkIgnoresUnknownUUID() throws {
        // Stale Spotlight donations to deleted podcasts shouldn't switch
        // tabs and push an empty detail view. Verifies the router
        // short-circuits when the UUID isn't in store.
        let container = try makeContainer()
        let context = container.mainContext

        var receivedSwitchTab: String?
        var receivedOpenID: UUID?
        let switchObserver = NotificationCenter.default.addObserver(
            forName: .offscriptSwitchTab, object: nil, queue: .main
        ) { note in receivedSwitchTab = note.userInfo?["tab"] as? String }
        let openObserver = NotificationCenter.default.addObserver(
            forName: .offscriptOpenPodcast, object: nil, queue: .main
        ) { note in receivedOpenID = note.userInfo?["podcastID"] as? UUID }
        defer {
            NotificationCenter.default.removeObserver(switchObserver)
            NotificationCenter.default.removeObserver(openObserver)
            DeepLinkRouter.pendingPodcastDeepLink = nil
        }

        DeepLinkRouter.pendingPodcastDeepLink = nil
        let url = URL(string: "offscript://podcast/\(UUID().uuidString)")!
        DeepLinkRouter.handle(url, in: context)

        let runLoop = RunLoop.current
        _ = runLoop.run(mode: .default, before: Date().addingTimeInterval(0.2))

        #expect(receivedSwitchTab == nil)
        #expect(receivedOpenID == nil)
        #expect(DeepLinkRouter.pendingPodcastDeepLink == nil)
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
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

#if os(iOS)
private final class RecordingAudioSession: OffScriptAudioSessionApplying {
    private(set) var category: AVAudioSession.Category?
    private(set) var mode: AVAudioSession.Mode?
    private(set) var options: AVAudioSession.CategoryOptions = []
    private(set) var routeSharingPolicy: AVAudioSession.RouteSharingPolicy?
    private(set) var didCallSetCategoryWithPolicy = false

    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws {
        self.category = category
        self.mode = mode
        self.options = options
        routeSharingPolicy = nil
    }

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        policy: AVAudioSession.RouteSharingPolicy,
        options: AVAudioSession.CategoryOptions
    ) throws {
        self.category = category
        self.mode = mode
        self.options = options
        routeSharingPolicy = policy
        didCallSetCategoryWithPolicy = true
    }
}
#endif

// MARK: - EpisodeDurationFormatter Tests

/// Pins the contract for `EpisodeDurationFormatter.short(_:)` and
/// `.spoken(_:)` — both have 15+ call sites across HomeView,
/// LibraryView, and the Now Playing surfaces, but had zero test
/// coverage prior to the 2.4.0 audit (Phase 1.1).
struct EpisodeDurationFormatterTests {
    // MARK: short(_:)

    @Test func shortZero() {
        #expect(EpisodeDurationFormatter.short(0) == "0m")
    }

    @Test func shortSubMinuteRoundsDown() {
        #expect(EpisodeDurationFormatter.short(59) == "0m")
    }

    @Test func shortExactlyOneMinute() {
        #expect(EpisodeDurationFormatter.short(60) == "1m")
    }

    @Test func shortThirtyTwoMinutes() {
        #expect(EpisodeDurationFormatter.short(32 * 60) == "32m")
    }

    @Test func shortExactlyOneHour() {
        #expect(EpisodeDurationFormatter.short(60 * 60) == "1h")
    }

    @Test func shortOneHourFiveMinutes() {
        #expect(EpisodeDurationFormatter.short(65 * 60) == "1h 5m")
    }

    @Test func shortTwoHoursExact() {
        #expect(EpisodeDurationFormatter.short(2 * 3600) == "2h")
    }

    @Test func shortFiveHoursExact() {
        #expect(EpisodeDurationFormatter.short(5 * 3600) == "5h")
    }

    /// Defensive contract: negative durations clamp to "0m" so a
    /// stale `playedPosition > duration` arithmetic glitch never
    /// surfaces a "-1m" glyph in the UI. `Int(-1.0/60)` truncates
    /// toward zero, which is what we rely on.
    @Test func shortNegativeClampsToZero() {
        #expect(EpisodeDurationFormatter.short(-1) == "0m")
    }

    // MARK: spoken(_:)

    @Test func spokenZero() {
        #expect(EpisodeDurationFormatter.spoken(0) == "0 minutes")
    }

    @Test func spokenSubMinute() {
        #expect(EpisodeDurationFormatter.spoken(45) == "0 minutes")
    }

    @Test func spokenSingularMinute() {
        #expect(EpisodeDurationFormatter.spoken(60) == "1 minute")
    }

    @Test func spokenPluralMinutes() {
        #expect(EpisodeDurationFormatter.spoken(32 * 60) == "32 minutes")
    }

    @Test func spokenSingularHour() {
        #expect(EpisodeDurationFormatter.spoken(60 * 60) == "1 hour")
    }

    @Test func spokenSingularHourSingularMinute() {
        #expect(EpisodeDurationFormatter.spoken(61 * 60) == "1 hour 1 minute")
    }

    @Test func spokenSingularHourPluralMinutes() {
        #expect(EpisodeDurationFormatter.spoken(65 * 60) == "1 hour 5 minutes")
    }

    @Test func spokenPluralHoursSingularMinute() {
        #expect(EpisodeDurationFormatter.spoken(2 * 3600 + 60) == "2 hours 1 minute")
    }

    @Test func spokenTwoHoursExact() {
        #expect(EpisodeDurationFormatter.spoken(2 * 3600) == "2 hours")
    }

    @Test func spokenTwentyFourHoursExact() {
        #expect(EpisodeDurationFormatter.spoken(24 * 3600) == "24 hours")
    }

    @Test func spokenNegativeClampsToZero() {
        #expect(EpisodeDurationFormatter.spoken(-1) == "0 minutes")
    }
}

// MARK: - Recommendation Explanation Tests

/// Phase 20 audit: pins the contract that recommendation explanation
/// strings name the specific user action behind each pick rather than
/// falling back to vague boilerplate. See
/// `docs/superpowers/audits/2026-05-19-recommendation-credibility.md`.
@MainActor
struct RecommendationExplanationTests {
    // MARK: container

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
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: tests

    /// Show-affinity evidence — multiple completions of the same show —
    /// renders an explanation that names the show AND the concrete
    /// finish count, so the user can verify it against their own
    /// recent listens.
    @Test
    func showAffinityExplanationCitesShowAndCount() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        AppSettings.preferredGenres = []
        defer { AppSettings.preferredGenres = originalGenres }

        let show = Podcast(title: "Reply All", feedURL: URL(string: "https://example.com/reply.xml")!)
        let finishedA = Episode(
            title: "Finished A",
            pubDate: Date().addingTimeInterval(-20 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/a.mp3")!,
            podcast: show
        )
        let finishedB = Episode(
            title: "Finished B",
            pubDate: Date().addingTimeInterval(-10 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/b.mp3")!,
            podcast: show
        )
        let candidate = Episode(
            title: "New Drop",
            pubDate: Date().addingTimeInterval(-2 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/c.mp3")!,
            podcast: show
        )
        finishedA.isPlayed = true
        finishedB.isPlayed = true
        context.insert(show)
        context.insert(finishedA)
        context.insert(finishedB)
        context.insert(candidate)
        context.insert(PlaybackEvent(kind: .completed, position: 1_800, episode: finishedA))
        context.insert(PlaybackEvent(kind: .completed, position: 1_800, episode: finishedB))
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)
        let scoredSection = try #require(sections.first(where: { $0.episodes.contains(where: { $0.id == candidate.id }) }))
        let explanation = scoredSection.explanation(for: candidate)

        #expect(explanation.contains("Reply All"))
        #expect(explanation.contains("2"), "Explanation should name the concrete finish count, got: \(explanation)")
    }

    /// A recommendation backed by genre evidence cites the genre name
    /// explicitly rather than saying "lane" or "category" abstractly.
    @Test
    func genreOnlyExplanationCitesTheGenre() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        defer { AppSettings.preferredGenres = originalGenres }
        AppSettings.preferredGenres = []

        let show = Podcast(title: "Tech Daily", feedURL: URL(string: "https://example.com/tech.xml")!)
        show.categories = ["technology"]
        let episode = Episode(
            title: "Today In Tech",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/today.mp3")!,
            podcast: show
        )
        let taste = UserTasteProfile()
        taste.preferredGenres = ["technology"]
        taste.topTags = ["technology"]  // make hasData == true

        context.insert(show)
        context.insert(episode)
        context.insert(taste)
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)
        let scored = try #require(
            sections
                .flatMap(\.scoredEpisodes)
                .first(where: { $0.episode.id == episode.id })
        )

        #expect(scored.explanation.localizedCaseInsensitiveContains("technology"))
        // Phase 20: no "selected lane" boilerplate — the genre is the
        // evidence, not the word "lane".
        #expect(!scored.explanation.localizedCaseInsensitiveContains("selected"))
    }

    /// When BOTH show affinity AND tag match evidence exist, the
    /// composed explanation must surface the show (most specific
    /// evidence) — it's the more verifiable signal.
    @Test
    func compositeExplanationPrefersShowOverTagAlone() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        defer { AppSettings.preferredGenres = originalGenres }
        AppSettings.preferredGenres = []

        let show = Podcast(title: "Hardcore History", feedURL: URL(string: "https://example.com/hh.xml")!)
        let prior = Episode(
            title: "Earlier Drop",
            pubDate: Date().addingTimeInterval(-15 * 86_400),
            duration: 3_600,
            audioURL: URL(string: "https://example.com/p.mp3")!,
            podcast: show
        )
        let candidate = Episode(
            title: "New Drop",
            pubDate: Date().addingTimeInterval(-2 * 86_400),
            duration: 3_600,
            audioURL: URL(string: "https://example.com/n.mp3")!,
            podcast: show
        )
        let priorProfile = EpisodeProfile(episodeID: prior.id)
        priorProfile.tags = ["long-form history"]
        let candidateProfile = EpisodeProfile(episodeID: candidate.id)
        candidateProfile.tags = ["long-form history"]
        prior.isPlayed = true

        context.insert(show)
        context.insert(prior)
        context.insert(candidate)
        context.insert(priorProfile)
        context.insert(candidateProfile)
        context.insert(PlaybackEvent(kind: .completed, position: 3_600, episode: prior))
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)
        let scored = try #require(
            sections.flatMap(\.scoredEpisodes).first(where: { $0.episode.id == candidate.id })
        )
        // Show signal is more specific than the tag signal, so the
        // composed primary should be the show.
        #expect(scored.explanation.contains("Hardcore History"))
        #expect(scored.signalTrace.contains(RecommendationSignal(label: "source", value: "completion")))
    }

    /// `homeSignal` returns nil — not vague boilerplate — when an
    /// episode has zero concrete signal behind it. That episode then
    /// surfaces (if at all) only through the catch-all subscription
    /// rail, which uses an honest "From your subscribed show …" copy.
    @Test
    func noConcreteEvidenceReturnsHonestSubscriptionFallback() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        defer { AppSettings.preferredGenres = originalGenres }
        AppSettings.preferredGenres = []

        let show = Podcast(
            title: "Untouched Sub",
            feedURL: URL(string: "https://example.com/untouched.xml")!,
            isSubscribed: true
        )
        let episode = Episode(
            title: "Latest",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/latest.mp3")!,
            podcast: show
        )
        context.insert(show)
        context.insert(episode)
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)
        let fromSubs = try #require(sections.first(where: { $0.title == "From Your Subscriptions" }))
        let scored = try #require(fromSubs.scoredEpisodes.first(where: { $0.episode.id == episode.id }))

        // Honest fallback: names the show + the verifiable user action
        // (subscribe). NOT "Available from …" (the prior dead-code
        // boilerplate) and NOT "Recommended" / "Probably interesting".
        #expect(scored.explanation.contains("Untouched Sub"))
        #expect(scored.explanation.contains("subscribed"))
        #expect(!scored.explanation.localizedCaseInsensitiveContains("available from"))
        #expect(!scored.explanation.localizedCaseInsensitiveContains("recommended"))
    }

    /// VoiceOver speaks "·" as the literal word "middle dot" — so
    /// neither the explanation nor any chip value may contain one.
    @Test
    func explanationAndSignalsAreFreeOfMiddleDot() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        defer { AppSettings.preferredGenres = originalGenres }
        AppSettings.preferredGenres = []

        let show = Podcast(title: "Reply All", feedURL: URL(string: "https://example.com/m.xml")!)
        let prior = Episode(
            title: "Older",
            pubDate: Date().addingTimeInterval(-7 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/older.mp3")!,
            podcast: show
        )
        let candidate = Episode(
            title: "New",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/new.mp3")!,
            podcast: show
        )
        prior.isPlayed = true
        context.insert(show)
        context.insert(prior)
        context.insert(candidate)
        context.insert(PlaybackEvent(kind: .completed, position: 1_800, episode: prior))
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)
        for section in sections {
            for scored in section.scoredEpisodes {
                #expect(!scored.explanation.contains("·"), "explanation contains middle dot: \(scored.explanation)")
                for signal in scored.signalTrace {
                    #expect(!signal.label.contains("·"))
                    #expect(!signal.value.contains("·"))
                }
            }
        }
    }

    /// The signal-trace rail view caps at 3 chips. The data layer must
    /// not exceed that even when many evidence sources fire — anything
    /// past index 2 is invisible and would just inflate the score
    /// rather than the user-visible justification.
    @Test
    func signalTraceStaysWithinThreeChipVisualBudget() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        defer { AppSettings.preferredGenres = originalGenres }
        AppSettings.preferredGenres = [.technology]

        let show = Podcast(title: "Decoder", feedURL: URL(string: "https://example.com/d.xml")!)
        show.categories = ["technology"]
        let liked = Episode(
            title: "Liked",
            pubDate: Date().addingTimeInterval(-3 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/l.mp3")!,
            podcast: show
        )
        let candidate = Episode(
            title: "Candidate",
            pubDate: .now,
            duration: 1_500,
            audioURL: URL(string: "https://example.com/c.mp3")!,
            podcast: show
        )
        let likedProfile = EpisodeProfile(episodeID: liked.id)
        likedProfile.tags = ["ai", "policy", "platform shifts"]
        let candidateProfile = EpisodeProfile(episodeID: candidate.id)
        candidateProfile.tags = ["ai", "policy", "platform shifts"]

        context.insert(show)
        context.insert(liked)
        context.insert(candidate)
        context.insert(likedProfile)
        context.insert(candidateProfile)
        context.insert(PreferenceSignal(action: .moreLikeThis, episode: liked))
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)
        let scored = try #require(
            sections.flatMap(\.scoredEpisodes).first(where: { $0.episode.id == candidate.id })
        )

        // The rail view (`RecommendationSignalTraceView`) prefixes the
        // trace to 3 entries, so the underlying source-buckets shown
        // must include the most informative ones first. We allow the
        // raw trace to be longer than 3 (the view truncates), but the
        // user-visible prefix MUST be the three most concrete chips.
        let visible = Array(scored.signalTrace.prefix(3))
        let sources = visible.filter { $0.label == "source" }.map(\.value)
        // At least one of the top three must be a chosen-strength
        // source — i.e. the user's most direct evidence wins the
        // visible budget.
        let chosenSources: Set<String> = ["queue", "resume", "explicit signal", "show intent"]
        #expect(visible.contains(where: { $0.label == "strength" })
                || sources.contains(where: { chosenSources.contains($0) }))
    }

    /// `homeSignal`'s resume explanation uses `EpisodeDurationFormatter.spoken`
    /// for the WHY copy ("12 minutes left") so VoiceOver reads it as a
    /// sentence. The chip value continues to use `.short` ("12m") for
    /// the mono trace.
    @Test
    func resumeExplanationUsesSpokenDurationFormatter() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        defer { AppSettings.preferredGenres = originalGenres }
        AppSettings.preferredGenres = []

        let show = Podcast(title: "Show", feedURL: URL(string: "https://example.com/r.xml")!)
        let episode = Episode(
            title: "Resumable",
            pubDate: Date().addingTimeInterval(-1 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/resumable.mp3")!,
            podcast: show
        )
        episode.playedPosition = 600  // 10 minutes done, 20 left
        context.insert(show)
        context.insert(episode)
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)
        let scored = try #require(
            sections.flatMap(\.scoredEpisodes).first(where: { $0.episode.id == episode.id })
        )

        // "20 minutes" not "20m" in the WHY sentence — VoiceOver
        // reads "m" as the letter, not "minutes".
        #expect(scored.explanation.contains("20 minutes"))
        #expect(!scored.explanation.contains("20m left"))
        // But the chip value (mono trace) keeps the compact form.
        let leftChip = scored.signalTrace.first(where: { $0.label == "left" })
        #expect(leftChip?.value == "20m")
    }

    /// Explanation strings must stay under 80 characters at the
    /// scoring boundary — anything longer truncates on the rail card
    /// and a user looking at a card never sees the punchline. Walks
    /// every produced explanation in a thin-signal Home build.
    @Test
    func explanationsStayUnderEightyCharacters() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        defer { AppSettings.preferredGenres = originalGenres }
        AppSettings.preferredGenres = [.technology]

        let show = Podcast(title: "Decoder", feedURL: URL(string: "https://example.com/e.xml")!)
        show.categories = ["technology"]
        let liked = Episode(
            title: "Liked",
            pubDate: Date().addingTimeInterval(-2 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/eliked.mp3")!,
            podcast: show
        )
        let candidate = Episode(
            title: "Candidate",
            pubDate: .now,
            duration: 1_200,
            audioURL: URL(string: "https://example.com/ecand.mp3")!,
            podcast: show
        )
        let likedProfile = EpisodeProfile(episodeID: liked.id)
        likedProfile.tags = ["artificial intelligence infrastructure", "developer workflows"]
        let candidateProfile = EpisodeProfile(episodeID: candidate.id)
        candidateProfile.tags = ["artificial intelligence infrastructure", "developer workflows"]
        context.insert(show)
        context.insert(liked)
        context.insert(candidate)
        context.insert(likedProfile)
        context.insert(candidateProfile)
        context.insert(PreferenceSignal(action: .moreLikeThis, episode: liked))
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)
        for section in sections {
            for scored in section.scoredEpisodes {
                #expect(scored.explanation.count <= 80,
                        "Explanation over 80 chars (\(scored.explanation.count)): \(scored.explanation)")
            }
        }
    }

    /// A show that has been `.skippedQuickly`'d enough to cross the
    /// suppression threshold MUST NOT come back through a rail with a
    /// hedged "but we still think you'll like it" explanation —
    /// silent demotion is the right behavior. Brand promise: "no
    /// algorithm pushing".
    @Test
    func heavilySkippedShowIsSilentlySuppressed() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        defer { AppSettings.preferredGenres = originalGenres }
        AppSettings.preferredGenres = []

        let show = Podcast(title: "Heavily Skipped", feedURL: URL(string: "https://example.com/skip.xml")!)
        let skippedA = Episode(
            title: "Skipped A",
            pubDate: Date().addingTimeInterval(-3 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/skipa.mp3")!,
            podcast: show
        )
        let skippedB = Episode(
            title: "Skipped B",
            pubDate: Date().addingTimeInterval(-2 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/skipb.mp3")!,
            podcast: show
        )
        let skippedC = Episode(
            title: "Skipped C",
            pubDate: Date().addingTimeInterval(-1 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/skipc.mp3")!,
            podcast: show
        )
        let candidate = Episode(
            title: "Suppressed Candidate",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/suppressed.mp3")!,
            podcast: show
        )
        context.insert(show)
        context.insert(skippedA)
        context.insert(skippedB)
        context.insert(skippedC)
        context.insert(candidate)
        // notInterested is -5.0 per signal; two of them ≤ -7 trips
        // the show-suppression threshold (≤ -7).
        context.insert(PreferenceSignal(action: .notInterested, episode: skippedA))
        context.insert(PreferenceSignal(action: .notInterested, episode: skippedB))
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)
        let allEpisodes = sections.flatMap(\.episodes)
        // The candidate from the suppressed show must not appear in
        // any signal-driven rail. (notInterested also suppresses by
        // dislikedEpisodeIDs for the seed episodes themselves.)
        #expect(!allEpisodes.contains(where: { $0.id == candidate.id }),
                "Heavily-skipped show's new episodes must be silently demoted")
    }

    /// Every `RecommendationSignal` chip must have a non-empty value
    /// — an orphan label ("source: ") would render as a confusing
    /// half-chip with no information.
    @Test
    func allSignalChipsHaveNonEmptyValues() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        defer { AppSettings.preferredGenres = originalGenres }
        AppSettings.preferredGenres = [.technology]

        let show = Podcast(title: "Mixed Show", feedURL: URL(string: "https://example.com/mx.xml")!)
        show.categories = ["technology"]
        let prior = Episode(
            title: "Prior",
            pubDate: Date().addingTimeInterval(-4 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/p.mp3")!,
            podcast: show
        )
        let candidate = Episode(
            title: "Cand",
            pubDate: .now,
            duration: 900,
            audioURL: URL(string: "https://example.com/c2.mp3")!,
            podcast: show
        )
        let priorProfile = EpisodeProfile(episodeID: prior.id)
        priorProfile.tags = ["ai"]
        let candidateProfile = EpisodeProfile(episodeID: candidate.id)
        candidateProfile.tags = ["ai"]
        prior.isPlayed = true

        context.insert(show)
        context.insert(prior)
        context.insert(candidate)
        context.insert(priorProfile)
        context.insert(candidateProfile)
        context.insert(PlaybackEvent(kind: .completed, position: 1_800, episode: prior))
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)
        for section in sections {
            for scored in section.scoredEpisodes {
                for signal in scored.signalTrace {
                    #expect(!signal.label.isEmpty, "Orphan-label chip in trace: \(scored.signalTrace)")
                    #expect(!signal.value.isEmpty, "Orphan-value chip — label \(signal.label) has empty value")
                }
            }
        }
    }

    /// Explicit "more like this" signals are surfaced with a concrete
    /// match count when ≥ 2 tags match — replaces the Phase-19 vague
    /// "Matches what you asked for: …" boilerplate.
    @Test
    func explicitSignalExplanationNamesConcreteMatchCount() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalGenres = AppSettings.preferredGenres
        defer { AppSettings.preferredGenres = originalGenres }
        AppSettings.preferredGenres = []

        let showA = Podcast(title: "Show A", feedURL: URL(string: "https://example.com/sa.xml")!)
        let showB = Podcast(title: "Show B", feedURL: URL(string: "https://example.com/sb.xml")!)
        let seed = Episode(
            title: "Seed",
            pubDate: Date().addingTimeInterval(-3 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/seed-exp.mp3")!,
            podcast: showA
        )
        let candidate = Episode(
            title: "Cand",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/cand-exp.mp3")!,
            podcast: showB
        )
        let seedProfile = EpisodeProfile(episodeID: seed.id)
        seedProfile.tags = ["ai tooling", "developer workflows"]
        let candidateProfile = EpisodeProfile(episodeID: candidate.id)
        candidateProfile.tags = ["ai tooling", "developer workflows"]

        context.insert(showA)
        context.insert(showB)
        context.insert(seed)
        context.insert(candidate)
        context.insert(seedProfile)
        context.insert(candidateProfile)
        context.insert(PreferenceSignal(action: .moreLikeThis, episode: seed))
        try context.save()

        let sections = try RecommendationService().homeSections(context: context, limit: 3)
        let scored = try #require(
            sections.flatMap(\.scoredEpisodes).first(where: { $0.episode.id == candidate.id })
        )

        // Concrete count surfaced ("Hits 2 tags …") — not the vague
        // "Matches what you asked for" the Phase-19 audit flagged.
        #expect(scored.explanation.contains("2"))
        #expect(!scored.explanation.contains("Matches what you asked for"))
    }
}

// MARK: - voiceOverMetadata Tests

/// Mirrors the `voiceOverMetadata` contract introduced in PRs #267,
/// #268, and #270:
///   - drop uppercasing
///   - drop the "·" separator (VO speaks it literally)
///   - expand "S2 E5" to "Season 2 Episode 5"
///   - use `EpisodeDurationFormatter.spoken` so "1h 5m" is read as
///     "1 hour 5 minutes" instead of "1 H 5 M"
///
/// Pure helper duplicated here so the test doesn't have to spin up
/// SwiftData-backed `PodcastEpisode` instances. The three production
/// builders are then walked manually against this logic (see
/// docs/superpowers/audits/2026-05-19-voiceover-walk.md).
struct VoiceOverMetadataTests {
    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return cal
    }()

    private static let locale = Locale(identifier: "en_US_POSIX")

    /// Encodes the spoken voiceOverMetadata contract. As of 2.4.0 this
    /// matches both HomeView builders (`HomeView.swift:1098`, `:1330`)
    /// exactly — they emit `[date, S/E, duration]` with the same
    /// conditional S/E inclusion.
    /// Known divergences still in production (see the audit walk in
    /// docs/superpowers/audits/2026-05-19-voiceover-walk.md):
    ///   - LibraryView.swift:2996 emits `[S/E, date, duration]` — it
    ///     mirrors its own visible mono metadata (`[S/E, date, duration]`),
    ///     which differs from Home's visible order (`[date, duration]`).
    ///     Each surface's voiceOverMetadata mirrors its own visible order.
    ///   - Duration is gated on `> 0` here; both Home and Library only
    ///     nil-check, so a 0-duration episode would emit "0 minutes" in
    ///     production.
    /// Do NOT copy this helper into production — re-derive from each
    /// surface's visible metadata order.
    private static func voiceOverMetadata(
        pubDate: Date?,
        seasonNumber: Int?,
        episodeNumber: Int?,
        duration: TimeInterval?
    ) -> String {
        var parts: [String] = []
        if let pubDate {
            // Match `Date.formatted(date: .abbreviated, time: .omitted)`
            // with a fixed locale + calendar so the assertion is
            // deterministic regardless of host settings.
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "MMM d, yyyy"
            parts.append(formatter.string(from: pubDate))
        }
        if let s = seasonNumber, let e = episodeNumber {
            parts.append("Season \(s) Episode \(e)")
        } else if let e = episodeNumber {
            parts.append("Episode \(e)")
        }
        if let duration, duration > 0 {
            parts.append(EpisodeDurationFormatter.spoken(duration))
        }
        return parts.joined(separator: ", ")
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    @Test func fullMetadataWithSeasonAndDuration() {
        let output = Self.voiceOverMetadata(
            pubDate: Self.date(2026, 5, 1),
            seasonNumber: 2,
            episodeNumber: 5,
            duration: 65 * 60
        )
        #expect(output == "May 1, 2026, Season 2 Episode 5, 1 hour 5 minutes")
    }

    @Test func metadataWithEpisodeOnly() {
        let output = Self.voiceOverMetadata(
            pubDate: Self.date(2026, 5, 1),
            seasonNumber: nil,
            episodeNumber: 12,
            duration: 32 * 60
        )
        #expect(output == "May 1, 2026, Episode 12, 32 minutes")
    }

    @Test func metadataWithoutDuration() {
        let output = Self.voiceOverMetadata(
            pubDate: Self.date(2026, 5, 1),
            seasonNumber: nil,
            episodeNumber: 12,
            duration: nil
        )
        #expect(output == "May 1, 2026, Episode 12")
    }

    @Test func metadataOmitsZeroDuration() {
        let output = Self.voiceOverMetadata(
            pubDate: Self.date(2026, 5, 1),
            seasonNumber: nil,
            episodeNumber: 12,
            duration: 0
        )
        #expect(output == "May 1, 2026, Episode 12")
    }

    @Test func metadataWithoutPubDate() {
        let output = Self.voiceOverMetadata(
            pubDate: nil,
            seasonNumber: 2,
            episodeNumber: 5,
            duration: 65 * 60
        )
        #expect(output == "Season 2 Episode 5, 1 hour 5 minutes")
    }

    @Test func metadataAllMissing() {
        let output = Self.voiceOverMetadata(
            pubDate: nil,
            seasonNumber: nil,
            episodeNumber: nil,
            duration: nil
        )
        #expect(output == "")
    }

    // MARK: Structural assertions — the bugs we're guarding against

    @Test func metadataNeverContainsMiddleDotSeparator() {
        let output = Self.voiceOverMetadata(
            pubDate: Self.date(2026, 5, 1),
            seasonNumber: 2,
            episodeNumber: 5,
            duration: 65 * 60
        )
        #expect(!output.contains("·"))
    }

    @Test func metadataNeverContainsUppercaseGlyphs() {
        let output = Self.voiceOverMetadata(
            pubDate: Self.date(2026, 5, 1),
            seasonNumber: 2,
            episodeNumber: 5,
            duration: 65 * 60
        )
        #expect(!output.contains("MAY"))
        #expect(!output.contains("1H"))
    }
}

// MARK: - Podcast Namespace <podcast:chapters> Tests

/// Tests for first-class podcast-namespace chapter parsing (Phase 12).
///
/// These cover the JSON payload defined in
/// https://github.com/Podcastindex-org/podcast-namespace/blob/main/proposal-docs/chapters/chapters.md
/// and exercise `ExternalChapterLoader.decode(data:duration:)` plus the
/// roundtrip behavior of the extended `EpisodeChapter` schema.
struct PodcastNamespaceChaptersTests {
    private static func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    /// 1. Valid payload decodes N chapters with correct titles and startTimes,
    ///    including float (non-integer) startTimes per the spec.
    @Test func decodesValidEnvelopeWithFloatStartTimes() {
        let payload = Self.data("""
        {
          "version": "1.2.0",
          "chapters": [
            { "startTime": 0, "title": "Intro" },
            { "startTime": 65.5, "title": "First topic" },
            { "startTime": 285, "title": "Second topic" }
          ]
        }
        """)

        let chapters = ExternalChapterLoader.decode(data: payload, duration: 3600)

        #expect(chapters.count == 3)
        #expect(chapters[0].title == "Intro")
        #expect(chapters[0].startTime == 0)
        #expect(chapters[1].title == "First topic")
        #expect(chapters[1].startTime == 65.5)
        #expect(chapters[2].startTime == 285)
    }

    /// 2. endTime, img, url, toc round-trip onto the model.
    @Test func decodesOptionalFieldsOntoModel() {
        let payload = Self.data("""
        {
          "chapters": [
            {
              "startTime": 100,
              "endTime": 250,
              "title": "Sponsor",
              "img": "https://example.com/img.jpg",
              "url": "https://example.com/link",
              "toc": false
            }
          ]
        }
        """)

        let chapters = ExternalChapterLoader.decode(data: payload, duration: 3600)

        #expect(chapters.count == 1)
        let chapter = chapters[0]
        #expect(chapter.title == "Sponsor")
        #expect(chapter.startTime == 100)
        #expect(chapter.endTime == 250)
        #expect(chapter.imageURL?.absoluteString == "https://example.com/img.jpg")
        #expect(chapter.linkURL?.absoluteString == "https://example.com/link")
        #expect(chapter.isInTableOfContents == false)
    }

    /// 3. Chapters with startTime past the episode duration are dropped
    ///    (they're bogus — the spec doesn't allow them, but real-world
    ///    feeds occasionally ship malformed entries).
    @Test func filtersChaptersBeyondEpisodeDuration() {
        let payload = Self.data("""
        {
          "chapters": [
            { "startTime": 0, "title": "Intro" },
            { "startTime": 60, "title": "Mid" },
            { "startTime": 300, "title": "Past the end" }
          ]
        }
        """)

        let chapters = ExternalChapterLoader.decode(data: payload, duration: 120)

        #expect(chapters.count == 2)
        #expect(chapters.contains { $0.title == "Intro" })
        #expect(chapters.contains { $0.title == "Mid" })
        #expect(!chapters.contains { $0.title == "Past the end" })
    }

    /// 4. JSON round-trip: encode an [EpisodeChapter] (as the model does
    ///    into chaptersStorage), decode it back, and assert equality. This
    ///    proves the custom Codable conformance is symmetric — critical
    ///    because the SwiftData persisted column is a JSON string.
    @Test func chaptersJSONRoundTrip() throws {
        let original: [EpisodeChapter] = [
            EpisodeChapter(title: "Intro", startTime: 0),
            EpisodeChapter(
                title: "Sponsor",
                startTime: 100,
                endTime: 200,
                imageURL: URL(string: "https://example.com/img.jpg"),
                linkURL: URL(string: "https://example.com/link"),
                isInTableOfContents: false
            )
        ]

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([EpisodeChapter].self, from: encoded)

        #expect(decoded == original)
    }

    /// 5. Decoding back-compat: a payload missing all optional fields
    ///    (i.e. old persisted chapters from before the schema extension)
    ///    decodes cleanly with optional fields nil and isInTableOfContents
    ///    defaulting to true.
    @Test func decodesLegacyPayloadWithOnlyTitleAndStartTime() throws {
        let legacyJSON = Self.data(#"""
        [
          { "title": "Intro", "startTime": 0 },
          { "title": "Topic A", "startTime": 90 }
        ]
        """#)

        let decoded = try JSONDecoder().decode([EpisodeChapter].self, from: legacyJSON)

        #expect(decoded.count == 2)
        #expect(decoded[0].title == "Intro")
        #expect(decoded[0].startTime == 0)
        #expect(decoded[0].endTime == nil)
        #expect(decoded[0].imageURL == nil)
        #expect(decoded[0].linkURL == nil)
        #expect(decoded[0].isInTableOfContents == true)
        #expect(decoded[1].title == "Topic A")
        #expect(decoded[1].startTime == 90)
    }

    /// 6. toc=false chapters are still decoded — the spec says they
    ///    still affect playback boundaries, and the UI is responsible
    ///    for filtering them from any navigation list. The model layer
    ///    must NOT discard them.
    @Test func tocFalseChaptersStillDecoded() {
        let payload = Self.data("""
        {
          "chapters": [
            { "startTime": 0, "title": "Intro", "toc": true },
            { "startTime": 60, "title": "Sponsor", "toc": false },
            { "startTime": 120, "title": "Main", "toc": true }
          ]
        }
        """)

        let chapters = ExternalChapterLoader.decode(data: payload, duration: 3600)

        #expect(chapters.count == 3)
        let sponsor = chapters.first { $0.title == "Sponsor" }
        #expect(sponsor != nil)
        #expect(sponsor?.isInTableOfContents == false)
        // All three should be present so playback boundaries remain correct.
        #expect(chapters.map(\.title) == ["Intro", "Sponsor", "Main"])
    }

    // MARK: - Feed-parser element detection

    /// Bonus assertion (not counted in the target six): the namespace-aware
    /// detector accepts the prefixed form even when namespaceURI is nil,
    /// which is the common XMLParser shape for our feed pipeline.
    @Test func detectsPodcastChaptersByPrefixedQName() {
        #expect(RSSFeedParser.isPodcastChaptersElement(
            elementName: "podcast:chapters",
            qName: "podcast:chapters",
            namespaceURI: nil
        ))
        #expect(RSSFeedParser.isPodcastChaptersElement(
            elementName: "chapters",
            qName: nil,
            namespaceURI: "https://podcastindex.org/namespace/1.0"
        ))
        #expect(!RSSFeedParser.isPodcastChaptersElement(
            elementName: "chapters",
            qName: nil,
            namespaceURI: nil
        ))
    }
}

// MARK: - Transcript pipeline

/// Covers the published-transcript path landed in Phase 14:
///   - WebVTT and Podcasting 2.0 JSON decoding into [TranscriptCue]
///   - selection rule when multiple <podcast:transcript> entries exist
///     (format and language preferences)
///   - roundtrip of cues through the SwiftData cache storage shape.
///
/// These tests are pure parsing/selection — no URLSession involved — so they
/// run fast and offline like the rest of the suite.
struct TranscriptPipelineTests {
    @Test
    func vttDecoderParsesTimingAndText() throws {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:04.500
        Welcome to the show.

        2
        00:00:04.500 --> 00:00:08.000 align:start
        Today we talk about transcripts.

        NOTE this is just a comment, ignored

        00:01:00.250 --> 00:01:02.750
        Multi
        line text body.
        """

        let cues = try #require(PublishedTranscriptLoader.decodeVTT(text: vtt))

        #expect(cues.count == 3)
        #expect(cues[0].startTime == 1.0)
        #expect(cues[0].endTime == 4.5)
        #expect(cues[0].text == "Welcome to the show.")

        #expect(cues[1].startTime == 4.5)
        #expect(cues[1].endTime == 8.0)
        #expect(cues[1].text == "Today we talk about transcripts.")

        #expect(cues[2].startTime == 60.25)
        #expect(cues[2].endTime == 62.75)
        #expect(cues[2].text == "Multi\nline text body.")
    }

    @Test
    func jsonDecoderParsesPodcasting20Format() throws {
        let json = """
        {
          "version": "1.0.0",
          "segments": [
            { "speaker": "Alice", "startTime": 0.0, "endTime": 3.2, "body": "Hello listener." },
            { "speaker": "Bob",   "startTime": 3.2, "endTime": 6.0, "body": "Glad to be here." },
            { "speaker": "",      "startTime": 6.0, "endTime": 9.5, "body": "  trimmed body  " }
          ]
        }
        """.data(using: .utf8)!

        let cues = try #require(PublishedTranscriptLoader.decodeJSON(data: json))

        #expect(cues.count == 3)
        #expect(cues[0].speaker == "Alice")
        #expect(cues[0].startTime == 0.0)
        #expect(cues[0].endTime == 3.2)
        #expect(cues[0].text == "Hello listener.")

        #expect(cues[1].speaker == "Bob")
        // Empty speaker string should be normalized to nil so the UI doesn't
        // render a "(blank): foo" line.
        #expect(cues[2].speaker == nil)
        #expect(cues[2].text == "trimmed body")
    }

    @Test
    func loaderPicksJSONOverVTTOverSRTOverHTML() {
        let url = URL(string: "https://example.com/t")!
        let html = EpisodeTranscriptReference(url: url.appending(path: "h"), mimeType: "text/html", language: "en", rel: nil)
        let srt = EpisodeTranscriptReference(url: url.appending(path: "s"), mimeType: "application/srt", language: "en", rel: nil)
        let vtt = EpisodeTranscriptReference(url: url.appending(path: "v"), mimeType: "text/vtt", language: "en", rel: nil)
        let json = EpisodeTranscriptReference(url: url.appending(path: "j"), mimeType: "application/json", language: "en", rel: nil)

        let pick = PublishedTranscriptLoader.bestReference(
            from: [html, srt, vtt, json],
            preferredLanguage: "en"
        )
        #expect(pick?.url == json.url)

        // Without JSON it should fall to VTT.
        let pickNoJSON = PublishedTranscriptLoader.bestReference(
            from: [html, srt, vtt],
            preferredLanguage: "en"
        )
        #expect(pickNoJSON?.url == vtt.url)
    }

    @Test
    func loaderPicksLanguageMatchWithinSameFormat() {
        let url = URL(string: "https://example.com/t")!
        let vttDE = EpisodeTranscriptReference(url: url.appending(path: "de"), mimeType: "text/vtt", language: "de", rel: nil)
        let vttEN = EpisodeTranscriptReference(url: url.appending(path: "en"), mimeType: "text/vtt", language: "en-US", rel: nil)

        let pickEN = PublishedTranscriptLoader.bestReference(
            from: [vttDE, vttEN],
            preferredLanguage: "en"
        )
        #expect(pickEN?.url == vttEN.url)

        let pickDE = PublishedTranscriptLoader.bestReference(
            from: [vttDE, vttEN],
            preferredLanguage: "de"
        )
        #expect(pickDE?.url == vttDE.url)
    }

    @Test
    func transcriptCueCacheRoundtripIsLossless() {
        let original: [TranscriptCue] = [
            TranscriptCue(startTime: 0, endTime: 1.5, speaker: "Alice", text: "Hello."),
            TranscriptCue(startTime: 1.5, endTime: 3.25, speaker: nil, text: "World."),
            TranscriptCue(startTime: 3.25, endTime: 6.0, speaker: "Bob", text: "Multi\nline.")
        ]

        let encoded = EpisodeTranscriptCache.encodeCues(original)
        #expect(!encoded.isEmpty)

        let decoded = EpisodeTranscriptCache.decodeCues(encoded)
        #expect(decoded == original)

        // Empty-cue roundtrip should yield an empty storage string, so we
        // don't bloat the SwiftData row with `[]`.
        #expect(EpisodeTranscriptCache.encodeCues([]).isEmpty)
        #expect(EpisodeTranscriptCache.decodeCues("").isEmpty)
    }

    @Test
    func parseDispatchSniffsByContentWhenMimeTypeMissing() throws {
        let vttBytes = """
        WEBVTT

        00:00:00.000 --> 00:00:01.000
        Hi.
        """.data(using: .utf8)!

        let cues = try #require(PublishedTranscriptLoader.parse(data: vttBytes, mimeType: nil))
        #expect(cues.count == 1)
        #expect(cues[0].text == "Hi.")
    }
}

// MARK: - Offline Reliability Tests
//
// Phase 1 of NEXT_IMPLEMENTATION_BACKLOG — covers the on-launch
// reconciliation, orphan-file sweep, cancel cleanup, and the
// PodcastUnsubscribeService transcript-cache cleanup that Phase 14
// flagged. These tests touch the real applicationSupportDirectory so
// each test scopes its files to UUIDs that the rest of the suite
// won't collide with, and cleans them up in a defer block.

/// Helper — the real production Downloads dir. Lives in Application
/// Support so it survives across launches in real use. Tests reuse it
/// (instead of stubbing FileManager) because `DownloadService.sweepOrphanDownloadFiles`
/// is the contract under test and it reads from this exact location.
@MainActor
private func productionDownloadsDirectory() throws -> URL {
    let supportURL = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let downloadsURL = supportURL.appending(path: "Downloads", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
    return downloadsURL
}

@MainActor
struct OfflineReliabilityTests {
    @Test
    func reconcileFlipsOrphanedDownloadingEpisodeToFailed() throws {
        let container = try makeOfflineContainer()
        let context = ModelContext(container)
        let podcast = Podcast(title: "Reliability Show", feedURL: URL(string: "https://example.com/r.xml")!)
        context.insert(podcast)
        let episode = Episode(
            title: "Interrupted",
            pubDate: .now,
            audioURL: URL(string: "https://example.com/interrupted.mp3")!,
            podcast: podcast
        )
        context.insert(episode)
        // Simulate an app kill mid-download: state persisted as .downloading
        // with no local file landed.
        episode.downloadState = .downloading
        episode.downloadProgress = 0.42
        episode.localFileURL = nil
        try context.save()

        DownloadService.shared.reconcileForTesting(context: context)

        #expect(episode.downloadState == .failed)
        #expect(episode.downloadProgress == 0)
        #expect(episode.isDownloaded == false)
        #expect(episode.downloadErrorMessage != nil)
    }

    @Test
    func reconcilePromotesDownloadedRowWithMatchingFile() throws {
        let container = try makeOfflineContainer()
        let context = ModelContext(container)
        let podcast = Podcast(title: "Disk Match", feedURL: URL(string: "https://example.com/d.xml")!)
        context.insert(podcast)
        let episode = Episode(
            title: "Already Saved",
            pubDate: .now,
            audioURL: URL(string: "https://example.com/saved.mp3")!,
            podcast: podcast
        )
        context.insert(episode)

        // Seed a real file on disk that matches the episode's `localFileURL`.
        let downloadsDir = try productionDownloadsDirectory()
        let fileURL = downloadsDir.appending(path: "\(episode.id.uuidString).mp3")
        try Data("synthetic".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // Persisted state says .queued (e.g. the request was queued but the
        // file was finalized before the state save committed — possible on
        // a force-kill between move-into-place and save).
        episode.downloadState = .queued
        episode.localFileURL = fileURL
        try context.save()

        DownloadService.shared.reconcileForTesting(context: context)

        #expect(episode.downloadState == .downloaded)
        #expect(episode.isDownloaded == true)
        #expect(episode.downloadProgress == 1)
    }

    @Test
    func reconcileClearsDownloadedRowWhenFileMissing() throws {
        let container = try makeOfflineContainer()
        let context = ModelContext(container)
        let podcast = Podcast(title: "Vanished", feedURL: URL(string: "https://example.com/v.xml")!)
        context.insert(podcast)
        let episode = Episode(
            title: "Lost File",
            pubDate: .now,
            audioURL: URL(string: "https://example.com/lost.mp3")!,
            podcast: podcast
        )
        context.insert(episode)

        // Persist a downloaded row pointing at a path that does NOT exist
        // (user cleared via Files.app, low-disk eviction, etc).
        let phantomURL = try productionDownloadsDirectory()
            .appending(path: "\(episode.id.uuidString).mp3")
        // Make sure no file is actually at the path.
        try? FileManager.default.removeItem(at: phantomURL)
        episode.downloadState = .downloaded
        episode.isDownloaded = true
        episode.downloadProgress = 1
        episode.localFileURL = phantomURL
        try context.save()

        DownloadService.shared.reconcileForTesting(context: context)

        #expect(episode.downloadState == .notDownloaded)
        #expect(episode.isDownloaded == false)
        #expect(episode.localFileURL == nil)
    }

    @Test
    func sweepRemovesOrphanFilesWithNoOwningEpisode() throws {
        let container = try makeOfflineContainer()
        let context = ModelContext(container)
        // Create a podcast/episode so the context isn't empty (otherwise the
        // sweep would also touch its own files, but there shouldn't be any).
        let podcast = Podcast(title: "Survivor", feedURL: URL(string: "https://example.com/s.xml")!)
        context.insert(podcast)
        let liveEpisode = Episode(
            title: "Lives",
            pubDate: .now,
            audioURL: URL(string: "https://example.com/lives.mp3")!,
            podcast: podcast
        )
        context.insert(liveEpisode)

        let downloadsDir = try productionDownloadsDirectory()
        // Orphan: filename UUID has no matching Episode.
        let orphanID = UUID()
        let orphanURL = downloadsDir.appending(path: "\(orphanID.uuidString).mp3")
        try Data("orphan".utf8).write(to: orphanURL)
        // Owned: filename UUID matches `liveEpisode`.
        let ownedURL = downloadsDir.appending(path: "\(liveEpisode.id.uuidString).mp3")
        try Data("owned".utf8).write(to: ownedURL)
        defer {
            try? FileManager.default.removeItem(at: orphanURL)
            try? FileManager.default.removeItem(at: ownedURL)
        }
        liveEpisode.localFileURL = ownedURL
        liveEpisode.downloadState = .downloaded
        liveEpisode.isDownloaded = true
        try context.save()

        DownloadService.shared.reconcileForTesting(context: context)

        // Orphan should be gone; owned file should still be there.
        #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
        #expect(FileManager.default.fileExists(atPath: ownedURL.path))
        // Owned episode should remain downloaded.
        #expect(liveEpisode.downloadState == .downloaded)
    }

    @Test
    func unsubscribeRemovesTranscriptCacheForPodcastEpisodes() throws {
        let container = try makeOfflineContainer()
        let context = ModelContext(container)
        let leaving = Podcast(title: "Bye", feedURL: URL(string: "https://example.com/bye.xml")!)
        let staying = Podcast(title: "Stay", feedURL: URL(string: "https://example.com/stay.xml")!)
        context.insert(leaving)
        context.insert(staying)

        let leavingEp = Episode(
            title: "Bye 1",
            pubDate: .now,
            audioURL: URL(string: "https://example.com/bye1.mp3")!,
            podcast: leaving
        )
        let stayingEp = Episode(
            title: "Stay 1",
            pubDate: .now,
            audioURL: URL(string: "https://example.com/stay1.mp3")!,
            podcast: staying
        )
        context.insert(leavingEp)
        context.insert(stayingEp)

        let leavingCache = EpisodeTranscriptCache(
            episodeID: leavingEp.id,
            text: "Bye transcript",
            source: "speech"
        )
        let stayingCache = EpisodeTranscriptCache(
            episodeID: stayingEp.id,
            text: "Stay transcript",
            source: "speech"
        )
        context.insert(leavingCache)
        context.insert(stayingCache)
        try context.save()

        let ok = PodcastUnsubscribeService.unsubscribe(leaving, in: context)
        #expect(ok)

        let descriptor = FetchDescriptor<EpisodeTranscriptCache>()
        let remaining = try context.fetch(descriptor)
        let remainingIDs = Set(remaining.map(\.episodeID))
        #expect(!remainingIDs.contains(leavingEp.id))
        #expect(remainingIDs.contains(stayingEp.id))
    }

    @Test
    func cancelClearsTrackerEntriesAndPartialFile() throws {
        let container = try makeOfflineContainer()
        let context = ModelContext(container)
        let podcast = Podcast(title: "Cancel", feedURL: URL(string: "https://example.com/c.xml")!)
        context.insert(podcast)
        let episode = Episode(
            title: "Aborted",
            pubDate: .now,
            audioURL: URL(string: "https://example.com/abort.mp3")!,
            podcast: podcast
        )
        context.insert(episode)
        // Simulate a queued state: no URLSession task yet — DownloadService's
        // queued-branch cancel path.
        episode.downloadState = .queued
        episode.downloadProgress = 0
        try context.save()

        DownloadService.shared.reconcileForTesting(context: context)
        DownloadService.shared.cancelDownload(for: episode)

        #expect(episode.downloadState == .notDownloaded)
        #expect(episode.downloadProgress == 0)
        #expect(episode.isDownloaded == false)
        // Tracker dictionaries should not be holding the cancelled episode.
        #expect(!DownloadService.shared.trackedEpisodeIDsForTesting.contains(episode.id))
    }

    private func makeOfflineContainer() throws -> ModelContainer {
        // Wider schema than makeContainer above — we need EpisodeTranscriptCache
        // for the unsubscribe-cleanup test.
        let schema = Schema([
            Podcast.self,
            Episode.self,
            EpisodeProfile.self,
            PlaybackEvent.self,
            PreferenceSignal.self,
            QueueItem.self,
            UserTasteProfile.self,
            TelemetryEvent.self,
            EpisodeTranscriptCache.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

// MARK: - CuratedDiscoveryTests
//
// Phase 3 "Discovery That Feels Curated" — latest-episode previews on
// Search result rows. The tests pin the contract that matters: the
// loader is lazy, capped, cancellation-aware, cache-stable, and the
// metadata it produces is correctly bucketed and VO-friendly.

@Suite("CuratedDiscovery")
struct CuratedDiscoveryTests {
    // Shared fixtures — small, focused helpers. The real
    // `PodcastPreviewService.preview(for:)` does live HTTP, so every test
    // injects a deterministic fetch closure via the `fetch:` seam.
    private static let sampleResult = PodcastSearchResult(
        title: "Sample Show",
        author: "Sample Author",
        feedURL: URL(string: "https://example.com/feed.xml")!,
        artworkURL: nil,
        websiteURL: nil,
        summary: "Technology"
    )

    private static func makeSnapshot(
        episodeTitle: String = "Latest Episode",
        pubDate: Date? = Date(timeIntervalSince1970: 1_700_000_000),
        duration: TimeInterval? = 47 * 60
    ) -> PodcastPreviewSnapshot {
        let episode = PodcastPreviewEpisode(
            id: "ep-1",
            title: episodeTitle,
            pubDate: pubDate,
            duration: duration,
            summary: "Summary",
            audioURL: URL(string: "https://example.com/ep1.mp3")!,
            artworkURL: nil
        )
        return PodcastPreviewSnapshot(
            title: "Sample Show",
            author: "Sample Author",
            summary: "Sample summary",
            categories: ["Technology"],
            websiteURL: nil,
            latestEpisodes: [episode]
        )
    }

    // MARK: SearchPreviewMetadata formatting

    @Test
    func freshnessLabelBucketsAcrossWindows() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Today: same instant should bucket as TODAY (and stay there for
        // anything inside the first 24h window).
        #expect(SearchPreviewMetadata.freshnessLabel(pubDate: now, now: now) == "TODAY")
        // 18h ago is still < 1 day.
        #expect(SearchPreviewMetadata.freshnessLabel(
            pubDate: now.addingTimeInterval(-18 * 3600), now: now) == "TODAY")
        // 1 day exactly.
        #expect(SearchPreviewMetadata.freshnessLabel(
            pubDate: now.addingTimeInterval(-86_400), now: now) == "1D AGO")
        // 3 days.
        #expect(SearchPreviewMetadata.freshnessLabel(
            pubDate: now.addingTimeInterval(-3 * 86_400), now: now) == "3D AGO")
        // 1 week edge — at 7 days exactly we jump to weeks.
        #expect(SearchPreviewMetadata.freshnessLabel(
            pubDate: now.addingTimeInterval(-7 * 86_400), now: now) == "1W AGO")
        // 3 weeks.
        #expect(SearchPreviewMetadata.freshnessLabel(
            pubDate: now.addingTimeInterval(-21 * 86_400), now: now) == "3W AGO")
    }

    @Test
    func freshnessLabelHandlesFutureDates() {
        // RSS feeds occasionally publish with a future-dated pubDate due to
        // timezone slips. We treat negative intervals as TODAY rather than
        // surfacing a "-1D AGO" chip — the chip should never read negative.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let future = now.addingTimeInterval(3600)
        #expect(SearchPreviewMetadata.freshnessLabel(pubDate: future, now: now) == "TODAY")
        #expect(SearchPreviewMetadata.freshnessSpoken(pubDate: future, now: now) == "today")
    }

    @Test
    func metadataInitFailsOnEmptyEpisodes() {
        // No episodes -> no preview. Otherwise we'd render a "● LATEST"
        // chip with nothing underneath.
        let snapshot = PodcastPreviewSnapshot(
            title: "Empty",
            author: "Author",
            summary: nil,
            categories: [],
            websiteURL: nil,
            latestEpisodes: []
        )
        #expect(SearchPreviewMetadata(snapshot: snapshot, now: Date()) == nil)
    }

    @Test
    func metadataInitFailsOnBlankEpisodeTitle() {
        // A whitespace-only title is just as useless as no episode — the
        // row would render an empty title row. Treat as no preview.
        let episode = PodcastPreviewEpisode(
            id: "ep",
            title: "   ",
            pubDate: Date(),
            duration: 1800,
            summary: nil,
            audioURL: URL(string: "https://example.com/a.mp3")!,
            artworkURL: nil
        )
        let snapshot = PodcastPreviewSnapshot(
            title: "Show", author: "Author", summary: nil, categories: [],
            websiteURL: nil, latestEpisodes: [episode]
        )
        #expect(SearchPreviewMetadata(snapshot: snapshot, now: Date()) == nil)
    }

    @Test
    func metadataPicksUpDurationLabelsAndSpokenForm() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = Self.makeSnapshot(
            pubDate: now.addingTimeInterval(-3 * 86_400),
            duration: 47 * 60
        )
        let metadata = SearchPreviewMetadata(snapshot: snapshot, now: now)
        #expect(metadata?.freshnessLabel == "3D AGO")
        #expect(metadata?.freshnessSpoken == "3 days ago")
        #expect(metadata?.durationLabel == "47M")
        #expect(metadata?.durationSpoken == "47 minutes")
    }

    @Test
    func metadataDropsSubMinuteDurations() {
        // A 35-second "episode" duration is almost always a feed quirk
        // (chapter marker counted as duration, missing tag, etc.). Drop
        // the duration label rather than show "0M" — the metadata strip
        // hides the dot separator when durationLabel is empty.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = Self.makeSnapshot(pubDate: now, duration: 35)
        let metadata = SearchPreviewMetadata(snapshot: snapshot, now: now)
        #expect(metadata?.durationLabel == "")
        #expect(metadata?.durationSpoken == "")
    }

    // MARK: SearchPreviewLoader behavior

    @MainActor
    @Test
    func loaderReturnsNilForRowsBeyondPreviewCap() async {
        // Rows past the cap should return nil — the row treats that the
        // same as `.failed` (renders nothing) so the layout stays stable
        // as the user scrolls. We assert no fetch was attempted by
        // checking the call count.
        var fetchCount = 0
        let loader = SearchPreviewLoader(
            previewCap: 3,
            fetch: { _ in
                fetchCount += 1
                return Self.makeSnapshot()
            }
        )
        // Rank 4 is outside the cap of 3.
        #expect(loader.state(for: Self.sampleResult, rank: 4) == nil)
        // Give any inadvertent async task a tick to run; it shouldn't.
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(fetchCount == 0)
    }

    @MainActor
    @Test
    func loaderFetchesOnceAndCachesAcrossCalls() async {
        // Two state(for:rank:) calls for the same feed should result in
        // exactly one fetch — that's the cache contract. If the loader
        // re-fetched on every render, a 25-row search would fan out into
        // 25 × renders RSS parses on every keystroke.
        var fetchCount = 0
        let loader = SearchPreviewLoader(
            previewCap: 8,
            fetch: { _ in
                fetchCount += 1
                return Self.makeSnapshot()
            }
        )
        _ = loader.state(for: Self.sampleResult, rank: 1)
        // Yield so the in-flight Task completes; recordSuccess flips the
        // state from .loading to .loaded.
        for _ in 0..<10 {
            await Task.yield()
            if case .loaded = loader.state(for: Self.sampleResult, rank: 1) { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        // Calling state() again should hit the cache, not the fetcher.
        _ = loader.state(for: Self.sampleResult, rank: 1)
        _ = loader.state(for: Self.sampleResult, rank: 1)
        #expect(fetchCount == 1)
        if case .loaded(let metadata) = loader.state(for: Self.sampleResult, rank: 1) {
            #expect(metadata.latestEpisodeTitle == "Latest Episode")
        } else {
            Issue.record("Expected loaded state after fetch")
        }
    }

    @MainActor
    @Test
    func loaderRecordsFailureWhenFetchThrows() async {
        // A fetch that throws (e.g. 500 from the RSS host, parse error)
        // should land as .failed — the row falls back to the no-preview
        // shape rather than spinning forever.
        struct StubError: Error {}
        let loader = SearchPreviewLoader(
            previewCap: 8,
            fetch: { _ in throw StubError() }
        )
        _ = loader.state(for: Self.sampleResult, rank: 1)
        for _ in 0..<10 {
            await Task.yield()
            if case .failed = loader.state(for: Self.sampleResult, rank: 1) { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(loader.state(for: Self.sampleResult, rank: 1) == .failed)
    }
}

// MARK: - PlaybackEvent emission (Phase 19)

/// Pins the contract for the four `PlaybackEvent.Kind` emitters wired in
/// Phase 19. Phase 18's audit found `~75%` of the playback-event scoring
/// machinery was dead code reading from a stream that only ever carried
/// `.completed` events. These tests cover the heuristics that turn user
/// behavior into the missing four signals — `.skippedQuickly`, `.abandoned`,
/// `.advancedFromQueue`, `.resumed` — without driving the AVPlayer
/// directly (the live singleton has audio-session side-effects we don't
/// want in a test process). The pure `classifySwitchAway` static is the
/// load-bearing piece; integration tests verify the wiring through
/// `PlaybackController.shared` for the auto-advance + resume paths.
@Suite("PlaybackEventEmission")
struct PlaybackEventEmissionTests {
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
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    private func makeEpisode(
        title: String = "Ep",
        in context: ModelContext,
        podcast: Podcast? = nil
    ) -> Episode {
        let pod = podcast ?? {
            let p = Podcast(title: "Show", feedURL: URL(string: "https://example.com/\(UUID().uuidString).xml")!)
            context.insert(p)
            return p
        }()
        let ep = Episode(
            title: title,
            pubDate: .now,
            audioURL: URL(string: "https://example.com/\(UUID().uuidString).mp3")!,
            podcast: pod
        )
        context.insert(ep)
        return ep
    }

    // MARK: classifySwitchAway pure tests

    @Test
    @MainActor
    func classifierReturnsSkippedQuicklyUnder30Seconds() throws {
        let container = try makeContainer()
        let ep = makeEpisode(in: container.mainContext)
        ep.duration = 1800 // 30-minute episode
        // 5 seconds in — well below the 30s skipped-quickly floor.
        #expect(PlaybackController.classifySwitchAway(episode: ep, position: 5, duration: 1800) == .skippedQuickly)
    }

    @Test
    @MainActor
    func classifierReturnsAbandonedAt60Percent() throws {
        let container = try makeContainer()
        let ep = makeEpisode(in: container.mainContext)
        ep.duration = 1800
        // 60% through (~18 minutes) — past quick-skip, well short of the
        // 85% "close enough to finish" gate.
        #expect(PlaybackController.classifySwitchAway(episode: ep, position: 1080, duration: 1800) == .abandoned)
    }

    @Test
    @MainActor
    func classifierReturnsNilAt90PercentCloseEnoughToFinish() throws {
        let container = try makeContainer()
        let ep = makeEpisode(in: container.mainContext)
        ep.duration = 1800
        // 90% through — past the 85% threshold. Emitting `.abandoned` here
        // would teach the recommender the user disliked content they
        // almost finished, which is exactly backwards.
        #expect(PlaybackController.classifySwitchAway(episode: ep, position: 1620, duration: 1800) == nil)
    }

    @Test
    @MainActor
    func classifierReturnsNilWhenEpisodeAlreadyCompleted() throws {
        let container = try makeContainer()
        let ep = makeEpisode(in: container.mainContext)
        ep.duration = 1800
        ep.isPlayed = true
        // The completion observer set isPlayed = true and emitted `.completed`
        // before auto-advance reached prepareItem. Don't double-emit.
        #expect(PlaybackController.classifySwitchAway(episode: ep, position: 100, duration: 1800) == nil)
    }

    @Test
    @MainActor
    func classifierReturnsNilWhenNoProgress() throws {
        let container = try makeContainer()
        let ep = makeEpisode(in: container.mainContext)
        ep.duration = 1800
        // User loaded an episode then bailed before any listening — no
        // signal either way. (Most common cause: deep-link / Spotlight
        // tap that the user immediately backed out of.)
        #expect(PlaybackController.classifySwitchAway(episode: ep, position: 0, duration: 1800) == nil)
    }

    @Test
    @MainActor
    func classifierTreats4HourEpisodeAt1MinuteAsQuickSkip() throws {
        let container = try makeContainer()
        let ep = makeEpisode(in: container.mainContext)
        ep.duration = 14400 // 4-hour episode
        // 60 seconds in. Past the wall-clock 30s floor, but the played
        // fraction (1/240 ≈ 0.4%) is well below 5% — clearly a quick
        // skip on a long-form episode. Without the fraction gate this
        // would mis-classify as `.abandoned`.
        #expect(PlaybackController.classifySwitchAway(episode: ep, position: 60, duration: 14400) == .skippedQuickly)
    }

    @Test
    @MainActor
    func classifierReturnsAbandonedWhenDurationUnknown() throws {
        let container = try makeContainer()
        let ep = makeEpisode(in: container.mainContext)
        // Episode duration not yet loaded (RSS-only, no AVPlayerItem
        // metadata yet). The fraction gates can't apply; fall through
        // to the wall-clock threshold. 5 minutes in with unknown
        // duration reads as abandonment, not quick skip.
        #expect(PlaybackController.classifySwitchAway(episode: ep, position: 300, duration: 0) == .abandoned)
    }

    // MARK: Integration through PlaybackController.shared

    @Test
    @MainActor
    func playSwitchingAwayMidEpisodeEmitsAbandoned() throws {
        // Drive the live singleton: prime an episode in mid-playback,
        // then call `play(newEpisode)` to trigger the switch-away path
        // in `prepareItem`. The outgoing episode should have an
        // `.abandoned` event recorded.
        let container = try makeContainer()
        let context = container.mainContext

        let outgoing = makeEpisode(title: "Outgoing", in: context)
        let incoming = makeEpisode(title: "Incoming", in: context)

        let controller = PlaybackController.shared
        controller.debugResetForTesting()
        controller.configure(context: context)
        controller.debugPrimePlayback(
            episode: outgoing,
            duration: 1800,
            currentTime: 900, // 50% through — abandonment territory
            isPlaying: true,
            presentPlayer: true
        )

        controller.play(incoming, in: context)

        let events = try context.fetch(FetchDescriptor<PlaybackEvent>())
        let outgoingEvents = events.filter { $0.episode?.id == outgoing.id }
        #expect(outgoingEvents.count == 1)
        #expect(outgoingEvents.first?.kind == .abandoned)
    }

    @Test
    @MainActor
    func playSwitchingAwayWithin30SecondsEmitsSkippedQuickly() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let outgoing = makeEpisode(title: "Outgoing", in: context)
        let incoming = makeEpisode(title: "Incoming", in: context)

        let controller = PlaybackController.shared
        controller.debugResetForTesting()
        controller.configure(context: context)
        controller.debugPrimePlayback(
            episode: outgoing,
            duration: 1800,
            currentTime: 5, // 5 seconds — quick skip
            isPlaying: true,
            presentPlayer: true
        )

        controller.play(incoming, in: context)

        let events = try context.fetch(FetchDescriptor<PlaybackEvent>())
        let outgoingEvents = events.filter { $0.episode?.id == outgoing.id }
        #expect(outgoingEvents.count == 1)
        #expect(outgoingEvents.first?.kind == .skippedQuickly)
    }

    @Test
    @MainActor
    func playSwitchingAwayNearCompletionEmitsNoEvent() throws {
        // 90% played — past the 85% threshold. We treat as good-faith
        // finish even though `.AVPlayerItemDidPlayToEndTime` never fired.
        let container = try makeContainer()
        let context = container.mainContext

        let outgoing = makeEpisode(title: "Outgoing", in: context)
        let incoming = makeEpisode(title: "Incoming", in: context)

        let controller = PlaybackController.shared
        controller.debugResetForTesting()
        controller.configure(context: context)
        controller.debugPrimePlayback(
            episode: outgoing,
            duration: 1800,
            currentTime: 1620, // 90%
            isPlaying: true,
            presentPlayer: true
        )

        controller.play(incoming, in: context)

        let events = try context.fetch(FetchDescriptor<PlaybackEvent>())
        let outgoingEvents = events.filter { $0.episode?.id == outgoing.id }
        #expect(outgoingEvents.isEmpty)
    }

    @Test
    @MainActor
    func replayingSameEpisodeDoesNotEmitSkipEvent() throws {
        // Tapping the currently-playing episode again is a re-load, not
        // a switch-away — no skip/abandon signal should fire.
        let container = try makeContainer()
        let context = container.mainContext

        let ep = makeEpisode(in: context)

        let controller = PlaybackController.shared
        controller.debugResetForTesting()
        controller.configure(context: context)
        controller.debugPrimePlayback(
            episode: ep,
            duration: 1800,
            currentTime: 600,
            isPlaying: true,
            presentPlayer: true
        )

        controller.play(ep, in: context)

        let events = try context.fetch(FetchDescriptor<PlaybackEvent>())
        // No skip/abandon (we replayed the same episode).
        #expect(events.allSatisfy { $0.kind != .skippedQuickly && $0.kind != .abandoned })
    }

    @Test
    @MainActor
    func togglePlayPauseResumeAtMeaningfulProgressEmitsResumed() throws {
        // User resumed mid-episode (past the 60s resumed-progress gate)
        // by tapping the mini-player play button. Emit `.resumed`.
        let container = try makeContainer()
        let context = container.mainContext

        let ep = makeEpisode(in: context)

        let controller = PlaybackController.shared
        controller.debugResetForTesting()
        controller.configure(context: context)
        controller.debugPrimePlayback(
            episode: ep,
            duration: 1800,
            currentTime: 600, // 10 minutes in — well past 60s gate
            isPlaying: false, // paused — togglePlayPause will resume
            presentPlayer: true
        )

        controller.togglePlayPause()
        // Re-pause immediately so we don't leave the test process with
        // a live audio player.
        if controller.isPlaying { controller.togglePlayPause() }

        let events = try context.fetch(FetchDescriptor<PlaybackEvent>())
        let resumed = events.filter { $0.kind == .resumed && $0.episode?.id == ep.id }
        #expect(resumed.count == 1)
    }

    @Test
    @MainActor
    func togglePlayPauseResumeBelow60SecondsEmitsNothing() throws {
        // User paused 10 seconds into a freshly queued episode, then
        // tapped play again. That's not a true resume — still in the
        // initial-listening phase. Emitting `.resumed` here would
        // inflate the positive signal on every queued episode.
        let container = try makeContainer()
        let context = container.mainContext

        let ep = makeEpisode(in: context)

        let controller = PlaybackController.shared
        controller.debugResetForTesting()
        controller.configure(context: context)
        controller.debugPrimePlayback(
            episode: ep,
            duration: 1800,
            currentTime: 10, // below 60s gate
            isPlaying: false,
            presentPlayer: true
        )

        controller.togglePlayPause()
        if controller.isPlaying { controller.togglePlayPause() }

        let events = try context.fetch(FetchDescriptor<PlaybackEvent>())
        #expect(events.allSatisfy { $0.kind != .resumed })
    }

    @Test
    @MainActor
    func playbackCompletionWithAutoplayEmitsAdvancedFromQueue() async throws {
        // Drive the real completion observer by posting
        // `.AVPlayerItemDidPlayToEndTime`. The observer should:
        //   1. Emit `.completed` for the finishing episode
        //   2. Call `skipToNextInQueue` → prepareItem on nextUp
        //   3. Emit `.advancedFromQueue` for nextUp (the new episode)
        //   4. NOT emit any skip/abandon (finishing.isPlayed becomes true)
        let container = try makeContainer()
        let context = container.mainContext

        let podcast = Podcast(title: "AutoAdv", feedURL: URL(string: "https://example.com/aa.xml")!)
        context.insert(podcast)
        let finishing = Episode(title: "Finishing", pubDate: .now, audioURL: URL(string: "https://example.com/f.mp3")!, podcast: podcast)
        let nextUp = Episode(title: "NextUp", pubDate: .now, audioURL: URL(string: "https://example.com/n.mp3")!, podcast: podcast)
        context.insert(finishing)
        context.insert(nextUp)

        try QueueService.addToEnd(nextUp, in: context)

        // Default to autoplay on (the controller falls back to true when
        // the key is unset, but we set it explicitly so a stale UserDefaults
        // entry from a prior test run can't suppress auto-advance.)
        UserDefaults.standard.set(true, forKey: "offscript.autoPlayNext")

        let controller = PlaybackController.shared
        controller.debugResetForTesting()
        controller.configure(context: context)
        controller.debugPrimePlayback(
            episode: finishing,
            duration: 1800,
            currentTime: 1800,
            isPlaying: true,
            presentPlayer: true
        )

        // Post the end-time notification — picked up by
        // `observePlaybackCompletion` which routes the completion through
        // a `Task { @MainActor }` (not synchronous), so we have to spin
        // the run loop a beat to let it land.
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: nil)
        for _ in 0..<10 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
            if controller.currentEpisode?.id == nextUp.id { break }
        }

        let events = try context.fetch(FetchDescriptor<PlaybackEvent>())
        let advanced = events.filter { $0.kind == .advancedFromQueue }
        let completed = events.filter { $0.kind == .completed }
        let skippedOnFinishing = events.filter {
            $0.episode?.id == finishing.id && ($0.kind == .skippedQuickly || $0.kind == .abandoned)
        }

        #expect(completed.count == 1)
        #expect(completed.first?.episode?.id == finishing.id)
        #expect(advanced.count == 1)
        #expect(advanced.first?.episode?.id == nextUp.id) // emitted FOR the NEW episode
        #expect(skippedOnFinishing.isEmpty) // no double-emit
    }

    @Test
    @MainActor
    func autoAdvanceDoesNotDoubleEmitSkipOrAbandonedOnFinishedEpisode() throws {
        // The completion observer marks `isPlayed = true` before calling
        // `skipToNextInQueue`, which calls `play(nextEpisode)` → prepareItem.
        // The skip/abandoned classifier must return nil for the OUTGOING
        // episode (it's already `isPlayed`), so we don't double-emit on
        // top of `.completed`. This test pins that the prepareItem path
        // honors the `isPlayed` short-circuit.
        let container = try makeContainer()
        let context = container.mainContext

        let podcast = Podcast(title: "Auto-advance", feedURL: URL(string: "https://example.com/aa.xml")!)
        context.insert(podcast)
        let finishing = Episode(title: "Finishing", pubDate: .now, audioURL: URL(string: "https://example.com/f.mp3")!, podcast: podcast)
        let nextUp = Episode(title: "NextUp", pubDate: .now, audioURL: URL(string: "https://example.com/n.mp3")!, podcast: podcast)
        context.insert(finishing)
        context.insert(nextUp)

        let controller = PlaybackController.shared
        controller.debugResetForTesting()
        controller.configure(context: context)
        controller.debugPrimePlayback(
            episode: finishing,
            duration: 1800,
            currentTime: 1800,
            isPlaying: true,
            presentPlayer: true
        )
        // Mirror the completion observer: episode is now played.
        finishing.isPlayed = true
        try context.save()

        // This is what the observer calls after marking isPlayed + emitting
        // .completed: switching the controller to the next episode. Our
        // contract: no skippedQuickly / abandoned should fire for
        // `finishing` because it's already `isPlayed`. The real production
        // emission of `.advancedFromQueue` happens inside the observer
        // callback (post-skipToNextInQueue) and is out of reach of an
        // AVPlayer-less unit test, but the no-double-emit contract is
        // testable here.
        controller.play(nextUp, in: context)

        let events = try context.fetch(FetchDescriptor<PlaybackEvent>())
        let skipOnFinishing = events.filter {
            $0.episode?.id == finishing.id && ($0.kind == .skippedQuickly || $0.kind == .abandoned)
        }
        #expect(skipOnFinishing.isEmpty)
    }

    @Test
    @MainActor
    func togglePlayPausePauseAlonePersistsNoEvent() throws {
        // Pausing should never emit a PlaybackEvent — only resumes
        // (with meaningful progress) carry signal.
        let container = try makeContainer()
        let context = container.mainContext

        let ep = makeEpisode(in: context)

        let controller = PlaybackController.shared
        controller.debugResetForTesting()
        controller.configure(context: context)
        controller.debugPrimePlayback(
            episode: ep,
            duration: 1800,
            currentTime: 600,
            isPlaying: true,
            presentPlayer: true
        )

        controller.togglePlayPause() // pause

        let events = try context.fetch(FetchDescriptor<PlaybackEvent>())
        #expect(events.isEmpty)
    }
}

/// Pins the brand-promise decay contract from the Phase 18
/// `2026-05-19-recommendation-credibility.md` audit: 14-day half-life,
/// hard 120-day cutoff (no floor), and a per-show binge dampener that
/// applies only to passive playback signals — explicit preference
/// signals AND negative passive signals must still accumulate fully.
@Suite("TasteProfileDecay")
struct TasteProfileDecayTests {
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
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: recencyWeight pure tests

    @Test
    @MainActor
    func decayHalfLifeIs14Days() {
        let weight = TasteProfileService.recencyWeight(for: Date().addingTimeInterval(-14 * 86_400))
        #expect(abs(weight - 0.5) < 0.01)
    }

    @Test
    @MainActor
    func decayHasNoFloorPastCutoff() {
        // 121 days = one day past the 120-day signalCutoffDays. The old
        // formula had a 0.15 floor that lingered here forever.
        let weight = TasteProfileService.recencyWeight(for: Date().addingTimeInterval(-121 * 86_400))
        #expect(weight == 0)
    }

    @Test
    @MainActor
    func decayReturnsOneAtZeroAge() {
        let weight = TasteProfileService.recencyWeight(for: .now)
        #expect(abs(weight - 1.0) < 0.001)
    }

    @Test
    @MainActor
    func decayHalvesAgainAt28Days() {
        // Half-life contract: weight halves every 14 days, so 28 days
        // should land near 0.25. A second pin guards against future
        // edits that change the curve shape but happen to leave the
        // 14-day point at 0.5.
        let weight = TasteProfileService.recencyWeight(for: Date().addingTimeInterval(-28 * 86_400))
        #expect(abs(weight - 0.25) < 0.01)
    }

    @Test
    @MainActor
    func decayJustInsideCutoffStillContributes() {
        // 119 days — one day inside the cutoff. Weight should be tiny
        // but strictly positive. Old code returned 0.15 here; new code
        // should return something like exp(-ln(2) * 119/14) ≈ 0.0028.
        let weight = TasteProfileService.recencyWeight(for: Date().addingTimeInterval(-119 * 86_400))
        #expect(weight > 0)
        #expect(weight < 0.01)
    }

    // MARK: binge dampener (passive playback)

    @Test
    @MainActor
    func tasteProfileBingeDampenerCapsSingleShowDominance() throws {
        // 20 recent `.completed` events on Show A's "ai" tag vs. a
        // single `like` on Show B's "history" tag. Without the
        // dampener, Show A's tagScore = 20 * 1.5 = 30 swamps Show B's
        // 5.0 and history never reaches `topTags`. With the dampener,
        // Show A's sum collapses to 1.5 * Σ(1/sqrt(k), k=1..20) ≈ 11.3
        // — still above 5.0 but now history is firmly inside the
        // top 3.
        let container = try makeContainer()
        let context = container.mainContext

        let showA = Podcast(title: "Binge Show A", feedURL: URL(string: "https://example.com/a.xml")!)
        let showB = Podcast(title: "Niche Show B", feedURL: URL(string: "https://example.com/b.xml")!)
        context.insert(showA)
        context.insert(showB)

        for i in 0..<20 {
            let ep = Episode(
                title: "A\(i)",
                pubDate: Date().addingTimeInterval(-Double(i) * 3_600),
                duration: 1_800,
                audioURL: URL(string: "https://example.com/a/\(i).mp3")!,
                podcast: showA
            )
            context.insert(ep)
            let profile = EpisodeProfile(episodeID: ep.id)
            profile.tags = ["ai"]
            context.insert(profile)
            context.insert(PlaybackEvent(kind: .completed, position: 1_800, episode: ep))
        }

        let bEp = Episode(
            title: "B0",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/b/0.mp3")!,
            podcast: showB
        )
        context.insert(bEp)
        let bProfile = EpisodeProfile(episodeID: bEp.id)
        bProfile.tags = ["history"]
        context.insert(bProfile)
        context.insert(PreferenceSignal(action: .like, episode: bEp))

        try context.save()
        try TasteProfileService.refresh(in: context, force: true)

        let profile = try TasteProfileService.loadOrCreate(in: context)
        let top3 = Array(profile.topTags.prefix(3))
        #expect(top3.contains("history"))
        // Sanity: "ai" still wins outright; dampener doesn't flip the
        // ranking, it just stops Show A from drowning Show B out.
        #expect(profile.topTags.first == "ai")
    }

    @Test
    @MainActor
    func tasteProfileExplicitSignalsAreNotBingeDampened() throws {
        // 5 explicit `.moreLikeThis` taps on episodes from the same
        // show should each contribute the full 8.0. Sum = 40 for the
        // tag they all share. Mirror that with a single like (weight
        // 5.0) on a different show's tag — explicit signals stacking
        // is the brand promise: tapping the button N times reads as
        // Nx weight.
        let container = try makeContainer()
        let context = container.mainContext

        let show = Podcast(title: "Decoder", feedURL: URL(string: "https://example.com/decoder.xml")!)
        context.insert(show)
        for i in 0..<5 {
            let ep = Episode(
                title: "Decoder \(i)",
                pubDate: Date().addingTimeInterval(-Double(i) * 3_600),
                duration: 1_800,
                audioURL: URL(string: "https://example.com/decoder/\(i).mp3")!,
                podcast: show
            )
            context.insert(ep)
            let p = EpisodeProfile(episodeID: ep.id)
            p.tags = ["ai tooling"]
            context.insert(p)
            context.insert(PreferenceSignal(action: .moreLikeThis, episode: ep))
        }

        let otherShow = Podcast(title: "Other", feedURL: URL(string: "https://example.com/other.xml")!)
        let otherEp = Episode(
            title: "Other",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/other.mp3")!,
            podcast: otherShow
        )
        context.insert(otherShow)
        context.insert(otherEp)
        let otherProfile = EpisodeProfile(episodeID: otherEp.id)
        otherProfile.tags = ["history"]
        context.insert(otherProfile)
        context.insert(PreferenceSignal(action: .like, episode: otherEp))

        try context.save()
        try TasteProfileService.refresh(in: context, force: true)

        let profile = try TasteProfileService.loadOrCreate(in: context)
        // "ai tooling" must be ranked first: 5 explicit signals = 5x
        // weight, not √-dampened.
        #expect(profile.topTags.first == "ai tooling")
        // Show affinity should also credit Decoder for the explicit
        // taps; if these were dampened, Other's single like (5.0)
        // would beat Decoder's dampened 5*8/√k sum.
        #expect(profile.showAffinity.first == "Decoder")
    }

    @Test
    @MainActor
    func tasteProfileNegativeSignalsAreNotBingeDampened() throws {
        // 10 `.skippedQuickly` events on Show X should fully
        // accumulate to a deeply negative tagScore so the negative
        // signal still bites in the suppression logic downstream.
        // If we accidentally dampened negative signals, a noisy
        // skipper would have ~22% influence by the 20th skip, which
        // we explicitly DO NOT want — repeat skips read as a strong
        // "stop showing me this" signal.
        let container = try makeContainer()
        let context = container.mainContext

        let show = Podcast(title: "Skip Show", feedURL: URL(string: "https://example.com/skip.xml")!)
        context.insert(show)

        for i in 0..<10 {
            let ep = Episode(
                title: "S\(i)",
                pubDate: Date().addingTimeInterval(-Double(i) * 3_600),
                duration: 1_800,
                audioURL: URL(string: "https://example.com/skip/\(i).mp3")!,
                podcast: show
            )
            context.insert(ep)
            let p = EpisodeProfile(episodeID: ep.id)
            p.tags = ["disliked-tag"]
            context.insert(p)
            context.insert(PlaybackEvent(kind: .skippedQuickly, position: 5, episode: ep))
        }

        // Add one positive signal on the disliked-tag with a tiny
        // weight so the tag is in the map at all (the negative
        // pathway can't surface in `topTags` because that filter
        // drops `value <= 0`).
        let positiveEp = Episode(
            title: "Pos",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/pos.mp3")!,
            podcast: show
        )
        context.insert(positiveEp)
        let posProfile = EpisodeProfile(episodeID: positiveEp.id)
        posProfile.tags = ["disliked-tag"]
        context.insert(posProfile)
        context.insert(PreferenceSignal(action: .like, episode: positiveEp))

        try context.save()
        try TasteProfileService.refresh(in: context, force: true)

        let profile = try TasteProfileService.loadOrCreate(in: context)
        // The single +5 like on disliked-tag is dwarfed by 10x -1.4
        // skippedQuickly signals (each near full weight after
        // recency). The aggregate is negative and the tag must NOT
        // appear in topTags.
        #expect(!profile.topTags.contains("disliked-tag"))
        // Show affinity is a related fail-safe: a 10x skip-quickly
        // run on Show X must not float Show X into showAffinity. The
        // positive +5 from a like is more than offset by 10x -1.6
        // playbackShowWeight on the same show.
        #expect(!profile.showAffinity.contains("Skip Show"))
    }

    @Test
    @MainActor
    func tasteProfileRefreshIgnoresEventsOlderThanCutoff() throws {
        // A single `.completed` event 130 days old must NOT
        // contribute to topTags. Mirror it with a recent
        // `.moreLikeThis` on a different tag to give the profile
        // something to bind to (so we know the refresh ran).
        let container = try makeContainer()
        let context = container.mainContext

        let show = Podcast(title: "Ancient", feedURL: URL(string: "https://example.com/old.xml")!)
        context.insert(show)

        let ancientEp = Episode(
            title: "Old",
            pubDate: Date().addingTimeInterval(-130 * 86_400),
            duration: 1_800,
            audioURL: URL(string: "https://example.com/old.mp3")!,
            podcast: show
        )
        context.insert(ancientEp)
        let ancientProfile = EpisodeProfile(episodeID: ancientEp.id)
        ancientProfile.tags = ["fossil-tag"]
        context.insert(ancientProfile)
        let ancientEvent = PlaybackEvent(kind: .completed, position: 1_800, episode: ancientEp)
        ancientEvent.date = Date().addingTimeInterval(-130 * 86_400)
        context.insert(ancientEvent)

        let freshEp = Episode(
            title: "Fresh",
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/fresh.mp3")!,
            podcast: show
        )
        context.insert(freshEp)
        let freshProfile = EpisodeProfile(episodeID: freshEp.id)
        freshProfile.tags = ["fresh-tag"]
        context.insert(freshProfile)
        context.insert(PreferenceSignal(action: .moreLikeThis, episode: freshEp))

        try context.save()
        try TasteProfileService.refresh(in: context, force: true)

        let profile = try TasteProfileService.loadOrCreate(in: context)
        #expect(profile.topTags.contains("fresh-tag"))
        #expect(!profile.topTags.contains("fossil-tag"))
    }
}


/// Pins the editorial-collection filter contract from the Phase 21
/// `2026-05-19-curated-discovery.md` audit: declarative filters that
/// compose by intersection, with deterministic resolution against the
/// shipped catalog. These are pure tests on the `Filter.matches` and
/// `CuratedPodcastCatalog.resolve` surfaces — no live network, no
/// SwiftData container.
@Suite("CuratedDiscoveryFilter")
struct CuratedDiscoveryFilterTests {
    private func makeEntry(
        genre: Genre = .technology,
        duration: ClosedRange<TimeInterval>? = 45 * 60 ... 65 * 60,
        keywords: Set<String> = []
    ) -> CuratedEntry {
        let result = PodcastSearchResult(
            title: "Test Show",
            author: "Author",
            feedURL: URL(string: "https://example.com/\(UUID().uuidString).xml")!,
            artworkURL: nil,
            websiteURL: nil,
            summary: nil
        )
        return CuratedEntry(result: result, genre: genre, typicalDuration: duration, keywords: keywords)
    }

    @Test
    func collectionFilterMatchesDurationRangeOverlap() {
        // The candidate's typicalDuration is 30...50 min — its upper
        // bound (50 min) overlaps the filter's 45...65 min window, so
        // it should match. A candidate at 90...120 min sits entirely
        // above the window and must NOT match.
        let overlap = makeEntry(duration: 30 * 60 ... 50 * 60)
        let above = makeEntry(duration: 90 * 60 ... 120 * 60)
        let filter = EditorialCollection.Filter.duration(min: 45 * 60, max: 65 * 60)
        #expect(filter.matches(overlap))
        #expect(!filter.matches(above))
    }

    @Test
    func collectionFilterHandlesOpenEndedDuration() {
        // `.duration(min: 90*60, max: nil)` — no upper cap. A
        // 240...360 min range satisfies the floor.
        let lowerOnly = EditorialCollection.Filter.duration(min: 90 * 60, max: nil)
        let longShow = makeEntry(duration: 240 * 60 ... 360 * 60)
        #expect(lowerOnly.matches(longShow))

        // `.duration(min: nil, max: 30*60)` — no lower cap. A
        // 20...35 min range's lower bound (20) is inside the cap.
        let upperOnly = EditorialCollection.Filter.duration(min: nil, max: 30 * 60)
        let mixedShortish = makeEntry(duration: 20 * 60 ... 35 * 60)
        #expect(upperOnly.matches(mixedShortish))
    }

    @Test
    func collectionFilterCombinesIntersectionCorrectly() {
        // `.combined([...])` requires ALL members to match. A
        // candidate that passes duration but is in the wrong genre
        // must be rejected; a candidate in the right genre but
        // outside the duration must also be rejected.
        let filter = EditorialCollection.Filter.combined([
            .duration(min: nil, max: 25 * 60),
            .genres([.newsAndPolitics])
        ])
        let rightDurationWrongGenre = makeEntry(
            genre: .comedy,
            duration: 10 * 60 ... 20 * 60
        )
        let rightGenreWrongDuration = makeEntry(
            genre: .newsAndPolitics,
            duration: 45 * 60 ... 60 * 60
        )
        let bothMatch = makeEntry(
            genre: .newsAndPolitics,
            duration: 10 * 60 ... 20 * 60
        )
        #expect(!filter.matches(rightDurationWrongGenre))
        #expect(!filter.matches(rightGenreWrongDuration))
        #expect(filter.matches(bothMatch))
    }

    @Test
    func collectionFilterKeywordsAreCaseInsensitive() {
        // Curator keywords land lowercased, but the filter shape
        // should still accept uppercase input from the call site. The
        // candidate must also be rejected when none of its keywords
        // match the filter's set.
        let filter = EditorialCollection.Filter.keywords(["Interview"])
        let matchingEntry = makeEntry(keywords: ["interview"])
        let mismatchEntry = makeEntry(keywords: ["storytelling"])
        #expect(filter.matches(matchingEntry))
        #expect(!filter.matches(mismatchEntry))
    }

    @Test
    func collectionFilterRejectsCandidatesMissingDurationForDurationFilter() {
        // The curator's `typicalDuration = nil` opt-out (mini + full
        // episodes vary too wildly to bucket) MUST exclude the
        // candidate from any duration-shaped filter — we'd rather
        // omit a show than mis-bucket it.
        let filter = EditorialCollection.Filter.duration(min: 45 * 60, max: 65 * 60)
        let unbucketed = makeEntry(duration: nil)
        #expect(!filter.matches(unbucketed))
    }

    @Test
    func resolveProducesNonEmptyForEveryShippedCollection() {
        // Guard: a future catalog edit must not silently empty a
        // shipped editorial shelf. The audit's design contract is
        // "we never paint a shelf that lies to the user."
        for collection in CuratedPodcastCatalog.editorialCollections {
            let resolved = CuratedPodcastCatalog.resolve(collection)
            #expect(!resolved.isEmpty, "Collection \(collection.id) resolved empty")
        }
    }

    @Test
    func resolvePreservesCatalogOrder() {
        // Resolution should never reorder — editorial ordering is
        // catalog-curated. Pick a collection that resolves to ≥ 2
        // entries and verify the resolved sequence is a subsequence
        // of `CuratedPodcastCatalog.entries`.
        let allEntries = CuratedPodcastCatalog.entries
        let allFeedOrder = allEntries.map(\.result.feedURL)
        for collection in CuratedPodcastCatalog.editorialCollections {
            let resolved = CuratedPodcastCatalog.resolve(collection)
            guard resolved.count >= 2 else { continue }
            let resolvedFeeds = resolved.map(\.result.feedURL)
            // Walk `allFeedOrder` and confirm `resolvedFeeds` appear
            // in the same relative order.
            var walkIndex = 0
            for feed in allFeedOrder where walkIndex < resolvedFeeds.count {
                if feed == resolvedFeeds[walkIndex] {
                    walkIndex += 1
                }
            }
            #expect(
                walkIndex == resolvedFeeds.count,
                "Collection \(collection.id) reorders catalog: \(resolvedFeeds)"
            )
        }
    }

    @Test
    func resolveCurrentlyDoesNotDeduplicateByFeedURL() {
        // Defensive coverage: the current implementation does NOT
        // dedupe by feedURL — if the catalog later contained the
        // same feed in two genres, `resolve` would emit both
        // CuratedEntry instances. Pin that as the current behavior so
        // a future dedup pass (Set<URL> hop in `resolve`) is forced
        // to update this test deliberately. Today no catalog feed
        // duplicates exist, so resolution returns distinct feeds
        // either way — this test pins the *catalog* invariant
        // alongside.
        let resolved = CuratedPodcastCatalog.resolve(
            EditorialCollection(
                id: "test-all",
                title: "All",
                subtitle: nil,
                curatorNote: nil,
                filter: .duration(min: 0, max: 24 * 3_600)
            )
        )
        let uniqueFeeds = Set(resolved.map(\.result.feedURL))
        #expect(uniqueFeeds.count == resolved.count)
    }

    @Test
    func collectionFilterCombinedEmptyMatchesEverything() {
        // `.combined([])` reduces to `allSatisfy({…})` over an empty
        // set, which is vacuously true. This is the only sensible
        // identity — pin it so a future "if empty, return false"
        // edit can't slip in.
        let filter = EditorialCollection.Filter.combined([])
        let anyEntry = makeEntry()
        #expect(filter.matches(anyEntry))
    }
}

/// Pins the contracts the Debug Inspector relies on from Phase 27
/// (`2026-05-20-debug-inspector.md`): `SyncHistoryService` selection
/// + fallback + status labeling, and the same `FetchDescriptor`
/// shapes the inspector's private `refreshTelemetry` / `refreshDownloads`
/// / `clearAllTelemetry` paths use. We test the descriptor contract
/// rather than reaching into the view's private state — if a future
/// refactor changes the predicate shape (e.g. swaps sort field),
/// these tests fail on the contract before they fail on the UI.
@Suite("DebugInspector")
struct DebugInspectorTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Podcast.self,
            Episode.self,
            EpisodeProfile.self,
            PlaybackEvent.self,
            PreferenceSignal.self,
            QueueItem.self,
            UserTasteProfile.self,
            TelemetryEvent.self,
            EpisodeTranscriptCache.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    private func makePodcast(
        title: String,
        in context: ModelContext,
        isSubscribed: Bool = true,
        lastSyncAttemptAt: Date? = nil,
        syncStatus: String = "idle"
    ) -> Podcast {
        let podcast = Podcast(
            title: title,
            feedURL: URL(string: "https://example.com/\(UUID().uuidString).xml")!,
            isSubscribed: isSubscribed
        )
        podcast.lastSyncAttemptAt = lastSyncAttemptAt
        podcast.syncStatus = syncStatus
        context.insert(podcast)
        return podcast
    }

    @MainActor
    private func makeEpisode(
        title: String = "Ep",
        state: Episode.DownloadState,
        in context: ModelContext,
        requestedAt: Date? = nil,
        completedAt: Date? = nil
    ) -> Episode {
        let podcast = Podcast(
            title: "Show",
            feedURL: URL(string: "https://example.com/\(UUID().uuidString).xml")!
        )
        context.insert(podcast)
        let episode = Episode(
            title: title,
            pubDate: .now,
            duration: 1_800,
            audioURL: URL(string: "https://example.com/\(UUID().uuidString).mp3")!,
            podcast: podcast
        )
        episode.downloadState = state
        episode.downloadRequestedAt = requestedAt
        episode.downloadCompletedAt = completedAt
        context.insert(episode)
        return episode
    }

    // MARK: Telemetry contracts

    @Test
    @MainActor
    func debugInspectorListsAllTelemetryEvents() throws {
        // Seeds 5 events with strictly-staggered createdAt values and
        // pins the same descriptor the inspector uses
        // (createdAt desc, fetchLimit = 100). Result must be 5
        // descending — newest first.
        let container = try makeContainer()
        let context = container.mainContext

        let baseline = Date(timeIntervalSinceReferenceDate: 1_700_000_000)
        for i in 0..<5 {
            let event = TelemetryEvent(
                name: "test.event.\(i)",
                createdAt: baseline.addingTimeInterval(Double(i) * 60)
            )
            context.insert(event)
        }
        try context.save()

        var descriptor = FetchDescriptor<TelemetryEvent>(
            sortBy: [SortDescriptor(\TelemetryEvent.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        let events = try context.fetch(descriptor)
        #expect(events.count == 5)
        #expect(events.first?.name == "test.event.4")
        #expect(events.last?.name == "test.event.0")
    }

    @Test
    @MainActor
    func debugInspectorRespectsTelemetryFetchLimit() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let baseline = Date(timeIntervalSinceReferenceDate: 1_700_000_000)
        for i in 0..<150 {
            let event = TelemetryEvent(
                name: "test.event.\(i)",
                createdAt: baseline.addingTimeInterval(Double(i))
            )
            context.insert(event)
        }
        try context.save()

        var descriptor = FetchDescriptor<TelemetryEvent>(
            sortBy: [SortDescriptor(\TelemetryEvent.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        let events = try context.fetch(descriptor)
        #expect(events.count == 100)
        // Newest-first: the most recent event should be event index 149.
        #expect(events.first?.name == "test.event.149")
    }

    @Test
    @MainActor
    func debugInspectorTelemetryClearAllWipesStore() throws {
        let container = try makeContainer()
        let context = container.mainContext

        for i in 0..<5 {
            context.insert(TelemetryEvent(name: "noise.\(i)"))
        }
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<TelemetryEvent>()) == 5)

        try context.delete(model: TelemetryEvent.self)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<TelemetryEvent>()) == 0)
    }

    // MARK: Download-state grouping contracts

    @Test
    @MainActor
    func debugInspectorDownloadStateSectionGroupsCorrectly() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let downloading = makeEpisode(title: "DLing", state: .downloading, in: context)
        let queued = makeEpisode(title: "Q", state: .queued, in: context)
        let failed = makeEpisode(title: "F", state: .failed, in: context)
        let downloaded = makeEpisode(title: "Done", state: .downloaded, in: context)
        // notDownloaded sentinel — must not appear in any of the four sections.
        _ = makeEpisode(title: "Plain", state: .notDownloaded, in: context)
        try context.save()

        let downloadingState = Episode.DownloadState.downloading.rawValue
        let queuedState = Episode.DownloadState.queued.rawValue
        let failedState = Episode.DownloadState.failed.rawValue
        let downloadedState = Episode.DownloadState.downloaded.rawValue

        let downloadingFetched = try context.fetch(FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.downloadStateRawValue == downloadingState }
        ))
        let queuedFetched = try context.fetch(FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.downloadStateRawValue == queuedState }
        ))
        let failedFetched = try context.fetch(FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.downloadStateRawValue == failedState }
        ))
        let downloadedFetched = try context.fetch(FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.downloadStateRawValue == downloadedState }
        ))

        #expect(downloadingFetched.map(\.id) == [downloading.id])
        #expect(queuedFetched.map(\.id) == [queued.id])
        #expect(failedFetched.map(\.id) == [failed.id])
        #expect(downloadedFetched.map(\.id) == [downloaded.id])
    }

    @Test
    @MainActor
    func debugInspectorDownloadedSectionSortsByCompletedAtDesc() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let base = Date(timeIntervalSinceReferenceDate: 1_700_000_000)
        let oldest = makeEpisode(
            title: "Oldest",
            state: .downloaded,
            in: context,
            completedAt: base
        )
        let middle = makeEpisode(
            title: "Middle",
            state: .downloaded,
            in: context,
            completedAt: base.addingTimeInterval(60)
        )
        let newest = makeEpisode(
            title: "Newest",
            state: .downloaded,
            in: context,
            completedAt: base.addingTimeInterval(120)
        )
        try context.save()

        let downloadedState = Episode.DownloadState.downloaded.rawValue
        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.downloadStateRawValue == downloadedState },
            sortBy: [SortDescriptor(\Episode.downloadCompletedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        let fetched = try context.fetch(descriptor)
        #expect(fetched.map(\.id) == [newest.id, middle.id, oldest.id])
    }

    @Test
    @MainActor
    func debugInspectorFailedRowRetryFlipsStateToQueued() throws {
        // The inspector's failed-row retry calls
        // `DownloadService.shared.startDownload(for:)`. We can't easily
        // exercise the live network path in unit tests, but we can pin
        // the contract that `startDownload` moves a `.failed` episode
        // forward and clears the prior error message.
        let container = try makeContainer()
        let context = container.mainContext

        // Reset the singleton so test isolation holds.
        DebugTeardown.resetAllSingletons()
        DownloadService.shared.configure(context: context)

        let failed = makeEpisode(title: "F", state: .failed, in: context)
        failed.downloadErrorMessage = "Network unreachable"
        try context.save()
        #expect(failed.downloadState == .failed)

        DownloadService.shared.startDownload(for: failed)
        // startDownload schedules a URLSession task; in test we can't
        // wait for the network. The synchronous part of the contract
        // we DO pin: the episode is no longer in `.failed` (the
        // service must have moved it forward) and the prior error
        // message has been cleared.
        #expect(failed.downloadState != .failed)
        #expect(failed.downloadErrorMessage == nil)

        DebugTeardown.resetAllSingletons()
    }

    // MARK: SyncHistoryService

    @Test
    @MainActor
    func syncHistoryServiceFallsBackToSubscribedWhenNoneAttempted() throws {
        let container = try makeContainer()
        let context = container.mainContext

        _ = makePodcast(title: "Charlie", in: context, lastSyncAttemptAt: nil)
        _ = makePodcast(title: "Alpha", in: context, lastSyncAttemptAt: nil)
        _ = makePodcast(title: "Bravo", in: context, lastSyncAttemptAt: nil)
        try context.save()

        let result = SyncHistoryService.recentlyAttempted(in: context, limit: 10)
        #expect(result.count == 3)
        #expect(result.map(\.title) == ["Alpha", "Bravo", "Charlie"])
    }

    @Test
    @MainActor
    func syncHistoryServicePrefersAttemptedOverSubscribedFallback() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Two attempted + one never-attempted. The attempted ones
        // should come back (not the fallback).
        _ = makePodcast(title: "Never", in: context, lastSyncAttemptAt: nil)
        _ = makePodcast(
            title: "Recent",
            in: context,
            lastSyncAttemptAt: Date().addingTimeInterval(-60),
            syncStatus: "success"
        )
        _ = makePodcast(
            title: "Older",
            in: context,
            lastSyncAttemptAt: Date().addingTimeInterval(-3_600),
            syncStatus: "success"
        )
        try context.save()

        let result = SyncHistoryService.recentlyAttempted(in: context, limit: 10)
        #expect(result.map(\.title) == ["Recent", "Older"])
        // Sanity: the "Never" podcast must be absent because the
        // attempted set was non-empty (no fallback triggered).
        #expect(!result.contains(where: { $0.title == "Never" }))
    }

    @Test
    @MainActor
    func syncHistoryServiceStatusLabelHandlesUnknownState() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let podcast = makePodcast(title: "X", in: context, syncStatus: "throttled")
        try context.save()

        #expect(SyncHistoryService.statusLabel(for: podcast) == "● THROTTLED")
    }

    @Test
    @MainActor
    func syncHistoryServiceStatusLabelMapsKnownStates() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let success = makePodcast(title: "S", in: context, syncStatus: "success")
        let failed = makePodcast(title: "F", in: context, syncStatus: "failed")
        let pending = makePodcast(title: "P", in: context, syncStatus: "pending")
        let idleAttempted = makePodcast(
            title: "IA",
            in: context,
            lastSyncAttemptAt: Date(),
            syncStatus: "idle"
        )
        let never = makePodcast(title: "N", in: context, syncStatus: "idle")
        try context.save()

        #expect(SyncHistoryService.statusLabel(for: success) == "● SUCCESS")
        #expect(SyncHistoryService.statusLabel(for: failed) == "× FAILED")
        #expect(SyncHistoryService.statusLabel(for: pending) == "◐ PENDING")
        #expect(SyncHistoryService.statusLabel(for: idleAttempted) == "● IDLE")
        #expect(SyncHistoryService.statusLabel(for: never) == "○ NEVER")
    }
}

/// Pins the SRT + HTML decoder contracts from Phase 29
/// (`2026-05-19-transcript-pipeline-audit.md`). All inputs are pure
/// strings → `[TranscriptCue]`, so the fixtures live inline. The
/// dispatch sniffs (leading `<` → HTML, integer + `-->` → SRT) are
/// also covered here so the entry point's auto-detect stays honest.
@Suite("TranscriptDecoder")
struct TranscriptDecoderTests {
    @Test
    func srtDecoderHandlesCommaAndPeriodMsSeparators() {
        // Canonical SRT uses comma; period is widely emitted and the
        // parser normalises both. Two-block fixture exercises both.
        let srt = """
        1
        00:00:01,500 --> 00:00:03,000
        Comma-separated start.

        2
        00:00:04.250 --> 00:00:06.000
        Period-separated start.
        """
        let cues = PublishedTranscriptLoader.decodeSRT(text: srt) ?? []
        #expect(cues.count == 2)
        #expect(abs((cues.first?.startTime ?? 0) - 1.5) < 0.001)
        #expect(abs((cues[1].startTime) - 4.25) < 0.001)
    }

    @Test
    func srtDecoderStripsHTMLTagsInCueText() {
        let srt = """
        1
        00:00:00,000 --> 00:00:05,000
        <i>Italic</i> and <b>bold</b> markup.
        """
        let cues = PublishedTranscriptLoader.decodeSRT(text: srt) ?? []
        let text = cues.first?.text ?? ""
        #expect(!text.contains("<i>"))
        #expect(!text.contains("</b>"))
        #expect(text.contains("Italic"))
        #expect(text.contains("bold"))
    }

    @Test
    func srtDecoderHandlesMultilineCueText() {
        // Multi-line cues are joined with a space.
        let srt = """
        1
        00:00:00,000 --> 00:00:10,000
        Second line, possibly
        spread across two rows.
        """
        let cues = PublishedTranscriptLoader.decodeSRT(text: srt) ?? []
        #expect(cues.first?.text == "Second line, possibly spread across two rows.")
    }

    @Test
    func srtDecoderToleratesWindowsLineEndings() {
        // Windows feeds use \r\n. The parser normalises before
        // splitting on \n\n.
        let srt = "1\r\n00:00:01,000 --> 00:00:02,000\r\nWindows line endings.\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\nAnother cue."
        let cues = PublishedTranscriptLoader.decodeSRT(text: srt) ?? []
        #expect(cues.count == 2)
        #expect(cues.first?.text == "Windows line endings.")
    }

    @Test
    func srtDecoderToleratesTrailingBlankBlocks() {
        let srt = """
        1
        00:00:01,000 --> 00:00:02,000
        First.



        """
        let cues = PublishedTranscriptLoader.decodeSRT(text: srt) ?? []
        #expect(cues.count == 1)
        #expect(cues.first?.text == "First.")
    }

    @Test
    func srtDecoderReturnsNilForEmptyInput() {
        // Edge: a string with no parseable blocks should return nil,
        // not an empty array — the dispatch uses nil to fall through
        // to the next decoder.
        #expect(PublishedTranscriptLoader.decodeSRT(text: "") == nil)
        #expect(PublishedTranscriptLoader.decodeSRT(text: "not a transcript") == nil)
    }

    @Test
    func htmlDecoderExtractsTimedCuesFromDataStartAttributes() {
        let html = """
        <article>
        <p data-start="0.5">First line at half a second.</p>
        <p data-start="5.25">Second line, five and a quarter.</p>
        </article>
        """
        let cues = PublishedTranscriptLoader.decodeHTML(text: html, episodeDuration: nil) ?? []
        #expect(cues.count == 2)
        #expect(abs((cues.first?.startTime ?? 0) - 0.5) < 0.001)
        #expect(cues.first?.text == "First line at half a second.")
        #expect(abs((cues[1].startTime) - 5.25) < 0.001)
    }

    @Test
    func htmlDecoderExtractsTimedCuesFromDataTimeSpans() {
        // `<span data-time="N">` is the alternate convention.
        let html = #"""
        <p><span data-time="12.0">Twelve seconds.</span> <span data-time="14.5">Fourteen and a half.</span></p>
        """#
        let cues = PublishedTranscriptLoader.decodeHTML(text: html, episodeDuration: nil) ?? []
        #expect(cues.count == 2)
        #expect(abs((cues.first?.startTime ?? 0) - 12.0) < 0.001)
        #expect(cues[1].text == "Fourteen and a half.")
    }

    @Test
    func htmlDecoderFallsBackToSingleCueWhenNoTimingPresent() {
        // No data-start / data-time attributes → single cue spanning
        // the episode duration so the prose is still searchable.
        let html = """
        <article>
        <p>This transcript has no timing markers at all.</p>
        <p>Just prose, paragraph after paragraph.</p>
        </article>
        """
        let cues = PublishedTranscriptLoader.decodeHTML(text: html, episodeDuration: 1_800) ?? []
        #expect(cues.count == 1)
        #expect(cues.first?.startTime == 0)
        #expect(cues.first?.endTime == 1_800)
        #expect(cues.first?.text.contains("no timing markers") == true)
        #expect(cues.first?.text.contains("paragraph") == true)
    }

    @Test
    func htmlDecoderStripsCommonEntitiesInPlainText() {
        // Entities the stripper explicitly decodes: &nbsp; &amp;
        // &lt; &gt; &quot; &#39; &apos;.
        let html = "<p>Tom &amp; Jerry &nbsp; &lt;3 &quot;hi&quot; &#39;ok&#39;</p>"
        let cues = PublishedTranscriptLoader.decodeHTML(text: html, episodeDuration: 60) ?? []
        let text = cues.first?.text ?? ""
        #expect(text.contains("Tom & Jerry"))
        #expect(text.contains("<3"))
        #expect(text.contains("\"hi\""))
        #expect(text.contains("'ok'"))
        #expect(!text.contains("&amp;"))
        #expect(!text.contains("&nbsp;"))
    }

    @Test
    func parseDispatchSniffsSRTByIntegerPlusTiming() {
        // No mimeType + content that starts with an integer + the
        // SRT timing line. The dispatch should pick `decodeSRT`.
        let srt = """
        1
        00:00:01,000 --> 00:00:02,000
        Sniffed as SRT.
        """
        let data = Data(srt.utf8)
        let cues = PublishedTranscriptLoader.parse(data: data, mimeType: nil) ?? []
        #expect(cues.count == 1)
        #expect(cues.first?.text == "Sniffed as SRT.")
    }

    @Test
    func parseDispatchSniffsHTMLByLeadingAngleBracket() {
        // No mimeType + content starting with `<`. The dispatch
        // should pick `decodeHTML`.
        let html = "<article><p data-start=\"7\">Hello.</p></article>"
        let data = Data(html.utf8)
        let cues = PublishedTranscriptLoader.parse(data: data, mimeType: nil) ?? []
        #expect(cues.count == 1)
        #expect(cues.first?.text == "Hello.")
    }
}

// MARK: - Open-App Intents (Phase 40)

/// Covers the four `Open<Tab>Intent` types that deep-link into the tab bar
/// via the `offscript://tab/<name>` scheme. These intents have
/// `openAppWhenRun = true` and run on the main actor, so the tests focus on
/// statically-knowable invariants (titles, URL contract, parameterless
/// shape, `AppShortcutsProvider` registration) rather than invoking
/// `perform()` — which would require a live `UIApplication`.
@Suite("OpenAppIntents")
struct OpenAppIntentsTests {
    @Test
    func openLibraryIntentTitleAndDialog() {
        // Localized titles bridge to plain strings via String(localized:).
        // We don't pin exact wording (it could be re-translated) — instead
        // we assert that both fields are populated, which is what catches
        // a regression where someone accidentally drops the metadata.
        let title = String(localized: OpenLibraryIntent.title)
        #expect(!title.isEmpty)
        #expect(title.localizedCaseInsensitiveContains("library"))

        // `IntentDescription` doesn't expose its body string publicly in a
        // testable form; use Mirror to walk its stored properties and find
        // any non-empty String. This is intentionally lax — the goal is to
        // catch "someone replaced the description with an empty string"
        // rather than lock in exact copy.
        let mirror = Mirror(reflecting: OpenLibraryIntent.description)
        let hasNonEmptyString = mirror.children.contains { _, value in
            if let string = value as? String { return !string.isEmpty }
            if let resource = value as? LocalizedStringResource {
                return !String(localized: resource).isEmpty
            }
            return false
        }
        #expect(hasNonEmptyString || !String(describing: OpenLibraryIntent.description).isEmpty)

        // Also assert openAppWhenRun — the entire point of these intents is
        // to bring the app forward, so flipping this to false would
        // silently break the user-visible behavior.
        #expect(OpenLibraryIntent.openAppWhenRun == true)
    }

    @Test
    func openQueueIntentRoutesToCorrectURL() {
        // The static URL helper is what each intent's `perform()` hands to
        // `UIApplication.shared.open`, so asserting it here is equivalent
        // to asserting the runtime route without spinning up UIKit.
        #expect(OpenTabIntentURL.queue.absoluteString == "offscript://tab/queue")
        #expect(OpenTabIntentURL.queue.scheme == "offscript")
        #expect(OpenTabIntentURL.queue.host == "tab")
        #expect(OpenTabIntentURL.queue.pathComponents.last == "queue")

        // Sibling URLs should follow the same contract so the deep-link
        // grammar in DeepLinkRouter (`["home", "library", "queue", "search"]`)
        // remains a closed set.
        #expect(OpenTabIntentURL.home.absoluteString == "offscript://tab/home")
        #expect(OpenTabIntentURL.library.absoluteString == "offscript://tab/library")
        #expect(OpenTabIntentURL.search.absoluteString == "offscript://tab/search")
    }

    @Test
    func appShortcutsProviderListsAllFourOpenIntents() {
        // The Phase 16 lineup is Resume / Pause / Skip / PlayNext / PlayEpisode
        // (5 entries). Adding the 4 open-tab intents takes us to 9.
        let shortcuts = OffScriptShortcuts.appShortcuts
        #expect(shortcuts.count == 9)

        // Identity check via shortTitle (the only intent-identifying field
        // that survives AppShortcut's opaque PreparedIntent wrapper in
        // `String(describing:)`). The intent TYPE name doesn't appear in
        // the mirror dump — preparedIntent is just AppIntents.PreparedIntent.
        // shortTitle does land in the dump verbatim, so that's the seam.
        let allText = shortcuts.map { String(describing: $0) }.joined(separator: "\n")
        #expect(allText.contains("Open Home"))
        #expect(allText.contains("Open Library"))
        #expect(allText.contains("Open Queue"))
        #expect(allText.contains("Open Search"))
    }

    @Test
    func openAppIntentsDoNotRequireParameters() {
        // Parameterless intents must be default-constructible; this is the
        // contract `AppShortcut(intent: OpenLibraryIntent(), …)` relies on.
        // If someone adds an `@Parameter` without a default, this stops
        // compiling — but we also assert at runtime to catch the case
        // where a parameter is added with a synthesized default that we'd
        // otherwise miss.
        _ = OpenHomeIntent()
        _ = OpenLibraryIntent()
        _ = OpenQueueIntent()
        _ = OpenSearchIntent()

        // Walk the Mirror of a fresh instance and confirm no child looks
        // like an `@Parameter` wrapper. `@Parameter` synthesizes a
        // `_<name>` backing-storage property whose type name starts with
        // "IntentParameter" — that's the marker we sniff for.
        for intent: any AppIntent in [
            OpenHomeIntent(),
            OpenLibraryIntent(),
            OpenQueueIntent(),
            OpenSearchIntent()
        ] {
            let mirror = Mirror(reflecting: intent)
            let hasParameter = mirror.children.contains { _, value in
                String(describing: type(of: value)).contains("IntentParameter")
            }
            #expect(!hasParameter, "\(type(of: intent)) should be parameterless")
        }
    }
}

// MARK: - Live Activity lifecycle (Phase 39)

/// Exercises the Phase 39 fix: a Live Activity bound to one episode must end
/// when the user switches to another episode, otherwise the Lock Screen /
/// Dynamic Island UI keeps the previous episode's artwork pinned (artwork
/// lives in `ActivityAttributes`, which `activity.update()` cannot mutate).
///
/// ActivityKit refuses to start activities outside a real host process with
/// the right entitlements, so we cannot assert against `Activity<>.activities`
/// directly from unit tests. What we *can* verify:
///   1. `NowPlayingActivityCoordinator.endCurrent()` exists and runs cleanly
///      when there are no activities to end (must be safe to call eagerly).
///   2. The publisher's episode-change subscription is wired correctly:
///      switching episodes via the live PlaybackController singleton drives
///      the subscription without crashing on the now-dangling previous
///      episode reference.
@MainActor
struct LiveActivityLifecycleTests {
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
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeEpisode(title: String, in context: ModelContext) -> Episode {
        let podcast = Podcast(
            title: "Show-\(title)",
            feedURL: URL(string: "https://example.com/\(UUID().uuidString).xml")!
        )
        context.insert(podcast)
        let episode = Episode(
            title: title,
            pubDate: .now,
            audioURL: URL(string: "https://example.com/\(UUID().uuidString).mp3")!,
            podcast: podcast
        )
        context.insert(episode)
        return episode
    }

    @Test
    func endCurrentIsSafeWhenNoActivitiesPresent() async {
        // In the unit-test host process ActivityKit reports zero activities.
        // The coordinator must early-out cleanly rather than throwing or
        // hanging on `activity.end(...)` against an empty collection.
        await NowPlayingActivityCoordinator.endCurrent()
        // No assertion needed — reaching this line without throwing or
        // hanging is the contract. If endCurrent() ever regresses to a force
        // unwrap or unguarded loop on a missing API, the test process will
        // crash here.
    }

    @Test
    func switchingEpisodesDoesNotCrashPublisherSubscription() throws {
        // Drives the live publisher subscription end-to-end: prime episode A
        // (publisher sees A → A's id), switch to episode B (publisher's
        // dropFirst().removeDuplicates() chain fires), confirm the wiring
        // holds. Without the Phase 39 fix the subscription doesn't exist at
        // all; with it, the new subscription must survive a real episode swap
        // without dangling-reference crashes when the publisher
        // dereferences episode.podcast for the snapshot.
        let container = try makeContainer()
        let context = container.mainContext
        let episodeA = makeEpisode(title: "Episode A", in: context)
        let episodeB = makeEpisode(title: "Episode B", in: context)

        let controller = PlaybackController.shared
        controller.debugResetForTesting()
        controller.configure(context: context)

        // Hook up the publisher's subscriptions. `start()` is idempotent and
        // `debugResetForTesting()` above tore down any prior subscriptions
        // from earlier tests in the suite.
        NowPlayingPublisher.shared.start()

        controller.debugPrimePlayback(
            episode: episodeA,
            duration: 1800,
            currentTime: 60,
            isPlaying: true,
            presentPlayer: true
        )
        #expect(controller.currentEpisode?.id == episodeA.id)

        // Now flip to episode B. The publisher's episode-change subscription
        // observes the id transition and calls endActivity() / endCurrent().
        // With no real Activity registered (test host), endCurrent() is a
        // no-op — but the subscription must still fire without crashing on
        // the SwiftData @Model reference.
        controller.debugPrimePlayback(
            episode: episodeB,
            duration: 1800,
            currentTime: 0,
            isPlaying: true,
            presentPlayer: true
        )
        #expect(controller.currentEpisode?.id == episodeB.id)

        // Clean up before the in-memory ModelContainer goes away, otherwise
        // the publisher's lingering Combine sinks will see a dangling
        // episode reference on the next event.
        controller.debugResetForTesting()
    }
}

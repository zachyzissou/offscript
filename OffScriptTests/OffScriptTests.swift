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
        #expect(sections.flatMap(\.episodes).contains(where: { $0.id == fresh.id }) == false)
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
        #expect(sections.flatMap(\.episodes).contains(where: { $0.id == freshRandom.id }) == false)
    }

    @Test
    @MainActor
    func homeRecommendationsDoNotReturnRecencyOnlyCandidates() throws {
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

        #expect(sections.isEmpty)
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
        #expect(evidencedScore.explanation == "Latest episodes overlap your audio craft signal")
        #expect(evidencedScore.signalTrace.contains(RecommendationSignal(label: "source", value: "latest episode")))
        #expect(evidencedScore.signalTrace.contains(RecommendationSignal(label: "tags", value: "audio craft")))
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
    func recommendationExplainerRewritesGenreLaneReasonsFromTrace() {
        let reason = RecommendationExplainer.authoredReason(
            fallback: "Matches your selected technology lane",
            signals: [
                RecommendationSignal(label: "source", value: "genre"),
                RecommendationSignal(label: "lane", value: "technology")
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
                RecommendationSignal(label: "tags", value: "audio craft")
            ]
        )

        #expect(reason == "Latest episodes overlap your audio craft signal")
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
    func recommendationExplainerKeepsUnknownFallbacks() {
        let fallback = "Special editorial pick"

        let reason = RecommendationExplainer.authoredReason(
            fallback: fallback,
            signals: [RecommendationSignal(label: "source", value: "editor")]
        )

        #expect(reason == fallback)
    }

    @Test
    @MainActor
    func appSettingsRoundTripsPreferences() {
        let originalAutoPlay = AppSettings.autoPlayNext
        let originalPreferShort = AppSettings.preferShortEpisodes
        let originalDownloadedOnly = AppSettings.libraryShowDownloadedOnly
        let originalSortMode = AppSettings.librarySortMode
        let originalGenres = AppSettings.preferredGenres
        let originalRecommendationMode = AppSettings.recommendationMode

        AppSettings.autoPlayNext = false
        AppSettings.preferShortEpisodes = true
        AppSettings.libraryShowDownloadedOnly = true
        AppSettings.librarySortMode = .recentlyPlayed
        AppSettings.preferredGenres = [.technology, .newsAndPolitics]
        AppSettings.recommendationMode = .discovery

        #expect(AppSettings.autoPlayNext == false)
        #expect(AppSettings.preferShortEpisodes == true)
        #expect(AppSettings.libraryShowDownloadedOnly == true)
        #expect(AppSettings.librarySortMode == .recentlyPlayed)
        #expect(AppSettings.preferredGenres == [.technology, .newsAndPolitics])
        #expect(AppSettings.recommendationMode == .discovery)

        AppSettings.autoPlayNext = originalAutoPlay
        AppSettings.preferShortEpisodes = originalPreferShort
        AppSettings.libraryShowDownloadedOnly = originalDownloadedOnly
        AppSettings.librarySortMode = originalSortMode
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
    func libraryDirectoryOrganizerFiltersAndSortsLargeLibraries() {
        let stale = Podcast(
            title: "Stale Sync",
            author: "Ops Desk",
            feedURL: URL(string: "https://example.com/stale.xml")!,
            categories: ["News"]
        )
        stale.syncStatus = "failed"
        stale.syncFailureCount = 2

        let active = Podcast(
            title: "Audio Craft",
            author: "Studio Team",
            feedURL: URL(string: "https://example.com/audio.xml")!,
            categories: ["Technology", "Design"]
        )
        let quiet = Podcast(
            title: "Quiet Archive",
            author: "Library",
            feedURL: URL(string: "https://example.com/archive.xml")!,
            categories: ["History"]
        )

        let unplayedCounts = [active.id: 8, quiet.id: 0, stale.id: 1]
        let inProgressCounts = [active.id: 1]

        let queryFiltered = LibraryDirectoryOrganizer.filteredPodcasts(
            [stale, active, quiet],
            query: "studio",
            scope: .all,
            sort: .title,
            unplayedCounts: unplayedCounts,
            inProgressCounts: inProgressCounts
        )
        #expect(queryFiltered.map(\.title) == ["Audio Craft"])

        let attentionSorted = LibraryDirectoryOrganizer.filteredPodcasts(
            [quiet, active, stale],
            query: "",
            scope: .all,
            sort: .attention,
            unplayedCounts: unplayedCounts,
            inProgressCounts: inProgressCounts
        )
        #expect(attentionSorted.map(\.title) == ["Stale Sync", "Audio Craft", "Quiet Archive"])

        let inProgressOnly = LibraryDirectoryOrganizer.filteredPodcasts(
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
    @MainActor
    func libraryDirectoryOrganizerBuildsAlphabetSections() {
        let numeric = Podcast(title: "99 Invisible", feedURL: URL(string: "https://example.com/99.xml")!)
        let alpha = Podcast(title: "Audio Craft", feedURL: URL(string: "https://example.com/audio.xml")!)
        let beta = Podcast(title: "Beta Feed", feedURL: URL(string: "https://example.com/beta.xml")!)

        let sections = LibraryDirectoryOrganizer.sections(for: [numeric, alpha, beta])

        #expect(sections.map(\.title) == ["A", "B", "#"])
        #expect(sections.flatMap(\.podcasts).map(\.title) == ["Audio Craft", "Beta Feed", "99 Invisible"])
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
        #expect(podcast.syncStatus == "syncing")
        #expect(podcast.lastSyncAttemptAt != nil)
        #expect(podcast.syncErrorMessage == nil)
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

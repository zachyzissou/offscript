# Onboarding Overhaul Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the static informational onboarding with an interactive multi-step flow: Sign in with Apple → genre picker → podcast picker (curated + live) → feed import with taste profiling — so users land on a populated, personalized Home feed.

**Architecture:** A step-based `OnboardingFlowView` manages four screens. Each screen collects a signal (identity, genres, podcast selections) that feeds downstream. The existing `FeedSyncService` and `TopicExtractionService` handle all import and enrichment. A curated podcast catalog provides instant content, supplemented by live results from Apple's RSS Feed Generator API.

**Tech Stack:** SwiftUI, AuthenticationServices, Keychain Services, SwiftData, Apple RSS Feed Generator API, existing FeedSyncService/TopicExtractionService/RecommendationService

**Spec:** `docs/superpowers/specs/2026-03-17-onboarding-overhaul-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| **Create:** `OffScript/CuratedPodcastCatalog.swift` | `Genre` enum with Apple genre IDs + hardcoded curated podcast entries as `PodcastSearchResult` |
| **Create:** `OffScript/UserProfileService.swift` | Keychain read/write for Apple ID credential (enum with static methods) |
| **Create:** `OffScript/OnboardingFlowView.swift` | Multi-step container: manages `@State var step`, renders correct screen per step |
| **Create:** `OffScript/GenrePickerView.swift` | Screen 2: tappable genre grid, passes selections forward |
| **Create:** `OffScript/PodcastPickerView.swift` | Screen 3: genre-filtered rails of curated + live podcasts, selection tracking |
| **Create:** `OffScript/ImportProgressView.swift` | Screen 4: sequential import with per-podcast progress, taste seeding |
| **Modify:** `OffScript/ContentView.swift` | Swap `OnboardingView` → `OnboardingFlowView`, remove `SampleDataSeeder` call |
| **Modify:** `OffScript/PodcastServices.swift` | Remove `SampleDataSeeder` enum (lines 226-315) |
| **Modify:** `OffScript/RecommendationService.swift` | Add genre preference boost to scoring |
| **Delete:** `OffScript/OnboardingView.swift` | Replaced by `OnboardingFlowView` + sub-views |
| **Modify:** `OffScriptTests/OffScriptTests.swift` | Add tests for `Genre`, `CuratedPodcastCatalog`, `UserProfileService` |

---

### Task 1: Genre Enum + Curated Podcast Catalog

The foundation data layer — no UI, no network. Everything else depends on this.

**Files:**
- Create: `OffScript/CuratedPodcastCatalog.swift`
- Modify: `OffScriptTests/OffScriptTests.swift`

- [ ] **Step 1: Write tests for Genre enum and catalog**

Add to `OffScriptTests/OffScriptTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme OffScript -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OffScriptTests 2>&1 | tail -20`
Expected: FAIL — `Genre` and `CuratedPodcastCatalog` not found

- [ ] **Step 3: Implement Genre enum and CuratedPodcastCatalog**

Create `OffScript/CuratedPodcastCatalog.swift`:

```swift
import Foundation

enum Genre: String, CaseIterable, Identifiable {
    case technology
    case cultureAndSociety
    case comedy
    case trueCrime
    case newsAndPolitics
    case science
    case business
    case healthAndWellness
    case sports
    case music
    case history
    case education

    var id: String { rawValue }

    var title: String {
        switch self {
        case .technology: return "Technology"
        case .cultureAndSociety: return "Culture & Society"
        case .comedy: return "Comedy"
        case .trueCrime: return "True Crime"
        case .newsAndPolitics: return "News & Politics"
        case .science: return "Science"
        case .business: return "Business"
        case .healthAndWellness: return "Health & Wellness"
        case .sports: return "Sports"
        case .music: return "Music"
        case .history: return "History"
        case .education: return "Education"
        }
    }

    var systemImage: String {
        switch self {
        case .technology: return "cpu"
        case .cultureAndSociety: return "globe.americas"
        case .comedy: return "face.smiling"
        case .trueCrime: return "magnifyingglass"
        case .newsAndPolitics: return "newspaper"
        case .science: return "atom"
        case .business: return "chart.line.uptrend.xyaxis"
        case .healthAndWellness: return "heart"
        case .sports: return "sportscourt"
        case .music: return "music.note"
        case .history: return "clock.arrow.circlepath"
        case .education: return "graduationcap"
        }
    }

    /// Apple Podcasts genre ID for the RSS Feed Generator API
    var appleGenreID: Int {
        switch self {
        case .technology: return 1318
        case .cultureAndSociety: return 1324
        case .comedy: return 1303
        case .trueCrime: return 1488
        case .newsAndPolitics: return 1489
        case .science: return 1533
        case .business: return 1321
        case .healthAndWellness: return 1512
        case .sports: return 1545
        case .music: return 1310
        case .history: return 1487
        case .education: return 1304
        }
    }
}

enum CuratedPodcastCatalog {
    /// All curated podcasts across all genres
    static var all: [PodcastSearchResult] {
        Genre.allCases.flatMap { podcasts(for: $0) }
    }

    /// Curated podcasts for a specific genre
    static func podcasts(for genre: Genre) -> [PodcastSearchResult] {
        switch genre {
        case .technology:
            return [
                entry(title: "Lex Fridman Podcast", author: "Lex Fridman", feed: "https://lexfridman.com/feed/podcast/", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts125/v4/c3/9d/e3/c39de370-3dfc-2a36-0a0d-09da0f0f2fb5/mza_7055951557267025897.jpg/600x600bb.jpg"),
                entry(title: "Acquired", author: "Ben Gilbert & David Rosenthal", feed: "https://feeds.pacific-content.com/acquired", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/a2/ab/fd/a2abfdb0-a0c4-1aab-400a-2a57a6d1a498/mza_10068498047498498498.jpg/600x600bb.jpg"),
                entry(title: "The Vergecast", author: "The Verge", feed: "https://feeds.megaphone.fm/vergecast", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/3d/f0/2c/3df02cdb-e857-3c3c-3f37-a0a3c1fba498/mza_17343223853483629612.jpg/600x600bb.jpg"),
                entry(title: "Accidental Tech Podcast", author: "Marco Arment, Casey Liss, John Siracusa", feed: "https://atp.fm/episodes?format=rss", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/20/42/52/204252e6-0b74-5fa5-3e65-8c64b5f2f93c/mza_8438045701290662498.png/600x600bb.jpg"),
            ]
        case .cultureAndSociety:
            return [
                entry(title: "Radiolab", author: "WNYC Studios", feed: "https://feeds.simplecast.com/EmVW7VGp", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/91/3d/e5/913de51c-9358-8a99-5a82-99a2c3e5d7e9/mza_15932833847498327798.jpg/600x600bb.jpg"),
                entry(title: "99% Invisible", author: "Roman Mars", feed: "https://feeds.simplecast.com/BqbsxVfO", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/2b/69/d7/2b69d7e5-62c3-97ba-a4de-61e0e5acf5d4/mza_9289093033793017447.jpg/600x600bb.jpg"),
                entry(title: "Freakonomics Radio", author: "Freakonomics Radio + Stitcher", feed: "https://feeds.simplecast.com/Y8lFbOT4", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts125/v4/9a/55/75/9a5575e0-4af5-ab29-7894-5d6c0b3cd55e/mza_7565089999152753446.jpg/600x600bb.jpg"),
                entry(title: "This American Life", author: "This American Life", feed: "https://www.thisamericanlife.org/podcast/rss.xml", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/41/87/4e/41874eed-6b53-3e75-f2a0-d0188a6bf3f5/mza_5763994068438908376.jpg/600x600bb.jpg"),
            ]
        case .comedy:
            return [
                entry(title: "Conan O'Brien Needs a Friend", author: "Team Coco & Earwolf", feed: "https://feeds.simplecast.com/dHoohVNH", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/4e/c8/72/4ec87247-8e49-6b73-1be3-a3e6b3b5adf7/mza_3340978315797574212.jpg/600x600bb.jpg"),
                entry(title: "SmartLess", author: "Jason Bateman, Sean Hayes, Will Arnett", feed: "https://feeds.simplecast.com/zt3mMlMD", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/d7/d6/51/d7d651b6-5cb0-ae64-adc1-eb5dc13e2780/mza_16991829328888412991.jpg/600x600bb.jpg"),
                entry(title: "Pardon My Take", author: "Barstool Sports", feed: "https://mcsorleys.barstoolsports.com/feed/pardon-my-take", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/e8/5b/c1/e85bc167-3945-1b08-7526-e7c0cf73c14a/mza_2987826474137463792.jpg/600x600bb.jpg"),
            ]
        case .trueCrime:
            return [
                entry(title: "Serial", author: "Serial Productions & The New York Times", feed: "https://feeds.simplecast.com/xl36XBC2", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/30/a8/5b/30a85b9e-1dfe-0a74-5d8a-2c4e0fbfb157/mza_10796879403498698704.jpg/600x600bb.jpg"),
                entry(title: "Crime Junkie", author: "audiochuck", feed: "https://feeds.simplecast.com/qm_9xx0g", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/d7/c0/34/d7c03431-1bbd-d73a-33ef-fd3337b2b3fb/mza_3052451586876927082.jpg/600x600bb.jpg"),
                entry(title: "Casefile True Crime", author: "Casefile Presents", feed: "https://audioboom.com/channels/4998987.rss", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/28/d1/61/28d16155-eda0-0e5a-fa48-b1fa16c9e5ba/mza_15483003543698968893.jpg/600x600bb.jpg"),
            ]
        case .newsAndPolitics:
            return [
                entry(title: "The Daily", author: "The New York Times", feed: "https://feeds.simplecast.com/54nAGcIl", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/43/47/31/434731c3-6e64-3d4f-b809-f5e3f0d3ab42/mza_9085813861285268024.jpg/600x600bb.jpg"),
                entry(title: "Pod Save America", author: "Crooked Media", feed: "https://feeds.megaphone.fm/pod-save-america", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/4a/72/90/4a7290e4-dcfd-1a81-3f08-dfd0c5fc4d22/mza_12018119764198490497.jpg/600x600bb.jpg"),
                entry(title: "Up First", author: "NPR", feed: "https://feeds.npr.org/510318/podcast.xml", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/56/6f/7f/566f7f50-2d70-5c3a-2b4e-78a78f953e94/mza_15491610645704370757.jpg/600x600bb.jpg"),
            ]
        case .science:
            return [
                entry(title: "Huberman Lab", author: "Scicomm Media", feed: "https://feeds.megaphone.fm/hubermanlab", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/3e/3f/7c/3e3f7c42-6a32-98df-8c25-e48eb9c0a9ee/mza_15060074375674713297.jpg/600x600bb.jpg"),
                entry(title: "StarTalk Radio", author: "Neil deGrasse Tyson", feed: "https://feeds.simplecast.com/4T39_jAj", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts125/v4/72/c2/8c/72c28c24-73d5-b8b5-e83b-c2b19fcdcfbf/mza_6985883752087901871.jpg/600x600bb.jpg"),
                entry(title: "Science Vs", author: "Spotify Studios", feed: "https://feeds.megaphone.fm/sciencevs", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/ee/c9/f3/eec9f3b7-c8e0-06f8-7ee5-d4cd11d00d26/mza_12741548736685082927.jpg/600x600bb.jpg"),
            ]
        case .business:
            return [
                entry(title: "How I Built This", author: "Guy Raz | Wondery", feed: "https://feeds.npr.org/510313/podcast.xml", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/2e/41/5c/2e415c44-f9a6-f63c-7c93-a2f3e4b7f8c8/mza_14175099654781143544.jpg/600x600bb.jpg"),
                entry(title: "The Prof G Pod", author: "Vox Media Podcast Network", feed: "https://feeds.megaphone.fm/profgpod", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/fa/da/70/fada700a-e80f-3b7c-3e37-bf53d0c1db72/mza_11479685143587654563.jpg/600x600bb.jpg"),
                entry(title: "Masters of Scale", author: "WaitWhat", feed: "https://rss.art19.com/masters-of-scale", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/a0/d5/1a/a0d51a51-b2fc-3f29-6a04-dbd55f52a1df/mza_13879992792979527808.jpg/600x600bb.jpg"),
            ]
        case .healthAndWellness:
            return [
                entry(title: "The Peter Attia Drive", author: "Peter Attia, MD", feed: "https://peterattiadrive.libsyn.com/rss", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/14/37/de/1437de33-2d80-a8e1-df4f-9aa5d0f0fa3a/mza_11994272752327478347.jpg/600x600bb.jpg"),
                entry(title: "Ten Percent Happier", author: "Dan Harris", feed: "https://feeds.megaphone.fm/ten-percent-happier", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/4c/e4/31/4ce431c5-d7c0-6e7c-d7a0-5c97f3fb7417/mza_7085935429645287174.jpg/600x600bb.jpg"),
                entry(title: "On Purpose with Jay Shetty", author: "Jay Shetty", feed: "https://feeds.simplecast.com/xRbIdeRv", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/68/3c/c4/683cc4eb-6d79-e382-ed64-6c787e7e8a93/mza_12990568032890389939.jpg/600x600bb.jpg"),
            ]
        case .sports:
            return [
                entry(title: "The Bill Simmons Podcast", author: "The Ringer", feed: "https://feeds.megaphone.fm/the-bill-simmons-podcast", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/38/4a/f0/384af066-76b6-b2d6-0e37-c1a3c2bf7c59/mza_4920670993482505526.jpg/600x600bb.jpg"),
                entry(title: "New Heights", author: "Wave Sports + Entertainment", feed: "https://feeds.megaphone.fm/new-heights", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/be/75/b0/be75b0c0-0adf-3d22-3f00-58e87d7aed76/mza_14979479490899677635.jpg/600x600bb.jpg"),
            ]
        case .music:
            return [
                entry(title: "Dissect", author: "Spotify Studios", feed: "https://feeds.megaphone.fm/dissect", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/3f/c5/1c/3fc51c60-61e6-e8ab-8ab1-9cf6f6b6cbf3/mza_3459975193367749249.jpg/600x600bb.jpg"),
                entry(title: "Song Exploder", author: "Hrishikesh Hirway", feed: "https://feed.songexploder.net/SongExploder", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/90/34/6f/90346f64-d5b6-fc1c-4e28-ad6f2a60aa5e/mza_15087641671946791407.jpg/600x600bb.jpg"),
                entry(title: "Broken Record", author: "Pushkin Industries", feed: "https://feeds.megaphone.fm/broken-record", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/a0/71/39/a0713904-0b3a-8e68-c795-e53bc7f2d08b/mza_4775695803207862497.jpg/600x600bb.jpg"),
            ]
        case .history:
            return [
                entry(title: "Hardcore History", author: "Dan Carlin", feed: "https://feeds.feedburner.com/dancarlin/history", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts125/v4/5e/35/03/5e350305-0845-7eaa-0c92-b1b5d5d38cbe/mza_12567987073499596219.jpg/600x600bb.jpg"),
                entry(title: "Revisionist History", author: "Pushkin Industries", feed: "https://feeds.megaphone.fm/revisionisthistory", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts125/v4/68/62/7f/68627fda-0dd7-b8f7-b6a3-c27e04e9f9ec/mza_17291218380425000798.jpg/600x600bb.jpg"),
                entry(title: "The Rest Is History", author: "Goalhanger Podcasts", feed: "https://feeds.megaphone.fm/the-rest-is-history", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/f6/73/b0/f673b02c-1a94-6caa-c4d3-03ea0d26ac27/mza_12636953965508907982.jpg/600x600bb.jpg"),
            ]
        case .education:
            return [
                entry(title: "TED Radio Hour", author: "NPR", feed: "https://feeds.npr.org/510298/podcast.xml", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/49/a6/05/49a60584-5a3c-af67-0262-ff5fb3079370/mza_16853948296583403669.jpg/600x600bb.jpg"),
                entry(title: "Hidden Brain", author: "Shankar Vedantam", feed: "https://feeds.simplecast.com/kwWc0lhf", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/06/f5/74/06f574c7-a575-52c0-c4d1-a7cfe2addc07/mza_16375498632764614517.jpg/600x600bb.jpg"),
                entry(title: "Stuff You Should Know", author: "iHeartPodcasts", feed: "https://feeds.megaphone.fm/stuffyoushouldknow", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/59/e3/fc/59e3fc55-b0ca-3b00-8242-d06f1bbd9338/mza_13487802947062498030.jpg/600x600bb.jpg"),
            ]
        }
    }

    private static func entry(title: String, author: String, feed: String, artwork: String) -> PodcastSearchResult {
        PodcastSearchResult(
            title: title,
            author: author,
            feedURL: URL(string: feed)!,
            artworkURL: URL(string: artwork),
            websiteURL: nil,
            summary: nil
        )
    }
}
```

**Important:** The feed URLs and artwork URLs above are best-effort. After creating the file, verify a few by spot-checking in a browser (e.g., open the feed URL — it should return XML). If any are broken, look up the correct feed URL via iTunes Search API: `https://itunes.apple.com/search?term=PODCAST_NAME&media=podcast&entity=podcast&limit=1` and use the `feedUrl` and `artworkUrl600` from the response.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme OffScript -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OffScriptTests 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add OffScript/CuratedPodcastCatalog.swift OffScriptTests/OffScriptTests.swift
git commit -m "feat: add Genre enum and CuratedPodcastCatalog with real podcast feed URLs"
```

---

### Task 2: UserProfileService (Keychain wrapper)

Keychain-backed storage for Sign in with Apple credentials. Enum with static methods matching the `QueueService` pattern.

**Files:**
- Create: `OffScript/UserProfileService.swift`
- Modify: `OffScriptTests/OffScriptTests.swift`

- [ ] **Step 1: Write tests for UserProfileService**

Add to `OffScriptTests/OffScriptTests.swift`:

```swift
@Test
func userProfileServiceRoundTrips() throws {
    // Clean up any existing test data
    UserProfileService.deleteCredential()

    #expect(UserProfileService.currentUserID == nil)
    #expect(UserProfileService.displayName == nil)

    try UserProfileService.saveCredential(userID: "test-user-123", displayName: "Zach")

    #expect(UserProfileService.currentUserID == "test-user-123")
    #expect(UserProfileService.displayName == "Zach")

    UserProfileService.deleteCredential()
    #expect(UserProfileService.currentUserID == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `UserProfileService` not found

- [ ] **Step 3: Implement UserProfileService**

Create `OffScript/UserProfileService.swift`:

```swift
import Foundation
import Security

enum UserProfileService {
    private static let serviceName = "com.offscript.apple-id"
    private static let userIDKey = "userIdentifier"
    private static let displayNameKey = "offscript.displayName"

    static var currentUserID: String? {
        readKeychain(account: userIDKey)
    }

    static var displayName: String? {
        get { UserDefaults.standard.string(forKey: displayNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: displayNameKey) }
    }

    static func saveCredential(userID: String, displayName: String?) throws {
        try writeKeychain(account: userIDKey, value: userID)
        if let displayName {
            self.displayName = displayName
        }
    }

    static func deleteCredential() {
        deleteKeychain(account: userIDKey)
        UserDefaults.standard.removeObject(forKey: displayNameKey)
    }

    // MARK: - Keychain Helpers

    private static func writeKeychain(account: String, value: String) throws {
        let data = Data(value.utf8)
        deleteKeychain(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    private static func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error {
        case unhandled(OSStatus)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Expected: All tests PASS (Note: Keychain tests require running on a simulator or device, not just building)

- [ ] **Step 5: Commit**

```bash
git add OffScript/UserProfileService.swift OffScriptTests/OffScriptTests.swift
git commit -m "feat: add UserProfileService with Keychain-backed Apple ID storage"
```

---

### Task 3: OnboardingFlowView (multi-step container)

The container view that manages step-based navigation between the four onboarding screens.

**Files:**
- Create: `OffScript/OnboardingFlowView.swift`

- [ ] **Step 1: Create OnboardingFlowView with step navigation**

Create `OffScript/OnboardingFlowView.swift`:

```swift
import SwiftUI

struct OnboardingFlowView: View {
    @AppStorage("offscript.hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var step = 0
    @State private var selectedGenres: Set<Genre> = []
    @State private var selectedPodcasts: [PodcastSearchResult] = []

    var body: some View {
        ZStack {
            // Atmospheric background (shared across all steps)
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.06, blue: 0.04),
                    Color.offscriptBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.offscriptAccent.opacity(0.08), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 400
            )
            .ignoresSafeArea()

            switch step {
            case 0:
                welcomeScreen
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case 1:
                GenrePickerView(
                    selectedGenres: $selectedGenres,
                    onContinue: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 2 } },
                    onBack: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 0 } }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            case 2:
                PodcastPickerView(
                    selectedGenres: selectedGenres,
                    onContinue: { podcasts in
                        selectedPodcasts = podcasts
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 3 }
                    },
                    onBack: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 1 } }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            case 3:
                ImportProgressView(
                    podcasts: selectedPodcasts,
                    selectedGenres: selectedGenres,
                    onComplete: { hasSeenOnboarding = true }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            default:
                EmptyView()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
    }

    private var welcomeScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Spacer(minLength: 60)

                VStack(alignment: .leading, spacing: 18) {
                    Text("OffScript")
                        .font(.system(size: 46, weight: .bold, design: .serif))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.offscriptTextPrimary, Color.offscriptAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .staggeredEntrance(index: 0, delay: 0.12)

                    Text("Podcasts that feel curated,\nnot algorithmic.")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .staggeredEntrance(index: 1, delay: 0.12)

                    Text("OffScript learns from a few good picks to build a feed that feels edited — not endless.")
                        .font(.offscriptBody)
                        .foregroundStyle(Color.offscriptTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .staggeredEntrance(index: 2, delay: 0.12)
                }

                VStack(spacing: 12) {
                    SignInWithAppleSection(onComplete: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 1 }
                    })
                    .staggeredEntrance(index: 3, delay: 0.12)

                    Button("Skip for now") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 1 }
                    }
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextMuted)
                    .staggeredEntrance(index: 4, delay: 0.12)
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 24)
        }
    }
}

private struct SignInWithAppleSection: View {
    let onComplete: () -> Void

    var body: some View {
        // Sign in with Apple button
        SignInWithAppleButtonView(onComplete: onComplete)
            .frame(height: 52)
    }
}
```

- [ ] **Step 2: Create the Sign in with Apple button wrapper**

Add to the bottom of `OnboardingFlowView.swift` (and add `import AuthenticationServices` at the top of the file alongside the existing `import SwiftUI`):

```swift
private struct SignInWithAppleButtonView: UIViewRepresentable {
    let onComplete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .white)
        button.cornerRadius = 18
        button.addTarget(context.coordinator, action: #selector(Coordinator.handleSignIn), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}

    final class Coordinator: NSObject, ASAuthorizationControllerDelegate {
        let onComplete: () -> Void

        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }

        @objc func handleSignIn() {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.performRequests()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                let displayName = [credential.fullName?.givenName, credential.fullName?.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                try? UserProfileService.saveCredential(
                    userID: credential.user,
                    displayName: displayName.isEmpty ? nil : displayName
                )
            }
            onComplete()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            // User cancelled or error — just proceed without identity
            onComplete()
        }
    }
}
```

**Important:** The views referenced in `OnboardingFlowView` (`GenrePickerView`, `PodcastPickerView`, `ImportProgressView`) don't exist yet. Add placeholder stubs at the bottom of the file to unblock compilation — they'll be replaced by dedicated files in subsequent tasks:

```swift
// MARK: - Placeholder stubs (will be replaced by dedicated files)
struct GenrePickerView: View {
    @Binding var selectedGenres: Set<Genre>
    let onContinue: () -> Void
    let onBack: () -> Void
    var body: some View { Text("Genre Picker") }
}

struct PodcastPickerView: View {
    let selectedGenres: Set<Genre>
    let onContinue: ([PodcastSearchResult]) -> Void
    let onBack: () -> Void
    var body: some View { Text("Podcast Picker") }
}

struct ImportProgressView: View {
    let podcasts: [PodcastSearchResult]
    let selectedGenres: Set<Genre>
    let onComplete: () -> Void
    var body: some View { Text("Import Progress") }
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild build -scheme OffScript -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add OffScript/OnboardingFlowView.swift
git commit -m "feat: add OnboardingFlowView with step navigation and Sign in with Apple"
```

---

### Task 4: GenrePickerView (Screen 2)

Interactive genre grid with toggle selection. Remove the placeholder stub from Task 3.

**Files:**
- Create: `OffScript/GenrePickerView.swift`
- Modify: `OffScript/OnboardingFlowView.swift` (remove GenrePickerView placeholder stub)

- [ ] **Step 1: Create GenrePickerView**

Create `OffScript/GenrePickerView.swift`:

```swift
import SwiftUI

struct GenrePickerView: View {
    @Binding var selectedGenres: Set<Genre>
    let onContinue: () -> Void
    let onBack: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What are you into?")
                            .font(.system(.title, design: .serif, weight: .bold))
                            .foregroundStyle(Color.offscriptTextPrimary)
                            .staggeredEntrance(index: 0)

                        Text("Pick a few — we'll use these to find shows you'll actually listen to.")
                            .font(.offscriptBody)
                            .foregroundStyle(Color.offscriptTextSecondary)
                            .staggeredEntrance(index: 1)
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(Genre.allCases.enumerated()), id: \.element.id) { index, genre in
                            GenreCard(
                                genre: genre,
                                isSelected: selectedGenres.contains(genre),
                                onTap: { toggleGenre(genre) }
                            )
                            .staggeredEntrance(index: index + 2)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 120)
            }

            // Bottom bar
            VStack(spacing: 12) {
                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(OnboardingContinueButtonStyle())

                Button("Back") { onBack() }
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextMuted)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                Color.offscriptBackground.opacity(0.95)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    private func toggleGenre(_ genre: Genre) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            if selectedGenres.contains(genre) {
                selectedGenres.remove(genre)
            } else {
                selectedGenres.insert(genre)
            }
        }
    }

}

private struct GenreCard: View {
    let genre: Genre
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: genre.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.offscriptAccent : Color.offscriptTextSecondary)

                Text(genre.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.offscriptTextPrimary : Color.offscriptTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 90)
            .background(isSelected ? Color.offscriptAccentSoft : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                    .stroke(isSelected ? Color.offscriptAccent : Color.offscriptHairline, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isSelected)
        .accessibilityLabel("\(genre.title)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct OnboardingContinueButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.offscriptAccent)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.97 : 1.0))
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
```

- [ ] **Step 2: Remove GenrePickerView placeholder stub from OnboardingFlowView.swift**

Remove the `struct GenrePickerView` placeholder stub at the bottom of `OnboardingFlowView.swift`.

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild build -scheme OffScript -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add OffScript/GenrePickerView.swift OffScript/OnboardingFlowView.swift
git commit -m "feat: add GenrePickerView with interactive genre grid"
```

---

### Task 5: PodcastPickerView (Screen 3)

Genre-filtered horizontal rails of curated + live podcasts with selection tracking. This is the most complex UI screen.

**Files:**
- Create: `OffScript/PodcastPickerView.swift`
- Modify: `OffScript/OnboardingFlowView.swift` (remove PodcastPickerView placeholder stub)
- Modify: `OffScript/PodcastServices.swift` (add `TopPodcastsService` for Apple RSS Feed Generator API)

- [ ] **Step 1: Add TopPodcastsService for live genre fetching**

Add to `OffScript/PodcastServices.swift` (after `PodcastSearchService`, before `FeedSyncService`):

```swift
enum TopPodcastsService {
    /// Fetches top podcasts for a genre from Apple's RSS Feed Generator API,
    /// then resolves actual RSS feed URLs via iTunes Lookup API.
    /// Returns empty array on failure (curated catalog is the fallback).
    static func fetchTop(genre: Genre, limit: Int = 10) async -> [PodcastSearchResult] {
        let urlString = "https://rss.applemarketingtools.com/api/v2/us/podcasts/top/\(limit)/genre=\(genre.appleGenreID)/json"
        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(AppleRSSFeedResponse.self, from: data)

            // The RSS Feed Generator returns iTunes Store URLs, not RSS feed URLs.
            // We need to resolve feed URLs via iTunes Lookup API using the podcast ID.
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

    /// Resolves the actual RSS feed URL for a podcast via the iTunes Lookup API.
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
```

- [ ] **Step 2: Create PodcastPickerView**

Create `OffScript/PodcastPickerView.swift`:

```swift
import SwiftUI

struct PodcastPickerView: View {
    let selectedGenres: Set<Genre>
    let onContinue: ([PodcastSearchResult]) -> Void
    let onBack: () -> Void

    @State private var selectedFeeds: Set<URL> = []
    @State private var livePodcasts: [Genre: [PodcastSearchResult]] = [:]
    @State private var allPodcasts: [PodcastSearchResult] = []

    private var prioritizedGenres: [Genre] {
        let selected = Genre.allCases.filter { selectedGenres.contains($0) }
        let rest = Genre.allCases.filter { !selectedGenres.contains($0) }
        return selected + rest
    }

    private var canContinue: Bool { selectedFeeds.count >= 3 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pick 3+ shows to build your feed")
                            .font(.system(.title, design: .serif, weight: .bold))
                            .foregroundStyle(Color.offscriptTextPrimary)

                        Text("We'll subscribe you and start learning your taste.")
                            .font(.offscriptBody)
                            .foregroundStyle(Color.offscriptTextSecondary)
                    }
                    .padding(.horizontal, 24)

                    ForEach(prioritizedGenres) { genre in
                        let podcasts = mergedPodcasts(for: genre)
                        if !podcasts.isEmpty {
                            PodcastGenreRail(
                                genre: genre,
                                podcasts: podcasts,
                                selectedFeeds: $selectedFeeds,
                                showExploreHeader: !selectedGenres.isEmpty && !selectedGenres.contains(genre)
                            )
                        }
                    }
                }
                .padding(.top, 32)
                .padding(.bottom, 120)
            }

            // Bottom bar with selection count
            VStack(spacing: 12) {
                Button {
                    let selected = allPodcasts.filter { selectedFeeds.contains($0.feedURL) }
                    onContinue(selected)
                } label: {
                    HStack {
                        Text("Continue")
                        if !selectedFeeds.isEmpty {
                            Text("(\(selectedFeeds.count))")
                                .fontWeight(.bold)
                        }
                    }
                }
                .buttonStyle(OnboardingContinueButtonStyle())
                .disabled(!canContinue)
                .opacity(canContinue ? 1.0 : 0.5)

                if !canContinue {
                    Text("Pick \(max(0, 3 - selectedFeeds.count)) more")
                        .font(.offscriptMeta)
                        .foregroundStyle(Color.offscriptTextMuted)
                }

                Button("Back") { onBack() }
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextMuted)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                Color.offscriptBackground.opacity(0.95)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .task { await loadLivePodcasts() }
    }

    private func mergedPodcasts(for genre: Genre) -> [PodcastSearchResult] {
        let curated = CuratedPodcastCatalog.podcasts(for: genre)
        let live = livePodcasts[genre] ?? []
        let curatedURLs = Set(curated.map(\.feedURL))
        let deduped = live.filter { !curatedURLs.contains($0.feedURL) }
        return curated + deduped
    }

    @MainActor
    private func loadLivePodcasts() async {
        // Build the full list of all curated podcasts for selection lookup
        allPodcasts = CuratedPodcastCatalog.all

        // Fetch live results per genre (prioritize selected genres)
        for genre in prioritizedGenres {
            let results = await TopPodcastsService.fetchTop(genre: genre, limit: 8)
            if !results.isEmpty {
                livePodcasts[genre] = results
                // Update allPodcasts with any new live entries
                let existingURLs = Set(allPodcasts.map(\.feedURL))
                let newEntries = results.filter { !existingURLs.contains($0.feedURL) }
                allPodcasts.append(contentsOf: newEntries)
            }
        }
    }
}

private struct PodcastGenreRail: View {
    let genre: Genre
    let podcasts: [PodcastSearchResult]
    @Binding var selectedFeeds: Set<URL>
    let showExploreHeader: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showExploreHeader {
                Text("Explore More")
                    .font(.offscriptMicro.weight(.semibold))
                    .foregroundStyle(Color.offscriptTextMuted)
                    .padding(.horizontal, 24)
            }

            Text(genre.title)
                .font(.offscriptSectionTitle)
                .foregroundStyle(Color.offscriptTextPrimary)
                .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(podcasts, id: \.feedURL) { podcast in
                        OnboardingPodcastCard(
                            podcast: podcast,
                            isSelected: selectedFeeds.contains(podcast.feedURL),
                            onTap: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                    if selectedFeeds.contains(podcast.feedURL) {
                                        selectedFeeds.remove(podcast.feedURL)
                                    } else {
                                        selectedFeeds.insert(podcast.feedURL)
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

private struct OnboardingPodcastCard: View {
    let podcast: PodcastSearchResult
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    OffScriptArtworkView(
                        url: podcast.artworkURL,
                        cornerRadius: OffScriptTheme.Radius.medium
                    )
                    .frame(width: 120, height: 120)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.offscriptAccent)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                            .padding(6)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                        .stroke(isSelected ? Color.offscriptAccent : Color.clear, lineWidth: 2)
                )

                Text(podcast.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(podcast.author)
                    .font(.caption2)
                    .foregroundStyle(Color.offscriptTextMuted)
                    .lineLimit(1)
            }
            .frame(width: 120)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isSelected)
        .accessibilityLabel("\(podcast.title) by \(podcast.author)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
```

- [ ] **Step 3: Remove PodcastPickerView placeholder stub from OnboardingFlowView.swift**

Remove the `struct PodcastPickerView` placeholder stub at the bottom of `OnboardingFlowView.swift`.

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild build -scheme OffScript -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add OffScript/PodcastPickerView.swift OffScript/PodcastServices.swift OffScript/OnboardingFlowView.swift
git commit -m "feat: add PodcastPickerView with curated + live genre rails"
```

---

### Task 6: ImportProgressView (Screen 4)

Sequential import with per-podcast progress indicators and taste profile seeding.

**Files:**
- Create: `OffScript/ImportProgressView.swift`
- Modify: `OffScript/OnboardingFlowView.swift` (remove ImportProgressView placeholder stub)

- [ ] **Step 1: Create ImportProgressView**

Create `OffScript/ImportProgressView.swift`:

```swift
import SwiftData
import SwiftUI

struct ImportProgressView: View {
    @Environment(\.modelContext) private var modelContext

    let podcasts: [PodcastSearchResult]
    let selectedGenres: Set<Genre>
    let onComplete: () -> Void

    @State private var statuses: [URL: ImportStatus] = [:]
    @State private var isComplete = false

    enum ImportStatus {
        case pending
        case importing
        case done
        case failed
    }

    private let syncService = FeedSyncService()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 14) {
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.offscriptAccent)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Color.offscriptAccent)
                }

                Text(isComplete ? "Your feed is ready" : "Building your feed...")
                    .font(.system(.title2, design: .serif, weight: .bold))
                    .foregroundStyle(Color.offscriptTextPrimary)

                Text(isComplete ? "Head in — your recommendations are waiting." : "Fetching episodes and learning your taste...")
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                ForEach(podcasts, id: \.feedURL) { podcast in
                    ImportRow(
                        podcast: podcast,
                        status: statuses[podcast.feedURL] ?? .pending
                    )
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .task {
            await runImports()
        }
    }

    @MainActor
    private func runImports() async {
        for podcast in podcasts {
            statuses[podcast.feedURL] = .importing

            do {
                let imported = try await syncService.importPodcast(from: podcast, into: modelContext)

                // Seed taste: like the most recent episode
                if let newestEpisode = imported.episodes
                    .sorted(by: { $0.pubDate > $1.pubDate })
                    .first {
                    let signal = PreferenceSignal(action: .like, episode: newestEpisode)
                    modelContext.insert(signal)
                    try? modelContext.save()
                }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    statuses[podcast.feedURL] = .done
                }
            } catch {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    statuses[podcast.feedURL] = .failed
                }
            }
        }

        // Persist genre preferences
        let genreStrings = selectedGenres.map(\.rawValue)
        UserDefaults.standard.set(genreStrings, forKey: "offscript.preferredGenres")

        // Brief pause to show completion state
        try? await Task.sleep(for: .seconds(1.2))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isComplete = true
        }

        // Auto-advance after a beat — notify parent to set hasSeenOnboarding
        try? await Task.sleep(for: .seconds(1.5))
        onComplete()
    }
}

private struct ImportRow: View {
    let podcast: PodcastSearchResult
    let status: ImportProgressView.ImportStatus

    var body: some View {
        HStack(spacing: 14) {
            OffScriptArtworkView(
                url: podcast.artworkURL,
                cornerRadius: OffScriptTheme.Radius.small
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(podcast.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .lineLimit(1)

                Text(podcast.author)
                    .font(.offscriptMeta)
                    .foregroundStyle(Color.offscriptTextMuted)
                    .lineLimit(1)
            }

            Spacer()

            Group {
                switch status {
                case .pending:
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 24, height: 24)
                case .importing:
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.offscriptAccent)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.offscriptAccent)
                        .font(.title3)
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.offscriptDestructive)
                        .font(.title3)
                }
            }
            .frame(width: 24, height: 24)
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: OffScriptTheme.Radius.small, style: .continuous))
    }
}
```

- [ ] **Step 2: Remove ImportProgressView placeholder stub from OnboardingFlowView.swift**

Remove the `struct ImportProgressView` placeholder stub at the bottom of `OnboardingFlowView.swift`.

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild build -scheme OffScript -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add OffScript/ImportProgressView.swift OffScript/OnboardingFlowView.swift
git commit -m "feat: add ImportProgressView with sequential import and taste seeding"
```

---

### Task 7: Wire up ContentView + Remove SampleDataSeeder

Connect the new onboarding flow and clean up the old code.

**Files:**
- Modify: `OffScript/ContentView.swift`
- Modify: `OffScript/PodcastServices.swift`
- Delete: `OffScript/OnboardingView.swift`

- [ ] **Step 1: Update ContentView to use OnboardingFlowView**

In `OffScript/ContentView.swift`, replace the onboarding branch (lines 85-91):

```swift
// OLD:
OnboardingView { jumpToSearch in
    hasSeenOnboarding = true
    if jumpToSearch {
        selectedTab = 3
    }
}

// NEW:
OnboardingFlowView()
```

- [ ] **Step 2: Remove SampleDataSeeder call from ContentView**

In `OffScript/ContentView.swift`, remove line 96:

```swift
// DELETE this line:
try? await SampleDataSeeder.seedIfNeeded(context: modelContext)
```

- [ ] **Step 3: Remove SampleDataSeeder from PodcastServices.swift**

In `OffScript/PodcastServices.swift`, delete the entire `SampleDataSeeder` enum (lines 226-315).

- [ ] **Step 4: Delete OnboardingView.swift**

```bash
git rm OffScript/OnboardingView.swift
```

- [ ] **Step 5: Build to verify compilation**

Run: `xcodebuild build -scheme OffScript -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Run all tests**

Run: `xcodebuild test -scheme OffScript -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OffScriptTests 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add OffScript/ContentView.swift OffScript/PodcastServices.swift
git commit -m "feat: wire OnboardingFlowView, remove SampleDataSeeder and old OnboardingView"
```

---

### Task 8: Genre Preference Boost in RecommendationService

Enhance the recommendation engine to factor in the user's genre preferences from onboarding.

**Files:**
- Modify: `OffScript/RecommendationService.swift`
- Modify: `OffScriptTests/OffScriptTests.swift`

- [ ] **Step 1: Write test for genre preference boost**

Add to `OffScriptTests/OffScriptTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `genreBoost` method not found

- [ ] **Step 3: Add genreBoost to RecommendationScorer**

In `OffScript/RecommendationService.swift`, add to `RecommendationScorer`:

```swift
static func genreBoost(podcastCategories: [String], preferredGenres: [String]) -> Double {
    let normalizedCategories = Set(podcastCategories.map { $0.lowercased() })
    let normalizedPreferred = Set(preferredGenres.map { $0.lowercased() })
    let overlap = normalizedCategories.intersection(normalizedPreferred)
    return overlap.isEmpty ? 0 : 0.06
}
```

- [ ] **Step 4: Wire genre boost into scoreWithExplanation**

In `OffScript/RecommendationService.swift`, in the `scoreWithExplanation` method, after the existing scoring (around line 128, before the explanation block), add:

```swift
// Genre preference boost
if let preferredGenres = UserDefaults.standard.stringArray(forKey: "offscript.preferredGenres") {
    let genreNames = preferredGenres.compactMap { Genre(rawValue: $0)?.title.lowercased() }
    value += RecommendationScorer.genreBoost(
        podcastCategories: episode.podcast.categories.map { $0.lowercased() },
        preferredGenres: genreNames
    )
}
```

- [ ] **Step 5: Run tests to verify they pass**

Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add OffScript/RecommendationService.swift OffScriptTests/OffScriptTests.swift
git commit -m "feat: add genre preference boost to recommendation scoring"
```

---

### Task 9: Add Sign in with Apple Entitlement

The Xcode project needs the Sign in with Apple capability. This is a manual Xcode step but can be done via entitlements file.

**Files:**
- Create: `OffScript/OffScript.entitlements` (if not already present)

- [ ] **Step 1: Check for existing entitlements file**

```bash
find . -name "*.entitlements" -not -path "./.build/*"
```

- [ ] **Step 2: Create or update entitlements file**

Create `OffScript/OffScript.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.applesignin</key>
    <array>
        <string>Default</string>
    </array>
</dict>
</plist>
```

**Note:** The entitlements file must also be referenced in the Xcode project's build settings under `CODE_SIGN_ENTITLEMENTS`. This may need to be done manually in Xcode if the pbxproj doesn't have it configured. The implementer should open Xcode → target → Signing & Capabilities → "+ Capability" → "Sign in with Apple" to ensure proper configuration.

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -scheme OffScript -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add OffScript/OffScript.entitlements
git commit -m "feat: add Sign in with Apple entitlement"
```

---

### Task 10: Reset Simulator Data + Integration Test

Clear the old seed data from the simulator and verify the full flow end-to-end.

- [ ] **Step 1: Reset simulator to clear old SwiftData**

```bash
xcrun simctl shutdown all
xcrun simctl erase all
```

This clears the old `SampleDataSeeder` data so the app starts fresh.

- [ ] **Step 2: Build and run in simulator**

Run: `xcodebuild build -scheme OffScript -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`

Then manually launch the app in the simulator to verify:
1. Welcome screen appears with "OffScript" title and Sign in with Apple button
2. Tapping "Skip for now" advances to genre picker
3. Genre grid shows 12 tappable genre cards with icons
4. Selecting genres and tapping "Continue" shows podcast picker
5. Curated podcasts appear immediately; live results fill in after a moment
6. Selected genres appear first in the podcast picker
7. Selecting 3+ podcasts enables the Continue button
8. Import screen shows progress per podcast
9. After import completes, app transitions to Home feed
10. Home feed shows real episodes from imported podcasts
11. Tapping play on an episode streams real audio

- [ ] **Step 3: Run all tests**

Run: `xcodebuild test -scheme OffScript -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OffScriptTests 2>&1 | tail -30`
Expected: All tests PASS

- [ ] **Step 4: Final commit if any cleanup was needed**

```bash
git add -A
git commit -m "chore: integration test cleanup"
```

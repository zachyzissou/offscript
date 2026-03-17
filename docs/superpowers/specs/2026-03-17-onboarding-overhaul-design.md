# Onboarding Overhaul — Design Spec

## Goal

Replace the static informational onboarding with an interactive, multi-step flow that authenticates the user, captures listening interests, subscribes them to real podcasts, and builds an initial taste profile — so they land on a populated, personalized Home feed.

## Architecture

The onboarding becomes a multi-screen flow managed by a single `OnboardingFlowView` with step-based navigation. Each step collects a signal that feeds downstream: Apple ID → genre interests → podcast selections → feed import + taste profiling. The existing `FeedSyncService` and `TopicExtractionService` handle all import and enrichment work — no new backend services needed.

Sign in with Apple provides lightweight identity via `AuthenticationServices`. The user's Apple ID identifier is stored in Keychain for persistence across installs. No server-side auth — purely local identity for now, with a foundation for future sync/social features.

## Tech Stack

- SwiftUI (multi-step flow with `@State` step tracking)
- AuthenticationServices (Sign in with Apple)
- Existing `FeedSyncService`, `TopicExtractionService`, `RecommendationService`
- Apple RSS Feed Generator API (top podcasts by genre ID, supplementing curated catalog)
- Keychain Services (Apple ID credential storage)

---

## Flow Overview

```
Screen 1: Welcome + Sign in with Apple
    ↓
Screen 2: Genre/Interest Picker
    ↓
Screen 3: Podcast Picker (curated + live, filtered by genres)
    ↓
Screen 4: Import Progress ("Building your feed...")
    ↓
→ Home Feed (populated, personalized)
```

---

## Screen 1: Welcome + Sign in with Apple

**Purpose:** Establish identity and set the tone.

**Layout:**
- App logo/title "OffScript" with the existing gradient treatment
- Tagline: "Podcasts that feel curated, not algorithmic."
- Brief value prop (2-3 lines, not cards — keep it tight)
- "Continue with Apple" button (ASAuthorizationAppleIDButton)
- "Skip for now" text button below

**Sign in with Apple implementation:**
- Uses `ASAuthorizationController` via SwiftUI's `SignInWithAppleButton`
- On success: store `userIdentifier` in Keychain, store display name if provided
- On skip: proceed without identity, no Keychain write
- A new `UserProfileService` manages Keychain read/write and exposes `currentUserID: String?` and `displayName: String?`

**Data model addition:**
- No SwiftData model needed for auth — Keychain is the source of truth
- `UserProfileService` is an enum with static methods (matches `QueueService` pattern)
- Requires "Sign in with Apple" capability added to Xcode project entitlements

---

## Navigation & Completion Contract

**Step navigation:** The flow supports both forward and backward navigation. Users can go back from Screen 3 to Screen 2 to adjust genres, or from Screen 2 to Screen 1. Screen 4 (import) is forward-only — once imports start, there's no going back.

**Completion callback:** `OnboardingFlowView` takes no callback closure. It directly writes `@AppStorage("offscript.hasSeenOnboarding")` which `ContentView` already observes. The old `jumpToSearch` parameter is removed — users who complete onboarding land on the Home tab (index 0) since they already have content. The `SampleDataSeeder` call in `ContentView` is removed entirely.

**Mid-import resilience:** `hasSeenOnboarding` is set to `true` at the start of Screen 4. If the user force-quits mid-import, already-imported podcasts persist in SwiftData. On next launch, the user sees the Home feed with whatever was successfully imported. Podcasts with `syncStatus == "failed"` can be re-synced via pull-to-refresh on the Library tab.

---

## Screen 2: Genre/Interest Picker

**Purpose:** Capture broad listening interests to filter the podcast picker and seed initial taste signals.

**Layout:**
- Header: "What are you into?"
- Subtitle: "Pick a few — we'll use these to find shows you'll actually listen to."
- Grid of genre pills/cards (3 columns), each tappable with toggle selection state
- Selected state: accent border + checkmark + filled background
- "Continue" button at bottom, enabled always (genres are optional but encouraged)

**Genres (10-12):**
- Technology
- Culture & Society
- Comedy
- True Crime
- News & Politics
- Science
- Business
- Health & Wellness
- Sports
- Music
- History
- Education

**Data flow:**
- Selected genres stored as `@State` array, passed to Screen 3
- Also persisted to `UserDefaults` as a `[String]` array via `UserDefaults.standard.set(_:forKey:)` at key `offscript.preferredGenres`, read back via `UserDefaults.standard.stringArray(forKey:)` for recommendation weighting

---

## Screen 3: Podcast Picker

**Purpose:** Let the user choose real podcasts to subscribe to. Hybrid curated + live approach.

**Layout:**
- Header: "Pick 3+ shows to build your feed"
- Vertical scroll with horizontal rails per genre section
- Each section: genre title + horizontal scroll of podcast cards
- Podcast card: artwork (square, ~120pt), title below, author below that
- Selected state: accent border + checkmark overlay on artwork
- Bottom bar: "Continue" button with selection count badge, disabled until 3+ selected
- If genres were selected on Screen 2, those genre sections appear first/expanded; others appear below in an "Explore More" section

**Curated catalog:**
- A new `CuratedPodcastCatalog` enum/struct containing ~3-4 hardcoded podcasts per genre
- Each entry: `title`, `author`, `feedURL` (real RSS URL), `artworkURL` (real artwork), `genre`
- These render immediately with no network dependency
- Total: ~36-48 curated podcasts across all genres

**Live enrichment:**
- On appear, fetch top podcasts per genre via Apple's RSS Feed Generator API: `https://rss.applemarketingtools.com/api/v2/us/podcasts/top/10/genre={genreId}/json`
- Each `Genre` case carries its Apple genre ID (e.g., Technology = 1318, Comedy = 1303)
- Response includes `feedUrl`, `name`, `artistName`, `artworkUrl100` — map to `PodcastSearchResult`
- Deduplicate against curated entries by `feedURL`
- Append live results to each genre section
- If fetch fails, curated entries are sufficient — no error state shown

**Podcast card data structure:**
- Reuses existing `PodcastSearchResult` for both curated and live entries

**Selection tracking:**
- `@State private var selectedFeeds: Set<URL>` tracks selections by feed URL
- Minimum 3 to proceed

---

## Screen 4: Import Progress

**Purpose:** Import selected podcasts, fetch RSS feeds, enrich episodes, build taste profile. Show the user the app is working for them.

**Layout:**
- Centered layout with animated activity
- "Building your feed..." header
- List of selected podcasts with per-podcast status indicators:
  - Spinner → checkmark as each completes
  - Podcast artwork + title for each row
- Brief copy at bottom: "Fetching episodes and learning your taste..."
- Auto-advances to Home feed when all imports complete

**Import logic:**
- Set `hasSeenOnboarding = true` at the START of import (so force-quit mid-import doesn't restart onboarding — already-imported podcasts persist in SwiftData)
- For each selected podcast, call `FeedSyncService.importPodcast(from:into:)` sequentially on `@MainActor` (since `importPodcast` is `@MainActor` and shares a `ModelContext`, concurrent access is unsafe — serial execution is fine since the network I/O suspends off main thread)
- Each import triggers `TopicExtractionService.enrich()` per episode (already wired into `FeedSyncService.sync()`)
- On all completions: auto-transition to Home feed

**Taste profile seeding:**
- The genre selections from Screen 2 inform a new `UserDefaults` key `offscript.preferredGenres`
- The `RecommendationService` can optionally boost episodes matching preferred genres (enhancement to existing scoring)
- The per-episode `EpisodeProfile` tags generated by `TopicExtractionService` (via FoundationModels or NLTagger fallback) form the organic taste graph — no additional LLM call needed beyond what already exists
- Auto-generate `PreferenceSignal(.like)` for the most recent episode of each selected podcast to warm up the recommendation engine (skip if sync failed and no episodes exist)

---

## Files to Create

| File | Purpose |
|------|---------|
| `OnboardingFlowView.swift` | Multi-step onboarding container (replaces current `OnboardingView`) |
| `GenrePickerView.swift` | Screen 2: genre interest grid |
| `PodcastPickerView.swift` | Screen 3: curated + live podcast selection |
| `ImportProgressView.swift` | Screen 4: feed import with progress |
| `UserProfileService.swift` | Keychain-backed Apple ID storage |
| `CuratedPodcastCatalog.swift` | Hardcoded curated podcast entries by genre, includes `Genre` enum with Apple genre IDs |

## Files to Modify

| File | Change |
|------|--------|
| `ContentView.swift` | Point to `OnboardingFlowView` instead of `OnboardingView`, remove `SampleDataSeeder` call |
| `PodcastServices.swift` | Remove `SampleDataSeeder` enum entirely |
| `RecommendationService.swift` | Optional: boost episodes matching `offscript.preferredGenres` |
| `OnboardingView.swift` | Delete (replaced by `OnboardingFlowView.swift`) |

---

## Curated Podcast Catalog (Initial Selection)

Real, well-known podcasts with stable RSS feeds:

**Technology:**
- Lex Fridman Podcast
- Acquired
- The Vergecast
- Accidental Tech Podcast

**Culture & Society:**
- Radiolab
- 99% Invisible
- Freakonomics Radio
- This American Life

**Comedy:**
- Conan O'Brien Needs a Friend
- SmartLess
- The Joe Rogan Experience
- Call Her Daddy

**True Crime:**
- Serial
- Crime Junkie
- My Favorite Murder
- Casefile

**Science:**
- Huberman Lab
- StarTalk Radio
- Ologies
- Science Vs

**Business:**
- How I Built This
- The Prof G Pod
- All-In Podcast
- Masters of Scale

**Health & Wellness:**
- The Peter Attia Drive
- Ten Percent Happier
- On Purpose with Jay Shetty

**News & Politics:**
- The Daily (NYT)
- Pod Save America
- Up First (NPR)
- The Ben Shapiro Show

**Sports:**
- The Bill Simmons Podcast
- New Heights
- Pardon My Take

**History:**
- Hardcore History
- Revisionist History
- The Rest Is History

**Music:**
- Dissect
- Song Exploder
- Broken Record

**Education:**
- TED Radio Hour
- Hidden Brain
- Stuff You Should Know

---

## Error Handling

- **Sign in with Apple fails:** Show inline error, allow retry or skip
- **iTunes API fails:** Silently fall back to curated-only — no error shown to user
- **Individual feed import fails:** Show error icon on that podcast row, allow retry, don't block others from completing
- **All imports fail:** Show retry button, allow going back to reselect
- **Network completely unavailable:** Curated catalog still shows (artwork URLs won't load but titles/metadata are hardcoded). Import step will fail — show offline message with retry
- **Import succeeds but sync fails (no episodes):** Podcast exists in SwiftData with `syncStatus = "failed"` and zero episodes. This is acceptable — the Home feed handles empty subscriptions gracefully, and the user can pull-to-refresh on Library to retry sync

---

## Out of Scope

- Server-side auth / user accounts backend
- iCloud sync of preferences
- Social features (sharing, following)
- Custom genre creation
- Podcast preview/sampling during onboarding
- Onboarding analytics/funnel tracking

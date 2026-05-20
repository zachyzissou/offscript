# OffScript Test Matrix

A repeatable map of every major app surface and how to verify it. Use this
instead of relying on conversational memory when planning a regression
sweep, signing off on a release, or scoping a new agent's verification
contract.

## How To Read This Doc

Each surface has up to four rows:

- **Automated unit** — runs in CI / `xcodebuild` against
  `OffScriptTests`. If a row is in this column the test command is the
  verification.
- **Automated UI** — runs in CI / `xcodebuild` against
  `OffScriptUITests`. If a row is in this column the test command is the
  verification.
- **Simulator manual** — run on the iOS Simulator with the listed launch
  arguments. Reasonable for any agent or contributor with Xcode.
- **TestFlight / real device** — only meaningful on hardware. Required
  before claiming a flow is shipped. Real-device flows can never be
  signed off from simulator-only evidence
  (see `docs/AGENT_EXECUTION_RUNBOOK.md`).

Test commands assume `iPhone 17 Pro` on `OS=latest`. Swap the destination
freely; CI uses the same scheme.

Primary unit gate (everything in OffScriptTests):

```sh
xcodebuild test \
  -project OffScript.xcodeproj \
  -scheme OffScript \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro' \
  -only-testing:OffScriptTests \
  CODE_SIGNING_ALLOWED=NO
```

Primary UI gate (everything in OffScriptUITests):

```sh
xcodebuild test \
  -project OffScript.xcodeproj \
  -scheme OffScript \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro' \
  -only-testing:OffScriptUITests \
  CODE_SIGNING_ALLOWED=NO
```

To run a single test, append `/<TestSuite>/<methodName>` to
`-only-testing`.

## Launch Argument Reference

The app reads these `UserDefaults`-style launch arguments (set via
`-key value` on `xcrun simctl launch` or `XCUIApplication.launchArguments`):

| Argument | Type | Effect |
|---|---|---|
| `-offscript.hasSeenOnboarding` | `YES` / `NO` | Skips or forces onboarding. |
| `-offscript.debugSeedSampleData` | `YES` / `NO` | Seeds 3 podcasts × 3 episodes for populated-state audits. |
| `-offscript.debugSeedLibrarySize` | int (≥ 1) | Seeds a deterministic `N`-show library (`A Channel 001` … `Z Channel NNN`). Triggers automatic stale-store reset. |
| `-offscript.debugSeedEpisodesPerShow` | int | Episode count per seeded show (paired with `debugSeedLibrarySize`). |
| `-offscript.debugWipeLibrary` | `YES` / `NO` | Wipes the SwiftData store at launch (DEBUG builds only). Used by UI tests that need a guaranteed-empty Library/Queue tab regardless of prior simulator state. |
| `-offscript.debugLaunchTab` | `0`-`3` | Launches directly into Home (0), Library (1), Queue (2), or Search (3). |
| `-offscript.debugSelectedTab` | `0`-`3` | Same effect, persists selection across launches. |
| `-offscript.debugBootPlayback` | `YES` / `NO` | Boots with a fake "now playing" state. |
| `-offscript.debugBootIsPlaying` | `YES` / `NO` | Pairs with `debugBootPlayback`. Defaults to playing. |
| `-offscript.debugPresentPlayer` | `YES` / `NO` | Boots with the full Player sheet open. |

Source of truth: `OffScript/AppSettings.swift`, `OffScript/ContentView.swift`.

## Surface Coverage

### Onboarding & first-run

| Layer | Verification | Notes |
|---|---|---|
| Automated unit | `OffScriptTests` — `feedSyncOPMLBootstrapCapsEpisodesAndSkipsProfiles`, `feedSyncOnboardingBootstrapCapsEpisodesAndSkipsExpensiveEnrichment`, `onboardingPreferenceSignalFetchesNewestEpisodeWithoutSortingRelationship` | Bootstrap import + signal extraction. |
| Automated UI | `OffScriptUITests/testOnboardingFirstScreenSmoke`, `testOnboardingFlowAdvancesFromWelcomeToGenrePicker`, `testOnboardingGenrePickerExposesDisabledCTAGate`, `testOnboardingBackFromGenrePickerReturnsToWelcome` | Verifies first screen + POWER ON → wiring, genre-picker CTA gating, BACK navigation. |
| Simulator manual | `-offscript.hasSeenOnboarding NO` | Walk the entire onboarding flow including starter subscriptions. |
| Real device | TestFlight install, fresh device | Required for Sign in with Apple flow validation. Tracked in #112. End-to-end onboarding completion (genre tap → podcast pick → import → home) is real-device-only — see `docs/superpowers/audits/2026-05-20-ui-test-coverage-phase5.md` for the GenreCard hit-test gap that blocks UI-level coverage. |

### Library — directory, filters, alphabet

| Layer | Verification | Notes |
|---|---|---|
| Automated UI | `OffScriptUITests/testLargeLibrarySeedSmoke`, `testLargeLibrarySwitchesFromLibraryToHomeQuickly`, `testLargeLibraryAlphabetRailJumpsToSelectedLetter`, `testLargeLibraryDirectoryControlsStayResponsive` | Drive a 258-show seeded library through scroll, alphabet jump, ATTN/UNPLAYED filters, search filter clear. |
| Automated UI | `OffScriptUITests/testTunerDetailScreensUseInlineBackChrome`, `testLibraryReloadsAfterDetailUnsubscribe` | Detail-push back chrome + post-unsubscribe reload. |
| Automated unit | `OffScriptTests` — `podcastDetailRankerPrefersFeedSuppliedEpisodeNumber`, `podcastDetailRankerNumbersOldestFirstOnFullFeed`, `podcastDetailRankerSuppressesNumberOnFilteredSubsets`, `podcastDetailRankerStillUsesExplicitNumberOnFilteredSubsets`, `podcastDetailRankerHandlesEmptyAndOutOfRangeIndexes`, plus `libraryDirectory*` snapshot/refresh tests | Episode rank labelling, snapshot indexing. |
| Simulator manual | `-offscript.debugSeedLibrarySize 258 -offscript.debugSeedEpisodesPerShow 3 -offscript.debugLaunchTab 1` | Visual audit of large-library scroll perf, hairlines, density. Issues #107, #115, #119. |
| Real device | iPhone 17 Pro, real OPML import | Required for actual import latency claims. Tracked in #105. |

### Import & sync

| Layer | Verification | Notes |
|---|---|---|
| Automated unit | `OffScriptTests` — `feedSync*` family: `feedSyncImportsAlreadyParsedOPMLFeedWithoutRefetching`, `feedSyncFastBatchImportUsesCheapProfilesAndSkipsExternalChapters`, `feedSyncOPMLBootstrapCapsEpisodesAndSkipsProfiles`, `feedSyncCappedImportOnlyMatchesExistingEpisodesInProcessedWindow`, `feedSyncStagesSearchSubscriptionBeforeNetworkWork`, `feedSyncSubscribeThenHydrateCanReturnBeforeNetworkWork`, `feedSyncStagesMultipleOnboardingSubscriptionsInOneBatch`, `feedSyncOnboardingBootstrapCapsEpisodesAndSkipsExpensiveEnrichment`, `feedSyncSelectsLatestCappedItemsWithoutFullFeedSort`; plus the `opmlBatch*` / `opmlImport*` / `opmlBootstrap*` siblings | Bootstrap caps, dedupe, retry, staging, cancellation, concurrent-fetch + serial-apply. |
| Simulator manual | Drag-drop OPML into the simulator's Files app, then `IMPORT` from Library | Verifies the OPML/paste entry point and progress UI. Issue #105. |
| Real device | TestFlight, real iCloud-sized OPML | Required for real network/feed-server timeout claims. |

### Search & discovery

| Layer | Verification | Notes |
|---|---|---|
| Automated UI | `OffScriptUITests/testPostOnboardingShellSmoke` | Tabs to Search and verifies the screen exists. |
| Automated unit | `OffScriptTests` — recommendation discovery + signal trace tests | Discovery genre/local-evidence guarding. |
| Simulator manual | Tap Search tab, query Apple Podcasts Search | Issue #123 covers subscribe-flow polish. |
| Real device | Real Apple Podcasts Search results | Required to evaluate "no algorithm pushing" copy honesty in production. |

### Queue

| Layer | Verification | Notes |
|---|---|---|
| Automated unit | `OffScriptTests` — `queueServiceMovesItemsAndPersistsOrder`, `queueServicePlayNextPromotesEpisodeToFront`, `queueServiceSkipsCurrentEpisodeWhenPoppingNext` | Queue logic. |
| Automated UI | `OffScriptUITests/testPostOnboardingShellSmoke`, `testQueueShowsEmptyStateOnFreshLaunch`, `testQueueClearAllRequiresConfirmation`, `testQueueRowOpensEpisodeDetail`, `testQueueRowsExposePlayAffordanceForEachSeededEpisode` | Tab visit smoke, empty state, × CLEAR ALL confirm strip, row → detail nav, per-row → PLAY / → RESUME / ● PLAYING affordances on a seeded queue. |
| Simulator manual | `-offscript.debugSeedSampleData YES`, queue several episodes, reorder | Issue #126 covers heavy-listener queue ergonomics. |
| Real device | TestFlight, multi-day queue use | Required to evaluate persistence and reorder gestures at scale. Queue autoplay (end-of-episode → auto-advance) is real-device-only until `PlaybackController` gains a `debugSimulateEpisodeCompletion` hook — see `docs/superpowers/audits/2026-05-20-ui-test-coverage-phase5.md`. |

### Player & playback

| Layer | Verification | Notes |
|---|---|---|
| Automated unit | `OffScriptTests` — `playbackAudioSessionUsesSilentSwitchSafeCategory`, `chapterParserExtractsTimestampedShowNotes`, `rssParserExtractsFeedMetadataChaptersAndTranscripts`, `episodeResolvedChaptersPreferPersistedMetadata`, `downloadServiceDeletesLocalFilesAndResetsEpisodeState`, `downloadServiceReconcilesInterruptedDownloadsOnConfigure` | Playback audio session, chapter/transcript pipelines, download service. |
| Simulator manual | `-offscript.debugBootPlayback YES -offscript.debugPresentPlayer YES` | Visual audit of Player and MiniPlayer surfaces. |
| Real device only | Background playback, lock screen art, silent-switch behavior, Now Playing widget, Live Activity, Dynamic Island | Required — the simulator does not faithfully reproduce these. Tracked in #113, #124. |

### Settings — identity, iCloud, counts, destructive actions

| Layer | Verification | Notes |
|---|---|---|
| Automated UI | `OffScriptUITests/testSettingsPanelOpensFromHome`, `testSettingsPanelOpensFromLibrary`, `testSettingsPanelDismissAndReopenCycleStaysStable`, `testSettingsPanelOpensWithLargeLibrarySeed` | Open from Home, open from Library, present→dismiss→re-present cycle stability, large-library seeded counts and simulator iCloud `NOT CONFIG` state. |
| Automated unit | `OffScriptTests` — `appSettingsRoundTripsPreferences`, identity/keychain breadcrumb tests | Preference round-trip, identity logging. |
| Simulator manual | Open Settings, tap each Tuner key, present sign-out confirmation, dismiss | Tracks #114 audit work. |
| Real device | TestFlight Sign in with Apple, real iCloud account, sign-out + re-sign-in | Required for crash-report parity with #114 / #112. |

### Recommendations

| Layer | Verification | Notes |
|---|---|---|
| Automated unit | `OffScriptTests` — `recommendationExplainer*` family (`recommendationExplainerRewritesSavedSignalReasonsFromTrace`, `recommendationExplainerComposesAndClipsExplicitEvidence`, `recommendationExplainerRewritesGenreLaneReasonsFromTrace`, `recommendationExplainerPrioritizesEvidenceInMixedDiscoveryTraces`, `recommendationExplainerDoesNotClaimLocalEvidenceForGenreOnlyDiscovery`, `recommendationExplainerPreservesGenericQuickDurationReasons`, `recommendationExplainerKeepsShortListenPreferenceReason`, `recommendationExplainerKeepsUnknownFallbacks`); `tasteProfileRefresh*` family (`tasteProfileRefreshAggregatesSignals`, `tasteProfileRefreshBuildsTagsFromCompletedEpisodes`, `tasteProfileRefreshWeightsRecentExplicitSignalAboveOldCompletion`, `tasteProfileRefreshLetsOneExplicitIntentBeatSeveralPassiveCompletions`, `tasteProfileRefreshDemotesNegativePreferenceSignals`, `tasteProfileRefreshSkipsWhenFreshUnlessForced`); `homeRecommendations*`, `recommendationScoreRewardsBetterFit`, `genrePreferenceBoostIncreasesScore`, `headlineCandidateUsesStrongestAuthoredSignalAcrossSections`, `signalLockedModeExcludesGenreOnlyCandidates`, `lessLikeThis*`, `repeatedNegativeSignalsHardSuppressSharedTags`, `discoveryPreviewEvidenceBeatsGenreOnlyCatalogMatch`, `playerSuggestionsExposeNowPlayingSignalTrace`, `playerSuggestionsPreferStrongNowPlayingOverlapOverSameShow`, `preferenceFeedbackServicePostsRetuneNotificationAfterSaving`, `recommendationPreferredGenresFallbackToOnboardingSettingsWhenProfileIsEmpty` | WHY copy clipping, signal compositing, taste profile. |
| Simulator manual | `-offscript.debugSeedSampleData YES`, scroll Home rails | Visual audit of rail card layouts. Issue #118 covered text overflow. |
| Real device | TestFlight, multi-day listening | Required for "follows intentional feedback" claim in CHANGELOG. Tracked in #108. |

### Background playback, audio session, silent switch

| Layer | Verification | Notes |
|---|---|---|
| Automated unit | _None — see #113._ | Issue #113 calls for adding regression coverage. |
| Real device only | Lock screen playback, silent switch toggle while audio plays, AirPods route changes, CarPlay. | Required. Cannot be claimed from simulator. |

### Widgets, Live Activity, Dynamic Island

| Layer | Verification | Notes |
|---|---|---|
| Automated unit | _None — visual surfaces only._ | |
| Simulator manual | `OffScriptWidgets` preview in Xcode | Layout-only smoke. |
| Real device only | Add widget to Home Screen, start playback, observe Live Activity + Dynamic Island | Required. Tracked under #111. |

### Release & TestFlight visibility

| Layer | Verification | Notes |
|---|---|---|
| Tooling | `scripts/app_store_connect.py xcode-cloud {probe,inspect,reconfigure,start-build,build-run}` | Xcode Cloud + ASC visibility helpers. |
| Manual | Verify the visible internal TestFlight build matches the latest uploaded build before declaring shipped. | Issue #121 covers the unassigned-build edge case. |

## Pre-Release Sign-Off Checklist

Before marking a build shipped on the project board:

1. Run the **primary unit gate** (above). All tests must pass.
2. Run the **primary UI gate** (above). All tests must pass.
3. Confirm Xcode Cloud Archive succeeded for the release commit
   (`scripts/app_store_connect.py xcode-cloud build-run <run-id>`).
4. Confirm the build is **assigned to the expected internal beta group**,
   not just uploaded — a VALID build with no group assignment is invisible
   to testers (see #121).
5. Real-device pass on at least one iPhone for: background playback,
   silent switch, lock screen art, Sign in with Apple, iCloud state,
   widgets/Live Activity. Required before claiming any of these in the
   CHANGELOG.

## Adding To The Matrix

When a new automated test or simulator/real-device flow is added:

1. Land the test or flow with its PR.
2. Add a row here in the same PR. Do not claim coverage that does not
   yet exist in code.
3. If the flow is real-device-only, do not list a simulator command —
   leave the simulator column empty so the matrix stays honest.

## Lurking Crash Class: SwiftData Refs Across Singleton Test Boundaries

Surfaced during Phase 19 (PlaybackEvent emission tests, commit `9ecc9dd`).

**Symptom:** A test that exercises `PlaybackController.shared` or any
other `@MainActor` singleton publishing `@Model` references crashes on
the *next* test in the run — not the test that wrote the bad state.
Stack trace lands inside the singleton's own `body`/observer/Combine
subscription, dereferencing a model object whose `ModelContainer` was
torn down with the previous test's in-memory context.

**Root cause:** `static let shared = X()` is process-scoped. SwiftData
contexts are run-scoped. The singleton outlives the context, but its
cached `currentEpisode` / `currentRecommendation` / etc. references
point into the dead container.

**The fix (when authoring a new test):**
1. Add a `debugResetForTesting()` method on the singleton (already done
   for `PlaybackController` and `NowPlayingPublisher`).
2. Call it in the test's setup OR teardown.
3. The reset method must (a) cancel any Combine subscription on the
   model object, (b) `currentX = nil`, and (c) clear any background
   `Task` holding model refs.

If you're authoring a singleton that publishes `@Model`-typed values,
ship a `debugResetForTesting()` alongside it. Future-you running tests
six months from now will not enjoy debugging the inevitable flake
without one.

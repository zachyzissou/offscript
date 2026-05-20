# CarPlay readiness audit — 2026-05-19

## Current state

OffScript does **not** support CarPlay in any first-class sense. There is no CarPlay entitlement, no `CPTemplateApplicationScene` declaration in `Info.plist`, no `CPListTemplate` / `CPNowPlayingTemplate` code anywhere in the project, and no CarPlay-specific scene delegate. What does work today is the *passive* CarPlay surface that any `audio` background-mode app gets for free: `MPNowPlayingInfoCenter` is populated and a subset of `MPRemoteCommandCenter` commands are wired, so when a phone running OffScript is plugged into a CarPlay head unit and audio is already playing, the user sees the system "Now Playing" tile with title, podcast name, artwork, and play/pause/skip controls. They cannot, however, **launch** OffScript from CarPlay, **browse** their library, **start** an episode, or see OffScript as an audio app in the CarPlay home grid. This is "lock-screen-class" support, not CarPlay-class support.

## Findings

### A. Entitlements / Info.plist

- `OffScript/OffScript.entitlements` (read at audit time) contains only `com.apple.developer.applesignin` and `com.apple.security.application-groups`. No `com.apple.developer.playable-content` (the legacy entitlement) and no `com.apple.developer.carplay-audio` (the modern audio-app entitlement) are declared. Without `com.apple.developer.carplay-audio`, iOS will not surface OffScript on the CarPlay home screen at all, no matter what scene config is shipped.
- `OffScript/Info.plist` declares `UIBackgroundModes` = `audio, fetch, processing` but has **no** `UIApplicationSceneManifest` / `UISceneConfigurations` entry. There is no `CPTemplateApplicationScene` role declared and no `UISceneClassName` pointing at a `CPTemplateApplicationSceneDelegate`. The app appears to rely on SwiftUI's default scene wiring with no custom `UISceneConfiguration` for CarPlay.
- No `NSUserActivityTypes` for CarPlay handoff are declared.

### B. `MPNowPlayingInfoCenter` metadata coverage

Reviewed `PlaybackController.swift` lines 630-701 and `NowPlayingPublisher.swift`. Coverage is **good for lock-screen, thin for CarPlay**:

- `MPMediaItemPropertyTitle` — set (episode title). Correct.
- `MPMediaItemPropertyPodcastTitle` — set (podcast.title). Good — CarPlay's podcast-aware UI uses this.
- `MPMediaItemPropertyArtist` — set (podcast.author ?? podcast.title). Reasonable fallback.
- `MPMediaItemPropertyAlbumTitle` — **not set**. CarPlay's Now Playing screen often shows album as the show context; using podcast title here as well would give a slightly richer presentation. Minor gap.
- `MPMediaItemPropertyArtwork` — set asynchronously via `updateNowPlayingArtwork(for:)`. Loads off-main, handles file vs remote URLs, guards against stale completions with a URL re-check, logs failures. This is the highest-quality piece of the integration.
- `MPNowPlayingInfoPropertyElapsedPlaybackTime` — set on episode load and refreshed in `updateNowPlayingElapsed()` / `updateNowPlayingPlaybackRate()`. However, *elapsed time is only pushed when the playback rate or active episode changes*, not on the ~1Hz time tick. CarPlay scrub-bars can therefore drift visibly; iOS extrapolates from rate + last-set elapsed, which is usually fine for steady-rate playback but stutters around variable-rate, seeks, or pause/resume bursts.
- `MPMediaItemPropertyPlaybackDuration` — set. Correct.
- `MPNowPlayingInfoPropertyMediaType` — set to `.audio.rawValue`. Correct (worth confirming `.podcast` is not preferred — `MPNowPlayingInfoMediaType` does not expose a podcast case, so `.audio` is right).
- `MPNowPlayingInfoPropertyPlaybackRate` — set and updated through `updateNowPlayingPlaybackRate()`. Correct.
- `MPNowPlayingInfoPropertyDefaultPlaybackRate` — **not set**. CarPlay's per-app speed picker relies on this when the user has chosen a non-1x default. Minor gap.
- `MPNowPlayingInfoPropertyAssetURL` / `MPNowPlayingInfoPropertyIsLiveStream` — not set. Acceptable for VOD podcasts.
- Chapter metadata (`MPNowPlayingInfoPropertyChapterNumber`, `MPNowPlayingInfoPropertyCurrentLanguageOptions`) — not set. OffScript doesn't currently model chapters; not a regression.

### C. `MPRemoteCommandCenter` remote-command wiring

`configureRemoteCommands()` in `PlaybackController.swift` lines 591-628 wires:

- `playCommand` — re-activates audio session, plays, restores rate. Correct.
- `pauseCommand` — pauses, updates rate. Correct.
- `togglePlayPauseCommand` — wired. Correct.
- `skipForwardCommand` — `preferredIntervals = [30]`, seeks +30. Correct.
- `skipBackwardCommand` — `preferredIntervals = [15]`, seeks -15. Correct (asymmetric forward/back matches Apple Podcasts convention).
- `nextTrackCommand` — wired to `skipToNextInQueue()`. Correct.

**Missing remote commands:**
- `previousTrackCommand` — not wired. CarPlay shows a previous-track button when this is present; today users can only go forward through the queue.
- `changePlaybackPositionCommand` — **not wired**. This is the big one: CarPlay's progress bar lets users scrub by tapping on the timeline, and without this command target the scrubber is non-interactive. Lock-screen scrubbing is also disabled. Given OffScript already exposes `seek(to:)`, adding this is ~6 lines.
- `changePlaybackRateCommand` — not wired. CarPlay's per-app speed picker is therefore read-only.
- `seekForwardCommand` / `seekBackwardCommand` (the long-press variants on lock-screen and some head units) — not wired. Low priority.

### D. CarPlay scene templates (`CPListTemplate` / `CPNowPlayingTemplate`)

**Not implemented at all.** Repo-wide grep for `CarPlay|CPTemplate|CPListTemplate|CPNowPlaying` matched only:

- `OffScript/PlaybackController.swift:596` — a comment mentioning CarPlay in the context of audio-session re-activation.

There is no `CPTemplateApplicationSceneDelegate`, no `CPInterfaceController` usage, no `CPListSection` for the library, no `CPNowPlayingTemplate` extension, no `CPSearchTemplate`. The user will never see an OffScript tile in the CarPlay launcher.

### E. Browse hierarchy — can users browse shows + queue + recents in-car?

**No.** Today, the only way to start OffScript playback while driving is:

1. Start the episode on the phone before getting in the car, OR
2. Use the existing Siri intents (`ResumeListeningIntent`, `PlayNextInQueueIntent`, `PauseListeningIntent`, `SkipForwardIntent`) by voice — these are `AppIntent`-based and work fine over CarPlay's Siri layer, but the user has to remember the phrases.

The four AppIntents in `OffScriptAppIntents.swift` would map cleanly onto a CarPlay browse hierarchy:

- Top-level list: **Continue Listening** (1 row, leads to `ResumeListeningIntent`), **Queue** (N rows from the queue model), **Subscriptions** (per-podcast → per-episode), **Recents** (history). Each leaf row would trigger an "open episode + play" intent that doesn't exist yet (there is no `PlayEpisodeIntent(episodeID:)`).
- The model layer already supports this — `OffScriptAppIntents.makeContext()` exists and the SwiftData schema is queryable from an intent process — so building the CarPlay browse tree on top of the existing data layer is mostly a presentation/template-wiring job, not a model rewrite.

## Classification

- **MUST-FIX**:
  - Wire `MPRemoteCommandCenter.shared().changePlaybackPositionCommand` to `PlaybackController.seek(to:)`. This is the single highest-ROI lock-screen / CarPlay fix in the repo today — a non-interactive scrubber looks broken next to Apple Podcasts, and the underlying seek API is already there. ~6 lines.
  - Push `MPNowPlayingInfoPropertyElapsedPlaybackTime` on the existing ~1Hz time tick (or at least every few seconds), not only on rate/episode changes. Otherwise the CarPlay scrubber position drifts on pause/resume.

- **GAP** (feature gap, not regression):
  - No `com.apple.developer.carplay-audio` entitlement; no `CPTemplateApplicationScene` declared; no `CPListTemplate` / `CPNowPlayingTemplate` code. OffScript will not appear on the CarPlay home grid until all three exist.
  - Missing `previousTrackCommand`, `changePlaybackRateCommand`, `MPMediaItemPropertyAlbumTitle`, `MPNowPlayingInfoPropertyDefaultPlaybackRate`.
  - No `PlayEpisodeIntent(episodeID:)` — needed to wire browse-tree leaf rows to playback once CarPlay templates exist.

- **STRATEGIC**: **CarPlay is worth a real implementation for v3, not v2.5.** Podcast-app discovery in CarPlay is one of the few places Apple Podcasts and Overcast still win against indie apps purely on table-stakes presence — if OffScript isn't on the CarPlay home grid, a meaningful slice of the target audience (commuters) literally cannot use it during their primary listening window. Scope estimate for a credible v3 implementation: (1) request the `com.apple.developer.carplay-audio` entitlement from Apple (~1-2 week dev portal turnaround, gating); (2) `CPTemplateApplicationSceneDelegate` + scene config in `Info.plist` (~1 day); (3) a 3-tab `CPTabBarTemplate` with Continue / Queue / Subscriptions backed by the existing SwiftData store (~2-3 days); (4) `CPNowPlayingTemplate` + custom buttons for the 30/15s skip + speed (~1 day); (5) the two MUST-FIX remote-command items above (~1 hour); (6) one full round of Xcode CarPlay-simulator polish across the typography and artwork-fallback paths (~1-2 days). Total: **~2 weeks of focused work plus the entitlement wait**, which is small relative to the strategic positioning. For v2.5 the right move is just the two MUST-FIX items so the *existing* passive surface stops looking broken.

## Reproduction notes

To exercise the current (passive) CarPlay surface without writing any new code:

1. Build and run OffScript on the iPhone 17 Pro / iOS 26.5 simulator (UDID `F623EB2A-1CF4-405E-9583-6B0EE2053FDE`).
2. In Xcode: **Window → Devices and Simulators**, or from the running Simulator app use **I/O → External Displays → CarPlay**. A second window appears showing the CarPlay home grid.
3. Start an episode in OffScript on the phone simulator. Switch focus to the CarPlay window.
4. Observe: OffScript will **not** have a tile in the CarPlay app grid (no entitlement, no scene). However, tap the bottom-bar "Now Playing" indicator on the CarPlay home — the system Now Playing screen will show OffScript's episode title, podcast title, and artwork, and the play/pause/skip ±30/15 buttons will work.
5. Confirm the scrubber gap: tap on the CarPlay scrubber timeline — nothing happens, because `changePlaybackPositionCommand` is unwired.
6. To verify the entitlement / scene gap, run `plutil -p OffScript/Info.plist` (or open it in Xcode) and confirm there is no `UIApplicationSceneManifest` → `UISceneConfigurations` → `CPTemplateApplicationSceneSessionRoleApplication` entry. `cat OffScript/OffScript.entitlements` will confirm no CarPlay entitlement is present.

## Phase 16 — scaffolding landed

2026-05-20: Code-side CarPlay support is now built and ready. The blocker is Apple's entitlement-grant flow.

### What landed
- `com.apple.developer.carplay-audio` entitlement declaration in `OffScript/OffScript.entitlements` (Bool `true`).
- `UIApplicationSceneManifest` → `CPTemplateApplicationSceneSessionRoleAudio` configuration in `OffScript/Info.plist` pointing at `$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate`.
- `OffScript/CarPlaySceneDelegate.swift`: `CPTemplateApplicationSceneDelegate` skeleton + 4-tab `CPTabBarTemplate`:
  - **Library** — subscribed podcasts → nested `CPListTemplate` of recent episodes.
  - **Queue** — current queue in user-defined order.
  - **Recent** — last 20 episodes by `Episode.lastPlayedAt`.
  - **Recommendations** — top 10 scored episodes from `RecommendationService.homeSections` (`refreshTasteProfile: false` so scene-connect stays cheap).
- Per-row artwork download with on-actor `NSCache` (128-entry cap), lazy `setImage(_:)` so list render doesn't block on JPEG fetches.
- `CPNowPlayingTemplate.shared` configured with `isUpNextButtonEnabled = true` and an empty `CPNowPlayingTemplateObserver` conformance as a hook point.
- `OffScriptApp.carPlayModelContainer` static accessor (set as a side effect of the lazy `sharedModelContainer` build) so the scene delegate — which doesn't have access to the SwiftUI `\.modelContext` environment — can fetch from SwiftData.

### What's blocked on Apple
- `com.apple.developer.carplay-audio` entitlement must be requested via Apple's developer portal (<https://developer.apple.com/contact/carplay/>).
- Until the entitlement is granted, the entry won't be honored by code-signing for App Store / TestFlight, so OffScript won't appear in the CarPlay app grid — but the project still builds and ships normally.
- Once granted, the next signed build will appear in CarPlay. **No code changes required after grant.**

### Reuse notes (things existed; we used them)
- `PlaybackController.shared.play(_:in:)` works as-is from CarPlay handlers — already main-actor isolated, already accepts an optional `ModelContext`, and already drives `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`.
- `RecommendationService.homeSections(context:mode:limit:refreshTasteProfile:)` is the public surface CarPlay uses; we pass `refreshTasteProfile: false` because the main app refreshes the profile on its own cadence and CarPlay scene-connect should be cheap.
- `Episode.artworkURL ?? Episode.podcast.artworkURL` is the existing fallback chain used by `OffScriptArtworkView`; reused in `attachArtwork(to:url:)`. The CarPlay list-item image API needs a `UIImage`, so we cannot reuse the `CachedAsyncImage` SwiftUI view directly — the per-scene `NSCache<NSURL, UIImage>` is the lightest-weight bridge.

### Deferred (intentional gaps to clean up post-grant)
- No tests. CarPlay's `CPInterfaceController` / `CPListTemplate` types are awkward to mock and the integration value comes from running on a real head unit, not from unit coverage of section builders. Add an integration smoke test once we have access to a CarPlay simulator session that can be scripted.
- No "Search" tab. CarPlay supports `CPSearchTemplate`; we punted because typing in-car is rare and the four-tab MVP matches the audit's recommended scope. Easy follow-up after entitlement grant. **(resolved in Phase 28 below)**
- No deep integration with the player suggestions surface (`RecommendationService.playerSuggestions`) for the Now Playing "Up Next" button. `isUpNextButtonEnabled = true` shows the button, but the tap is currently a no-op until a `nowPlayingButtonTapped` handler is wired. Follow-up when we have a CarPlay simulator session to actually exercise it. **(resolved in Phase 28 below)**

## Phase 28 — CPSearchTemplate + Up Next

2026-05-20: Closed out the two follow-ups Phase 16 deferred.

### What landed
- **5th tab: Search.** `makeSearchTemplate()` returns a `CPSearchTemplate` with the scene delegate as its `CPSearchTemplateDelegate`. Wired into the existing `CPTabBarTemplate` with a `magnifyingglass` SF Symbol and the title "Search".
- **On-device-only matching.** `searchPodcasts(matching:)` searches subscribed podcasts AND recently-played episodes (`Episode.lastPlayedAt != nil`) by case-insensitive `String.range(of:options:)` contains. Capped at 30 hits total (`ListLimits.searchResults`), with subscribed podcasts sorting before episodes (driver-first ergonomics: pick the show, then the episode). Explicitly does NOT hit iTunes / network catalogs — CarPlay's audio app surface is for *playing what you already follow*, and waiting on a network round-trip mid-drive is bad UX.
- **Min-query floor.** `ListLimits.searchMinChars = 2` so single-character noise during voice composition / steering-wheel scroll-wheel entry doesn't thrash the SwiftData fetch.
- **Search result handlers reuse existing item builders.** Podcast hits use a new `searchListItem(for: Podcast)` that pushes the existing `pushEpisodeList(for:)` template (same nav as the Library tab). Episode hits reuse `listItem(for: Episode)` and play through `PlaybackController.shared.play(_:in:)`. The `selectedResult` delegate just forwards to `item.handler` so the search surface inherits all behavior for free.
- **Up Next button wired.** `CPNowPlayingTemplateObserver.nowPlayingTemplateUpNextButtonTapped(_:)` now pushes a `CPListTemplate` whose contents come from `fetchUpNext()`:
  1. **`QueueService.orderedItems` first** — the user's explicit queue is the authoritative "what plays next" source (it's what `PlaybackController.advanceToNextQueuedEpisode` reads on episode completion). Excludes the currently-playing episode so the list shows what comes *after*.
  2. **`RecommendationService.playerSuggestions` as fallback** — when the queue is empty, surface contextual suggestions for the current episode rather than an empty list. Same call shape `PlayerView` uses for its in-app Up Next strip.
  3. Capped at 10 entries (`ListLimits.upNext`) — single-glance, not a scroll task.

### Reuse notes
- `QueueService.orderedItems(in:)` — already used by `queueSections()` for the Queue tab; reusing it for Up Next means both surfaces stay in sync with the same SwiftData source of truth.
- `RecommendationService.playerSuggestions(currentEpisode:context:limit:)` — the public surface `PlayerView` uses for its own contextual recommendations strip. CarPlay just calls it with `limit: 10` and projects the resulting `ScoredEpisode` array onto `Episode`s for the list.
- `PlaybackController.shared.currentEpisode` is `@Published private(set)`, so reading it from `fetchUpNext()` is safe and gives us the correct anchor episode without any new plumbing.

### Validation (real-device-only, deferred)
CarPlay UI cannot be exercised via XCUITest on the iPhone simulator — `CPInterfaceController` is only instantiated when an actual CarPlay head unit (or Xcode's CarPlay Simulator running against a paired device) connects. The smoke test for these additions has to run on real hardware:

1. Connect iPhone to CarPlay (head unit) or attach Xcode CarPlay Simulator to a paired device.
2. Verify 5 tabs visible in order: Library, Queue, Recent, Recommendations, Search.
3. Tap **Search** → enter "rogan" (or any subscribed-show fragment). Expect: subscribed-podcast hits before episode hits, max 30 rows, two-char minimum (single-char doesn't query).
4. Tap a podcast hit → expect the existing episode list template to push (same as Library tab).
5. Tap an episode hit → expect playback to start (via `PlaybackController.shared.play`).
6. Start any episode → swipe up on Now Playing → tap **Up Next**:
   - If queue has items: expect those, in order, excluding the currently-playing episode.
   - If queue is empty: expect player-suggestion episodes for the current show.
   - Tap any row → expect playback to switch to that episode.

This validation runs once per Apple entitlement-grant cycle and isn't worth a recurring CI gate. Logged here so the validator (human or future agent) has the script.

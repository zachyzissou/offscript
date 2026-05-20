# UI Test Coverage — Phase 5

**Date:** 2026-05-20
**Branch:** `audit/expanded-surface-2026-05-19`
**Scope:** Phase 5 of `docs/NEXT_IMPLEMENTATION_BACKLOG.md` — deeper
regression coverage around onboarding, queue autoplay, sync retries,
and offline playback.

## Tests landed

Four new UI tests in `OffScriptUITests/OffScriptUITests.swift`:

| Name | What it pins | Wall time |
|---|---|---|
| `testOnboardingFlowAdvancesFromWelcomeToGenrePicker` | POWER ON → key on the welcome screen wires into `step = 1` and the genre picker (`01 · TASTE / Pick your bands`) appears. | ~10s |
| `testOnboardingGenrePickerExposesDisabledCTAGate` | Empty genre picker exposes `PICK AT LEAST ONE BAND` as a `.disabled()` button, `CONTINUE →` does not render, and the SELECTED counter reads `0 SELECTED`. | ~9s |
| `testOnboardingBackFromGenrePickerReturnsToWelcome` | `← BACK` on the genre picker returns to the welcome screen (SIGNAL ACQUIRED + POWER ON → reappear). | ~10s |
| `testQueueRowsExposePlayAffordanceForEachSeededEpisode` | A 3-episode seeded queue renders ≥3 action keys matching `PLAY` / `RESUME` / `PLAYING` — no orphan rows missing affordances. | ~6s |

All four pass in isolation and pass together (35.3s total).

## Tests deferred (with reasons)

### 1. Onboarding → CTA flip after selecting a genre

**Originally planned:** `testOnboardingGenrePickerCTAFlipsToContinueAfterSelection`

**Why deferred:** The `GenrePickerView.GenreCard` buttons drop direct
`XCUIElement.tap()` AND coordinate-offset taps. Three repeated taps —
including coordinate taps inside the visible card rectangle — never
fire the Button's `onTap` closure: the SELECTED counter stays at `0
SELECTED`, the `.accessibilityLabel` stays as `"Comedy"` (not
`"Comedy, selected"`), and the underlying state binding doesn't
mutate.

**Root cause (confidence: medium-high):**
`GenrePickerView.GenreCard` (lines 124–168) wraps a VStack of
StaticText + Image under `.buttonStyle(.plain)` with no
`.contentShape(Rectangle())`. Without a content shape, SwiftUI hit-tests
only the inner static-text glyph bounds — XCUITest's tap lands in the
padded background where there's no hit-test target, and the gesture
silently drops. (Real-finger taps work because they land inside the
text or close enough to trigger the bigger touch slop.)

**Fix path:** Add `.contentShape(Rectangle())` after the Button's
label content (or before `.buttonStyle(.plain)`), OR add an
`.accessibilityIdentifier("GenreCard-\(genre.rawValue)")` so tests can
drive a more deterministic element. Either change unlocks the
selection-toggle UI test plus the downstream "CONTINUE → goes to
podcast picker" coverage. **Out of scope for this Phase-5 task** —
genre picker source file is owned by other in-flight subagents.

### 2. Full onboarding completion → home

**Originally planned:** `testOnboardingCompletesAndLandsOnHome`

**Why deferred:** The completion path walks
`PodcastPickerView` (which fires off iTunes Search / curated catalog
requests) → `ImportProgressView` (which fans out per-podcast RSS
imports through `FeedSyncService`). End-to-end UI test would be
network-dependent + 30–60s of import latency in the loop — fragile by
construction. Better covered by the existing `feedSync*` unit tests
plus simulator-manual + real-device verification in `TEST_MATRIX.md`.

### 3. Onboarding skip path

**Originally planned:** `testOnboardingSkipPathLeavesUserOnHomeWithEmptyLibrary`

**Why deferred:** There's no skip-onboarding affordance — the welcome
screen has POWER ON → (which advances) and Sign in with Apple (which
also advances). The only escape is to relaunch with
`hasSeenOnboarding: true`, which is what
`testPostOnboardingShellSmoke` already covers. No new test value to
extract here.

### 4. Queue autoplay advances to next episode on completion

**Originally planned:** `testQueueAutoplayAdvancesToNextEpisodeOnCompletion`

**Why deferred:** True autoplay requires
`AVPlayerItemDidPlayToEndTime`, which only fires when a real audio
URL plays to its end. The debug seed
(`ContentView.configureDebugSeedDataIfNeeded`) uses
`https://placeholder.invalid/sample/N.mp3` URLs that fail at the
asset-load step, long before end-of-item. `PlaybackController` exposes
only `debugPrimePlayback` for the initial-state path — there's no
debug hook to fast-forward through end-of-item or invoke the
`.AVPlayerItemDidPlayToEndTime` observer manually.

**Fix path:** Add a debug method like
`PlaybackController.debugSimulateEpisodeCompletion()` that synthesises
the same `NotificationCenter.default` post that the AVPlayerItem
observer (`PlaybackController.swift:616`) listens for. That would
exercise the end-of-episode → auto-advance → next-up logic with the
same code path as production, without needing a real audio session.

### 5. Queue autoplay respects end-of-episode sleep timer

**Originally planned:** `testQueueAutoplayRespectsEndOfEpisodeSleepTimer`

**Why deferred:** Blocked by the same missing
`debugSimulateEpisodeCompletion` hook as #4. Sleep-timer state is
already exposed on `PlaybackController` (`isEndOfEpisodeSleepArmed`),
so once the completion hook lands this test is one extra arm-and-fire
on top of #4.

### 6. Sync retry — podcast detail after transient network failure

**Originally planned:** `testPodcastDetailRetryAfterTransientNetworkFailure`

**Why deferred:** No first-class API in the XCUITest runner for
toggling iOS-level network state. The documented approach (`xcrun
simctl status_bar booted override --dataNetwork none`) modifies the
simulator chrome but does NOT disable URLSession networking, and it
also pollutes other simulators in the parallel-test pool — six
concurrent subagents share the iPhone 17 Pro pool.

**Fix path:** Either inject a `URLSession`-backed `FeedSyncService`
that can be overridden in tests via a launch arg
(`-offscript.debugFeedSyncMode failure`), OR add an in-app
"simulate-offline" debug toggle wired to a launch arg. The plumbing
already exists for `debugSeedQueue` etc. so a `debugForceSyncFailure`
flag is feasible.

### 7. Sync retry — Home discovery rail per-pick retry after failure

**Originally planned:** `testHomeDiscoveryRailPerPickRetryAfterFailure`

**Why deferred:** Same network-injection gap as #6. The per-pick
`importErrors` map (`HomeView.swift:429`) IS testable in unit-test
land — already covered by the `feedSync*` family — but UI-level
retry-and-recover needs the network injection hook.

### 8. Offline playback works on a downloaded episode

**Originally planned:** `testOfflinePlaybackWorksOnDownloadedEpisode`

**Why deferred:** Sample seed never marks any episode as downloaded;
`localFileURL` stays nil and `downloadState = .notDownloaded`. The
audio URLs (`placeholder.invalid`) can't actually download. There is
no debug arg for pre-populating a downloaded fixture.

**Fix path:** Add `-offscript.debugSeedDownloadedEpisode YES` that
copies a bundled `Tests/Resources/silent.mp3` fixture into the
documents directory, populates the latest seed episode's
`localFileURL`, and sets `downloadState = .downloaded`. Once that
hook exists the offline-playback path becomes a deterministic UI
test.

### 9. Offline playback persists scrub position across launches

**Originally planned:** `testOfflinePlaybackPersistsScrubPositionAcrossLaunches`

**Why deferred:** Same as #8 — needs the
`debugSeedDownloadedEpisode` fixture path. Persistence itself is
covered by `playedPosition` round-trip in
`OffScriptTests.appSettingsRoundTripsPreferences` and friends; the
gap is specifically the UI-layer reopen-and-resume.

## Top finding about the UI testing infrastructure

**Genre picker buttons are not XCUITest-tappable.**

The `GenreCard` Button inside `GenrePickerView` (Phase-5 owner
shouldn't edit it) wraps its label in `.buttonStyle(.plain)` without a
`.contentShape(Rectangle())`. SwiftUI hit-tests only the inner static
text bounds, so XCUITest taps that land in the visible padded area
silently drop. This makes the entire
welcome → genres → podcasts → import → home flow non-driveable from
UI tests, which is why every onboarding completion test in this
Phase-5 backlog had to defer.

This pattern (Button on `.plain` style with no explicit content
shape) likely exists elsewhere in the app — any place we add a
visually-bigger-than-its-text affordance under a SwiftUI Button needs
a `.contentShape(Rectangle())` to be UI-testable. Worth a follow-up
sweep.

Secondary findings:

- The `debugWipeLibrary` flag added in Phase 3 is essential for clean
  Phase-5 tests; every new test uses it. This is the right default.
- `PlaybackController` is missing a `debugSimulateEpisodeCompletion`
  hook. Without it, end-to-end queue-autoplay testing in UI land is
  impossible. Highest-leverage debug-arg add.
- `FeedSyncService` has no network-injection hook for tests. Without
  it, sync-retry-on-failure UI testing is impossible. Second-highest
  leverage.
- No bundled audio fixture exists for offline-playback testing. Third
  highest-leverage.

## Commits

This audit doc + the four new tests land as separate commits on
`audit/expanded-surface-2026-05-19`. See `git log
audit/expanded-surface-2026-05-19` for the exact SHAs.

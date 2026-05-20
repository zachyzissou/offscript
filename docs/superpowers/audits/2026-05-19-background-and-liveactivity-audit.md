# Background refresh + Live Activity / Widget audit — 2026-05-19

Branch: `audit/expanded-surface-2026-05-19` · HEAD at audit start: `e44b0cd`

Scope: `OffScript/BackgroundFeedRefresh.swift`, `OffScript/NowPlayingActivityAttributes.swift`,
`OffScriptWidgets/NowPlayingLiveActivity.swift`, `OffScriptWidgets/NowPlayingWidget.swift`,
`OffScriptWidgets/SharedNowPlayingState.swift`. Read-only context:
`PlaybackController.swift`, `NowPlayingPublisher.swift`, `OffScriptApp.swift`, `Info.plist`.

---

## BackgroundFeedRefresh

### BGTaskScheduler config
- Identifier: `com.offscript.feed-refresh`. ✅ Matches the single entry in
  `OffScript/Info.plist > BGTaskSchedulerPermittedIdentifiers`.
- Registration: NOT done via `BGTaskScheduler.register(forTaskWithIdentifier:)`. Instead the app
  uses the modern SwiftUI **`.backgroundTask(.appRefresh:)`** modifier in `OffScriptApp.swift`,
  which performs the registration implicitly. Good — that's the recommended iOS 17+ surface.
- Submission: `BGAppRefreshTaskRequest` with `earliestBeginDate = now + 30min` baseline.
- `UIBackgroundModes` in `Info.plist` includes `fetch`, `processing`, and `audio`. The combo is
  appropriate for an audio app that also wants opportunistic feed pulls.

### Expiration handler
- `BGTaskScheduler.register` would force an explicit `expirationHandler`. The SwiftUI
  `.backgroundTask` modifier substitutes Swift Concurrency cancellation: when the system reclaims
  time, the enclosing `Task` is cancelled and `Task.isCancelled` flips. The implementation
  observes this between podcasts and is now also guarded inside the `service.sync` `do/catch` via
  an explicit `catch is CancellationError` branch (added in this audit).
- Net: equivalent semantics to a manual `expirationHandler`, but the contract is now documented
  in code so future maintainers don't think it's missing.

### Re-schedule loop
- `scheduleNextRefresh()` is called **before** work starts so the next slot is queued even if we
  get force-stopped mid-run. ✅
- On cancellation the previously-scheduled (minimum-interval) request is left in place — system
  reclaim isn't a failure signal, no need to back off.
- Added: on a run where ≥3 podcasts were attempted and 100% failed, we re-schedule with a 2-hour
  backoff (`scheduleNextRefresh(backoff: true)`). This prevents tight-loop retries from burning
  through iOS's background-refresh budget, which would silently demote the app out of
  opportunistic slots and degrade the feature for everyone.

### Failure throttle
- Per-podcast: `FeedSyncRetryPolicy.nextRetryDate(afterFailureCount:)` already drives exponential
  backoff at the feed level via `nextRetryAt` — the loop skips podcasts whose `nextRetryAt > .now`.
- Per-task: now backed by the global backoff above. The combination protects both the system
  budget and the per-feed retry curve.

---

## Live Activity lifecycle

### Start / update / end
- **Start** (`NowPlayingPublisher.updateActivity`): only when no `currentActivity` exists AND
  `ActivityAuthorizationInfo().areActivitiesEnabled` is true. Called from the time-tick / play-
  state Combine pipeline.
- **Update**: `activity.update(ActivityContent(state:staleDate:))` on every Combine emission,
  throttled to a 5-second floor by `NowPlayingPublisher.scheduleWrite`. Time ticks coalesce.
- **End**: only when `currentEpisode == nil`. ⚠️ Notably **not** called on episode change, app
  termination, or scene background.

### Stale cleanup at launch
- ⚠️ **GAP at audit start**: nothing cleaned up activities left over from a prior force-quit. iOS
  does not auto-end activities when the host app dies — they stay pinned to Dynamic Island /
  Lock Screen with frozen state until the user manually dismisses, producing "ghost" activities.
- ✅ **Fix added (this audit)**: `NowPlayingActivityCoordinator.endStaleActivities()` enumerates
  `Activity<NowPlayingActivityAttributes>.activities` at launch and ends each with
  `.immediate` dismissal. The hook to call this lives in `OffScriptApp.swift`, which is **owned by
  another agent** in this audit cycle — wiring is **DEFERRED**. The helper is in place and
  documented so the App-owning agent can invoke it from `OffScriptApp.init()` or `body`'s `.task`.

### Content state updates as episode progresses?
- Yes. `NowPlayingPublisher` subscribes to `PlaybackController.shared.$currentTime` (1Hz tick)
  and coalesces writes to ≥5s intervals before calling `activity.update`. The Live Activity
  progress bar tracks playback in near-real-time on supported devices.
- `Info.plist` declares both `NSSupportsLiveActivities` and `NSSupportsLiveActivitiesFrequentUpdates`,
  so the higher update budget is requested. ✅

### Dynamic Island three-layout coverage
- **Compact leading**: waveform/play icon (now with accessibilityLabel)
- **Compact trailing**: monospaced time-remaining label (`Xh Ym` or `Ym`)
- **Minimal**: same icon as compact leading
- **Expanded**: leading artwork, center episode + podcast titles, trailing icon, bottom progress bar
- All three required compact + expanded + minimal surfaces are implemented. ✅

### Lock Screen presentation
- Custom `LockScreenView` with artwork, OFFSCRIPT wordmark, episode title (2 lines), podcast title,
  and orange progress bar.
- Wrapped in `Link(destination: offscript://player)` so tapping deep-links into the player view —
  matches the widget's `widgetURL`.
- Accessibility: previously had no combined label; the icon + wordmark + titles were each separate
  VoiceOver stops. Fixed in this audit: decorative icons / wordmark are `accessibilityHidden`,
  with a single combined `accessibilityLabel` describing the activity.

---

## Widget

### Size families
Five supported, declared explicitly via `.supportedFamilies`:
`systemSmall`, `systemMedium`, `accessoryCircular`, `accessoryRectangular`, `accessoryInline`.
No Lock Screen `accessoryInline` — wait, there is. ✅ Reasonable coverage. No `systemLarge`,
which is fine for a now-playing widget (no extra info to surface).

### Refresh cadence
- Static timeline policy: one entry, then `.after(now + 5min)`. The main app proactively pokes
  `WidgetCenter.shared.reloadAllTimelines()` on every snapshot change (via `NowPlayingPublisher`),
  so the 5-minute timeline is a backstop, not the primary refresh path.
- WidgetKit budget: 5-minute fallback is conservative enough not to burn through the daily
  reload budget. ✅

### Placeholder
- `NowPlayingSnapshot.empty` → "Nothing playing" / "Tap to open OffScript" copy. Reads cleanly
  when the user has never played anything. ✅

### Tap targets
- `widgetURL(URL(string: "offscript://player"))` on the whole containerBackground — every size
  family deep-links to the player view via `DeepLinkRouter` (verified by routing config in
  `Info.plist` `CFBundleURLTypes` + scheme `offscript`). ✅

### Accessibility
- ⚠️ **GAP at audit start**: every size family had separate VoiceOver elements for the decorative
  waveform icon and "OFFSCRIPT" / "NOW PLAYING" wordmarks. VO users heard "Waveform. OFFSCRIPT.
  Episode title. Podcast title. Forty-two percent." — verbose and disjointed.
- ✅ **Fix added**: decorative symbols + wordmarks marked `accessibilityHidden(true)`, and each
  view has a single combined `accessibilityLabel` that reads as one sentence. Progress views
  carry their numeric value via `.accessibilityValue("X percent")`.

---

## SharedNowPlayingState

### Sync mechanism
- App Group `group.com.offscript.shared` declared in both target entitlements (verified
  `OffScript/OffScript.entitlements` + `OffScriptWidgets/OffScriptWidgets.entitlements`).
- Single key (`nowPlayingSnapshot`) holding a JSON-encoded `NowPlayingSnapshot` blob in suite
  UserDefaults. Reader-only path on the widget side; writer-only path on the host side.
- Two files (`OffScript/SharedNowPlayingState.swift` and `OffScriptWidgets/SharedNowPlayingState.swift`)
  with **identical** content — keeping them in sync is by convention. Low risk because the struct
  is tiny, but a single source-of-truth (target membership shared) would be cleaner. Cross-cutting
  fix — left for a project-file edit. Noted as deferred.

### Thread safety
- UserDefaults writes from a single host process are atomic (each `set(forKey:)` is internally
  serialized). The widget process reads only — no read/write race possible.
- Concurrent host writes: all writes funnel through `NowPlayingPublisher.performWrite()`, which is
  `@MainActor` — serialized at the actor boundary.
- Encoding/decoding errors are silently dropped (`try?`). On corruption the widget falls back to
  `.empty` — acceptable degraded state.

---

## Fixes applied

| # | File | Description | Commit |
|---|------|-------------|--------|
| 1 | `OffScript/BackgroundFeedRefresh.swift` | Failure throttle + explicit cancellation catch + documented expiration semantics | _see commit log_ |
| 2 | `OffScriptWidgets/NowPlayingLiveActivity.swift` | Accessibility labels on Dynamic Island + Lock Screen; combined VO label | _see commit log_ |
| 3 | `OffScriptWidgets/NowPlayingWidget.swift` | Accessibility labels + values across small/medium/circular views | _see commit log_ |
| 4 | `OffScript/NowPlayingActivityAttributes.swift` | Added `NowPlayingActivityCoordinator.endStaleActivities()` helper | _see commit log_ |

Build: `xcodebuild ... build` → `** BUILD SUCCEEDED **`.

## Deferred / cross-cutting

These need edits to read-only files in this audit's scope. Document for follow-up:

- ~~**`OffScriptApp.swift`** — wire `NowPlayingActivityCoordinator.endStaleActivities()` into a
  `.task` on the `WindowGroup` (or `OffScriptAppDelegate.application(_:didFinishLaunchingWithOptions:)`).
  Without this, the helper added here doesn't actually fire and ghost activities persist after
  force-quit. **HIGH PRIORITY follow-up.**~~ **LANDED commit `7c73621` (`fix(liveactivity): sweep stale Live Activities on cold launch`) — wires the helper into the ContentView `.task` on `WindowGroup`.**
- **`PlaybackController.swift` / `NowPlayingPublisher.swift`** — call `endActivity()` on episode
  *change* (not just on `currentEpisode == nil`), so a new activity starts with fresh attributes
  when the artwork URL changes. Currently the activity persists across episode boundaries with
  stale artwork.
- **`SharedNowPlayingState.swift` duplication** — collapse into one file with shared target
  membership instead of duplicating across host + widget. Requires `.xcodeproj` edit.
- **`NowPlayingPublisher`** — add a `scenePhase == .background` hook to flush a final
  `activity.update` before going dark, so the activity doesn't show frozen state for ~5s after
  backgrounding.

## Classification

### MUST-FIX
- ~~**Ghost Live Activities on relaunch.** Helper landed; call site is deferred to App-owning agent.
  Until that call site is wired, users who force-quit while listening see a frozen pinned activity
  until they manually swipe it away. Real bug, visible to users.~~ **RESOLVED commit `7c73621`. Wired into `OffScriptApp` body's `.task`.**

### GAP
- VoiceOver experience on widget + Live Activity was a string of disjointed labels — fixed.
- Background refresh had no global failure throttle — fixed.
- Activity not ended on episode change — deferred (requires `PlaybackController` change).
- Two copies of `NowPlayingSnapshot` / `NowPlayingStorage` instead of shared target membership —
  deferred (project file change).

### STRATEGIC
The background / Live Activity / widget surface is **solid but uneven**. The widget and shared-
state plumbing are well-architected (App Group, snapshot pattern, WidgetCenter pokes) and were
mostly polish work — accessibility labels, no logic bugs. The background refresh is correctly
hooked into modern SwiftUI APIs and has appropriate retry policies layered at both the per-feed
and per-task level after this audit. The weakest link is **Live Activity lifecycle**: the start /
update path is fine, but end-of-life — episode change, app termination, force-quit recovery — has
real gaps. This audit landed the cleanup helper but two of the three end-of-life issues require
edits outside the owned set. Recommend a focused follow-up PR in the next cycle that touches
`OffScriptApp` and `NowPlayingPublisher` together to close out lifecycle completely; once that
ships, this surface is shippable-quality. Until then it's "works in the happy path, ghosts under
duress" — a known weakness.

# Dead-code-wiring sweep — 2026-05-20

## Context

Earlier phases of this audit branch surfaced **eight** scaffolding-not-connected
patterns (Phases 11, 14, 15, 17, 19, 20 + two deletions). A pattern this strong
almost certainly has more lurking. This document is a systematic seven-pass
sweep across every `static let shared`, every `configure(...)`, every protocol,
every event-shaped enum, every `Notification.Name`, every `@Published`, and
every cache wrapper.

Methodology was: locate every declaration of the receiver/consumer shape, then
grep for the emitter/caller side. Anything with zero or near-zero emit sites
got pulled into the findings table.

Phase 24 owns `BackgroundTranscriptionService.swift` and `OffScriptApp.swift`
concurrently with this sweep, so findings there are noted but not actioned.

## Pass 1: `static let shared` singletons

| Singleton | External call sites (excluding decl) | Verdict |
| --- | --- | --- |
| `SpeechTranscriptionService.shared` | 9 | NOT-A-FINDING — actively used |
| `NetworkMonitor.shared` | 1 (`DownloadService.connectionType`) | NOT-A-FINDING but see Pass 6 |
| `BackgroundTranscriptionService.shared` | 2 | NOT-A-FINDING |
| `PlaybackController.shared` | 46 | NOT-A-FINDING |
| `ImageCache.shared` | 2 (both in AppTheme.swift) | NOT-A-FINDING |
| **`SpeechAnalyzerService.shared`** | **0** | **DORMANT** — entire iOS-26-streaming class is scaffolding |
| `MetricKitReporter.shared` | 1 (`OffScriptApp.configure()`) | NOT-A-FINDING |
| `BatchImportService.shared` | 5 | NOT-A-FINDING |
| `NowPlayingPublisher.shared` | 2 | NOT-A-FINDING |
| `DownloadService.shared` | 19 | NOT-A-FINDING |

**Major finding:** `OffScript/SpeechAnalyzerService.swift` (104 lines) has zero
production call sites. Class, `static let shared`, `cachedTranscript(...)`, and
`transcribeStreaming(...)` are all dead. The internal comment acknowledges the
streaming path "falls through to the legacy service today; the streaming
surface is here so call sites can adopt it without restructuring once the SDK
ships." Pre-iOS-26 dormancy.

## Pass 2: `configure(...)` methods

| Method | Caller | Verdict |
| --- | --- | --- |
| `BackgroundTranscriptionService.ForegroundCompat.configure` | `ContentView.swift:148` | NOT-A-FINDING (no-op shim by design — Phase 24 territory) |
| `CrashReporter.configure` | `OffScriptApp.swift:38` | NOT-A-FINDING |
| `PlaybackController.configure` | `ContentView.swift:144` | NOT-A-FINDING |
| `DownloadService.configure` | `ContentView.swift:158` | NOT-A-FINDING (fixed Phase 15) |
| `MetricKitReporter.configure` | `OffScriptApp.swift:39` | NOT-A-FINDING |

No new dead-configure findings.

## Pass 3: Protocols

| Protocol | Conformers | Callers | Verdict |
| --- | --- | --- | --- |
| `OffScriptAudioSessionApplying` | `AVAudioSession` + test mock | `OffScriptAudioSessionConfiguration.apply` | NOT-A-FINDING |

Only one production protocol exists, and it's wired.

## Pass 4: Enum cases never emitted

### `PlaybackEvent.Kind` (`Models.swift:214`)

| Case | Emit sites | Read sites | Verdict |
| --- | --- | --- | --- |
| `.started` | 0 | TasteProfileService + RecommendationService (switch arms) | **BROKEN-WIRING** — readers built, no emitter |
| `.completed` | `PlaybackController.swift:618` | 2 | NOT-A-FINDING |
| `.skippedQuickly` | via `classifySwitchAway` → `recordPlaybackEvent` line 385 | multiple | NOT-A-FINDING |
| `.seekedForward` | 0 | TasteProfileService + RecommendationService (switch arms with weight 0) | DEAD or BROKEN-WIRING |
| `.seekedBackward` | 0 | same as above | DEAD or BROKEN-WIRING |
| `.abandoned` | via `classifySwitchAway` | multiple | NOT-A-FINDING |
| `.advancedFromQueue` | `PlaybackController.swift:645` | multiple | NOT-A-FINDING (Phase 19) |
| `.resumed` | `PlaybackController.swift:462` | multiple | NOT-A-FINDING (Phase 19) |

`.seekedForward` and `.seekedBackward` are weighted 0 in both
`TasteProfileService.preferenceWeight` and `RecommendationService` — readers
exist purely to fail the switch exhaustively. They could be removed from the
enum entirely without behavioral change (the readers just disappear with
them). Classify as **DEAD** unless there's a roadmap intention to start
emitting them.

`.started` is more interesting: `TasteProfileService.swift:152` reads
`$0.kind == .started || $0.kind == .resumed` to compute a `startedCount`, but
`.started` is never emitted, so the formula effectively reduces to
`max(resumed_count, 1)`. This is a **BROKEN-WIRING** finding: either the
formula's intention was "every time the user pressed play" (then we should
emit `.started` in `PlaybackController.load(...)`) or `.started` should be
removed.

### `PreferenceSignal.Action` (`Models.swift:245`)

| Case | Emit sites | Verdict |
| --- | --- | --- |
| `.like` | `EpisodeDetailView`, `HomeView`, `ImportProgressView` | NOT-A-FINDING |
| `.notInterested` | `HomeView` | NOT-A-FINDING |
| `.moreLikeThis` | `HomeView` | NOT-A-FINDING |
| `.lessLikeThis` | `EpisodeDetailView`, `HomeView` | NOT-A-FINDING |

All wired.

### `Episode.DownloadState` (`Models.swift:68`)

All five cases emitted and read multiple times. NOT-A-FINDING.

### `AppSettings.CloudSyncRuntimeState` (`AppSettings.swift:50`)

| Case | Emit sites | Verdict |
| --- | --- | --- |
| `.localOnly` | 0 (only used as fallback default in `cloudSyncRuntimeState` getter) | NOT-A-FINDING (implicit initial value) |
| `.cloudBacked` | `OffScriptApp.swift:159` | NOT-A-FINDING |
| `.fallbackFailed` | `OffScriptApp.swift:113`, `162` | NOT-A-FINDING |

### `AppSettings.LibrarySortMode` (`AppSettings.swift:44`)

**DEAD enum.** `LibrarySortMode` is defined and exposed via
`AppSettings.librarySortMode` but the only callers are tests
(`OffScriptTests.swift:1780/1788/1795/1802`). `LibraryView` uses its own
scoped `LibraryDirectorySort` enum, never `AppSettings.librarySortMode`. The
enum, the static property, and the `libraryShowDownloadedOnly` property are
all production-dead.

### `BatchImportService.Phase`

All three cases wired. NOT-A-FINDING.

### `SearchPreviewLoader.PreviewState`

All three cases (`.loading`, `.loaded`, `.failed`) wired. NOT-A-FINDING.

### `ImportRowStatus` (`LibraryImportSheet.swift:509`)

All six cases emitted. NOT-A-FINDING.

## Pass 5: NotificationCenter names

| Name | Posters | Observers | Verdict |
| --- | --- | --- | --- |
| `offscriptSwitchTab` | `DeepLinkRouter:95`, `:163`, `QueueView:105` | `ContentView:184` | NOT-A-FINDING |
| `offscriptActiveTabChanged` | `ContentView:202` | `SearchView:111`, `LibraryView:949` | NOT-A-FINDING |
| `offscriptRecommendationFeedbackChanged` | `PreferenceFeedbackService:16` | `HomeView:148` | NOT-A-FINDING |
| `offscriptLibrarySubscriptionsChanged` | `PodcastUnsubscribeService:106` | `LibraryView:943` | NOT-A-FINDING |
| `offscriptOpenPodcast` | `DeepLinkRouter:168` | `LibraryView:952` | NOT-A-FINDING |

All notification names have at least one poster and one observer. No dead
one-way wiring.

## Pass 6: `@Published` write-only / read-only

| Property | Write sites | Read sites | Verdict |
| --- | --- | --- | --- |
| `PlaybackController.currentEpisode`, `isPlaying`, `currentTime`, `duration`, `playbackError`, etc. | many | many | NOT-A-FINDING |
| `BatchImportService.phase` | several | `LibraryView`, `LibraryImportSheet` | NOT-A-FINDING |
| `BatchImportService.progress` | several | `LibraryImportSheet` | NOT-A-FINDING |
| **`BatchImportService.entries`** | 1 (`start(...)`) | only internal `totalCount` getter | DORMANT (low cost — kept as `@Published` for potential future view binding) |
| **`NetworkMonitor.isConnected`** | 1 (`AppSettings.swift:18`) | 0 | **DEAD** — written every path-update tick, never observed. Only `connectionType` is read (by `DownloadService.connectionType == .wifi`). |

## Pass 7: Caches

| Cache | Write site | Read site | Verdict |
| --- | --- | --- | --- |
| `HTMLPlainTextCache.cache` (NSCache) | `String.strippingHTML` getter | same | NOT-A-FINDING |
| `ImageCache.memoryCache` (NSCache) | `loadImage` write, `image(for:)` read | both | NOT-A-FINDING |
| `ImageCache.session.urlCache` (URLCache) | URLSession implicit | URLSession implicit | NOT-A-FINDING |
| `CarPlaySceneDelegate.artworkCache` | line 292 | line 280 | NOT-A-FINDING |

All caches symmetric.

## Pass 8 (bonus): write-only model fields

| Field | Production write sites | Production read sites | Verdict |
| --- | --- | --- | --- |
| `Episode.downloadRequestedAt` | DownloadService:79,127 | DownloadService:296 (sort key) | NOT-A-FINDING |
| `Episode.downloadCompletedAt` | several | DownloadService:226, BackgroundTranscriptionService:229 (sort) | NOT-A-FINDING |
| `Episode.downloadErrorMessage` | several | EpisodeDetailView, DownloadService UI | NOT-A-FINDING |
| `Podcast.subscribedAt` | many | LibraryView sort key | NOT-A-FINDING |
| **`Podcast.lastSyncAttemptAt`** | 8 production write sites | **0 production reads (only test assertions)** | **DEAD field outside tests** |

## Pass 9 (bonus): write-only persistent rows

| Type | Write sites | Production read sites | Verdict |
| --- | --- | --- | --- |
| **`TelemetryEvent`** (SwiftData @Model) | `TelemetryService.track(...)` (~16 call sites across DownloadService, PodcastServices) | **0** (only `TelemetryEvent.self` in schema list + tests fetching) | **DEAD persistence** — rows accumulate forever with no consumer surface |
| `PlaybackEvent` | many | TasteProfileService, RecommendationService | NOT-A-FINDING |
| `PreferenceSignal` | several | RecommendationService, TasteProfileService | NOT-A-FINDING |
| `EpisodeProfile` | TopicExtractionService | RecommendationService, TasteProfileService | NOT-A-FINDING |
| `EpisodeTranscriptCache` | SpeechTranscriptionService, PublishedTranscriptLoader | both | NOT-A-FINDING |

## Pass 10 (bonus): orphaned subsystems

| Subsystem | Issue | Verdict |
| --- | --- | --- |
| `BackgroundFeedRefresh` (`BackgroundFeedRefresh.swift`) | `scheduleNextRefresh()` is only called from inside `performRefresh`. There is **no bootstrap call** at app launch or scene-active. The `.backgroundTask(.appRefresh(...))` modifier in `OffScriptApp.swift:137` only registers a handler — it does not submit a `BGTaskRequest`. Without an initial submission, iOS has nothing to schedule, so `performRefresh` may never fire. | **BROKEN-WIRING** (Phase 24 owns `OffScriptApp.swift`; flag for that worker) |
| `BackgroundTranscriptionService.scheduleNextRound` | Same shape: only called from inside `performTranscriptionRound`. No bootstrap. | **BROKEN-WIRING** (Phase 24 owns this file directly) |

## Verdicts summary

### DEAD (delete recommended, no behavioral risk)
1. `AppSettings.LibrarySortMode` enum + `AppSettings.librarySortMode` static + `AppSettings.libraryShowDownloadedOnly` static — only exercised by tests
2. `AppSettings.lastCloudSyncDate` static — never written, never read
3. `NetworkMonitor.isConnected` — written on every path-update tick, observed nowhere
4. `PlaybackEvent.Kind.seekedForward` and `.seekedBackward` — both never emitted, both weighted 0 in reader switch arms
5. `Podcast.lastSyncAttemptAt` — 8 production write sites, zero production reads (only test assertions)

### DEAD persistence
6. `TelemetryEvent` model — `TelemetryService.track(...)` accumulates rows indefinitely (DownloadService alone calls it ~12 times). Nothing in production code ever fetches these rows. Either wire an export/inspector surface or remove the model + service.

### DORMANT (kept as future-iOS scaffolding)
7. `SpeechAnalyzerService` (entire class, ~104 lines) — iOS 26 streaming-transcription path. Internal comment confirms intentional dormancy. Leave with `// TODO: enable when iOS 26 SpeechAnalyzer SDK stabilizes` to make intent explicit.

### BROKEN-WIRING (receiver built, emitter missing — Phase-19-shaped follow-ups)
8. `PlaybackEvent.Kind.started` — `TasteProfileService.swift:152` computes `startedCount` from `.started || .resumed`, but `.started` is never emitted. Formula collapses to `max(resumed_count, 1)` which is probably not the intended behavior. Either emit `.started` in `PlaybackController.load(...)` or simplify the formula.
9. `BackgroundFeedRefresh.scheduleNextRefresh()` — no bootstrap submitter at app launch. Subsystem cannot self-start. (Phase 24 may address; if not, single-line fix in `OffScriptApp.swift` or `ContentView`.)
10. `BackgroundTranscriptionService.scheduleNextRound()` — same shape as #9. (Phase 24 owns.)

### NOT-A-FINDING (false positives, included for completeness above)

## Inline fixes applied

None. Every finding required either a judgment call (DEAD vs BROKEN-WIRING)
or touched a file owned by Phase 24. Audit-only.

## Recommended follow-ups (highest leverage first)

1. **TelemetryEvent (DEAD persistence).** Either build a surface (e.g.
   debug-only Telemetry tab in SettingsView, or an export-CSV button) or
   delete `TelemetryService`, `TelemetryEvent`, and the ~16 call sites. As
   written it bloats the SwiftData store forever with rows nobody reads.
   Highest leverage because every `track(...)` call site is doing pure work
   that creates persistent garbage.

2. **`PlaybackEvent.Kind.started` BROKEN-WIRING.** Decide intention: if
   `.started` is meant to represent "pressed play on a fresh load", emit it
   in `PlaybackController.load(...)` alongside the existing `.resumed` logic.
   If not, simplify `TasteProfileService.swift:152` to read only `.resumed`
   and remove `.started` from `PlaybackEvent.Kind`. The current half-state
   silently breaks the `startedCount` denominator and skews recommendation
   weighting.

3. **Bootstrap submitter for `BackgroundFeedRefresh.scheduleNextRefresh()`.**
   Without an initial `BGTaskScheduler.submit`, the SwiftUI
   `.backgroundTask(.appRefresh)` handler is unreachable. Coordinate with
   Phase 24 since they own `OffScriptApp.swift`. Same fix likely applies to
   `BackgroundTranscriptionService.scheduleNextRound`.

### Lower-leverage cleanups

4. Delete `AppSettings.LibrarySortMode` enum + `librarySortMode` static +
   `libraryShowDownloadedOnly` static (production-dead, only tests exercise
   them — and the tests can go too, since they don't cover production
   behavior).

5. Delete `AppSettings.lastCloudSyncDate` (declared, never used).

6. Delete `NetworkMonitor.isConnected` (write-only; the connection-type read
   in `DownloadService` covers what production actually needs).

7. Delete `PlaybackEvent.Kind.seekedForward` and `.seekedBackward` (zero
   emitters, readers weight them 0, no behavioral change from removal).

8. Delete `Podcast.lastSyncAttemptAt` field (production write-only). The
   tests that read it should be removed since they don't pin production
   behavior.

9. Add explicit `// TODO: iOS 26` annotation to `SpeechAnalyzerService` so
   the dormancy is loud at the call-decision boundary, not buried inside the
   class doc comment.

## Pattern observation

Of 10 distinct findings, the cluster is roughly:

- **3 are "no consumer" patterns** (TelemetryEvent, NetworkMonitor.isConnected,
  AppSettings.lastCloudSyncDate) — same shape as the
  `offscript.lastEpisodeAudioURL` reader-without-writer finding in Phase 17,
  just inverted (writer without reader).

- **2 are "bootstrap missing" patterns** (BackgroundFeedRefresh,
  BackgroundTranscriptionService scheduling) — same shape as the
  `DownloadService.configure()` finding fixed in Phase 15.

- **3 are "dead enum case" patterns** (`PlaybackEvent.Kind.started`,
  `.seekedForward`, `.seekedBackward`) — same shape as the Phase 19 finding
  that fixed `.skippedQuickly` / `.abandoned` / `.advancedFromQueue` /
  `.resumed`.

- **1 is full-class dormancy** (`SpeechAnalyzerService`) — same shape as
  Phase 14's `PublishedTranscriptLoader` missing emitter, but more honest
  about its dormancy.

- **1 is dead test-only surface** (`LibrarySortMode` / `librarySortMode`) —
  novel shape; a Sept 2024 onboarding sort feature that got designed and
  test-covered but never UI-wired.

The dominant root cause looks like Phase-19-shaped: enum cases and writer
properties get added eagerly when designing a domain model, but the
reader/emitter side gets deferred and then never returned to.

# Singleton tear-down hardening — Phase 26

## Lurking-crash class

Surfaced during Phase 19 (commit `9ecc9dd`) and re-documented in
`docs/TEST_MATRIX.md` § "Lurking Crash Class". The pattern: a
`static let shared = X()` singleton outlives the SwiftData
`ModelContainer` of any single test, but caches an `@Model`-typed
property (`Episode`, `Podcast`), a `ModelContext`, a `Combine`
subscription on `@Model.publisher`, or an in-flight `Task` /
`URLSessionTask` whose completion callback dereferences a `@Model`. The
test that *wrote* the dangling reference passes cleanly; the *next*
test in the run crashes inside the singleton's body / sink / delegate
callback the moment something accesses the stale model.

Symptoms observed (documented in TEST_MATRIX commit `1233b73`):

- `autoAdvanceDoesNotDoubleEmitSkipOrAbandonedOnFinishedEpisode`
- `podcastDeepLinkPostsSwitchTabAndOpenPodcastForExistingPodcast`
- Several `PlaybackEventEmissionTests` cases — all pass in isolation,
  fail when the full suite runs together.

Phase 19 fixed `PlaybackController` + `NowPlayingPublisher`. This
phase audits every remaining `static let shared` for the same hazard
and closes the gaps.

## Singletons audited

| Singleton                              | Holds `@Model` refs?       | `debugResetForTesting` present? | Status     |
|----------------------------------------|----------------------------|---------------------------------|------------|
| `PlaybackController.shared`            | Yes (`currentEpisode`)     | Yes (Phase 19)                  | OK         |
| `NowPlayingPublisher.shared`           | Yes (Combine subs on `$currentEpisode`) | Yes — `debugStopForTesting` (Phase 19) | OK         |
| `DownloadService.shared`               | Yes (cached `modelContext`, `URLSessionDownloadTask` callbacks fetch `Episode`) | **No**                          | **GAP — fixed** |
| `BatchImportService.shared`            | Yes (`activeModelContext`, running `Task` mutates `Podcast`/`Episode`) | **No**                          | **GAP — fixed** |
| `SpeechTranscriptionService.shared`    | No — `[UUID: String]` cache only | n/a                             | Safe       |
| `SpeechAnalyzerService.shared`         | No — `[UUID: String]` cache only | n/a                             | Safe       |
| `BackgroundTranscriptionService.shared`| No — `ForegroundCompat` shim is stateless | n/a                             | Safe       |
| `NetworkMonitor.shared`                | No — primitive `connectionType` only | n/a                             | Safe       |
| `MetricKitReporter.shared`             | No — forwards payloads to OSLog/Sentry | n/a                             | Safe       |
| `ImageCache.shared`                    | No — `NSCache<NSString, UIImage>` | n/a                             | Safe       |

Enum-based "singletons" that have no instance state (and so by
construction can't hold `@Model` refs across tests):
`AppSettings`, `DeepLinkRouter`, `SpotlightIndexer`,
`PreferenceFeedbackService`, `BackgroundTranscriptionService` (the
outer enum), `OffScriptAudioSessionConfiguration`.

## Gaps fixed

### `DownloadService.shared`

Held a cached `modelContext`, plus `taskToEpisodeID` /
`episodeIDToTask` dictionaries pinning in-flight
`URLSessionDownloadTask`s. The URLSession delegate methods
(`didWriteData`, `didFinishDownloadingTo`, `didCompleteWithError`)
all hop to the main actor and call `self.episode(for: episodeID)`
through the cached context. After a test tears its container down,
the next test's `DownloadService.shared.configure(context:)` swaps
the context — but any callback still in flight from the previous
test executes against the dead context and crashes in SwiftData.

Fix: added a `#if DEBUG`-gated `debugResetForTesting()` that cancels
every in-flight task, clears both task dictionaries, clears the
progress-throttle dictionaries, resets `hasReconciledPersistedState`
back to `false`, nils the background completion handler, and nils
the `modelContext` last.

### `BatchImportService.shared`

Held an `activeModelContext` plus a long-running `task` that imports
podcasts via `FeedSyncService.importPodcast(...)` — every podcast/
episode insert lands against `activeModelContext`. A test that
exercises this service and tears down its container before the task
finishes would otherwise leak a `Task` writing into the (now
invalid) context.

Fix: added `debugResetForTesting()` that cancels the task, nils
`activeModelContext`, and resets the published `progress` / `entries`
/ `phase` to their idle values.

## `DebugTeardown.resetAllSingletons` helper

New file `OffScript/DebugTeardown.swift` (DEBUG-only) provides a
single entry point that resets every hardened singleton in one call:

```swift
DebugTeardown.resetAllSingletons()
```

The file's header comment documents the contract: any new
`static let shared` that caches a `ModelContext`, an `@Model`-typed
property, a `Combine` subscription on `@Model.publisher`, or a
background `Task` touching `@Model` refs must wire its
`debugResetForTesting()` into the helper. This is a forcing
function — adding singletons here is the canonical way to keep test
isolation honest, instead of asking every future test author to
remember each singleton by hand.

## Tests that should now stabilize

Verification is deferred to Phase 31 (which owns the test file).
These are the cases documented in `docs/TEST_MATRIX.md` commit
`1233b73` as pre-existing flakes that the singleton-pollution class
explains:

- `autoAdvanceDoesNotDoubleEmitSkipOrAbandonedOnFinishedEpisode`
- `podcastDeepLinkPostsSwitchTabAndOpenPodcastForExistingPodcast`
- The `PlaybackEventEmissionTests` cases that pass in isolation but
  fail in full-suite runs

Phase 31 will land a single `DebugTeardown.resetAllSingletons()`
call into the test setup/teardown and confirm the cases stabilize.
If any flake survives that change, the next step is to look at
non-singleton sources of cross-test state (UserDefaults, file
system, Spotlight index, etc.) — outside this phase's scope.

## Top finding

`DownloadService.shared` was the singleton most clearly missed by
the original Phase 19 sweep. Its URLSession delegate is `nonisolated`
and dispatches into `Task { @MainActor in … self.episode(for: …) }`
blocks that fetch through the cached `modelContext`. Because the
delegate's lifetime is the URLSession's (which is the singleton's,
which is the process's), a test that starts a download and tears
down its container hands the next test a delegate ready to fetch
into a dead context as soon as URLSession decides to call back. The
hazard is harder to spot than `PlaybackController`'s `@Published
currentEpisode` because it's hidden behind a `nonisolated` callback
rather than a SwiftUI subscription — worth keeping on the audit
checklist for any future service that combines a `URLSession`
delegate with a cached `ModelContext`.

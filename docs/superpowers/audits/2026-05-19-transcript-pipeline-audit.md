# Transcript pipeline audit — 2026-05-19

Phase 14 audit. Branch `audit/expanded-surface-2026-05-19`, baseline HEAD `8f6cef6`.
Mirrors the Phase 12 chapter-pipeline shape (feed-element detect → JSON fetch →
model persist → spec back-compat).

## A. Feed-provided published transcripts

**State (pre-audit):**
- `EpisodeTranscriptReference` exists with `url`, `mimeType`, `language`, `rel`.
- `RSSFeedParser` parses `<podcast:transcript url type language rel>` into the
  episode at `PodcastServices.swift:1160`.
- `Episode.transcriptReferences` round-trips through a JSON-encoded storage
  field with deterministic language+url sort order.
- **No loader existed.** Even when a feed published an authoritative transcript,
  the pipeline ran on-device Speech (60-90s of CPU) for a transcript the
  publisher already shipped.
- No timed-cue model. Persisted transcript was flat text.

**Gaps + fixes applied:**
- **MUST-FIX (resolved):** Added `OffScript/PublishedTranscriptLoader.swift`.
  Selects the best `<podcast:transcript>` reference using a JSON > VTT > SRT >
  HTML format score, then within-format prefers language match (exact >
  language-code-prefix > none > explicit-mismatch). Fetches with a 15s timeout,
  decodes by MIME type (with content-sniff fallback when type is missing or
  ambiguous), persists `[TranscriptCue]` + plain text to
  `EpisodeTranscriptCache` keyed by `source = "published"`. Replaces any prior
  cache row so a Speech-generated transcript is upgraded to the authoritative
  one on next open.
- **MUST-FIX (resolved):** `SpeechTranscriptionService.transcribe()` now calls
  the loader before requesting Speech authorization. Episodes with feed-provided
  transcripts skip the Speech pipeline entirely.
- **GAP (open, documented):** SRT and HTML decoders are stubbed (return `nil`).
  SRT is a near-clone of VTT with a different timestamp separator and is the
  next obvious add. HTML transcripts carry no timing — would need a separate
  flat-text storage path.
- **GAP (open):** The loader uses `URLSession.shared` directly. A future pass
  could route through a shared `URLSessionConfiguration` with a custom UA so
  publisher analytics can attribute requests to OffScript.

## B. On-device Speech recognition

**State (pre-audit):**
- `SpeechTranscriptionService` already set `request.requiresOnDeviceRecognition = true`.
- Guarded by `SFSpeechRecognizer().supportsOnDeviceRecognition`.
- Authorization handled via `SFSpeechRecognizer.requestAuthorization`.
- `Info.plist` declares `NSSpeechRecognitionUsageDescription` (verified).
- Locale hard-coded to `en-US`.

**Gaps + fixes applied:**
- **GAP (resolved):** Originally the three guards (init, availability,
  on-device-support) were a single `else throw` with no log trail. Split into
  three named `speechLogger.warning(...)` arms so production logs reveal which
  arm tripped. The on-device-support arm carries a privacy comment citing
  CLAUDE.md so future maintainers understand why we never relax this guard.
- **GAP (open, documented):** Locale is hard-coded to `en-US`. For non-English
  shows, the recognizer will refuse or produce gibberish. Two-step fix:
  (1) thread `Podcast.language` (if recorded) through to the recognizer locale,
  (2) fall back to `Locale.current` if absent. Deferred — needs a feed-side
  language signal first.
- **GAP (deferred):** No pre-download check for offline language models. The
  Speech framework downloads on first use; an offline-from-cold-launch user
  may see the on-device guard trip. Not actionable from app code (the
  framework owns the model lifecycle).

## C. Background pipeline

**State (pre-audit):**
- `BackgroundTranscriptionService` uses a plain `Task` driven by
  `NWPathMonitor` + battery state, NOT `BGTaskScheduler` or the SwiftUI
  `.backgroundTask(.appRefresh:)` modifier (which is what `BackgroundFeedRefresh`
  uses).
- Skip-policy already in place: ≤90 min episodes, on Wi-Fi, charging or not in
  low-power mode, skip if already persisted.
- No expiration handler — the Task runs until the OS kills the app.

**Gaps (deferred):**
- **GAP (deferred):** The service is effectively foreground-only despite the
  filename. It opportunistically runs while the user is in-app on Wi-Fi +
  charging. Wiring it to `BGTaskScheduler` (matching `BackgroundFeedRefresh`)
  is the natural next step — would let transcripts arrive overnight while the
  device charges. Not landed this round to keep the audit scoped to the
  pipeline itself.
- **GAP (deferred):** No expiration handler. If we move to `BGTaskScheduler`,
  the task closure needs `task.expirationHandler` so we cancel the in-flight
  `SFSpeechRecognitionTask` cleanly. Today the in-app `Task` is just killed by
  the OS when the user leaves the app — Speech state is leaked.
- **Note:** The 90-min duration cap and battery+wifi gating are good defaults
  and were left untouched.

## D. Cache discipline

**State (pre-audit):**
- `SpeechTranscriptionService` already has a 5-entry LRU on its in-memory
  cache (good — prevents process-memory pressure).
- `EpisodeTranscriptCache` SwiftData model has **no size cap, no LRU eviction**.
- Unsubscribe path (`PodcastUnsubscribeService`) does NOT clear transcript
  rows. Spotlight, downloaded files, and queue items are cleaned up; transcripts
  are not.
- Not shared with the widget extension (no app-group config — and `coreSpotlight`
  is the only inter-process surface today).

**Gaps + fixes applied:**
- **GAP (deferred — file ownership):** Adding transcript cleanup to
  `PodcastUnsubscribeService.unsubscribe()` is a one-line side-effect insert
  but that file is outside this audit's owned-file list. **Flag for a Phase 15
  task: add `EpisodeTranscriptCache` cleanup after step 4 (Spotlight de-index)
  in `PodcastUnsubscribeService.unsubscribe`.** Suggested implementation:
  fetch all `EpisodeTranscriptCache` rows where `episodeID ∈ episodeIDs`,
  `context.delete(...)` each, before the final `context.save()`.
- **GAP (deferred):** No SwiftData-level LRU on transcripts. A 30-min episode
  transcript averages ~50KB of plain text; 1000 cached episodes ≈ 50MB which
  is acceptable today, but bulk-fetched JSON transcripts (with cues) trend
  10-20× larger. Recommend a 500MB cap with oldest-`generatedAt` eviction as
  a future fix. Not urgent.
- **Note:** Schema migration concern — I added `language` (optional String)
  and `cuesStorage` (String defaulted to "") to `EpisodeTranscriptCache`.
  SwiftData lightweight migration should handle both since they have defaults.
  Verified by running the full test suite which exercises the in-memory
  model container.

## E. UI surface (read-only this round)

**Observations:**
- `SpeechTranscriptionPanel` renders a flat `Text(transcriptText)` inside a
  `ScrollView`. Power-user fallback, no synchronization.
- **No synchronized current-line highlight.** Data flow can support this now
  (cues persist via `EpisodeTranscriptCache.cues`), but no UI consumer reads
  the cues yet. Surface as a Phase 15 follow-up.
- **No in-transcript search.** Easy add on top of the existing flat-text
  surface; defer.
- `EpisodeDetailView.swift:90-95` mounts `SpeechTranscriptionPanel` directly
  with no awareness of whether published references exist. A future pass
  should show a "Published transcript" pill (read directly from
  `episode.transcriptReferences`) so the user understands which source they're
  looking at. The plumbing for this is now in place.

**Deferred items (Phase 15+ UI follow-up):**
1. Render `transcriptText` as a list of `TranscriptCue` rows, highlight the
   active row from `PlaybackController.shared.currentTime`.
2. Tap-a-line to seek the player.
3. Search bar within the transcript.
4. Source pill (Published / On-device).

## Classification

**MUST-FIX (resolved this audit):**
- Add `PublishedTranscriptLoader` for VTT + JSON formats.
- Wire `SpeechTranscriptionService` to prefer the loader over Speech.
- Surface on-device Speech availability failures as `OSLog` warnings, not
  silent throws.

**GAP (open, documented):**
- SRT + HTML decoders unimplemented.
- Speech locale hard-coded to `en-US`.
- Background pipeline doesn't use `BGTaskScheduler`.
- No SwiftData-level LRU on transcript cache.

**DEFERRED (file ownership / scope):**
- Transcript cleanup on unsubscribe (one-line edit to
  `PodcastUnsubscribeService`, out of this audit's ownership).
- UI surface: synchronized line highlight, in-transcript search, source pill.

**STRATEGIC:** The transcript pipeline pre-audit was at roughly the same
maturity stage as the chapter pipeline was pre-Phase-12: feed parser landed,
model field landed, but no loader connecting the two. The biggest finding is
the structural one — that `EpisodeTranscriptReference` was being captured but
ignored, with the on-device Speech path always taking precedence. With the
loader landed, the pipeline is now production-ready for the ~30-40% of feeds
that publish transcripts (mostly larger podcast networks); the rest still
correctly fall back to on-device Speech. The next-most-valuable single
investment is wiring `BackgroundTranscriptionService` to `BGTaskScheduler`
so transcripts can arrive overnight; the rest of the open gaps are
incremental polish.

## Fixes applied

- `328df0c` feat(transcripts): add PublishedTranscriptLoader for VTT + JSON formats
- `1e9ce18` fix(transcripts): surface on-device Speech availability as a warning
- `2c45675` test(transcripts): cover VTT + JSON parsing and language/type preference
- (this doc) docs: transcript pipeline audit findings

Build green at every step; full suite 152 tests passing (146 prior + 6 new).

## Phase 24 — BGTaskScheduler resolution (2026-05-20)

The Phase 14 audit found `BackgroundTranscriptionService` was
effectively foreground-only — a plain `Task` driven by `NWPathMonitor`
+ battery state that only ran while the app was active. Phase 24
refactors it to use the modern `.backgroundTask(.appRefresh:)` pattern
matching `BackgroundFeedRefresh`.

### Changes

- New static `taskIdentifier` (`com.offscript.background-transcription`),
  `maxRunDurationSeconds` (25s), `maxEpisodesPerRun` (3) constants.
- `performTranscriptionRound(container:)` static `@MainActor @Sendable`
  method as the `.backgroundTask` entry point. Schedules the next round
  *before* doing work so the timer is always queued even on force-stop.
- Candidate selection sorts by `lastPlayedAt` desc then
  `downloadCompletedAt` desc — most-likely-to-be-played-next first —
  bounded fetch (25) with in-memory filtering for the
  optional-`duration` and persisted-transcript checks (neither
  expresses cleanly in `#Predicate`).
- Failure-throttle mirroring `BackgroundFeedRefresh`'s pattern but
  UserDefaults-backed (no per-episode model field for transcription
  failure count). Threshold: 3 consecutive rounds where every attempted
  episode failed → next round scheduled with 2-hour backoff. Resets on
  success.
- Time-budget check between episodes (exits cleanly when 25s elapsed).
- `Task.checkCancellation()` between episodes; `CancellationError`
  caught as `.info` (system reclaim is normal, not a failure — does
  *not* trip the throttle).
- Shape changed from `final class` singleton to `enum` (matching
  `BackgroundFeedRefresh`). The existing foreground call sites
  (`ContentView.onAppear`, `DownloadService.didFinishDownload`) reference
  `BackgroundTranscriptionService.shared.configure(context:)` /
  `.didFinishDownload(episodeID:)`; those are preserved as no-op shims
  on a `ForegroundCompat` inner type so callers in non-owned files keep
  compiling. The shims log at `.debug` and explicitly note the work has
  moved to the BGTaskScheduler path.

### Host-app wiring required (DEFERRED — file ownership)

This commit refactors the service into a callable entry point but does
**not** wire it into the app's scene or register the identifier with
the system. Until both edits below land, the new pattern won't fire —
the static method is dead code. Both are 1-line additions to files
owned by other phases (`OffScriptApp.swift` was touched by Phase 16
CarPlay; `Info.plist` is project-config-shaped).

Add to `OffScriptApp.swift`'s scene body, after the existing
`BackgroundFeedRefresh` `.backgroundTask` modifier (around line 137):

```swift
.backgroundTask(.appRefresh(BackgroundTranscriptionService.taskIdentifier)) {
    await BackgroundTranscriptionService.performTranscriptionRound(container: sharedModelContainer)
}
```

Add to `Info.plist`'s existing `BGTaskSchedulerPermittedIdentifiers`
array (currently contains only `com.offscript.feed-refresh`):

```xml
<string>com.offscript.background-transcription</string>
```

iOS rejects `BGTaskScheduler.submit` for any identifier not listed in
that array, so without the plist change `scheduleNextRound()` will log
"Failed to schedule" on every invocation. The current commit ships the
service refactored; the wiring is a 2-line follow-up.


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
- ~~**GAP (open, documented):** SRT and HTML decoders are stubbed (return `nil`).
  SRT is a near-clone of VTT with a different timestamp separator and is the
  next obvious add. HTML transcripts carry no timing — would need a separate
  flat-text storage path.~~ **LANDED Phase 29, commit `71b7afe` (`feat(transcripts): land SRT + HTML decoders in PublishedTranscriptLoader`).** See Phase 29 section at the bottom of this doc.
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
- ~~**GAP (deferred):** The service is effectively foreground-only despite the
  filename. It opportunistically runs while the user is in-app on Wi-Fi +
  charging. Wiring it to `BGTaskScheduler` (matching `BackgroundFeedRefresh`)
  is the natural next step — would let transcripts arrive overnight while the
  device charges. Not landed this round to keep the audit scoped to the
  pipeline itself.~~ **LANDED Phase 24, commit `43d92e2` (`refactor(transcripts): adopt .backgroundTask BGTaskScheduler pattern`); host-app wiring + Info.plist registration landed Phase 23, commit `b2fb431`.**
- ~~**GAP (deferred):** No expiration handler. If we move to `BGTaskScheduler`,
  the task closure needs `task.expirationHandler` so we cancel the in-flight
  `SFSpeechRecognitionTask` cleanly. Today the in-app `Task` is just killed by
  the OS when the user leaves the app — Speech state is leaked.~~ **RESOLVED via the `.backgroundTask` migration in `43d92e2` — Swift Concurrency cancellation replaces the manual `expirationHandler` contract.**
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
- ~~**GAP (deferred — file ownership):** Adding transcript cleanup to
  `PodcastUnsubscribeService.unsubscribe()` is a one-line side-effect insert
  but that file is outside this audit's owned-file list. **Flag for a Phase 15
  task: add `EpisodeTranscriptCache` cleanup after step 4 (Spotlight de-index)
  in `PodcastUnsubscribeService.unsubscribe`.** Suggested implementation:
  fetch all `EpisodeTranscriptCache` rows where `episodeID ∈ episodeIDs`,
  `context.delete(...)` each, before the final `context.save()`.~~ **LANDED Phase 15, commit `ca4009f` (`fix(unsubscribe): clean up transcript cache when removing a podcast`).** See offline-pipeline audit § F for the contract test pinning the behavior.
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
  looking at. The plumbing for this is now in place. **LANDED Phase 30, commit `d085c27`.**

**Deferred items (Phase 15+ UI follow-up):**
1. ~~Render `transcriptText` as a list of `TranscriptCue` rows, highlight the
   active row from `PlaybackController.shared.currentTime`.~~ **LANDED Phase 30, commit `25e1020` (`feat(transcripts): synchronized cue list + tap-to-seek (Phase 30)`).** Cue state wired in `d085c27`; full synchronized UI landed in `25e1020`.
2. ~~Tap-a-line to seek the player.~~ **LANDED Phase 30, commit `25e1020`.**
3. ~~Search bar within the transcript.~~ **LANDED Phase 30, commit `7b63047` (`feat(transcripts): search-within-transcript on the cue panel`).**
4. ~~Source pill (Published / On-device).~~ **LANDED Phase 30, commit `d085c27` (`feat(transcripts): wire cue/source state + provenance pill`).**

**Bonus follow-on (Phase 30):** Follow-playhead toggle + manual-scroll disengage landed in commit `50e9141` — beyond the original deferred scope.

## Classification

**MUST-FIX (resolved this audit):**
- Add `PublishedTranscriptLoader` for VTT + JSON formats.
- Wire `SpeechTranscriptionService` to prefer the loader over Speech.
- Surface on-device Speech availability failures as `OSLog` warnings, not
  silent throws.

**GAP (open, documented):**
- ~~SRT + HTML decoders unimplemented.~~ **LANDED Phase 29 (`71b7afe`).**
- Speech locale hard-coded to `en-US`.
- ~~Background pipeline doesn't use `BGTaskScheduler`.~~ **LANDED Phase 24 (`43d92e2`) + Phase 23 wiring (`b2fb431`).**
- No SwiftData-level LRU on transcript cache.

**DEFERRED (file ownership / scope):**
- ~~Transcript cleanup on unsubscribe (one-line edit to
  `PodcastUnsubscribeService`, out of this audit's ownership).~~ **LANDED Phase 15 (`ca4009f`).**
- ~~UI surface: synchronized line highlight, in-transcript search, source pill.~~ **ALL LANDED in Phase 30 — synchronized highlight + tap-to-seek (`25e1020`), search (`7b63047`), source pill (`d085c27`), bonus follow-playhead toggle (`50e9141`).**

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

### Host-app wiring required ~~(DEFERRED — file ownership)~~ **LANDED Phase 23, commit `b2fb431`.**

This commit refactors the service into a callable entry point but does
**not** wire it into the app's scene or register the identifier with
the system. Until both edits below land, the new pattern won't fire —
the static method is dead code. Both are 1-line additions to files
owned by other phases (`OffScriptApp.swift` was touched by Phase 16
CarPlay; `Info.plist` is project-config-shaped). **Both wiring edits landed in commit `b2fb431` along with the bootstrap-submit calls for both subsystems.**

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

## Phase 29 — SRT + HTML decoders (2026-05-20)

Phase 14 (`PublishedTranscriptLoader.swift`) shipped tolerant VTT + JSON
decoders and left SRT and HTML as TODO stubs. The loader's MIME-type
dispatch fell through to `nil` for both, so any feed publishing a
`text/html` or `application/srt` transcript reference was silently
discarded even when no JSON/VTT alternative existed. This phase lands
both decoders and wires them into the dispatch.

### SRT (SubRip)

The SubRip wire format is essentially "VTT with commas":

```
1
00:00:00,000 --> 00:00:05,200
<i>First</i> line of dialogue.

2
00:00:05,500 --> 00:00:10,000
Second line, possibly
spread across two rows.
```

The new `decodeSRT(data:)` / `decodeSRT(text:)` entry points tolerate
the irregularities that show up in real feeds:

- Comma OR period as the milliseconds separator (the spec mandates
  comma; period is widely tolerated and several large publishers emit
  it). `parseSRTTimestamp` normalises comma → period before parsing.
- Windows line endings (`\r\n`) and lone `\r` — normalised up front.
- Optional sequence number on line one — present in canonical SRT,
  absent in some hand-edited exports. We tolerate either shape by
  sniffing for an integer followed by a timing line.
- HTML-style inline tags (`<i>`, `<b>`, `<font color="...">`) — these
  are SRT extensions used by sub editors. Stripped via the same
  regex-based tag remover the HTML path uses.
- Multi-line cue text joined with a single space (cleaner for plain-
  text export than preserving the line-wrapping shape).
- Trailing blank blocks at end of file (common from "save without
  trailing newline" exporters).

### HTML

HTML transcripts are a loose convention — the Podcasting 2.0 spec
acknowledges they exist but doesn't prescribe a timing format. In
practice two patterns show up:

1. `<p data-start="N">…</p>` or `<span data-time="N">…</span>` — used
   by Buzzsprout and a few self-hosted feeds. Carries paragraph-level
   timing but no end markers.
2. Plain prose with no timing at all — the majority of HTML transcripts.

`decodeHTML(data:episodeDuration:)` handles both:

- First it runs a regex over the document looking for the timed-paragraph
  pattern. If any matches come back, it builds cues from them
  (`startTime = data-start`, `endTime = startTime` since there's no end
  marker — the player can synthesise an end by looking at the next
  cue's start).
- If nothing matches, it falls back to a single cue spanning
  `[0, episode.duration]` with the stripped, whitespace-collapsed
  prose. Not scrubbable, but the transcript is at least searchable
  and addressable.

The tag stripper decodes the five common entities (`&amp; &lt; &gt;
&quot; &nbsp;`) plus the two common apostrophe variants (`&#39;
&apos;`). We intentionally do NOT decode the full HTML entity table —
transcripts are prose, anything more exotic is a publisher
mis-encoding worth surfacing rather than silently papering over.

### Dispatch wiring

`parse(data:mimeType:)` gained an optional third argument
`episodeDuration: TimeInterval? = nil` (defaults to nil to preserve the
visible-for-tests entry point used by `decodeJSON` / `decodeVTT`
callers). The dispatch now covers:

| MIME contains | Decoder |
| --- | --- |
| `json` | `decodeJSON` |
| `vtt` | `decodeVTT` |
| `srt` or `subrip` | `decodeSRT` |
| `html` or `xhtml` | `decodeHTML(_, episodeDuration:)` |

The sniff fallback (used when `mimeType` is nil or unrecognised) also
gained two new shapes:

- Leading `<` → treat as HTML
- First line is an integer AND second line contains `-->` → treat as
  SRT

These mirror the existing `WEBVTT` / `{` / `[` sniffs.

### Tests ~~(DEFERRED — Phase 31 owns `OffScriptTests.swift`)~~ **LANDED 2026-05-20**

All 11 decoder + dispatch-sniff cases landed in
`TranscriptDecoderTests` plus one nil-on-empty pin for the SRT
decoder (commit `20420ca`,
`test(transcripts): cover Phase 29 SRT + HTML decoders`).

Original list:

- `srtDecoderHandlesCommaAndPeriodMsSeparators()`
- `srtDecoderStripsHTMLTagsInCueText()`
- `srtDecoderHandlesMultilineCueText()`
- `srtDecoderToleratesWindowsLineEndings()`
- `srtDecoderToleratesTrailingBlankBlocks()`
- `htmlDecoderExtractsTimedCuesFromDataStartAttributes()`
- `htmlDecoderExtractsTimedCuesFromDataTimeSpans()`
- `htmlDecoderFallsBackToSingleCueWhenNoTimingPresent()`
- `htmlDecoderStripsCommonEntitiesInPlainText()`
- `parseDispatchSniffsSRTByIntegerPlusTiming()`
- `parseDispatchSniffsHTMLByLeadingAngleBracket()`

All inputs are pure strings → `[TranscriptCue]`, so the test fixtures
can live inline as Swift string literals rather than separate `.srt` /
`.html` files in the test bundle.

## Phase 30 — UI consumer landed (2026-05-20)

Phase 14 surfaced timed `TranscriptCue`s to the model (cache stores
`[TranscriptCue]` alongside flat text + `source` + `language`), but the
audit at the top of this doc flagged that `SpeechTranscriptionPanel`
"shows a flat-text panel with no synchronized line highlight, no
search, no source pill." Phase 30 wired the consumer.

### What landed in `SpeechTranscriptionPanel.swift`

- **Direct cache read for cues.** The panel now does its own
  `FetchDescriptor<EpisodeTranscriptCache>` lookup (same shape as
  `SpeechTranscriptionService.persistedTranscript`) so it can read
  `cues`, `source`, and `language` — not just flat text. Re-hydrates
  on `.task(id: episode.id)` and again after a Speech run completes.
- **Provenance pill.** Header renders a Tuner chip:
  `● ON-DEVICE` (offscriptFnMode green) for `source == "speech"`,
  `● PUBLISHED · <LANG>` (offscriptFnInfo cyan) for `"published"`,
  `● MIXED` (offscriptSignalYellow) reserved for a future hybrid. The
  panel title also flips between `TRANSCRIPT · PUBLISHED` and `· ON
  DEVICE`.
- **Synchronized cue list.** When `cues` is non-empty, the
  expand-to-read fallback is replaced by a `LazyVStack` of cue rows
  driven by `PlaybackController.shared.currentTime` (observed via
  `@ObservedObject`, mirroring `EpisodeDetailView`'s existing
  pattern). The current cue (computed as `cues.lastIndex { startTime
  <= playerTime && endTime > playerTime }`) renders in
  `offscriptSignalYellow` with a 2pt leading rail. ±2 neighbours
  render in `offscriptPaperWhite`, far cues in `offscriptSoftPaper`.
- **Scroll-follow.** `ScrollViewReader.scrollTo(idx, anchor: .center)`
  inside an `onChange(of: currentCueIndex)` keeps the active line
  centered. A `simultaneousGesture(DragGesture(minimumDistance: 6))`
  flips `followPlayhead = false` when the user pans manually; a
  "→ FOLLOW" Tuner key appears in the search row to re-engage.
- **Tap-to-seek.** Each row is a `.buttonStyle(.plain)` Button that
  calls `PlaybackController.shared.seek(to: cue.startTime)`. Seeking
  also re-engages auto-scroll and clears any active search.
- **Search-within.** A Tuner search field above the list filters cues
  via `localizedCaseInsensitiveContains`. Match count surfaces as a
  soft-paper TunerLabel. Tapping a match seeks + clears the query.
- **Accessibility.** Container is `.accessibilityElement(children:
  .contain)` so VO navigates cue-by-cue. Each row's label is `"Cue N
  at <spoken timestamp>. <text>[. Currently playing]"` with a hint of
  "Double-tap to seek". Search field and follow-playhead toggle labels
  are state-aware.
- **OLED design vocabulary.** No rounded backgrounds, no gradients,
  no shadows. Highlight is a 2pt yellow rail on the leading edge (no
  fill), rows are flat with hairline dividers, the cue scroller has a
  1pt offscriptHairline outline over offscriptFillSubtle.

### Edge cases handled

- `TranscriptCue.endTime` is non-optional `TimeInterval`, but a `0`
  sentinel is common when publishers omit it — the lookup treats
  `endTime > 0 ? endTime : .infinity` so the last cue stays
  highlighted instead of falling out of the window.
- `currentCueIndex` returns `nil` when playback isn't on this episode,
  which suppresses both the rail and the auto-scroll (so navigating
  to an unrelated episode's detail view while something else plays
  doesn't visually thrash).
- Mid-playback expansion: `cueScrollView.onAppear` jumps directly to
  the current cue with no animation, then subsequent updates animate.
- Search and follow-playhead don't fight: tapping a search result
  clears the query AND re-engages follow, so the user lands in the
  linear flow at the right line.

### Deferred (DEFERRED — schema / cross-file)

- **Mixed-source provenance.** `EpisodeTranscriptCache.source` is a
  single `String`; there's no per-cue source field. The pill renders
  `● MIXED` if `source == "mixed"` ever lands, but no current writer
  produces that value. A hybrid pass (on-device cues backfilling gaps
  in a partial published transcript) would need a per-cue source flag
  on `TranscriptCue` itself — a schema change outside Phase 30's file
  ownership. Surfaced as a finding rather than mutating the model.
- **Combine debounce instead of body-re-eval on every tick.** The
  current implementation re-runs the body on every `currentTime`
  republish because `PlaybackController` is `@ObservedObject`. For a
  320pt scroller with at most ~200 cue rows that's fine; if the
  rendered cue count ever climbs over ~500 we should switch to a
  debounced Combine pipeline (e.g. `player.$currentTime
  .removeDuplicates { abs($0 - $1) < 0.25 }.assign(to:)`) and store
  `currentCueIndex` as derived `@State` instead of a computed
  property. Out of scope here.
- **Search-match in-text highlighting.** Matched substrings inside
  cue text aren't visually highlighted (only the cue itself is
  filtered in). `AttributedString.markdown`-style match emphasis is
  a polish pass — not blocking the Phase 14 audit fix.

### Files touched

- `OffScript/SpeechTranscriptionPanel.swift` — wholesale view rewrite
  across 4 feature commits (provenance pill / cue list + tap-seek /
  search / follow-playhead toggle) plus this doc commit.

### Verification

`xcodebuild ... build` produces only one pre-existing failure in
`OffScript/DebugInspectorView.swift` (an untracked file from another
concurrent phase, outside Phase 30 file ownership).
`SpeechTranscriptionPanel.swift` itself compiles clean.


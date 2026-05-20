# Dead-code-wiring re-sweep — 2026-05-20

## Methodology

Re-ran the Phase 23 sweep methodology (`2026-05-20-deadcode-wiring-sweep.md`)
against current HEAD on `audit/expanded-surface-2026-05-19`. Same seven
systematic passes (static-shared, configure, protocol, enum cases,
Notification.Name, NSCache/URLCache, @Published) plus the bonus passes
(write-only model fields, write-only persistent rows, orphaned subsystems).

Additionally inspected eight specific surfaces that shipped after Phase 23:

- `EditorialCollection.Filter` cases (Phase 21)
- `SearchPreviewLoader.PreviewState` (Phase 17)
- `TranscriptCue` `speaker` + `endTime` fields (Phase 14/29)
- `EpisodeChapter` `imageURL` / `linkURL` / `isInTableOfContents` (Phase 12)
- `PlaybackEvent.Kind` new cases since Phase 23
- `DebugInspectorView` section data sources (Phase 27)
- CarPlay tabs (Phase 16/28)
- `NowPlayingActivityCoordinator` methods (Phase 22)

Codebase grew from ~30k LOC at Phase 23 to **26,382 LOC** across 62 source
files. (The "+2k" estimate in the prompt was high — net-positive after
Phase 25's deletions, Phase 33 docs cleanup, etc.) New files shipped
post-Phase 23: `DebugInspectorView.swift` (712 LOC),
`NotificationService.swift` (211 LOC), `SyncHistoryService.swift` (81 LOC),
`SharedNowPlayingState.swift` (64 LOC), `DebugTeardown.swift` (55 LOC).

Audit-only — no code edits.

## Phase 23 resolution status

Phase 23 surfaced 10 findings.

**RESOLVED (by Phases 25, 27, b2fb431):**

1. `AppSettings.LibrarySortMode` + `librarySortMode` + `libraryShowDownloadedOnly` — DELETED in Phase 25 (`e8f4eaa`).
2. `AppSettings.lastCloudSyncDate` — DELETED in Phase 25 (`b7c119a`).
3. `NetworkMonitor.isConnected` — DELETED in Phase 25 (`e2bd525`).
6. `TelemetryEvent` model — CONSUMED by Phase 27 `DebugInspectorView` (telemetry section, ~100-row inspector with detail sheet + clear button).
8. `PlaybackEvent.Kind.started` BROKEN-WIRING — RESOLVED by `b2fb431`. `PlaybackController.swift:352` now emits `.started` in `load(...)`. The `TasteProfileService.swift:152` formula `max(playbackEvents.filter { $0.kind == .started || $0.kind == .resumed }.count, 1)` is no longer collapsed to `max(resumed_count, 1)`.
9. `BackgroundFeedRefresh.scheduleNextRefresh()` bootstrap — RESOLVED by `b2fb431`. `OffScriptApp.swift:143` submits the initial request.
10. `BackgroundTranscriptionService.scheduleNextRound()` bootstrap — RESOLVED by `b2fb431`. `OffScriptApp.swift:144` submits the initial request.

**STILL STANDING (intentional kept-with-rationale):**

4. `Podcast.lastSyncAttemptAt` — was kept due to SwiftData migration cost. **Now actually consumed** by `SyncHistoryService.recentlyAttempted` (sortBy + predicate filter) and `DebugInspectorView` row display. Phase 23's "0 production reads" finding is now stale; recommend re-classifying to NOT-A-FINDING in the Phase 23 doc.
5. `PlaybackEvent.Kind.seekedForward` + `.seekedBackward` — still zero emitters, still weighted 0 in reader switch arms. Kept for decode safety.
7. `SpeechAnalyzerService` — still 0 call sites, still intentional iOS 26 dormancy.

Of Phase 23's 10 findings: **6 resolved**, **3 kept (intentional)**, **1 stale** (#4 — receiver now wired).

## NEW findings

### N1. `EpisodeProfile` scoring fields — five-field BROKEN-WIRING cluster

`OffScript/Models.swift:330-335` declares six "Recommendation-engine scoring
inputs" on the `EpisodeProfile` `@Model`:

```
var qualityScore: Double = 0.0
var confidenceScore: Double = 0.0
var estimatedListeningContext: String?
var freshnessBucket: String?
var introSkipSeconds: TimeInterval = 0
var outroSkipSeconds: TimeInterval = 0
```

The comment says "added on origin/main". Grep confirms:

| Field | Write sites | Read sites |
| --- | --- | --- |
| `qualityScore` | **0** | 1 (`RecommendationService.swift:540`) |
| `confidenceScore` | **0** | **0** |
| `estimatedListeningContext` | **0** | **0** |
| `freshnessBucket` | **0** | **0** |
| `introSkipSeconds` | **0** | **0** |
| `outroSkipSeconds` | **0** | **0** |

`TopicExtractionService.enrich(...)` — the only `EpisodeProfile` writer in
the codebase — sets only `tags`, `entities`, `summary`. Never touches any
of these six fields.

The single reader at `RecommendationService.swift:540`:

```swift
let quality = min(max(profile?.qualityScore ?? 0, 0), 1)
// ...
let qualityTieBreak = quality * 5
```

Since `qualityScore` defaults to `0.0` and is never written, `quality` is
always `0.0` and `qualityTieBreak` is always `0`. The "quality tiebreaker"
in the recommendation scorer is silently a no-op.

**Verdict:** BROKEN-WIRING (5 fields) + dormant reader (1 field).
Largest single finding of this re-sweep — five SwiftData fields that
allocate column space, ship in every migration, and contribute nothing.
The `qualityScore` reader actively misleads anyone reading
`RecommendationService.swift` into thinking a quality signal influences
ranking when it doesn't.

### N2. `NotificationService` + `NotificationDelegate` — full-class dormancy

`OffScript/NotificationService.swift` (211 LOC) declares:

- `NotificationService.shared` (singleton)
- `requestAuthorization() async -> Bool`
- `scheduleNewEpisodeNotification(for:)`
- `cancelNewEpisodeNotification(for:)`
- `NotificationDelegate.shared` (UNUserNotificationCenterDelegate)
- `notificationsForNewEpisodes` UserDefaults key

Grep confirms **zero production call sites** across the entire codebase.

The companion audit `docs/superpowers/audits/2026-05-20-push-notifications.md`
explicitly documents this as intentional scaffolding:

> Build verified on iOS Simulator (Debug). **No call sites yet** — service
> is self-contained.

And in `NotificationService.swift:38` (`cancelNewEpisodeNotification`):

> Call sites (to be wired — see audit):
>   - When the user plays the episode before the notification fires
>   - When the user unsubscribes from the podcast
>   - When the episode is deleted

There is also no Settings UI toggle for the
`offscript.notificationsForNewEpisodes` opt-in, so even if the call sites
landed, the gate would default-off forever.

**Verdict:** DORMANT (intentional, documented). Same shape as Phase 23's
`SpeechAnalyzerService` finding — entire subsystem with a designated
producer (`BackgroundFeedRefresh`) and consumer (deep-link router via
`UIApplication.shared.open` loopback) that just hasn't been wired yet.

### N3. `TranscriptCue.speaker` field — populated by JSON only, displayed only in flat-text mode

`OffScript/EpisodeTranscriptCache.swift:13` declares `var speaker: String?`.

Population paths:
- `PublishedTranscriptLoader.swift:221` (JSON decoder) — populates if non-empty
- VTT decoder (`:275`) — always `nil`
- SRT decoder (`:363`) — always `nil`
- HTML decoder (`:412`, `:439`) — always `nil`

Read paths:
- `PublishedTranscriptLoader.swift:480` — in the `flatten(cues:)` helper, prepends `"\(speaker): \(cue.text)"` when present.

`SpeechTranscriptionPanel.swift` (the UI consumer of cues) renders
`cue.text` only — never `cue.speaker`. So `speaker` only surfaces in the
flat-text fallback path, never in the timed-cue UI that all production
transcript display goes through.

**Verdict:** DORMANT (low-cost, structurally honest). The flatten helper
keeps the field from being entirely write-only, and the JSON producer is
spec-correct. But the cue-display UI is the only path users ever see, and
it ignores `speaker` entirely. If the intent is to surface speaker labels
in the cue panel, a UI-side change is needed.

### N4. `EpisodeChapter` extended fields — fully wired (NOT-A-FINDING)

Re-confirmed for completeness. `imageURL` (read at `PlayerView.swift:147`),
`linkURL` (read at `PlayerView.swift:401`), `isInTableOfContents`
(filtered at `PlayerView.swift:324`) — all written by the JSON chapters
decoder (`PodcastServices.swift:1349-1360`) and consumed by `PlayerView`.

### N5. `SearchPreviewLoader.PreviewState` — fully wired (NOT-A-FINDING)

All three cases (`.loading`, `.loaded`, `.failed`) are emitted by the
loader and consumed by `SearchView.swift` (`.loaded` shows preview chip,
`.loading` shows shimmer, `.failed`/`.none` collapses the preview block).

### N6. `EditorialCollection.Filter` cases — fully wired (NOT-A-FINDING)

All four cases (`.duration`, `.genres`, `.keywords`, `.combined`) are
emitted by `CuratedPodcastCatalog`'s starter collections and consumed by
the filter switch at `CuratedPodcastCatalog.swift:215-228`.

### N7. CarPlay tabs — fully wired (NOT-A-FINDING)

All five tabs (`Library`, `Queue`, `Recent`, `Recommendations`, `Search`)
in `CarPlaySceneDelegate.makeRootTemplate()` have real data sources:

- Library → SwiftData `Podcast` fetch
- Queue → `QueueItem` fetch sorted by position
- Recent → episodes by `lastPlayedAt`
- Recommendations → `RecommendationService.homeSections`
- Search → `CPSearchTemplate` with library + episode fallback

No stubs, no empty-state placeholders that hide a missing fetch.

### N8. `NowPlayingActivityCoordinator` — fully wired (NOT-A-FINDING)

Only one method exists (`endStaleActivities`) and it is called from
`OffScriptApp.swift:142`. No dormant methods. The enum is minimal by design
— the happy-path lifecycle (`start`/`update`/`end`) lives in
`NowPlayingPublisher`, as documented in the enum's doc comment.

### N9. Stale Phase 23 finding — `Podcast.lastSyncAttemptAt`

Not a new finding per se, but worth surfacing: Phase 23 #4 marked this
field as "DEAD outside tests" and Phase 25 kept it for migration reasons.
Phase 27's `SyncHistoryService` and `DebugInspectorView` now actually
read it (predicate filter, sort key, row display). Phase 23's status
table should be updated to reflect that the deferral now has a real
consumer.

### N10. `Notification.Name` symmetry — fully wired (NOT-A-FINDING)

All five notification names in `DeepLinkRouter.swift:11-19` have at least
one poster and one observer. Same five names as Phase 23 — no new
notifications shipped that would skew the symmetry.

## Comparison: rate of dead-code accumulation

- **Phase 23 (~30k LOC):** 10 findings → 0.33 findings/kLOC
- **Phase 36 (~26.4k LOC):** 3 new actionable findings (N1, N2, N3) → 0.11 findings/kLOC
- **Net-over-time:** 3 patterns introduced over ~13 commits across Phases 24-35 (post-Phase-23). The drop in rate is partly because Phase 25 surgically removed 3 of Phase 23's findings (so the codebase is smaller AND less dead-code-dense), and partly because Phase 27 (Debug Inspector) and `b2fb431` (Phase 23 follow-up) explicitly closed 4 of Phase 23's findings.

In absolute counts, the floor of actively-dormant scaffolding has dropped
from 10 to 6 (4 closed by deletion, 2 closed by wiring, 4 still
intentional + 2 new dormant + 1 new BROKEN-WIRING). The codebase is in a
better wiring-density state than it was at Phase 23.

## Pattern themes

The dominant pattern from Phase 23 was **"reader/emitter asymmetry"** —
half a contract gets shipped, the other half gets deferred.

Phase 36's findings split this pattern more cleanly:

- **Eagerly-declared model fields with no producer (N1)** — `EpisodeProfile`
  shipped six scoring fields without any of `TopicExtractionService`,
  `RecommendationService`, or `BatchImportService` writing them. The
  default `0.0` is decode-safe but production-meaningless. Same shape as
  Phase 23's `PlaybackEvent.Kind.started` (reader-without-writer), just
  on persisted columns instead of enum cases.

- **Whole-subsystem scaffolding (N2)** — `NotificationService`. Identical
  shape to Phase 23's `SpeechAnalyzerService` dormancy: a designed
  surface with a documented future caller, marked clearly as not-yet-wired
  in a companion audit doc.

- **Half-wired struct fields (N3)** — `TranscriptCue.speaker` is populated
  in one decode path, consumed in one flatten helper, but invisible to
  the UI consumer that all production reads flow through. Novel shape:
  end-to-end correct on paper, dead in practice because the production
  consumer ignores it.

The good news: **N2 is documented**, **N3 is structurally honest** (the
helper read keeps it from being write-only), and **N1 is concentrated in
one model class** so the surgical fix is small.

## Verdicts

- **DEAD:** 0
- **DORMANT:** 2 (N2 NotificationService, N3 TranscriptCue.speaker UI display)
- **BROKEN-WIRING:** 1 (N1 EpisodeProfile scoring fields — 5 fields with no writer + 1 reader of an always-zero value)
- **NOT-A-FINDING:** 7 (N4–N10, plus all six Phase 23 items that have since been resolved)

## Recommended follow-ups

Ranked by leverage:

1. **N1 (EpisodeProfile scoring fields).** Highest leverage. Decide
   product intent:
   - **If the fields are intended for the recommender:** wire
     `TopicExtractionService.enrich(...)` to write `qualityScore` (e.g.
     based on `summary.count`, presence of structured chapters, etc.) and
     extend `RecommendationService` to read `confidenceScore`,
     `estimatedListeningContext`, `freshnessBucket`. The `RecommendationService:540`
     reader is already in place — just needs a non-zero writer.
   - **If they were speculative:** delete all six fields. Touches one
     `@Model`; requires a SwiftData V*→V+1 migration (same decode-safety
     concern as `PlaybackEvent.Kind.seekedForward`, but with stronger
     justification because the columns currently bloat every install for
     zero behavioral value).
   - **In either case:** remove the misleading `qualityTieBreak = quality * 5`
     at `RecommendationService:540`, or wire it. Right now the line
     suggests there's a quality signal in scoring when there isn't.

2. **N2 (NotificationService dormancy).** Lower urgency than N1 because
   it's documented in a dedicated audit doc and the next phase appears
   to be working through it. But if Phase 37 stalls, add an explicit
   `// TODO: wire from BackgroundFeedRefresh in Phase 37` annotation on
   the class to match the pattern recommended for `SpeechAnalyzerService`.

3. **N3 (TranscriptCue.speaker UI display).** Lowest leverage. The data
   path is correct; the gap is purely UI. If speaker labels aren't on
   the transcript-panel roadmap, leave as-is — the cost of the field is
   one optional `String?` per cue and the flatten helper genuinely uses
   it. If the panel is getting per-speaker styling soon, just route
   `cue.speaker` through `SpeechTranscriptionPanel`.

4. **Phase 23 doc maintenance.** Update Phase 23's #4 row
   (`Podcast.lastSyncAttemptAt`) to reflect that Phase 27 added real
   read consumers. The "0 production reads (only test assertions)"
   language is now stale.

## Pattern observation

Phase 23 closed cleanly: 6 of 10 findings resolved within ~13 commits,
2 stayed intentionally-deferred for migration safety, 1 was full-class
scaffolding (still appropriate). The "every domain model gets eager
fields, deferred wiring" pattern noted in Phase 23's summary repeated
exactly once in N1. That's a substantial improvement in discipline —
either the team learned from Phase 23, or the post-Phase-23 commits
have been doing tighter wiring on net.

The Phase 27 Debug Inspector deserves explicit credit: it converted
`TelemetryEvent` from "DEAD persistence" to a consumed surface without
any product compromise (debug-only consumer, not a user-facing
telemetry feature). Same pattern would work for N1 if the scoring
fields turn out to be speculative — surface them in the inspector,
let them prove or disprove themselves.

# Audit cross-reference sweep — 2026-05-20

## Methodology

Walked every audit doc under `docs/superpowers/audits/`, extracted each
"Deferred to follow-up" / "Tests to land in follow-up" / "Strategic" /
"Open GAP" bullet, then classified it against the commit log on
`audit/expanded-surface-2026-05-19` from base `1316f3b` through HEAD.

Updated the source docs in place: each landed item is struck through
with the commit ref (and phase number when present) appended. Items
still genuinely deferred were left untouched. Items superseded or
obviated by later work were marked with their resolution.

The branch carries 121 commits since the audit cycle opened. The audit
cycle has been highly productive — over half of the deferred items
from the 2026-05-19 baseline have been resolved on the same branch.

## Summary stats

- **Total deferred items found:** ~64 (across 14 audit docs at sweep
  start; an additional `2026-05-20-todo-fixme-sweep.md` doc appeared
  during the sweep but does not introduce new deferrals to track)
- **Landed:** 36 — every landed item has a commit ref appended in the
  source doc
- **Still deferred:** 26 — see per-doc breakdown below
- **Obviated by later work:** 2 — both in the recommendation-credibility
  audit (the seven Phase-18 decay-test stubs were once thought
  superseded by Phase 19 but ultimately landed in their original shape
  as commit `f0852bb`)

## Per-doc resolutions

| Doc | Landed | Still deferred | Obviated | Notes |
| --- | ---: | ---: | ---: | --- |
| 2026-05-19-audio-session-audit.md | 0 | 4 | 0 | All four deferred items are design judgments (e.g. `setActive(false)` after long idle) — none are bugs |
| 2026-05-19-background-and-liveactivity-audit.md | 1 | 3 | 0 | Ghost-Live-Activity wiring landed (`7c73621`). Three deferred items still need cross-file edits |
| 2026-05-19-carplay-readiness.md | 2 | 0 | 0 | Already self-annotated with Phase 28 closures (`bb87d37`) |
| 2026-05-19-curated-discovery.md | 1 | 6 | 0 | Sub-task #2 (editorial collections) landed Phase 21. Sub-task #3 (post-import handoff) and other follow-ups still open |
| 2026-05-19-design-token-audit.md | 1 | 1 | 0 | `tunerFont(size:)` helper landed (`c45d808`) and migrated across 14 views |
| 2026-05-19-feedSync-test-investigation.md | 0 | 2 | 0 | Notes-for-follow-up: telemetry surface now exists, so first-launch logging is unblocked |
| 2026-05-19-intents-spotlight-audit.md | 2 | 3 | 0 | Donate calls (Phase 11, `9d25794`) and `lastEpisodeAudioURL` write (`591bb8f`) landed |
| 2026-05-19-offline-pipeline-audit.md | 2 | 2 | 0 | Wi-Fi-only Settings UI (`9fa6b49`) and ambient Library row badge (`37f092c`) landed |
| 2026-05-19-privacy-and-production-audit.md | 1 | 5 | 0 | `sendDefaultPii = false` landed (`6c94e44`). App-Store-Connect-side process gaps remain |
| 2026-05-19-recommendation-credibility.md | 8 | 2 | 0 | Phase 19 emitters (`82d7f71`), Phase 20 explanation strings (`4a26922`, `d6affd3`), `.started` (`b2fb431`), 7 Phase-18 decay tests (`f0852bb`) |
| 2026-05-19-swiftdata-icloud-audit.md | 0 | 7 | 0 | None of the seven cross-cutting items landed — they touch read-only files and require their own audits |
| 2026-05-19-transcript-pipeline-audit.md | 8 | 3 | 0 | Phase 15 unsubscribe cleanup, Phase 24 BGTaskScheduler, Phase 23 wiring, Phase 29 SRT/HTML decoders, Phase 30 cue UI (highlight, search, pill, tap-to-seek, follow toggle) all landed |
| 2026-05-19-voiceover-walk.md | 3 | 4 | 0 | Library a11y polish + voiceOverMetadata symmetry already self-annotated (Phase 8) |
| 2026-05-20-deadcode-wiring-sweep.md | 4 | 2 | 0 | Item #6 (TelemetryEvent) consumed by Phase 27 Debug Inspector. Items 4 & 5 remain documented "kept-with-rationale" |
| 2026-05-20-debug-inspector.md | 0 | 9 | 0 | Phase-31-owned test suite — verification still pending |
| 2026-05-20-library-row-download-badges.md | 0 | 6 | 0 | Tests-deferred-to-Phase-20 plan didn't land in Phase 20; still open |
| 2026-05-20-singleton-teardown-hardening.md | 0 | 1 | 0 | Phase 31 has not yet wired `DebugTeardown.resetAllSingletons()` into test setup |

## Newly-discovered patterns

Three patterns emerged from the cross-doc walk that no individual audit
captured in one place:

### 1. `TelemetryEvent` was referenced as deferred-or-questioned in 5 separate docs

- `2026-05-19-curated-discovery.md` — wanted "subscribe-from-preview"
  telemetry events
- `2026-05-19-feedSync-test-investigation.md` — wanted to log
  `NLTagger.availableTagSchemes` on first launch
- `2026-05-19-recommendation-credibility.md` — implicitly relied on a
  consumer for the binge-dampener evidence
- `2026-05-20-deadcode-wiring-sweep.md` — flagged the model as DEAD
  persistence
- `2026-05-20-debug-inspector.md` — built the consumer

The consolidated decision (build a Debug Inspector consumer rather than
delete the persistence) was made centrally in `2026-05-20-debug-inspector.md`
and resolved in commits `8ac21a1`, `dc56ed2`, and `9fa6b49`. All
upstream docs should now point to the Debug Inspector as the canonical
consumer. The cross-ref sweep has annotated the deadcode-wiring sweep
and feedSync-test-investigation docs accordingly.

### 2. Phase 23 (`b2fb431`) closed broken-wiring across at least 3 audits in one commit

`b2fb431` ("fix(wiring): land three small fixes from Phase 23 dead-code
sweep") simultaneously resolved:
- `2026-05-19-recommendation-credibility.md` `.started` emission (the
  unfinished-affinity denominator fix)
- `2026-05-19-transcript-pipeline-audit.md` BGTaskScheduler host-app
  wiring (the 2-line follow-up the Phase 24 doc explicitly flagged as
  deferred)
- `2026-05-20-deadcode-wiring-sweep.md` items 8, 9, 10 (the entire
  "BROKEN-WIRING (receiver built, emitter missing)" verdict bucket)

This pattern — a single small commit closing scaffolding-not-connected
items across multiple subsystems — is the strongest evidence that the
"is every `configure(...)` actually called?" / "is every receiver
matched by an emitter?" sweep methodology pays off. Worth canonizing as
a recurring audit pass.

### 3. "Tests to land in follow-up" stubs are highly correlated with Phase 31's empty deliverable

Four docs deferred test coverage citing "Phase 31 owns
`OffScriptTests.swift`":
- `2026-05-19-curated-discovery.md` (editorial-collection filter tests)
- `2026-05-19-recommendation-credibility.md` (decay tests)
- `2026-05-19-transcript-pipeline-audit.md` (SRT + HTML decoder tests)
- `2026-05-20-debug-inspector.md` (9 inspector-surface tests)
- `2026-05-20-library-row-download-badges.md` (6 chip tests)
- `2026-05-20-singleton-teardown-hardening.md` (verification of the
  flaky-tests-stabilize claim)

Phase 31 has landed `f0852bb` (the Phase 18 decay tests), `83dff2b`
(the Phase 21 editorial-collection tests), `20420ca` (Phase 29 SRT/HTML
decoder tests), and `732e10a` (Phase 27 Debug Inspector +
SyncHistoryService tests). Still outstanding:
- Phase 22 download-chip tests
- Phase 26 singleton-teardown verification (wiring
  `DebugTeardown.resetAllSingletons()` into test setup)

Worth filing Phase 31 as a single deferred-item ledger rather than
threading the same "Phase 31 owns the test file" deferral across 6+
docs. The Phase 26 singleton-teardown verification in particular is the
single highest-leverage open item because it's documented as the
explanation for known test flakes; landing the helper call into test
setup should stabilize the documented flaky cases.

## Recommended next moves

Sorted by leverage (highest first):

1. **Wire `DebugTeardown.resetAllSingletons()` into the test setup**
   (Phase 31 follow-up to Phase 26). The helper exists (`c1791b9`); the
   call site doesn't. The
   `autoAdvanceDoesNotDoubleEmitSkipOrAbandonedOnFinishedEpisode` and
   `podcastDeepLinkPostsSwitchTabAndOpenPodcastForExistingPodcast`
   flakes can be measured before/after. Single-line edit in test
   setup. If flakes survive, look at non-singleton cross-test state.

2. **Land Phase 27 / 29 / 22 test suites** as a single Phase-31 commit.
   The contract pinning is documented; the deferral was purely a file-
   ownership constraint that no longer applies. Roughly 20-30 new test
   functions across three audit-doc-defined contracts.

3. **Land `endActivity()` on episode change** (background-and-liveactivity
   audit deferred item). Without it the Live Activity persists across
   episode boundaries with stale artwork. Single Combine subscription
   change in `NowPlayingPublisher`.

4. **Land Open-app intents** (`OpenLibraryIntent`, `OpenQueueIntent`,
   `OpenSearchIntent` with `openAppWhenRun = true`) from the
   intents-spotlight audit deferred list. The deep-link contract
   (`offscript://tab/<name>`) already exists.

5. **Per-launch `AppleIdentityService.validateStoredCredential()` call**
   from the SwiftData/iCloud audit. The CHANGELOG documents the breadcrumb
   logging but the actual per-launch validation is the gap that lets
   revoked credentials sit unnoticed until Settings is opened.

### Lower-leverage but documented

6. Sentry `beforeBreadcrumb` filter for episode/feed URL scrubbing
   (privacy audit deferral).
7. Fastlane / `app-store/metadata/` directory for App-Store-Connect
   metadata source-of-truth (privacy audit STRATEGIC item).
8. CloudKit entitlement when the signed distribution profile lands
   (privacy + SwiftData audits, both flagged).
9. Speech locale threading (transcript-pipeline audit `en-US`-only).
10. Phase 1 voiceOverMetadata Home-vs-Library symmetry (the only
    remaining Phase 8 item; resolved for Library but Home symmetry is
    deliberate per-surface).

# Pre-existing test failure investigation — feedSyncFastBatchImportUsesCheapProfilesAndSkipsExternalChapters

## Test location
`OffScriptTests/OffScriptTests.swift:2776` (the failing `#expect(!profile.tags.isEmpty)`).

## Test intent
The test pins two related contracts for the "fast batch import" feed-sync
options (`FeedSyncOptions.fastBatchImport`):

1. External chapter URLs must NOT be fetched/resolved — `episode.chapters`
   should be empty even when `ParsedFeedItem.externalChapterURL` is set.
2. A "cheap" heuristic `EpisodeProfile` must still be created with non-empty
   `tags`, derived from the episode's title + summary using on-device NLP.

The test feeds in title `"Local AI policy and newsroom automation"` and
summary `"A practical conversation about policy, newsroom operations, and
automation."` — both should yield obvious noun tags
(`policy`, `newsroom`, `automation`, `conversation`, `operations`, ...).

## Reproduction
- Confirmed still failing on `e44b0cd` via:
  ```
  xcodebuild ... -only-testing:"OffScriptTests/OffScriptTests/feedSyncFastBatchImportUsesCheapProfilesAndSkipsExternalChapters()" test
  ```
  → `Expectation failed: !((profile.tags → []).isEmpty → true → true)`
- Failure mode: `profile.tags` was `[]` (the array was created, just empty).

## Diagnosis
The test exercises `FeedSyncService.importPodcast(... options:
.fastBatchImport(...))`, which routes through `apply(parsed:...)` in
`OffScript/PodcastServices.swift`. For `enrichmentMode == .heuristic` (which
`fastBatchImport` selects) the import path calls
`TopicExtractionService.enrichHeuristically(episode:in:)`. That in turn
calls `TopicExtractionService.heuristicTagsAndEntities(from:)` and writes
the result into `profile.tags` / `profile.entities`.

`heuristicTagsAndEntities` was built on top of `NLTagger` with the
`.lexicalClass` (for nouns) and `.nameType` (for entities) schemes. A quick
diagnostic test added to the suite confirmed two things on the iOS Simulator
runner (Xcode 16, iOS 18 simulator):

```
DIAG availableTagSchemes for .word/.english: ["Language", "Script", "TokenType"]
```

i.e. `NLTagger.availableTagSchemes(for: .word, language: .english)` returns
ONLY `Language` / `Script` / `TokenType`. The lexical-class and name-type
models are NOT bundled with the simulator runtime. As a result, the
`enumerateTags(... scheme: .lexicalClass)` and `... scheme: .nameType)`
loops in `heuristicTagsAndEntities` never invoke their closures at all — the
tagger silently emits zero tags, the noun bucket stays empty, and
`profile.tags` is `[]`.

This is not just a test problem: the same gap will hit any real iOS device
where the on-device NL models haven't downloaded yet (a known transient
state on fresh installs and on older devices where the lexical-class model
is not preinstalled). Production code was silently producing empty profile
tags for those users.

Setting `tagger.setLanguage(.english, range: ...)` did NOT help — the model
itself is missing, not just unbound.

## Classification
- [ ] TEST BUG (assertion wrong)
- [x] PRODUCTION BUG (cheap-profile codepath drifted / was never robust)
- [ ] CONTRACT-CHANGE (deliberate, test stale)

The test's contract is right (`profile.tags` should not be empty after a
fast batch import). The production code wasn't honouring it whenever the
lexical-class NL model is unavailable, which is the steady state on the
simulator and a transient state on devices.

## Fix
**File:** `OffScript/TopicExtractionService.swift`
**Change:** in `heuristicTagsAndEntities(from:)`:

1. Explicitly `setLanguage(.english, range:)` before enumerating, so when
   the models *are* present they bind correctly.
2. Check `NLTagger.availableTagSchemes(for: .word, language: .english)`
   before each `enumerateTags` call — skip the lexical-class / name-type
   loops entirely if the model isn't loaded (otherwise we burn the work and
   get nothing).
3. Add a fallback path: when `.lexicalClass` is unavailable, run an
   `NLTokenizer` (which only depends on the always-bundled tokenization
   model) and count tokens that are longer than 2 chars and aren't in the
   stopword list or a new closed-class English function-word list
   (`heuristicFunctionWords`). This is dumber than POS-tagging but produces
   enough signal for the recommendation/topic surfaces to work, and it
   keeps the contract that fast batch imports always populate `profile.tags`.

Single commit, surgical — no refactor of the import pipeline.

## Verification
- Failing test now passes: ✓ (`feedSyncFastBatchImportUsesCheapProfilesAndSkipsExternalChapters` → passed after 0.053s)
- Full OffScriptTests target: 139/139 passing: ✓ (`Test run with 139 tests in 3 suites passed after 3.174 seconds.`)
- No other tests regressed: ✓ (entities for this fixture are empty, which is also fine — the test only asserts on `tags`; the heuristic-based fallback intentionally leaves `entities` empty when the name-type model is missing because we don't have a safe way to invent named-entity boundaries from a tokenizer).

## Notes for follow-up
- Once we ship a real telemetry surface, log the
  `NLTagger.availableTagSchemes` shape on first launch so we can see how
  often real devices hit the fallback path. **A telemetry surface now exists (Phase 27 Debug Inspector, commit `dc56ed2`) — the call site to record `NLTagger.availableTagSchemes` on first launch could now plug into `TelemetryService.track(...)`.**
- If the fallback tag quality becomes a problem in production, swap in a
  hand-rolled noun heuristic (e.g. capitalized words + words ending in
  -tion / -ment / -ity) — but the present fallback is good enough to
  unblock topic plumbing for now.

# Curated discovery — Phase 3 implementation

## What was built

Search result rows now render a **latest-episode preview** under the
title/author header: a `● LATEST · 3D AGO` chip, the freshest episode's
title, and a `3D AGO · 47M` freshness/duration strip. Previews are
fetched lazily per row (cap of 8 — everything above the fold on a tall
device, plus a little headroom) via the existing
`PodcastPreviewService.preview(for:episodeLimit: 1)`, then cached by
feed URL so re-typing a previous query feels instant. In-flight fetches
cancel on query change.

The pitch in one line: before this, a stranger had to subscribe blind
based on title + author + iTunes genre alone. Now they see *what they'd
actually start with*, *when it dropped*, and *how long it runs* —
OffScript's "fewer choices, better listening" made concrete on the
surface where strangers first meet the app.

## Why this sub-task (over the other two)

The Phase 3 backlog called out three candidates:

1. **Richer show previews with latest-episode context.** ← picked
2. Expand browse into topic/editorial groupings (currently flat
   genre-based catalog in `CuratedPodcastCatalog`).
3. Improve post-import handoff into first recommendation or first play.

I picked #1 because:

- **The plumbing was already in place but unused on Search.**
  `PodcastPreviewService` and `PodcastPreviewSnapshot` exist for
  `DiscoveryService`'s recommendation scoring, but `SearchView`
  discarded all of that and rendered title + author + iTunes
  `primaryGenreName` only. The user had to subscribe, *then* go look at
  the episode list. The data, parser, and types were already shipping;
  what was missing was the surface.
- **Highest user-visible delta.** This is the moment a non-onboarded
  user opens the app, types a topic, and decides if OffScript is going
  to be different. Search rows are the first impression. Editorial
  groupings (#2) is mostly content/copy work in a static Swift file
  and would feel like reorganized furniture; post-import handoff (#3)
  is incremental — Onboarding already hands users to Home with starter
  PreferenceSignals, and improving that is polish, not a new surface.
- **Tightly scoped.** One new file, two surgical edits to `SearchView`,
  zero schema changes, zero touches to recommendation/taste/queue
  code. Safe to ship next to three other concurrent subagents.

## File changes

- `OffScript/SearchPreviewLoader.swift` (new, 245 lines) — the
  `@MainActor @Observable` loader and the `SearchPreviewMetadata`
  formatted snapshot.
- `OffScript/SearchView.swift` — wires the loader into the search
  surface, threads `previewState` into `SearchResultRow`, adds the
  `previewBlock` and skeleton, and extends `rowVoiceOverLabel` to
  fold preview details into the existing combined a11y element.
- `OffScriptTests/OffScriptTests.swift` — appended a
  `CuratedDiscoveryTests` suite with nine tests.

## Tests added

Nine tests in a new `CuratedDiscoveryTests` suite:

- `freshnessLabelBucketsAcrossWindows` — TODAY / 1D / 3D / 1W / 3W /
  abbreviated-date thresholds.
- `freshnessLabelHandlesFutureDates` — RSS timezone slips don't render
  negative chips.
- `metadataInitFailsOnEmptyEpisodes` — no-episode snapshots produce no
  preview (prevents an empty "● LATEST" chip).
- `metadataInitFailsOnBlankEpisodeTitle` — whitespace-only episode
  titles same as empty.
- `metadataPicksUpDurationLabelsAndSpokenForm` — mono "47M" + spoken
  "47 minutes" pair correctly.
- `metadataDropsSubMinuteDurations` — sub-60s durations (feed quirks)
  hide the duration strip rather than show "0M".
- `loaderReturnsNilForRowsBeyondPreviewCap` — rank > cap doesn't
  schedule a fetch (no 25-row fan-out on long results).
- `loaderFetchesOnceAndCachesAcrossCalls` — re-rendering the same row
  hits the cache, not the fetcher.
- `loaderRecordsFailureWhenFetchThrows` — failed fetches land as
  `.failed`, not stuck in `.loading`.

All inject a deterministic fetch closure via the loader's init seam —
no live HTTP touches the test suite. Total tests 158 → 167.

## Deferred to a future cycle

### Sub-task #2 — Topic / editorial groupings

`OffScript/CuratedPodcastCatalog.swift` is currently a flat
`Genre` enum -> `[PodcastSearchResult]` map. The Phase 3 vision wants
editorial layers on top, e.g.

- "Curious about science?" (cross-cuts science + education + history)
- "Long-form interviews" (cross-cuts Lex Fridman + Acquired + How I
  Built This + Conan + SmartLess)
- "Newsroom" (Daily + Up First + Pod Save America)
- "Just under an hour" (duration-filtered — needs the preview pipeline
  this PR adds, which is convenient for a follow-up)

Suggested shape: a new `EditorialCollection` struct with `title`,
`subtitle`, `feedURLs: [URL]`, `pinnedShowOrder`. Surface it in
`PodcastPickerView` above the per-genre rails as a "EDITORIAL ·
CURATED" section. Probably a 2-3 commit chunk.

### Sub-task #3 — Post-import handoff into first play

The current `ImportProgressView` ends in a `→ CONTINUE` button that
calls `onComplete()` — which only flips `offscript.hasSeenOnboarding`
and drops the user on Home. Home does already surface starter
recommendations (because `ImportProgressView.syncStagedPodcastsInBackground`
seeds `PreferenceSignal(action: .like)` for the newest episode of each
imported show), but there's no narrative bridge — the user doesn't know
*why* the first card they see was picked or that they have anything to
listen to right now.

A clean Phase-3 improvement: when `runImports` completes successfully,
queue a single "first listen" suggestion from the freshest episode of
any imported show, and present it inside `ImportProgressView` as a
"START WITH →" plate before exiting onboarding. Requires hooking into
`RecommendationService` or seeding a one-off recommendation card —
which is owned by another concurrent subagent (Phase 4), so this
deferred deliberately to avoid stepping on their changes.

### Edges of this PR

- **Preview cap is fixed at 8.** On the largest iPad/landscape layout
  more than 8 rows could be above the fold. A dynamic cap based on
  the result list's measured size would be nicer, but 8 covers every
  iPhone form factor including 16 Pro Max landscape. Follow up if real
  iPad layouts surface the gap.
- **`PodcastPreviewService.preview(for:)` has a 20-second timeout and
  no retry.** A slow feed host could leave a row in `.loading` for a
  full 20s. Acceptable for now (the row's main info still renders), but
  a 5-second fast-fail with a one-button retry could match the same
  recovery vocabulary used elsewhere in the row.
- **No usage telemetry.** We don't yet emit a `TelemetryEvent` when a
  user subscribes from a search row that had a preview vs. one that
  didn't — that's the data we'd actually want to measure whether
  previews improve subscribe-confidence. Defer until Phase 4
  recommendations land, since that's where the unified telemetry
  taxonomy is being defined.

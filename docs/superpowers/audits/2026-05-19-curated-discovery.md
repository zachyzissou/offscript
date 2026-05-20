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

## Phase 21 — editorial collections (2026-05-20)

The deferred sub-task #2 from the Phase 17 audit landed: editorial
collections layered over `CuratedPodcastCatalog`. The catalog is no
longer just a flat `Genre → [PodcastSearchResult]` map — it now also
exposes a `CuratedEntry` augmentation (genre + curator duration estimate
+ keyword set), six starter `EditorialCollection`s, and a declarative
`Filter` enum (`duration` / `genres` / `keywords` / `combined`) that
decides membership. The filter is intentionally declarative so the
predicate is testable in isolation and composes via `combined([...])`
intersections.

The Tuner vocabulary already had a "EDITORIAL · CURATED" tag waiting
(see `PodcastGenreRail`'s explore-mode label) — collections now own
that label cleanly. Each collection card is a hairline rectangle with a
4-up artwork stack, the title in body-13.5 semibold, an italic curator
note, and a `N INSIDE` mono count chip. Tapping opens a sheet detail
that lists every resolved entry with a 56pt artwork tile, a typical
duration chip (e.g. `45–65 MIN`), and a signal-yellow toggle plate;
selection is two-way-bound to the same `selectedFeeds` set the genre
rails write to, so a listener can pick a whole viewpoint without losing
their band-side picks.

### Collections shipped

Six starter collections, listed in surface order:

- **`just-under-an-hour`** — duration 45–65 min. The "commute-shaped
  episode" shelf. Resolves to ~20 channels across Culture, Comedy,
  News, Science, Business, Health, Music, History, Education.
- **`long-form-interviews`** — duration ≥ 90 min ∧ keyword "interview".
  Lex, Acquired, Huberman, Peter Attia, Bill Simmons. The "settle in"
  shelf — when length is the point.
- **`news-on-the-go`** — duration ≤ 25 min ∧ genre News & Politics. The
  Daily + Up First. Thin (two channels), but honest — these are the
  only news shows in the catalog that actually deliver in under 25.
- **`for-new-listeners`** — keyword "introductory". The widest shelf
  (~18 channels) — every starter pick the curator marked as easy to
  open cold.
- **`storytelling`** — keyword "storytelling". Acquired, Radiolab, 99%I,
  TAL, Serial, Crime Junkie, Casefile, Dissect, Song Exploder,
  Hardcore, Revisionist, Rest is History, Hidden Brain. The tape-rich,
  edited-to-hold-attention shelf.
- **`quick-hits`** — duration ≤ 30 min. 99%I (low end), Up First, Song
  Exploder, Science Vs (low end), The Daily (low end), Masters of
  Scale (low end). Lunch-break / dog-walk shelf.

The strip only renders collections that resolve to ≥ 1 entry — we
never paint a shelf that lies to the user about what's behind the tap.

An earlier draft included a "Hands-free workouts" collection
(`duration 30–50 ∧ keywords fitness/running/training`) but the current
catalog leans long-form-interview for health/wellness, so the filter
resolved to zero shows. Dropped in favour of the broader
`quick-hits` shelf rather than ship an empty card; honest editorial
beats a category we can't deliver on. If the catalog later includes
shorter wellness/fitness shows, reintroduce the workouts shelf.

### Surface integration

- **`PodcastPickerView`** — owns the integration. The editorial strip
  renders between the existing `(N PICKED / M BANDS)` counter row and
  the genre rail block. Selections from the detail sheet flow into the
  same `selectedFeeds` set that drives `canContinue`, so collections
  count toward the "3+ channels / 2+ bands" gate the picker already
  enforces — no parallel selection state to keep in sync. Genre cards
  underneath still work exactly as before.
- **`GenrePickerView`** — deliberately *not* changed. Step 1's job is
  "pick which bands to tune"; layering collection cards there would
  mix taste-shape (genre) with curator-shape (collection) decisions
  in the same step. The collections land one step later, where the
  user is already inside the channel bank and a shelf is a natural
  alternative entry to the rails. Surfaced as a finding rather than
  shipped.

### Tests to land in a follow-up

`OffScriptTests/OffScriptTests.swift` is owned by a parallel subagent
(Phase 20) — I did not touch it. The following tests should land once
that subagent's commit is in:

1. `func collectionFilterMatchesDurationRangeOverlap()` — assert a
   `.duration(min: 45*60, max: 65*60)` filter matches a candidate with
   `typicalDuration: 30...50` (boundary overlap on the upper end), and
   rejects a candidate with `90...120` (entirely above the window).
2. `func collectionFilterHandlesOpenEndedDuration()` — `.duration(min:
   90*60, max: nil)` matches a 240–360 range; `.duration(min: nil,
   max: 30*60)` matches a 20–35 range (lower-bound inside the cap).
3. `func collectionFilterCombinesIntersectionCorrectly()` —
   `.combined([.duration(...), .genres([.newsAndPolitics])])` rejects
   a candidate that matches the duration but is in the wrong genre,
   and rejects one in the right genre but outside the duration.
4. `func collectionFilterKeywordsAreCaseInsensitive()` —
   `.keywords(["Interview"])` matches a candidate with `keywords:
   ["interview"]` and rejects one with `keywords: ["storytelling"]`.
5. `func collectionFilterRejectsCandidatesMissingDurationForDurationFilter()`
   — `.duration(...)` returns `false` when `typicalDuration` is `nil`
   (mini-vs-full-episode shows that the curator chose not to bucket).
6. `func resolveProducesNonEmptyForEveryShippedCollection()` — iterate
   `CuratedPodcastCatalog.editorialCollections` and assert each
   resolves to at least one entry. Guards against catalog edits
   silently emptying a shelf.
7. `func resolvePreservesCatalogOrder()` — resolved entries appear in
   the same order as `CuratedPodcastCatalog.entries` (so editorial
   ordering is curator-controlled, not filter-side-effected).
8. `func resolveDeduplicatesByFeedURL()` — defensive: if the catalog
   later contains a duplicate `feedURL` across genres, resolution
   doesn't double-count (currently it would; this test would catch
   that and force a `Set<URL>` dedup pass).

### Deferred / Follow-ups

- **Threading measured duration into the picker.** The detail row
  currently shows the *curator's* `typicalDuration` estimate. The
  ideal next move is to swap that for the runtime measured value
  from `SearchPreviewLoader` once the loader is reused outside Search
  — preserve the curator estimate as the bootstrap, hydrate with the
  measured median once previews arrive. The `Filter.duration` shape
  is already correct for that swap.
- **`SearchView` could surface a "BROWSE BY MOOD" shelf** at the top
  of an empty-state search. Same cards, different entry. Not done
  this round; flagged as a clean follow-up.
- **A curator-only `pinnedOrder` per collection.** Right now resolved
  order is catalog order. If the curator wants "Radiolab first, then
  TAL, then 99%I" inside Storytelling, that ordering can't be
  expressed yet. Add a `pinned: [URL]?` to the `EditorialCollection`
  struct when needed.
- **Empty-state safety net.** The strip filters out empty collections,
  but the brand voice would benefit from at least *naming* the
  filter when nothing matches (e.g. the workouts shelf this PR
  dropped). Not worth shipping until we know which collections
  routinely empty under live catalog edits.

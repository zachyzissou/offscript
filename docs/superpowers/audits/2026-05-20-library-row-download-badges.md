# Library row download badges — Phase 22 implementation

## What was built

Library episode rows now surface the ambient `Episode.downloadState` as
a small Tuner chip next to the row's existing action controls. Until
this change, `DownloadButton` (used on the episode detail screen) was
the only place a user could see download status; on the Library list a
queued or failed download was invisible without drilling in. The chip
closes that scanning gap without replacing `DownloadButton` — that
button still owns the explicit Download / Cancel / Retry control surface
on detail, while the chip is the ambient list-level readout.

The chip is hidden for `.notDownloaded` so the default state adds no
visual noise. For the other four states it renders an uppercase
`● <STATE>` mono label in a function-coded color matching
`DownloadButton`'s vocabulary. When `.failed`, the chip itself becomes a
44pt-min retry button (calls `DownloadService.shared.startDownload(for:)`),
acting as a secondary affordance alongside `DownloadButton` so a user
scanning the list can retry without drilling in. VoiceOver surfaces the
same state via the row's existing accessibility label (spoken vocabulary
strips the `●` / `·` punctuation and lowercases the words to read
naturally).

## Design choices

State → color → text mapping (matches `DownloadButton.swift`):

| State           | Color                   | Chip text             | Spoken state             |
| --------------- | ----------------------- | --------------------- | ------------------------ |
| `.notDownloaded`| —                       | (hidden)              | (silent)                 |
| `.queued`       | `offscriptFnInfo`       | `● QUEUED`            | `queued for download`    |
| `.downloading`  | `offscriptSignalYellow` | `● DOWNLOADING`       | `download in progress`   |
| `.downloaded`   | `offscriptFnMode`       | `● ON DEVICE`         | `on device`              |
| `.failed`       | `offscriptFnRecord`     | `● FAILED · RETRY`    | `download failed`        |

Rationale:
- **Function-coded colors** match existing semantic precedent in the
  Tuner system: yellow for actionable / in-progress, fn-info blue for
  passive waiting (`● N IN PROGRESS` on `PodcastShelfRow` uses the same
  token), fn-mode green for success, fn-record red for error.
- **Hidden on `.notDownloaded`** because the chip is meant to flag
  meaningful state changes, not advertise every row's default. Adding
  the chip to every row would dominate the visual hierarchy and dilute
  the signal value.
- **Chip placed in the action row** (trailing, after Play / Queue and
  the `Spacer()`) rather than inside the `NavigationLink` label. This
  lets the `.failed` chip own its own tap target for retry without
  fighting the NavigationLink's tap. For other states the chip is
  decorative (`.accessibilityHidden(true)`) and VO routes through the
  row label.
- **`● FAILED · RETRY` over plain `● FAILED`** because failed downloads
  are the only state where the chip is itself an action target — the
  trailing `· RETRY` glyph reads as a verb prompt to sighted users, and
  the bordered emphasis (`Rectangle().stroke`) sets it apart visually
  from the decorative chips.
- **VO label appends `, <spoken state>`** only when state is non-default,
  matching the existing `voiceOverMetadata` pattern (no `·`, lowercase,
  spelled-out words). `.notDownloaded` stays silent — VO users would
  hear the state on every row otherwise, which is noise.
- **Reused `TunerLabel`** (size 9, mono uppercase) rather than a new
  view. Matches the existing `● SYNC FAILED` chip on `PodcastShelfRow`
  (also size 8/9 TunerLabel) so the visual grammar stays consistent.

## Files touched

- `OffScript/LibraryView.swift`
  - New private `DownloadChip` namespace (chip text + color + spoken
    state mapping)
  - New private `EpisodeDownloadStateChip` view (renders the chip, owns
    retry tap target for `.failed`)
  - `PodcastEpisodeTunerRow.body`: chip appended to the action row;
    `rowAccessibilityLabel` appends spoken state when non-default
  - `TunerLibraryCard.body`: chip appended to the action row; new
    `cardAccessibilityLabel` computed to append spoken state

No other files touched.

## Tests to land in follow-up

**Status (2026-05-20, Phase 31 sweep):** **STILL DEFERRED.** The
download-chip helpers (`DownloadChip` enum, `EpisodeDownloadStateChip`
view, `PodcastEpisodeTunerRow.rowAccessibilityLabel`,
`TunerLibraryCard.cardAccessibilityLabel`) are `private` /
`fileprivate` inside `LibraryView.swift`. `@testable import` doesn't
reach below `internal`, so none of the six tests below can be
authored without a tiny visibility change in `LibraryView.swift`
(e.g. moving `DownloadChip` to `internal` or extracting it to a
sibling file). That change is owned by the next round's library-row
phase, not this one. Re-document the tests here unchanged so the
follow-up has the same target list.

The original Phase 20 subagent edited `OffScriptTests` concurrently
with this audit; Phase 20 has since committed (`9e653c7`), but those
tests covered RecommendationExplanation, not the download-chip
contract. Tests to land once the helpers are reachable:

1. `func libraryRowShowsDownloadingChipWhenStateIsDownloading()` — seed
   an `Episode` with `.downloading`, render `PodcastEpisodeTunerRow`,
   assert the chip text reads `● DOWNLOADING` and the chip color
   matches `offscriptSignalYellow`.
2. `func libraryRowHidesChipWhenStateIsNotDownloaded()` — seed
   `.notDownloaded`, assert no `EpisodeDownloadStateChip` body renders
   (chip text helper returns `nil`).
3. `func libraryRowFailedChipInvokesRetryOnTap()` — seed `.failed`,
   tap the chip in a UI test (or invoke the closure directly via
   `ViewInspector`), assert `DownloadService.shared.startDownload(for:)`
   is called for the episode and that VO label reads
   `"Retry download for <title>"`.
4. `func libraryRowAccessibilityLabelAppendsDownloadStateWhenNonDefault()` —
   seed `.queued`, assert `rowAccessibilityLabel` ends with
   `", queued for download"`.
5. `func libraryRowAccessibilityLabelOmitsDownloadStateWhenNotDownloaded()` —
   seed `.notDownloaded`, assert `rowAccessibilityLabel` does NOT
   contain any download-state phrasing.
6. `func tunerLibraryCardSurfacesDownloadStateInChipAndA11yLabel()` —
   parallel of (1)+(4) for `TunerLibraryCard` to guard against the two
   row variants drifting apart.

## Deferred / Follow-ups

- **Aggregate chip on `PodcastShelfRow`?** The directory's per-podcast
  row could surface a podcast-level rollup ("● 3 ON DEVICE",
  "● 2 DOWNLOADING") by summing episode states. Not in this round
  because (a) it requires episode aggregation work outside file scope
  for download-state purposes, and (b) the existing `unplayedCount`
  rollup already pays an SQL/SwiftData cost per row — adding more
  aggregation needs perf analysis first.
- **`EpisodeRailCard` / Home tuner rail variants** were not in scope
  this round; they likely deserve the same chip but live outside
  `LibraryView.swift`. Worth a small follow-up to extend
  `EpisodeDownloadStateChip` usage across the home tuner rails so the
  chip vocabulary is consistent app-wide.
- **Progress percentage on `.downloading`** — `DownloadButton` shows
  `"%"` of progress; the chip currently shows only the state. If users
  ask for finer-grained feedback, we could append `episode.downloadProgress`
  here too. Held back to keep the chip glance-readable.
- **Animation on state transitions** (`.queued` → `.downloading`,
  `.downloading` → `.downloaded`) — would benefit from a subtle Tuner
  pulse but deferred to keep this commit small. Candidate for the
  `animate` skill in a follow-up.

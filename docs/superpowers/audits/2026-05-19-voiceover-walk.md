# Pre-release VoiceOver walk — 2026-05-19

## Baseline (before audit)

- Branch: `release/2.4.0-audit` cut from `main` @ `1316f3b`
- MARKETING_VERSION: 2.3.11
- CURRENT_PROJECT_VERSION: 2026043004
- Simulator: iPhone 17 Pro · iOS 26.5 (UDID `F623EB2A-1CF4-405E-9583-6B0EE2053FDE`)
- Toolchain: Xcode 26.5 (17F42)
- Build: succeeded
- Compile warnings (unique): 0
- Unit tests: 110/111 passing (OffScriptTests target only; 1 pre-existing failure: `feedSyncFastBatchImportUsesCheapProfilesAndSkipsExternalChapters` at OffScriptTests.swift:2776 — `profile.tags` empty when expected non-empty)
- UI tests: deferred to Phase 3 (5× per test reliability check)

### Baseline notes

- `Config/Secrets.xcconfig` is gitignored and was missing locally; created from `Secrets.xcconfig.example` with a placeholder `SENTRY_DSN` so the local debug build can link. Xcode Cloud materializes the real value via `ci_post_clone.sh`, so no commit is needed.

## Surfaces

_Filled in during Phase 2 — VoiceOver functional verification._

## Phase 1 findings

### Test coverage added

- `EpisodeDurationFormatterTests` (20 cases) pins the `.short(_:)` /
  `.spoken(_:)` contract from `AppTheme.swift:885-913`, including a
  defensive negative-input clamp. The existing implementation already
  truncates `Int(negative / 60)` toward zero, so no formatter patch
  was needed — the tests are pure contract-pinning.
- `VoiceOverMetadataTests` (8 cases) snapshots the
  no-uppercase / no-middle-dot / spoken-duration / "Season X Episode Y"
  contract introduced across PRs #267, #268, and #270. Uses a fixed
  `Locale("en_US_POSIX")` + `Calendar(identifier: .gregorian)` so the
  date string is deterministic across hosts.

### Drift across the three `voiceOverMetadata` builders

The plan assumed all three builders are "near-identical." They are
not:

- **LibraryView `PodcastEpisodeTunerRow.voiceOverMetadata`
  (LibraryView.swift:2996)** — emits the full contract:
  `"<date>, Season <s> Episode <e>, <spoken duration>"`. Matches the
  CHANGELOG-described shape exactly.
- **HomeView `TunerRailCard.voiceOverMetadata`
  (HomeView.swift:1098)** — emits only date + spoken duration. No
  Season/Episode component at all; if the episode has season/episode
  metadata, VO never speaks it on the Home rail card.
- **HomeView second card variant `voiceOverMetadata`
  (HomeView.swift:1330)** — same as above. Date + spoken duration
  only; no Season/Episode.

This is intentional in the sense that the Home rail card's visible
`metadata` also doesn't show season/episode (only date + duration), so
the VO label mirrors what's on screen. But it does mean the VO readout
on Home is **lossier than the underlying data warrants** — a
season-numbered show is announced by date+duration alone on Home, then
"Season 2 Episode 5" on the Library row. Flagging for Phase 2 / Phase
6 to decide whether to align the Home builders with the Library
builder, or leave them as a deliberate per-surface choice.

## Phase 2 static-audit findings

Scope note: Phase 2 was narrowed from a manual Accessibility Inspector
walk to a static analysis. The eight greps below catch the regression
classes the CHANGELOG documents. Surfaces requiring runtime VO focus
order and rotor verification are listed in the deferred section for
Phase 2b.

### Check 1: SF Symbol names leaking into a11y labels

Grep:
`\.accessibilityLabel\("(arrow|chevron|circle|square|plus|minus|xmark|checkmark|ellipsis|line|exclamationmark)`

- No matches. The class of bug where a developer pasted a SF Symbol
  name into `.accessibilityLabel(...)` directly is fully absent across
  the OffScript target.

### Check 2: Middle-dot in labels

Grep: `\.accessibilityLabel\(.*·`

- No matches. The CHANGELOG #268 contract — strip `·` from VO labels
  because VoiceOver pronounces it literally — holds across the
  codebase.

### Check 3: Uppercase mono glyphs being spoken

Grep: `\.accessibilityLabel\(.*(\.uppercased\(\)|metadata\)|metadata,)`
and follow-on `\.accessibilityLabel\(.*metadata`

- No matches. None of the visible `metadata` mono strings are being
  passed through as an `.accessibilityLabel`. The three call sites
  noted in Phase 1 (`HomeView.swift:1273`, `LibraryView.swift:2861`,
  and friends) consistently use `voiceOverMetadata` instead.

### Check 4: Bare visible text used as label

Grep: `\.accessibilityLabel\(.*TunerLabel|\.accessibilityLabel\([A-Za-z]+Text\)`

- No matches. No `.accessibilityLabel(TunerLabel(...))` or
  `.accessibilityLabel(someText)` smell anywhere.

### Check 5: Buttons missing title-aware labels (per surface)

For each surface I cross-referenced the CHANGELOG claim against the
view file. Findings:

**HomeView.swift**
- HeroTunerCard ellipsis (`…` more actions): `More actions for
  <title>` at `HomeView.swift:1042`. **OK** — matches
  CHANGELOG #243.
- Hero Play / Queue chips: title-aware at `HomeView.swift:1003-1018`.
  **OK.**
- Hero feedback chips (LIKE / MORE / LESS / HIDE): title-aware at
  `HomeView.swift:1049-1052`. **OK** — matches CHANGELOG #127.
- HomeStarterRail `+ ADD`: title-aware at `HomeView.swift:556-565`.
  **OK** — matches CHANGELOG #127.
- TunerDiscoveryRail `+ TUNE` / `✗ FAILED · RETRY`: title-aware at
  `HomeView.swift:866-875`. **OK.**
- TunerRailCard NavigationLink: combined + title-aware at
  `HomeView.swift:1272-1273`. **OK** — matches CHANGELOG #267.

**LibraryView.swift**
- SHOWS · DIRECTORY rows: rich label built at
  `LibraryView.swift:2205-2222` (`libraryShelfRowAccessibilityLabel`)
  including channel#, title, author, in-progress/unplayed counts,
  sync-failed chip. **OK** — matches CHANGELOG #246.
- SCOPE / SORT / ROWS mode keys at `LibraryView.swift:1953`:
  `.accessibilityLabel(title)` only — VO reads "ALL" /"AZ" /
  "ARTWORK" without the dimension prefix.
  **DRIFT** — CHANGELOG #127 says these "now expose explicit
  VoiceOver labels," but the label is just the chip title, so two
  separate "ALL" chips (across SCOPE and a hypothetical future
  dimension) would read identically. Not regression-class but
  inconsistent with the title-aware naming the rest of the audit
  found. *Not a clean one-line fix — needs a per-dimension prefix or
  a dedicated label per case in `LibraryDirectoryScope.label` etc.,
  so deferring.*
- Episode FilterRow chips: `Filter episodes by <title>` at
  `LibraryView.swift:3039`. **OK** — matches CHANGELOG #127.
- `+ LOAD 100 MORE` pager: `Load 100 more episodes` at
  `LibraryView.swift:2449`. **OK.**
- `× UNSUBSCRIBE` confirm strip: `Cancel unsubscribe` and `Confirm
  unsubscribe` at `LibraryView.swift:2809` and `:2823` — generic, no
  podcast title.
  **POLISH** — destructive confirm without the podcast title is
  ambiguous if the user has accidentally tapped into a confirm strip
  for a different show. The directory bulk-confirm at QueueView and
  SettingsView is similarly count-aware, but Queue/Settings each
  operate on a single global stack/account where the unsubscribe is
  per-podcast — so the title is more load-bearing here. Defer.
- Per-row play/queue keys at `LibraryView.swift:2172` and `:2188` and
  again at `:2952` and `:2968`: title-aware. **OK.**
- `× UNSUBSCRIBE` (entry, not confirm) at `LibraryView.swift:2705`:
  `Unsubscribe from <podcast.title>`. **OK.**
- TunerLibraryCard NavigationLink at `LibraryView.swift:2156-2157`:
  combined + title-aware. **OK** — matches CHANGELOG #266.

**SearchView.swift**
- Topic chips: `Search for <topic>` at `SearchView.swift:405`. **OK.**
- RECENT SEARCHES rows: `Search again for <item>` at
  `SearchView.swift:508`. **OK.**
- `× CLEAR` recents (with confirm): `Clear recent searches` /
  `Cancel clear recent searches` / `Confirm clear recent searches` at
  `SearchView.swift:435`, `:462`, `:477`. **OK.**
- `+ ADD TO LIBRARY` / `→ WEBSITE`: title-aware at
  `SearchView.swift:670-678` and `:696`. **OK.**
- `× CLEAR SEARCH` in NO MATCHES: `Clear search query` at
  `SearchView.swift:205`. **OK.**
- SearchResultRow combined descriptive zone at
  `SearchView.swift:641-642`. **OK** — matches CHANGELOG #261.

**QueueView.swift**
- Lead-strip `→ PLAY` / `→ RESUME` / `● PLAYING`: at
  `QueueView.swift:389` reads with title via
  state-aware label.  **OK.**
- Lead-strip `× REMOVE`: `Remove <title> from queue` at
  `QueueView.swift:416`. **OK.**
- List `× CLEAR ALL`: count-aware
  `Clear all <N> queued episodes` at `QueueView.swift:159`, plus
  matching cancel/confirm at `:231` / `:250`. **OK** — matches
  CHANGELOG #127.
- Reorder up/down + remove: title-aware at
  `QueueView.swift:515-530`. **OK** — matches CHANGELOG #224.
- NavigationLink (row tap → EpisodeDetail): title-aware at
  `QueueView.swift:489`. **OK.**

**PlayerView.swift**
- UP NEXT descriptive zone: combined + title-aware at
  `PlayerView.swift:408-409`. **OK** — matches CHANGELOG #265.
- UP NEXT `→ PLAY` / `× DROP`: title-aware at
  `PlayerView.swift:438` and `:452`. **OK.**
- Transport buttons: labels supplied via `tunerTransport(label:)` /
  `tunerTransportPrimary(label:)` at `PlayerView.swift:213` and
  `:226`. (Caller-provided labels at every call site — verified
  visually OK.) **OK.**
- Chapter row: `Chapter <n>: <title> at <time>` at
  `PlayerView.swift:355`. **OK.**
- What's Next `+`/`▶`: title-aware at `PlayerView.swift:989` and
  `:1010`. **OK.**
- Sleep / rate pickers and END OF EP: labeled at `:517`, `:576`,
  `:665`. **OK.**

**EpisodeDetailView.swift**
- Action chips (Play/Resume/Now playing): title-aware state-machine
  label at `EpisodeDetailView.swift:240`. **OK.**
- Queue / QUEUE NEXT: title-aware at `EpisodeDetailView.swift:269`
  and `:299`. **OK.**
- Retry download: `Retry download for <title>` at `:355`. **OK.**
- Like / Not for me feedback: title-aware at
  `EpisodeDetailView.swift:465` and `:497`. **OK.**
- FROM CHANNEL chip: `Open <podcast.title> channel` at `:545`. **OK**
  — matches CHANGELOG #249.

**SettingsView.swift**
- Identity readouts (`CREDENTIAL`/`CLOUD`): single-element ignore
  pattern at `SettingsView.swift:654-655`. **OK** — matches
  CHANGELOG #247.
- `× SIGN OUT` (entry) + confirm Cancel/Confirm: labeled at
  `SettingsView.swift:583`, `:774`, `:788`. **OK** — matches
  CHANGELOG #127.
- `↻ REBUILD SIGNAL`: explicit label at
  `SettingsView.swift:451`. **OK.**
- Default rate / per-podcast `× RESET` + confirm pair: at `:251`,
  `:310`, `:346`, `:361`. **OK.**
- Recommendation-mode chips: `<mode> recommendation mode` +
  `.isSelected` trait at `:530`. **OK** — matches CHANGELOG #228.

**CardComponents.swift**
- Queue button title-aware: `<title> already queued` at
  `CardComponents.swift:131` and `:312-313`. **OK** — matches
  CHANGELOG #224.

**LibraryImportSheet.swift**
- BACK button: `Back to import menu` at
  `LibraryImportSheet.swift:376`. **OK** — matches CHANGELOG #244.

### Check 6: voiceOverMetadata builder gaps

No code change since the Phase 1 baseline (`4194aa9`). Confirmed:
- `HomeView.swift:1098` and `:1330` still emit date + spoken duration
  only (no Season/Episode).
- `LibraryView.swift:2996` still emits date + Season X Episode Y +
  spoken duration.

The drift documented in Phase 1 is unchanged. Treating as **DEFERRED**
to Phase 6 / a deliberate product decision: align Home to Library, or
leave as deliberate per-surface choice. Either way, not a
ship-blocker.

### Check 7: Undeclared decorative SF Symbols

Walked every `Image(systemName: …)` in EpisodeDetailView, HomeView,
LibraryView, SearchView, QueueView, PlayerView, and CardComponents.
Findings (decoration *not* inside a Button-with-label, *not* yet
hidden):

- `SearchView.swift:119`, leading `magnifyingglass` in
  `tunerSearchField`: **MUST-FIX** — fixed in commit `ce796ad`.
- `LibraryView.swift:1877`, leading `magnifyingglass` in directory
  filter `tunerSearchField`: **MUST-FIX** — fixed in commit
  `ce796ad`.
- `LibraryView.swift:2593`, leading `magnifyingglass` in episode
  search field: **MUST-FIX** — fixed in commit `ce796ad`.
- All `Image(systemName:)` inside Button labels (transport buttons,
  ellipsis, play/plus/checkmark/xmark within action chips) are
  shadowed by the parent Button's `.accessibilityLabel`, so they
  don't leak SF Symbol names. **OK.**
- The chevron at `LibraryView.swift:2287` (PodcastShelfRow trailing
  chevron) and at `EpisodeDetailView.swift:535` (FROM CHANNEL
  chevron) both carry `.accessibilityHidden(true)`. **OK** — matches
  CHANGELOG #235.

### Check 8: Combined NavigationLink pattern

Grep: `accessibilityElement(children:` across the six list/detail
view files.

The pattern is `.accessibilityElement(children: .ignore) +
.accessibilityLabel(...)` rather than `.combine`. CHANGELOG wording
("now reads as one VoiceOver stop") describes the *outcome*, not the
specific modifier; the `.ignore` form is functionally equivalent (and
arguably safer because it doesn't depend on every child having its
own usable label). Verified at:

- `HomeView.swift:1272` (TunerRailCard) — combined.
- `HomeView.swift:1314` (`.contain` for the wrapper) — intentional,
  preserves child elements per #267.
- `LibraryView.swift:1820` (Library header import-strip running
  header) — combined per #248.
- `LibraryView.swift:1985` (alphabet rail letter) — combined.
- `LibraryView.swift:2156` (TunerLibraryCard) — combined per #266.
- `LibraryView.swift:2924` (PodcastEpisodeTunerRow) — combined per
  #265.
- `LibraryView.swift:3125` (FROM CHANNEL chip) — combined per #249.
- `SearchView.swift:641` (SearchResultRow descriptive) — combined per
  #261.
- `SearchView.swift:713` (import-failed inline strip) — `.combine`.
- `QueueView.swift:324` (lead-strip header) — combined.
- `PlayerView.swift:408` (UP NEXT descriptive) — combined per #262.
- `PlayerView.swift:812` (scrubber readout) — combined.
- `EpisodeDetailView.swift:544` (FROM CHANNEL chip) — combined per
  #249.

No drift between CHANGELOG and code on the combine pattern. **OK.**

### Surfaces deferred to runtime audit (Phase 2b)

Static analysis can't verify:

1. **VO focus order** through the Home hero card → rail → discovery
   flow. The labels are right but the visit order may surprise — e.g.
   does VO reach the `…` more-actions key before the Play chip, or
   after? Phase 2b runtime check should walk Home top-to-bottom with
   VO enabled.
2. **Rotor / heading hierarchy** — none of the views use
   `.accessibilityRotor(_:entries:)` or `.accessibilityAddTraits(.isHeader)`.
   `TunerLabel` eyebrows like `RECENT SEARCHES` and `STACK · TAP × TO
   REMOVE` are visually section headers but a VO user can't jump
   between them via the headings rotor. Defer to Phase 2b for a
   judgement call (low-impact if VO list-navigation is already
   linear).
3. **EpisodeDetail action row toggle states** — does the `+ QUEUE`
   key correctly announce "Already queued" when state flips
   underneath the user? The static label is right; the runtime needs
   to confirm the value re-renders to VO.
4. **SCOPE / SORT / ROWS chip drift** (Check 5 finding) — verify
   whether ambiguous "ALL" / "AZ" / "ARTWORK" labels actually confuse
   a VO user or whether the ScrollView focus context disambiguates
   them in practice.
5. **Confirmation strip focus** — when `× CLEAR ALL` or `× SIGN OUT`
   opens the inline confirm strip, does VO focus advance into the
   strip or stay on the original key? CHANGELOG doesn't claim a
   specific focus behavior, so this is informational rather than a
   regression check.

### Summary by classification

- **MUST-FIX**: 3 (all fixed in `ce796ad`) — decorative magnifying
  glass icons.
- **DRIFT**: 1 (deferred) — Library SCOPE/SORT/ROWS chips use
  dimension-less labels.
- **POLISH**: 1 (deferred) — `Cancel unsubscribe` / `Confirm
  unsubscribe` not title-aware.
- **DEFERRED**: 5 — surfaces requiring runtime VO walk; documented
  for Phase 2b.

No additional ship-blockers found. The Phase 1 voiceOverMetadata Home
vs Library asymmetry remains the most significant standing finding
and is a product decision rather than a regression.


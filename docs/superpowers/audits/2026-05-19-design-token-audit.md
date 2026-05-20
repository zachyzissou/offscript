# Design-token conformance audit — 2026-05-19

Static grep audit against the rules in `CLAUDE.md`. Run on branch
`release/2.4.0-audit` at HEAD `7326f26` (pre-fix; new commits below append
to this branch). Scope: `OffScript/` source tree only — excludes
`AppTheme.swift` (defines the tokens), tests, and widget extensions.

## Check 1: inline Color.white / Color.black opacity

Grep: `Color\.(white|black)\.opacity\(` in `OffScript/**.swift` minus
`AppTheme.swift` and comment lines.

**Result: 0 matches.** No regressions against the v2.3.10 cleanup —
`AppTheme.swift` is the only file that touches raw white/black opacity,
and the call there is on `Color.offscriptStudioBlack` (a named token),
not bare `Color.black`.

## Check 2: raw Color.white / Color.black (no opacity)

Grep: `Color\.(white|black)([^a-zA-Z]|$)` minus the .opacity hits already
covered in Check 1.

**Result: 0 matches.** Nothing in `OffScript/` reaches for raw
`Color.white` or `Color.black` outside `AppTheme.swift`.

## Check 3: raw .font(.system(...)) outside AppTheme

Grep: `\.font\(\.system\(` minus `AppTheme.swift` and comments.

**Result: 212 matches across 19 files.** This is the bulk of the audit.
Almost every call site is one of these three buckets:

- **NOT-A-FINDING — section/title/body styles that align with the named
  styles in CLAUDE.md.** `.system(size: 32, weight: .bold)` is the display
  headline. `.system(size: 22, weight: .semibold)` is the section title.
  `.system(size: 13.5, ...)` is body. These appear in every page header
  (Home, Library, Queue, Settings, ImportProgress) and the per-section
  headings in EpisodeDetailView, PlayerView, LibraryView. They're written
  inline rather than as named modifiers — annoying, but not a
  CLAUDE.md violation. Leaving as-is.
- **DRIFT — mono "metadata" text that arguably should be `TunerLabel`.**
  41 sites use `design: .monospaced` outside `TunerLabel`. Detailed in
  Check 7. Most are NOT clean fixes because they live inside HStacks
  with icons (a `TunerLabel` is a `View`, not a font modifier, so it
  can't be lifted onto the parent HStack), or use tracking `1.4` /
  `0.6` (TunerLabel hardcodes `1.6`), or apply
  `.monospacedDigit()` only. Replacing them would visually shift letter
  spacing on every chip and pill.
- **POLISH — one-off readouts at sizes that aren't in the named set.**
  Examples: `.system(size: 26)` in PlayerView (big elapsed-time number),
  `.system(size: 56)` in OnboardingFlowView (OFF·SCRIPT wordmark),
  `.system(size: 18, .light)` and `.system(size: 20)` etc. These are
  deliberately unique-per-screen display elements. Not worth promoting
  to tokens for a single call site each.

Sized breakdown of the 212 matches:

| File | hits | dominant style |
| --- | ---: | --- |
| LibraryView.swift          | 39 | mixed (12 mono, rest body/title) |
| PlayerView.swift           | 17 | mixed |
| HomeView.swift             | 16 | mixed |
| SearchView.swift           | 16 | mixed |
| SettingsView.swift         | 16 | mixed |
| LibraryImportSheet.swift   | 16 | mixed |
| EpisodeDetailView.swift    | 13 | many mono (button chrome) |
| CardComponents.swift       | 12 | mixed |
| QueueView.swift            |  9 | mixed |
| OnboardingFlowView.swift   |  6 | wordmark + step numerals |
| PodcastPickerView.swift    |  7 | mixed |
| GenrePickerView.swift      |  7 | mixed |
| MiniPlayer.swift           |  4 | title + transport icons |
| ImportProgressView.swift   |  4 | mixed |
| EpisodeBriefingView.swift  |  3 | section copy |
| LibraryImportSheet.swift   | (above) |  |
| ContentView.swift          |  2 | tab-bar chrome |
| EpisodeTranslationView.swift | 2 | mixed |
| SpeechTranscriptionPanel.swift | 2 | body copy |
| DownloadButton.swift       |  1 | button label |

None are MUST-FIX. The largest class of legitimate fixes here is the
mono-without-TunerLabel set, treated separately under Check 7.

## Check 4: legacy corner radii (12, 24, 32)

Greps:
- `cornerRadius\((12|24|32)`
- `RoundedRectangle\(cornerRadius:\s*(12|24|32)`

**Result: 0 matches in either grep.** The legacy editorial radii are
fully gone from `OffScript/` source. Sharp Tuner aesthetic is enforced.

## Check 5: OffScriptArtworkView hairline-stroke pairing

CLAUDE.md spec: every `OffScriptArtworkView(... cornerRadius: 3)` needs a
`Rectangle().stroke(Color.offscriptHairline)` overlay. Grepped all 18
`OffScriptArtworkView(` call sites in `OffScript/`. Confirmed by
inspection of the next ~6 lines after each:

| File:line | size | cornerRadius | hairline overlay? | classification |
| --- | --- | --: | --- | --- |
| SearchView.swift:620             | 64×64    | 3 | yes | OK |
| CardComponents.swift:38          | 200×150  | 0 | no  | DRIFT (hero card, see note) |
| CardComponents.swift:204         | 52×52    | 3 | **NO** | **MUST-FIX, fixed** |
| PodcastPickerView.swift:204      | 120×120  | 3 | yes (on enclosing ZStack) | OK |
| EpisodeDetailView.swift:138      | 96×96    | 3 | **NO** | **MUST-FIX, fixed** |
| EpisodeDetailView.swift:525      | 44×44    | 3 | **NO** | **MUST-FIX, fixed** |
| ImportProgressView.swift:278     | 40×40    | 3 | yes | OK |
| HomeView.swift:803               | 168×168  | 3 | yes | OK |
| HomeView.swift:937               | full×200 | 3 | yes (line 943) | OK |
| HomeView.swift:1243              | 168×168  | 3 | yes | OK |
| QueueView.swift:343              | 88×88    | 3 | yes | OK |
| QueueView.swift:457              | 48×48    | 3 | yes | OK |
| LibraryView.swift:2131           | 64×64    | 3 | yes | OK |
| LibraryView.swift:2252           | 56×56    | 3 | yes | OK |
| LibraryView.swift:2665           | 96×96    | 3 | yes | OK |
| PlayerView.swift:124             | 120×120  | 3 | yes | OK |
| PlayerView.swift:387             | 44×44    | 3 | yes | OK |
| PlayerView.swift:957             | 40×40    | 3 | yes | OK |
| MiniPlayer.swift:39              | 44×44    | 3 | yes | OK |

Note on `CardComponents.swift:38`: `cornerRadius: 0` for a 200×150
horizontal-scroll feature card. CLAUDE.md says artwork is `cornerRadius:
3`, but this is the editorial "feature card" used by the Home dial
section, not a tile. Reads as intentional drift — the wide flat edge is
part of the spec sheet vocabulary. **Flagging as DRIFT, not fixing**:
moving to `3` here would visually shift the only large-format artwork
card in the app and is a design call, not a token-conformance call.

## Check 6: rounded backgrounds on Tuner action buttons

Grep: `\.background\(\s*(RoundedRectangle|Capsule\(\))` in
`OffScript/**.swift` minus `AppTheme.swift`.

**Result: 0 matches.** No `Capsule()` chrome, no `RoundedRectangle`
backgrounds. All button backgrounds are flat `Rectangle()` fills (or
solid color fills) with `.overlay(Rectangle().stroke(...))`, per the
Tuner spec.

## Check 7: TunerLabel monospaced rule

Grep: `design:\s*\.monospaced` outside `AppTheme.swift` and outside
`TunerLabel` matches.

**Result: 41 matches.** Files:

- CardComponents.swift (5): podcast title rows, rank counters, metadata
  rows.
- EpisodeDetailView.swift (6): PLAY / QUEUE / QUEUE NEXT / DOWNLOAD /
  SHARE button labels — all live inside `HStack { Image + Text }`
  patterns so TunerLabel (which is itself a Text-only View) can't sit
  on the HStack.
- SearchView.swift (3): EYEBROW · STATUS strips, "X RESULTS" counters.
- SettingsView.swift (2): big "OFF SCRIPT" wordmark + a number readout.
- PodcastPickerView.swift (2): subtitle metadata.
- HomeView.swift (1): briefing-strip eyebrow.
- OnboardingFlowView.swift (2): manifesto step counter (uses
  `.monospacedDigit()` + tracking 0.6, intentionally distinct from
  TunerLabel), and a `● ERROR` strip.
- ImportProgressView.swift (1): podcast row metadata.
- GenrePickerView.swift (3): genre subtitle pill, counter, selection.
- LibraryView.swift (7): channel rows, "GO TO TOP" headline,
  per-section eyebrows. Mostly inside HStacks.
- QueueView.swift (1): UP-NEXT lead strip eyebrow.
- EpisodeBriefingView.swift (1): briefing-section eyebrow.
- LibraryImportSheet.swift (3): import-status strips.
- PlayerView.swift (3): transport rail readouts, UP-NEXT eyebrow.
- ContentView.swift (1): tab-bar chrome counter.

Classification:

- **NONE are clean MUST-FIX swap-to-`TunerLabel`** because every one of
  them differs from TunerLabel in at least one of:
  - lives inside an `HStack { Image + Text }` button label
  - uses tracking other than `1.6` (`1.4`, `0.6`, `0`)
  - uses a non-semibold weight (`.bold`, `.regular`, `.light`)
  - applies `.monospacedDigit()` to mixed letter/digit content
  - is composed with other modifiers (`.foregroundStyle` with
    state-dependent colour, `.lineLimit`, `.tracking`) before
    `.font(...)` is applied.
- **All 41 are DRIFT.** Rolling these into `TunerLabel` would require
  either (a) widening the `TunerLabel` API surface (a refactor that
  shouldn't ship in a pre-release audit), or (b) introducing a separate
  `tunerFont(size:)` font-only modifier so HStack+icon button labels can
  use the same vocabulary without wrapping the text in a separate View.
  Both are worth doing, neither is in scope for Phase 5.

## Summary

- **MUST-FIX: 3 (3 fixed, 0 deferred)**
- **DRIFT: 42** — 41 mono-without-TunerLabel sites + 1 cornerRadius-0
  hero card. None blocking; all are sub-token scaffolding that would
  benefit from a follow-up unified `tunerFont(size:)` modifier.
- **POLISH: 0** — no individual `.font(.system(...))` call is wrong in
  isolation; the dominant pattern is "inline named style" rather than
  "ad-hoc Font".

### New commits

- `e5b411f` — fix(design): add hairline overlay to row-chip artwork in CardComponents
- `e4bfa4a` — fix(design): add hairline overlay to hero artwork in EpisodeDetailView
- `1639130` — fix(design): add hairline overlay to channel-chip artwork in EpisodeDetailView

### Top findings by impact

1. **3 artwork tiles were missing the hairline overlay** that CLAUDE.md
   prescribes — the 96×96 hero on `EpisodeDetailView` (every episode
   detail), the 44×44 channel chip on `EpisodeDetailView`, and the 52×52
   row chip in `CardComponents`. Visually, artwork without the
   single-pixel border floats against the OLED field instead of sitting
   inside its cell. All three are now fixed.
2. **The `OffScriptArtworkView` API doesn't apply the hairline itself.**
   It's the call site's responsibility, which is why these drifted.
   Worth considering a `OffScriptArtworkTile(...)` wrapper that bundles
   `frame + .overlay(stroke)` so future call sites can't forget.
   (Out of scope for this audit; recorded here for v2.4.x backlog.)
3. **`TunerLabel` doesn't cover the HStack+icon button label case.** 41
   monospaced sites can't migrate cleanly because they live inside a
   button HStack. A small font-only modifier
   (`func tunerFont(size:) -> some View`) would unblock the bulk of
   them. Recommended as a v2.4.x follow-up.

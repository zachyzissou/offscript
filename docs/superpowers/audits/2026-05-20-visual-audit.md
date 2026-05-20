# Visual audit — 2026-05-20

Branch: `audit/expanded-surface-2026-05-19`
Sim: iPhone 17 Pro / iOS 26.5 (`F623EB2A-1CF4-405E-9583-6B0EE2053FDE`)
App build: Debug, commit at branch tip.

## Methodology

Booted the iPhone 17 Pro / iOS 26.5 simulator, built `OffScript` from
the current branch, and launched the freshly installed `OffScript.app`
across 8 (surface × seed-state) combinations using `xcrun simctl launch`
with the project's debug launch overrides:

- `-offscript.hasSeenOnboarding YES` (bypass onboarding gate)
- `-offscript.debugWipeLibrary YES` (clean SwiftData store)
- `-offscript.debugSeedSampleData YES` (3-show sample seed)
- `-offscript.debugSeedLibrarySize 258` (deterministic large library)
- `-offscript.debugSeedQueue N` (stack N episodes into the queue)
- `-offscript.debugLaunchTab N` (jump to tab on launch)

Each screenshot was inspected at full resolution against the Tuner OLED
design-system principles documented in `CLAUDE.md`:

- Pure black `#000` (`offscriptStudioBlack`) field — never tinted.
- Signal-yellow `#e8d24a` (`offscriptSignalYellow`) as the only primary
  accent; function-coded red/green/cyan/yellow only for state.
- Sharp corners — 0pt for buttons/cards, 3pt for artwork tiles, with a
  hairline `Rectangle().stroke(.offscriptHairline)` overlay.
- Single-pixel hairline borders (`offscriptHairline` @ 8% white).
- `TunerLabel` mono for every eyebrow, status badge, channel number,
  time code, metadata caption.
- `·` middle-dot used only inside `TunerLabel` eyebrows
  (e.g. `TODAY · WED, MAY 20`), never leaking into body or button copy.

## Screenshots

| File | Description |
| --- | --- |
| `2026-05-20-visual-audit/home-empty.png` | Home tab, wiped library. Falls into the "Pick a few well-liked channels" curated-add list (post-onboarding empty Home). |
| `2026-05-20-visual-audit/home-seeded.png` | Home tab, 3-show sample seed. Radiolab headline card with `15M LEFT FROM YOUR LAST SESSION` plus Resume Thread strip. |
| `2026-05-20-visual-audit/library-empty.png` | Library tab, wiped library. `NO CHANNELS TUNED` / `Your library is empty` empty state with `→ FIND SHOWS` CTA. |
| `2026-05-20-visual-audit/library-seeded-small.png` | Library tab, 3-show sample seed. Counters (3 SHOWS · 3 VISIBLE · 9 UNPLAYED · 3 IN PROGRESS), Continue Listening + Fresh Episodes rails, Directory · Control filters. |
| `2026-05-20-visual-audit/library-258-shows.png` | Library tab, 258-show deterministic large seed. Stress-tests counters (258 / 258 / 258 / 52) and the directory section. |
| `2026-05-20-visual-audit/queue-empty.png` | Queue tab, wiped library. `QUEUE EMPTY` / `Nothing queued yet` empty state with `→ EXPLORE SHOWS` CTA. |
| `2026-05-20-visual-audit/queue-seeded.png` | Queue tab, 5-episode seed. `NEXT UP · IN PROGRESS` card with Resume/Remove keys, Stack list with row controls + `× CLEAR ALL`. |
| `2026-05-20-visual-audit/search-default.png` | Search tab, default empty entry state. Hairline search field, Tuning Tip, Starter Topics grid. |

## Findings

### REGRESSIONS

None observed. Every screen still parses as instrument-cluster:
pure-black field, monospaced eyebrows, signal-yellow accents, hairline
dividers, sharp corners. No glass-capsule chrome, no rounded surface
cards, no inline `Color.white.opacity(...)` blooms, no stray middle
dots leaking into body copy. The 100-commit feature surge has not
visibly broken the design system on any of the eight inspected states.

### POLISH

1. **`home-empty.png` — "0 TUNED" counter has weak contrast.** The
   right-rail status reads `0 TUNED` in `offscriptFnInfo` cyan, but at
   that font size it sits very close to the unused-cyan threshold and
   reads as decoration rather than a live counter. Consider promoting
   to `offscriptSignalYellow` when count == 0 (so the user notices the
   actionable zero state), or pairing with a "● " glyph for parity with
   `● HEADLINE` etc.
   *Severity: POLISH. Suggested fix: in the Home empty header strip,
   swap `TunerLabel(text: "0 TUNED", color: .offscriptFnInfo)` for
   `.offscriptSignalYellow` when value is zero.*

2. **`home-seeded.png` — Headline artwork placeholder is dead air.**
   The Radiolab headline tile is 360pt+ tall and renders as an empty
   black square with only a tiny waveform glyph in the center. Even at
   3pt corner radius with hairline border, the proportions feel under-
   designed compared to the dense metadata strip below it. Suggested:
   if the artwork URL is `placeholder.invalid` (which it is in the
   sample seed), fall through to a `TunerLabel` channel-number
   treatment + a larger waveform glyph so the empty state has a
   designed identity, not just an absence.
   *Severity: POLISH. Most users will see real artwork; this only bites
   sample-seed/dev builds and offline cold-starts.*

3. **`library-seeded-small.png` — Continue Listening cards have a
   secondary tile cut off on the right.** Each rail row shows the
   primary card fully and a sibling card clipped at the right edge.
   This is intentional "more to scroll" affordance, but the clipped
   card has no visible action keys (Play, +) — it reads as a render
   bug rather than peeking. Consider adding a 2-3pt right-edge fade
   or a "→ N MORE" tail tile to make the affordance explicit.
   *Severity: POLISH.*

4. **`library-seeded-small.png` — Filter chip "ALL" selected state
   uses a solid signal-yellow fill rather than the hairline-outline +
   yellow-text convention seen elsewhere.** Compare with `→ RESUME`
   on `home-seeded.png` (hairline outline, yellow text). Filter chips
   in `SCOPE` row break that convention by going solid-yellow with
   black text. This is the only place in the audit where signal-yellow
   is used as a fill color rather than as a stroke/text accent. The
   `SORT` row's `A-Z` chip does the same thing. Decide whether the
   filled treatment is the new "active filter chip" pattern (in which
   case document it in CLAUDE.md) or unify it with the outline pattern.
   *Severity: POLISH / design-system clarification.*

5. **`library-seeded-small.png` & `library-258-shows.png` — Directory
   filter row clips its last chip (`NEEDS SYNC`) at the right edge.**
   The horizontal scroller offers no visible affordance that it
   scrolls. Same critique as the artwork-rail clipping above.
   *Severity: POLISH.*

6. **`queue-seeded.png` — Row controls (▲ ▼ ×) on stack rows have
   inconsistent visual weight.** The play key is a solid signal-yellow
   square, the up/down chevrons are hairline outline with gray glyph,
   and the `×` is a hairline outline with red glyph. Three different
   treatments for four sibling controls. Consider unifying: solid
   yellow for the primary action (play), hairline + signal-yellow
   glyph for navigational secondary (up/down), hairline +
   `offscriptFnRecord` glyph for destructive (×). The current up/down
   gray reads as "disabled" even when enabled.
   *Severity: POLISH.*

7. **`queue-seeded.png` — Tab bar Queue badge "5" overlaps the queue
   icon.** The badge sits flush against the top-right corner of the
   icon without breathing room. At 5-7 items it's still legible; at
   triple-digit queues this will collide. Consider 1-2pt of padding,
   or moving the badge to a `TunerLabel`-style superscript treatment.
   *Severity: POLISH.*

8. **`queue-seeded.png` — Stack row titles truncate aggressively
   ("Radiol…", "Lex Frid…", "Conan O'Bri…").** The episode-title
   column is squeezed by the four trailing controls. On a phone-width
   screen the title is the most important affordance — losing 60% of
   it to truncation hurts scanability. Consider stacking the row in
   two lines (title on top, controls beneath) or hiding the secondary
   chevrons behind a swipe gesture.
   *Severity: POLISH.*

9. **`search-default.png` — Starter Topics grid uses 2-column layout
   with what appears to be ~16pt internal padding inside each cell.**
   The cells feel tall compared to the single-line `TECH` / `NEWS`
   labels they hold. Tightening to a 3-column grid or reducing cell
   height by ~20% would feel more like a control panel and less like
   a marketing tile grid.
   *Severity: POLISH.*

10. **All seeded screenshots — `· ` middle-dot is rendered as plain
    ASCII `.` in some `TunerLabel` strings.** Check `home-seeded.png`
    `TODAY · WED, MAY 20` (correct middle-dot) vs `library-seeded-small`
    `MAY 20, 2026 · 25M` on the Radiolab card (also correct). I could
    not find a violation in this batch — flagging as a verification
    note rather than a finding. Worth a quick grep for hardcoded
    `". "` separators in `TunerLabel` callsites.

### NEW AREAS

1. **Continue Listening + Fresh Episodes rails (Library)** — These
   rails are recent (per the 100-commit recap) and feel slightly
   under-polished compared to Home. The artwork tile dominates each
   card, with title/eyebrow/duration crammed below. Could benefit from
   a design pass that tightens the card to a Home-style headline
   treatment, or differentiates Library rails from Home rails so they
   don't feel like a smaller copy of the same component.

2. **Directory · Control section (Library)** — `SCOPE`, `SORT`, and
   the (clipped) `ROWS` section read as a real instrument-panel
   control bank, which is on-brand and very nice. The filled-chip
   active-state question (see Polish #4) is the main thing standing
   in the way of this section being the strongest piece in the app.

3. **Large-library counters (`library-258-shows.png`)** — Showing
   `258 / 258 / 258 / 52` reads cleanly. The four-column counter row
   scales nicely from 3-show seed to 258-show seed without layout
   breakage, which is unusual and worth calling out as a win.

4. **Queue NEXT UP card (`queue-seeded.png`)** — The `→ RESUME` +
   `× REMOVE` paired keys with the IN PROGRESS eyebrow is the most
   instrument-panel-feeling component in the app right now. The
   `× CLEAR ALL` destructive-strip header below it is also strong.

5. **Search empty state (`search-default.png`)** — `TUNING TIP /
   Three strong inputs` is genuinely well-written microcopy that
   matches the brand voice. The hairline search field with leading
   magnifier glyph is exactly the iOS-26 chrome trap workaround the
   bible calls for. Solid surface.

## Strategic verdict

After 100+ commits of feature work, the Tuner OLED design system is
**holding remarkably well**. Every surface inspected reads as part of
the same instrument-cluster aesthetic — pure-black field, monospaced
metadata, hairline borders, sharp corners, signal-yellow as the only
"color" most of the time. No glass-capsule iOS 26 leakage. No inline
opacity blooms. No rounded surface cards. The empty states are
strong, the seeded states are strong, the 258-show stress test is
strong.

The polish items above are exactly that — polish, not drift. The two
most worth fixing are (a) deciding whether filled-yellow filter chips
are the new active-chip pattern and documenting that in CLAUDE.md, and
(b) the queue stack row's four-different-treatment row controls. Both
are component-level questions, not system-level questions, and neither
threatens the integrity of the visual language.

The system is mature enough that a designer joining the team today
could read CLAUDE.md, look at these eight screenshots, and reliably
ship new surfaces that match. That is the actual definition of a
design system holding.

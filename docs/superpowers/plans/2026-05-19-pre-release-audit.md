# Pre-Release Audit & Hardening — Unreleased (2026-05-19)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Audit the Unreleased section of OffScript (predominantly VoiceOver/accessibility + new UI test coverage) and harden it to the bar required for a clean TestFlight push — no spam, one substantive release.

**Architecture:** This is an audit/hardening plan, not a feature build. The shape is: prove the build green → close the unit-test gap on the new spoken-metadata code → walk every claimed VoiceOver improvement against the simulator → stabilise the new UI tests → performance-check the 258-show case → verify visual + design-system conformance → cut a TestFlight build.

**Tech Stack:** iOS 26.2, SwiftUI, SwiftData, XCTest, Swift Testing, FoundationModels, Speech, Xcode Cloud, MetricKit, Sentry.

**Working copy:** `/Users/zachgonser/Documents/OffScript/` (fresh `main` @ `1316f3b`).

**Source of truth for what's in scope:** the `## [Unreleased]` section of `CHANGELOG.md`. Anything that has been promoted out of Unreleased on `main` is in-scope; anything still on feature branches is out of scope for this release.

---

## File Structure

This plan does **not** create new product code. It creates:

- `OffScriptTests/EpisodeDurationFormatterTests.swift` — new XCTest file. Pure-Foundation unit tests for `EpisodeDurationFormatter.spoken()` and `.short()`. No SwiftData / no UIKit / no simulator dependency, so they run on `xcodebuild test -destination 'platform=iOS Simulator,OS=latest'` in seconds.
- `OffScriptTests/VoiceOverMetadataTests.swift` — new XCTest file. Pulls the `voiceOverMetadata` builder logic out of view structs into a small testable helper, then asserts on its output across edge inputs (no `·` separator, no double-uppercased text, season/episode expansion, missing duration handling).
- `docs/superpowers/audits/2026-05-19-voiceover-walk.md` — new audit notes file. Records what VoiceOver actually spoke on each surface, what was wrong, what was fixed. This becomes the artifact backing the release.
- `docs/superpowers/audits/2026-05-19-258-show-perf.md` — new audit notes file. Records the cold-launch + scroll + alphabet-jump timings on the seeded 258-show library, plus any Instruments traces captured.
- Modifications inside the existing code paths:
  - `OffScript/AppTheme.swift:885-913` — `EpisodeDurationFormatter` only if the new tests surface bugs.
  - `OffScript/HomeView.swift:1098`, `OffScript/HomeView.swift:1330`, `OffScript/LibraryView.swift:2996` — `voiceOverMetadata` builders, only if the new tests or VO walk surface bugs.
  - `OffScript.xcodeproj/project.pbxproj` — `CURRENT_PROJECT_VERSION` bump for the TestFlight build.
  - `CHANGELOG.md` — promotion of `[Unreleased]` to a numbered section + new Unreleased stub.

If the audit surfaces real bugs, **each fix is its own task with its own commit**, slotted into the appropriate phase. The plan below assumes the optimistic path; expand it inline as findings come in.

---

## Phase 0: Baseline

### Task 0.1: Confirm clean build on main

**Files:**
- Read: `OffScript.xcodeproj/project.pbxproj`

- [ ] **Step 1: List available simulators**

Run: `xcrun simctl list devices available | grep -E 'iPhone (15|16|17) Pro' | head -5`

Pick the first iPhone Pro simulator UDID for the rest of the plan and store it: `export OFFSCRIPT_SIM_UDID=<uuid>`.

- [ ] **Step 2: Boot the simulator**

Run: `xcrun simctl boot "$OFFSCRIPT_SIM_UDID" 2>/dev/null || true`
Expected: no error (already-booted is fine).

- [ ] **Step 3: Clean build the app target**

Run from repo root:
```bash
xcodebuild -project OffScript.xcodeproj \
  -scheme OffScript \
  -destination "platform=iOS Simulator,id=$OFFSCRIPT_SIM_UDID" \
  -configuration Debug \
  clean build 2>&1 | tee /tmp/offscript-build.log | tail -40
```
Expected: `** BUILD SUCCEEDED **`. If it fails, **stop and triage** — the audit cannot proceed against a broken build.

- [ ] **Step 4: Capture warning baseline**

Run: `grep -E 'warning:' /tmp/offscript-build.log | sort -u | wc -l && grep -E 'warning:' /tmp/offscript-build.log | sort -u > /tmp/offscript-warnings-baseline.txt`

Record the count in the audit notes file (created in 0.5).

- [ ] **Step 5: Capture test baseline**

Run: `xcodebuild -project OffScript.xcodeproj -scheme OffScript -destination "platform=iOS Simulator,id=$OFFSCRIPT_SIM_UDID" test 2>&1 | tee /tmp/offscript-test.log | tail -80`
Expected: all tests pass. Record pass/fail counts.

- [ ] **Step 6: Create the audit notes file**

Create `docs/superpowers/audits/2026-05-19-voiceover-walk.md` with:
```markdown
# Pre-release VoiceOver walk — 2026-05-19

## Baseline (before audit)
- Build: `1316f3b` on `main`
- MARKETING_VERSION: 2.3.11
- CURRENT_PROJECT_VERSION: 2026043004
- Compile warnings: <count from step 4>
- Unit tests: <pass>/<fail>/<total> (from step 5)
- UI tests: <pass>/<fail>/<total> (from step 5)

## Surfaces (filled in Phase 3)
```

- [ ] **Step 7: Commit baseline notes**

```bash
git checkout -b release/2.4.0-audit
git add docs/superpowers/audits/2026-05-19-voiceover-walk.md
git add docs/superpowers/plans/2026-05-19-pre-release-audit.md
git commit -m "chore: open pre-release audit baseline for 2.4.0"
```

---

## Phase 1: Close the spoken-duration test gap (TDD)

The `Unreleased` section adds `EpisodeDurationFormatter.spoken(_:)` and threads it through ~15 sites. **There are zero unit tests for it.** This phase fixes that first, because it's pure-Foundation and cheap, and the simulator walk later will assume the formatter is correct.

### Task 1.1: Write the failing spoken() tests

**Files:**
- Create: `OffScriptTests/EpisodeDurationFormatterTests.swift`
- Read: `OffScript/AppTheme.swift:885-913`

- [ ] **Step 1: Write the failing test file**

```swift
import XCTest
@testable import OffScript

final class EpisodeDurationFormatterTests: XCTestCase {
    // MARK: - short(_:)

    func testShort_zeroSeconds_returnsZeroMinutes() {
        XCTAssertEqual(EpisodeDurationFormatter.short(0), "0m")
    }

    func testShort_subMinute_returnsZeroMinutes() {
        XCTAssertEqual(EpisodeDurationFormatter.short(59), "0m")
    }

    func testShort_exactlyOneMinute() {
        XCTAssertEqual(EpisodeDurationFormatter.short(60), "1m")
    }

    func testShort_underOneHour() {
        XCTAssertEqual(EpisodeDurationFormatter.short(32 * 60), "32m")
    }

    func testShort_exactlyOneHour() {
        XCTAssertEqual(EpisodeDurationFormatter.short(60 * 60), "1h")
    }

    func testShort_oneHourFiveMinutes() {
        XCTAssertEqual(EpisodeDurationFormatter.short(65 * 60), "1h 5m")
    }

    func testShort_twoHours() {
        XCTAssertEqual(EpisodeDurationFormatter.short(2 * 3600), "2h")
    }

    func testShort_longRunNoMinuteRemainder() {
        XCTAssertEqual(EpisodeDurationFormatter.short(5 * 3600), "5h")
    }

    func testShort_negativeDurationClampsToZero() {
        // Behavior contract: defensive — never read as "-1m" to a user.
        // If this fails, file a bug and decide intent before patching.
        XCTAssertEqual(EpisodeDurationFormatter.short(-1), "0m")
    }

    // MARK: - spoken(_:) — VoiceOver-friendly

    func testSpoken_zero_returnsZeroMinutes() {
        XCTAssertEqual(EpisodeDurationFormatter.spoken(0), "0 minutes")
    }

    func testSpoken_subMinute_returnsZeroMinutes() {
        XCTAssertEqual(EpisodeDurationFormatter.spoken(45), "0 minutes")
    }

    func testSpoken_exactlyOneMinute_singular() {
        XCTAssertEqual(EpisodeDurationFormatter.spoken(60), "1 minute")
    }

    func testSpoken_pluralMinutes() {
        XCTAssertEqual(EpisodeDurationFormatter.spoken(32 * 60), "32 minutes")
    }

    func testSpoken_exactlyOneHour_singular() {
        XCTAssertEqual(EpisodeDurationFormatter.spoken(60 * 60), "1 hour")
    }

    func testSpoken_oneHourOneMinute_bothSingular() {
        XCTAssertEqual(EpisodeDurationFormatter.spoken(61 * 60), "1 hour 1 minute")
    }

    func testSpoken_oneHourFiveMinutes_hourSingularMinutesPlural() {
        XCTAssertEqual(EpisodeDurationFormatter.spoken(65 * 60), "1 hour 5 minutes")
    }

    func testSpoken_twoHoursOneMinute() {
        XCTAssertEqual(EpisodeDurationFormatter.spoken(2 * 3600 + 60), "2 hours 1 minute")
    }

    func testSpoken_twoHoursOnly_pluralNoMinutes() {
        XCTAssertEqual(EpisodeDurationFormatter.spoken(2 * 3600), "2 hours")
    }

    func testSpoken_largeDuration_24Hours() {
        XCTAssertEqual(EpisodeDurationFormatter.spoken(24 * 3600), "24 hours")
    }

    func testSpoken_negativeDuration() {
        // Same contract decision as short(): document and pin current
        // behavior; if it's wrong we patch it here.
        XCTAssertEqual(EpisodeDurationFormatter.spoken(-1), "0 minutes")
    }
}
```

- [ ] **Step 2: Run, expect failures or PASS**

Run:
```bash
xcodebuild -project OffScript.xcodeproj \
  -scheme OffScript \
  -destination "platform=iOS Simulator,id=$OFFSCRIPT_SIM_UDID" \
  -only-testing:OffScriptTests/EpisodeDurationFormatterTests \
  test 2>&1 | tee /tmp/duration-test.log | tail -30
```

Expected one of:
- All pass → spoken/short are correct in every covered case. Skip Task 1.2, go to 1.3.
- `testSpoken_zero_returnsZeroMinutes` / `testSpoken_subMinute_returnsZeroMinutes` etc. fail → real bug. **Read the failure carefully:** the current `spoken(_:)` returns `"0 minutes"` only when `hours == 0` and `minutes == 0` falls through the same branch — so this case looks fine but `negative` may not be. Whatever fails is real.
- Negative tests fail → defensive clamp is missing.

### Task 1.2: Fix any failures surfaced by 1.1

**Files:**
- Modify: `OffScript/AppTheme.swift:885-913`

- [ ] **Step 1: Patch only what failed**

If `testShort_negativeDurationClampsToZero` and/or `testSpoken_negativeDuration` failed, change the head of each function to:

```swift
static func short(_ duration: TimeInterval) -> String {
    let clamped = max(duration, 0)
    let minutes = Int(clamped / 60)
    // ... rest unchanged
}
```

and the equivalent in `spoken`. Do not refactor anything else. Run only the failing tests until they pass:
```bash
xcodebuild ... -only-testing:OffScriptTests/EpisodeDurationFormatterTests/testShort_negativeDurationClampsToZero test
```

- [ ] **Step 2: Re-run the whole formatter suite**

Same command as Task 1.1 Step 2. Expected: all green.

- [ ] **Step 3: Commit**

```bash
git add OffScriptTests/EpisodeDurationFormatterTests.swift OffScript/AppTheme.swift
git commit -m "test: pin EpisodeDurationFormatter.spoken contract + clamp negatives

Adds 20 unit tests (10 short, 10 spoken) covering zero, sub-minute,
exact boundaries, singular/plural agreement, and large durations.
Clamps negative input to 0 so neither readout can read '-1m' / 'minus
one minute' to a sighted or VoiceOver user."
```

If no fix was needed, the commit message drops the second paragraph.

### Task 1.3: Extract & test voiceOverMetadata builders

**Files:**
- Create: `OffScriptTests/VoiceOverMetadataTests.swift`
- Read: `OffScript/HomeView.swift:1098-1115`, `OffScript/HomeView.swift:1330-1345`, `OffScript/LibraryView.swift:2994-3015`

- [ ] **Step 1: Read all three voiceOverMetadata definitions and confirm they share shape**

Run: `grep -n -A 18 "private var voiceOverMetadata" OffScript/HomeView.swift OffScript/LibraryView.swift > /tmp/vo-metadata.txt && cat /tmp/vo-metadata.txt`

Expected: three near-identical builders that take a `pubDate`, an optional `season`/`episode` number, and a `duration`. If the bodies diverge in non-trivial ways, **note that as a finding** in the audit file — three copies that should be one.

- [ ] **Step 2: Write the failing test file**

Tests cover the *contract* from CHANGELOG.md ("drop uppercasing and the `·` separator, expand `S2 E5` to `Season 2 Episode 5`, use spoken duration"). To make those testable without booting the SwiftData store, the test file copies the builder logic into a small free function `voiceOverMetadataString(...)` matching the existing private vars exactly, then asserts on it:

```swift
import XCTest
@testable import OffScript

final class VoiceOverMetadataTests: XCTestCase {
    // Mirror of HomeView TunerRailCard.voiceOverMetadata.
    // If the production builder changes shape, update this mirror and the
    // matching production var in lockstep; the test name is intentional.
    private func voiceOverMetadataString(
        pubDate: Date?,
        season: Int?,
        episode: Int?,
        duration: TimeInterval?
    ) -> String {
        var parts: [String] = []
        if let pubDate {
            parts.append(Self.dateFormatter.string(from: pubDate))
        }
        if let season, let episode {
            parts.append("Season \(season) Episode \(episode)")
        } else if let episode {
            parts.append("Episode \(episode)")
        }
        if let duration, duration > 0 {
            parts.append(EpisodeDurationFormatter.spoken(duration))
        }
        return parts.joined(separator: ", ")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func testAllFieldsPresent_seasonAndEpisode() {
        let s = voiceOverMetadataString(
            pubDate: date(2026, 5, 1),
            season: 2, episode: 5,
            duration: 65 * 60
        )
        XCTAssertEqual(s, "May 1, 2026, Season 2 Episode 5, 1 hour 5 minutes")
    }

    func testEpisodeOnly_noSeason() {
        let s = voiceOverMetadataString(
            pubDate: date(2026, 5, 1),
            season: nil, episode: 12,
            duration: 32 * 60
        )
        XCTAssertEqual(s, "May 1, 2026, Episode 12, 32 minutes")
    }

    func testMissingDuration_omitted() {
        let s = voiceOverMetadataString(
            pubDate: date(2026, 5, 1),
            season: nil, episode: 12,
            duration: nil
        )
        XCTAssertEqual(s, "May 1, 2026, Episode 12")
    }

    func testZeroDuration_omitted() {
        let s = voiceOverMetadataString(
            pubDate: date(2026, 5, 1),
            season: nil, episode: 12,
            duration: 0
        )
        XCTAssertEqual(s, "May 1, 2026, Episode 12")
    }

    func testMissingPubDate_omitted() {
        let s = voiceOverMetadataString(
            pubDate: nil,
            season: 2, episode: 5,
            duration: 65 * 60
        )
        XCTAssertEqual(s, "Season 2 Episode 5, 1 hour 5 minutes")
    }

    func testAllOptionalsMissing_returnsEmptyString() {
        // Defensive: VoiceOver gets empty label string from caller;
        // the surrounding `accessibilityLabel` should drop trailing commas.
        let s = voiceOverMetadataString(
            pubDate: nil, season: nil, episode: nil, duration: nil
        )
        XCTAssertEqual(s, "")
    }

    func testNoUppercaseInOutput() {
        let s = voiceOverMetadataString(
            pubDate: date(2026, 5, 1),
            season: 2, episode: 5,
            duration: 65 * 60
        )
        // The visible mono variant uppercases ("MAY 1, 2026 · S2 E5 · 1H 5M");
        // the spoken variant must not, to avoid VO spelling letters.
        XCTAssertFalse(s.contains("MAY"))
        XCTAssertFalse(s.contains("1H"))
    }

    func testNoMiddleDotSeparator() {
        let s = voiceOverMetadataString(
            pubDate: date(2026, 5, 1),
            season: 2, episode: 5,
            duration: 65 * 60
        )
        // VO speaks "·" literally.
        XCTAssertFalse(s.contains("·"))
    }
}
```

- [ ] **Step 3: Run, expect pass**

```bash
xcodebuild ... -only-testing:OffScriptTests/VoiceOverMetadataTests test 2>&1 | tail -30
```

Expected: all green. The test mirrors the builder rather than calling into a view struct, so it's a snapshot of the contract. **If the test ever drifts from any of the three production builders, that's a finding.**

- [ ] **Step 4: Walk every production voiceOverMetadata var and confirm it matches the mirror**

For each of:
- `HomeView.swift:1098` (TunerRailCard)
- `HomeView.swift:1330` (other Home card)
- `LibraryView.swift:2996` (PodcastEpisodeTunerRow)

Open the file, diff the body against the test's `voiceOverMetadataString`. Any divergence (different ordering, missing field, different format) is logged in the audit file as a real finding and triggers a follow-up task to either fix the production code or update the mirror (with rationale).

- [ ] **Step 5: Commit**

```bash
git add OffScriptTests/VoiceOverMetadataTests.swift
git commit -m "test: snapshot voiceOverMetadata contract — no \"·\", no uppercase, spoken duration"
```

---

## Phase 2: VoiceOver functional walk

The Unreleased section claims ~25 specific VoiceOver improvements across Hero, Home rails, Library, Search, Queue, Player, EpisodeDetail, Settings. **None of them have been verified with VoiceOver actually turned on.** This phase walks each surface, records what VO says, and files any deltas as bugs.

### Task 2.1: Enable VoiceOver in the simulator + script the speech log

**Files:**
- Read: `docs/TEST_MATRIX.md` (for the launch-arg cheat sheet)

- [ ] **Step 1: Launch the app with the 258-show seed**

```bash
xcrun simctl install "$OFFSCRIPT_SIM_UDID" \
  "$(xcrun simctl get_app_container "$OFFSCRIPT_SIM_UDID" com.offscript.app app 2>/dev/null || \
     xcodebuild -project OffScript.xcodeproj -scheme OffScript -destination id=$OFFSCRIPT_SIM_UDID \
       -derivedDataPath /tmp/offscript-derived build 2>&1 | tail -1; \
     find /tmp/offscript-derived/Build/Products -name 'OffScript.app' -type d | head -1)"

xcrun simctl launch --console-pty "$OFFSCRIPT_SIM_UDID" com.offscript.app \
  -offscript.debugLibrarySize 258 \
  -offscript.debugLaunchTab 0 &
sleep 4
```

Expected: app foreground, Home tab, seeded library visible. If the install path is fragile, just build through Xcode once and re-run the launch line.

- [ ] **Step 2: Turn on VoiceOver**

The reliable simulator path is to toggle via the keyboard shortcut after enabling the **Accessibility Inspector** equivalent. From Terminal:
```bash
xcrun simctl spawn "$OFFSCRIPT_SIM_UDID" defaults write com.apple.Accessibility VoiceOverTouchEnabled -int 1
xcrun simctl spawn "$OFFSCRIPT_SIM_UDID" defaults write com.apple.Accessibility ApplicationAccessibilityEnabled -int 1
```

Verify with a screenshot:
```bash
xcrun simctl io "$OFFSCRIPT_SIM_UDID" screenshot /tmp/vo-on.png
```

Open `/tmp/vo-on.png` — confirm the VoiceOver focus rectangle is drawn. If not, fall back to manual: open the Simulator menu → I/O → Send Hardware Keyboard to Device, then Cmd-F5 / triple-click side button.

- [ ] **Step 3: Capture per-surface VO transcripts**

For each surface in 2.2–2.8, use the macOS **Accessibility Inspector** (Xcode → Open Developer Tool → Accessibility Inspector) targeted at the running simulator process. The inspector's "Audit" tab is the cheapest verification path; the "Inspection" tab gives the exact label/value/traits the simulator will hand to VoiceOver.

For each focusable element on the surface, paste the inspector's label string into the audit file under that surface's heading.

### Task 2.2: Home — Hero card, recommendation rails, discovery rail

**Surface:** `HomeView.swift`

- [ ] **Step 1: Focus the Hero card**

Expected label shape (from CHANGELOG):
```
Open <title> from <podcast>, <reason>, <date>, Season N Episode M, X minutes
```
plus a sibling `Play <title>`, `Add <title> to queue`, `More actions for <title>`.

Record what the inspector actually shows. If any element reads as `Button` only, or the spoken duration ends up as `1H 5M`, that's a finding.

- [ ] **Step 2: Focus a TunerRailCard row**

Expected: one combined stop per row + per-row Play / Queue buttons.

- [ ] **Step 3: Focus a starter pick (HomeStarterRail)**

Expected (per CHANGELOG #262): `Pick <rank>, <title>, by <author>, <summary>` + per-row `+ ADD <title>`.

- [ ] **Step 4: Focus the discovery rail (TunerDiscoveryRail)**

Expected (per CHANGELOG #256): per-pick error states (`✗ FAILED · RETRY`) read separately from the global error strip.

- [ ] **Step 5: Append findings to the audit file**

Add a `### Home` subsection under `## Surfaces` in `docs/superpowers/audits/2026-05-19-voiceover-walk.md`. Each finding row:
```markdown
- [ ] **Hero · `…` more-actions button:** Spoke `…, button`. Expected: `More actions for <title>`. → FILE FIX TASK.
```

### Task 2.3: Library — directory, alphabet rail, import strip, podcast detail

**Surface:** `LibraryView.swift`, `LibraryImportSheet.swift`, `PodcastDetailView.swift`

Same pattern as 2.2. Specific items to verify:

- [ ] **Step 1: Library SHOWS · DIRECTORY row**

Expected (#264): `Open channel NN, <title>, by <author>, <X> in progress, <Y> unplayed, sync failed`. Zero-padded channel number, no dangling clauses on healthy rows.

- [ ] **Step 2: Alphabet directory keys**

Each letter is expected to read as `Jump to <letter>`. With 258 shows, the alphabet rail is realistic; verify `Z` actually jumps + the audible feedback (scroll) finishes within ~1s.

- [ ] **Step 3: × UNSUBSCRIBE confirmation**

Two-stage flow: tap `×` → CONFIRM strip → tap CONFIRM. VO must reach both stages without trapping focus.

- [ ] **Step 4: Import sheet BACK button**

Expected (CHANGELOG): `Back to import menu`, single stop. 44pt min height — verify with inspector's Frame readout.

- [ ] **Step 5: PodcastDetail RETRY key on load error**

Expected: ↻ RETRY reads as `Retry loading <podcast name>` (or close to it). If just `Retry`, that's a finding.

- [ ] **Step 6: Append findings under `### Library`**

### Task 2.4: Search — topic chips, recent searches, results, pull-to-refresh

**Surface:** `SearchView.swift`

- [ ] **Step 1: Topic chip row**

Expected: `Topic <name>` per chip; activating runs the search.

- [ ] **Step 2: RECENT SEARCHES × CLEAR confirmation**

Two-stage. CONFIRM strip count should be `1 recent search` for a single entry, `N recent searches` plural otherwise.

- [ ] **Step 3: Search result row**

Expected (#261): `Result <rank>, in library, <title>, by <author>` + per-row `+ ADD TO LIBRARY <title>` / `→ WEBSITE for <title>`. Missing-author rows must drop the trailing `by ` (not read `by ,`).

- [ ] **Step 4: × CLEAR SEARCH on empty/no-match state**

Expected: `Clear search` or similar single-action label.

- [ ] **Step 5: Pull-to-refresh gesture**

Trigger with the inspector's pull-to-refresh simulation. Idle (no query) must be a no-op.

- [ ] **Step 6: Append findings under `### Search`**

### Task 2.5: Queue — lead strip, rows, tappable detail, × CLEAR ALL

**Surface:** `QueueView.swift`

- [ ] **Step 1: Lead-strip → PLAY / × REMOVE**

Expected: title-aware labels.

- [ ] **Step 2: Queue row tappable area**

NavigationLink label: `Open <title> from <podcast> detail`. Sibling play/move/remove must keep their own a11y elements (verify focus order: NavigationLink → Play → Move → Remove).

- [ ] **Step 3: × CLEAR ALL two-stage confirmation**

Expected: count pluralizes correctly (`1 episode` vs `N episodes`).

- [ ] **Step 4: Empty state**

After `× CLEAR ALL`, empty state must read `Queue empty, Nothing queued yet, Explore shows` + actionable button label.

- [ ] **Step 5: Append findings under `### Queue`**

### Task 2.6: PlayerView — UP NEXT, transport, SPEED, SLEEP

**Surface:** `PlayerView.swift`

- [ ] **Step 1: UP NEXT combined stop**

Expected (#263): `Up next, <title>, from <podcast>, <duration>`. Single stop + sibling `→ PLAY` / `× DROP`.

- [ ] **Step 2: Transport controls**

`Play / Pause / Skip back 15 seconds / Skip forward 30 seconds` (or whatever the configured skip intervals are; verify with `Settings → Playback`).

- [ ] **Step 3: SPEED menu**

Already covered by 2.3.11 (`Playback speed` + hint). Verify hint still reads.

- [ ] **Step 4: SLEEP menu**

Already covered by 2.3.11. Verify both states: timer off vs. timer running.

- [ ] **Step 5: DURATION readout**

The visible mono text is `32M` etc.; the spoken label must be `32 minutes`. Confirm.

- [ ] **Step 6: Append findings under `### Player`**

### Task 2.7: EpisodeDetail — action chips, feedback, time-remaining

**Surface:** `EpisodeDetailView.swift`

- [ ] **Step 1: Action chips**

Expected: `Play <title>` / `Resume <title>` / `Now playing <title>`, `Add <title> to queue` / `Already queued`, `Retry download for <title>`, `Like <title>` / `Liked`, `Not for me — show fewer episodes like <title>` / `Marked not for me`.

- [ ] **Step 2: timeRemaining progress strip**

Expected (#270): `15 minutes left` (using `EpisodeDurationFormatter.spoken`). The visible `15M LEFT` is for sighted users only.

- [ ] **Step 3: SF Symbol decoration hidden from a11y**

Per CHANGELOG: decorative SF Symbols inside the chips must be hidden from accessibility. Verify with inspector — no element should report a label like `arrow.up.left`.

- [ ] **Step 4: Append findings under `### EpisodeDetail`**

### Task 2.8: Settings — sign-in identity, sign-out, signal rebuild

**Surface:** `SettingsView.swift`

- [ ] **Step 1: CREDENTIAL / CLOUD readouts**

Expected: each reads as one combined element (label + value), not split.

- [ ] **Step 2: Sign-out two-stage confirmation**

Sign out → CONFIRM strip → Cancel / Confirm. Cancel must return cleanly; the confirm hint must indicate destructiveness.

- [ ] **Step 3: Signal rebuild key**

Expected: `Rebuild signal` or close.

- [ ] **Step 4: Recommendation tuner (SIGNAL / BALANCED / DISCOVERY)**

(This one is from the *prior* Unreleased work documented in the orphaned worktree's CHANGELOG and may not yet be on main — confirm whether it ships in 2.4.0. If it does, verify the three-position control has a single combined a11y element with the current value spoken.)

- [ ] **Step 5: Append findings under `### Settings`**

### Task 2.9: Triage findings → file fix tasks

- [ ] **Step 1: Scan the audit file**

Open `docs/superpowers/audits/2026-05-19-voiceover-walk.md`. For each `→ FILE FIX TASK` line, add a corresponding task to this plan under "Phase 2.X · Fix VO Finding N" with the exact file, line, and patch.

- [ ] **Step 2: Apply each fix as its own commit**

Per finding, one commit, message `fix(a11y): <finding>`. Re-run the inspector on the fixed surface to verify before moving to the next.

- [ ] **Step 3: Commit the audit file**

```bash
git add docs/superpowers/audits/2026-05-19-voiceover-walk.md
git commit -m "docs: VoiceOver walk findings for 2.4.0 audit"
```

---

## Phase 3: New UI test stability

The Unreleased section adds ~14 new UI tests. UI tests on iOS are notorious for flakes (animation timing, simulator state, network during launch). This phase runs each new test 5× and surfaces any flakes before they hit CI.

### Task 3.1: Run new UI tests in a loop

**Files:**
- Read: `OffScriptUITests/OffScriptUITests.swift`

- [ ] **Step 1: Identify new tests vs. tests that existed before this release**

Run: `git log --diff-filter=A --pretty=format: --name-only HEAD~80..HEAD | grep OffScriptUITests | sort -u`

Expected output: shows whether new test methods landed in distinct files or just in `OffScriptUITests.swift`. Cross-reference against the test method list captured earlier:

```
testQueueClearAllRequiresConfirmation
testQueueRowOpensEpisodeDetail
testSettingsPanelOpensWithLargeLibrarySeed
testLibraryImportKeyOpensImportSheet
testLargeLibrarySeedSmoke
testLargeLibrarySwitchesFromLibraryToHomeQuickly
testLargeLibraryAlphabetRailJumpsToSelectedLetter
testLargeLibraryDirectoryControlsStayResponsive
testTunerDetailScreensUseInlineBackChrome
testLibraryReloadsAfterDetailUnsubscribe
testSettingsPanelDismissAndReopenCycleStaysStable
testSettingsSignOutConfirmDismissesCleanly
testLibraryShowsEmptyStateOnFreshLaunch
testQueueShowsEmptyStateOnFreshLaunch
```

- [ ] **Step 2: Run each five times, capture pass/fail**

For each test (replace `<TestName>`):
```bash
for i in 1 2 3 4 5; do
  echo "=== Run $i ==="
  xcodebuild -project OffScript.xcodeproj \
    -scheme OffScript \
    -destination "platform=iOS Simulator,id=$OFFSCRIPT_SIM_UDID" \
    -only-testing:OffScriptUITests/OffScriptUITests/<TestName> \
    test 2>&1 | tail -5
done
```

Record results in a table in `docs/superpowers/audits/2026-05-19-ui-flake.md`:
```markdown
| Test | R1 | R2 | R3 | R4 | R5 | Notes |
|---|---|---|---|---|---|---|
| testQueueRowOpensEpisodeDetail | ✓ | ✓ | ✓ | ✓ | ✓ |  |
| testLargeLibraryAlphabetRailJumpsToSelectedLetter | ✓ | ✗ | ✓ | ✓ | ✓ | timing |
```

- [ ] **Step 3: For any flaky test, capture the failure log**

Run a sixth time with `-resultBundlePath /tmp/<test>.xcresult`; open with Xcode to see the screenshot + failure timeline. Add the diagnosis to the table's Notes column.

### Task 3.2: Fix flakes by stabilising waits, not by skipping

For each flaky test:

**Files:**
- Modify: `OffScriptUITests/OffScriptUITests.swift:<line>`

- [ ] **Step 1: Diagnose**

Common causes:
- `app.tap()` before the target's animation finishes — fix with `XCTNSPredicateExpectation` waiting on `exists == true && isHittable == true`, not a sleep.
- Simulator state contamination — fix by adding `-offscript.debugWipeLibrary YES` to that test's launch args if it isn't there yet.
- Async SwiftData fetch racing first render — fix with an explicit wait on the expected first-row's `exists` predicate.

- [ ] **Step 2: Patch with a wait, not a sleep**

Pattern:
```swift
let row = app.buttons["Z"]
XCTAssertTrue(row.waitForExistence(timeout: 5), "Alphabet Z key never rendered")
row.tap()
let zHeader = app.staticTexts["Z"].firstMatch
XCTAssertTrue(zHeader.waitForExistence(timeout: 3), "List did not scroll to Z section")
```

Never `Thread.sleep`, never `sleep(_)`, never raw `usleep`.

- [ ] **Step 3: Re-run the once-flaky test 10× to confirm stable**

If any of the 10 still fails, the wait isn't sufficient — return to Step 1.

- [ ] **Step 4: Commit per fix**

`fix(uitest): wait for alphabet rail before tapping Z` etc.

---

## Phase 4: 258-show performance audit

The Unreleased section adds a deterministic 258-show seed (`-offscript.debugLibrarySize 258`). This is the Library scrolling case the v2.3.11 polish round targeted. Verify the optimization stuck and that the alphabet rail, search, and tab switches all stay snappy.

### Task 4.1: Cold launch + Library scroll

**Files:**
- Read: `OffScript/LibraryView.swift:1-100`

- [ ] **Step 1: Cold launch into Library**

```bash
xcrun simctl terminate "$OFFSCRIPT_SIM_UDID" com.offscript.app
time xcrun simctl launch "$OFFSCRIPT_SIM_UDID" com.offscript.app \
  -offscript.debugLibrarySize 258 \
  -offscript.debugLaunchTab 1
```

Record wall time. Target: under 2.5s on a base M-series Mac simulator.

- [ ] **Step 2: First-render screenshot**

Run `sleep 1 && xcrun simctl io "$OFFSCRIPT_SIM_UDID" screenshot /tmp/lib-cold.png`.

Open the screenshot — verify the first ~12 rows render with their counts (`X IN PROGRESS · Y UNPLAYED`), the alphabet rail is present, and no spinner persists.

- [ ] **Step 3: Profile a scroll if launch > 2.5s**

Use Instruments via `xcrun xctrace record --output /tmp/lib.trace --template 'Time Profiler' --target-stdout - --launch -- com.offscript.app ...`. Open the trace, check for hot frames in `LibraryView.body` or `@Query` recomputation. The v2.3.11 fix split into two predicate-filtered queries — verify there's no third fetch-all that crept back in.

- [ ] **Step 4: Document numbers in `docs/superpowers/audits/2026-05-19-258-show-perf.md`**

### Task 4.2: Alphabet jump

- [ ] **Step 1: Time the Z jump**

In the inspector, watch the scroll completion. If it takes more than ~400ms, that's a finding.

- [ ] **Step 2: Verify hidden sections render lazily**

Scroll back to A, then jump to Z — the intermediate sections should not all be hydrated. Check Memory in Xcode debug navigator: stable, not growing.

- [ ] **Step 3: Document**

### Task 4.3: Search-as-you-type on a large library

- [ ] **Step 1: Type a 3-char query in Search**

Time from last keystroke to first result. Target: under 200ms.

- [ ] **Step 2: Document and commit perf audit**

```bash
git add docs/superpowers/audits/2026-05-19-258-show-perf.md
git commit -m "docs: 258-show performance audit for 2.4.0"
```

---

## Phase 5: Design-system & token conformance

CLAUDE.md is explicit: no inline `Color.white.opacity(0.XX)`, no raw `Font.system()` outside named styles, hairline = `offscriptHairline`, artwork radius = 3pt rectangle, button radius = 0pt. The Unreleased section touches a lot of view code; any backslide is easy to introduce in an a11y pass.

### Task 5.1: Grep for inline color violations

- [ ] **Step 1: Run the violation scan**

```bash
grep -nE "Color\.(white|black)\.opacity\(" OffScript/ -r | grep -v "// " > /tmp/color-violations.txt
wc -l /tmp/color-violations.txt
```

Expected: zero lines after dropping comment-only matches. Anything that returns is a finding.

- [ ] **Step 2: Triage each violation**

For each line, either:
- swap to `Color.offscriptHairline` / `Color.offscriptSoftPaper` / a token from `AppTheme.swift`, OR
- if no token fits, add a token to AppTheme and use that.

- [ ] **Step 3: Commit per logical group of fixes**

`fix(design): swap inline white opacity for offscriptHairline in <file>`.

### Task 5.2: Grep for raw Font.system outside AppTheme

- [ ] **Step 1: Scan**

```bash
grep -nE "\.font\(\.system\(" OffScript/ -r --include='*.swift' | \
  grep -v "AppTheme.swift" | \
  grep -v "// " > /tmp/font-violations.txt
wc -l /tmp/font-violations.txt
```

CLAUDE.md allows certain named display/section/body usages but discourages ad-hoc `Font.system()`. Each line is a candidate finding; decide per-site whether it should move into AppTheme or use an existing token.

- [ ] **Step 2: Patch as appropriate, commit per group**

### Task 5.3: Artwork radius + hairline border audit

- [ ] **Step 1: Grep for OffScriptArtworkView usages**

```bash
grep -n "OffScriptArtworkView" OffScript/ -r | grep -v "AppTheme.swift" > /tmp/artwork.txt
```

Verify each call uses `cornerRadius: 3` and is followed by a `Rectangle().stroke(Color.offscriptHairline)` overlay (CLAUDE.md spec). Anything bare or with `cornerRadius: 12 / 24` is from the legacy editorial direction and is a finding.

- [ ] **Step 2: Patch + commit**

---

## Phase 6: Confirmation & retry flow audit

The Unreleased section introduces several two-stage confirmation patterns and several retry keys. Each must be walked once with touch and once with VoiceOver, and the audit file should record any state where the user gets stuck.

### Task 6.1: Confirmation strips

- [ ] **Step 1: Verify each two-stage confirm**

Walk in this order:
1. Library × UNSUBSCRIBE → CONFIRM
2. Queue × CLEAR ALL → CONFIRM (with 1, 5, and 0 episodes — verify pluralization)
3. Search RECENT SEARCHES × CLEAR → CONFIRM
4. Settings sign-out → CONFIRM

For each: tap CONFIRM and verify the destructive action completes; reset the seed; tap CANCEL and verify nothing changed and Settings/Library/Search/Queue stay foregrounded.

- [ ] **Step 2: Repeat with VoiceOver on**

Same path with VO on. Confirm focus reaches both CONFIRM and CANCEL keys without trapping.

- [ ] **Step 3: Document any stuck-focus / can't-dismiss / silent-success cases**

### Task 6.2: Retry keys

- [ ] **Step 1: Force a transient error in each location**

- PodcastDetail load error: launch with airplane mode on (`xcrun simctl status_bar booted override --dataNetwork none --wifiMode failed`), navigate to a podcast, verify ↻ RETRY appears, restore network, tap RETRY, verify success.
- Search error strip: same airplane-mode pattern, perform a search, tap RETRY.
- Home discovery rail per-pick error: with network off, tap + TUNE on a discovery row, verify `✗ FAILED · RETRY` flips state and that **a sibling row's tap is independent** (separate `importingIDs` tracking from #214).

- [ ] **Step 2: Restore network**

```bash
xcrun simctl status_bar booted clear
```

- [ ] **Step 3: Commit confirmation/retry findings**

---

## Phase 7: Release prep

### Task 7.1: Bump version + write release notes

**Files:**
- Modify: `OffScript.xcodeproj/project.pbxproj` (`CURRENT_PROJECT_VERSION`)
- Modify: `CHANGELOG.md` (promote Unreleased → `[2.4.0] — 2026-05-19`)
- Create: `build/TestFlight/notes/testflight-notes.txt`

- [ ] **Step 1: Decide on the version**

The Unreleased section is large (~30 a11y improvements + new UI tests + new Home lane). Recommend `MARKETING_VERSION = 2.4.0` (minor bump, since this is a perceivable user-facing improvement to a11y) and `CURRENT_PROJECT_VERSION = 2026051901`. Confirm with operator before bumping.

- [ ] **Step 2: Promote Unreleased**

In `CHANGELOG.md`, change `## [Unreleased]` → `## [Unreleased]\n\n## [2.4.0] — 2026-05-19\n\n<existing body>` so the next release has a clean Unreleased header at the top.

- [ ] **Step 3: Bump project version**

In `OffScript.xcodeproj/project.pbxproj`, find every occurrence of `CURRENT_PROJECT_VERSION = 2026043004` and bump to `2026051901`. Find `MARKETING_VERSION = 2.3.11`, bump to `2.4.0` (only if Step 1 confirmed).

- [ ] **Step 4: Write TestFlight notes**

Write `build/TestFlight/notes/testflight-notes.txt`:
```
2.4.0 — VoiceOver pass

— Hero, rails, Library, Search, Queue, Player, Episode Detail, Settings: actions, rows, and metadata now read with explicit, title-aware labels instead of mono visible text or icon names.
— Spoken durations ("1 hour 5 minutes") replace the visible "1H 5M" glyphs for VoiceOver.
— New "More From Shows You Chose" Home lane separates your explicit like signal from passive completion.
— Search now supports pull-to-refresh; clear recents now requires confirm.
— Queue rows are tappable to open episode detail.
— Internal: deterministic 258-show seed for UI tests; canonical TEST_MATRIX.

Known limits: <fill in from audit findings that didn't make it>
```

- [ ] **Step 5: Local archive smoke-test**

```bash
xcodebuild -project OffScript.xcodeproj \
  -scheme OffScript \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -archivePath /tmp/OffScript-2.4.0.xcarchive \
  archive 2>&1 | tail -20
```
Expected: `** ARCHIVE SUCCEEDED **`. This isn't the production archive (Xcode Cloud does that) — it's a sanity check that signing + entitlements + Sentry config still work.

- [ ] **Step 6: Commit + push the release branch**

```bash
git add CHANGELOG.md OffScript.xcodeproj/project.pbxproj build/TestFlight/notes/testflight-notes.txt
git commit -m "chore: cut 2.4.0 — VoiceOver pass + new UI test coverage"
git push -u origin release/2.4.0-audit
```

- [ ] **Step 7: Open PR**

```bash
gh pr create --title "Cut 2.4.0 — VoiceOver pass + UI test coverage" --body "$(cat <<'EOF'
## Summary
- Audit + harden the Unreleased section before the next TestFlight push.
- 20 new unit tests pin EpisodeDurationFormatter.spoken contract.
- VoiceOver walked on simulator across Home, Library, Search, Queue, Player, Episode Detail, Settings (see `docs/superpowers/audits/2026-05-19-voiceover-walk.md`).
- 258-show performance regression check (see `docs/superpowers/audits/2026-05-19-258-show-perf.md`).
- Promotes Unreleased → 2.4.0; bumps CURRENT_PROJECT_VERSION to 2026051901.

## Test plan
- [ ] All new unit tests pass
- [ ] Every UI test in `OffScriptUITests` runs green 5×
- [ ] VoiceOver walk audit file shows no open findings
- [ ] Local archive succeeds with Release config
- [ ] Xcode Cloud build on `release/2.4.0-audit` succeeds

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 8: Hand off to Xcode Cloud**

Per `docs/TESTFLIGHT.md`, merging to `main` triggers Xcode Cloud. Either merge the PR after review or push a `v2.4.0-rc1` tag if you want to ship from the branch first. Don't `start-build` manually unless you need to bypass the merge — let CI handle it.

---

## Self-Review

- **Spec coverage:** Every claim in the Unreleased section maps to a task — VoiceOver to Phase 2.X, spoken-duration to Phase 1, new UI tests to Phase 3, 258-show seed to Phase 4. New Home "More From Shows You Chose" lane is verified during Phase 2.2. The recommendation-tuner mentioned in the orphaned worktree is handled defensively in Task 2.8 Step 4 — confirm whether it's actually on main before counting it in scope.
- **Placeholders:** None — every step has a concrete command or file edit.
- **Type consistency:** `EpisodeDurationFormatter` is the same name everywhere; `voiceOverMetadata` (private var) is the same shape across the three call sites and matches the test mirror.

## Risks & escape hatches

- **VoiceOver walk in Accessibility Inspector is manual.** If this gets tedious mid-pass, switch to scripted UI tests that read `XCUIElement.label` for each focusable element and assert against expected strings — pricier to write but cheaper to re-run on every change.
- **xcodebuild flakes on the simulator pool.** If a UI test fails on R1 and passes on R2-R5, run it 5 more times before classifying as flake.
- **The audit may surface more than 3-4 fixable findings.** If it does, ship 2.4.0 with the must-fix subset (anything where VO is silent, misleading, or traps focus) and move the polish-tier findings to a 2.4.1 Unreleased section. Do not let the audit balloon block the release indefinitely — the whole point is to ship one good build, not a perfect one.

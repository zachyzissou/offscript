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


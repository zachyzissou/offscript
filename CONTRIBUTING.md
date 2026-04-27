# Contributing to OffScript

Thanks for the interest. OffScript is currently a single-maintainer project (with some Claude agent work) and **isn't accepting external code contributions yet**. Bug reports, design feedback, and feature ideas are very welcome.

## If you're a TestFlight tester

- **Crashes** are already in Sentry. You don't need to file anything. If you want to add color (what episode you were on, what you tapped right before), open an issue.
- **Bugs that aren't crashes** (UI weirdness, wrong recommendations, sync issues, audio glitches): please [open a Bug Report issue](https://github.com/zachyzissou/offscript/issues/new?template=bug_report.yml).
- **Feature ideas**: [open a Feature Request issue](https://github.com/zachyzissou/offscript/issues/new?template=feature_request.yml).

## If you want to read the code

That's encouraged — it's public for transparency. The architecture overview is in [`README.md`](README.md), the design vocabulary is in [`DESIGN.md`](DESIGN.md), and the agent-readable design bible is [`CLAUDE.md`](CLAUDE.md). Re-using anything in your own project requires permission — see [`LICENSE`](LICENSE).

## Codebase guidelines (for the maintainer + agents)

These live in [`CLAUDE.md`](CLAUDE.md), but the most important ones:

- **Use the named tokens.** No inline `Color.white.opacity(0.XX)` or raw `Font.system(...)` — use `offscriptAccent`, `offscriptCard`, `.offscriptHero`, `.offscriptMeta`, etc. The Tuner palette flows through these.
- **Tuner primitives.** New UI uses `TunerTag`, `TunerLabel`, `TunerRingMeter`, `TunerReadout`, `TunerTransportButton`, `TunerModeToggle`. Don't reinvent.
- **No bare `try?`.** Always do/catch with OSLog. The categories are per service (`Logger(subsystem: "OffScript", category: "ServiceName")`).
- **SwiftData.** Use predicate-filtered `FetchDescriptor`, never fetch-all-then-filter. Never `persistentModelID` in `#Predicate` — use stored UUIDs.
- **Stay in-app.** Never open external URLs without `SFSafariViewController`.
- **Build the actual project** before declaring something fixed. SourceKit's "Cannot find type in scope" for cross-file types is a false positive — use `xcodebuild` or the Xcode MCP `BuildProject`.

## Releasing

OffScript ships through three TestFlight pathways. Pick the one that matches the
intent of the change:

### 1. Curated release — preferred (cut a GitHub Release)

Use this for anything that should ship with intentional, human-written notes
(features, design refreshes, UX improvements, anything you'd want a tester to
*understand* before opening the app).

1. Bump `MARKETING_VERSION` in the project to the new SemVer, e.g. `2.3.0`.
   Commit + merge to `main` first so the version is the source of truth.
2. On GitHub: **Releases → Draft a new release**.
3. **Tag**: `vX.Y.Z` matching the marketing version (e.g. `v2.3.0`). The leading
   `v` is stripped automatically by the workflow.
4. **Title**: short, expert phrasing — "OffScript 2.3 — Apple Intelligence + Live
   Activity" beats "Release 2.3.0".
5. **Body**: write the actual TestFlight What-To-Test notes here. The workflow
   uses the release body verbatim as TestFlight notes, so:
   - Lead with the headline change in one sentence
   - Group fixes / additions / known issues with H3 headings
   - Reference issue / PR numbers where relevant
   - Avoid marketing words ("revolutionary", "must-try"); state what's there
6. Mark **Pre-release** while it's a TestFlight beta. Convert to a final release
   when you actually ship to the App Store.
7. **Publish release**. The `release: published` trigger on
   `.github/workflows/testflight.yml` takes over: it builds, uploads to
   TestFlight, attaches the release body as TestFlight notes, and pings external
   testers automatically.

### 2. Fast path — push to `main`

Use this for hotfixes, dependency bumps, or small iterative pushes that don't
warrant manual notes.

Push (or merge a PR) to `main`. The workflow:
- Builds + uploads to TestFlight (notes auto-generated from the commit log)
- Cuts a GitHub Release tagged `testflight-X.Y.Z-build.N` and marked as
  pre-release, with the auto-generated notes attached
- The release stays editable on the Releases page if you want to clean up the
  notes after the fact

### 3. Manual override — `workflow_dispatch`

Run the workflow from the **Actions** tab when you need explicit control:
- Custom `marketing_version` / `build_number`
- Custom summary + What-To-Test text
- Useful for re-running a build without a code change

### Versioning + the changelog

- `MARKETING_VERSION` is SemVer; the git tag matches (`v2.3.0`).
- TestFlight build numbers are `YYYYMMDD<run-number><attempt>` (auto-generated).
- `CHANGELOG.md` should grow a new `## [X.Y.Z] — DATE` block in the same PR that
  lands the version bump. The release body and the changelog block don't have
  to be word-for-word identical — the changelog is the durable record, the
  release body is what testers see.

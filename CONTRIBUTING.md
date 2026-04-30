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

OffScript ships through **Xcode Cloud** — Apple's CI/CD that runs inside App
Store Connect. It manages signing certs / provisioning profiles automatically
(no Apple Developer cert-cap pain), auto-registers new bundle IDs (so adding
extension targets just works), and uploads to TestFlight as a built-in action.

### Two trigger paths

**Path 1 — Push to `main`** (fast, day-to-day):
- Push (or merge a PR) to `main`
- Xcode Cloud detects the push, archives, signs, uploads to TestFlight
  with TestFlight and App Store deployment preparation so the same build can
  be assigned to internal and external testers
- No release notes are written; testers see the commit message

**Path 2 — Cut a GitHub Release with `vX.Y.Z` tag** (curated):
- Bump `MARKETING_VERSION` in the project to the new SemVer, commit + merge
  to `main` first so the version is the source of truth
- On GitHub: **Releases → Draft a new release**, tag `vX.Y.Z` matching the
  marketing version, write expert TestFlight notes in the body
- Pushing the tag triggers Xcode Cloud's tag start condition
- For TestFlight notes that pull from the release body, see the optional
  `ci_post_xcodebuild.sh` hook (TODO — not wired yet; today release notes
  on TestFlight come from the manually-edited What-To-Test field in
  TestFlight UI)
- Update `CHANGELOG.md` in the same PR as the version bump

### Operational tooling

The pipeline lives in App Store Connect's web UI but is fully manageable
from `scripts/app_store_connect.py`:

```sh
# Inspect the current Xcode Cloud setup
scripts/app_store_connect.py xcode-cloud probe

# Inspect a specific workflow's start condition + actions + recent builds
scripts/app_store_connect.py xcode-cloud inspect <workflow-uuid>

# Reconfigure a workflow (branch + tag conditions + TestFlight audience)
scripts/app_store_connect.py xcode-cloud reconfigure <workflow-uuid> --testflight --apply

# Manually trigger a build run
scripts/app_store_connect.py xcode-cloud start-build <workflow-uuid>
```

These commands all need the same ASC API key the legacy GH Actions workflow
used (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`). For one-off ops, run
the same commands from the **Xcode Cloud Probe** GitHub Actions workflow
(Actions tab → Run workflow) so you don't need a local `.env`.

### Pre-build hook

`ci_scripts/ci_post_clone.sh` runs inside Xcode Cloud immediately after the
repo clone. It materializes `Config/Secrets.xcconfig` from the `SENTRY_DSN`
environment variable Xcode Cloud passes in. Set the variable in App Store
Connect → Xcode Cloud → Workflows → Environment.

### Versioning + the changelog

- `MARKETING_VERSION` is SemVer; the git tag matches (`v2.3.0`).
- Build numbers come from Xcode Cloud (sequential per workflow). Override
  via the `CI_BUILD_NUMBER` environment variable if needed.
- `CHANGELOG.md` should grow a new `## [X.Y.Z] — DATE` block in the same PR
  that lands the version bump.

### Why we left GH Actions behind

The previous `.github/workflows/testflight.yml` (now `.disabled`) ran
`xcodebuild archive + altool upload` on a hosted macOS-26 runner. It worked
but kept hitting Apple-side limits that Xcode Cloud is immune to:
- iOS distribution cert cap (3 / account) was tripped every time a new
  bundle ID auto-created a cert
- New extension bundle IDs needed manual provisioning profile setup in the
  Apple Developer Portal before CI could sign them
- Sentry DSN injection had to be hand-rolled in the workflow

Xcode Cloud handles all three natively. The disabled workflow file stays
in `.github/workflows/testflight.yml.disabled` for historical reference;
move it back if Xcode Cloud ever has an outage and you need the fallback.

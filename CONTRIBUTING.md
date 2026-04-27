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

Push to `main` triggers `.github/workflows/testflight.yml`, which archives, runs unit tests, uploads to TestFlight, waits for ASC processing, and writes the release notes from the commit log. No manual steps.

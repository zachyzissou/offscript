# Changelog

All notable changes to OffScript. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html) — though TestFlight builds carry a `YYYYMMDD<run>.<attempt>` build number layered on top of the marketing version.

## [Unreleased]

### Added
- GitHub repo overhaul: README, CONTRIBUTING, LICENSE, issue + PR templates, this changelog.

## [2.0] — 2026-04-26

### Added
- **Tuner OLED design direction.** Pure black field, signal-yellow primary accent, function-coded tag pills (record-red / mode-green / power-yellow / info-cyan), single-pixel hairlines, monospaced metadata. Replaces the previous warm-amber editorial direction.
- New design primitives: `TunerTag`, `TunerRingMeter`, `TunerReadout`, `TunerTrace`, `TunerTransportButton`, `TunerModeToggle`, `TunerLabel`, `TunerArtworkTile`.
- New onboarding flow: POWER ON welcome → "01 · TASTE / Pick your bands" → "02 · CHANNELS / Tune the bank" → import.
- New EpisodeDetail spec sheet layout with Ferrari-cluster readouts.
- New app icon: signal-yellow VU dial on OLED black with REC indicator.
- **Sentry-Cocoa** integration (errors-only, quota-aware): sampleRate 1.0 for errors, 5% perf transactions, no profiling, screenshot/view-hierarchy capture off for privacy.
- **MetricKit** subscription via `MetricKitReporter` — daily metric payloads logged via OSLog, crash diagnostics forwarded into Sentry as `.fatal` events.

### Changed
- All theme tokens (`offscriptAccent`, `offscriptCard`, `offscriptBackground`, etc.) remap to Tuner OLED palette automatically — every existing surface inherits the new look without per-view rewrites.
- `OffScriptScrubber` rebuilt as instrument-scale rule (60-tick major/minor/fine, thin playhead, NOW caption) — replaces the previous capsule + thumb scrubber.
- `OffScriptProgressBar` reduced to 1px hairline + signal-yellow fill — replaces the gradient capsule.
- Surface modifier (`offscriptSurface` / `offscriptUtilitySurface`) switched from gradient cards to flat black + 1px hairline; corner radii reduced to 3-6 pt (was 16-32 pt).
- Typography swapped from Playfair Display to SF Pro Display at light weights with tight tracking; SF Mono with wide tracking for all metadata.

### Fixed
- CI TestFlight upload: `AppIcon.appiconset/Contents.json` had iOS universal entries with no `filename`, so the asset compiler shipped icon-less bundles and ASC rejected the upload (missing 120/152 px icons + `CFBundleIconName`). Wired `AppIcon.png` into all three iOS universal entries.
- CI signing: rotated `ASC_KEY_P8_BASE64` GitHub secret to a working API key with provisioning-profile cloud-fetch permissions.

## [1.14.1] and earlier

See git history. Pre-2.0 versions used the warm-amber editorial direction and shipped via manual `xcodebuild` runs.

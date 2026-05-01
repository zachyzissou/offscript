# OffScript

> A podcast app that listens to what *you* listen to — not to whoever paid for placement.

OffScript is an iOS podcast app with **on-device, privacy-first recommendations**. We use Apple's machine learning stack to build a taste profile from your actual listening — no algorithmic feed manipulation, no paid promotions, no tracking-cookie-of-podcasting "for you" page.

The app is currently shipping the **Tuner OLED** design direction — pure black field, signal-yellow accent, instrument-cluster vocabulary. Think Ferrari dashboard for your earphones, not Spotify pastel.

---

## Status

| Area | State |
|------|-------|
| Platform | iOS 26.2+ (SwiftUI / SwiftData) |
| Distribution | TestFlight beta — internal + external groups |
| CI | Xcode Cloud on `main` / `v*`; GitHub Actions probe workflow only |
| Crash + perf telemetry | Sentry (errors-only, quota-aware) + MetricKit |
| Marketing version | `2.3.11` |

[![Xcode Cloud Probe](https://github.com/zachyzissou/offscript/actions/workflows/xcode-cloud-probe.yml/badge.svg)](https://github.com/zachyzissou/offscript/actions/workflows/xcode-cloud-probe.yml)

---

## What's different

**No algorithm, no paid placements.** Recommendations are computed on-device from your listening history, podcasts you've liked, and topics you've spent the most hours on. Nothing about your taste leaves your phone.

**Audio + video, equal billing.** Most podcast apps treat video as an afterthought. We treat them as the same content with different presentation.

**A taste profile you can actually read and edit.** The on-device ML model is exposed in the Profile tab — you can see what topics you're "tuned to," nudge them up or down, and the recommendations re-rank live.

**Editorial pacing.** Your home feed has *one* lead recommendation per session — not 47 cards in 12 rails. The rest is on demand.

---

## Architecture

```
OffScript/
├─ App/
│  ├─ OffScriptApp.swift          @main — boots Sentry, MetricKit, ModelContainer
│  ├─ ContentView.swift           Tab shell + MiniPlayer mounting
│  └─ AppTheme.swift              Tuner palette, typography, primitives
├─ Models/
│  └─ Models.swift                Podcast / Episode / QueueItem / TasteProfile (SwiftData)
├─ Services/
│  ├─ PodcastServices.swift       Search, RSS sync, queue, taste extraction
│  ├─ PlaybackController.swift    AVPlayer + MPNowPlaying + remote command center
│  ├─ RecommendationService.swift On-device ranker
│  └─ CrashReporter.swift         Sentry init (DSN-gated, errors-only)
├─ Views/
│  ├─ HomeView                    Lead recommendation + rails
│  ├─ LibraryView                 Subscribed shows
│  ├─ SearchView                  iTunes search + import
│  ├─ QueueView                   Programmed listening sequence
│  ├─ PlayerView / MiniPlayer     Full + docked playback UI
│  ├─ EpisodeDetailView           Spec sheet for an episode
│  ├─ Onboarding/                 POWER ON → genres → channels → import
│  └─ SettingsView                Tuning, taste profile, downloads
└─ Assets.xcassets/AppIcon...     Tuner VU dial icon
```

**SwiftData with versioned migrations** — see `SchemaMigration.swift`. Migrations are non-destructive; the persistent store survives schema bumps.

---

## Development

```bash
# Open the project (no SPM resolve needed — Xcode handles it)
open OffScript.xcodeproj
```

### Required tooling

- **Xcode 26+** (iOS 26.2+ simulator/device targets; project currently uses Swift 5 mode)
- **Ruby + xcodeproj gem** for the project-mutation scripts in `scripts/` (`gem install xcodeproj`)
- Optional: **Sentry account + DSN** — without it, Sentry init silently no-ops and dev builds work fine

### Configuring Sentry locally

```bash
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
# Edit Config/Secrets.xcconfig and paste your DSN
```

`Config/Secrets.xcconfig` is `.gitignore`d. Don't commit it. Xcode Cloud materializes its own copy from the `SENTRY_DSN` environment variable.

### Building locally

Standard Xcode build (`Cmd+B`). The `Sentry-Cocoa` SPM package resolves on first build (~5–10 s).

### Running tests

```bash
xcodebuild test -project OffScript.xcodeproj -scheme OffScript \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro'
```

For the full automated/simulator/real-device coverage map plus launch
argument reference, see [`docs/TEST_MATRIX.md`](docs/TEST_MATRIX.md).

---

## Shipping

We ship via **Xcode Cloud → App Store Connect → TestFlight**. Push to `main` or create a `v*` tag/release and Xcode Cloud archives, signs, and uploads with Apple-managed signing.

```bash
# Inspect or manually trigger the Xcode Cloud workflow via the repo tooling
scripts/app_store_connect.py xcode-cloud probe
scripts/app_store_connect.py xcode-cloud start-build <workflow-uuid>
```

The active GitHub workflow is [`.github/workflows/xcode-cloud-probe.yml`](.github/workflows/xcode-cloud-probe.yml), an on-demand operations wrapper for App Store Connect/Xcode Cloud checks. The old GitHub Actions TestFlight flow remains at [`.github/workflows/testflight.yml.disabled`](.github/workflows/testflight.yml.disabled) only as a fallback reference.

Required App Store Connect credentials for local/probe tooling:

| Secret | Purpose |
|--------|---------|
| `ASC_KEY_ID` | App Store Connect API key id |
| `ASC_ISSUER_ID` | ASC issuer UUID |
| `ASC_KEY_PATH` or `ASC_KEY_P8_BASE64` | `.p8` private key path or base64-encoded contents |
| `SENTRY_DSN` *(optional)* | Sentry project DSN — when absent, Sentry is disabled in the resulting build |

Build numbers must be greater than the latest App Store Connect build before an upload; bump `CURRENT_PROJECT_VERSION` when preparing a candidate unless Xcode Cloud is configured to override it.

---

## Design

The current shipped Tuner direction is documented in [`CLAUDE.md`](CLAUDE.md). Per-component design tokens live in [`OffScript/AppTheme.swift`](OffScript/AppTheme.swift) — palette, typography, `TunerLabel`, `TunerTag`, artwork, surface, and readout primitives. [`DESIGN.md`](DESIGN.md) is aspirational vNext design context and should not override the Tuner OLED implementation bible.

---

## Telemetry

- **Sentry** captures errors (`.error` and `.fatal` only) + 5% of perf transactions. Screenshots and view hierarchies are off (privacy: episode titles + queue contents are user-identifying). Release tagged as `MARKETING_VERSION-CFBundleVersion`. Environment auto-detected: `debug` / `testflight` / `production`.
- **MetricKit** subscribes via `MetricKitReporter`. Daily metric payloads land in OSLog (`Console.app`); crash diagnostics get forwarded into Sentry as `.fatal` events with the MetricKit payload as context. Sentry dedupes on stack signature, so already-reported crashes coalesce.
- **No third-party analytics.** No GA, no Mixpanel, no Segment, no AppsFlyer.

---

## License

Proprietary — not yet open source. See the [LICENSE](LICENSE) file for the current terms (UNLICENSED).

---

## Contributing

OffScript is currently maintained by [@zachyzissou](https://github.com/zachyzissou) with help from various Claude agents. External contributions aren't being accepted yet, but bug reports and feature ideas are welcome via [GitHub Issues](https://github.com/zachyzissou/offscript/issues).

If you're a TestFlight tester and you hit a crash, the report is already in Sentry — you don't have to do anything. Optional: write a short note in an issue with what you were doing right before the crash, which makes triage 10× faster.

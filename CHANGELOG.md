# Changelog

All notable changes to OffScript. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html) — though TestFlight builds carry a `YYYYMMDD<run>.<attempt>` build number layered on top of the marketing version.

## [Unreleased]

## [2.2.0] — 2026-04-27

### Added
- **Apple Intelligence pre-listen briefing.** `EpisodeBriefingView` generates a 3-bullet "what you'll learn" + one-line hook on-device via `FoundationModels` `@Generable`. Hidden silently on devices without Apple Intelligence. Cached per episode ID.
- **On-device Translation** for non-English episodes via Apple's `Translation` framework. Source language detected with `NLLanguageRecognizer`. Hidden when source matches user locale.
- **On-device Speech transcription.** `SpeechTranscriptionService` + `SpeechTranscriptionPanel` use Apple's `Speech` framework with `requiresOnDeviceRecognition=true` — audio never leaves the phone. Persisted via new `EpisodeTranscriptCache` SwiftData model so transcripts survive restart.
- **`SpeechAnalyzerService` scaffold** for iOS 26+ streaming transcription with progress callback. Falls through to `SFSpeechRecognizer` until the iOS 26 SDK lands.
- **Background opportunistic transcription.** `BackgroundTranscriptionService` runs after a successful download when on Wi-Fi + power. Bounded fetch (25 newest), one episode at a time, skips > 90 min and already-transcribed.
- **Siri / Shortcuts via App Intents.** `OffScriptAppIntents` ships ResumeListening / Pause / SkipForward / PlayNextInQueue. "Hey Siri, resume OffScript" works without unlocking.
- **Spotlight donations.** `SpotlightIndexer` donates up to 500 newest subscribed episodes to CoreSpotlight in batches. iOS system search and Siri Suggestions surface OffScript episodes. 24h debounce, 30-day item TTL.
- **Now Playing widget** (Lock + Home + Watch surfaces) — five families: systemSmall, systemMedium, accessoryCircular, accessoryRectangular, accessoryInline. Tap deep-links into the player.
- **Live Activity / Dynamic Island** for now-playing — compact / expanded / minimal layouts + Lock Screen banner. Updated by `NowPlayingPublisher` from main app via `ActivityKit`.
- **Deep links.** `offscript://` URL scheme registered. `DeepLinkRouter` handles `offscript://player`, `/episode/<uuid>`, `/episode/<uuid>/play`, `/podcast/<uuid>`. Wired via `.onOpenURL` + `.onContinueUserActivity(CSSearchableItemActionType)` for Spotlight result taps.
- **`PlaybackController.load(_:in:)`** — load an episode without auto-starting playback (used by the no-autoplay deep-link path).
- **AI-driven WHY copy generator** (`RecommendationExplainer`) — full generation + lightweight rephrase via `FoundationModels`. Service ready; rail-card swap-in deferred to a follow-up.

### Changed
- **TestFlight workflow now release-driven.** Cutting a GitHub Release with a `vX.Y.Z` tag triggers a TestFlight build that uses the release tag as `MARKETING_VERSION` and the release body as the TestFlight What-To-Test notes. Push-to-main still works (auto-cuts a prerelease GitHub Release tagged `testflight-X.Y.Z-build.N` after a successful TestFlight ship).
- New `OffScriptWidgets` app-extension target wired via `scripts/add_widget_extension.rb` (idempotent xcodeproj-gem setup).
- App Group `group.com.offscript.app` shared between main app and widget extension via entitlements.
- `EpisodeTranscriptCache` `@Model` added to `SchemaV1.models` (additive lightweight migration — existing data persists).

### Infrastructure
- `Info.plist` additions: `NSSpeechRecognitionUsageDescription`, `NSSupportsLiveActivities`, `NSSupportsLiveActivitiesFrequentUpdates`, `CFBundleURLTypes` for `offscript://`.
- `OffScript.entitlements` adds `com.apple.security.application-groups`.
- `permissions: contents: write` on TestFlight workflow so it can cut releases + push tags.

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

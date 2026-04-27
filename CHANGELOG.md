# Changelog

All notable changes to OffScript. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html) — though TestFlight builds carry a `YYYYMMDD<run>.<attempt>` build number layered on top of the marketing version.

## [Unreleased]

## [2.3.5] — 2026-04-27

### Fixed — Sign in with Apple (was silently broken)
- **Missing entitlement.** `OffScript.entitlements` had no `com.apple.developer.applesignin` capability. Without it, every `ASAuthorizationController.performRequests()` call failed at the system level — but the failure callback wasn't logged, so the symptom was just "the button does nothing." Added `Default` scope so the app can request user identity at sign-in time.
- **Missing `presentationContextProvider`.** iOS 26 has multiple connected scenes, and `ASAuthorizationController` will refuse to present its sheet without an explicit window anchor. The Coordinator now conforms to `ASAuthorizationControllerPresentationContextProviding` and returns the foreground-active key window — falls back to the first active scene's window, finally to a fresh `UIWindow()`, so it's never nil.
- **Controller release race.** The local `ASAuthorizationController` lived only in `handleSignIn()`'s scope, which meant ARC could free it before the delegate callback fired (Apple's API expects the caller to hold a strong reference until completion). The Coordinator now keeps an `inFlightController` reference, cleared on success or error.
- **Silent error handling.** The `didCompleteWithError` callback used to just call `onComplete()` and swallow the error. Now logs via OSLog so the actual reason surfaces in Console.

### Fixed — OPML import was unbearably slow
- **Sequential → 6-way bounded parallelism.** Previously, each OPML row resolved + imported in series; a 50-podcast OPML easily took multiple minutes because most of that wall time was idle waiting on per-feed network round-trips. `batchImportOPML` now runs 6 imports concurrently via `withTaskGroup`, priming the pump and keeping the pipeline full as each completes. ~6× faster end-to-end on typical OPML sizes.
- **Episode limit on initial sync.** OPML imports were pulling the entire back catalog for every feed (some podcasts have 500+ episodes). Now passes `episodeLimit: 25` so each show lands fast with recent episodes — background refresh fills in older episodes later. Cuts per-feed time from seconds to ~half a second on most feeds.

### Changed
- Sign-in with Apple button radius dropped from 18 → 0 to align with the Tuner sharp-rectangle vocabulary. Style is otherwise stock Apple, since their button design isn't ours to override.

## [2.3.4] — 2026-04-27

### Added — PlayerView depth pass
- **Chapters in PlayerView.** The model already parsed PSC chapter tags + summary timestamp patterns via `EpisodeChapterParser` for months — the data was on the model graph and just never rendered. Now there's a "CHAPTERS · TAP TO SEEK" section between the transport row and Up Next that:
  - Lists every chapter with `01·02·03` rank prefixes, mono start times, and the chapter title
  - Highlights the current chapter in signal-yellow with a `▶` glyph (recomputed against `player.currentTime`, so it tracks live as playback crosses each marker)
  - Tap-to-seek — tapping any row jumps playback to that chapter's start time
  - Self-hides when the episode has no chapters, no empty state churn
- **Sleep timer.** SLEEP key in the Player controls row, with the standard podcast app intervals (5 / 15 / 30 / 45 / 60 min). Active timer shows live `mm:ss` countdown directly on the key in signal-yellow; tapping reveals the Cancel option. Implementation in `PlaybackController.setSleepTimer(minutes:)` / `cancelSleepTimer()` — `Task.sleep` based, cancelled cleanly on deinit and on rescheduling.
- **Per-podcast playback rate.** Speed menu now sets the rate per podcast — pick 1.5× for a fast-talker, 1.0× for narrative, and OffScript remembers each choice. The SPEED key on the Player turns signal-yellow when the current podcast has a custom pace so you can see at a glance you're not on the default. Storage is `UserDefaults`-keyed by podcast UUID via `PodcastPlaybackPreferences` — no SwiftData migration for what's a UI preference, not a content fact. Rate menu expanded to 1.0× / 1.1× / 1.25× / 1.5× / 1.75× / 2.0× / 2.5× to match what every other podcast app offers.

### Added — MiniPlayer transport
- **Skip-back-15 and skip-forward-30 keys** flanking the play key in the MiniPlayer. Same icons (`gobackward.15`, `goforward.30`) and skip amounts as the lock-screen / CarPlay remote commands so the muscle memory transfers. The most-frequent in-app interactions (rewind a phrase, skip an ad) no longer require opening the full player. Hidden when there's no real duration so they don't sit dead on a fresh load.

### Fixed
- **PlayerView artwork block** was using `TunerTag` with `offscriptFnRecord` (record red) for the podcast title — same bug class as the QueueLeadStrip fix in 2.3.2. Switched to `TunerLabel` in `offscriptFnInfo` (cyan), matching every other place a podcast title is shown.

## [2.3.3] — 2026-04-27

### Added — import functionality
- **Paste-URL import.** Library header has a new Import key (`square.and.arrow.down`, next to the settings cog). Pasting a podcast feed URL fetches the feed once, parses title + author + artwork + summary, and lands the show in the library indistinguishably from a search-tap import. Tolerates URLs without a scheme (auto-prefixes `https://`), tolerates `feed://` URLs, rejects obvious non-URLs (search terms, single words). All errors surface inline in the import sheet with the actual reason — no silent failures.
- **OPML import.** Same Import key opens the file picker for OPML files exported from Apple Podcasts, Pocket Casts, Overcast, AntennaPod, and gPodder. Parser is forgiving across the slight format variations between exporters (xmlUrl casing, text vs. title attribute, missing type=rss). Preview screen shows every feed found in the file with `01·02·03` rank prefixes. "→ IMPORT ALL" runs them sequentially with per-row status (`○ STANDBY / ● IMPORTING / ✓ ADDED / ✕ FAILED`) — one bad feed doesn't fail the whole batch.
- **`PodcastImportService`** — single source of truth for "raw URL or OPML entry → `PodcastSearchResult`" resolution. URL paste, OPML, and the existing search-tap path all converge on `FeedSyncService.importPodcast(...)` so subscribed-state, sync, and library-display behavior is identical across all three.
- **`LibraryImportSheet`** — Tuner-styled sheet with a three-mode state machine (menu → paste URL or OPML preview). Hairline-rule sections, mono status badges, function-coded colors, sharp-rectangle keys throughout — same vocabulary as every other Tuner surface.

### Why this was missing
Until now, the only way to add a podcast was to type the title into Search and hope iTunes had it indexed. No feed-URL paste, no OPML, no migration path from another podcast app. That's the highest-friction gap in the app for anyone arriving from Overcast / Pocket Casts / Apple Podcasts.

## [2.3.2] — 2026-04-27

### Fixed — playback (root-cause fix for two reported bugs)
- **Audio now keeps playing when the app is backgrounded.** Root cause: `Info.plist` was missing `UIBackgroundModes → audio`. Without that key, the `setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)` call threw at session-configure time — the bare `try?` swallowed the throw — and iOS fell back to the default `.soloAmbient` category, which suspends in background. Adding the entitlement makes the call succeed, the session sticks at `.playback`, and audio survives backgrounding.
- **Audio now plays through the silent / ring-mute switch.** Same root cause — `.soloAmbient` respects the silent switch by spec; `.playback` does not. Fixing the Info.plist key fixes both reported symptoms with one change.
- **Phone calls / Siri no longer kill playback permanently.** Added `AVAudioSession.interruptionNotification` handling — pause on `began`, resume on `ended` if the system signals `shouldResume`. Was missing entirely; an interrupted episode would never resume even after the call ended.
- **Headphone / Bluetooth unplug correctly pauses** instead of blasting through the speaker. Added `AVAudioSession.routeChangeNotification` handling for `oldDeviceUnavailable`.
- **Media-services reset recovery.** Added `mediaServicesWereResetNotification` handler that re-runs `configureAudioSession()` and resumes if we were playing. Rare but real — if iOS resets media services while in background, the session needs to be recreated from scratch.
- **Lock-screen / CarPlay / Control Center play command** now re-activates the audio session before resuming, matching the in-app `togglePlayPause()` path. Was missing — remote-command resume could fail silently if the session had been deactivated by another app.

### Changed — Tuner sharp-rectangle vocabulary, end-to-end
- **`TunerTag` was secretly using `Capsule()` for its outline.** That meant every reason badge across the app — hero card "PICK UP WHERE YOU STOPPED", lead-card explanation chips, AI reason tags, queue-lead podcast title — was rendered as a rounded pill, violating the Tuner sharp-rectangle rule. Swapped to `Rectangle()`. One-line fix surfaces consistently everywhere `TunerTag` is used.
- **`EpisodeDetailView` "QUEUE" / "QUEUED" button** outline was the last `Capsule().stroke` left in the screen-level UI. Swapped to `Rectangle().stroke`.
- **`QueueLeadStrip` podcast title color**: was rendering in `offscriptFnRecord` (record red), which is the function-coded color reserved for destructive / error signals (× CLEAR ALL, × REMOVE). Switched to `offscriptFnInfo` (cyan), matching every other place a podcast title is shown — and switched from `TunerTag` to a `TunerLabel` since the rectangle chrome was redundant.

### Removed — dead `AppTheme.swift` primitives left over from the editorial direction
- `PrimaryPillButtonStyle` / `SecondaryPillButtonStyle` — the old orange-pill Resume button and glass-pill Queue button. All call sites migrated to inline Tuner sharp-rectangle keys.
- `SkeletonRailCard` / `SkeletonHeroCard` / `SkeletonSearchRow` — pre-Tuner shimmer skeletons with rounded fills + capsule chips. Tuner rails render hairline-rectangle placeholders inline; nothing referenced them.
- `GrainOverlay` / `offscriptGrain` extension + the `SplitMix64` PRNG it used — the editorial-paper grain texture from the warm-amber direction. Tuner is flat OLED black; no grain belongs.

### Net effect
- Two reported playback bugs fixed by a one-key Info.plist correction (the actual fix) plus four AVAudioSession-level handlers that should have always been there (the production-readiness fix).
- Zero remaining `Capsule()` / rounded chrome in the Tuner UI vocabulary. Sharp rectangles everywhere.
- ~150 lines of dead code removed from `AppTheme.swift`.

## [2.3.1] — 2026-04-27

### Changed — Tuner finishing pass
- **`ImportProgressView`** (onboarding step 03) ported to Tuner spec sheet vocabulary. Was the last screen still using centered-loading editorial layout with big spinner + checkmark. Now uses the `03 · TUNING` eyebrow + `● TUNING N/M` status badge + `Tuning channels…` headline + hairline-divided per-channel rows with `01·02·03` rank prefixes and mono `○ STANDBY / ● TUNING / ✓ TUNED / ✕ FAILED` status labels. Function-coded colors line up with the rest of the app.
- **`DownloadButton`** ported. Was the last `SecondaryPillButtonStyle` (rounded capsule) in the codebase. Now sharp hairline rectangle with mono status text and function-coded color (signal-yellow for actionable / mode-green when downloaded / record-red on failure).
- **In-line Tuner progress rails** in `EpisodeDetailView` + `CardComponents.EpisodeVerticalCard` (replaces removed `OffScriptProgressBar`).

### Removed — dead code in `AppTheme.swift`
12 view structs that had no callers after the Tuner port — keeping them around made the design system look like two vocabularies were still in active use:
- 7 legacy editorial-direction views: `OffScriptReasonBadge`, `OffScriptExplanationTag`, `OffScriptEmptyState`, `OffScriptSectionHeader`, `OffScriptUtilityHeader`, `OffScriptProgressBar`, `OffScriptScrubber`.
- 5 unused Tuner primitives: `TunerRingMeter`, `TunerTrace`, `TunerTransportButton`, `TunerModeToggle`, `TunerArtworkTile`. Designed for the spec but never composed into actual screens — Player built its own transport row, scrubber went native `Slider`, rail cards use sharp `OffScriptArtworkView` tiles, filter chips landed as inline Tuner buttons.

### Changed — design bible
`CLAUDE.md` rewritten. Was still describing the old warm-amber editorial direction (Playfair Display, gradient cards, 12/24/32pt radii) — completely stale relative to what shipped. Now documents the Tuner OLED instrument-cluster direction, the iOS 26 chrome trap (don't use `TabView`/`.toolbar`/`.searchable`), the spec-sheet skeleton every screen follows, the component cheat sheet (`TunerLabel`, `TunerTag`, inline Tuner action buttons), and the operational tooling (Xcode Cloud + simctl audit pattern).

## [2.3.0] — 2026-04-27

### Changed
- **Full Tuner OLED port across the rest of the app.** The 2.0 design landing only touched `EpisodeDetailView` + design tokens; `HomeView`, `LibraryView`, `QueueView`, `SearchView`, `SettingsView`, `MiniPlayer`, and `PlayerView` still rendered with the old editorial vocabulary (rounded gradient cards, `OffScriptSectionHeader`, `OffScriptUtilityHeader`, `OffScriptExplanationTag`, `HeroRecommendationCard`). They had the new colors but the old layout — that's the "UI not fully implemented" feeling. Every top-level surface now uses the spec-sheet vocabulary: `TunerLabel` eyebrows, hairline-rule section dividers, mono channel readouts, sharp 3pt artwork tiles with hairline borders, no surface modifiers, sharp-cornered Tuner action buttons.
  - `MiniPlayer` — flat-black strip with single-pixel signal-yellow progress rail, 44pt-tap signal-yellow square play key, mono `● PLAYING` / `❙❙ PAUSED` status badges
  - `HomeView` — `HomeTunerHeader` with TODAY · DAY DATE eyebrow, `HeroTunerCard` with Tuner action keys (`→ PLAY` / `+ QUEUE`), `TunerRail` / `TunerRailCard` with mono channel readouts
  - `PlayerView` — full spec sheet (PLAYER · NOW PLAYING header, POS / REM mono readouts, signal-yellow tick rule scrubber, 4-key transport row with hairline buttons, UP NEXT + WHAT'S NEXT + CONTROLS sections all hairline-divided)
  - `LibraryView` — channel directory layout, `01·02·03` numbered channel rows, mono stat readouts (SHOWS · UNPLAYED · IN PROGRESS), Tuner episode rails
  - `PodcastDetailView` — channel detail spec sheet with `001·002·003` episode numbering, mono metadata, Tuner action buttons
  - `QueueView` — working-set spec sheet, `02 RANK ARTWORK TITLE` row layout, `× CLEAR ALL` action, NEXT UP lead strip
  - `SearchView` — signal scan layout with starter-topic mode toggles, hairline-divided result rows numbered `01·02·03`
  - `SettingsView` — config panel with stat readouts, Tuner toggles, hairline-divided sections (PLAYBACK / ICLOUD SYNC / ABOUT)
- **3 Apple AI cards refactored** to spec-sheet vocabulary on `EpisodeDetailView`. They were rounded panel cards stuck inside an otherwise-Tuner screen — `TunerLabel` eyebrow + hairline rule + content, no surface wrapper, mono numbered bullets in the briefing, function-coded status badges (`● REC` / `● READY` / `● ERROR`).

### Notes
- All sections now use the same vocabulary defined by the existing `TunerLabel`, `TunerTag`, and surface conventions in `AppTheme.swift`. No new design primitives were added — this is purely catching the rest of the app up to the language `EpisodeDetailView` was already speaking.

## [2.2.3] — 2026-04-27

### Added
- **Now Playing widget** restored — five families: systemSmall, systemMedium, accessoryCircular, accessoryRectangular, accessoryInline. Tap deep-links into the player.
- **Live Activity / Dynamic Island** restored — compact / expanded / minimal layouts + Lock Screen banner.
- `OffScriptWidgets` app-extension target back in the project (re-added via `scripts/add_widget_extension.rb`).
- App Group `group.com.offscript.shared` registered in Apple Developer Portal and bound to `com.offscript.app` + `com.offscript.app.widgets`. Both targets' entitlements + `NowPlayingStorage.suiteName` reference it.

### Notes
- Original identifier `group.com.offscript.app` was unavailable globally, swapped to `group.com.offscript.shared`. Source updated in lockstep across 5 files in [`8568b61`](https://github.com/zachyzissou/offscript/commit/8568b61).
- This is the first ship through the new Xcode Cloud pipeline that includes both an app and an app-extension target with shared App Group state. Apple-managed signing handles both bundle IDs automatically.

## [2.2.2] — 2026-04-27

### Changed
- **CI pivoted from GitHub Actions to Xcode Cloud.** Apple-managed signing certs (no per-account cap), automatic provisioning profile generation, native TestFlight upload action. The previous `.github/workflows/testflight.yml` was fighting Apple's signing infrastructure — now `.disabled`, kept as fallback.
- New `scripts/app_store_connect.py` subcommands for fully-automated Xcode Cloud ops: `xcode-cloud probe`, `inspect`, `reconfigure`, `start-build`, `build-run`. Created/PATCHed via the App Store Connect API — no clicking through web UIs required.
- `.github/workflows/xcode-cloud-probe.yml` — on-demand workflow for probe/inspect/reconfigure/start-build/build-run, runnable from Actions tab without local creds.
- `ci_scripts/ci_post_clone.sh` — Xcode Cloud post-clone hook that materializes `Config/Secrets.xcconfig` from the `SENTRY_DSN` env var.
- `CONTRIBUTING.md` "Releasing" section rewritten — two trigger paths (push to main / cut `vX.Y.Z` GitHub Release), operational tooling reference, "Why we left GH Actions behind" footnote.

### Fixed
- `.claude/worktrees/hardcore-villani` was indexed as a stale 160000 (gitlink) entry, producing `GitCloneStep` warnings on every Xcode Cloud build. Removed via `git rm --cached`.
- App Group entitlement (`group.com.offscript.app`) on the host app was breaking the ExportArchive step because the App Group itself wasn't registered in App Store Connect. Removed pending widget extension re-add.

## [2.2.1] — 2026-04-27

### Fixed
- **TestFlight signing failure** introduced in 2.2.0. The new `OffScriptWidgets` app-extension target needs `com.offscript.app.widgets` registered in App Store Connect with the App Groups capability + a provisioning profile that includes `group.com.offscript.app` before CI can sign it. Stripped the target via `scripts/remove_widget_extension.rb` so the host app + Apple AI features ship cleanly. The Swift sources stay in `OffScriptWidgets/` for the follow-up.
- Apple Developer cert limit (3 iOS distribution certs / account) was also being hit by the auto-create flow for the new bundle ID. Revoke an unused cert in the developer portal before re-adding the widget target.

### Deferred
- Now Playing widget + Live Activity / Dynamic Island. Re-add by:
  1. Register App ID `com.offscript.app.widgets` in [Apple Developer Portal](https://developer.apple.com/account/resources/identifiers/list) with App Groups capability enabled.
  2. Add `group.com.offscript.app` under App Groups; assign it to both bundle IDs.
  3. Revoke an unused iOS distribution cert if at the 3-cert limit.
  4. Run `scripts/add_widget_extension.rb` to put the target back, push, watch CI ship.

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

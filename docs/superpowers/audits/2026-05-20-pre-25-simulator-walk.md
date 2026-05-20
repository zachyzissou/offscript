# Pre-2.5.0 simulator walk — 2026-05-20

End-to-end simulator audit pre-flighting the 2.5.0 release (PR #275).
Scope: clean build, full unit + targeted UI suite, screenshot walk of
every major surface, design-system + a11y inspection, declaration
spot-checks (CarPlay, BGTask, privacy, Wi-Fi-only).

## Build state

- **Branch:** `audit/expanded-surface-2026-05-19` at `c1668550893924ff796d63b8e115ba4ac6c603c3`
- **Toolchain:** Xcode 26.5
- **Sim:** iPhone 17 Pro · iOS 26.5 (UDID `F623EB2A-1CF4-405E-9583-6B0EE2053FDE`)
- **Build:** `** BUILD SUCCEEDED **` with 3 warnings (no errors):
  - `SearchPreviewLoader.swift:111:17` and `:114:17` — "no 'async' operations occur within 'await' expression" (idempotent `await` on synchronous calls — low-priority cleanup)
  - `NotificationService.swift:126:63` — "capture of 'episode' with non-Sendable type 'Episode' in a '@Sendable' closure" (Phase 37 push scaffolding — needs `@MainActor` or a Sendable transport struct before push notifications go live; not exercised in production paths today)
- **Unit tests (`OffScriptTests`):** 236 individual `✔ Test passed` lines / 5 crash-killed (same SwiftData singleton-pollution class — see `TEST_MATRIX.md` lines 193-220). All five pass in isolation. Suites: TasteProfileDecay 9/9, CuratedDiscovery, PlaybackEventEmission, CuratedDiscoveryFilter, DebugInspector, TranscriptDecoder, OpenAppIntents, LiveActivityLifecycle all `passed`. Process-level "Failing tests:" footer is the way Swift Testing surfaces crashes from prior tests poisoning singletons.
- **UI tests (12 Phase-5 + recent additions, parallel):** **11 passed / 1 failed.**
  - **Failure:** `OffScriptUITests/testLargeLibraryDirectoryControlsStayResponsive` (`OffScriptUITests.swift:357: XCTAssertTrue failed - ATTN sort did not appear`). Reproducible in isolation. Classified as a **non-shipping test-only regression** introduced by commit `39a49e5` (`fix(a11y): dimension-aware chip labels`) which overrode the chip's accessibility label from "ATTN" to "Sort: needs attention first". The test was not updated. Visible UI is correct; user-facing behavior is unchanged. See **Functional findings** below.

## Screenshot inventory

11 captures in `docs/superpowers/audits/2026-05-20-pre-25-simulator-walk/`:

| File | State |
|---|---|
| `home-empty.png` | Home / wiped library — curated channel bootstrap copy ("Pick a few well-loved channels") |
| `home-seeded.png` | Home / 3 seeded shows — HEADLINE card + RESUME THREAD rail |
| `home-with-miniplayer.png` | Home seeded + boot playback — MiniPlayer docked above tab bar; QUEUE badge "2" |
| `library-empty.png` | Library / wiped — "Your library is empty" + → FIND SHOWS CTA + IMPORT/SYNC/TUNE row |
| `library-seeded.png` | Library / 3 seeded shows — directory controls + Phase 41 outline chips |
| `library-258.png` | Library / 258-show seed — 258 SHOWS / 774 UNPLAYED / 52 IN PROGRESS counts; controls responsive |
| `queue-empty.png` | Queue / empty — "Nothing queued yet" + working-set copy + → EXPLORE SHOWS CTA |
| `queue-seeded.png` | Queue / 5 stacked — NEXT UP card + 4 visible queue rows |
| `search-default.png` | Search / default — Tuner search field + STARTER TOPICS grid |
| `player-presented.png` | Player sheet — full spec sheet (transport / UP NEXT / CONTROLS) |
| `onboarding-1.png` | Onboarding screen 1 — OFF SCRIPT. brand + 4 commitments + Sign in / POWER ON |

## Design-system findings

### BLOCKERS

None. Every captured surface honors the design system: pure-black field, sharp corners, hairline borders, signal-yellow as the only accent for active state, function-coded chips (RADIOLAB cyan info, × DROP red destructive, ● PLAYING mode green). No `.buttonStyle(.plain)` chrome leaks. No floating Liquid Glass capsules.

### POLISH

| Item | Surface | Severity | Notes |
|---|---|---|---|
| Tab bar QUEUE badge "2"/"5" pill | `home-with-miniplayer.png`, `queue-seeded.png` | POLISH | The auto-generated TabView-style yellow rounded pill clashes with the otherwise sharp-corner Tuner system. The TabView replacement (`TunerTabBar`) already takes responsibility for the tab chrome; the badge needs a hairline-rectangle render for full design-system conformance. Pre-existing; unchanged by 2.5.0 work. |
| Queue row episode title wraps mid-word | `queue-seeded.png` | POLISH | Title column reads "Radiol / ab — …" because the column is sandwiched between channel artwork + 5 action keys (▶ ▲ ▼ ×). Two-line truncation works but the line break lands inside the word "Radiolab" because there's no `.truncationMode(.tail)` cap. Phase 41 polish landed the row hierarchy but the column-width tightness is post-merge visible. Suggest `.lineLimit(2)` + `.truncationMode(.tail)` on the row title in `QueueView`. |
| Onboarding `OFF / SCRIPT.` line break | `onboarding-1.png` | POLISH | The display title splits "OFF / SCRIPT." across two lines on the iPhone 17 Pro safe-area width. Intentional? Possibly. Reads visually as `OFF / SCRIPT.` with the yellow `.` on line 2, which is a strong brand stamp. Not a regression — pre-existing — and arguably part of the brand mark. Listing for future review; not blocking 2.5.0. |

### NEW-AREA observations

| Item | Surface | Notes |
|---|---|---|
| Phase 41 outline-only chip treatment | `library-seeded.png`, `library-258.png` | Renders correctly. Selected `ALL` and `A-Z` chips show signal-yellow stroke + signal-yellow glyph, unselected use hairline stroke + paper-white glyph. The 2026-05-20 design audit drift (solid-fill selected chip) is resolved. |
| Phase 22 download chip on Library rows | `library-seeded.png`, `library-258.png` | Not currently exercised in screenshots because no downloads in flight. Source confirms `LibraryView.swift:2902-2925` ships the `● DOWNLOADING / ✓ DOWNLOADED / ● FAILED` chip vocabulary. Real-device validation needed. |
| Curated-bootstrap empty state | `home-empty.png` | Phase 17 curated discovery surfaces correctly when library is wiped — shows NEWS & CULTURE + TECH & DESIGN starter rails with `+ ADD` keys. The empty state is *useful*, not blank — strong onboarding flow recovery. |

## Functional findings

| Flow | Result |
|---|---|
| CarPlay entitlement | `com.apple.developer.carplay-audio` present in `OffScript.entitlements`. `UIApplicationSceneManifest` maps `CPTemplateApplicationSceneSessionRoleAudio` → `CarPlaySceneDelegate` (Phase 16/28). Real-device validation gated by Apple-issued CarPlay entitlement; not exercisable in simulator. |
| BGTask registration | `BGTaskSchedulerPermittedIdentifiers` declares `com.offscript.feed-refresh` + `com.offscript.background-transcription` in Info.plist (Phase 24). `UIBackgroundModes = "audio fetch processing"` set via `INFOPLIST_KEY_UIBackgroundModes` in pbxproj. Real-device validation required for actual BGAppRefreshTask + BGProcessingTask dispatch. |
| Privacy manifest | `PrivacyInfo.xcprivacy`: `NSPrivacyTracking false`, `NSPrivacyTrackingDomains` empty, `NSPrivacyCollectedDataTypes` empty (consistent with no-cloud claim), `NSPrivacyAccessedAPITypes` declares UserDefaults (CA92.1) + FileTimestamp (C617.1). Widget extension carries its own manifest. Looks ready for submission. |
| Wi-Fi-only downloads toggle | `SettingsView.swift:445` ships the row with proper Tuner styling — DOWNLOADS · WI-FI ONLY label + ON/OFF chip + dedicated voice-over label "Download only on Wi-Fi. Currently <on\|off>." (Phase 27). `DownloadService.swift:104` enforces in code. Real-device validation required for actual cellular gate. |
| Debug Inspector accessibility | Wired into Settings sheet via `isDebugInspectorPresented` State + `DebugInspectorView()` (Phase 27). UI test `testSettingsPanelOpensWithLargeLibrarySeed` validates the Settings entry from Library. Visual auto-capture of Debug Inspector + Settings panel itself was not achievable through `simctl io` alone — see "Auto-capture limitations" below. |
| New Phase 40 AppIntents | `OffScriptTests` suite "OpenAppIntents" reports all 4 intents (`OpenLibrary`/`OpenQueue`/`OpenSearch`/`OpenHome`) pass: title+dialog, URL routing, AppShortcutsProvider lists all four, no-parameter contract. |
| Phase 39 LiveActivity end-on-episode-change | Suite `LiveActivityLifecycleTests` passes both tests: `endCurrentIsSafeWhenNoActivitiesPresent` + `switchingEpisodesDoesNotCrashPublisherSubscription`. Real-device validation required to see the Dynamic Island artwork actually flip rather than orphan. |
| `testLargeLibraryDirectoryControlsStayResponsive` ATTN failure | **Root cause:** the test queries `app.buttons["ATTN"]` but the chip's `.accessibilityLabel` was overridden to `"Sort: needs attention first"` in commit `39a49e5` to give VoiceOver dimension context. The test was not updated. **User-facing impact: zero** — the visible label is still `ATTN`, only the spoken VoiceOver string changed. Fix is one line: change the test query to `app.buttons["Sort: needs attention first"]` (or add `.accessibilityIdentifier("LibrarySortATTN")` as a stable test handle). Documented as test-only blocker — do not block 2.5.0 ship on this. |

## Auto-capture limitations

The following surfaces require real-device or hand-driven simulator validation. `xcrun simctl io screenshot` and `xcrun simctl launch` get to a screen via launch args, but tap-driven flows that need `XCUIElement.tap()` can only be exercised inside an XCUITest target. AppleScript-driven `cliclick` / `osascript` taps into the simulator window aren't reliable (the window's point/pixel scaling differs across runs).

Not captured this run; requires manual entry on real device or via an XCUITest screenshotter:
- Settings panel visual (verified open via existing `testSettingsPanelOpensWithLargeLibrarySeed`; visual not auto-captured)
- Debug Inspector visual (verified wired in source `SettingsView.swift:104`)
- Player Sleep Timer sheet
- Episode detail sheet
- Podcast detail screen with episode list
- Transcript view + synchronized line highlighting (Phase 30)
- Live Activity rendering on Dynamic Island (simulator does not render it faithfully)
- CarPlay screens (entitlement-gated, simulator's CarPlay sim has known fidelity gaps)
- AirPods route / hardware media keys / silent switch (real device only)
- Push notification arrival (real device + APNs)

## Known carry-forward issues from PR #275

- 4 `PlaybackEventEmissionTests` + the 1 `TasteProfileDecayTests.decayHalfLifeIs14Days` get killed mid-run by the SwiftData/singleton-pollution flake class. All pass in isolation. Documented in `docs/TEST_MATRIX.md` lines 193-220. Phase 26 hardened the known offenders; `TasteProfileDecayTests` is a new sibling of the same class — adding `DebugTeardown.resetAllSingletons()` in the suite's setUp would clear it.
- 1 build warning in `NotificationService.swift:126` (Phase 37 push scaffolding) — non-Sendable `Episode` captured in a `@Sendable` closure. Push notifications are scaffolded but not yet wired to APNs; needs resolution before push goes live.
- The CHANGELOG/release notes for 2.5.0 should call out: Phase 16 CarPlay scaffolding is in but **not user-visible** without Apple's CarPlay entitlement approval; Phase 24 BGTask, Phase 27 Wi-Fi-only, Phase 39 LiveActivity-end-on-change, Phase 40 AppIntents are all in.

## GO / NO-GO recommendation

**GO** for 2.5.0 ship. The single non-passing UI test (`testLargeLibraryDirectoryControlsStayResponsive`) is a test-only failure caused by an a11y improvement that wasn't propagated to the test query string — the production UI works correctly. Ship 2.5.0, file a follow-up to update the test query and unblock the green run.

Strongly recommend the follow-up land within the 2.5.0 release window since the test-suite reds out on every CI run otherwise — but do not block this build on it.

## What still requires real-device validation

Per `docs/TEST_MATRIX.md` and `docs/AGENT_EXECUTION_RUNBOOK.md`, the simulator cannot honestly sign off on:

- Background playback while screen is locked
- Lock-screen artwork rendering + transport controls
- Silent-switch interaction during playback
- AirPods route change / pause-on-removal
- CarPlay screens (entitlement-gated)
- Now Playing widget rendering on Home Screen
- Live Activity rendering on Dynamic Island and lock screen
- Push notification arrival (Phase 37 scaffolding, not yet wired)
- Sign in with Apple end-to-end (real iCloud account required for full path)
- BGTask scheduler waking the app for feed refresh + background transcription
- Wi-Fi-only download enforcement on actual cellular link
- Speech Recognition framework actually downloading on-device model
- Real OPML import latency claims at the catalog scale users will hit

A separate real-device pass on iPhone 17 Pro before TestFlight wide-rollout is recommended — at minimum: background playback, silent switch, lock screen art, Sign in with Apple, iCloud sync state, Now Playing widget, Live Activity on Dynamic Island, Wi-Fi-only on cellular.

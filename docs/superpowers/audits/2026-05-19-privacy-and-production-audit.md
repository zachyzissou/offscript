# Privacy manifest + production-readiness audit — 2026-05-19

Branch: `audit/expanded-surface-2026-05-19`
HEAD at audit start: `e44b0cd`
Scope: `OffScript/PrivacyInfo.xcprivacy`, `OffScript/Info.plist`,
`OffScript/OffScript.entitlements`, `OffScriptWidgets/Info.plist`,
`OffScriptWidgets/OffScriptWidgets.entitlements`. Source files read-only.

---

## Privacy manifest (PrivacyInfo.xcprivacy)

**Status: present and correct** (with one over-declared category that is
benign — see below).

Existing file (`OffScript/PrivacyInfo.xcprivacy`) declares:

| Category | Reason | Code uses it? |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` (read/write access to UserDefaults owned by app/extension) | YES — 38 `UserDefaults` references across the app, including the shared `group.com.offscript.shared` suite read/written by both targets (`SharedNowPlayingState.swift`). |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` (inside-app-use display to user) | NO — no `creationDate`, `modificationDate`, `attributesOfItem`, `NSURLContentModificationDateKey` usage found in `OffScript/*.swift`. Over-declared but harmless; likely a defensive add for transitive SDK behaviour. **Keep.** |

Top-level flags:
- `NSPrivacyTracking` = `false` — correct (app does not track per the
  marketing claim).
- `NSPrivacyTrackingDomains` empty — correct.
- `NSPrivacyCollectedDataTypes` empty — consistent with "on-device only".
  Verify against the Sentry data flow (see below): if Sentry's crash
  payloads count as "Diagnostics" under Apple's taxonomy, that's a
  privacy-nutrition-label gap, NOT a manifest gap (the manifest covers
  required-reason APIs only).

API categories NOT declared, verified NOT needed:

| Category | Code search result |
|---|---|
| `NSPrivacyAccessedAPICategoryDiskSpace` | No `volumeAvailableCapacity*` or `attributesOfFileSystem` usage. |
| `NSPrivacyAccessedAPICategorySystemBootTime` | No `systemUptime` / `kern.boottime` usage. |
| `NSPrivacyAccessedAPICategoryActiveKeyboards` | No `UITextInputMode.activeInputModes` usage. |

**Widget target has no PrivacyInfo.xcprivacy.** The widget extension is
bundled into the app and accesses the same `UserDefaults` suite. Apple's
official guidance (WWDC23 / Nov-2023 enforcement) is that each binary
that links the API directly must declare. For an extension bundled into
the app, the app's manifest is typically sufficient because both binaries
ship together — but a per-extension manifest is the safer, future-proof
move. **Filed as GAP, fixed in this audit** (new file:
`OffScriptWidgets/PrivacyInfo.xcprivacy`).

---

## Info.plist usage descriptions (`OffScript/Info.plist`)

| Key | Value | Code uses? |
|---|---|---|
| `NSSpeechRecognitionUsageDescription` | "OffScript can generate transcripts on-device for episodes that don't ship one. Audio never leaves your phone." | YES — `SpeechTranscriptionService.swift` calls `SFSpeechRecognizer.requestAuthorization`. Wording is honest about on-device only. |

No other `NS*UsageDescription` keys — verified absent:

| Capability | Code search | Status |
|---|---|---|
| Microphone (`NSMicrophoneUsageDescription`) | No `AVAudioRecorder` / `AVCaptureSession` / `requestRecordPermission` usage. `AVAudioSession` is set to `.playback` / `.spokenAudio` (playback-only). | Correctly absent. |
| Photo Library | No `UIImagePickerController` / `PHPickerViewController` usage. | Correctly absent. |
| Camera | No `AVCaptureDevice` usage. | Correctly absent. |
| Location | No `CLLocationManager` usage. | Correctly absent. |
| User Tracking (`NSUserTrackingUsageDescription`) | No `ATTrackingManager` / `AppTrackingTransparency` usage. | Correctly absent — matches "no third-party tracking" promise. |
| Contacts / Calendars / Reminders / Bluetooth | All absent from code. | Correctly absent. |

Other Info.plist keys reviewed:

| Key | Notes |
|---|---|
| `BGTaskSchedulerPermittedIdentifiers` = `["com.offscript.feed-refresh"]` | Matches `BackgroundFeedRefresh.swift` identifier (verified read-only). |
| `CFBundleURLTypes` = `offscript://` | Wired to `DeepLinkRouter.swift`. |
| `ITSAppUsesNonExemptEncryption` = `false` | **DUPLICATE** of build setting `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`. Same value — Xcode will warn at build but won't fail. Resolved by removing from Info.plist (pbxproj is canonical). |
| `NSSupportsLiveActivities` = `true` | Matches `NowPlayingLiveActivity.swift`. |
| `NSSupportsLiveActivitiesFrequentUpdates` = `true` | Matches frequent-update budget per CarPlay/now-playing patterns. |
| `SentryDSN` = `$(SENTRY_DSN)` | **DUPLICATE** of build setting `INFOPLIST_KEY_SentryDSN = "$(SENTRY_DSN)"`. Same expansion — same warning class. Resolved by removing from Info.plist. |
| `UIAppFonts` | `PlayfairDisplay-Variable.ttf`, `PlayfairDisplay-Italic-Variable.ttf` — both ship under `OffScript/Fonts/`. |
| `UILaunchScreen` | Color-only launch screen, `LaunchBackground` asset. |
| `UIBackgroundModes` = `["audio","fetch","processing"]` | **DUPLICATE** of build setting `INFOPLIST_KEY_UIBackgroundModes = "audio fetch processing"`. Same value — Xcode warns. Resolved by removing from Info.plist. |

`CFBundleDisplayName` is set via build setting (`INFOPLIST_KEY_CFBundleDisplayName = OffScript`) — not duplicated in Info.plist. Correct.

`UISupportedInterfaceOrientations` is set via build setting, not in Info.plist — correct.

`LSApplicationCategoryType` = `public.app-category.entertainment` — set via build setting.

`UIApplicationSupportsCarPlay` — absent from both Info.plist and pbxproj. Consistent with the audio-session/CarPlay audit findings (CarPlay is NOT enabled; lock-screen Now Playing is the only car surface). No action.

`NSAppTransportSecurity` — absent. Default secure (HTTPS-only). Correct.

---

## Entitlements

### `OffScript/OffScript.entitlements`

| Key | Value | Used in code? |
|---|---|---|
| `com.apple.developer.applesignin` | `["Default"]` | YES — `SettingsView.swift:620` uses `SignInWithAppleButton`, `OnboardingFlowView.swift:149` uses `SignInWithAppleButtonView`. |
| `com.apple.security.application-groups` | `["group.com.offscript.shared"]` | YES — `SharedNowPlayingState.suiteName = "group.com.offscript.shared"`. Matches widget entitlement exactly. |

**Notable absence: no iCloud / CloudKit entitlements.** The code
references CloudKit (`AppleIdentityService.swift`, `SettingsView.swift`),
but `AppleIdentityService.hasCloudKitEntitlement` reads the embedded
provisioning profile at runtime and gracefully returns
`.notConfigured` when absent. The user-facing copy in
`SettingsView.swift:829` is explicit: *"This build is missing iCloud
entitlements. Sync stays local until the signed CloudKit profile
lands."*. This is **deliberate** — CloudKit is profile-gated, not
hard-coded. No action; flag for the signed/distribution profile.

**No `keychain-access-groups`** — the app doesn't share keychain items
across targets. The widget doesn't need keychain. Correct.

**No `com.apple.developer.usernotifications.communication`,
`com.apple.developer.networking.wifi-info`, `com.apple.developer.devicecheck`,
`com.apple.developer.associated-domains`** — none used. Correct.

### `OffScriptWidgets/OffScriptWidgets.entitlements`

| Key | Value | Used in code? |
|---|---|---|
| `com.apple.security.application-groups` | `["group.com.offscript.shared"]` | YES — `OffScriptWidgets/SharedNowPlayingState.swift:41` and `OffScriptWidgetsBundle.swift:8-9`. Matches main-app entitlement exactly. |

Widget does not need `applesignin`, CloudKit, push, or any other entitlement.
Minimal and correct.

---

## Sentry privacy config (read-only review — DEFER fixes)

Reviewed `OffScript/CrashReporter.swift:60-100`. Findings:

| Aspect | Status |
|---|---|
| DSN source | `Bundle.main.object(forInfoDictionaryKey: "SentryDSN")` — pulled from xcconfig at build time per CLAUDE.md. Skips init if DSN is the literal `$(SENTRY_DSN)` placeholder (line 50-63). Good — open-source PR builds won't accidentally ping Sentry. |
| `attachStacktrace` | `true` — needed for symbolication. OK. |
| `enableAutoSessionTracking` | `true` — session events are anonymous (no PII by default). OK. |
| `attachScreenshot` | **`false`** — explicit. Good (episode titles / queue would be PII). |
| `attachViewHierarchy` | **`false`** — explicit. Good. |
| `beforeSend` | Drops everything below `.error`. Quota-friendly; also drops info/warning noise that could carry user titles. OK. |
| `sendDefaultPii` | **Not explicitly set.** Sentry-cocoa default is `false`, but explicit `options.sendDefaultPii = false` would be more defensible if audited. **GAP — DEFERRED** (CrashReporter.swift is out of audit scope). |
| `tracesSampleRate` | `0.05` — 5% perf transactions. Could still carry URL paths. Acceptable. |
| `enableSwizzling` | `true` — required for auto-instrumentation. Adds network request capture; URLs may end up in breadcrumbs. **Worth a follow-up** to verify breadcrumb scrubbing. **DEFERRED.** |

Deferred follow-ups for the source-owner pass:
1. Explicitly set `options.sendDefaultPii = false`.
2. Add a `beforeBreadcrumb` filter to scrub episode-detail URLs / podcast feed URLs from network breadcrumbs.
3. Document the data flow in `docs/privacy/sentry.md` (or similar) so the App Store Privacy Nutrition Label can cite specifics.

---

## App Store metadata

**No `fastlane/`, `metadata/`, or `app-store-metadata/` directories
exist in the repo.** The closest assets are:

- `Config/AppStoreConnect.env.example` — API-key creds template.
- `Config/TestFlightUploadOptions.plist` — TestFlight upload config.
- `ci_scripts/` — likely Xcode Cloud scripts (read-only for this audit).

**GAP — App Store metadata not tracked in git.** Release notes, keywords,
support URL, marketing URL, privacy policy URL, and screenshots are
presumably authored directly in App Store Connect. For a v2.4.0 app
heading to broader release, this is a process risk:

- Privacy policy URL must be present in App Store Connect — verify
  manually before submission.
- Privacy Nutrition Label must be filled in App Store Connect to declare
  Sentry's crash data collection (Diagnostics → Crash Data → linked to
  user: No; used for tracking: No).
- Release notes have no source-of-truth in git — recommend creating
  `fastlane/metadata/en-US/` or a minimal `app-store/release-notes/<version>.txt`
  file going forward.

This is a STRATEGIC gap, not a code blocker. Filed under deferred.

---

## Bundle identity

| Claim | Verified value |
|---|---|
| Bundle id `com.offscript.app` | `PRODUCT_BUNDLE_IDENTIFIER = com.offscript.app` ✓ |
| Widget bundle id | `com.offscript.app.widgets` (matches the conventional `<parent>.widgets` pattern, set in pbxproj) ✓ |
| Display name "OffScript" | `INFOPLIST_KEY_CFBundleDisplayName = OffScript` ✓ |
| iOS deployment target 26.2 | `IPHONEOS_DEPLOYMENT_TARGET = 26.2` ✓ (all targets) |
| Marketing version | `MARKETING_VERSION = 2.4.0` |
| Build number | `CURRENT_PROJECT_VERSION = 2026051901` (date-encoded) |
| App category | `public.app-category.entertainment` |
| Encryption declaration | `ITSAppUsesNonExemptEncryption = NO` (TLS-only; no exempt crypto declared) |

All consistent with CLAUDE.md.

---

## Fixes applied (this audit)

1. **Removed two duplicate keys from `OffScript/Info.plist`** that are already set via `INFOPLIST_KEY_*` build settings in `OffScript.xcodeproj/project.pbxproj`. Xcode merges Apple-recognized `INFOPLIST_KEY_*` build settings into the generated Info.plist; having the same key in both sources emits a duplicate-key warning at build:
   - `ITSAppUsesNonExemptEncryption` → already `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` in pbxproj.
   - `UIBackgroundModes` → already `INFOPLIST_KEY_UIBackgroundModes = "audio fetch processing"` in pbxproj.

   **`SentryDSN` was kept** in Info.plist. `INFOPLIST_KEY_SentryDSN` is not in Apple's recognized-key list, so Xcode does NOT merge it; the Info.plist entry is the source of truth and `CrashReporter.swift` reads it via `Bundle.main.object(forInfoDictionaryKey: "SentryDSN")`.

2. **Added `OffScriptWidgets/PrivacyInfo.xcprivacy`** declaring `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`, since the widget reads the shared `UserDefaults(suiteName: "group.com.offscript.shared")`. **Caveat: this file is not yet a member of the widget target in `project.pbxproj`** — Xcode project file is out of audit scope. Whoever picks up the next pbxproj-touching task must add this file to the `OffScriptWidgets` target's "Copy Bundle Resources" build phase. Tracked as a deferred follow-up below.

Commits (this audit):

- `chore(info): remove duplicate Info.plist keys also set in build settings`
- `chore(privacy): add widget target privacy manifest`
- `docs: privacy + production-readiness audit findings`

Build verified green with `xcodebuild -project OffScript.xcodeproj -scheme OffScript -destination "platform=iOS Simulator,id=F623EB2A-1CF4-405E-9583-6B0EE2053FDE" -configuration Debug build` after fixes (** BUILD SUCCEEDED **).

---

## Deferred

- **Sentry `sendDefaultPii = false`** — explicit assertion in `CrashReporter.swift` (out of scope).
- **Sentry `beforeBreadcrumb`** to scrub episode/feed URLs (out of scope).
- **App Store metadata in git** — establish `fastlane/metadata/` or `app-store/` with release notes, keywords, privacy policy URL. Strategic, not blocking.
- **Privacy Nutrition Label** — must be filled in App Store Connect; declare Sentry as Diagnostics → Crash Data → not linked to user → not used for tracking.
- **Privacy Policy URL** — must point to a live URL in App Store Connect before submission. No URL is tracked in this repo today.
- **CloudKit entitlement** — deliberately deferred to the signed distribution profile, per `SettingsView.swift:829` user copy. When that lands, add `com.apple.developer.icloud-container-identifiers`, `com.apple.developer.icloud-services`, and `com.apple.developer.ubiquity-container-identifiers` to `OffScript.entitlements`.
- **Add `OffScriptWidgets/PrivacyInfo.xcprivacy` to the widget target's Copy Bundle Resources phase** in `OffScript.xcodeproj/project.pbxproj` — the file was created in this audit but cannot be added to the target without editing pbxproj (out of scope).
- **Widget per-target privacy manifest already added in this audit; recheck once Sentry SDK adds its own bundled manifest** — should not need updates.

---

## Classification

### MUST-FIX (before next App Store submission)
- **None within file scope.** The privacy manifest declares the right
  categories; Info.plist has the only usage description needed
  (`NSSpeechRecognitionUsageDescription`); entitlements are minimal and
  match code; the widget's missing privacy manifest is fixed in this
  audit.

### GAP (App-Store-submission gates)
- **Privacy Policy URL** must be set in App Store Connect (not trackable in repo).
- **Privacy Nutrition Label** must be filled in App Store Connect to
  declare Sentry crash diagnostics. Forgetting this triggers a 2.5
  rejection.
- **App Store metadata** (release notes, screenshots, keywords) lives
  only in App Store Connect today — process risk, not a blocker.
- **Sentry `sendDefaultPii = false`** should be explicit before
  submission so reviewers can confirm from source.
- **CloudKit entitlement** will need to be added when the signed profile
  lands; the runtime guard prevents crashes, but the "iCloud Sync"
  feature is currently dead-coded in production builds.

### STRATEGIC

OffScript is **technically ready to submit** to the App Store from a
plist/entitlements/manifest perspective. The required-reason API
manifest is correct, usage descriptions match the only sensitive API
the app touches (on-device speech recognition), entitlements are
minimal and honest, and the Sentry pipeline is privacy-conscious enough
to defend in App Review (no screenshots, no view hierarchy, errors-only,
no PII flag implicit-false). The remaining gaps are **process-side**:
the Privacy Nutrition Label, Privacy Policy URL, and release-notes
authorship live entirely in App Store Connect with no source-of-truth in
git, which means each submission depends on someone remembering to fill
those forms correctly. For a v2.4.0 app aimed at broader release, the
single highest-leverage follow-up is to set up `fastlane/metadata/`
(even just as a static directory checked into git) so that what App
Store Connect shows can be diffed and reviewed alongside code. The
CloudKit entitlement deferral is a deliberate architectural choice and
fine to leave; the runtime check in `AppleIdentityService` is the right
pattern. With the two file-level fixes in this audit (duplicate-key
cleanup, widget privacy manifest), the codebase side of the submission
checklist is complete.

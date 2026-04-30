# OffScript — Design & Development Bible

## App Identity
OffScript is an iOS podcast app with on-device AI recommendations. The visual direction is **Tuner OLED instrument cluster** — pure-black field, signal-yellow primary accent, function-coded tag pills, single-pixel hairlines, monospaced metadata. Reads as an instrument panel, not iOS Music.

The app is built around three commitments testers should feel on every screen:
1. **On-device AI** — FoundationModels for episode briefings + WHY copy, Speech for transcripts, Translation for non-English titles. No cloud round-trip; no third-party API keys touch listening data.
2. **No paid placements, no algorithm pushing** — the recommendation engine works only on signals the user generated themselves.
3. **Native Apple integration** — Siri intents, Spotlight donations, Now Playing widget, Live Activity, Dynamic Island.

## Visual vocabulary

### Colors (use named tokens from `AppTheme.swift` only)
- **Background**: `offscriptStudioBlack` — pure `#000`. The OLED field everything floats on.
- **Primary text**: `offscriptPaperWhite` (`#f3f1ea`)
- **Secondary text**: `offscriptSoftPaper` (`#7a7872`)
- **Primary accent**: `offscriptSignalYellow` (`#e8d24a`) — the only "color" most screens use. Active state, selected mode, headline eyebrow, key transport.
- **Function-coded accents** — used sparingly, only for state communication:
  - `offscriptFnRecord` (red `#e85a3c`) — destructive, error, recording
  - `offscriptFnMode` (green `#5fcf7e`) — active mode, success state
  - `offscriptFnInfo` (cyan `#5dc4e8`) — passive info, podcast title, source label
  - `offscriptFnMute` (gray) — disabled / off
- **Hairline**: `offscriptHairline` (white @ 8% alpha) — every divider, every border, every panel edge.
- **NEVER** use inline `Color.white.opacity(0.XX)`. Always reach for a token.

### Typography (named styles, not raw `Font.system()`)
- **Display headlines**: `.system(size: 32, weight: .bold).tracking(-0.5)` — screen titles ("Home", "Library", "Queue")
- **Section titles**: `.system(size: 22, weight: .semibold)` — episode titles, podcast names
- **Body**: `.system(size: 13.5, weight: .regular).lineSpacing(2)` — copy
- **Mono metadata**: `TunerLabel(...)` — every readout, eyebrow, status badge, channel number, time code. **Use `TunerLabel` rather than rolling your own monospaced text.**

### Corner radii — sharp, not rounded
- **Artwork tiles**: 3pt — `OffScriptArtworkView(url:cornerRadius: 3)` with a `Rectangle().stroke(Color.offscriptHairline)` overlay
- **Buttons / cards**: 0pt rectangles with hairline strokes
- The legacy 12 / 24 / 32pt radii from the editorial direction are gone — the Tuner aesthetic is sharp.

## Page architecture

Every top-level screen follows the same spec-sheet skeleton:

```
┌── EYEBROW (TunerLabel signalYellow) · STATUS (TunerLabel fnInfo) ──┐
│  Big screen title (32pt bold)                                       │
│  ── hairline rule ──                                                │
│  Section eyebrow (TunerLabel signalYellow)                          │
│  Section content                                                    │
│  ── hairline rule ──                                                │
│  Next section eyebrow                                               │
│  Next section content                                               │
└─────────────────────────────────────────────────────────────────────┘
```

- Pages use plain `VStack` with hairline-divided sections, **not** rounded surface cards.
- Section spacing: 16pt vertical between sections is the default; 12pt between section heading and content; 8pt between rows within a section.

## Component cheat sheet

### `TunerLabel`
The workhorse. Use for every eyebrow, status badge, mono caption.
```swift
TunerLabel(text: "BRIEFING · APPLE INTELLIGENCE", color: .offscriptSignalYellow)
TunerLabel(text: "● PLAYING", color: .offscriptFnMode)
TunerLabel(text: "● ERROR", color: .offscriptFnRecord)
```

### `TunerTag`
Pill-style tag with optional `dim: true` for less-emphatic uses.
```swift
TunerTag(text: episode.podcast.title, color: .offscriptFnRecord)
TunerTag(text: reason, color: .offscriptSignalYellow, dim: true)
```

### Tuner action button (inline, not a struct)
Repeated pattern for buttons: hairline rectangle with mono TunerLabel inside. No separate component — by convention, inline:
```swift
Button(action: action) {
    TunerLabel(text: "→ PLAY", color: .offscriptSignalYellow, size: 11)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
}
.buttonStyle(.plain)
```

### iOS 26 chrome trap
iOS 26 wraps SwiftUI-vended chrome in floating Liquid Glass / glass-capsule treatments that ignore `.buttonStyle(.plain)` and our color tokens:
- `TabView` → glass capsule. Use `TunerTabBar` instead.
- `.toolbar` ToolbarItem buttons → glass circles. Render buttons inline in the screen body.
- `.searchable` → translucent rounded search bar. Use a custom hairline `TextField` (see `SearchView.tunerSearchField`).

### Now Playing surfaces (`MiniPlayer`, `PlayerView`)
- MiniPlayer is a flat strip docked above the tab bar — no shadow, no rounded card, top hairline rule + 2pt signal-yellow progress rail + sharp signal-yellow play key (44pt hit target, 36pt visible).
- PlayerView is a full spec sheet: dismiss key inline (not toolbar), hairline-divided sections (`PLAYER · NOW PLAYING`, `UP NEXT`, `WHAT'S NEXT`, `CONTROLS · TRANSPORT`).

## Error handling
- **NEVER** use bare `try?` — always use do/catch with OSLog logging.
- Logger convention: `Logger(subsystem: "com.offscript", category: "ServiceName")`.
- Network failures: log URL, HTTP status, error description.
- SwiftData saves: log on failure.
- User-initiated actions: surface errors in UI (`● ERROR` `TunerLabel` strips).

## SwiftData
- **NEVER** use `persistentModelID` in `#Predicate` — use stored UUID properties.
- **ALWAYS** use predicate-filtered `FetchDescriptor` instead of fetch-all-then-filter.
- Relationships must have explicit `@Relationship(deleteRule:)` annotations.
- Schema migrations: `VersionedSchema` (`SchemaV1`, `SchemaV2`) + `OffScriptMigrationPlan`. Recovery in `OffScriptApp.sharedModelContainer` is three-tier: migrate → quarantine the entire `OffScript/` Application Support subdirectory and retry → in-memory fallback so the app always launches.

## Navigation
- Keep users in-app — never open external links without `SFSafariViewController`.
- Programmatic navigation (`@State + .navigationDestination`) for complex cards, not `NavigationLink` (which intercepts taps from sibling buttons).
- Deep links: `offscript://player`, `offscript://episode/<uuid>`, `offscript://episode/<uuid>/play`, `offscript://podcast/<uuid>`, `offscript://tab/<home|library|queue|search>`. All routed through `DeepLinkRouter`.

## Build & Testing
- SourceKit "Cannot find type in scope" errors for cross-file types are false positives — verify with actual build.
- Always run `xcodebuild` or Xcode MCP `BuildProject` to verify, not SourceKit diagnostics.
- Visual audits: `xcrun simctl io booted screenshot` is the reliable path; `xcrun simctl spawn DEVICE defaults write com.offscript.app offscript.debugLaunchTab -int N` swaps tabs without taps. `-offscript.debugSeedSampleData YES` populates 3 podcasts × 3 episodes for populated-state audits.

## CI
- TestFlight ships through **Xcode Cloud** (`Default` workflow on App Store Connect, branch start condition `main`, tag `v*`, action `ARCHIVE` with `buildDistributionAudience = APP_STORE_ELIGIBLE` so the same build can go to internal and external TestFlight testers).
- The legacy GH-Actions workflow lives at `.github/workflows/testflight.yml.disabled` for reference.
- Operational tools: `scripts/app_store_connect.py xcode-cloud {probe,inspect,reconfigure,start-build,build-run}`. The `Xcode Cloud Probe` GH workflow runs them on demand without a local `.env`.
- Sentry DSN injection: `ci_scripts/ci_post_clone.sh` materializes `Config/Secrets.xcconfig` from the `SENTRY_DSN` Xcode Cloud env var.

# OffScript — Design & Development Bible

## App Identity
OffScript is an iOS podcast app with on-device AI recommendations. Aesthetic: **Tuner OLED** — high-end OLED instrument cluster (Polestar / McLaren / studio monitor). Pure black field, signal-yellow as the only interactive accent, hairline strokes, mono uppercase labels, no gradients, no glow, no shadows.

The app is dark-only by design (instrument clusters are always black). The system Light Mode preference is honored only for share sheets and external surfaces; the app itself forces `.preferredColorScheme(.dark)`.

## Typography
Mono-forward, two distinct stacks with non-overlapping jobs. **NEVER** use raw `Font.system()` — always use the named tokens from AppTheme.swift.

- **Display value**: `.offscriptHero` — huge ultra-thin sans, monospaced digits. The single biggest number on a screen (player timecode, headline stat).
- **Display title**: `.offscriptDisplay` — thin sans `title2`, NOT serif. Episode titles in player, screen titles.
- **Utility title**: `.offscriptUtilityTitle` — sans semibold `title3`. Section heads.
- **Section title**: `.offscriptSectionTitle` — sans semibold `headline`.
- **Card title**: `.offscriptCardTitle` — sans semibold `subheadline`.
- **Body**: `.offscriptBody` — system sans `callout`. For prose only.
- **Mono meta**: `.offscriptMeta`, `.offscriptMicro` — system monospaced caption / caption2 with tabular digits. Use for **every** timecode, duration, percentage, scrubber readout, date metadata.
- **Tag label**: `.offscriptTagLabel` — 9.5pt mono semibold for tag-pill text. Apply with `.tracking(1.4)` and `.uppercased()`.

**No serif anywhere.** Playfair is gone. The instrument cluster speaks two languages — thin sans and tabular mono.

## Color Tokens
- **NEVER** use inline `Color.white.opacity(0.XX)` — use named tokens from AppTheme.swift
- **Surfaces**: pure black field. `offscriptBackground` = `Color.black`. Cards step `offscriptCard` → `offscriptCardRaised` → `offscriptCardStrong`. `offscriptCardUtility` is recessed (pure black + hairline) for inputs.
- **The interactive accent is signal yellow.** `Color.offscriptAccent` (`#e8d24a`). Use for play, scrubber, active state, focus rings. **Never use it for decorative section labels** — that drains its meaning.
- **Functional accent set** — tag pills + ring meter strokes only, each carrying semantic meaning:
  - `offscriptAccentSecondary` (cyan) → informational tag (episode #, host name, why we recommended)
  - `offscriptAccentOK` (mint) → mode / status pill ("LIVE", "AUTO", "DOWNLOADED")
  - `offscriptDestructive` (warm red) → warnings, errors, RECord state
- **Text hierarchy**: `offscriptTextPrimary` (warm white `#f3f1ea`) → `offscriptTextSecondary` (62%) → `offscriptTextMuted` (32%)
- **Hairlines**: `Color.offscriptHairline` is 8% white. Always stroke at **0.5 lineWidth**, never 1pt.

## Corner Radii (use OffScriptTheme.Radius tokens)
**Tuner is sharp.** Most elements are square or have tiny radii (≤6pt).
- **Hairline / tag pills**: 3pt (inline)
- **Capsule pills**: only for primary CTAs (`PrimaryPillButtonStyle`)
- **Cards / panels**: `OffScriptTheme.Radius.small` (now 6) for everything
- **Hero / artwork**: `OffScriptTheme.Radius.medium` (now 8)
- **Avoid** `OffScriptTheme.Radius.large` — soft decorative radii belong to the previous theme.

## Spacing System
- **Page padding**: `OffScriptTheme.pagePadding` (20pt)
- **Section spacing**: `OffScriptTheme.sectionSpacing` (28pt)
- **Item spacing**: `OffScriptTheme.itemSpacing` (16pt)

### Card Internal Padding
- **Standard panels**: 16pt
- **Compact panels**: 12pt
- **Avoid 20+pt padding** — Tuner reads tighter than the previous theme.

## Button Patterns

### Action Hierarchy (apply ruthlessly)
1. **Primary CTA**: filled signal-yellow capsule, uppercase mono label. `PrimaryPillButtonStyle`. Max one per screen.
2. **Secondary action**: outlined hairline pill, no fill, uppercase mono label. `SecondaryPillButtonStyle`.
3. **Tertiary**: text-link in mono uppercase with tracking, foreground = `offscriptTextPrimary` or `offscriptAccent`.
4. **Iconographic**: square hairline-bordered cell from `TTransportCell` with custom SF Symbol glyph + uppercase cap label below.

**Never** use rounded outline buttons that aren't pills. Never put two filled buttons on the same row.

### Play Actions
- **Compact**: `TTransportCell` style cell, signal-yellow play glyph
- **Primary/detail**: `PrimaryPillButtonStyle` "PLAY" / "RESUME"
- **Player transport**: 5 equal `TTransportCell`s, play key gets `emphasized: true`

### Queue Actions
- **Compact**: `+` icon in `TTransportCell` style
- **Detail**: `SecondaryPillButtonStyle` "ADD TO QUEUE"
- **Already queued**: `TTagPill(label: "QUEUED", tone: .ok)`

## Tuner UI Primitives (defined in `OffScript/OffScriptTunerKit.swift`)
- **`TTagPill(label:tone:)`** — replaces `OffScriptReasonBadge` / `OffScriptExplanationTag`. Tones: `.neutral`, `.info`, `.ok`, `.warn`, `.signal`.
- **`TReadout(value:unit:label:tint:size:alignment:)`** — Ferrari-style "huge thin value + tiny mono label" pair. Use for any prominent number.
- **`TRingMeter(...)`** — circular hairline meter with optional center text. Replaces every gauge / circular progress.
- **`TTransportCell(cap:emphasized:action:glyph:)`** — single transport key. Compose 4–6 into a row.
- **`TSpark(samples:tint:)`** — single-pixel polyline trace. Decorative instrument signal.
- **`TSectionHeader(eyebrow:title:rule:)`** — replaces `OffScriptSectionHeader` for Tuner screens.
- **`TPanel(title:padding:content:)`** — flat black panel + hairline. Replaces `offscriptSurface()` for control groups.

## Card Artwork Sizes (sharp 6pt corners)
- **Hero card**: Full-width, 200pt height
- **Standard rail card**: 160×160 (Tuner cards are square)
- **Library episode card**: 84×84
- **Search result card**: 64×64
- **Queue lead card**: 88×88
- **Queue item card**: 48×48
- **MiniPlayer thumbnail**: 44×44

## MiniPlayer
- Docked at bottom, below tab bar, full-width
- Artwork 44×44, padding 16h/10v, button spacing 8pt
- Episode title: 1-line
- Progress: hairline 1pt strip across the very top edge of the bar — instrument signal, not a separate widget
- Swipe up → open full player, swipe right → dismiss

## Error Handling
- **NEVER** use bare `try?` — always use do/catch with OSLog logging
- Logger convention: `Logger(subsystem: "com.offscript", category: "ServiceName")`
- Network failures: log URL, HTTP status, error description
- SwiftData saves: log on failure
- User-initiated actions: surface errors in UI (banners, error cards)

## SwiftData
- **NEVER** use `persistentModelID` in `#Predicate` — use stored UUID properties
- **ALWAYS** use predicate-filtered `FetchDescriptor` instead of fetch-all-then-filter
- Relationships must have explicit `@Relationship(deleteRule:)` annotations
- Use `VersionedSchema` for migrations (see SchemaMigration.swift)

## Navigation
- Keep users in-app — never open external links without SFSafariViewController
- Use programmatic navigation (`@State + .navigationDestination`) for complex cards, not `NavigationLink` (which intercepts taps from sibling buttons)

## Build & Testing
- SourceKit "Cannot find type in scope" errors for cross-file types are false positives — verify with actual build
- Always run `xcodebuild` or Xcode MCP `BuildProject` to verify, not SourceKit diagnostics
- Reset simulator (`xcrun simctl erase all`) when testing schema changes

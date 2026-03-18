# OffScript — Design & Development Bible

## App Identity
OffScript is an iOS podcast app with on-device AI recommendations. Dark editorial aesthetic — "editor's listening desk." Warm-to-cool gradient backgrounds, grain textures, serif display type, mono metadata.

## Typography
- **Display/Hero titles**: Playfair Display (bundled) — `.offscriptHero`, `.offscriptDisplay`
- **Section titles**: System serif bold — `.offscriptSectionTitle`
- **Card titles**: System default semibold — `.offscriptCardTitle`
- **Body text**: System default — `.offscriptBody`
- **Metadata**: System monospaced — `.offscriptMeta`, `.offscriptMicro`
- **NEVER** use raw `Font.system()` — always use named text styles from AppTheme.swift

## Color Tokens
- **NEVER** use inline `Color.white.opacity(0.XX)` — use named tokens from AppTheme.swift
- Accent: `Color.offscriptAccent` (warm amber-orange)
- Text hierarchy: `offscriptTextPrimary` → `offscriptTextSecondary` → `offscriptTextMuted`
- Surfaces: `offscriptCard`, `offscriptCardRaised`, `offscriptCardStrong`, `offscriptCardUtility`
- Destructive: `Color.offscriptDestructive`

## Corner Radii (use OffScriptTheme.Radius tokens)
- **Small** (12pt): Compact cards, queue items, buttons
- **Medium** (24pt): Standard cards, rail cards, search results
- **Large** (32pt): Hero cards, lead cards, artwork in player

## Spacing System
- **Page padding**: `OffScriptTheme.pagePadding` (20pt) — horizontal margins on all views
- **Spacious padding**: `OffScriptTheme.spaciousPadding` (28pt) — hero/lead content only
- **Section spacing**: `OffScriptTheme.sectionSpacing` (28pt) — between major sections
- **Item spacing**: `OffScriptTheme.itemSpacing` (18pt) — between cards in rails

### Card Internal Padding
- **Lead/hero cards**: 20pt
- **Standard cards**: 16pt
- **Compact cards**: 12pt

## Button Patterns

### Queue Actions
- **Compact contexts** (rail cards, list items): `"+" icon` in circle button
- **Detail contexts** (EpisodeDetailView, prominent cards): `"Add to Queue"` text pill
- **Already queued**: Checkmark icon (compact) or disabled `"Queued"` text (detail)

### Play Actions
- **Compact contexts** (rail cards, queue items, mini player): Icon-only circle (`play.fill`)
- **Primary/detail contexts** (hero card, episode detail): Text pill `"Play"` / `"Resume"`
- **Player transport**: Large 84pt circle button

### Button Sizing
- Compact icon circles: 36pt
- Standard icon circles: 44pt
- Text pills: Auto-sized with `fixedSize()` to prevent truncation

## Card Artwork Sizes
- **Hero card**: Full-width, 200pt height
- **Standard rail card**: 190×142pt
- **Library episode card**: 90×90pt
- **Search result card**: 76×76pt
- **Queue lead card**: 96×96pt
- **Queue item card**: 56×56pt
- **MiniPlayer thumbnail**: 52×52pt

## MiniPlayer
- Docked at bottom of screen, below tab bar
- Full-width, extends into safe area
- Artwork 52×52, padding 20h/12v, button spacing 8pt
- Episode title: 2-line max
- Progress bar: full-width, 2.5pt height
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

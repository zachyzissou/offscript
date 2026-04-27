# Design System: OffScript vNext

**Project ID:** `projects/10602978267448639151`  
**Design Direction:** The Signal Desk

OffScript is a recommendation-first podcast app for people who want fewer choices, better listening, and honest reasons. This design system describes where the product should go next. It is intentionally aspirational and should not be constrained by the current SwiftUI implementation.

Use this file as the source of truth for Stitch, agent design reviews, SwiftUI redesign work, app screenshots, and future marketing visuals.

## 1. Visual Theme & Atmosphere

OffScript should feel like a private editorial listening room: a dark desk, a stack of annotated episode cards, glowing waveform traces, and one confident recommendation waiting at the top.

The app is not a generic podcast client. It is not a dashboard. It is not a copy of Overcast, Pocket Casts, Castro, Spotify, Apple Podcasts, or any `getdesign.md` reference. It borrows sharper lessons from excellent systems:

- WIRED-like editorial confidence: strong hierarchy, mono kickers, story-first composition.
- ElevenLabs-like audio tactility: waveform motifs, refined depth, soft physical controls.
- Spotify-like content darkness: artwork provides color while chrome recedes.
- Apple-like iOS discipline: stable navigation, cinematic whitespace, precise interaction states.

The target feeling is **curated intelligence**. OffScript should make recommendations feel selected by taste, not emitted by an algorithm.

Core adjectives:

- Editorial
- Acoustic
- Tactile
- Focused
- Warm-dark
- Explainable
- Premium
- Human

Core anti-adjectives:

- Generic
- Dashboard-like
- Purple SaaS
- Frosted-glass demo
- Algorithmic black box
- Dense settings utility
- Card soup

## 2. Creative North Star

**The Signal Desk**

Imagine a night editor preparing a tight listening brief. The best episode is clipped to the top. The reason is handwritten in the margin. Fresh options are sorted into small stacks. The player feels like an audio instrument, not a media overlay.

Everything in the interface should answer one of three questions:

1. What should I listen to?
2. Why is OffScript recommending it?
3. What happens if I press play?

If a surface does not help answer one of those, it should be quieter, deferred, or removed.

## 3. Color Palette & Roles

This is a new vNext palette. Update implementation tokens to match this direction over time instead of forcing Stitch to follow the current app colors exactly.

| Semantic Name | Hex / Alpha | Role |
| --- | --- | --- |
| Studio Black | `#070707` | Deep app background, full-player stage, bottom navigation base. Never use pure black for text-on-text layering unless contrast is protected. |
| Ink Charcoal | `#101113` | Primary page background and scroll canvas. Warmer and less harsh than pure black. |
| Graphite Plate | `#18191D` | Standard card and rail surface. Feels like a physical plate on the desk. |
| Lifted Graphite | `#222329` | Elevated cards, mini player, active queue rows, modal sheets. |
| Warm Slate | `#2A241E` | Warm editorial feature surfaces and hero panels. Use when a section needs taste rather than utility. |
| Paper White | `#F7F1E8` | Primary text, hero headlines, major episode titles. Slightly warm, never sterile. |
| Soft Paper | `#D8D0C4` | Body text, episode descriptions, secondary player text. |
| Faded Paper | `#9B948B` | Metadata, captions, inactive labels, timestamps. |
| Signal Orange | `#FF7A1A` | Primary actions, playback progress, active tab, recommendation signal markers. Use functionally, not decoratively. |
| Copper Glow | `#C76B33` | Secondary warm accent for shadows, waveform glow, contextual warmth. |
| Cream Note | `#E9CFA6` | Explanation badges, editorial notes, “why this” surfaces. Not a primary action color. |
| Acid Bookmark | `#B7FF6A` | Rare success/added/save confirmation. Use as a tiny signal, never as a large fill. |
| Warning Amber | `#F3B24E` | Recoverable sync/import/download warnings. |
| Coral Cut | `#F06457` | Destructive actions and irreversible removes. |
| Blue Link Ink | `#5CA8FF` | External links, source links, legal/detail actions. Do not use for primary playback. |
| Hairline Smoke | `rgba(255,255,255,0.10)` | Card edges, control boundaries, bottom nav separation. |
| Ambient Shadow | `rgba(0,0,0,0.45)` | Dark-surface elevation. |
| Copper Shadow | `rgba(199,107,51,0.16)` | Warm hero/player glow only. |

Color rules:

- The UI should be mostly dark graphite and warm paper.
- Signal Orange is for playback and decisive actions.
- Cream Note is for recommendation explanations.
- Podcast artwork should provide most color variation.
- Avoid broad purple, blue-purple, or generic neon gradients.
- Avoid transparent glass over complex artwork unless a solid readability layer sits above it.
- Semantic colors must stay small and precise.

## 4. Typography Rules

OffScript needs a stronger editorial type system than a default iOS app.

Recommended type direction:

- Display serif: **Newsreader**, **Fraunces**, **Playfair Display**, or a similar high-contrast editorial serif.
- Interface sans: **Avenir Next**, **Satoshi**, **Inter**, or SF-compatible system sans if native fidelity is more important.
- Mono metadata: **SF Mono**, **Geist Mono**, or system monospaced.

Typography roles:

| Role | Visual Description | Usage |
| --- | --- | --- |
| Hero Editorial | High-contrast serif, 34-42pt on iPhone, tight but readable leading. | Home lead statement, onboarding thesis, major player/title moments. |
| Section Editorial | Serif, 22-26pt, confident but not oversized. | `Best Next`, `Fresh Signals`, `Continue`, `Library`. |
| Episode Title | Semibold sans or restrained serif, 17-22pt depending on prominence. | Episode cards, queue rows, player context. |
| Body Copy | Sans, 15-17pt, relaxed enough for episode summaries. | Descriptions, onboarding copy, empty states. |
| Signal Kicker | Monospaced uppercase, 11-13pt, 0.8-1.2px tracking. | Recommendation labels, show/source, duration, freshness, sync state. |
| Micro Utility | Monospaced or sans, 10-12pt. | Download progress, timestamps, small control labels. |

Typography rules:

- Every recommendation card gets a mono signal kicker.
- Every major surface gets one editorial headline, not several competing titles.
- Body copy should be comfortable, not tiny.
- Metadata is always visually quieter than title and reason.
- Avoid shrinking long podcast titles into illegibility; wrap or recompose instead.
- Do not use more than three type voices on one screen.

## 5. Shape, Depth, And Materials

OffScript should feel tactile and physical, but not skeuomorphic.

Corner system:

- 8pt: tiny chips, progress capsules, utility fields.
- 14pt: compact buttons and small rows.
- 20pt: standard episode cards.
- 28pt: hero recommendation cards and player panels.
- 36pt: full-player sheets and major atmospheric surfaces.
- Full pill: playback actions, topic chips, filters.
- Circle: transport controls, artwork-adjacent icon controls.

Depth system:

| Level | Treatment | Use |
| --- | --- | --- |
| Level 0 | Studio Black / Ink Charcoal, no border | Page background and full-player stage. |
| Level 1 | Graphite Plate with Hairline Smoke | Standard episode and library cards. |
| Level 2 | Lifted Graphite with soft shadow | Mini player, lead recommendation, queue lead row. |
| Level 3 | Warm Slate with Copper Shadow | Hero modules and special editorial moments. |
| Level 4 | Solid dark sheet with protected foreground | Full player, modals, high-attention overlays. |

Depth rules:

- Use shadow to clarify stacking, not to decorate every card.
- Use warm glow only around hero/player moments.
- Use hairline edges on floating dark surfaces.
- Avoid default `List` rows on core product screens.
- Clip every artwork image explicitly.

## 6. Component Stylings

### Lead Recommendation Card

The lead recommendation is OffScript's signature object. It should feel like an annotated editorial pick.

Structure:

- Large artwork or artwork-derived color field.
- Mono kicker such as `BEST NEXT`, `SIGNAL PATH`, or `CONTINUE`.
- Episode title with strong hierarchy.
- One visible reason in Cream Note styling.
- Primary Play button in Signal Orange.
- Secondary Queue button in dark pill.
- Optional small confidence/context line, never raw score.

Rules:

- Only one lead recommendation per Home screen.
- It must not look like an ad.
- It must expose both action and reason without requiring detail navigation.

### Episode Cards

Episode cards should feel like story tiles, not generic rows.

Structure:

- Fixed artwork well with clipping.
- Mono show/source kicker.
- Title.
- Date/duration/progress metadata.
- One reason or status.
- One primary action and one secondary action max.

Rules:

- Artwork never escapes the card.
- Adjacent cards must have visible spacing.
- Long text wraps within the content column.
- Do not stack multiple unbounded buttons inside small cards.

### Reason Badges

Reason badges are the product's trust layer.

Visual style:

- Cream Note text or fill.
- Full-pill or clipped paper-tag shape.
- Mono or compact sans.
- Optional tiny signal glyph.

Good examples:

- `Fits your 28 min window`
- `Because you finished Decoder`
- `Fresh from a saved show`
- `You usually finish this format`
- `Continue from 42%`

Bad examples:

- `Score: 0.82`
- `Recommended for you`
- `AI pick`
- `Trending`

### Playback Controls

The player should feel like a precision audio instrument.

Controls:

- Play/pause is the visual center.
- 15s back and 30s forward are secondary but clearly reachable.
- Progress should feel continuous and tactile.
- Chapter, sleep timer, route picker, share, and queue are available without cluttering the transport row.

Rules:

- Full-player artwork should fit by default, not over-zoom.
- Player controls sit on a protected foreground panel.
- Queue context should appear in the player so it is not a dead end.

### Mini Player

The mini player is a docked audio strip, not a card accidentally covering navigation.

Rules:

- It sits above the tab bar with clear spacing.
- It never obscures tab labels or hit targets.
- It has integrated progress.
- It can expand into the full player with visual continuity.
- It should remain legible over all tab backgrounds.

### Navigation

Bottom tabs remain stable. OffScript can look distinctive without making users relearn iOS navigation.

Tab rules:

- Use stable positions: Home, Library, Queue, Search.
- Active state uses Signal Orange.
- Inactive state uses Faded Paper.
- Do not hide playback behind navigation.
- Do not move high-frequency controls between releases.

## 7. Screen Patterns

### Home

Home is the editorial front page.

Pattern:

- App title and one compact settings/profile action.
- One dominant lead recommendation.
- Short reason visible above or beneath the episode title.
- Supporting rails: `Continue`, `Fresh Signals`, `Quick Wins`, `From Your Shows`.
- Every rail has a clear editorial purpose.

Avoid:

- Equal-weight feed cards.
- Large decorative hero copy pushing content below the fold.
- Repeating the same artwork/card layout across every section.

### Library

Library is active listening inventory.

Pattern:

- Top-level collections: `In Progress`, `Downloaded`, `Fresh`, `Shows`.
- Persistent sort/filter affordances.
- Sync failure and stale-feed state are visible and recoverable.
- Show pages feel like clean archives with episode search.

Avoid:

- Plain directory lists.
- Unclipped artwork.
- Rows where actions collide with title text.

### Queue

Queue is the working set.

Pattern:

- Lead "Up Next" item with stronger visual treatment.
- Reorder affordance is obvious.
- Swipe remove is available.
- `Play Next` and `Add to End` semantics are predictable.

Avoid:

- Queue as a hidden player submenu.
- Ambiguous autoplay state.

### Search And Import

Search is discovery and onboarding continuation.

Pattern:

- Search field as a dark tactile utility surface.
- Topic shortcuts for cold start.
- Show detail before import.
- Post-import payoff routes to first recommended episode.

Avoid:

- Treating RSS import as a raw technical task.
- Success states that do not tell users what to play next.

### Full Player

Full player is the emotional center.

Pattern:

- Fit-scaled artwork or atmospheric crop with subject preservation.
- Episode/show hierarchy on a protected foreground panel.
- Transport row has generous hit targets.
- Chapter and queue context are visible below the fold but discoverable.
- Done/collapse action is stable and reachable.

Avoid:

- Zoomed artwork that crops the subject by default.
- Text floating directly on busy art.
- Controls compressed into one dense strip.

### Onboarding

Onboarding should prove taste quickly.

Pattern:

- One editorial promise.
- Three fast subscription/import moments.
- Topic preference without survey fatigue.
- First recommended episode shown immediately after setup.

Avoid:

- Long AI explanation.
- Empty library after onboarding.
- Import failure dead ends.

## 8. Motion And Interaction

Motion should feel like audio equipment: precise, weighted, and calm.

Motion rules:

- Use fast ease-out for cards entering.
- Use subtle stagger only on editorial stacks.
- Use spring only for player expansion/collapse and queue reorder.
- Use waveform/progress motion only where it communicates playback or loading.
- Respect Reduce Motion.
- Avoid bounce-heavy or decorative animation.

Signature interactions:

- Mini player expands into full player with matched artwork/transport continuity.
- Queue reorder uses physical lift and settle.
- Add-to-queue gives a tiny Acid Bookmark confirmation.
- Recommendation reason can expand into a short explanation, but defaults concise.

## 9. Accessibility And Legibility

OffScript is dark and artwork-heavy, so accessibility must be designed in, not patched later.

Rules:

- Text never relies on raw artwork contrast.
- Foreground text over artwork needs a solid/scrimmed protection layer.
- Touch targets should be at least 44pt.
- Reason badges must be readable at small sizes.
- Color never carries state alone.
- Dynamic Type should preserve hierarchy without overlap.
- VoiceOver labels must include episode title, show, duration, progress, and primary action.
- Reduce Transparency should keep all controls solid.

## 10. Implementation Translation

This file defines the destination. Implementation should move toward it intentionally.

SwiftUI translation rules:

- Create or update tokens before styling individual screens.
- Convert this palette into named `Color.offscript...` tokens.
- Convert type roles into named `Font.offscript...` tokens.
- Convert component patterns into reusable views before broad rollout.
- Do not hand-style one-off cards on every screen.
- Fix clipping and spacing defects before adding visual flourish.

Suggested token update names:

- `offscriptStudioBlack`
- `offscriptInkCharcoal`
- `offscriptGraphitePlate`
- `offscriptLiftedGraphite`
- `offscriptWarmSlate`
- `offscriptPaperWhite`
- `offscriptSoftPaper`
- `offscriptFadedPaper`
- `offscriptSignalOrange`
- `offscriptCopperGlow`
- `offscriptCreamNote`
- `offscriptAcidBookmark`

## 11. Stitch Prompt Starter

Use this prompt with Stitch:

```text
Use the attached OffScript vNext DESIGN.md as the source of truth. Design an iPhone podcast app screen for a recommendation-first audio app called OffScript. The style is The Signal Desk: dark editorial listening room, graphite physical surfaces, warm paper typography, mono signal labels, orange playback actions, cream recommendation notes, artwork-led color, tactile waveform details, and iOS-native bottom navigation. Make recommendations explainable and human. Avoid generic podcast app layouts, purple SaaS gradients, heavy glass over artwork, default List chrome, and equal-weight card feeds.
```


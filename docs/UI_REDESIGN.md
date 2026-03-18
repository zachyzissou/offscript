# OffScript UI Redesign Brief

## Product Tone
OffScript should feel like an editor's listening desk.

The app is not a neutral utility and it is not a flashy glass demo. It should feel curated, tactile, and calm:
- dark studio surfaces
- warm paper-like cards
- artwork-forward layouts
- serif headlines
- mono metadata
- restrained motion

The product promise is simple: open the app and instantly understand what to listen to next, why it was chosen, and how to act on it.

## Design Principles
1. Content leads.
   Podcast artwork, episode title, duration fit, and listening context should dominate the screen. Chrome supports the content rather than competing with it.

2. Recommendations are explainable.
   Every recommendation should carry a short reason such as `Because you finished Hard Fork`, `Fits 24 min`, or `Continue listening`.

3. The UI should feel premium without becoming ornamental.
   Use depth, gradients, motion, and blur to clarify hierarchy. Avoid decorative translucency that hurts legibility.

4. Listening should stay one tap away.
   Every major surface should expose an obvious primary play action. Queue and feedback actions should remain close, but secondary.

5. Navigation is a commitment.
   Keep the current bottom-tab structure and avoid moving high-frequency controls between updates.

6. The player is the emotional center.
   The mini player and full player should feel connected and premium. This is the surface users live in, so it deserves the most visual weight.

7. Trust beats novelty.
   Recommendations should not reshuffle unpredictably. Adaptive behavior should appear as helpful confidence, not surprising automation.

## Anti-Patterns
- Heavy Liquid Glass treatments over busy artwork backgrounds
- Generic iOS `List` styling on primary surfaces
- Too many equal-weight cards on Home
- Hidden queue context from the player
- Player controls that are small, dense, or inconsistent
- A feed that explains nothing about why items appeared

## Visual System
### Color
- `ink`: rich charcoal background with a warm bias
- `surface`: layered card tones for raised/floating content
- `paper`: soft off-white for primary text
- `accent`: warm orange for action, progress, and active states
- `muted`: legible but quiet metadata tones
- `status`: limited use for queue, success, warning, and error states

### Typography
- Serif display for hero and card titles
- Sans for body copy and controls
- Monospaced metadata for episode context, timestamps, and labels

### Shape and Depth
- 16pt small radius
- 24pt card radius
- 32pt hero/artwork radius
- one consistent soft shadow family
- hairline borders on elevated surfaces

### Motion
- quick ease-out transitions
- subtle staggered entrances
- matched visual relationship between mini player and full player
- no bounce-heavy animation as default

## Screen Strategy
### Home
- Promote one dominant `Best Next` hero recommendation at the top
- Show recommendation reasons inline
- Convert supporting sections into rails or grouped editorial blocks
- Preserve visible progress for unfinished episodes

### Mini Player
- Treat it like a compact tape deck
- Integrate progress into the bar itself
- Make the play/pause control visually bold

### Full Player
- Use artwork to create atmosphere, but keep text and controls highly legible
- Elevate transport controls and progress into a clear foreground card
- Surface queue context so the player is not a dead end

### Library
- Move away from a plain directory and toward active collections:
  `In Progress`, `Fresh Episodes`, `Shows`

### Queue
- Frame it as a working set, not a storage bin
- Make reorder and triage actions obvious

### Search
- Keep subscription one tap away
- Use starter pack / topic shortcuts to accelerate cold start

### Onboarding
- Sell the editorial recommendation premise
- Get the user to three subscriptions quickly
- Show payoff fast

## Shared Components To Extract
- `OffScriptCard`
- `ArtworkView`
- `SectionHeaderView`
- `PrimaryActionButton`
- `SecondaryActionButton`
- `ReasonBadge`
- `PlayerProgressBar`
- `FloatingSurface`
- `EmptyStateView`

## Implementation Roadmap
### Phase 1
- Expand `OffScript/AppTheme.swift` into a real design system
- Redesign `OffScript/MiniPlayer.swift`
- Redesign `OffScript/PlayerView.swift`
- Redesign the top of `OffScript/HomeView.swift`

Acceptance criteria:
- app has a unified surface, type, and spacing system
- player surfaces feel visually related
- Home has a clear editorial hierarchy
- recommendation reasons are visible

### Phase 2
- Redesign `OffScript/LibraryView.swift`
- Redesign `OffScript/QueueView.swift`
- Add shared empty-state styling

Acceptance criteria:
- generic `List` chrome no longer defines the product tone
- library and queue feel active rather than administrative

### Phase 3
- Redesign `OffScript/SearchView.swift`
- Redesign `OffScript/OnboardingView.swift`
- Bring `OffScript/SettingsView.swift` up to system standards

Acceptance criteria:
- first-run feels distinctive
- search accelerates subscription and taste bootstrap
- visual consistency holds across all top-level surfaces

## UX Non-Negotiables
- bottom tab bar remains stable
- primary playback actions stay discoverable
- recommendation reasons stay short and human-readable
- queue behavior never surprises the user
- readability is validated on top of real artwork and dark backgrounds

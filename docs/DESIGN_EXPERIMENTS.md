# OffScript Design Experiments

This document tracks visual/UX experiments generated through Stitch before production SwiftUI implementation. The goal is to compare materially different design choices, not small color or spacing variants.

## Experiment: Home A/B/C/D

Project: `OffScript iPhone Design System`  
Project ID: `10602978267448639151`  
Design system: `OffScript vNext - The Signal Desk`  
Design system asset: `assets/9613635482825796653`

### Shared Success Criteria

Each candidate must:

- Make the best next episode obvious within 2 seconds.
- Show a human-readable recommendation reason.
- Keep Play and Queue actions available without opening detail.
- Keep the mini player above the bottom tab bar without overlap.
- Preserve stable tabs: Home, Library, Queue, Search.
- Clip all artwork inside its container.
- Avoid generic podcast-feed/card-grid patterns.

### Variant A: Editorial Brief

Screen ID: `d50c92dda71c4da28d17f5fce60c1023`  
Resource: `projects/10602978267448639151/screens/d50c92dda71c4da28d17f5fce60c1023`  
Screenshot: `docs/stitch/screens/home-a-editorial-brief.png`

Hypothesis:

Home should feel like a concise editorial listening brief. One dominant recommendation creates trust and reduces choice fatigue.

What Works:

- Strongest answer to “what should I listen to next?”
- Best use of editorial hierarchy and explanation note.
- Most aligned with OffScript’s recommendation-first product thesis.
- Supporting content feels secondary instead of competing.

Risks:

- If the hero gets too tall, repeat users may feel slowed down.
- Needs careful implementation to keep the mini player and tab bar separated.
- Needs dynamic content rules for long episode titles.

Verdict:

Primary production candidate for Home.

### Variant B: Signal Console

Screen ID: `3171473cdca84ad2929ddac67c912b4c`  
Resource: `projects/10602978267448639151/screens/3171473cdca84ad2929ddac67c912b4c`  
Screenshot: `docs/stitch/screens/home-b-signal-console.png`

Hypothesis:

Some users want to compare multiple strong recommendations quickly. A ranked signal board can create control and transparency.

What Works:

- Best comparison model for top recommendations.
- Strong utility for later-stage/power users.
- Ranking, duration, freshness, and reasons make recommendation logic visible.
- Compact structure is easier to scan than a large hero-only model.

Risks:

- Comes closest to feeling like a dashboard.
- Repeated cards can become monotonous.
- More actions per card increase cognitive load.
- Less emotional and premium than Variant A.

Verdict:

Do not use as the overall Home structure. Borrow its ranked “Top Signals” module below the lead recommendation.

### Variant C: Immersive Listening Room

Screen ID: `054045e1fe7d4192a159173cd630bb26`  
Resource: `projects/10602978267448639151/screens/054045e1fe7d4192a159173cd630bb26`  
Screenshot: `docs/stitch/screens/home-c-immersive-room.png`

Hypothesis:

Home can feel more emotionally connected to playback by foregrounding current listening and the transition into what comes next.

What Works:

- Strongest emotional tone.
- Best player/now-playing atmosphere.
- Good model for the full player and expanded mini-player relationship.
- Makes progress and playback feel tactile.

Risks:

- Current playback dominates the Home screen more than recommendations.
- Best Next appears too low for a recommendation-first product.
- Risks drifting toward a Spotify-like listening surface.
- Better as Player direction than Home direction.

Verdict:

Use as input for `PlayerView` and full-player redesign, not Home.

### Variant D0: Signal Observatory

Screen ID: `65bd2773d81249ad8d43b1ea8f368fc8`  
Resource: `projects/10602978267448639151/screens/65bd2773d81249ad8d43b1ea8f368fc8`  
Screenshot: `docs/stitch/screens/home-d0-signal-observatory.png`

Hypothesis:

Home can become an editorial signal instrument instead of a feed, using a cinematic lead recommendation and observable reasoning.

What Works:

- More memorable than A/B/C.
- Keeps the lead recommendation obvious.
- Explanation remains visible.
- The mini player and tabs are correctly separated.

Risks:

- Still reads like a stylized card stack rather than a true leap.
- Portrait artwork dominates without enough system identity.
- The visual metaphor is not as strong as the later Analog Studio or Topographic Map variants.

Verdict:

Useful stepping stone. Do not implement directly.

### Variant D1: Signal Mixer

Screen ID: `15752ba9545a48c7bbab5ecfcccc6bc9`  
Resource: `projects/10602978267448639151/screens/15752ba9545a48c7bbab5ecfcccc6bc9`  
Screenshot: `docs/stitch/screens/home-d1-signal-mixer.png`

Hypothesis:

Podcast discovery can feel like tuning a high-end audio console, making recommendations feel selected and mixed rather than algorithmically dumped.

What Works:

- Stronger physical product feel.
- Good top calibration language.
- Better balance between brand identity, lead pick, next signals, mini player, and tabs.
- The tactile buttons are plausible for SwiftUI.

Risks:

- Could become too hardware-themed if every screen follows it literally.
- Some labels are too decorative and may not survive Dynamic Type.
- Needs a cleaner recommendation reason treatment.

Verdict:

Strong source for playback controls, mini-player polish, and signal/status language.

### Variant D2: Physical Analog Studio

Screen ID: `963e9d77c6144a58a7a89744e3c2e06f`  
Resource: `projects/10602978267448639151/screens/963e9d77c6144a58a7a89744e3c2e06f`  
Screenshot: `docs/stitch/screens/home-d2-analog-studio.png`

Hypothesis:

The boldest credible OffScript direction is a private analog listening studio: circular signal dial, copper-lit controls, and recommendation confidence as a physical meter.

What Works:

- Strongest "wow" candidate.
- Ownable audio identity that competitors do not have.
- Circular signal dial is memorable and could become a signature component.
- The confidence/reason module has a distinct product purpose, not just decoration.

Risks:

- Heavy visual treatment could reduce daily-use speed.
- Uppercase technical typography must be softened for long real podcast titles.
- Skeuomorphic controls can become gimmicky if not restrained.
- The secondary signal rows need more breathing room in production.

Verdict:

Best experimental direction to borrow from. Use its hero dial, copper-lit playback moments, and confidence meter, but implement with A's editorial restraint.

### Variant D3: Brutalist Editorial

Screen ID: `b83d29436bc84b1f95c213b8da87186f`  
Resource: `projects/10602978267448639151/screens/b83d29436bc84b1f95c213b8da87186f`  
Screenshot: `docs/stitch/screens/home-d3-brutalist-editorial.png`

Hypothesis:

OffScript can differentiate through a raw art-magazine editorial interface that treats recommendations like cultural criticism.

What Works:

- Most instantly distinctive.
- High-contrast lime highlight makes AI/recommendation state obvious.
- Large typographic gestures feel less like a commodity podcast app.

Risks:

- Highest readability and accessibility risk.
- Least calm for daily listening.
- Long titles and real feed metadata will break the composition.
- The bottom player and tabs feel cramped.

Verdict:

Do not ship as the main app direction. Borrow sparingly: bolder typography, high-contrast confidence tag, and stronger editorial attitude.

### Variant D4: Topographic Signal Map

Screen ID: `ef3c6e8371ec41198d6097cb5b22f4af`  
Resource: `projects/10602978267448639151/screens/ef3c6e8371ec41198d6097cb5b22f4af`  
Screenshot: `docs/stitch/screens/home-d4-topographic-signal-map.png`

Hypothesis:

Recommendations can be spatial: the lead pick and supporting picks form a visible signal map, making discovery feel explainable and navigable.

What Works:

- Best conceptual model for explainable recommendations.
- The connected-node cluster could make "why this" feel visual, not just textual.
- Good bridge between recommendation intelligence and audio identity.
- More elegant than D3 and more product-relevant than decorative waveform art.

Risks:

- Graph/map UI can become dashboard-like if overused.
- Node clusters are harder to make accessible and tappable.
- Requires careful SwiftUI layout to avoid overlap bugs.

Verdict:

Borrow the signal-map metaphor for a future recommendation-detail or "Why this" view. For Home, use only a restrained hint of this in the Top Signals module.

### Variant E1: Analog Master Console

Screen ID: `e7b6c0068aeb4367b57b6132c1d225c6`  
Resource: `projects/10602978267448639151/screens/e7b6c0068aeb4367b57b6132c1d225c6`  
Screenshot: `docs/stitch/screens/home-e1-analog-master-console.png`

Hypothesis:

OffScript can own a physical-audio identity by making recommendation confidence feel like a tangible studio instrument.

What Works:

- Strongest signature control language: circular aperture, tactile copper control, confidence meters.
- Immediately reads as audio-native instead of generic podcast-client UI.
- Good model for a branded play button, signal dial, and queue channel rows.

Risks:

- Too narrow and dense if copied literally.
- Several labels become decorative at real iPhone size.
- The hardware metaphor can overpower the actual episode title and reason.

Verdict:

Borrow the circular meter, copper play control, and tactile channel language. Do not copy the full master-console layout.

### Variant E2: Topographic Recommendation Map

Screen ID: `b14d9af80b2c4e1e9d5fbf0a76ae85ef`  
Resource: `projects/10602978267448639151/screens/b14d9af80b2c4e1e9d5fbf0a76ae85ef`  
Screenshot: `docs/stitch/screens/home-e2-topographic-recommendation-map.png`

Hypothesis:

Recommendations can become spatial, with the best episode sitting at the highest signal peak and supporting episodes arranged as map nodes.

What Works:

- The map metaphor remains product-relevant for explainable recommendation paths.
- Floating reason callout is a strong "why this" pattern.
- Dark terrain/grid treatment could become a future explanation-detail surface.

Risks:

- The generated result is less topographic than intended and drifts back toward standard cards.
- Spatial nodes are harder to make accessible and reliably tappable.
- The bottom recommendation area is visually underpowered.

Verdict:

Do not use for Home. Save the callout/map idea for a dedicated "Why this recommendation" screen.

### Variant E3: Editorial Zine

Screen ID: `f87bd089b7b84625b6477c9a834273e5`  
Resource: `projects/10602978267448639151/screens/f87bd089b7b84625b6477c9a834273e5`  
Screenshot: `docs/stitch/screens/home-e3-editorial-zine.png`

Hypothesis:

OffScript could feel like a cultural front page: opinionated, high-contrast, and sharply authored.

What Works:

- Boldest marketing screenshot.
- The title treatment is memorable and far from commodity podcast UI.
- Cream editor-note cards make the recommendation reason feel human.

Risks:

- Highest risk for real long episode titles, Dynamic Type, and daily scanning speed.
- Dense lower content can recreate the overlap/alignment issues we are trying to eliminate.
- The layout demands too many bespoke rules for real RSS data.

Verdict:

Use as attitude reference only. Borrow the editor-note treatment and typographic confidence, not the layout.

### Variant E4: Audio-Instrument Cockpit

Screen ID: `3645bd68ab8449aa8b7b0cb2da34d598`  
Resource: `projects/10602978267448639151/screens/3645bd68ab8449aa8b7b0cb2da34d598`  
Screenshot: `docs/stitch/screens/home-e4-audio-instrument-cockpit.png`

Hypothesis:

The app can make each recommendation feel like a tuned channel in a live audio cockpit.

What Works:

- Strong channel metaphor for queue and secondary recommendations.
- Mini-player treatment feels docked and intentional.
- The "target locked" bracket creates a clear primary focus.

Risks:

- Horizontal oversized panels can easily create off-screen/overlap issues.
- The cockpit metaphor reads more technical than human.
- Digital-instrument labels may be too cold for a recommendation-first app.

Verdict:

Borrow channel-strip ideas for queue/player states. Do not make Home a full cockpit.

### Variant E5: Premium Listening Room

Screen ID: `3d0aa9279c39443280de4bb80b0cad3e`  
Resource: `projects/10602978267448639151/screens/3d0aa9279c39443280de4bb80b0cad3e`  
Screenshot: `docs/stitch/screens/home-e5-premium-listening-room.png`

Hypothesis:

The best daily-use version of the bold direction is calmer: one monolithic recommendation surface, strong negative space, restrained orange, and a signature physical motif.

What Works:

- Best balance of "wow" and real podcast usability.
- Keeps the lead recommendation readable and calm.
- The monolith motif is ownable without becoming gimmicky.
- Sparse orange makes the primary play action feel decisive.

Risks:

- Could become too quiet if secondary recommendations are not distinctive enough.
- Needs careful empty/loading states so the spacious style does not feel barren.
- Artwork must remain clipped and fit-scaled to avoid the earlier bleed problems.

Verdict:

Primary production direction for the next SwiftUI pass. Combine E5's monolith structure with E1's signal meter and E3's cream editor note.

## Home Direction Decision

Implement a hybrid:

- Use Variant A as the Home spine.
- Add a compact Variant B-inspired `Top Signals` module below the lead pick.
- Borrow Variant C only for player/mini-player continuity, not Home hierarchy.
- Add Variant D2/E1's circular signal dial and confidence-meter language in a restrained way.
- Add Variant E5's monolithic recommendation surface as the current production target.
- Borrow Variant E3's editor-note explanation treatment without adopting its chaotic layout.
- Save Variant D4's connected signal-map pattern for the future "Why this" explanation surface.
- Do not use Variant D3 as a primary direction.

## Production A/B/C Testing Plan

Do not ship all three full Home layouts to beta users immediately. First implement the hybrid as the primary design. If runtime testing becomes useful later, test smaller variables:

- Lead recommendation layout density: spacious hero vs compact hero.
- Reason badge placement: inline under title vs note block.
- Secondary recommendations: horizontal rail vs ranked vertical list.
- Mini-player prominence: compact strip vs larger dock.

Suggested instrumentation:

- First play from Home.
- Play from lead recommendation.
- Queue from lead recommendation.
- Tap reason / expand explanation.
- Scroll depth on Home.
- Mini-player expand.
- Repeat Home engagement after relaunch.

Do not optimize solely for taps. OffScript’s goal is confident listening, so measure recommendation starts, completions, and reduced hunting behavior.

## Local SwiftUI A/B/C Harness

Current DEBUG launch variants:

- `hero`: E5-inspired premium monolith. Best for brand impression and recommendation confidence.
- `feed`: compact shortlist. Best for scan speed and exposing multiple picks above the mini player.
- `split`: balanced signal board. Best compromise between a clear lead pick and ranked comparison.

Current simulator screenshots:

- Hero: `docs/stitch/screens/current-home-hero.png`
- Feed-first: `docs/stitch/screens/current-home-feed.png`
- Split: `docs/stitch/screens/current-home-split.png`

Launch examples:

```sh
xcrun simctl launch --terminate-running-process booted com.offscript.app \
  -offscript.hasSeenOnboarding YES \
  -offscript.debugSeedLibrary YES \
  -offscript.debugBootPlayback YES \
  -offscript.debugLaunchTab 0 \
  -offscript.debugHomeVariant hero
```

Swap the final value to `feed` or `split` to capture the other candidates.

For repeatable visual QA, run:

```sh
scripts/capture_home_variants.sh
```

Current read:

- `hero` is still the strongest brand direction, but it uses the most vertical space and shows the least feed context on first paint.
- `feed` is the most practical daily-driver candidate because it exposes the lead pick plus ranked alternatives before the mini player.
- `split` is the safest compromise, but it is less distinctive than `hero` and less efficient than `feed`.

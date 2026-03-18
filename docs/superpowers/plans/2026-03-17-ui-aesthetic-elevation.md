# OffScript UI Aesthetic Elevation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Elevate OffScript's visual design from "competent dark mode" to a distinctive, signature experience that could only be this app — addressing typography compression, spatial monotony, color vocabulary, entrance motion, and the underselling of its core differentiator (explainable recommendations).

**Architecture:** All changes target the existing SwiftUI view layer and `AppTheme.swift` design system. No new dependencies. No model changes. Work progresses from the design system outward (theme tokens first, then component upgrades, then screen-level composition changes). Each task produces a visually testable result via Xcode Preview or Simulator.

**Tech Stack:** SwiftUI, SwiftData (read-only for views), AVFoundation (unchanged), SF Symbols

---

## File Structure

| File | Role | Tasks |
|------|------|-------|
| `OffScript/AppTheme.swift` | Design system: colors, fonts, surfaces, components | 1, 2, 3, 6, 8 |
| `OffScript/HomeView.swift` | Home feed with hero + rails | 4, 5 |
| `OffScript/PlayerView.swift` | Full-screen player | 5, 7 |
| `OffScript/MiniPlayer.swift` | Persistent mini player bar | 7 |
| `OffScript/OnboardingView.swift` | First-run experience | 9 |
| `OffScript/QueueView.swift` | Queue management | 5, 8 |
| `OffScript/EpisodeDetailView.swift` | Episode info + feedback | 5 |
| `OffScript/SearchView.swift` | Discovery | 5, 8 |
| `OffScript/LibraryView.swift` | Subscription library | 5 |
| `OffScript/ContentView.swift` | Root tab shell | 5 |
| `OffScript/SettingsView.swift` | Preferences | 5 |

---

### Task 1: Typography Hierarchy Refinement

**Why:** Text hierarchy is compressed (secondary 74% vs muted 70% = invisible difference). Body text too small. Uppercase text lacks letter-spacing. Monospaced is overused for non-data elements.

**Files:**
- Modify: `OffScript/AppTheme.swift` (Color extensions lines 15-32, Font extensions lines 34-43, OffScriptReasonBadge lines 104-120)

- [ ] **Step 1: Fix the secondary/muted text color gap**

Change `offscriptTextSecondary` and `offscriptTextMuted` to have visible separation:

```swift
// Before:
static let offscriptTextSecondary = Color.white.opacity(0.74)
static let offscriptTextMuted = Color.white.opacity(0.7)

// After:
static let offscriptTextSecondary = Color.white.opacity(0.78)
static let offscriptTextMuted = Color.white.opacity(0.52)
```

The gap goes from 4% to 26% — now clearly two distinct tiers on dark backgrounds.

- [ ] **Step 2: Upgrade body text size**

Change `offscriptBody` from `.subheadline` to `.callout` so episode descriptions and summaries are comfortable to read:

```swift
// Before:
static let offscriptBody = Font.system(.subheadline, design: .default)

// After:
static let offscriptBody = Font.system(.callout, design: .default)
```

- [ ] **Step 3: Add letter-spacing to uppercase text**

Update `OffScriptUtilityHeader`'s eyebrow text (line ~152) to add `.tracking(1.2)` on the uppercase eyebrow `Text` (note: `.tracking()` is a `Text`-level modifier in SwiftUI):

```swift
Text(eyebrow.uppercased())
    .font(.offscriptMeta.weight(.semibold))
    .tracking(1.2)
    .foregroundStyle(Color.offscriptAccent)
```

- [ ] **Step 4: Switch reason badges from monospaced to small-caps sans**

`OffScriptReasonBadge` currently uses `.offscriptMicro` (monospaced caption2). Reason text like "TOPIC MATCH" isn't data — it's a label. Change to a sans-serif small-caps treatment:

```swift
// In OffScriptReasonBadge body:
Text(text.uppercased())
    .font(.caption2.weight(.bold))
    .tracking(0.8)
    .foregroundStyle(Color.offscriptTextPrimary)
```

- [ ] **Step 5: Verify in Simulator**

Build and run. Check that:
- Episode descriptions in EpisodeDetailView are comfortably readable
- Secondary text (podcast titles) is clearly lighter than primary (episode titles)
- Muted text (timestamps, durations) is clearly lighter than secondary
- Reason badges feel like labels, not code
- Eyebrow text ("QUEUE", "SEARCH") breathes with letter-spacing

- [ ] **Step 6: Commit**

```bash
git add OffScript/AppTheme.swift
git commit -m "design: refine typography hierarchy — widen text color gap, upgrade body size, add tracking"
```

---

### Task 2: Color Palette Expansion

**Why:** Single accent (orange) carries too many meanings. Background gradient is imperceptible. No destructive color that harmonizes with palette. No texture/grain.

**Files:**
- Modify: `OffScript/AppTheme.swift` (Color extensions lines 15-32, OffScriptBackgroundView lines 45-53, new noise texture modifier)

- [ ] **Step 1: Add secondary accent and harmonized destructive colors**

Add to the `Color` extension block:

```swift
// Warm cream secondary accent — for informational highlights that aren't CTAs
static let offscriptAccentSecondary = Color(red: 0.92, green: 0.84, blue: 0.68)
static let offscriptAccentSecondaryMuted = Color(red: 0.92, green: 0.84, blue: 0.68).opacity(0.14)

// Destructive — desaturated coral that belongs in the warm palette
static let offscriptDestructive = Color(red: 0.88, green: 0.36, blue: 0.32)
static let offscriptDestructiveSoft = Color(red: 0.88, green: 0.36, blue: 0.32).opacity(0.16)
```

- [ ] **Step 2: Deepen background gradient range**

The current gradient is (0.08 → 0.04) — only 4% difference. Widen it:

```swift
// Before:
static let offscriptBackgroundTop = Color(red: 0.08, green: 0.08, blue: 0.09)
static let offscriptBackgroundBottom = Color(red: 0.04, green: 0.04, blue: 0.05)

// After — warm-biased top, cool-biased bottom for visible shift:
static let offscriptBackgroundTop = Color(red: 0.10, green: 0.09, blue: 0.08)
static let offscriptBackgroundBottom = Color(red: 0.03, green: 0.03, blue: 0.05)
```

- [ ] **Step 3: Add a subtle grain/noise texture overlay**

Create a `GrainOverlay` modifier that adds analog warmth to surfaces. Uses a seeded random with a fixed seed so the canvas doesn't re-render on every frame, and keeps the point count low for performance:

```swift
struct GrainOverlay: ViewModifier {
    var opacity: Double = 0.03

    func body(content: Content) -> some View {
        content.overlay(
            Canvas { context, size in
                var rng = SplitMix64(seed: 42)
                let count = min(Int(size.width * size.height * 0.005), 1200)
                for _ in 0..<count {
                    let x = CGFloat.random(in: 0..<size.width, using: &rng)
                    let y = CGFloat.random(in: 0..<size.height, using: &rng)
                    let gray = CGFloat.random(in: 0.3...1.0, using: &rng)
                    context.fill(
                        Path(CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                        with: .color(Color(white: gray, opacity: opacity))
                    )
                }
            }
            .allowsHitTesting(false)
            .drawingGroup()
        )
    }
}

// Deterministic RNG so grain pattern is stable across renders
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

extension View {
    func offscriptGrain(opacity: Double = 0.03) -> some View {
        modifier(GrainOverlay(opacity: opacity))
    }
}
```

- [ ] **Step 4: Apply grain to card surfaces**

In `OffScriptSurfaceModifier.body`, add `.offscriptGrain()` on the background `RoundedRectangle` fill (before the overlay and shadow, so grain applies to the card face only, not the shadow region):

```swift
.background(
    RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(
            LinearGradient(
                colors: prominent
                    ? [Color.offscriptCardStrong, Color.offscriptCardRaised]
                    : [Color.offscriptCardRaised, Color.offscriptCard],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .offscriptGrain(opacity: prominent ? 0.035 : 0.025)
)
```

- [ ] **Step 5: Verify in Simulator**

Check that:
- Background gradient is subtly visible (warm top, cooler bottom)
- Grain texture is visible on cards when looking closely, but not distracting at normal viewing distance
- The secondary accent color is distinct from the primary orange

- [ ] **Step 6: Commit**

```bash
git add OffScript/AppTheme.swift
git commit -m "design: expand color palette — secondary accent, warm background gradient, grain texture"
```

---

### Task 3: Recommendation Explanation Treatment

**Why:** OffScript's killer feature (explainable AI recommendations) uses the same `OffScriptReasonBadge` as generic labels like "42M" and "QUEUED." The most distinctive content gets the least distinctive visual treatment.

**Files:**
- Modify: `OffScript/AppTheme.swift` (add new component after OffScriptReasonBadge ~line 120)
- Modify: `OffScript/HomeView.swift` (HeroRecommendationCard ~line 171, EpisodeRailCard ~line 317)
- Modify: `OffScript/PlayerView.swift` (PlayerSuggestionRow ~line 322)

- [ ] **Step 1: Create a dedicated `OffScriptExplanationTag` component**

This is visually distinct from reason badges — it uses the secondary accent and has a left-edge accent bar:

Add after `OffScriptReasonBadge` in `AppTheme.swift`:

```swift
struct OffScriptExplanationTag: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.offscriptAccent)
                .frame(width: 3, height: 14)

            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.offscriptAccentSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.offscriptAccentSecondaryMuted)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
```

- [ ] **Step 2: Replace reason badges with explanation tags in HeroRecommendationCard**

In `HomeView.swift`, in `HeroRecommendationCard`, find the `OffScriptReasonBadge(text: reason)` call (~line 171) and replace:

```swift
// Before:
OffScriptReasonBadge(text: reason)

// After:
OffScriptExplanationTag(text: reason)
```

- [ ] **Step 3: Replace reason badges with explanation tags in EpisodeRailCard**

In `HomeView.swift`, in `EpisodeRailCard`, find `OffScriptReasonBadge(text: reason)` (~line 317) and replace:

```swift
// Before:
OffScriptReasonBadge(text: reason)

// After:
OffScriptExplanationTag(text: reason)
```

- [ ] **Step 4: Replace the accent color on PlayerSuggestionRow explanations**

In `PlayerView.swift`, in `PlayerSuggestionRow` (~line 322), the explanation text currently uses `Color.offscriptAccent`. Change to:

```swift
// Before:
Text(scored.explanation)
    .font(.offscriptMicro.weight(.semibold))
    .foregroundStyle(Color.offscriptAccent)
    .lineLimit(1)

// After:
OffScriptExplanationTag(text: scored.explanation)
```

- [ ] **Step 5: Verify in Simulator**

Check that:
- Explanation tags are visually distinct from reason badges (different color, shape, left accent bar)
- They scan clearly at a glance — the accent bar draws the eye
- The warm cream color doesn't clash with the orange accent on the same card
- Text truncation works cleanly on long explanations

- [ ] **Step 6: Commit**

```bash
git add OffScript/AppTheme.swift OffScript/HomeView.swift OffScript/PlayerView.swift
git commit -m "design: add distinctive explanation tag for AI recommendations"
```

---

### Task 4: Hero Card Breakout

**Why:** The home feed hero card (`HeroRecommendationCard`) is just a slightly larger card — it doesn't command the viewport. The spatial composition review scored C+ largely because every element sits in the same grid rhythm.

**Files:**
- Modify: `OffScript/HomeView.swift` (HeroRecommendationCard ~lines 150-265)

- [ ] **Step 1: Redesign the hero card layout**

Replace the current `HeroRecommendationCard` body with a layout that breaks the grid — larger artwork on top, content below, edge-to-edge feel:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 0) {
        // Artwork hero zone — larger, more dominant
        ZStack(alignment: .bottomLeading) {
            OffScriptArtworkView(
                url: episode.artworkURL ?? episode.podcast.artworkURL,
                cornerRadius: 0
            )
            .frame(height: 200)
            .clipped()
            .overlay(
                LinearGradient(
                    colors: [.clear, .clear, Color.offscriptCardStrong.opacity(0.7), Color.offscriptCardStrong],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Overlay the explanation tag on the artwork
            VStack(alignment: .leading, spacing: 8) {
                OffScriptExplanationTag(text: reason)

                Text(episode.podcast.title)
                    .font(.offscriptMeta.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.offscriptTextSecondary)
                    .lineLimit(1)
            }
            .padding(20)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: OffScriptTheme.Radius.large,
                topTrailingRadius: OffScriptTheme.Radius.large,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                style: .continuous
            )
        )

        // Content zone
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink {
                EpisodeDetailView(episode: episode)
            } label: {
                Text(episode.title)
                    .font(.system(.title2, design: .serif, weight: .bold))
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Label(metadata, systemImage: "clock")
                if episode.playedPosition > 0, !episode.isPlayed {
                    Label(timeRemaining, systemImage: "arrow.trianglehead.clockwise")
                }
            }
            .font(.offscriptMeta)
            .foregroundStyle(Color.offscriptTextMuted)

            if progressValue > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    OffScriptProgressBar(value: progressValue, height: 6)
                    Text("Resume from where you left off")
                        .font(.offscriptMeta)
                        .foregroundStyle(Color.offscriptTextMuted)
                }
            }

            HStack(spacing: 10) {
                Button("Play") {
                    PlaybackController.shared.play(episode, in: modelContext)
                }
                .buttonStyle(PrimaryPillButtonStyle())

                Button(episode.isQueued ? "Queued" : "Queue") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        try? QueueService.add(episode, in: modelContext)
                    }
                }
                .buttonStyle(SecondaryPillButtonStyle())
                .disabled(episode.isQueued)
                .sensoryFeedback(.impact(flexibility: .soft), trigger: episode.isQueued)

                Spacer()

                Menu {
                    Button("Like") { register(.like) }
                    Button("Less like this") { register(.lessLikeThis) }
                    Button("Not now") { register(.notInterested) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
                .accessibilityLabel("More actions")
                .accessibilityHint("Like this episode or tune future recommendations")
            }
        }
        .padding(20)
        .padding(.bottom, 4)
    }
    .background(
        RoundedRectangle(cornerRadius: OffScriptTheme.Radius.large, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.offscriptCardStrong, Color.offscriptCardRaised],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .offscriptGrain(opacity: 0.035)
    )
    .overlay(
        RoundedRectangle(cornerRadius: OffScriptTheme.Radius.large, style: .continuous)
            .stroke(Color.offscriptHairline, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: OffScriptTheme.Radius.large, style: .continuous))
    .shadow(color: Color.black.opacity(0.38), radius: 28, y: 14)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(episode.title) from \(episode.podcast.title). \(reason)")
}
```

- [ ] **Step 2: Verify in Simulator**

Check that:
- The hero card visually dominates the home feed — it looks *different* from everything else
- Artwork spans the full card width with a gradient fade
- Episode title is large and readable below the artwork
- The card doesn't clip awkwardly on smaller iPhones (SE/mini)
- NavigationLink to EpisodeDetailView still works
- Play/Queue/Menu buttons all function

- [ ] **Step 3: Commit**

```bash
git add OffScript/HomeView.swift
git commit -m "design: hero card breakout with full-width artwork and dominant layout"
```

---

### Task 5: Staggered Entrance Animations

**Why:** Content appears instantaneously after loading. Individual cards and sections don't stagger their entrance, making the screen feel like a data dump rather than a curated reveal.

**Files:**
- Modify: `OffScript/AppTheme.swift` (add stagger modifier)
- Modify: `OffScript/HomeView.swift` (apply to feed sections)
- Modify: `OffScript/QueueView.swift` (apply to queue items)
- Modify: `OffScript/LibraryView.swift` (apply to shelf cards)
- Modify: `OffScript/SearchView.swift` (apply to results)
- Modify: `OffScript/ContentView.swift` (no changes needed — stagger is per-screen)
- Modify: `OffScript/EpisodeDetailView.swift` (apply to sections)
- Modify: `OffScript/SettingsView.swift` (apply to stat cards)

- [ ] **Step 1: Create a staggered entrance modifier**

Add to `AppTheme.swift` (includes `accessibilityReduceMotion` support from the start):

```swift
struct StaggeredEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    let baseDelay: Double

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 1 : (isVisible ? 1 : 0))
            .offset(y: reduceMotion ? 0 : (isVisible ? 0 : 12))
            .animation(
                reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82)
                    .delay(Double(index) * baseDelay),
                value: isVisible
            )
            .onAppear { isVisible = true }
    }
}

extension View {
    func staggeredEntrance(index: Int, delay: Double = 0.06) -> some View {
        modifier(StaggeredEntrance(index: index, baseDelay: delay))
    }
}
```

- [ ] **Step 2: Apply to Home feed sections**

In `HomeView.swift`, in the main `body` `else` branch (where `sections` are rendered, after loading), wrap each visual element with a stagger index.

On the hero card (~line 62):
```swift
HeroRecommendationCard(
    episode: leadEpisode,
    reason: leadSection.explanation(for: leadEpisode)
)
.padding(.horizontal, OffScriptTheme.pagePadding)
.staggeredEntrance(index: 0)
```

On the "Next Best Picks" rail (~line 70):
```swift
RecommendationRail(...)
    .staggeredEntrance(index: 1)
```

On the `ForEach` for remaining sections (~line 79):
```swift
ForEach(Array(sections.dropFirst().enumerated()), id: \.element.id) { offset, section in
    RecommendationRail(
        title: section.title,
        subtitle: section.subtitle,
        episodes: section.episodes,
        reasonProvider: { section.explanation(for: $0) }
    )
    .staggeredEntrance(index: offset + 2)
}
```

- [ ] **Step 3: Apply to Queue items**

In `QueueView.swift`, on the `ForEach` items (~line 75):
```swift
ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
    QueueItemCard(item: item, rank: index + 1, onRemove: { ... })
        .contextMenu { ... }
        .padding(.horizontal, OffScriptTheme.pagePadding)
        .staggeredEntrance(index: index)
}
```

- [ ] **Step 4: Apply to Search results**

In `SearchView.swift`, on the `ForEach` results (~line 94):
```swift
ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
    SearchResultCard(...)
        .padding(.horizontal, OffScriptTheme.pagePadding)
        .staggeredEntrance(index: index)
}
```

- [ ] **Step 5: Verify in Simulator**

Check that:
- Home feed sections cascade in with a gentle waterfall effect
- Queue items stagger when the tab loads
- Search results stagger as they appear
- The animation feels like a reveal, not a delay
- `accessibilityReduceMotion` should be tested — stagger should still work but without the offset/opacity animation (the `onAppear` sets `isVisible = true` immediately regardless)

- [ ] **Step 6: Commit**

```bash
git add OffScript/AppTheme.swift OffScript/HomeView.swift OffScript/QueueView.swift OffScript/SearchView.swift
git commit -m "design: add staggered entrance animations across feed, queue, and search"
```

---

### Task 6: Button Hierarchy & Destructive Color

**Why:** Primary and secondary buttons differ only in fill color — same size, same weight, same shadow. Destructive actions use an unrelated red. Queue rank badges compete with CTAs by sharing the accent color.

**Files:**
- Modify: `OffScript/AppTheme.swift` (PrimaryPillButtonStyle ~line 272, SecondaryPillButtonStyle ~line 288)
- Modify: `OffScript/QueueView.swift` (rank badge ~line 201, Clear All button ~line 55)

- [ ] **Step 1: Differentiate primary button physicality**

Update `PrimaryPillButtonStyle` to feel heavier — slightly taller padding, deeper press scale, subtle shadow:

```swift
struct PrimaryPillButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(Color.offscriptAccent.opacity(configuration.isPressed ? 0.78 : 1.0))
            .clipShape(Capsule())
            .shadow(color: Color.offscriptAccent.opacity(configuration.isPressed ? 0 : 0.25), radius: 8, y: 4)
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.94 : 1.0))
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
```

Key changes: `.weight(.bold)` (was semibold), padding 18/13 (was 16/11), scale 0.94 (was 0.96), response 0.25 (was 0.3), accent shadow glow.

- [ ] **Step 2: Update queue rank badge to neutral color**

In `QueueView.swift`, `QueueItemCard` body (~line 201), change the rank circle from accent to neutral:

```swift
// Before:
Text("\(rank)")
    .font(.headline.weight(.bold))
    .foregroundStyle(Color.offscriptAccent)
    .frame(width: 34, height: 34)
    .background(Color.offscriptAccentSoft)
    .clipShape(Circle())

// After:
Text("\(rank)")
    .font(.headline.weight(.bold))
    .foregroundStyle(Color.offscriptTextPrimary)
    .frame(width: 34, height: 34)
    .background(Color.white.opacity(0.08))
    .clipShape(Circle())
    .overlay(
        Circle().stroke(Color.offscriptHairline, lineWidth: 1)
    )
```

- [ ] **Step 3: Apply harmonized destructive color to Clear All**

In `QueueView.swift`, the "Clear All" button (~line 55):

```swift
// Before:
.font(.offscriptMeta.weight(.semibold))
.foregroundStyle(Color.red.opacity(0.8))

// After:
.font(.offscriptMeta.weight(.semibold))
.foregroundStyle(Color.offscriptDestructive)
```

- [ ] **Step 4: Apply harmonized destructive to SearchErrorCard**

In `SearchView.swift`, `SearchErrorCard` (~line 280):

```swift
// Before:
.background(Color.red.opacity(0.18))
// ...
.stroke(Color.red.opacity(0.35), lineWidth: 1)

// After:
.background(Color.offscriptDestructiveSoft)
// ...
.stroke(Color.offscriptDestructive.opacity(0.4), lineWidth: 1)
```

- [ ] **Step 5: Verify in Simulator**

Check that:
- Primary buttons feel noticeably heavier than secondary (taller, bolder, glowing shadow)
- Queue numbers no longer look like tappable accent elements
- "Clear All" uses a warm red that doesn't jar against the palette
- Error cards use the same warm red family

- [ ] **Step 6: Commit**

```bash
git add OffScript/AppTheme.swift OffScript/QueueView.swift OffScript/SearchView.swift
git commit -m "design: differentiate button hierarchy, neutralize rank badges, harmonize destructive color"
```

---

### Task 7: MiniPlayer Character

**Why:** The mini player is visible for most of the user's session but is generic: artwork + title + play button. It needs more character to serve as OffScript's signature persistent element.

**Files:**
- Modify: `OffScript/MiniPlayer.swift` (full file, 68 lines)

- [ ] **Step 1: Add a circular progress ring around the artwork**

Replace the top-level `OffScriptProgressBar` with a ring around the artwork thumbnail. This makes progress visible *around* the content rather than as a separate bar:

```swift
struct MiniPlayer: View {
    @ObservedObject private var player = PlaybackController.shared

    var body: some View {
        if let episode = player.currentEpisode {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Artwork with progress ring — tapping opens the player
                    ZStack {
                        Circle()
                            .stroke(Color.offscriptProgressTrack, lineWidth: 3)
                            .frame(width: 54, height: 54)

                        Circle()
                            .trim(from: 0, to: progressValue)
                            .stroke(
                                Color.offscriptAccent,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .frame(width: 54, height: 54)
                            .rotationEffect(.degrees(-90))

                        OffScriptArtworkView(
                            url: episode.artworkURL ?? episode.podcast.artworkURL,
                            cornerRadius: 22
                        )
                        .frame(width: 44, height: 44)
                    }

                    // Title area — tapping opens the player
                    VStack(alignment: .leading, spacing: 3) {
                        Text(episode.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.offscriptTextPrimary)
                            .lineLimit(1)

                        Text(episode.podcast.title)
                            .font(.offscriptMeta)
                            .foregroundStyle(Color.offscriptTextMuted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Play/pause — separate button to avoid nested-button issues
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(width: 38, height: 38)
                            .background(Color.offscriptAccent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "Pause playback" : "Resume playback")
                    .accessibilityValue(episode.title)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            // Use contentShape + onTapGesture for the "open player" tap area
            // This avoids nesting a Button inside a Button
            .contentShape(Rectangle())
            .onTapGesture {
                player.isPlayerPresented = true
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Now playing: \(episode.title)")
            .accessibilityHint("Tap to expand the player")
            .offscriptSurface(radius: OffScriptTheme.Radius.medium)
            .padding(.horizontal, 12)
            .shadow(color: Color.black.opacity(0.22), radius: 16, y: 8)
        }
    }

    private var progressValue: Double {
        guard player.duration > 0 else { return 0 }
        return player.currentTime / player.duration
    }
}
```

Key changes: Progress bar replaced with circular ring around artwork. Surface upgraded from utility to standard. The "open player" action uses `onTapGesture` on the container (not a nested `Button`) so the play/pause `Button` captures taps correctly without interference.

- [ ] **Step 2: Verify in Simulator**

Check that:
- Progress ring animates smoothly during playback
- Ring starts at 12 o'clock and sweeps clockwise
- Tapping the mini player body opens the full player sheet
- Tapping the play/pause button toggles playback without opening the player
- The surface change (from utility to standard) makes the mini player feel more premium
- Artwork is centered and properly clipped within the ring

- [ ] **Step 3: Commit**

```bash
git add OffScript/MiniPlayer.swift
git commit -m "design: mini player with circular progress ring and premium surface"
```

---

### Task 8: Empty State Personality

**Why:** Empty states use `ContentUnavailableView` — Apple's generic system component. An app with editorial voice ("Queue with intent") should have empty states that match that tone.

**Files:**
- Modify: `OffScript/AppTheme.swift` (add custom empty state component)
- Modify: `OffScript/QueueView.swift` (replace ContentUnavailableView ~line 29)
- Modify: `OffScript/HomeView.swift` (replace ContentUnavailableView ~line 51)
- Modify: `OffScript/SearchView.swift` (replace ContentUnavailableView ~line 83)

- [ ] **Step 1: Create `OffScriptEmptyState` component**

Add to `AppTheme.swift`:

```swift
struct OffScriptEmptyState: View {
    let icon: String
    let headline: String
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.offscriptAccent.opacity(0.6))
                .frame(width: 72, height: 72)
                .background(Color.offscriptAccentSoft)
                .clipShape(Circle())

            VStack(spacing: 8) {
                Text(headline)
                    .font(.offscriptDisplay)
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 320)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 2: Replace Queue empty state**

In `QueueView.swift` (~line 29), replace the `ContentUnavailableView` + NavigationLink block:

```swift
// Before:
VStack(spacing: 20) {
    ContentUnavailableView("Queue is empty", systemImage: "text.badge.plus", description: Text("Save episodes from Home or Library and they'll stack up here in the order you actually want to hear them."))

    NavigationLink("Browse Home") {
        HomeView(onOpenSettings: {})
    }
    .buttonStyle(PrimaryPillButtonStyle())
}

// After:
VStack(spacing: 20) {
    OffScriptEmptyState(
        icon: "text.badge.plus",
        headline: "Nothing queued yet",
        message: "Your queue is a working set, not a backlog. Add a few episodes you actually plan to hear next."
    )

    NavigationLink("Browse Home") {
        HomeView(onOpenSettings: {})
    }
    .buttonStyle(PrimaryPillButtonStyle())
}
```

- [ ] **Step 3: Replace Home empty state**

In `HomeView.swift` (~line 51), replace:

```swift
// Before:
VStack(spacing: 20) {
    ContentUnavailableView("No recommendations yet", systemImage: "waveform.badge.magnifyingglass", description: Text("Add a few shows in Search and OffScript will build your smart feed."))

    NavigationLink("Browse Search") {
        SearchView()
    }
    .buttonStyle(PrimaryPillButtonStyle())
}

// After:
VStack(spacing: 20) {
    OffScriptEmptyState(
        icon: "waveform.badge.magnifyingglass",
        headline: "Your feed starts here",
        message: "Add three shows you trust and OffScript will build a feed that feels curated, not algorithmic."
    )

    NavigationLink("Browse Search") {
        SearchView()
    }
    .buttonStyle(PrimaryPillButtonStyle())
}
```

- [ ] **Step 4: Replace Search no-results state**

In `SearchView.swift` (~line 83), replace:

```swift
// Before:
ContentUnavailableView("No podcasts found", systemImage: "magnifyingglass", description: Text("Try another show, host, or topic."))

// After:
OffScriptEmptyState(
    icon: "magnifyingglass",
    headline: "No matches",
    message: "Try a different show name, host, or topic. Exact titles work best."
)
```

- [ ] **Step 5: Verify in Simulator**

Check that:
- Empty states use the app's serif display font and editorial voice
- The accent-tinted icon circle matches the overall aesthetic
- Copy feels authored and specific to each context
- Action buttons (NavigationLinks) still work

- [ ] **Step 6: Commit**

```bash
git add OffScript/AppTheme.swift OffScript/QueueView.swift OffScript/HomeView.swift OffScript/SearchView.swift
git commit -m "design: branded empty states with editorial voice"
```

---

### Task 9: Onboarding Visual Upgrade

**Why:** The onboarding screen is entirely text — no artwork, no animation, no visual hook for what should be the app's most important first impression. The design review noted it as "a wall of copy."

**Files:**
- Modify: `OffScript/OnboardingView.swift` (full file, 155 lines)

- [ ] **Step 1: Update OnboardingCard to accept an icon parameter**

Update `OnboardingCard` first (before rewriting the view body that calls it with the new parameter):

```swift
private struct OnboardingCard: View {
    var icon: String? = nil
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let icon {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.offscriptAccent)
                    .frame(width: 32, height: 32)
                    .background(Color.offscriptAccentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.offscriptTextSecondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.offscriptHairline, lineWidth: 1)
        )
    }
}
```

- [ ] **Step 2: Rewrite OnboardingView body with visual presence and entrance animation**

Rewrite the `OnboardingView` body to include a visual header, staggered card entrances, and a more atmospheric background:

```swift
struct OnboardingView: View {
    let onFinish: (_ jumpToSearch: Bool) -> Void
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Richer atmospheric background
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.06, blue: 0.04),
                        Color.offscriptBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Subtle accent glow in the upper region
                RadialGradient(
                    colors: [Color.offscriptAccent.opacity(0.08), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 400
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        // App identity
                        VStack(alignment: .leading, spacing: 18) {
                            Text("OffScript")
                                .font(.system(size: 46, weight: .bold, design: .serif))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.offscriptTextPrimary, Color.offscriptAccent],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .staggeredEntrance(index: 0, delay: 0.12)

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Build your Smart Feed in three good picks.")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.white)

                                Text("Add a few shows or topics you trust. OffScript uses those early signals to build a feed that feels edited instead of endless.")
                                    .font(.offscriptBody)
                                    .foregroundStyle(Color.offscriptTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .staggeredEntrance(index: 1, delay: 0.12)
                        }

                        HStack(spacing: 10) {
                            OnboardingStepIndicator(step: 1, text: "Add 3 shows")
                            OnboardingStepIndicator(step: 2, text: "Seed topics")
                            OnboardingStepIndicator(step: 3, text: "Get your feed")
                        }
                        .staggeredEntrance(index: 2, delay: 0.12)

                        VStack(spacing: 16) {
                            OnboardingCard(
                                icon: "hand.point.up.left.fill",
                                title: "Start with what you already trust",
                                detail: "Search for a few favorite shows, hosts, or topics. Three strong signals are enough to build your first feed."
                            )
                            .staggeredEntrance(index: 3, delay: 0.12)

                            OnboardingCard(
                                icon: "text.bubble.fill",
                                title: "OffScript explains its picks",
                                detail: "You'll see why an episode showed up, whether it fits your day, and what it's connected to."
                            )
                            .staggeredEntrance(index: 4, delay: 0.12)

                            OnboardingCard(
                                icon: "lock.shield.fill",
                                title: "Private by default",
                                detail: "Your listening profile stays local-first and on-device in this first version."
                            )
                            .staggeredEntrance(index: 5, delay: 0.12)
                        }

                        VStack(spacing: 12) {
                            Button("Add 3 shows to build my feed") {
                                onFinish(true)
                            }
                            .buttonStyle(OnboardingActionButtonStyle(prominent: true))

                            Button("Explore the sample library first") {
                                onFinish(false)
                            }
                            .buttonStyle(OnboardingActionButtonStyle(prominent: false))
                        }
                        .staggeredEntrance(index: 6, delay: 0.12)
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 48)
                    .padding(.bottom, 32)
                }
            }
        }
    }
}
```

- [ ] **Step 3: Verify in Simulator**

Check that:
- "OffScript" title has a subtle text gradient (white → orange)
- Background has a visible warm glow in the upper-left
- Cards stagger in with 120ms delays, creating a waterfall reveal
- Icons give each card visual differentiation
- Buttons still navigate correctly
- The overall impression is "designed first impression" not "wall of copy"

- [ ] **Step 4: Commit**

```bash
git add OffScript/OnboardingView.swift
git commit -m "design: onboarding upgrade — gradient title, staggered entrance, card icons, atmosphere"
```

> **Note:** Step numbering reflects the reordering: define the updated `OnboardingCard` (Step 1) before the `OnboardingView` body that calls it with the `icon:` parameter (Step 2).

---

### Task 10: Spatial Variation & Hairline Visibility

**Why:** Consistent 20pt padding everywhere creates monotony. Hairline borders at 8% opacity are nearly invisible, forcing shadows to do all the separation work.

**Files:**
- Modify: `OffScript/AppTheme.swift` (hairline color ~line 30, add spacious padding constant)

- [ ] **Step 1: Increase hairline border visibility**

```swift
// Before:
static let offscriptHairline = Color.white.opacity(0.08)

// After:
static let offscriptHairline = Color.white.opacity(0.12)
```

- [ ] **Step 2: Add a spacious padding tier for hero/lead content**

Add to `OffScriptTheme`:

```swift
enum OffScriptTheme {
    static let pagePadding: CGFloat = 20
    static let spaciousPadding: CGFloat = 28  // NEW — for hero sections and lead cards
    static let sectionSpacing: CGFloat = 28
    static let itemSpacing: CGFloat = 16
```

- [ ] **Step 3: Apply spacious padding to key hero elements**

In `HomeView.swift`, the hero card padding (~line 66):
```swift
// Before:
.padding(.horizontal, OffScriptTheme.pagePadding)

// After:
.padding(.horizontal, OffScriptTheme.spaciousPadding)
```

In `QueueView.swift`, the lead card padding (~line 42):
```swift
// Before:
.padding(.horizontal, OffScriptTheme.pagePadding)

// After:
.padding(.horizontal, OffScriptTheme.spaciousPadding)
```

- [ ] **Step 4: Verify in Simulator**

Check that:
- Card borders are subtly visible (not invisible, not heavy)
- Hero cards have noticeably more breathing room than list items
- The padding difference creates natural emphasis without being jarring

- [ ] **Step 5: Commit**

```bash
git add OffScript/AppTheme.swift OffScript/HomeView.swift OffScript/QueueView.swift
git commit -m "design: increase hairline visibility, add spacious padding tier for hero elements"
```

---

## Execution Order

Tasks are designed to be executed in order (1→10) because later tasks depend on earlier ones:

- **Task 1** (typography) and **Task 2** (colors) establish new tokens used by all subsequent tasks
- **Task 3** (explanation tags) uses `offscriptAccentSecondary` from Task 2
- **Task 4** (hero card) uses `OffScriptExplanationTag` from Task 3
- **Task 5** (stagger animations) creates the modifier used by Task 9
- **Tasks 6-10** can be parallelized if needed, but sequential execution is cleaner

## What This Plan Does NOT Cover

These were identified in the design review but are out of scope for this plan:

1. **Custom font bundling** — Adding a non-system serif font (like Playfair Display or Lora) requires modifying the Xcode project's Info.plist and bundling font files. This is a high-impact improvement but requires Xcode GUI interaction. Recommend as a follow-up.

2. **Scroll-linked parallax effects** — ScrollView offset tracking in SwiftUI is possible but fragile across iOS versions. Recommend prototyping separately.

3. **Player sheet matched geometry transition** — Replacing `.sheet` with a custom `fullScreenCover` + `matchedGeometryEffect` on artwork is complex and risks breaking the existing player presentation logic. Recommend as a dedicated task.

4. **Live Activities / WidgetKit / Siri Suggestions** — Require new extension targets. Deferred from previous phases.

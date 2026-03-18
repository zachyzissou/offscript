# OffScript Shipping Plan

> Generated 2026-03-18 from comprehensive 4-agent audit (feature completeness, ship blockers, docs/backlog, frontend design review)

## Current State

**All 12 feature areas are functionally complete**: Discovery, Subscription, Playback, Queue, Downloads, Recommendations, Onboarding, Settings, Sleep Timer, Chapters/Transcripts, Library, Home Feed. The app builds with zero warnings and zero errors.

**The app is NOT yet shippable** due to 2 hard blockers and several polish gaps.

---

## Phase 0: Ship Blockers (Must fix before ANY release)

- [ ] **0.1 — App Icon images**: `AppIcon.appiconset` has no image files. App Store Connect will reject. Need 1024x1024 icon + dark/tinted variants.
- [ ] **0.2 — PrivacyInfo.xcprivacy**: Missing. Apple requires privacy manifest for apps using UserDefaults (Required Reasons API). Will trigger rejection.

## Phase 0.5: Recommendation Engine Fixes (Functional but needs tuning)

The engine is fully wired — scoring, taste profiles, topic extraction, preference signals, playback events all work end-to-end. But the deep audit found 7 issues that affect recommendation quality:

- [ ] **0.5.1 — NLTagger stopword filter**: No stopword list on noun extraction. Common words ("episode", "show", "time") pollute the tag space, degrading the 26%-weighted topic overlap signal. High impact, low effort.
- [ ] **0.5.2 — Duration scoring should use learned preference**: The 18%-weighted `durationScore()` uses a static curve instead of `averageCompletedDurationMinutes` from the taste profile. The learned value only contributes +0.05 via `prefersShortEpisodes`.
- [ ] **0.5.3 — Fix inverted unfinished-episode affinity**: High abandonment rate (>0.2) boosts unfinished episodes. Should be the opposite — completionists want unfinished surfaced, abandoners don't.
- [ ] **0.5.4 — Cross-section deduplication**: Same episode can appear in Best Next, Quick Wins, and Because You Liked simultaneously.
- [ ] **0.5.5 — Real diversity enforcement**: Current diversity penalty is based on DB fetch order, not content. Need max 2 episodes per podcast per section.
- [ ] **0.5.6 — Genre boost should be proportional**: Flat +0.06 regardless of overlap depth. One matching genre = three matching genres.
- [ ] **0.5.7 — Remove dead EpisodeProfile fields**: `estimatedListeningContext`, `freshnessBucket`, `confidenceScore`, and `summary` are written but never read by scoring. Either use them or remove them.

## Phase 1: TestFlight-Ready (Internal testing)

- [ ] **1.1 — Playback speed persistence**: `playbackRate` resets to 1.0x on restart. Persist via `@AppStorage` or SwiftData.
- [ ] **1.2 — Playback session restoration**: App doesn't resume the currently-playing episode on relaunch. MiniPlayer doesn't appear until user manually plays again.
- [ ] **1.3 — Library sync error feedback**: `syncSubscriptions()` silently swallows errors. Show user-facing toast/banner on sync failure.
- [ ] **1.4 — Image caching**: `AsyncImage` has no disk cache — every appearance triggers a network fetch. Add `URLCache`-backed or third-party caching (Kingfisher/Nuke).
- [ ] **1.5 — Background downloads**: `URLSessionConfiguration.default` used instead of `.background`. Downloads fail if user switches apps mid-download.

## Phase 2: Design Identity (What separates "good" from "memorable")

- [ ] **2.1 — Custom display typeface**: Bundle a distinctive serif (Playfair Display, Libre Baskerville, etc.) for hero/section/display titles. System New York makes the app look like every other dark SwiftUI app. This is the single highest-impact design change.
- [ ] **2.2 — PlayerView rebuild**: The player is the "emotional center" but currently the most generic screen. Custom progress scrubber (replace system Slider), larger transport buttons, artwork-tinted glow behind play button.
- [ ] **2.3 — MiniPlayer → Player transition**: Add matched geometry or hero transition when expanding to full player. Currently a disconnected sheet presentation.
- [ ] **2.4 — Secondary accent color usage**: The warm cream `offscriptAccentSecondary` is defined but barely used. Introduce it for section subtitles, alternate badge tints, creating visual variety beyond orange-for-everything.
- [ ] **2.5 — Onboarding wordmark/lockup**: Replace system serif gradient title with custom typeface wordmark. First impression of brand identity.
- [ ] **2.6 — Player atmosphere animation**: Slow ambient drift on the blurred artwork background (scale oscillation 1.0→1.03 over 8s). Makes player feel alive.
- [ ] **2.7 — Haptic feedback on transport controls**: Add sensoryFeedback to play/pause, skip, and queue actions.
- [ ] **2.8 — Consolidate inline color literals**: Replace `Color.white.opacity(0.08)` etc. with named tokens to prevent drift.

## Phase 3: App Store Ready (Public release polish)

- [ ] **3.1 — VersionedSchema migrations**: Replace destructive migration with proper `VersionedSchema` + `SchemaMigrationPlan`. Current approach wipes all data on schema changes.
- [ ] **3.2 — Background feed refresh**: Add `BGTaskScheduler` for background feed sync. Users currently only get new episodes when foregrounding the app.
- [ ] **3.3 — Network monitoring**: Add `NWPathMonitor` for proactive offline detection and banner/toast.
- [ ] **3.4 — Storage management UI**: Show total download storage used, bulk delete options.
- [ ] **3.5 — Branded launch screen**: Replace auto-generated launch screen with branded splash.
- [ ] **3.6 — Widen Home rail cards**: 196pt → ~220pt, reduce artwork ratio to give text more room.

## Phase 4: Post-Launch Features (Backlog)

- [ ] **4.1 — OPML import/export**: Import from Apple Podcasts, Overcast, etc.
- [ ] **4.2 — Inline transcript rendering**: Display transcripts in-app with synchronized highlighting during playback.
- [ ] **4.3 — Auto-download new episodes**: Per-podcast setting to auto-download on publish.
- [ ] **4.4 — "End of episode" sleep timer option**
- [ ] **4.5 — Batch operations**: Mark all played, download all episodes in a podcast.
- [ ] **4.6 — Skip silence / voice boost**
- [ ] **4.7 — Deep links / URL schemes**: Share episode links, open from other apps.
- [ ] **4.8 — Taste decay / fatigue handling**: Prevent recommendation staleness over time.
- [ ] **4.9 — Cross-podcast content search**: Search episode content, not just iTunes metadata.

---

## Execution Order

```
Phase 0 (blockers)  →  can build & submit
Phase 1 (TestFlight) →  can test with real users
Phase 2 (design)     →  feels like a designed product (can overlap with Phase 1)
Phase 3 (App Store)  →  production-grade release
Phase 4 (post-launch) → ongoing feature development
```

## What's NOT Missing (Confirmed Working)

These are often-assumed gaps that are actually already built:

- RSS feed parsing with conditional sync (ETag/304) ✅
- Exponential backoff on sync failures ✅
- Chapter parsing (RSS + external JSON + description regex) ✅
- On-device topic extraction (FoundationModels + NLTagger fallback) ✅
- Time-of-day adaptive recommendations ✅
- Taste profile with multi-signal scoring ✅
- Download queue with concurrent limits ✅
- Skeleton loading states with shimmer ✅
- Staggered entrance animations ✅
- Grain texture on surfaces ✅
- Accessibility labels on all major controls ✅
- SwiftData relationship integrity (cascade/nullify delete rules) ✅
- Predicate-filtered queries (no more N+1 patterns) ✅
- Zero build warnings ✅

# OffScript Shipping Plan

> Generated 2026-03-18 from comprehensive 4-agent audit. Updated with implementation status.

## Current State

**All 12 feature areas are functionally complete**: Discovery, Subscription, Playback, Queue, Downloads, Recommendations, Onboarding, Settings, Sleep Timer, Chapters/Transcripts, Library, Home Feed. The app builds with **zero warnings and zero errors**.

---

## Phase 0: Ship Blockers — COMPLETE

- [x] **0.1 — App Icon**: 1024x1024 PNG configured for light/dark/tinted.
- [x] **0.2 — PrivacyInfo.xcprivacy**: Added with UserDefaults (CA92.1) and file timestamp (C617.1) declarations.

## Phase 0.5: Recommendation Engine — COMPLETE

All 7 issues resolved (most by Codex, verified in this session):

- [x] **0.5.1 — NLTagger stopword filter**: 60+ English stopwords in `TopicExtractionService`.
- [x] **0.5.2 — Duration scoring uses learned preference**: Gaussian curve centered on `averageCompletedDurationMinutes` with sigma=15.
- [x] **0.5.3 — Unfinished affinity fixed**: Boosts when `< 0.2` (completionists), not abandoners.
- [x] **0.5.4 — Cross-section deduplication**: `usedEpisodeIDs` set tracked across all sections.
- [x] **0.5.5 — Real diversity enforcement**: `diversified()` limits max 2 per podcast, interleaves.
- [x] **0.5.6 — Genre boost proportional**: `0.03 * min(overlapCount, 3)`.
- [x] **0.5.7 — Dead EpisodeProfile fields removed**: `estimatedListeningContext`, `freshnessBucket`, `confidenceScore` deleted.

## Phase 0.75: UI Bugs From Simulator Walkthrough — COMPLETE

- [x] **0.75.1 — Raw HTML in summaries**: Added `String.strippingHTML` via NSAttributedString + regex fallback.
- [x] **0.75.2 — Podcast detail vertical text**: Moved title below artwork at full width.
- [x] **0.75.3 — Button text wrapping**: Added `lineLimit(1)` to both pill button styles.
- [x] **0.75.4 — Episode title dominating viewport**: Moved title below HStack with `lineLimit(4)`.
- [x] **0.75.5 — Preview episodes not tappable**: Now tap to navigate or add to library.
- [ ] **0.75.6 — Search detail sheet artwork clipping**: Minor — artwork partially cut off at top of sheet.
- [ ] **0.75.7 — MiniPlayer tap target overlap**: Minor — tap coordinates overlap with tab bar on some devices.

## Phase 1: TestFlight-Ready — COMPLETE

- [x] **1.1 — Playback speed persistence**: Saved/restored via UserDefaults (`offscript.playbackRate`).
- [x] **1.2 — Playback session restoration**: Last-played episode restored on launch via saved audio URL.
- [x] **1.3 — Library sync error feedback**: Error banner with auto-dismiss in LibraryView.
- [x] **1.4 — Image caching**: `CachedAsyncImage` with `NSCache` + `URLCache` (50MB memory, 200MB disk).
- [x] **1.5 — Background downloads**: `URLSessionConfiguration.background` + AppDelegate completion handler.

## Phase 2: Design Identity — MOSTLY COMPLETE

- [ ] **2.1 — Custom display typeface**: Requires bundling a font file. Deferred — highest-impact design change for future.
- [ ] **2.2 — PlayerView custom scrubber**: System Slider still used. Deferred for player rebuild.
- [ ] **2.3 — MiniPlayer → Player transition**: Still a plain sheet. Deferred for matched geometry work.
- [x] **2.4 — Secondary accent color**: Warm cream applied to section subtitles.
- [ ] **2.5 — Onboarding wordmark**: Requires custom typeface (blocked by 2.1).
- [x] **2.6 — Player atmosphere animation**: Breathing scale oscillation (1.0→1.04 over 8s).
- [x] **2.7 — Haptic feedback**: Added to play/pause (Player + MiniPlayer), skip, and skip-to-next.
- [x] **2.8 — Color token consolidation**: `offscriptFillSubtle` and `offscriptFillLight` tokens replace inline literals.

## Phase 3: App Store Ready — MOSTLY COMPLETE

- [ ] **3.1 — VersionedSchema migrations**: Still using destructive migration. Documented with TODO.
- [ ] **3.2 — Background feed refresh**: No BGTaskScheduler yet. Feeds sync on foreground only.
- [x] **3.3 — Network monitoring**: `NetworkMonitor` with `NWPathMonitor` + offline banner.
- [x] **3.4 — Storage management**: Download storage display + "Clear All" in Settings.
- [ ] **3.5 — Branded launch screen**: Using auto-generated. Low priority.
- [x] **3.6 — Wider Home rail cards**: 196pt → 222pt with 4:3 artwork ratio.

## Phase 4: Post-Launch Features (Backlog)

- [ ] **4.1 — OPML import/export**
- [ ] **4.2 — Inline transcript rendering**
- [ ] **4.3 — Auto-download new episodes**
- [ ] **4.4 — "End of episode" sleep timer**
- [ ] **4.5 — Batch operations** (mark all played, download all)
- [ ] **4.6 — Skip silence / voice boost**
- [ ] **4.7 — Deep links / URL schemes**
- [ ] **4.8 — Taste decay / fatigue handling**
- [ ] **4.9 — Cross-podcast content search**

---

## Summary

| Phase | Status | Items | Done |
|-------|--------|-------|------|
| 0 — Blockers | COMPLETE | 2 | 2 |
| 0.5 — Recommendations | COMPLETE | 7 | 7 |
| 0.75 — UI Bugs | 5/7 DONE | 7 | 5 |
| 1 — TestFlight | COMPLETE | 5 | 5 |
| 2 — Design | 4/8 DONE | 8 | 4 |
| 3 — App Store | 3/6 DONE | 6 | 3 |
| 4 — Post-Launch | BACKLOG | 9 | 0 |
| **Total** | | **44** | **26** |

**Remaining deferred items** (7 items, none blocking TestFlight):
- Custom typeface (2.1) + onboarding wordmark (2.5) — requires font licensing/design decision
- Custom player scrubber (2.2) + MiniPlayer transition (2.3) — player rebuild scope
- VersionedSchema (3.1) — needed before production, not TestFlight
- Background feed refresh (3.2) — nice-to-have for TestFlight
- Branded launch screen (3.5) — cosmetic

## What's Confirmed Working

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
- Playback speed persistence ✅
- Session restoration on relaunch ✅
- Image caching (memory + disk) ✅
- Background downloads ✅
- Network monitoring with offline banner ✅
- Storage management UI ✅
- HTML stripping in summaries ✅
- Zero build warnings ✅

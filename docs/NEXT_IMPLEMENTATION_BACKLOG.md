# OffScript Next Implementation Backlog

## Phase 1: Offline Completion

### Objective
Make downloads and offline playback feel trustworthy in daily use.

### Files
- `/Users/zachgonser/Desktop/OffScript/OffScript/DownloadService.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/LibraryView.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/EpisodeDetailView.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/PlayerView.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/PlaybackController.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScriptTests/OffScriptTests.swift`

### Tasks
1. Add real queued-download semantics with limited concurrency.
2. Reconcile persisted `queued` and `downloading` episodes on launch/configure.
3. Surface active and failed download states in Library.
4. Keep downloaded state synchronized with actual on-disk files.
5. Add regression coverage for interrupted/failed download recovery.

## Phase 2: True Podcast-Player Depth

### Objective
Move from a good player to a genuinely podcast-native player.

### Files
- `/Users/zachgonser/Desktop/OffScript/OffScript/PodcastServices.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/Models.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/PlayerView.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/EpisodeDetailView.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/PlaybackController.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScriptTests/OffScriptTests.swift`

### Tasks
1. Parse first-class feed chapters where available.
2. Add transcript-ready model plumbing.
3. Improve end-of-episode continuity with clearer next-step actions.
4. Make episode detail the best place to understand what you are about to hear.

## Phase 3: Discovery That Feels Curated

### Objective
Make Search and import feel like OffScript, not generic RSS acquisition.

### Files
- `/Users/zachgonser/Desktop/OffScript/OffScript/SearchView.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/CuratedPodcastCatalog.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/ImportProgressView.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/OnboardingFlowView.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/PodcastServices.swift`

### Tasks
1. Add richer show previews with latest-episode context.
2. Expand browse from simple genres into topic/editorial groupings.
3. Improve post-import handoff into first recommendation or first play.

## Phase 4: Recommendation Credibility

### Objective
Make the app feel smart across Home, Queue, Player, and Search.

### Files
- `/Users/zachgonser/Desktop/OffScript/OffScript/RecommendationService.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/TasteProfileService.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/HomeView.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/PlayerView.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/QueueView.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/EpisodeDetailView.swift`

### Tasks
1. Improve fatigue handling and taste decay.
2. Strengthen explanation strings across all surfaces.
3. Use queue and playback behavior more directly in ranking.

## Phase 5: Beta Durability

### Objective
Make the app survive repeated use, bad feeds, and future iteration.

### Files
- `/Users/zachgonser/Desktop/OffScript/OffScript/SettingsView.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/TelemetryService.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScript/SyncCoordinator.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScriptTests/OffScriptTests.swift`
- `/Users/zachgonser/Desktop/OffScript/OffScriptUITests/OffScriptUITests.swift`

### Tasks
1. Expand diagnostics for sync/import/download history.
2. Add deeper regression coverage around onboarding, queue autoplay, sync retries, and offline playback.
3. Reduce remaining runtime warning debt and tighten failure messaging.

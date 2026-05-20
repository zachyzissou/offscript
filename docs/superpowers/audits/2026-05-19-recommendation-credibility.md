# Recommendation credibility — Phase 4 implementation

## What was built

Tightened fatigue handling and taste decay in `TasteProfileService.refresh()` so
that a binge from six months ago no longer dictates today's home rails. The old
recency curve had a hard floor of `0.15` and a half-life of roughly 42 days,
which meant every old completion contributed at least 15% of its weight forever
— directly contradicting the brand promise that "the recommendation engine
works only on signals the user generated themselves." Replaced with a clean
exponential half-life of 14 days, a hard 120-day cutoff (filtered at the
SwiftData fetch level, not in memory), and a per-show "binge dampener" that
applies `1/sqrt(k)` to the k-th passive playback contribution from a single
show so one heavy-rotation podcast can no longer crush every other signal in
`tagScores` / `showAffinity`.

Explicit feedback (Like / More / Less / NotInterested) is deliberately NOT
binge-dampened — those taps are intentional and the user expects them to read
as first-class. Negative passive signals (`skippedQuickly`, `abandoned`) are
also not dampened — a real-world finding that's important for moderation: if a
listener skips a show 10 times in a row, the dampener should not let that show
keep recommending itself.

## Why this sub-task (over the other two)

1. **Decay was the brand promise.** "Credibility" in the user's mind is "this
   thing reads my current taste, not a fossil." The floor + 42-day half-life
   made fossilized signal mathematically permanent.
2. **#3 (queue / playback as signal) is blocked by a scaffolding gap I
   discovered but cannot fix this round** — see "Strategic finding" below. Even
   if I retuned the playback-event scoring, no playback events besides
   `.completed` are ever emitted, so the retune would be cosmetic.
3. **#2 (explanation strings) already shipped a strong pass in 2.4** under
   "Home, Discovery, and Player recommendation cards now use authored local
   signal explanations." Further composition here is tactical — diminishing
   returns for one session.

## Specific changes

### `OffScript/TasteProfileService.swift`

- **New `decayHalfLifeDays = 14` constant** with a doc comment explaining the
  brand-promise rationale. The previous formula was `max(0.15, exp(-days/60))`
  — a hard floor plus a long half-life. Both pieces conspired to keep old
  signals alive.
- **New `signalCutoffDays = 120` constant.** Past this, `recencyWeight`
  returns 0 exactly. 120 gives 30d headroom over the 90-day cutoff that
  `RecommendationService.homeSections` and `playerSuggestions` already enforce
  on their own fetches, so signals don't snap to zero right at the edge of the
  rest of the system's window.
- **Fetch-level cutoff for `PlaybackEvent` and `PreferenceSignal`** via
  `#Predicate { $0.date >= cutoffDate }`. Previously this method loaded the
  full history and leaned on the (broken) decay floor to dampen it. The
  cutoff is now an enforced contract, not a soft hint.
- **Binge dampener (`1/sqrt(k)`)** applied to passive playback contributions
  in tag-score AND show-score accumulation. Events are sorted newest-first so
  the most recent completion gets full weight and the 20th gets ~22%. Explicit
  preference signals bypass the dampener entirely.
- **Recency curve rewritten** to a clean half-life formulation:
  `exp(-ln(2) * days / decayHalfLifeDays)`. Returns 0 past the cutoff. No
  floor.
- **`recencyWeight(for:)` made internal** (was private). The contract is now
  testable from `OffScriptTests` once that file is free; the function is also
  a load-bearing piece of the brand promise and deserves to be inspectable.

### What I deliberately did NOT change

- **`RecommendationService.swift`**: untouched this round. The scoring there
  is already in good shape and changes would compound risk. The decay
  improvements flow through naturally because `RecommendationService` reads
  the refreshed `UserTasteProfile`.
- **`EpisodeBriefingView.swift`**: unrelated to recommendation explanations
  (it's the Apple Intelligence pre-listen summary, not the WHY-this-card
  copy). No edits.
- **Existing weight constants** (`preferenceWeight`, `playbackTagWeight`,
  `playbackShowWeight`): left alone. The bug was in the decay curve and the
  lack of a binge cap, not in the per-event weights.

## Tests to add in follow-up

(All deferred — `OffScriptTests/OffScriptTests.swift` is owned by the Phase 3
subagent this round.)

1. `func decayHalfLifeIs14Days()` — assert
   `TasteProfileService.recencyWeight(for: Date().addingTimeInterval(-14*86400))`
   returns `0.5 ± 0.01`. Pins the half-life contract.

2. `func decayHasNoFloorPastCutoff()` — assert
   `TasteProfileService.recencyWeight(for: Date().addingTimeInterval(-121*86400))`
   returns exactly `0.0`. Pins the hard-cutoff contract; the old code returned
   `0.15` here forever.

3. `func decayReturnsOneAtZeroAge()` — assert
   `TasteProfileService.recencyWeight(for: .now)` returns `1.0 ± 0.001`. Sanity
   check that an in-the-moment signal isn't pre-dampened.

4. `func tasteProfileBingeDampenerCapsSingleShowDominance()` — 20 .completed
   events on Show A (all recent) vs. 1 like on Show B. Today's code lets Show
   A's tagScore = 20 * 1.5 = 30 vs. Show B's 5.0. With the dampener Show A's
   contribution sums to `1.5 * sum(1/sqrt(k) for k in 1...20) ≈ 11.3`, still
   above Show B but no longer 6x. The right assertion: Show B is in the top
   3 tags despite being outnumbered 20:1. (Without the dampener, Show B would
   be drowned out entirely.)

5. `func tasteProfileExplicitSignalsAreNotBingeDampened()` — 5 `moreLikeThis`
   on the same show should each contribute 8.0 fully (sum = 40). Pin that
   tapping the button 5 times still reads as 5x weight.

6. `func tasteProfileNegativeSignalsAreNotBingeDampened()` — 10 `skippedQuickly`
   on Show X should fully accumulate (sum = -14.0 for tag, -16.0 for show), so
   `negativeShowWeights` correctly suppresses the show in `RecommendationService`.

7. `func tasteProfileRefreshIgnoresEventsOlderThanCutoff()` — insert a single
   `.completed` event 130 days old and a fresh `moreLikeThis` on different
   tags. The old tag must not appear in `topTags` (previously it would, at
   `0.15` weight forever).

## Strategic finding

**The bigger Phase-14/15-style "scaffolding-not-connected" pattern in this
area is in `PlaybackEvent` emission, not decay.** While investigating sub-task
#3 (queue/playback as ranking signal), I found:

- `PlaybackEvent.Kind` has eight cases: `started`, `completed`, `skippedQuickly`,
  `seekedForward`, `seekedBackward`, `abandoned`, `advancedFromQueue`, `resumed`.
- `TasteProfileService.playbackTagWeight` and `playbackShowWeight` score all
  eight cases with carefully tuned positive AND negative weights (skippedQuickly:
  -1.4, advancedFromQueue: +0.9, etc.).
- `RecommendationService.negativeEvidence` reads `skippedQuickly` and
  `abandoned` to suppress adjacent recommendations.
- **The only `PlaybackEvent` ever instantiated in the codebase is
  `.completed`** (`PlaybackController.swift:475` is the sole call site).

Result: ~75% of the playback-event scoring machinery is dead code reading from
a stream that never carries the relevant events. Negative-signal suppression
based on "user skipped this in the first 30 seconds" sounds powerful but never
fires because no `.skippedQuickly` event is ever emitted. The
`advancedFromQueue` positive signal (which we want to use to credit the queue
flow more directly) is never emitted either.

**The right fix is in `PlaybackController` and `QueueService`**, not in
`RecommendationService` / `TasteProfileService`:

- Emit `.skippedQuickly` when the user scrubs forward past 80% of the episode
  within the first 30 seconds of play, or hits "next" before 30 seconds.
- Emit `.abandoned` when an episode is partially played but not touched for
  N days, OR when the user explicitly removes it from the queue mid-play.
- Emit `.advancedFromQueue` when the queue auto-advances after a completion
  (`PlaybackController.observePlaybackCompletion` line 489 calls
  `skipToNextInQueue()` — that's exactly the moment).
- Emit `.resumed` when a play() happens with `playedPosition > 60`.
- Emit `.seekedForward` / `.seekedBackward` when the user uses the skip
  controls (these are mostly diagnostic but help us learn pacing tolerance).

That work is outside this session's file ownership but would do more for
recommendation credibility than any further tuning of the decay curve —
it would turn the scoring code from "elegant theory operating on the wrong
inputs" into a working signal chain.

## Deferred

### Sub-task #2: Strengthen explanation strings

Already strong after 2.4's authored-explanation pass. The remaining vague
fallbacks I'd target next:

- In `RecommendationService.homeSignal` (line 620), `"Matches your saved
  signal: \(sample)"` for `tag match` — could be sharpened to `"You finished N
  episodes with \(sample)"` if we thread the completed-count through the
  evidence. The data is in `completedShowCounts` but isn't surfaced in the
  string today.
- In `RecommendationService.scoreWithExplanation` (line 754), `"Fits your
  recent interest in \"\(topTag)\""` — could include WHY that tag is "recent
  interest" (e.g., "...from 3 episodes this month"). Requires threading
  per-tag recency.
- `"Available from \(podcast)"` (line 791) is the genuinely-vague fallback the
  backlog calls out. It should be very rare, but when it fires it reads as
  filler — worth gating to "show only if literally no other evidence" and
  rephrasing.

### Sub-task #3: Queue and playback behavior as ranking signal

See "Strategic finding" above — the meaningful work here is in
`PlaybackController` and `QueueService` (event emission), not in the scoring
code. Specific deferrals:

- Emit `.advancedFromQueue` when queue auto-plays the next item.
- Emit `.skippedQuickly` on early-abandonment patterns.
- Emit `.resumed` when resuming a partially-played episode.
- Once those events flow, the existing TasteProfileService scoring + the
  binge dampener shipped this round combine to make queue completion +
  resume-from-pause first-class evidence.

### Schema-touching ideas (intentionally out of scope)

- `Episode.lastPlayedAt` would let scoring favor "you played this kind of
  episode recently" directly without round-tripping through tag scores. Not
  in scope: schema migration is a multi-session investment.
- A `dailyListeningWindow` profile field (when the user typically listens)
  would let us drop a "you usually listen mornings — this is a morning-fit
  short episode" rail. Schema work + sensor of `played at time-of-day` data
  collection.

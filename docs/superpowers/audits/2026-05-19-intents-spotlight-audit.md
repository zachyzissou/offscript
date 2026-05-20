# App Intents + Spotlight audit — 2026-05-19

Audit of `OffScript/OffScriptAppIntents.swift` and `OffScript/SpotlightIndexer.swift`
on branch `audit/expanded-surface-2026-05-19` (base HEAD `e44b0cd`).

## Intents declared

After this audit's fixes, five intents are declared. The first four existed
prior to the audit; `PlayEpisodeIntent` was added during it.

| Intent | Title | Has dialog | Donates | Shortcut surfaced |
|---|---|---|---|---|
| `ResumeListeningIntent` | "Resume Listening" | yes (`ProvidesDialog`) | no | yes |
| `SkipForwardIntent` | "Skip Forward 30 Seconds" | yes | no | yes |
| `PauseListeningIntent` | "Pause OffScript" | yes | no | yes |
| `PlayNextInQueueIntent` | "Play Next in Queue" | yes | no | yes |
| `PlayEpisodeIntent` (added) | "Play Episode" | yes | no | yes (with `$episode` parameter binding) |

All five have both `static let title: LocalizedStringResource` and a
non-empty `IntentDescription`. All return `some IntentResult & ProvidesDialog`
with a user-visible string. All have `openAppWhenRun = false` and run in the
intent extension process; they touch the shared `PlaybackController.shared`
singleton and open their own `ModelContext` via `OffScriptAppIntents.makeContext()`
when needed.

## AppShortcutsProvider

`OffScriptShortcuts: AppShortcutsProvider` is declared and registers all five
intents with `shortTitle`, `systemImageName`, and natural-language `phrases`
templated on `\(.applicationName)`. After the audit, `PlayEpisodeIntent` is
surfaced with a parameter-binding phrase `"Play \(\.$episode) in \(.applicationName)"`,
which lets Siri prompt the user to pick an episode by title.

Shortcut registration is complete relative to the intents that exist.

## AppEntity definitions

Before the audit: **none**. No `Episode` or `Podcast` was exposed as an
addressable noun, so Siri could only offer parameterless verbs.

After the audit:

- `EpisodeEntity: AppEntity` with `id`, `title`, `podcastTitle`, and a
  two-line `DisplayRepresentation` (title + subtitle).
- `EpisodeEntityQuery: EntityQuery` resolving by UUID and returning the
  newest 25 subscribed-show episodes as `suggestedEntities()` for the
  Shortcuts editor.
- No `PodcastEntity` yet — deferred because the existing Spotlight
  pipeline only indexes episodes, and adding a podcast-noun without
  corresponding indexing and deep-link routing is half a feature.

## Spotlight indexing

**What's indexed:** episodes only, scoped to `podcast.isSubscribed == true`.
Newest `maxEpisodesToIndex = 500` by `pubDate` descending. Batched at 200
per `indexSearchableItems` call to bound memory. Debounced by a 24-hour
`indexTTL` keyed on `offscript.spotlightLastIndexedAt` in `UserDefaults`.
Per-item `expirationDate = +30 days` ages out stale entries automatically.

**Fields covered** (after the audit; new fields marked **+**):

| Field | Value |
|---|---|
| `title` | `episode.title` |
| **+** `displayName` | `episode.title` |
| `contentDescription` | `episode.summary?.strippingHTML` |
| `artist` | `episode.podcast.author ?? episode.podcast.title` |
| `album` | `episode.podcast.title` |
| `containerTitle` | `episode.podcast.title` |
| **+** `containerIdentifier` | `episode.podcast.id.uuidString` |
| `contentCreationDate` | `episode.pubDate` |
| **+** `addedDate` | `episode.pubDate` (drives recency ranking) |
| `duration` | `episode.duration` as `NSNumber` |
| `thumbnailURL` | `episode.artworkURL ?? episode.podcast.artworkURL` |
| `keywords` | `["podcast", "OffScript", podcast.title]` + author when present |
| **+** `contentURL` | `offscript://episode/<uuid>` |
| `uniqueIdentifier` | `episode.id.uuidString` |
| `domainIdentifier` | `"com.offscript.episodes"` |
| `expirationDate` | now + 30 days |

**Deep-link round-trip:** `ContentView.swift` wires
`.onContinueUserActivity(CSSearchableItemActionType)`, extracts
`CSSearchableItemActivityIdentifier`, reconstructs
`offscript://episode/<uuid>`, and hands it to `DeepLinkRouter.handle(_:in:)`.
`DeepLinkRouter` fetches the `Episode` by UUID via `FetchDescriptor` and
calls `PlaybackController.shared.load(_:in:)` (not `play()`) so the user
lands on the player UI without surprise audio. Verified end-to-end on
inspection; no broken pieces.

**De-index on unsubscribe / delete:**
`PodcastUnsubscribeService.unsubscribe(...)` calls
`SpotlightIndexer.deindexEpisodes(ids:)` (line 67), passing the collected
episode UUIDs of the unsubscribed show. `SpotlightIndexer.deleteAll()` and
`invalidateIndex()` exist as bulk-reset escape hatches. No de-indexing on
single-episode delete — there's no episode-delete flow surfaced in the UI
(history retention is intentional for the taste profile), so this is
consistent rather than a gap.

**Cap:** 500 episodes total — well under Spotlight's per-app practical
ceiling. Batched correctly.

## Donations

**No `donate()` calls anywhere in the project** — confirmed by
`grep -rn 'donate\|IntentDonationManager' OffScript/`. The system therefore
has no signal to predict which intent the user is likely to invoke in any
given context: no Lock Screen / Spotlight prediction surfaces, no Siri
Suggestions, no smart-stack hints.

Fixing this requires call-sites in `PlaybackController` (when the user
starts an episode, donate `PlayEpisodeIntent` with the entity; when the
user pauses, donate `PauseListeningIntent`; etc.) — out of scope for this
audit. **Deferred.**

The `ResumeListeningIntent` fallback path reads
`UserDefaults.standard.string(forKey: "offscript.lastEpisodeAudioURL")`,
but **nothing in the codebase writes that key** (also verified by grep).
The in-memory path through `PlaybackController.shared.currentEpisode`
works, but on a cold-start where the controller hasn't been hydrated yet,
the intent will always fall through to "Nothing to resume yet" even when
the user has a perfectly valid last-played episode. Fixing this needs a
write in `PlaybackController.play(_:in:)` — **deferred**.

## Classification

**MUST-FIX**
- *(none — all critical issues require touching out-of-scope files)*

**GAP**
- No `donate()` calls anywhere → the system can't learn user habits or
  surface predictive shortcuts. Highest-leverage missing piece.
- `ResumeListeningIntent` cold-launch fallback reads a UserDefaults key
  that no writer populates. Effectively dead code on cold launches.
- No `PodcastEntity` and no podcast-level Spotlight indexing → users
  searching for a show by title in Spotlight get episode results only,
  ranked by recency; the show's home page is unreachable from Spotlight.
- Deep-link round-trip for Spotlight taps is `load()` (not `play()`),
  which is intentional but could optionally honor a per-user "auto-play
  Spotlight result" preference.

**STRATEGIC**
OffScript's Apple-integration surface is **competent but undersold**.
The structural pieces are right — there's a real intents file with a
shared `ModelContext` factory, an `AppShortcutsProvider` that registers
natural phrases, a Spotlight indexer that batches and debounces, and a
DeepLinkRouter that round-trips Spotlight taps. That's already past the
threshold most third-party podcast apps clear. But the surface is **flat**:
no entities (until this audit), no donations, no widgets shown driving
intents, no Live Activity intent buttons, no Control Center widget, no
App Shortcut tinted symbols. The platform offers a deep pyramid here —
`AppEntity` → `EntityQuery` → `OpenIntent` / `AppIntent` parameter
binding → `IntentDonationManager` → predictive surfaces → focus filters
→ Siri suggestions on the Lock Screen → Apple Watch complications. OffScript
sits on the bottom two rungs. With the two fixes from this audit it now
sits on rung three (parameterized intent + entity). The single highest-ROI
next step would be donating intents from `PlaybackController.play(_:)` and
the unsubscribe/subscribe flows — that unlocks four predictive surfaces
with a few lines of code. Treat this as a deliberately-conservative
foundation that's overdue for its second act, not a neglected surface.

## Fixes applied

- `1cd9a35` — `fix(spotlight): enrich episode CSSearchableItem metadata`
  (adds `displayName`, `containerIdentifier`, `addedDate`, author keyword,
  `contentURL` deep link).
- `c4604f2` — `fix(intents): add EpisodeEntity + parameterized PlayEpisodeIntent`
  (introduces an `AppEntity` for episodes, an `EntityQuery` with suggestions,
  and a parameter-bound `PlayEpisodeIntent` registered with Siri phrases).

Both fixes build clean against the iOS Simulator destination.

## Deferred

- **Donate calls.** Add `IntentDonationManager.shared.donate(intent:)` from
  `PlaybackController.play(_:in:)` (donate `PlayEpisodeIntent` with the
  episode entity), `PlaybackController.togglePlayPause()` (donate
  `PauseListeningIntent` / `ResumeListeningIntent`), and the unsubscribe
  flow (de-donate). Requires touching `PlaybackController.swift`.
- **`ResumeListeningIntent` cold-launch fix.** Persist
  `offscript.lastEpisodeAudioURL` from `PlaybackController.play(_:in:)`
  so the existing fallback in `ResumeListeningIntent.perform()` actually
  has data to read. Out of scope.
- **`PodcastEntity` + podcast Spotlight indexing.** Add a podcast `AppEntity`,
  index podcasts under a second domain (`com.offscript.podcasts`), and
  teach `ContentView.onContinueUserActivity` to inspect the
  `domainIdentifier` (currently it builds an `offscript://episode/` URL
  unconditionally). Touches `ContentView.swift`.
- **Open-app intents.** `OpenLibraryIntent`, `OpenQueueIntent`,
  `OpenSearchIntent` with `openAppWhenRun = true` so users can ask Siri
  to land them on a specific tab. Mostly contained in the intents file
  but needs a stable deep-link contract — already exists at
  `offscript://tab/<name>`, so the work is small. Skipped here to keep
  the audit focused; trivial follow-up.
- **Single-episode delete de-indexing.** No UI path for it today, but
  worth wiring defensively if/when episode delete is added.

## Phase 11 — donate() integration resolved

The top finding ("zero `donate()` calls in the codebase") is now closed.
Donations land at the user-action point after the action successfully
takes effect — donating an intent that didn't run pollutes the iOS
prediction model.

Commit: `9d25794` (`feat(intents): donate playback intents at user-action points`).

| Intent | Donation site | Trigger |
|---|---|---|
| `PlayEpisodeIntent` | `OffScript/PlaybackController.swift:257` (`play(_:in:)`) | After `AVPlayer.play()` succeeds on episode start |
| `ResumeListeningIntent` | `OffScript/PlaybackController.swift:341` (`togglePlayPause()`) | User-initiated resume (paused → playing) |
| `PauseListeningIntent` | `OffScript/PlaybackController.swift:339` (`togglePlayPause()`) | User-initiated pause (playing → paused) |
| `SkipForwardIntent` | `OffScript/PlaybackController.swift:355` (`seek(by:)`) | Positive seek only — we don't have a `SkipBackwardIntent` |
| `PlayNextInQueueIntent` | `OffScript/PlaybackController.swift:490` (auto-advance branch of `observePlaybackCompletion()`) | Episode completion auto-advance, guarded on `currentEpisode` actually changing |

Helper plumbing (`donate<Intent>(_:label:)` and per-intent wrappers) lives
at `OffScript/PlaybackController.swift:752-786`. All donations run inside
a detached `Task` so Siri index writes never block playback; failures are
logged through a dedicated `OSLog` category (`com.offscript` /
`IntentDonation`) so prediction-pipeline regressions remain diagnosable
from sysdiagnose without swallowing errors.

System-induced state changes (interruptions in
`handleInterruption(typeValue:optionValue:)`, route changes in
`handleRouteChange(reasonValue:)`) call `player.pause()` directly rather
than going through `togglePlayPause()`, so they correctly bypass
donation — pulling out the headphones must not teach Siri "the user
likes to pause around 8pm."

Verification: 139/139 unit tests still pass; debug build green against
`platform=iOS Simulator,id=F623EB2A-1CF4-405E-9583-6B0EE2053FDE` (iPhone
17 Pro · iOS 26.5).

Not addressed in this phase (separate deferred items above still stand):

- Unsubscribe-flow de-donation (no observed UI complaint yet).
- Cold-resume persistence of `offscript.lastEpisodeAudioURL` — still
  dead-code per the original audit; donation does not change that.
- Manual user-initiated next-track via the remote `nextTrackCommand` /
  in-app forward button is intentionally NOT donated to
  `PlayNextInQueueIntent` — only the auto-advance path is, matching the
  spec's framing of "play next thing" as a system-driven prediction
  signal. Revisit if Siri Suggestions under-surfaces the intent.

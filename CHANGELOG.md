# Changelog

All notable changes to OffScript. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html) — though TestFlight builds carry a date-stamped build number such as `YYYYMMDDNN` layered on top of the marketing version.

## [Unreleased]

### Added — UI QA swarm coverage
- **New `-offscript.debugWipeLibrary YES` launch arg wipes the SwiftData store before seeding** so UI tests that need a guaranteed-empty Library or Queue can launch deterministically regardless of prior simulator state. Documented in `docs/TEST_MATRIX.md`. Closes #177.
- **Library empty state now has UI smoke coverage** that asserts `● NO CHANNELS TUNED` and "Your library is empty" render on a freshly-wiped store, pinning the day-one Library experience against future header refactors (#115).
- **Queue empty state now has UI smoke coverage** that launches directly into the Queue tab on a fresh install, asserts `● QUEUE EMPTY`, the "Nothing queued yet" headline, and the `→ EXPLORE SHOWS` escape hatch render — pinning the empty-state copy heavy listeners hit on day one against future Queue refactors (#126).
- **Settings sign-out confirmation now has UI smoke coverage** that opens Settings, taps the destructive sign-out toggle when present, asserts the `CONFIRM · SIGN OUT` panel appears, cancels it, and verifies Settings stays alive and the runner stays foregrounded — pinning the destructive-dialog dismiss path against the build-51 class of Settings crashes (#114).
- **Podcast detail load errors now expose a `↻ RETRY` Tuner key** instead of just a static red `LOAD ERROR · …` label, so a user who hit a transient SwiftData fetch failure on the channel detail page can recover without backing out and re-entering (#115).
- **Library Import key now has UI smoke coverage** that taps the IMPORT affordance from a launched Library tab, asserts the `IMPORT · ADD CHANNELS` sheet appears, and verifies tapping `Close import` returns to Library — pinning the OPML/paste-URL entry point against header refactors (#115).
- **Hero recommendation card play/queue keys, hero feedback chips (LIKE/MORE/LESS/HIDE), and the starter-pick `+ ADD` row now expose explicit VoiceOver labels** that include the episode or pick title, so the home recommendation surface no longer falls back to the visible mono text and decorative arrow glyphs (#127).
- **LibraryView buttons now expose explicit VoiceOver labels** for the channel directory rows, scope/sort/density mode keys, episode filter chips, podcast detail website/cancel keys, per-row play/queue keys, and the `+ LOAD 100 MORE` pager so VoiceOver users can disambiguate every action by show or episode title (#127).
- **Settings playback-rate reset, signal rebuild, sign-out, and the sign-out confirmation Cancel/Confirm pair now exposes explicit VoiceOver labels** with hint copy on the destructive sign-out action, so destructive Settings flows can be operated with VoiceOver without guessing what each Tuner key does (#127).
- **Queue lead-strip `→ PLAY` / `× REMOVE` actions and the list `× CLEAR ALL` key now expose explicit VoiceOver labels** that include the episode title (or queued-episode count for the bulk clear), so the queue surface no longer reads ambiguous "Button" / mono visible text only (#127).
- **Search topic chips, recent-search rows, the clear-recents key, and discovery result row buttons (`+ ADD TO LIBRARY`, `→ WEBSITE`) now expose explicit VoiceOver labels** that include the topic / search term / podcast title, so Search no longer exposes ambiguous "Button" / `arrow.up.left` SF Symbol-name labels (#127).
- **Episode Detail action and feedback buttons now expose explicit VoiceOver labels** (`Play <title>` / `Resume <title>` / `Now playing <title>`, `Add <title> to queue` / `Already queued`, `Retry download for <title>`, `Like <title>` / `Liked`, `Not for me — show fewer episodes like <title>` / `Marked not for me`) and decorative SF Symbols inside those buttons are now hidden from accessibility, so VoiceOver reads one intentional label per action instead of the icon name plus the mono visible text (#127).
- **Repository now has a canonical [`docs/TEST_MATRIX.md`](docs/TEST_MATRIX.md)** mapping every major surface (onboarding, import/export, library, search, queue, player, background playback, settings, identity/iCloud, recommendations, widgets/Live Activity, release/TestFlight visibility) to its automated test, simulator manual command (with launch arguments), and real-device-only flow — so agents and sub-agents can plan regression sweeps and PR verification without relying on conversational memory (#116).
- **Settings UI coverage now opens the config panel from the Library tab** in addition to the existing Home entry point, locking in the Library Settings open path that the build 51 crash report flagged (#114).
- **Settings UI coverage now drives a present → dismiss → re-present cycle** to surface SwiftUI sheet lifecycle crashes that only appear after a Settings sheet has been opened, dismissed, and reopened (#114).
- **Large-library UI smoke coverage now seeds a deterministic 258-show library** and launches directly into Library, giving the 250+ show scrolling case a repeatable simulator test instead of a manual-only complaint.
- **Settings UI coverage now opens the config panel against a deterministic 258-show library** and verifies simulator iCloud status stays recoverable instead of crashing.
- **Debug large-library seeding now resets stale simulator data when an explicit library size is requested**, so visual audits and UI tests are not polluted by previous sample stores.
- **Large-library UI coverage now verifies alphabet directory jumps** by tapping the `Z` key in a 258-show Library and asserting the list scrolls to the `Z` section.
- **Home recommendations now have a dedicated “More From Shows You Chose” lane** so explicit like/more-like-this show intent is not mislabeled as passive completion affinity.

### Changed — Tuner UI conformance
- **Visible mono duration glyphs now expose spoken VoiceOver labels** — every "1H 5M" / "32M" `TunerLabel` rendered for sighted users now ships with `.accessibilityLabel(EpisodeDurationFormatter.spoken(...))` so VO speaks "1 hour 5 minutes" / "32 minutes" instead of letter-by-letter "one h five m". Also threaded the spoken formatter through Player UP NEXT's combined a11y label. Affects PlayerView (DURATION readout, UP NEXT badge + label), QueueView (LeadStrip header, queue row badge).
- **PodcastDetail and Home rail row a11y labels now use VO-friendly metadata** — the rich VO labels were interpolating the visible mono `metadata` ("E12 · MAY 1, 2026 · 1H 5M"); VoiceOver speaks the "·" separator literally and pronounces "1H 5M" as letters. New `voiceOverMetadata` variants drop uppercasing and the "·" separator, expand "S2 E5" to "Season 2 Episode 5", and use a new `EpisodeDurationFormatter.spoken(_:)` ("1 hour 5 minutes" / "32 minutes") so the readout pronounces naturally. Visible mono metadata is unchanged. Applies to PodcastEpisodeTunerRow and HomeView TunerRailCard.
- **Home rail card NavigationLinks now read as one VoiceOver stop** — `Open <title> from <podcast>, <reason>, <metadata>` instead of five separate stops for artwork + podcast eyebrow + title + reason + metadata. Sibling Play / Queue action keys keep their own a11y elements. Mirrors TunerLibraryCard (#266) and PodcastEpisodeTunerRow (#265).
- **TunerLibraryCard recommendation NavigationLink now reads as one VoiceOver stop** — `Open <title> from <podcast>, <reason>` instead of four separate stops for artwork, podcast eyebrow, episode title, and recommendation reason. The sibling Play / Queue action keys keep their own a11y elements. Mirrors PodcastEpisodeTunerRow (#265) and SearchResultRow (#261).
- **PodcastDetail episode rows' NavigationLink now reads as one VoiceOver stop** — `Open <title>, <rank>, <metadata>, <summary>` instead of three or more separate stops. The chronological rank glyph is folded in only when the feed lacks `<itunes:episode>` (so the metadata "E<n>" wouldn't already encode it); the stripped summary is appended when the row shows description text so VO users don't lose context. The sibling Play / Queue / More action keys keep their own a11y elements. Mirrors the combine pass on EpisodeDetail FROM CHANNEL chip (#249) and SearchResultRow (#261).
- **Library SHOWS · DIRECTORY rows now expose rich VoiceOver labels** — `Open channel <NN>, <title>, by <author>, <X> in progress, <Y> unplayed, sync failed` instead of the prior bare `Open <title> channel`. The parent row Button's `.accessibilityLabel` was clobbering every child, so VO users could not hear the channel number, in-progress / unplayed counts, or the `● SYNC FAILED` chip that sighted users see next to the title. The channel number is zero-padded to match the visible mono gutter; empty-author and zero-in-progress clauses are dropped so the label stays clean for healthy rows. Sync-failure predicate centralized on `LibraryDirectoryRow.hasSyncFailure` so the chip and VO label can't drift.
- **PlayerView UP NEXT descriptive zone now reads as one VoiceOver stop** — `Up next, <title>, from <podcast>, <duration>` instead of four separate stops for artwork, podcast eyebrow, episode title, and duration. The `→ PLAY` and `× DROP` keys keep their own a11y elements so VO can still act on the up-next item independently. Mirrors the combine pass on SearchResultRow (#261) and HomeStarterRail (#262).
- **HomeStarterRail descriptive zone now reads as one VoiceOver stop** — `Pick <rank>, <title>, by <author>, <summary>` instead of four separate stops per row. Empty-author and empty-summary clauses are dropped so VO doesn't read dangling fragments. Mirrors the combine pass shipped for SearchResultRow (#261) and TunerDiscoveryRail (#256). Action key keeps its own state-aware a11y label.
- **SearchResultRow descriptive zone now reads as one VoiceOver stop** — `Result <rank>, in library, <title>, by <author>` instead of four separate stops for rank, status chip, title, and author. For a 25-result list that drops the descriptive walk from ~100 stops to 25; the `+ ADD TO LIBRARY` and `→ WEBSITE` action keys keep their own a11y elements (so the full per-row count becomes one descriptive stop + up to two action stops). When `result.author` is empty (TopPodcastsService fallback) the trailing "by …" clause is dropped so VO doesn't read a dangling "by". Mirrors the combine pass applied to LibraryDirectoryRow (#246) and PodcastEpisodeTunerRow.
- **Search now supports pull-to-refresh** — the gesture re-runs the active query so a user can dismiss a stale `● SEARCH ERROR` strip or pull in newly catalogued shows without re-typing. Idle (no query) refresh is a no-op so the gesture stays harmless on the starter-topics + recent-searches landing. Mirrors the pull-to-refresh added to Home (#240) and Library + PodcastDetail (#239).
- **Search RECENT SEARCHES `× CLEAR` now requires confirmation** — first tap opens an inline `● CONFIRM CLEAR` strip with `× CONFIRM` / `CANCEL` keys, matching the Queue × CLEAR ALL and Library × UNSUBSCRIBE patterns. An accidental tap on × CLEAR no longer wipes the user's recent-search history without a second deliberate action. Confirm strip count text pluralizes for single-entry histories.
- **Queue rows are now tappable to open Episode Detail** — rank + artwork + title/metadata wrapped in a NavigationLink while the play / move / remove action buttons stay siblings. Matches the PodcastEpisodeTunerRow pattern; gives queued-item access to chapters, transcripts, and feedback without leaving the Queue tab. NavigationLink VoiceOver label is title + podcast aware (`Open <title> from <podcast> detail`) and `OffScriptUITests.testQueueRowOpensEpisodeDetail` asserts a seeded queue row pushes EpisodeDetailScreen.
- **Search empty `NO MATCHES` state now exposes a `× CLEAR SEARCH` recovery key** — one-tap reset back to the starter-topics + recent-searches landing state. Mirrors the clear-filter affordances on PodcastDetail (#208) and Library directory (#220).
- **Home discovery rail now owns per-pick import errors** — the same #214 fix applied to `HomeStarterRail` is now also on `TunerDiscoveryRail`. Failed `+ TUNE` flips to `✗ FAILED · RETRY` in `offscriptFnRecord` instead of overwriting a single global error strip. Per-pick in-flight tracking via `importingIDs: Set<String>` so concurrent taps both keep their `○ TUNING…` state.
- **HeroTunerCard `…` more-actions key now reads as `More actions for <title>`** (was generic `More actions`) and meets 44pt tap target (was 32pt visible).
- **EpisodeCompactCard's `+ QUEUE` and `✓ PLAYED` inline actions now expose title-aware VoiceOver labels** — `Add <title> to queue` / `Mark <title> as played`. Without this they read only the mono visible text without episode context.
- **CardComponents queue button now uses title-aware VoiceOver label** — last surface still using generic `Already queued`. Now reads `<title> already queued` consistent with #224's pass.
- **LibraryImportSheet `BACK` button now reads as `Back to import menu`** instead of `ChevronLeft, BACK` two-stop readback. Also bumped to 44pt min height.
- **Library OPML batch import strip's running header now reads as one VoiceOver stop** — `Importing 12 of 50 feeds in background` instead of two separate stops for the eyebrow and count. Cancel button stays its own a11y element.
- **Settings sign-in identity readouts (`CREDENTIAL` / `CLOUD`) now read as a single VoiceOver element each.** Same `accessibilityElement(children: .ignore)` pattern as #245 / #246 / #247.
- **EpisodeDetail `FROM CHANNEL` chip now reads as one VoiceOver action** — `Open <podcast title> channel`. Was multi-stop (`From Channel`, podcast title, `chevron.right`). Hides the decorative chevron and combines the rest via `accessibilityElement(children: .ignore)`.
- **Decorative chevrons on PodcastShelfRow and Settings rate-picker disclosure now hidden from VoiceOver.** The "ChevronRight" / "ChevronUp" SF symbol names were leaking into a11y readback as noise alongside the meaningful row labels.
- **TunerReadout (Episode detail's `DUR / POS / STATE` hero readouts) now reads as one VoiceOver element per readout** — `Duration 38 minutes` instead of separate `Duration`, `38`, `minutes` stops. Combines tag + value + optional unit via `accessibilityElement(children: .ignore)`. Same pattern as the Library and Settings stats fixes from #245 and #246.
- **Library header stats (SHOWS / VISIBLE / UNPLAYED / IN PROGRESS) now read as one VoiceOver element per stat** — same fix as the Settings stats row from #245.
- **Settings stats block (SUBSCRIBED / EPISODES / UNPLAYED / QUEUED + EXPLICIT / COMPLETED / TAGS) now reads as a single VoiceOver element per stat** — `12 subscribed` instead of `12, SUBSCRIBED` as two separate stops. Combines the value and label via `.accessibilityElement(children: .ignore)`.
- **PodcastDetail `+ LOAD 100 MORE` pager key now meets 44pt tap target.** Was ~34pt visible.
- **Player chapter row (`tap-to-seek`) now meets 44pt tap target.** Was ~33pt visible. Same `frame(minHeight: 44)` fix.
- **EpisodeTranslationView `→ TRANSLATE TO …` key now meets 44pt tap target.** Was ~30pt visible. Same `frame(minHeight: 44) + contentShape(Rectangle())` pattern.
- **Speech transcription panel action button now meets 44pt tap target.** Was ~30pt visible. Same `frame(minHeight: 44) + contentShape(Rectangle())` fix applied across the app.
- **Home now responds to pull-to-refresh** with the same `loadSections(manual:)` path as the existing retune key in HomeTunerHeader. Mirrors the Library / PodcastDetail pull-to-refresh shipped in #239 so the standard iOS swipe-down works on every list-of-content surface in the app.
- **Library and PodcastDetail now respond to pull-to-refresh** — the native iOS swipe-down gesture re-syncs every subscribed feed (Library) or just the one open feed (PodcastDetail). Reuses the same `syncSubscriptions()` / `FeedSyncService.sync(podcast:)` paths as the existing SYNC and ↻ REFRESH keys, so the LibrarySyncResult chip surfaces the outcome consistently regardless of which trigger fired.
- **PodcastDetail header now exposes a `↻ REFRESH` key** that re-syncs just that one feed. Previously the only path to refresh a single show was pull-to-refresh on the Library tab (which hits every feed). Useful for a user looking at one show who wants the latest episodes without re-syncing 50 feeds. Also bumps the existing `→ WEBSITE` key to 44pt min-height so the action row reads as a uniform bar.
- **QueueLeadStrip `→ PLAY` / `→ RESUME` and `× REMOVE` keys now meet 44pt tap target.** Were ~32pt visible. Same `frame(minHeight: 44) + contentShape(Rectangle())` pattern applied across the app.
- **Episode detail `↻ RETRY DOWNLOAD` key now meets 44pt tap target.** Was ~30pt (padding + 10pt label).
- **Settings recommendation-mode chips (Balanced / Lean Discovery / Stay Tuned) now meet 44pt tap target and announce the active mode to VoiceOver.** Were ~28pt visible. Added `frame(minHeight: 44)` and `accessibilityAddTraits(.isSelected)` so the highlighted chip is explicit to a11y users (background color alone wasn't enough).
- **Settings `↻ REBUILD SIGNAL` and `× SIGN OUT` (entry) keys now meet the 44pt tap target floor.** Both were ~30pt visible (padding + 10pt label). Added `frame(minHeight: 44) + contentShape(Rectangle())`. The matching ↻ RETRY DOWNLOAD on episode detail and × DISMISS on the import strip already pass; this brings the two remaining Settings ones up to the same standard.
- **Player rate picker (1×/1.25×/…) and sleep picker (5/15/30/45/60 MIN, × CANCEL, END OF EP) now meet the 44pt tap target floor.** Both grids were at 34pt minHeight — small enough to fat-finger across cells. Bumped to 44pt across the board, contentShape preserved.
- **Home cold-start `+ ADD` and discovery `+ TUNE` keys now meet the 44pt tap target floor.** Both were ~30pt (padding + 10pt label only). Same fix shipped for SearchView starter chips in #226 — adds `frame(minHeight: 44) + contentShape(Rectangle())` without changing the visible button outline.
- **Settings × SIGN OUT confirm panel now matches the common Tuner confirm vocabulary** — equal-width CANCEL / `× SIGN OUT` keys at 44pt min-height, paperWhite Cancel, fnRecord-tinted panel border. Was 28pt-tall buttons with mismatched colors. Closes the loop on bringing all four destructive-bulk confirm panels (Queue × CLEAR ALL, Settings × RESET rates, PodcastDetail × UNSUBSCRIBE, Settings × SIGN OUT) to the same shape.
- **PodcastDetail × UNSUBSCRIBE confirm panel now matches the Queue / Settings confirm vocabulary** — equal-width CANCEL / `× UNSUBSCRIBE` keys at 44pt min-height, `offscriptPaperWhite` Cancel label. Was 28pt-tall labels with mismatched `offscriptSoftPaper` Cancel — destructive bulk actions now share consistent dimensions across the app.
- **Settings `× RESET` per-podcast rates now drops into a Tuner-styled inline confirm strip** instead of wiping every show's custom playback speed on first tap. `● CONFIRM RESET` eyebrow + CANCEL / `× CONFIRM` key pair at 44pt min-height, mirroring the Queue × CLEAR ALL confirm pattern from #200 so destructive bulk-resets share vocabulary across the app.
- **Settings sign-in status message now auto-clears after ~8 seconds.** A stale "Sign-in failed. Please try again." used to linger across the next Settings open until the user took some other sign-in action. The auto-clear is cancellable so two back-to-back attempts both get a full readable window before the line fades.
- **Search starter-topic chips and `× CLEAR RECENT` key now meet the 44pt tap target floor.** Topic chips were ~30pt tall (padding + label only); the recent-searches clear button was ~14pt. Added `frame(minHeight: 44) + contentShape(Rectangle())` to bring both up to HIG's minimum tap-target size without changing the visible footprint of the chip.
- **Three remaining `Already queued` VoiceOver labels now include the episode title** — TunerLibraryCard (Library `Continue Listening` / `Fresh Episodes` rails), EpisodeDetailView's `+ QUEUE` action key, and HomeView's recommendation card queue button. Same fix as the other queue affordances; this brings the entire app to a consistent `<title> already queued` for the disabled state.
- **Queue row reorder + remove icon buttons now expose episode-title-aware VoiceOver labels** — `Move <title> up in queue` / `Move <title> down in queue` / `Remove <title> from queue` instead of the generic `Move up` / `Move down` / `Remove from queue`. A VoiceOver user navigating a 10-item queue can now disambiguate every action by the episode it targets.
- **Podcast detail header now flags `● SYNC FAILED`** when the feed has a non-zero failure count or `syncStatus == "failed"`. Mirrors the Library directory row chip from #206 — even when a user has navigated into a podcast detail page, they can see at a glance that the feed is unhealthy without flipping back to the Library scope filter.
- **Library directory empty state now exposes a `× CLEAR FILTER` recovery key** when an active scope (NEEDS SYNC, etc.) or search query collapsed the list to zero. Mirrors the PodcastDetail clear-filter affordance shipped in #208 — one-tap reset to scope `.all` and empty query instead of having to scroll back up to find the right control.
- **Playback rate picker now offers a `0.75×` slow option** in both the per-podcast Player picker and the Settings default-rate picker. Useful for language learners, dense or technical content, and accessibility — the previous floor was `1.0×`.
- **Player `WHAT'S NEXT · ON YOUR FREQUENCY` rows now expose a `+` queue key alongside `▶` play** so a listener can stack a suggested episode without interrupting current playback. Mirrors the play+queue affordance pair on Library / PodcastDetail episode rows. Hides when the suggestion is already queued so the row doesn't render a no-op.
- **OPML batch import strip now exposes a `× CANCEL` key while a batch is running** in addition to the existing progress + count readout. Previously the only way to abort a long-running 50+-feed import was to force-quit the app. Cancel preserves already-imported feeds and marks pending rows as `.cancelled` per the existing `BatchImportService.cancel()` semantics.
- **Queue empty state now picks the right escape hatch based on library state** — a user with subscribed podcasts sees `→ BROWSE LIBRARY` (find an episode to queue) instead of `→ EXPLORE SHOWS`, which used to push them back to Search even though their library was already populated. Fresh-install users with zero subscriptions still get `→ EXPLORE SHOWS` because Library is empty for them. Tap on the BROWSE LIBRARY key posts `.offscriptSwitchTab` to library so it lands in the right tab regardless of where the empty state was rendered.
- **OPML batch import strip now exposes a `↻ RETRY N` key** when a finished batch reports failed feeds — common case is a flaky network where 5 of 50 feeds 404'd transiently. Previously the user had to re-import the whole OPML and re-skip the 45 that already landed. New `BatchImportService.retryFailed(modelContext:)` filters `entries` to just the failed rows, resets their progress to `.pending`, and re-runs the same pipeline against only those.
- **Home cold-start `START HERE` rail now owns per-pick import errors** — when a starter pick's `+ ADD` fails, the key flips to `✗ FAILED · RETRY` in `offscriptFnRecord` and a `● ADD FAILED` strip with the underlying error renders inline, instead of the failure overwriting a single global error message that hid every earlier failure. Per-row in-flight tracking via a new `importingIDs: Set<String>` so two picks tapped in quick succession both keep their `○ ADDING…` state. Same pattern as the SearchView per-row error fix shipped in #199.
- **Player `✓ MARK PLAYED` now toggles to `↺ MARK UNPLAYED` when the episode is already played** so an accidental tap is recoverable in one tap instead of having to play the episode again to clear `isPlayed`. The unplayed branch resets `playedPosition` to 0 so the episode comes back into the unplayed pool.
- **Player's `+ QUEUE NEXT` key renamed to `+ QUEUE`** to match its actual `QueueService.add` (end-of-queue) behavior. Episode Detail's `QUEUE NEXT` (front-of-queue, via `QueueService.playNext`, shipped in #210) used the same label for opposite semantics — real bug for users who relied on labels.
- **Player sleep picker now offers an `END OF EP` option** alongside the 5/15/30/45/60-minute keys. Arms a flag on `PlaybackController` that suppresses auto-advance when the current episode finishes — the player pauses at the end instead of jumping into the next queued item. Common podcast-app affordance for falling asleep to one specific episode without committing to a wall-clock minute budget. SLEEP key label flips to `SLEEP  END OF EP` when armed.
- **Episode detail action row now exposes a `QUEUE NEXT` key** alongside the existing `+ QUEUE` (end-of-queue). Tapping promotes the episode to position 0 so it plays right after the current one finishes — heavy listeners with a long working set no longer have to drag-reorder. Hides when the episode is already next-up to avoid a no-op. Closes the "verify queue integration from Episode Detail" bullet of #126.
- **Home `● FEED UNAVAILABLE` error strip now exposes a `↻ RETRY` key** that re-runs the recommendation pipeline. Without retry the user previously had to leave Home and come back to trigger a reload after a transient SwiftData fetch hiccup or a CDN glitch on the discovery side.
- **Podcast detail's empty-filter state now exposes a `× CLEAR FILTER` recovery key** when the active filter or search query produced 0 episodes. Tapping it resets the filter to ALL and clears the search query, so a user who hit `DOWNLOADED` on a feed with no offline episodes doesn't have to manually find the filter row and re-tap `ALL` to get back.
- **Library now surfaces a brief inline summary chip after a manual SYNC** — `✓ SYNCED N` (clean), `● SYNCED N · M FAILED` (partial), or `● SYNC FAILED` (all). Auto-clears after ~6s; the next manual SYNC clears it immediately. Companion to the per-row `● SYNC FAILED` chips so the user can see at a glance whether the pull-to-refresh / SYNC tap was clean and pivot to the `NEEDS SYNC` filter scope when it wasn't.
- **Library directory rows now flag failed feed syncs inline** with a `● SYNC FAILED` chip in `offscriptFnRecord` next to `IN PROGRESS` / `UNPLAYED`. A podcast whose feed went 404 (host moved, feed renamed, source dropped) used to look identical to a healthy one in the directory unless the user flipped to the `needsSync` filter scope or opened the detail page; the chip surfaces the failure inline so users notice without changing scope.
- **Player `UP NEXT · CHANNEL QUEUE` row now exposes `→ PLAY` and `× DROP` action keys** so a listener can promote the next-up episode to current playback or drop it from the queue without opening the Queue tab or letting the current episode finish first. Closes the "verify queue integration from Home, Episode Detail, Search, Player" bullet of #126 — the Player surface previously rendered the up-next item as read-only.
- **Tab bar Queue badge now overflows to `99+`** instead of silently capping at `99`. A heavy listener with 150+ queued episodes used to see a flat `99` on the tab bar that disagreed with the QueueView header's `150 STACKED`.
- **MiniPlayer now surfaces playback errors directly on its status eyebrow** — when the AVPlayerItem fails or stalls, the `● PLAYING` / `❙❙ PAUSED` badge is replaced by `● ERROR` in `offscriptFnRecord`. Without this, a cellular drop would render as `● PLAYING` on the docked strip until the user opened the full player and saw the inline error. Companion to the `↻ RETRY` key on the full-player error strip (#124 sub-bullet).
- **Player playback-error strip now exposes a `↻ RETRY` key** in addition to the existing × dismiss. The retry rebuilds the `AVPlayerItem` for the current episode (restoring the saved position) and resumes playback in one tap, so a transient network stall on cellular doesn't force the user to dismiss the error and re-seek. Closes a sub-bullet of #124 (Player polish) and matches the same `↻ RETRY` recovery affordance shipped for podcast detail load errors (#166).
- **`offscript://podcast/<uuid>` deep links now actually navigate** to the podcast's detail page instead of being logged-and-dropped. `DeepLinkRouter.handlePodcast(...)` verifies the UUID exists in SwiftData, switches to the Library tab, stashes the UUID in `pendingPodcastDeepLink`, and posts a new `.offscriptOpenPodcast` notification carrying the UUID. `LibraryView` consumes the notification (warm path) and the pending UUID on first `.onAppear` (cold-launch path where the lazy tab hasn't been instantiated yet), then binds the value to its existing `selectedPodcastID` state so the existing `.navigationDestination` pushes `PodcastDetailView`. Unblocks Spotlight donations, Now Playing widget taps, and future Shortcuts intents that target a specific show.
- **Queue `× CLEAR ALL` now drops into a Tuner-styled inline confirm strip** instead of silently wiping the working set on first tap. The strip renders an `● CONFIRM CLEAR` eyebrow, the count of queued episodes, and a CANCEL / `× CONFIRM` key pair at 44pt min-height; cancelling restores the prior state, the strip auto-dismisses if the queue shrinks to ≤1 via another path while the dialog is open. Bulk-clear delegates to a single `QueueService.clearAll(...)` transaction so heavy queues drop in one telemetry event and one save instead of N. Closes the "audit large queue states" bullet of #126.
- **Search result rows now own their import error state** — when `+ ADD TO LIBRARY` fails for a specific row, the key flips to `✗ FAILED · RETRY` in the `offscriptFnRecord` accent and a `● IMPORT FAILED` strip with the underlying error renders below the action row, instead of the failure vanishing into the global search-error strip with no indication of which row failed. Tapping the row's RETRY key clears the row error and restages the import. Closes the "errors from Apple Podcasts Search/feed hydration are actionable" bullet of #123.
- **Player scrubber now floats a signal-yellow time bubble above the user's finger during a drag** that fades out on release, so scrubbing toward a specific timestamp is a closed-loop interaction instead of guessing-then-checking the static current/remaining mono labels. Tester feedback: "no time indicator over scrubber position." Seek-on-release behavior is unchanged. Closes #195.
- **Onboarding numbered manifesto now reads as the primary content peak below the OFF / SCRIPT. wordmark** — bumped to 17pt semibold body type with a 14pt mono signal-yellow row number, and the manifesto paragraph above is compressed to dim 13pt so it doesn't compete. Tester feedback: "people don't read small text, the directions should be bigger with greater emphasis." Closes #194.
- **Horizontal rails now fade their leading and trailing edges into `offscriptStudioBlack` via a shared `tunerRailEdgeFade()` view modifier** so partially-visible cards or chips read as "scroll for more" instead of clipping mid-content. Applied to the Home regular recommendation rails, Home discovery rail, Library `Continue Listening` / `Fresh Episodes` rails, the SCOPE/SORT/ROWS/DENSITY filter chip rows on the Library directory, and the podcast detail FilterRow. Closes #188.
- **Library header's IMPORT / SYNC / TUNE keys now share the same icon+label hairline-rectangle pattern** so the right-aligned trio reads as one uniform key bank instead of one big IMPORT button next to two small icon-only sync/settings squares. `ViewThatFits` falls back to icon-only at large Dynamic Type or narrow widths so the row never wraps. Closes #187.
- **Library header now hides the `SHOWS / VISIBLE / UNPLAYED / IN PROGRESS` stats row when the library is empty** so a fresh-install user sees just the header → empty-state copy without a redundant `0 / 0 / 0 / 0` band competing with the "Your library is empty" headline. The stats reappear the moment the user has at least one subscription. Found during a full UI screenshot pass.
- **Home now pins the Tuner header below the Dynamic Island via `safeAreaInset(edge: .top)`** — the eyebrow row, page title, retune key, and settings key stay anchored at the top of the screen while hero/rail/discovery content scrolls behind a solid black backing. Replaces the previous behavior where the header lived inside the scrolling stack and slid up off-screen. Closes #161 (supersedes draft PR #162, which applied a permanent `scaleEffect` to eyebrow text — that approach distorted text rendering on Pro devices without delivering the sticky-bar primary ask).
- **Home recommendation surfaces (hero card, regular rail cards, discovery rail cards) no longer render the `SOURCE: <bucket>` trace footer** — internal `RecommendationSignal` source bucket names like `LATEST` and `GENRE` were leaking onto a user-facing surface as debug-overlay copy. The authored `TunerRailReasonTag` / `TunerTag` reason already explains the pick in plain language; the trace stays available on Episode Detail and Player for the on-device-AI transparency story (#181).
- **Discovery rail cards now bottom-align their `+ TUNE` action key uniformly** by reserving a fixed 2-line slot for the title and absorbing reason-tag height variance with a `Spacer()` before the action. Stops the rail from staircasing when sibling card titles wrap to different line counts (#180).
- **The Queue lead strip now reflects current-state instead of always reading "● NEXT UP"** — when the lead queue item is the episode currently playing it switches to a green `● NOW PLAYING` eyebrow with a disabled `● PLAYING` key, and when the user has a resume position mid-episode the eyebrow becomes `● NEXT UP · IN PROGRESS` with a `→ RESUME` action key. Removes the visual ambiguity heavy listeners hit when bouncing between Player and Queue (#126).
- **Repository now has a [`docs/TUNER_CONFORMANCE.md`](docs/TUNER_CONFORMANCE.md) audit log** with a per-surface Tuner-conformance state table and an explicit "Intentional Native Exceptions" list (Sign in with Apple, share sheet, file importer, SFSafariViewController, MPNowPlayingInfoCenter, Live Activity / Dynamic Island), so future surface additions can be checked against a single source instead of re-deriving the rules per PR (#109).
- **Root Home, Library, Queue, and Search tabs now hide native empty navigation bars** so the top-of-app spacing is governed by the iOS safe area plus the 2pt Tuner inset instead of an invisible reserved nav bar.
- **Shared Tuner labels, tags, and readouts now scale through Dynamic Type metrics** while preserving the mono instrument-panel vocabulary.
- **The custom Tuner tab shell now keeps visited tab stacks alive** so returning from Library to Home does not rebuild the Home recommendation feed on every tab switch.
- **Compact Tuner keys now keep their visual size but expose 44pt hit targets** across Library, Player, Queue, Search, downloads, and episode detail actions.
- **Discovery/search copy now names Apple Podcasts Search explicitly** and avoids implying the app is running a generic opaque algorithmic feed.
- **Remaining app-controlled Liquid Glass controls were replaced with Tuner surfaces**: Settings toggles, Player scrubber, sign-out/unsubscribe confirmations, and sheet presentation chrome now use flat OLED panels, hairlines, and signal-yellow keys.
- **Player speed, sleep timer, settings default-rate, and episode download controls no longer invoke system `Menu` chrome.** They now use direct Tuner keys or inline sharp option grids, keeping daily playback controls inside the OLED instrument-panel language.
- **Home feedback, compact episode-card actions, and Queue reorder controls now use inline Tuner keys** instead of default `Menu`/long-press context surfaces, removing the remaining system action chrome from core playback and queue flows.
- **The Library `#-Z` carousel now targets the nearest available section for every key**, so sparse or filtered directories still respond when a letter does not currently have an exact section.
- **Long recommendation reason tags now wrap inside Tuner cards** instead of forcing fixed-width mono pills that could run off Home cards.
- **Library import is now an explicit `IMPORT` Tuner key** with an icon-only fallback when width is constrained, so the OPML/paste entry point is visible without guessing the glyph.
- **The bottom Tuner tab indicator now slides between Home, Library, Queue, and Search** with selection haptics instead of appearing abruptly in each cell.
- **Root page headers sit tighter to the safe area** to reclaim top-of-app space while keeping the iOS status/Dynamic Island safe region intact.
- **Large Library sections now render as flattened lazy headers, rows, and separators** so a 250+ show directory does not build an entire oversized letter section as one SwiftUI child.
- **The Library directory now renders from value snapshots instead of live SwiftData podcast models** so 250+ show scrolling does less model work and only resolves a show when a row is opened.
- **Library launch now avoids duplicate directory loads and coalesces snapshot rebuilds** so large libraries do less repeated sort/filter work while counts and controls update.
- **Home retune and Library sync now use explicit Tuner header keys instead of native pull-to-refresh chrome**, removing another app-controlled Liquid Glass surface while keeping refresh actions discoverable.
- **Podcast and episode detail pushes now use inline Tuner back keys** so Library and Home drill-down flows no longer fall back to native iOS back-button chrome.

### Changed — Library performance
- **Podcast detail episode-list scrolling now caches stripped HTML at 5,000 entries / 16MB** (up from 500 / 2MB), so a 200+ episode show no longer thrashes `NSAttributedString` HTML parsing on every scroll-recycle (#169).
- **Podcast detail rows now skip rendering the summary `Text` when the stripped form is empty**, eliminating the per-row `strippingHTML` cost on scroll for feeds whose summaries are HTML-only boilerplate (`<p>&nbsp;</p>` etc.) (#169).
- **`PodcastDetailView.loadEpisodes` now emits an `OffScriptPerformanceLog` signpost** (`podcast.detail.loadEpisodes`) tagged with podcast title, requested limit, row count, total matching count, and `hasMore`, so future scroll regressions are measurable in Instruments and OSLog (#169).

### Changed — recommendation quality
- **Discovery rail card count now scales with signal strength** — when 3+ signal-driven Home rails (Signal Lock, Resume Thread, More From Shows You Chose, Shows You Finish, Topic Continuation, Tuned Genres) are populated, Discovery uses its full mode limit (6 in Balanced, 10 in Discovery mode); when only 1–2 rails populate, the limit halves; when none populate Discovery shrinks to 3 cards. Stops Apple Podcasts Search results from dominating the screen on a signal-thin Home (#191; pairs with the From Your Subscriptions catch-all rail in #192).
- **Home now has a `From Your Subscriptions` catch-all rail** that surfaces the latest unplayed episodes from subscribed shows when no signal-driven rail (Signal Lock, Resume Thread, More From Shows You Chose, Shows You Finish, Topic Continuation) catches them. Pulls from the same subscribed-show pool the rest of the engine uses but bypasses the `homeSignal` requirement so cold-start / signal-thin users see their actual library on Home instead of "Apple Podcasts catalog with TUNE buttons" via Discovery / Tuned Genres. Negative show / tag signals (`Less Like This`, `Not Interested`) still suppress here just like in the signal-driven rails. Pairs with #191 (Discovery demotion).
- **Discovery rail reason copy now varies across adjacent cards by avoiding the previous card's chosen RecommendationExplainer source bucket** — a rail of three cards all backed by `latest episode` no longer reads as `LATEST EPISODES OVERLAP YOUR <noun> SIGNAL` repeated three times. The second/third card falls back to the next-strongest signal in its trace (e.g. tag match → topic overlap → show affinity), so the rail reads as authored signal instead of a template loop (#179).
- **Home recommendations now fetch targeted candidates from explicitly liked and completed shows outside the global recency window**, so large high-volume libraries cannot bury older high-signal follow-ups before scoring.
- **Home recommendations now compose multiple local evidence signals instead of stopping at the first matching rule**, so explicit topic feedback and “more from this show” reinforce one authored recommendation rather than competing as generic ranking buckets.
- **Recommendation reason copy now has deterministic rail-length clipping for combined evidence**, keeping long show/topic explanations inside Tuner cards.
- **All authored WHY copy paths now route through the same 72-character rail clip** so show-affinity, same-show, taste-tag, topic-overlap, recent-interest, liked-episode, now-playing, fresh, latest-episode, subscription, available, and unknown-fallback reasons can no longer overflow Home and Library rail cards (#118).
- **Wrapping Tuner reason tags now truncate with a tail ellipsis** instead of relying on parent clipping, so the second line of a long recommendation reason ends cleanly inside the hairline border.
- **Explicit “more like this” and like signals now carry substantially more weight than passive completions** so recommendations follow intentional user feedback instead of feeling like generic completion-based ranking.
- **Episode Detail feedback now uses the same retune notification path as Home cards** so likes and `NOT FOR ME` taps refresh recommendations consistently across entry points.
- **Discovery genre matches now stay low-confidence until backed by local evidence** such as latest-episode tag overlap, topic matches, show affinity, or feed freshness, and genre-only WHY copy no longer claims local evidence.

### Fixed — observability hygiene
- **`BackgroundFeedRefresh`, `CrashReporter`, `MetricKitReporter`, and `OffScriptApp` SwiftData loggers now use the `com.offscript` subsystem** like every other logger in the app — they were inconsistently using a bare `OffScript` subsystem, which meant `Console.app` filters on `subsystem:com.offscript` silently dropped those four important categories (background refresh, crash reporter, MetricKit, SwiftData container init/migration). Per the design bible's "Logger convention: `Logger(subsystem: \"com.offscript\", category: \"ServiceName\")`" rule.

### Fixed — silent failure paths
- **`CachedAsyncImage` URL fetch failures now log under a new `ImageCache` OSLog category at `.debug`** instead of dropping silently via bare `try?`. Kept at `.debug` so routinely-stale podcast artwork URLs (404, host migrations) don't spam `Console.app`, but verbose-mode triage now sees the underlying `URLError` description.
- **Background transcription's downloaded-episode candidate scan and Apple ID embedded-provisioning-profile entitlement parsing now log the underlying error** instead of dropping it via bare `try?` — so a failed transcription scan or a malformed `embedded.mobileprovision` leaves a real OSLog entry under `BackgroundTranscription` (`.error`) or the new `AppleIdentity` category (`.warning`). The legitimately-absent simulator/dev case (no `embedded.mobileprovision` in the bundle) stays quiet to avoid log spam.
- **Background feed refresh, deep-link episode lookup, `deleteAllDownloads`, `resumeQueuedDownloadsIfNeeded`, and `reconcilePersistedDownloads` now log the underlying SwiftData fetch error** instead of dropping it via bare `try?` — so a failed background refresh, a broken episode deep link, or a download lifecycle hiccup leaves a real OSLog entry (`BackgroundRefresh` at `.warning`, `DeepLink` and `DownloadService` at `.error`) instead of disappearing silently.
- **`modelContext.save()` calls on the played-state toggle (CardComponents) and the debug seed/reset paths (ContentView) no longer swallow errors via bare `try?`** — they now use `do/catch` with category-scoped OSLog (`CardComponents`, `App`) so SwiftData save failures during sample/large-library seeding or a played-state flip surface as real log lines.
- **`QueueService.add` calls in CardComponents, EpisodeDetailView, and the debug-boot queue seeder no longer swallow errors via bare `try?`** — they now use `do/catch` with category-scoped OSLog (`CardComponents`, `EpisodeDetail`, `App`) so a failed enqueue surfaces as a real log line instead of disappearing. Per the design bible's "NEVER use bare try?" rule.

### Fixed — onboarding, import, and sync UI honesty
- **Search and discovery import errors now surface the underlying `error.localizedDescription`** instead of generic "Search failed. Check your connection and try again." / "Couldn't import … yet." copy, so users can tell whether a failure is network, parsing, or feed-side rather than guessing (supersedes #158).
- **Podcast detail rows now show chronological "Episode N" labels instead of inverting newest-first display indices** so the first episode in a show reads as Episode 001 and the newest reads as the highest number, with feed-supplied `<itunes:episode>` values preferred when available and filtered subsets falling back to a `—` placeholder rather than a misleading partial-list rank (#145).
- **Onboarding background hydration now yields and waits briefly after local subscription completion** so the first Home render is not immediately contending with starter-feed apply/save work on the main SwiftData context.
- **Settings and Sign in with Apple now log identity, iCloud, signal-profile, and Keychain OSStatus breadcrumbs** so TestFlight Settings crashes and Apple sign-in failures can be correlated to the failing subsystem.
- **Onboarding Sign in with Apple no longer has an iOS 26 missing-window precondition crash path** and now logs Keychain OSStatus details when credential persistence fails.
- **Large OPML bootstrap imports now fetch feeds concurrently but apply SwiftData changes serially** and cap bootstrap RSS parsing to the small starter window, reducing 250+ show import stalls without changing normal full-feed sync.
- **Large Library count-driven filters no longer fetch every matching episode just to compute per-show badges** and instead use cancellable per-show count queries for `UNPLAYED`, `IN PROGRESS`, and `ATTN`.
- **Library now refreshes its directory after unsubscribing from a show detail screen** so the removed channel and visible count do not stay stale when returning from detail.
- **Recommendation negative signals are now graded instead of binary** so one `Less Like This` no longer erases a whole show while repeated negative evidence still suppresses strongly matched candidates.
- **Tuner chrome now uses shared modal/detail top insets and more resilient compact headers/import rows** so Settings, Import, and Library fallback surfaces keep the OLED instrument look at narrow widths and larger text sizes.
- **Onboarding Sign in with Apple fallback anchoring no longer emits the iOS 26 `ASPresentationAnchor(frame:)` archive warning** when no foreground scene is available.
- **Large OPML and onboarding bootstrap imports now use shorter feed request timeouts** so dead feeds release bounded import slots faster while normal subscribed-feed sync keeps its more patient timeout.
- **Onboarding Sign in with Apple now presents from the actual button window when available** and no longer uses the old crash-prone missing-scene path for the normal sign-in flow.
- **Onboarding starter subscriptions now commit immediately and hydrate in the background** using the same lightweight bootstrap profile as large imports, so picking three podcasts no longer waits on serial feed parsing, full episode enrichment, or external chapter lookups before entering the app.
- **Onboarding import no longer auto-completes through failed feeds.** Failed starter channels stay visible with retry and continue actions.
- **Bulk OPML import cancellation now marks pending/importing rows as cancelled** instead of leaving them stuck mid-import.
- **Settings no longer claims iCloud sync is active unless the launch actually opened a CloudKit-backed SwiftData container.**
- **The SwiftData test container is explicitly local-only** so CloudKit entitlements do not break in-memory unit tests.
- **Sentry TestFlight/App Store environment tagging now uses StoreKit 2 app transactions** instead of the deprecated receipt URL path, clearing the recurring iOS 18 `appStoreReceiptURL` archive warning.

### Fixed — Xcode Cloud signing
- **Xcode Cloud diagnostics now flag `INTERNAL_ONLY` archive workflows and use Apple's current `APP_STORE_ELIGIBLE` API enum** for TestFlight/App Store deployment preparation, with an explicit failure path when App Store Connect rejects action-array replacement because of hidden deployment config state.
- **Build number advanced to 41 after Xcode Cloud runs #40 and #41 failed exporting app build 40.**
- **Build number advanced to 42 after Xcode Cloud run #63 failed during App Store Connect preparation** while the product line continued shipping performance builds on main.
- **Build number advanced to 43 after App Store Connect reported `2.3.11 (42)` already uploaded** despite Cloud run #64 failing during preparation.
- **Build number advanced to 44 after App Store Connect reported `2.3.11 (43)` already uploaded** despite Cloud run #65 failing during preparation.
- **Build number advanced to `2026043001` after Xcode Cloud run #66 hit transient Sentry binary artifact download failures** and App Store Connect reported the small integer build-number range already uploaded, returning the project to the documented date-stamped TestFlight numbering scheme.
- **Build number advanced to `2026043002` after Xcode Cloud run #71 failed during App Store Connect preparation** before TestFlight internal testing could run.
- **Build number advanced to `2026043003` after Xcode Cloud run #98 failed during App Store Connect preparation** before TestFlight internal testing could run.
- **Build number advanced to `2026043004` after Xcode Cloud run #99 failed during App Store Connect preparation** before TestFlight internal testing could run.
- **CloudKit entitlements are temporarily withheld from the shipped target** because Apple-managed App Store and Ad Hoc profiles for `com.offscript.app` remain invalid after iCloud capability changes. The runtime still falls back to local storage and Settings reports the fallback instead of claiming sync is active.

### Added — large-library directory controls
- **Library now behaves like a real channel directory for 250+ show libraries.** The shows list has Tuner-styled search, scope filters, sort modes, compact/artwork row density, visible-count readouts, and an A-Z jump rail so large OPML imports are navigable without endless scrolling.
- **Large libraries default to compact rows.** Artwork-heavy rows remain available for smaller libraries, but 120+ show libraries automatically use dense Tuner rows to reduce scroll distance and image/layout churn.
- **The alphabet jump rail is now a full A-Z/# key bank with selected and disabled states** so large libraries expose every directory letter as a direct Tuner control instead of hiding letters in a horizontal strip.
- **The Library alphabet selector is back to the compact `#-Z` carousel form** while keeping the working direct-letter jump behavior and selected/disabled Tuner states.
- **Sparse Library alphabet keys now stay visually selectable when they jump to the nearest available section**, and the carousel highlights the key the listener chose instead of only the section it landed on.
- **Settings and Library import sheets no longer sit inside empty native navigation hosts**, reducing stray iOS navigation chrome while keeping the authored Tuner headers and inline DONE keys.

### Changed — Library performance
- **The subscribed-show directory fetch now runs through the Library SwiftData model actor** so opening or refreshing a 250+ show Library returns value snapshots to the UI actor instead of fetching the podcast table on first paint.
- **Library Tuner sync now batches subscribed-feed refreshes** so a 250+ show Library overlaps slow feed network requests and avoids one SwiftData podcast lookup per subscription before refreshing counts.
- **Library activation summary queries now run through the Library SwiftData model actor** and return only visible rail episode IDs to the UI actor, reducing first-paint contention for large subscribed libraries.
- **Count-driven Library directory badges now load through a SwiftData model actor** so exact per-show unplayed/in-progress counts no longer materialize large episode sets on the main UI actor for 250+ show libraries.
- **Home activation now skips the full taste-profile rebuild on normal tab switches** and scores from the last saved profile plus fresh local feedback rows, reducing Library-to-Home lag for 250+ show libraries while preserving manual Retune refresh behavior.
- **Library directory snapshots now build off the main actor and cancel stale work** so large `#-Z` filter/sort/index rebuilds do not keep blocking Library scrolling or the Library-to-Home tab transition.
- **The Library `#-Z` selector now uses precomputed jump targets from the directory snapshot** instead of recalculating nearest sections inside every rail render, keeping 250+ show letter jumps responsive and state-consistent when filters change.
- **Large Library rows now opt into SwiftUI equatable rendering** so unchanged channel rows avoid repaint churn while counts, filters, and import status update around them.
- **Inactive Home and Library tabs now stop rendering their heavy page bodies** while preserving tab state, so switching from a 250+ show Library back to Home no longer keeps the hidden directory tree in the transition path.
- **Count-driven Library directory modes now derive unplayed and in-progress per-show counts from one scoped fetch** instead of scanning overlapping episode sets twice for `ATTN` views.
- **Home/Library tab changes, recommendation loads, directory snapshots, summary fetches, and per-show count fetches now emit performance timings** so 250+ show lag can be measured from device logs instead of guessed from simulator feel.
- **OPML staging, retry, and cancellation now use scoped feed-URL variant lookups instead of full podcast-table scans for large batches**, while preserving normalized resubscribe behavior for small single-feed edge cases.
- **Large OPML imports now stage subscribed shows before network sync finishes**, so 250+ show libraries appear in Library immediately while feed hydration continues in the background.
- **Single-show adds from Home, Search, and pasted feed URLs now save the subscription before feed hydration**, then use a capped bootstrap sync in the background instead of blocking the UI on a full catalog import.
- **Onboarding now stages selected starter shows in one SwiftData batch** instead of saving each selected podcast independently, making the three-podcast starter flow a single local commit before background hydration.
- **Capped feed bootstrap now selects the newest episode slice without sorting full back catalogs**, so OPML and onboarding bootstrap paths do not pay full-feed sort cost when they only need the first few newest episodes.
- **Onboarding preference seeding now fetches the newest hydrated episode with a one-row SwiftData query** instead of sorting the podcast's relationship collection after background sync.
- **The Library directory now renders from a cached value snapshot instead of a live `@Query` podcast array**, reducing SwiftData invalidation churn while scrolling large subscribed libraries.
- **Settings now uses a subscribed-show `fetchCount` instead of materializing the podcast table**, and the custom tab bar indicator now slides as one continuous Tuner rail.
- **Home rail cards now use compact Tuner reason tags and shorter signal traces**, keeping recommendation explanations inside narrow 168px cards.
- **Tuner typography no longer uses negative tracking in app-authored titles and cards**, improving compact-device fitting and keeping OLED text rhythm consistent.
- **Settings now frames Sign in with Apple inside an authored Tuner identity panel** with compact credential and iCloud readouts while preserving Apple's native authorization button.
- **OPML batch hydration now uses a lightweight bootstrap pass** that imports only a small first slice of episodes and skips episode profile enrichment, avoiding thousands of episode/profile writes during the initial import.
- **The root Library podcast query now filters subscribed shows in SwiftData instead of fetching every historical podcast and filtering in Swift.**
- **Large-library scrolling no longer waits on per-show unplayed count churn by default.** Library now loads the aggregate unplayed count, fresh rail, and bounded in-progress rail first; exact per-show counts are deferred until `UNPLAYED` or `ATTN` directory modes need them.
- **Count-driven Library directory modes no longer run one count query per show.** `UNPLAYED`, `IN PROGRESS`, and `ATTN` now load the relevant episode set once and bucket counts by podcast in memory, removing hundreds of SwiftData round trips in 250+ show libraries.
- **Library directory count loading now tracks unplayed and in-progress count families independently**, so switching from `UNPLAYED` to `IN PROGRESS` or `ATTN` fetches only the missing count family instead of reusing stale load state.
- **Podcast detail search now uses bounded SwiftData predicates for filtering and paging** instead of scanning hydrated episode objects and stripping summaries on the main actor.
- **Library directory snapshots are now cached between relevant input changes** so import-strip ticks, selection changes, rail image updates, and other unrelated SwiftUI refreshes do not repeatedly re-filter, re-sort, and re-section the whole 250+ show directory.
- **Library artwork now uses fixed-size image requests on known-size surfaces** so rails, optional artwork rows, and channel detail headers do not pay a `GeometryReader` measurement cost per artwork view.
- **Library show rows now render from prebuilt directory row models** so channel numbers and per-show counts are computed once with the snapshot instead of via dictionary lookups and enumerated array allocation inside the SwiftUI row loop.
- **Library show rows now navigate through a single selected destination** instead of embedding a detail destination in every row of a 250+ show directory.
- **Library summary reloads are coalesced during background OPML imports** so each imported show does not immediately retrigger the expensive per-show count path while the list is being scrolled.
- **Library summary counts no longer issue one SwiftData `fetchCount` per subscribed show.** The page now loads the unplayed episode set once, derives the latest rail and per-show counts from that result, and avoids 250+ synchronous count queries on Library open.
- **Library directory rendering now builds one snapshot per render pass** for filtered shows, alphabet sections, and row numbers, with debounced search input so typing does not repeatedly sort/group the whole library.
- **Library no longer observes every OPML progress tick at the root page level.** The import strip repaints during batch progress, and the expensive directory snapshot refreshes when the batch reaches a terminal state.
- **Bulk OPML import now skips already-subscribed feed URLs before network fetch/parse work** using the same normalized feed-key logic as OPML dedupe, so re-importing a large library does not waste rows on feeds that are already tuned.
- **Capped feed imports now only look up existing episodes that can match the processed feed window** instead of fetching a show's entire historical episode table before an OPML/onboarding bootstrap slice.
- **Library summary loading now avoids hydrating the full unplayed back catalog on open.** The header count and fresh rail load from count/limited fetches first, while per-show unplayed counts fill in incrementally in small chunks.

### Added — recommendation tuner and signal discovery
- **Settings now has a three-position recommendation tuner** (`SIGNAL`, `BALANCED`, `DISCOVERY`) so listeners can choose whether OffScript stays strictly inside known local evidence or opens a new-show discovery lane.
- **Home can render a Tuner-styled discovery rail** sourced from the existing taste profile, with trace rows explaining whether each new podcast came from genre, tag, show-affinity, or discovery signal. Discovery rows can be tuned into the library without leaving Home.

### Changed — taste profile quality
- **Home recommendations now treat explicit Like / More Like This feedback as first-class signal** ahead of passive show completion, so the next Home surface follows what the listener deliberately asked for instead of drifting back toward generic fresh/feed picks.
- **Home show-affinity recommendations now use current preference events immediately** instead of waiting on the cached taste profile refresh window, so a newly liked show can influence the next render right away.
- **Player suggestions now let strong now-playing topic overlap beat unrelated same-show episodes**, making the player rail feel contextual to the current listen rather than a plain “more from this feed” list.
- **“Shows You Finish” now means actual completed playback events** instead of grouping resumed or queue-advanced events into completion evidence.
- **Home, Discovery, and Player recommendation cards now use authored local signal explanations** instead of raw algorithm fallback strings like `Matches your saved signal`, keeping WHY copy concrete even when Apple Intelligence is unavailable.
- **Taste refresh now uses weighted, decayed evidence instead of equal counts.** Recent explicit `More like this` signals beat old passive completions, while `Less like this`, `Not interested`, quick skips, and abandons demote matching tags and shows.
- **Recommendation modes now materially change Home ranking.** `SIGNAL` excludes genre-only candidates, while `BALANCED` and `DISCOVERY` can include a separate tuned-genre lane after local evidence.
- **Negative signals now suppress adjacent recommendations, not just the exact episode.** `Less like this`, `Not interested`, skipped, and abandoned signals carry disliked tags/show penalties into Home and Player suggestions.
- **Home now reloads recommendations immediately after explicit feedback** instead of waiting for the next automatic refresh path, and the headline card shows a small retuning status after Like / More / Less / Not Interested.
- **Discovery recommendations now inspect the latest feed preview before ranking new shows**, so Apple Podcasts Search hits with episode-level overlap beat generic genre-only catalog matches.
- **Home headline selection now ranks the strongest authored recommendation across all local sections** instead of blindly promoting the first row of the first section.

### Fixed — playback queue and Now Playing
- **Playing a queue row now removes that row before playback starts**, so completion/remote-next does not replay the same episode before advancing.
- **Remote pause updates the Now Playing playback rate** so Lock Screen and Control Center stop showing advancing playback after a headphone or Control Center pause.
- **Episode switches reset duration immediately and guard artwork updates** so stale duration/artwork from the previous episode cannot race into Player or Now Playing.

### Fixed — Apple identity / iCloud sync state
- **Opening Settings no longer crashes builds without CloudKit entitlements.** iCloud account-status checks are now gated behind a CloudKit entitlement/profile check, and Settings reports `ICLOUD · NOT CONFIGURED` until the signed CloudKit profile lands.
- **CloudKit sync is guarded by runtime container state** so failed or unavailable iCloud-backed stores fall back to local storage instead of presenting as active sync.
- **Settings now validates stored Sign in with Apple credentials** before treating the user as signed in. Revoked or missing credentials clear local identity and disable sync.
- **Transient Apple credential validation failures no longer clear a saved Apple ID.** Credentials are cleared only for revoked or not-found states.
- **iCloud account availability is checked separately from Apple identity.** Sign in with Apple no longer blindly enables sync when CloudKit is unavailable on the device.
- **Onboarding Sign in with Apple now checks iCloud availability before enabling sync**, matching Settings behavior.

### Fixed — playback audio session
- **Playback now uses an iOS-supported `.playback` audio-session configuration** instead of pairing the `.longFormAudio` route-sharing policy with AirPlay/Bluetooth category options. iOS rejects that combination with `OSStatus -50`; when the category set fails, the app falls back toward Silent-Mode-bound foreground audio. Keeping the session on `.playback` is what lets podcast audio survive lock, backgrounding, and the ringer switch.

### Fixed — Tuner QA polish
- **Home, Library, Queue, and Player icon keys keep their compact Tuner visuals inside 44pt hit targets**, preserving the instrument-panel look without tiny tap zones.
- **Xcode source warnings from the QA pass were cleaned up** while leaving only the generic project recommended-settings warning.

### Fixed — large OPML import performance
- **OPML batch import no longer fetches every feed twice.** The importer now applies the parsed feed metadata directly after the first network fetch instead of resolving the OPML row and then re-syncing the same URL immediately afterward.
- **Large libraries now dedupe feed URLs before work starts.** OPML exports with repeated URLs (including case/trailing-slash variants) preserve the first row and skip duplicates before progress tracking and import tasks are created.
- **Bulk imports avoid per-episode AI/chapter network fan-out.** OPML batch rows import the newest bounded episode set with cheap local topic profiles and defer full FoundationModels enrichment plus external chapter fetches to later sync paths, removing the worst multiplier for 50+ show libraries.
- **OPML `feed://` URLs now normalize through the same feed URL path as paste import.** Feed URL dedupe also collapses `http`, `feed`, default ports, fragments, and trailing slashes.
- **Batch import cancellation now stops enqueueing more feeds** and the Library strip reports completed rows instead of only added rows, so failed feeds do not make progress look stalled.

## [2.3.11] — 2026-04-27

Polish round 4 — performance, race fixes, accessibility hints from a final pre-release audit.

### Fixed — `LibraryView` performance on heavy listeners
- **`@Query` was fetching every Episode in the database, on every render.** The two derived arrays (`inProgressEpisodes`, `freshEpisodes`) filtered in Swift after a fetch-all. With 30 subscriptions and a 2k-episode back catalog (typical OPML import from a long-time listener), every Library render hydrated 2,000 model objects into memory just to drop most of them.
- **Now uses two predicate-filtered `@Query` declarations** that push the `isSubscribed && !isPlayed [&& playedPosition > 0]` check down to SQLite. Only the matching rows hydrate.
- **Per-podcast counts pre-bucketed once** instead of recomputed inside the `ForEach` over subscribed shows. The prior loop was O(N×M) — for each podcast row, it filtered `freshEpisodes` to count that podcast's unplayed episodes. With 30 podcasts and 2k episodes that's 60k iterations per scroll frame. Now O(N+M) total: build a `Dictionary<UUID, Int>` once, look up by podcast id.

### Fixed — race between unsubscribe and currently-playing episode
- `PodcastUnsubscribeService` deleting downloaded files for an unsubscribed podcast could fire while `AVPlayer` was mid-read on the local file URL — the file got removed from under the player. Now checks whether the currently-playing episode belongs to the podcast being unsubscribed and pauses playback first via the new `PlaybackController.pause()` public method. Without this the symptom was either silent corruption or a crash on some iOS versions.

### Added — accessibility hints
- PlayerView SPEED Menu — `accessibilityLabel("Playback speed") / accessibilityHint("Pick a speed for this podcast")`. VoiceOver previously announced just the visual label with no context about the Menu's purpose.
- PlayerView SLEEP Menu — same treatment, with hint that adapts to whether a timer is currently active.

## [2.3.10] — 2026-04-27

Polish round 3 — cascade cleanup, leaked references, and the residual punch list from a fresh re-audit.

### Added — proper unsubscribe cascade
- **`PodcastUnsubscribeService`** centralizes everything that has to happen when a user removes a show: marks the podcast `isSubscribed = false`, dequeues its episodes, **deletes downloaded audio files** for those episodes, **de-indexes them from CoreSpotlight** (so iOS Search stops surfacing them), and saves once at the end. Previously the unsubscribe handler in `LibraryView` only did the queue cleanup — Spotlight kept surfacing episodes from shows the user no longer followed for up to a month, and downloaded files sat on disk forever.
- **`SpotlightIndexer.deindexEpisodes(ids:)`** API. Per-podcast scoped — `deleteAll()` was the only existing wipe option. Used by the new unsubscribe service.
- Confirmation dialog copy updated to reflect the broader cleanup ("dequeues its episodes, deletes any offline downloads, and stops it from appearing in iOS Search").

### Fixed — DownloadService task leaks
- The `taskToEpisodeID` and `episodeIDToTask` dictionaries used to leak entries forever when an episode was deleted while its download was in-flight (the guard for `episode(for:)` returning nil just silently returned). Now the deleted-episode case explicitly cancels the task, removes both dictionary entries, and (on completion) deletes any partially-downloaded file. Three completion paths fixed: `didWriteData`, `didFinishDownloadingTo`, and `didCompleteWithError`.

### Fixed — second-pass audit findings
- **`AppTheme.swift` artwork gradient** was using `Color.black.opacity(0.08)` inline — switched to `Color.offscriptStudioBlack.opacity(0.08)` per the named-token rule (CLAUDE.md forbids bare white/black opacity).
- **`AppTheme.swift` shimmer overlay** was using `Color.white.opacity(0.08)` inline — switched to `Color.offscriptHairline`.
- **`QueueTunerHeader` two-eyebrow row** was missing `lineLimit(1)` on both labels, so the "QUEUE · WORKING SET" eyebrow could wrap onto the "Queue" headline at large Dynamic Type sizes. Same fix already applied to `HomeTunerHeader`, `SettingsHeader`, and `LibraryImportSheet` header in earlier rounds.
- **`LibraryBatchImportStrip` × DISMISS** key was a 36pt-tall touch target. Expanded to 44pt minimum with `contentShape(Rectangle())` and added `accessibilityLabel`.
- **`LibraryImportSheet` paste-URL × clear button** was 24×24 — well below HIG minimum. Expanded to 44×44 with `contentShape(Rectangle())` and `accessibilityLabel`.
- **`SearchView` error strip** had no recovery affordance. Added an inline `↻ RETRY` Tuner key so transient network errors don't require the user to retype the query.

## [2.3.9] — 2026-04-27

Polish pass driven by three parallel audits (UI consistency, feature correctness, lifecycle/edge-case). The list below covers the high-impact fixes; the remaining items roll forward to follow-up pushes.

### Fixed — UI consistency (Tuner vocabulary)
- **`CardComponents.swift` play buttons** were using `Circle().stroke(...)` — last remaining Tuner sharp-rectangle violations after the v2.3.2 sweep. Fixed in both EpisodeVerticalCard (rail card) and EpisodeCompactCard (list row).
- **`CardComponents.swift` podcast title color** was rendering in `offscriptSignalYellow` (yellow accent) on rail and list cards. Switched to `offscriptFnInfo` (cyan) per the function-coded color system. Yellow is reserved for actionable / accent state, not metadata labels.
- **`EpisodeDetailView.swift` podcast title** was rendering in `offscriptFnRecord` (record red) — same bug class fixed in QueueLeadStrip (2.3.2) and PlayerView artwork block (2.3.4). Switched to `offscriptFnInfo` cyan.
- **`PodcastDetailView` was using `.searchable()`** for episode search — iOS 26 renders that as a translucent rounded capsule that clashes with every other Tuner surface. Replaced with the custom Tuner `tunerEpisodeSearchField` (hairline rectangle, mono prompt, signal-yellow magnifier, sharp `×` clear).
- **SettingsView and LibraryImportSheet `.toolbar` ToolbarItem `Done` button** — iOS 26 wraps toolbar buttons in glass-capsule chrome that ignores `.plain` styling. Both DONE keys moved inline into their respective headers using the same Tuner sharp-rectangle vocabulary as every other action key.

### Fixed — hit targets
- Settings cog (Home + Library), Import key (Library), search-clear `×` (Search), card play / menu / remove buttons (CardComponents) — all expanded to 44pt hit targets with `contentShape(Rectangle())` while keeping the visual size. Several were as small as 24×24, well below HIG minimum.

### Fixed — playback correctness
- **AVPlayerItem error handling.** `PlaybackController` was creating a fresh `AVPlayerItem` and calling `player.play()` with no observation — if the audio URL 404'd, the codec was unsupported, or the network dropped, the UI sat in "playing" state with no audio and no error feedback. Now KVO-observes `item.status` plus the `AVPlayerItemFailedToPlayToEndTime` and `AVPlayerItemPlaybackStalled` notifications, surfaces a `playbackError` published string, and PlayerView renders an inline error strip with a dismiss key. Errors auto-clear on the next ready-to-play.
- **Now Playing artwork.** Lock screen and Control Center showed the episode title and podcast but no artwork — looked broken next to Apple Podcasts. `updateNowPlaying(for:)` now fetches artwork off-main and posts it to `MPNowPlayingInfoCenter` via `MPMediaItemArtwork`. Local file URLs read sync; remote URLs fetch on a utility-priority detached task.
- **Now Playing playback rate.** The published rate to MPNowPlayingInfoCenter was hardcoded to `1.0` — when the user picked a custom rate via the per-podcast picker, the lock screen / scrub UI still treated it as 1×. Now reflects the actual `playbackRate`. Also publishes `MPMediaItemPropertyArtist` so the lock screen shows author + show, not just show.
- **Sleep timer surviving backgrounding.** Previous timer used `Task.sleep(for: minutes)` which suspends with the app, so a timer set for 5 min would just freeze if the app spent any time backgrounded. Replaced with a wallclock-based loop that wakes every second, plus a `reevaluateSleepTimerOnForeground()` call wired to `scenePhase == .active` so a timer whose deadline passed during suspension fires the moment the app foregrounds.

### Fixed — silent failure
- **`DownloadService.swift:199` force unwrap.** `originalURL?.pathExtension.isEmpty == false ? originalURL!.pathExtension : "mp3"` crashed if `originalURL` was nil because the false-branch fell through to a force-unwrap. Replaced with a guard-let block that defaults to `"mp3"` cleanly.
- **Bare `try? save()` migrated to `saveOrLog`** across `DownloadService` (12 sites), `BackgroundFeedRefresh` (2), `SyncCoordinator` (3), `TelemetryService` (1). New `ModelContext.saveOrLog(category:)` helper logs the failing category + error description via OSLog instead of dropping the error on the floor. CLAUDE.md forbids bare `try?` for exactly this reason — silent save failure is the worst kind of failure to debug.

### Fixed — input safety
- **Recent searches delimiter escape.** Search history is stored as a single string joined by `\u{1F}` (UNIT SEPARATOR). If a user query somehow contained that control character, `split(separator:)` would corrupt the list on next read. Now defensively rejects queries containing the delimiter on store.
- **OPML import HTML rejection.** Pasting a feed URL that returns 200 OK with `Content-Type: text/html` (a misconfigured server's landing page at a feed-shaped URL) used to parse as an empty `ParsedFeed` — looked like "we found a feed but it has no episodes" instead of "this isn't a feed." Now rejects HTML responses up front with the proper `feedParseFailed` error.

## [2.3.8] — 2026-04-27

### Added — cold-start "Start Here" rail
- **Replaces the dead-end empty state on Home.** Before, a fresh install showed "Add three shows you trust" with a "→ BROWSE SEARCH" button — useful only if the user already knew exactly what they wanted to type. Now Home renders a curated "● START HERE" rail with 14 hand-picked podcasts grouped by category (News & Culture, Tech & Design, Story & Reporting, Ideas & Conversation, Humor). One-tap "+ ADD" subscribes through the same `FeedSyncService.importPodcast` pipeline that Search and OPML import use, so subscribed-state and library display behave identically.
- **Self-hides as soon as recommendations have data.** The starter rail only renders when `sections.isEmpty` — once the user subscribes to a few shows and the recommendation engine populates the home feed, the curated rail steps aside without ceremony.
- **`StarterRailService`** holds the curation as a single source of truth — easy to update without touching view code, and easy to swap to a network-backed source later if we want trending picks instead of static curation.

### Curation philosophy
Picks are well-loved, broadly accessible shows that hold up over years rather than ride-the-charts trendy picks. One per slot in each section so the rail doesn't feel like an algorithmic feed and the user can tell each was deliberately chosen. Five categories, three picks each (humor has two) — a structure that makes "I'll grab one from each" feel like a complete onboarding gesture.

## [2.3.7] — 2026-04-27

### Added — OPML export
- **OPML export from the import sheet.** "↑ EXPORT N SUBSCRIPTIONS" key on the menu generates a standards-compliant OPML 2.0 file from every subscribed podcast and presents the system share sheet — Save to Files, AirDrop, Mail, etc. The format matches what Apple Podcasts / Pocket Casts / Overcast / AntennaPod accept, so an OffScript export imports cleanly into any of them. Closes the loop with the OPML import path: users can move out as easily as they moved in.
- **`PodcastOPMLExporter`** — minimal XML-escape-aware exporter writing `<outline type="rss" text=… title=… xmlUrl=… author=… />` per subscribed podcast. Author attribute is included only when present. Filename includes ISO timestamp.

### Added — Settings playback parity
- **Default playback rate** picker in Settings → Playback. Sets the rate new podcasts inherit before the user picks something specific in the player (per-podcast picks still win). Same intervals as the player menu (1.0× / 1.1× / 1.25× / 1.5× / 1.75× / 2.0× / 2.5×).
- **Reset per-podcast rates** action in the same section. Wipes every show's custom playback speed back to the default — escape hatch for "I accidentally tasted everything to 2× and want out."

## [2.3.6] — 2026-04-27

### Added — OPML import is now a background process
- **`BatchImportService` singleton** owns the work, not the sheet. Tap "→ IMPORT ALL · IN BACKGROUND" and the sheet is free to close — the batch runs to completion regardless of where the user navigates. Reopening the sheet picks up the live state. Bounded 6-way `withTaskGroup` parallelism, episode-limit-25 per feed.
- **`LibraryBatchImportStrip`** — Tuner-styled status strip at the top of the Library page. While running: signal-yellow progress rail with `added/total` counter. Finished: `✓ IMPORT COMPLETE` (or `● IMPORT FINISHED` when any feed failed) with a "× DISMISS" key. Idle: invisible. The user always knows what's happening without having to open the sheet.

### Fixed — Home screen overlap
- **Hero-card metadata duplication.** The "X LEFT — PICK UP WHERE YOU STOPPED" reason tag and the "● X LEFT" metadata row were saying the same thing on adjacent rows. Stripped the metadata row to date + duration only; the tag carries the remaining-time signal.
- **Single-line lock on the dual-eyebrow row.** `HomeTunerHeader` was rendering "TODAY · MON, APR 27" + "OFFSCRIPT · CHANNEL FEED" without `lineLimit`, so at larger Dynamic Type sizes either side could wrap and collide with the "Home" title below. Both eyebrows now lock to one line; truncation is preferable to overlap.

## [2.3.5] — 2026-04-27

### Fixed — Sign in with Apple (was silently broken)
- **Missing entitlement.** `OffScript.entitlements` had no `com.apple.developer.applesignin` capability. Without it, every `ASAuthorizationController.performRequests()` call failed at the system level — but the failure callback wasn't logged, so the symptom was just "the button does nothing." Added `Default` scope so the app can request user identity at sign-in time.
- **Missing `presentationContextProvider`.** iOS 26 has multiple connected scenes, and `ASAuthorizationController` will refuse to present its sheet without an explicit window anchor. The Coordinator now conforms to `ASAuthorizationControllerPresentationContextProviding` and returns the foreground-active key window — falls back to the first active scene's window, finally to a fresh `UIWindow()`, so it's never nil.
- **Controller release race.** The local `ASAuthorizationController` lived only in `handleSignIn()`'s scope, which meant ARC could free it before the delegate callback fired (Apple's API expects the caller to hold a strong reference until completion). The Coordinator now keeps an `inFlightController` reference, cleared on success or error.
- **Silent error handling.** The `didCompleteWithError` callback used to just call `onComplete()` and swallow the error. Now logs via OSLog so the actual reason surfaces in Console.

### Fixed — OPML import was unbearably slow
- **Sequential → 6-way bounded parallelism.** Previously, each OPML row resolved + imported in series; a 50-podcast OPML easily took multiple minutes because most of that wall time was idle waiting on per-feed network round-trips. `batchImportOPML` now runs 6 imports concurrently via `withTaskGroup`, priming the pump and keeping the pipeline full as each completes. ~6× faster end-to-end on typical OPML sizes.
- **Episode limit on initial sync.** OPML imports were pulling the entire back catalog for every feed (some podcasts have 500+ episodes). Now passes `episodeLimit: 25` so each show lands fast with recent episodes — background refresh fills in older episodes later. Cuts per-feed time from seconds to ~half a second on most feeds.

### Changed
- Sign-in with Apple button radius dropped from 18 → 0 to align with the Tuner sharp-rectangle vocabulary. Style is otherwise stock Apple, since their button design isn't ours to override.

## [2.3.4] — 2026-04-27

### Added — PlayerView depth pass
- **Chapters in PlayerView.** The model already parsed PSC chapter tags + summary timestamp patterns via `EpisodeChapterParser` for months — the data was on the model graph and just never rendered. Now there's a "CHAPTERS · TAP TO SEEK" section between the transport row and Up Next that:
  - Lists every chapter with `01·02·03` rank prefixes, mono start times, and the chapter title
  - Highlights the current chapter in signal-yellow with a `▶` glyph (recomputed against `player.currentTime`, so it tracks live as playback crosses each marker)
  - Tap-to-seek — tapping any row jumps playback to that chapter's start time
  - Self-hides when the episode has no chapters, no empty state churn
- **Sleep timer.** SLEEP key in the Player controls row, with the standard podcast app intervals (5 / 15 / 30 / 45 / 60 min). Active timer shows live `mm:ss` countdown directly on the key in signal-yellow; tapping reveals the Cancel option. Implementation in `PlaybackController.setSleepTimer(minutes:)` / `cancelSleepTimer()` — `Task.sleep` based, cancelled cleanly on deinit and on rescheduling.
- **Per-podcast playback rate.** Speed menu now sets the rate per podcast — pick 1.5× for a fast-talker, 1.0× for narrative, and OffScript remembers each choice. The SPEED key on the Player turns signal-yellow when the current podcast has a custom pace so you can see at a glance you're not on the default. Storage is `UserDefaults`-keyed by podcast UUID via `PodcastPlaybackPreferences` — no SwiftData migration for what's a UI preference, not a content fact. Rate menu expanded to 1.0× / 1.1× / 1.25× / 1.5× / 1.75× / 2.0× / 2.5× to match what every other podcast app offers.

### Added — MiniPlayer transport
- **Skip-back-15 and skip-forward-30 keys** flanking the play key in the MiniPlayer. Same icons (`gobackward.15`, `goforward.30`) and skip amounts as the lock-screen / CarPlay remote commands so the muscle memory transfers. The most-frequent in-app interactions (rewind a phrase, skip an ad) no longer require opening the full player. Hidden when there's no real duration so they don't sit dead on a fresh load.

### Fixed
- **PlayerView artwork block** was using `TunerTag` with `offscriptFnRecord` (record red) for the podcast title — same bug class as the QueueLeadStrip fix in 2.3.2. Switched to `TunerLabel` in `offscriptFnInfo` (cyan), matching every other place a podcast title is shown.

## [2.3.3] — 2026-04-27

### Added — import functionality
- **Paste-URL import.** Library header has a new Import key (`square.and.arrow.down`, next to the settings cog). Pasting a podcast feed URL fetches the feed once, parses title + author + artwork + summary, and lands the show in the library indistinguishably from a search-tap import. Tolerates URLs without a scheme (auto-prefixes `https://`), tolerates `feed://` URLs, rejects obvious non-URLs (search terms, single words). All errors surface inline in the import sheet with the actual reason — no silent failures.
- **OPML import.** Same Import key opens the file picker for OPML files exported from Apple Podcasts, Pocket Casts, Overcast, AntennaPod, and gPodder. Parser is forgiving across the slight format variations between exporters (xmlUrl casing, text vs. title attribute, missing type=rss). Preview screen shows every feed found in the file with `01·02·03` rank prefixes. "→ IMPORT ALL" runs them sequentially with per-row status (`○ STANDBY / ● IMPORTING / ✓ ADDED / ✕ FAILED`) — one bad feed doesn't fail the whole batch.
- **`PodcastImportService`** — single source of truth for "raw URL or OPML entry → `PodcastSearchResult`" resolution. URL paste, OPML, and the existing search-tap path all converge on `FeedSyncService.importPodcast(...)` so subscribed-state, sync, and library-display behavior is identical across all three.
- **`LibraryImportSheet`** — Tuner-styled sheet with a three-mode state machine (menu → paste URL or OPML preview). Hairline-rule sections, mono status badges, function-coded colors, sharp-rectangle keys throughout — same vocabulary as every other Tuner surface.

### Why this was missing
Until now, the only way to add a podcast was to type the title into Search and hope iTunes had it indexed. No feed-URL paste, no OPML, no migration path from another podcast app. That's the highest-friction gap in the app for anyone arriving from Overcast / Pocket Casts / Apple Podcasts.

## [2.3.2] — 2026-04-27

### Fixed — playback (root-cause fix for two reported bugs)
- **Audio now keeps playing when the app is backgrounded.** Root cause: `Info.plist` was missing `UIBackgroundModes → audio`. Without that key, the `setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)` call threw at session-configure time — the bare `try?` swallowed the throw — and iOS fell back to the default `.soloAmbient` category, which suspends in background. Adding the entitlement makes the call succeed, the session sticks at `.playback`, and audio survives backgrounding.
- **Audio now plays through the silent / ring-mute switch.** Same root cause — `.soloAmbient` respects the silent switch by spec; `.playback` does not. Fixing the Info.plist key fixes both reported symptoms with one change.
- **Phone calls / Siri no longer kill playback permanently.** Added `AVAudioSession.interruptionNotification` handling — pause on `began`, resume on `ended` if the system signals `shouldResume`. Was missing entirely; an interrupted episode would never resume even after the call ended.
- **Headphone / Bluetooth unplug correctly pauses** instead of blasting through the speaker. Added `AVAudioSession.routeChangeNotification` handling for `oldDeviceUnavailable`.
- **Media-services reset recovery.** Added `mediaServicesWereResetNotification` handler that re-runs `configureAudioSession()` and resumes if we were playing. Rare but real — if iOS resets media services while in background, the session needs to be recreated from scratch.
- **Lock-screen / CarPlay / Control Center play command** now re-activates the audio session before resuming, matching the in-app `togglePlayPause()` path. Was missing — remote-command resume could fail silently if the session had been deactivated by another app.

### Changed — Tuner sharp-rectangle vocabulary, end-to-end
- **`TunerTag` was secretly using `Capsule()` for its outline.** That meant every reason badge across the app — hero card "PICK UP WHERE YOU STOPPED", lead-card explanation chips, AI reason tags, queue-lead podcast title — was rendered as a rounded pill, violating the Tuner sharp-rectangle rule. Swapped to `Rectangle()`. One-line fix surfaces consistently everywhere `TunerTag` is used.
- **`EpisodeDetailView` "QUEUE" / "QUEUED" button** outline was the last `Capsule().stroke` left in the screen-level UI. Swapped to `Rectangle().stroke`.
- **`QueueLeadStrip` podcast title color**: was rendering in `offscriptFnRecord` (record red), which is the function-coded color reserved for destructive / error signals (× CLEAR ALL, × REMOVE). Switched to `offscriptFnInfo` (cyan), matching every other place a podcast title is shown — and switched from `TunerTag` to a `TunerLabel` since the rectangle chrome was redundant.

### Removed — dead `AppTheme.swift` primitives left over from the editorial direction
- `PrimaryPillButtonStyle` / `SecondaryPillButtonStyle` — the old orange-pill Resume button and glass-pill Queue button. All call sites migrated to inline Tuner sharp-rectangle keys.
- `SkeletonRailCard` / `SkeletonHeroCard` / `SkeletonSearchRow` — pre-Tuner shimmer skeletons with rounded fills + capsule chips. Tuner rails render hairline-rectangle placeholders inline; nothing referenced them.
- `GrainOverlay` / `offscriptGrain` extension + the `SplitMix64` PRNG it used — the editorial-paper grain texture from the warm-amber direction. Tuner is flat OLED black; no grain belongs.

### Net effect
- Two reported playback bugs fixed by a one-key Info.plist correction (the actual fix) plus four AVAudioSession-level handlers that should have always been there (the production-readiness fix).
- Zero remaining `Capsule()` / rounded chrome in the Tuner UI vocabulary. Sharp rectangles everywhere.
- ~150 lines of dead code removed from `AppTheme.swift`.

## [2.3.1] — 2026-04-27

### Changed — Tuner finishing pass
- **`ImportProgressView`** (onboarding step 03) ported to Tuner spec sheet vocabulary. Was the last screen still using centered-loading editorial layout with big spinner + checkmark. Now uses the `03 · TUNING` eyebrow + `● TUNING N/M` status badge + `Tuning channels…` headline + hairline-divided per-channel rows with `01·02·03` rank prefixes and mono `○ STANDBY / ● TUNING / ✓ TUNED / ✕ FAILED` status labels. Function-coded colors line up with the rest of the app.
- **`DownloadButton`** ported. Was the last `SecondaryPillButtonStyle` (rounded capsule) in the codebase. Now sharp hairline rectangle with mono status text and function-coded color (signal-yellow for actionable / mode-green when downloaded / record-red on failure).
- **In-line Tuner progress rails** in `EpisodeDetailView` + `CardComponents.EpisodeVerticalCard` (replaces removed `OffScriptProgressBar`).

### Removed — dead code in `AppTheme.swift`
12 view structs that had no callers after the Tuner port — keeping them around made the design system look like two vocabularies were still in active use:
- 7 legacy editorial-direction views: `OffScriptReasonBadge`, `OffScriptExplanationTag`, `OffScriptEmptyState`, `OffScriptSectionHeader`, `OffScriptUtilityHeader`, `OffScriptProgressBar`, `OffScriptScrubber`.
- 5 unused Tuner primitives: `TunerRingMeter`, `TunerTrace`, `TunerTransportButton`, `TunerModeToggle`, `TunerArtworkTile`. Designed for the spec but never composed into actual screens — Player built its own transport row, scrubber went native `Slider`, rail cards use sharp `OffScriptArtworkView` tiles, filter chips landed as inline Tuner buttons.

### Changed — design bible
`CLAUDE.md` rewritten. Was still describing the old warm-amber editorial direction (Playfair Display, gradient cards, 12/24/32pt radii) — completely stale relative to what shipped. Now documents the Tuner OLED instrument-cluster direction, the iOS 26 chrome trap (don't use `TabView`/`.toolbar`/`.searchable`), the spec-sheet skeleton every screen follows, the component cheat sheet (`TunerLabel`, `TunerTag`, inline Tuner action buttons), and the operational tooling (Xcode Cloud + simctl audit pattern).

## [2.3.0] — 2026-04-27

### Changed
- **Full Tuner OLED port across the rest of the app.** The 2.0 design landing only touched `EpisodeDetailView` + design tokens; `HomeView`, `LibraryView`, `QueueView`, `SearchView`, `SettingsView`, `MiniPlayer`, and `PlayerView` still rendered with the old editorial vocabulary (rounded gradient cards, `OffScriptSectionHeader`, `OffScriptUtilityHeader`, `OffScriptExplanationTag`, `HeroRecommendationCard`). They had the new colors but the old layout — that's the "UI not fully implemented" feeling. Every top-level surface now uses the spec-sheet vocabulary: `TunerLabel` eyebrows, hairline-rule section dividers, mono channel readouts, sharp 3pt artwork tiles with hairline borders, no surface modifiers, sharp-cornered Tuner action buttons.
  - `MiniPlayer` — flat-black strip with single-pixel signal-yellow progress rail, 44pt-tap signal-yellow square play key, mono `● PLAYING` / `❙❙ PAUSED` status badges
  - `HomeView` — `HomeTunerHeader` with TODAY · DAY DATE eyebrow, `HeroTunerCard` with Tuner action keys (`→ PLAY` / `+ QUEUE`), `TunerRail` / `TunerRailCard` with mono channel readouts
  - `PlayerView` — full spec sheet (PLAYER · NOW PLAYING header, POS / REM mono readouts, signal-yellow tick rule scrubber, 4-key transport row with hairline buttons, UP NEXT + WHAT'S NEXT + CONTROLS sections all hairline-divided)
  - `LibraryView` — channel directory layout, `01·02·03` numbered channel rows, mono stat readouts (SHOWS · UNPLAYED · IN PROGRESS), Tuner episode rails
  - `PodcastDetailView` — channel detail spec sheet with `001·002·003` episode numbering, mono metadata, Tuner action buttons
  - `QueueView` — working-set spec sheet, `02 RANK ARTWORK TITLE` row layout, `× CLEAR ALL` action, NEXT UP lead strip
  - `SearchView` — signal scan layout with starter-topic mode toggles, hairline-divided result rows numbered `01·02·03`
  - `SettingsView` — config panel with stat readouts, Tuner toggles, hairline-divided sections (PLAYBACK / ICLOUD SYNC / ABOUT)
- **3 Apple AI cards refactored** to spec-sheet vocabulary on `EpisodeDetailView`. They were rounded panel cards stuck inside an otherwise-Tuner screen — `TunerLabel` eyebrow + hairline rule + content, no surface wrapper, mono numbered bullets in the briefing, function-coded status badges (`● REC` / `● READY` / `● ERROR`).

### Notes
- All sections now use the same vocabulary defined by the existing `TunerLabel`, `TunerTag`, and surface conventions in `AppTheme.swift`. No new design primitives were added — this is purely catching the rest of the app up to the language `EpisodeDetailView` was already speaking.

## [2.2.3] — 2026-04-27

### Added
- **Now Playing widget** restored — five families: systemSmall, systemMedium, accessoryCircular, accessoryRectangular, accessoryInline. Tap deep-links into the player.
- **Live Activity / Dynamic Island** restored — compact / expanded / minimal layouts + Lock Screen banner.
- `OffScriptWidgets` app-extension target back in the project (re-added via `scripts/add_widget_extension.rb`).
- App Group `group.com.offscript.shared` registered in Apple Developer Portal and bound to `com.offscript.app` + `com.offscript.app.widgets`. Both targets' entitlements + `NowPlayingStorage.suiteName` reference it.

### Notes
- Original identifier `group.com.offscript.app` was unavailable globally, swapped to `group.com.offscript.shared`. Source updated in lockstep across 5 files in [`8568b61`](https://github.com/zachyzissou/offscript/commit/8568b61).
- This is the first ship through the new Xcode Cloud pipeline that includes both an app and an app-extension target with shared App Group state. Apple-managed signing handles both bundle IDs automatically.

## [2.2.2] — 2026-04-27

### Changed
- **CI pivoted from GitHub Actions to Xcode Cloud.** Apple-managed signing certs (no per-account cap), automatic provisioning profile generation, native TestFlight upload action. The previous `.github/workflows/testflight.yml` was fighting Apple's signing infrastructure — now `.disabled`, kept as fallback.
- New `scripts/app_store_connect.py` subcommands for fully-automated Xcode Cloud ops: `xcode-cloud probe`, `inspect`, `reconfigure`, `start-build`, `build-run`. Created/PATCHed via the App Store Connect API — no clicking through web UIs required.
- `.github/workflows/xcode-cloud-probe.yml` — on-demand workflow for probe/inspect/reconfigure/start-build/build-run, runnable from Actions tab without local creds.
- `ci_scripts/ci_post_clone.sh` — Xcode Cloud post-clone hook that materializes `Config/Secrets.xcconfig` from the `SENTRY_DSN` env var.
- `CONTRIBUTING.md` "Releasing" section rewritten — two trigger paths (push to main / cut `vX.Y.Z` GitHub Release), operational tooling reference, "Why we left GH Actions behind" footnote.

### Fixed
- `.claude/worktrees/hardcore-villani` was indexed as a stale 160000 (gitlink) entry, producing `GitCloneStep` warnings on every Xcode Cloud build. Removed via `git rm --cached`.
- App Group entitlement (`group.com.offscript.app`) on the host app was breaking the ExportArchive step because the App Group itself wasn't registered in App Store Connect. Removed pending widget extension re-add.

## [2.2.1] — 2026-04-27

### Fixed
- **TestFlight signing failure** introduced in 2.2.0. The new `OffScriptWidgets` app-extension target needs `com.offscript.app.widgets` registered in App Store Connect with the App Groups capability + a provisioning profile that includes `group.com.offscript.app` before CI can sign it. Stripped the target via `scripts/remove_widget_extension.rb` so the host app + Apple AI features ship cleanly. The Swift sources stay in `OffScriptWidgets/` for the follow-up.
- Apple Developer cert limit (3 iOS distribution certs / account) was also being hit by the auto-create flow for the new bundle ID. Revoke an unused cert in the developer portal before re-adding the widget target.

### Deferred
- Now Playing widget + Live Activity / Dynamic Island. Re-add by:
  1. Register App ID `com.offscript.app.widgets` in [Apple Developer Portal](https://developer.apple.com/account/resources/identifiers/list) with App Groups capability enabled.
  2. Add `group.com.offscript.app` under App Groups; assign it to both bundle IDs.
  3. Revoke an unused iOS distribution cert if at the 3-cert limit.
  4. Run `scripts/add_widget_extension.rb` to put the target back, push, watch CI ship.

## [2.2.0] — 2026-04-27

### Added
- **Apple Intelligence pre-listen briefing.** `EpisodeBriefingView` generates a 3-bullet "what you'll learn" + one-line hook on-device via `FoundationModels` `@Generable`. Hidden silently on devices without Apple Intelligence. Cached per episode ID.
- **On-device Translation** for non-English episodes via Apple's `Translation` framework. Source language detected with `NLLanguageRecognizer`. Hidden when source matches user locale.
- **On-device Speech transcription.** `SpeechTranscriptionService` + `SpeechTranscriptionPanel` use Apple's `Speech` framework with `requiresOnDeviceRecognition=true` — audio never leaves the phone. Persisted via new `EpisodeTranscriptCache` SwiftData model so transcripts survive restart.
- **`SpeechAnalyzerService` scaffold** for iOS 26+ streaming transcription with progress callback. Falls through to `SFSpeechRecognizer` until the iOS 26 SDK lands.
- **Background opportunistic transcription.** `BackgroundTranscriptionService` runs after a successful download when on Wi-Fi + power. Bounded fetch (25 newest), one episode at a time, skips > 90 min and already-transcribed.
- **Siri / Shortcuts via App Intents.** `OffScriptAppIntents` ships ResumeListening / Pause / SkipForward / PlayNextInQueue. "Hey Siri, resume OffScript" works without unlocking.
- **Spotlight donations.** `SpotlightIndexer` donates up to 500 newest subscribed episodes to CoreSpotlight in batches. iOS system search and Siri Suggestions surface OffScript episodes. 24h debounce, 30-day item TTL.
- **Now Playing widget** (Lock + Home + Watch surfaces) — five families: systemSmall, systemMedium, accessoryCircular, accessoryRectangular, accessoryInline. Tap deep-links into the player.
- **Live Activity / Dynamic Island** for now-playing — compact / expanded / minimal layouts + Lock Screen banner. Updated by `NowPlayingPublisher` from main app via `ActivityKit`.
- **Deep links.** `offscript://` URL scheme registered. `DeepLinkRouter` handles `offscript://player`, `/episode/<uuid>`, `/episode/<uuid>/play`, `/podcast/<uuid>`. Wired via `.onOpenURL` + `.onContinueUserActivity(CSSearchableItemActionType)` for Spotlight result taps.
- **`PlaybackController.load(_:in:)`** — load an episode without auto-starting playback (used by the no-autoplay deep-link path).
- **AI-driven WHY copy generator** (`RecommendationExplainer`) — full generation + lightweight rephrase via `FoundationModels`. Service ready; rail-card swap-in deferred to a follow-up.

### Changed
- **TestFlight workflow now release-driven.** Cutting a GitHub Release with a `vX.Y.Z` tag triggers a TestFlight build that uses the release tag as `MARKETING_VERSION` and the release body as the TestFlight What-To-Test notes. Push-to-main still works (auto-cuts a prerelease GitHub Release tagged `testflight-X.Y.Z-build.N` after a successful TestFlight ship).
- New `OffScriptWidgets` app-extension target wired via `scripts/add_widget_extension.rb` (idempotent xcodeproj-gem setup).
- App Group `group.com.offscript.app` shared between main app and widget extension via entitlements.
- `EpisodeTranscriptCache` `@Model` added to `SchemaV1.models` (additive lightweight migration — existing data persists).

### Infrastructure
- `Info.plist` additions: `NSSpeechRecognitionUsageDescription`, `NSSupportsLiveActivities`, `NSSupportsLiveActivitiesFrequentUpdates`, `CFBundleURLTypes` for `offscript://`.
- `OffScript.entitlements` adds `com.apple.security.application-groups`.
- `permissions: contents: write` on TestFlight workflow so it can cut releases + push tags.

## [2.0] — 2026-04-26

### Added
- **Tuner OLED design direction.** Pure black field, signal-yellow primary accent, function-coded tag pills (record-red / mode-green / power-yellow / info-cyan), single-pixel hairlines, monospaced metadata. Replaces the previous warm-amber editorial direction.
- New design primitives: `TunerTag`, `TunerRingMeter`, `TunerReadout`, `TunerTrace`, `TunerTransportButton`, `TunerModeToggle`, `TunerLabel`, `TunerArtworkTile`.
- New onboarding flow: POWER ON welcome → "01 · TASTE / Pick your bands" → "02 · CHANNELS / Tune the bank" → import.
- New EpisodeDetail spec sheet layout with Ferrari-cluster readouts.
- New app icon: signal-yellow VU dial on OLED black with REC indicator.
- **Sentry-Cocoa** integration (errors-only, quota-aware): sampleRate 1.0 for errors, 5% perf transactions, no profiling, screenshot/view-hierarchy capture off for privacy.
- **MetricKit** subscription via `MetricKitReporter` — daily metric payloads logged via OSLog, crash diagnostics forwarded into Sentry as `.fatal` events.

### Changed
- All theme tokens (`offscriptAccent`, `offscriptCard`, `offscriptBackground`, etc.) remap to Tuner OLED palette automatically — every existing surface inherits the new look without per-view rewrites.
- `OffScriptScrubber` rebuilt as instrument-scale rule (60-tick major/minor/fine, thin playhead, NOW caption) — replaces the previous capsule + thumb scrubber.
- `OffScriptProgressBar` reduced to 1px hairline + signal-yellow fill — replaces the gradient capsule.
- Surface modifier (`offscriptSurface` / `offscriptUtilitySurface`) switched from gradient cards to flat black + 1px hairline; corner radii reduced to 3-6 pt (was 16-32 pt).
- Typography swapped from Playfair Display to SF Pro Display at light weights with tight tracking; SF Mono with wide tracking for all metadata.

### Fixed
- CI TestFlight upload: `AppIcon.appiconset/Contents.json` had iOS universal entries with no `filename`, so the asset compiler shipped icon-less bundles and ASC rejected the upload (missing 120/152 px icons + `CFBundleIconName`). Wired `AppIcon.png` into all three iOS universal entries.
- CI signing: rotated `ASC_KEY_P8_BASE64` GitHub secret to a working API key with provisioning-profile cloud-fetch permissions.

## [1.14.1] and earlier

See git history. Pre-2.0 versions used the warm-amber editorial direction and shipped via manual `xcodebuild` runs.

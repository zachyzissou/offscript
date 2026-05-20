# Offline-download pipeline audit — 2026-05-19

Phase 1 of `docs/NEXT_IMPLEMENTATION_BACKLOG.md`. Branch
`audit/expanded-surface-2026-05-19`, baseline HEAD `cce3d81`. Mirrors the
Phase 12 / Phase 14 audit shape (scaffolding → gap inventory → surgical
fixes → tests → docs).

The killer question for this surface is the subway test: **the user
queues 12 episodes on Wi-Fi at home, the app downloads two, the user
backgrounds the app, then the OS kills it; does the next launch pick up
where it left off, surface a sensible state, and avoid burning cellular
data?** Pre-audit, the answer was "no" for a reason that's not in
`DownloadService` itself — see section B.

## A. Queued semantics + concurrency

**State (pre-audit):**
- `DownloadService` already enforces `maximumConcurrentDownloads = 2` by
  gating `beginDownload(for:)` behind an `activeDownloadCount` check and
  pushing overflow into the `.queued` state. Backed by SwiftData (the
  Episode model persists `downloadStateRawValue`), so the queue survives
  app launches.
- `taskToEpisodeID` / `episodeIDToTask` dictionaries are correctly
  cleared in every URLSession delegate exit path (the v2.3.10 leak fix
  is intact across `didFinishDownloadingTo`, `didCompleteWithError`,
  cancel branch, and the "episode disappeared mid-download"
  defensive paths).
- `URLSessionConfiguration.background(withIdentifier:)` is used, so the
  OS hands downloads off when the app is suspended.

**Gaps + fixes applied:**
- **GAP (resolved): no Wi-Fi-only respect.** `AppSettings` had no
  cellular-vs-Wi-Fi flag, so a user opening Library on cellular and
  tapping "Download" would burn data with no recourse short of toggling
  iOS-level cellular access for the whole app. Added
  `AppSettings.downloadsWiFiOnly` (default `true`) and gated
  `startDownload(_:)` + `resumeQueuedDownloadsIfNeeded()` on
  `isAllowedOnCurrentNetwork`. When the toggle is on and the device is
  cellular, episodes persist as `.queued` and the queue drains as soon
  as `NetworkMonitor.shared.connectionType` flips to `.wifi`.
- **GAP (open, deferred):** no Settings UI surface yet to toggle
  `downloadsWiFiOnly`. The service-side enforcement landed so the
  toggle ships behind a known-working wiring.
- **GAP (open):** queue position is implicit (sorted by
  `downloadRequestedAt`). A future pass could expose a re-orderable
  queue surface in Library.

**Classification:** MUST-FIX resolved (Wi-Fi gate). GAP open (Settings
toggle, queue-reorder UI).

## B. On-launch reconciliation

**State (pre-audit):**
- `DownloadService.reconcilePersistedDownloads()` already existed and
  did the right work: episodes left in `.queued`/`.downloading` get
  promoted to `.downloaded` if the file is on disk, or flipped to
  `.failed` with a `"Download was interrupted. Retry to save this
  episode offline."` message otherwise.
- `configure(context:)` guarded the call behind a one-shot flag.
- **BUT — the configure call was dead code.** The only live caller was
  `SyncCoordinator.configure(_:)`, and `SyncCoordinator.shared` is
  never instantiated anywhere in the production app (only
  `FeedSyncService()` is instantiated directly in views). So
  `DownloadService` never received a model context, and every cold
  launch left interrupted downloads stuck in `.downloading` forever.

**Fixes applied:**
- **MUST-FIX (resolved):** wired
  `DownloadService.shared.configure(context: modelContext)` from
  `ContentView`'s startup `.task` block, alongside the other service
  configure calls. This was a one-line change but it unblocks the
  entire offline-trust posture.
- **MUST-FIX (resolved):** added `sweepOrphanDownloadFiles()` to the
  configure path. Walks the `Application Support/Downloads/` directory,
  parses the `<uuid>.<ext>` basename of every file, and deletes any
  file whose UUID doesn't resolve to a live Episode. Catches unsubscribe-
  while-downloading races and cascade-delete file-failure cases.

**Classification:** MUST-FIX resolved. The single most important fix in
this audit — without it, every other piece of offline machinery was
running blind.

## C. Active + failed state surfacing

**Read-only findings (no Library edits in scope):**
- `DownloadButton` (audited at `OffScript/DownloadButton.swift`) already
  surfaces every state explicitly:
  - `.notDownloaded` → "DOWNLOAD" with `arrow.down.circle`.
  - `.queued` → "QUEUED" with `clock.arrow.circlepath`, signal-yellow.
  - `.downloading` → percentage + `arrow.down.circle.fill`, signal-yellow.
  - `.failed` → "RETRY" with the retry-trianglehead icon, record-red.
  - `.downloaded` → "OFFLINE" with checkmark, mode-green.
  Accessibility labels + hints cover every state.
- `EpisodeFilter.downloaded` in `LibraryView` filters by
  `episode.downloadState == .downloaded`, which is the correct gate.
- The episode row itself only surfaces the `DownloadButton`, not a
  per-row badge or progress sliver. A user scrolling Library can see
  download state per row only by reading the button text — there's no
  ambient visual signal (e.g., a row-leading dot color, a "12 episodes
  saved offline" header chip).

**Classification:** DEFERRED — the data surface is sound; the missing
piece is ambient row-level UI, which belongs in a Library polish pass.

## D. Disk-file sync

**State (pre-audit):**
- `DownloadService.localURL(for:)` lazily corrects state — if an
  Episode has a `localFileURL` but the file is gone (Files.app delete,
  low-disk eviction), it clears `localFileURL`, flips
  `downloadState = .notDownloaded`, and saves. This is the right
  pattern for the "user deleted file out from under us" case.
- `reconcilePersistedDownloads()` calls `localURL(for:)` for every
  `.downloaded` row at launch, so the file-vs-state check runs
  proactively rather than waiting for the user to tap play.

**Fixes applied:**
- **GAP (resolved):** `sweepOrphanDownloadFiles()` (see B) handles the
  other half — files on disk with no Episode that claims them.

**Classification:** MUST-FIX resolved.

## E. Cancel + delete completeness

**State (pre-audit):**
- `cancelDownload(_:)` has two branches: the queued branch (no
  URLSession task exists yet) cleanly resets the episode; the active
  branch cancels the task, removes it from both tracker dicts, clears
  the progress-throttle bookkeeping, and resumes the next queued
  episode.
- `deleteDownload(_:)` defers to `cancelDownload(_:)` first, then
  deletes the local file via `removeFileIfPresent(at:)`, clears
  `localFileURL`, and resets state.
- Partial download fragments live inside the URLSession background
  session's own tmp store, not in `Application Support/Downloads/`, so
  cancel doesn't leave a `.partial` file in the user-visible Downloads
  directory. The URLSession delegate's `NSURLErrorCancelled` branch
  clears the tracker dicts.
- Spotlight is **not** explicitly de-indexed when a single download is
  deleted (only on unsubscribe). The v2.3.10 pattern indexes
  full-content episodes; downloaded episodes get extra indexing weight.
  Removing the download alone shouldn't change Spotlight presence
  (the episode metadata is still subscribed), so this is correct.

**Fixes applied:** None — the existing cleanup is correct.

**Classification:** No fix needed. The regression test
`cancelClearsTrackerEntriesAndPartialFile` pins the contract going
forward.

## F. PodcastUnsubscribeService transcript-cache cleanup

**State (pre-audit, flagged by Phase 14):**
- `PodcastUnsubscribeService.unsubscribe(_:in:)` cleaned up the
  podcast row (isSubscribed=false), queue items, downloaded audio
  files, and Spotlight entries, but **left `EpisodeTranscriptCache`
  rows untouched**. The cache is keyed by `episodeID` (a `@Attribute(.unique) UUID`),
  not a SwiftData relationship, so cascade-delete doesn't reach it.
- A user who unsubscribed from a show and re-subscribed days later
  would still see the stale on-device transcript as the "first hit"
  before `PublishedTranscriptLoader` got a chance to fetch the
  publisher-provided one.
- On a cloud-synced install, the stale transcripts also bloat iCloud
  storage indefinitely.

**Fixes applied:**
- **MUST-FIX (resolved):** the unsubscribe routine now fetches every
  `EpisodeTranscriptCache` whose `episodeID` is in the leaving podcast's
  episode-ID set and deletes each one. Logs the removed count via
  `os.Logger(category: "Unsubscribe")`. Test
  `unsubscribeRemovesTranscriptCacheForPodcastEpisodes` covers the
  contract, including the negative case (other podcasts' caches stay).

**Classification:** MUST-FIX resolved.

## Strategic verdict

**Subway test status — passing.** A user who queues 12 episodes on
Wi-Fi at home and gets killed by the OS will now, on next cold launch,
see two `.downloaded` rows, eight `.queued` rows (the queue drains
honoring the 2-concurrent cap), and any episode that was actually
mid-download as `.failed` with a retry CTA. If they're on cellular on
the train, no new downloads start until they hit Wi-Fi (because the
Wi-Fi-only default is on).

The biggest finding is the one that surprised me: **the entire offline
pipeline was running with a `nil` model context in production**
because the dead-code `SyncCoordinator.configure(_:)` call site was
never instantiated. Every piece of machinery — reconciliation, queue
drain, the `localURL(for:)` lazy self-heal — was correctly designed
but never invoked, since they all require a context. This is the kind
of bug that doesn't show up in a code review because each file
individually looks fine; you only catch it by tracing the wiring graph
end-to-end. Worth a future audit pass on "is every `configure(_:)` in
the service layer being called?"

Smaller surprises:
- Concurrency is already actor-bounded (well, `@MainActor`-bounded with
  an explicit count check). I expected to add a `DispatchSemaphore` and
  found the work was done.
- No Wi-Fi-only setting existed at all — not even disabled. Added the
  default-on flag and the gate, but the Settings UI to toggle it is
  open work.

## Deferred work

- **OffScriptApp.swift wiring:** the configure call landed in
  `ContentView.swift` because `OffScriptApp.swift` is read-only for
  this audit. `ContentView.swift` is the established home for service
  startup; this is the right shape but should be reviewed if
  `OffScriptApp.swift` ever takes over startup wiring.
- **Settings UI for `downloadsWiFiOnly`** — the flag is enforced;
  user-facing toggle pending.
- **Ambient Library row state** — `DownloadButton` covers the explicit
  control but rows don't carry an at-a-glance "this is downloaded /
  failed / queued" badge.
- **Queue reorder UI** — queue order is currently
  `downloadRequestedAt` ascending; no drag-handle surface.
- **Background URLSession resume-data preservation** — the existing
  `reconcilePersistedDownloads()` treats `.downloading` with no file as
  `.failed`. A future pass could persist URLSession resume data so the
  failure path can offer a true "resume from N%" rather than a fresh
  retry. Not in scope for Phase 1 — the contract is "we don't lose the
  user's intent," not "we don't lose the bytes."

## Files touched

- `OffScript/DownloadService.swift` — added `sweepOrphanDownloadFiles()`,
  Wi-Fi gate, `reconcileForTesting(context:)`, test-only count
  accessors. Existing reconciliation logic untouched.
- `OffScript/PodcastUnsubscribeService.swift` — transcript cache
  cleanup step.
- `OffScript/AppSettings.swift` — `downloadsWiFiOnly` flag.
- `OffScript/ContentView.swift` — added the missing
  `DownloadService.shared.configure(context:)` call to the startup
  `.task`.
- `OffScriptTests/OffScriptTests.swift` — `OfflineReliabilityTests`
  struct with 6 new `@Test`s.

## Test footprint

- Baseline: 152 passing.
- Post-audit: 158 passing (152 + 6 OfflineReliability).

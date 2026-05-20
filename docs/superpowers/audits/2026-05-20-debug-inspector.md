# Debug Inspector — Phase 27

## Why this exists

Phase 23's dead-code sweep found `TelemetryEvent` had 16 emit sites and 0
consumers. Phase 25 deferred the delete-vs-consume decision. This phase
consumes them: a debug-only inspector that surfaces dormant telemetry
alongside per-podcast sync history, download queues, and runtime metadata so
engineers can introspect the live store without attaching a debugger.

Pairs with resolving Phase 15's deferred user-facing toggle for
`AppSettings.downloadsWiFiOnly` — the flag was already enforced by
`DownloadService.isAllowedOnCurrentNetwork` but was invisible in Settings.

## Sections

### A. Telemetry events

- Pulls the last 100 `TelemetryEvent` rows via
  `FetchDescriptor<TelemetryEvent>(sortBy: [SortDescriptor(\.createdAt,
  order: .reverse)])` with `descriptor.fetchLimit = 100`.
- Renders timestamp + name + a 1-line metadata summary in `tunerFont(size:
  10)` mono so engineers can scan keys at a glance.
- Tap → full-payload `TelemetryDetailSheet` with each metadata pair shown
  as a Tuner label + monospaced selectable text.
- Top-of-list `× CLEAR ALL` key drops into a Tuner confirm strip
  (CANCEL / × CONFIRM) before calling `modelContext.delete(model:
  TelemetryEvent.self)` + `saveOrLog`. Same vocabulary as Queue × CLEAR
  ALL (#200), Settings × RESET (#229), and Settings × SIGN OUT.

### B. Sync history

- `SyncHistoryService.recentlyAttempted` runs `FetchDescriptor<Podcast>`
  filtering `isSubscribed && lastSyncAttemptAt != nil`, sorting by
  `lastSyncAttemptAt` desc, capped at 50. Falls back to subscribed-but-
  never-attempted when the attempted set is empty so empty installs still
  render something.
- Row shows: podcast title, status label (● SUCCESS / × FAILED / ◐ PENDING /
  ● IDLE / ○ NEVER), last-attempt timestamp, `syncFailureCount` when > 0,
  and `syncErrorMessage` inline when present.
- Status normalization in `SyncHistoryService.statusLabel(for:)` covers
  the vocabulary `FeedSyncService` writes today and surfaces any unknown
  raw values verbatim so new states aren't silently swallowed.

### C. Download state

- Four sections — `.downloading`, `.queued`, `.failed`, `.downloaded` —
  fetched via predicates on `Episode.downloadStateRawValue == "<state>"`.
  The `.downloaded` list is capped at 20 and sorted by
  `downloadCompletedAt` desc.
- `.downloading` rows show live `downloadProgress` as a percentage.
- `.failed` rows are tappable Tuner keys that re-invoke
  `DownloadService.shared.startDownload(for: episode)` and re-fetch on
  success. Each row exposes the `downloadErrorMessage`.
- `.downloaded` rows surface `downloadCompletedAt` in the Tuner monospaced
  timestamp format.

### D. Runtime metadata

- VERSION — `CFBundleShortVersionString (CFBundleVersion)` from Info.plist.
- STORE — derived from `AppSettings.cloudSyncRuntimeState`:
  CLOUD-BACKED / LOCAL ONLY / IN-MEMORY FALLBACK.
- ICLOUD ENABLED — `AppSettings.cloudSyncEnabled`.
- DOWNLOAD CACHE — `DownloadService.shared.totalDownloadSizeBytes`
  formatted via `ByteCountFormatter`.
- TRANSCRIPT CACHE — `fetchCount<EpisodeTranscriptCache>`.
- NEXT BG REFRESH — async query into `BGTaskScheduler.shared
  .getPendingTaskRequests` for the
  `com.offscript.feed-refresh` identifier, surfaced as the earliest begin
  date or "UNSCHEDULED" when no request is queued. (Chosen over
  UserDefaults bookkeeping because `BackgroundFeedRefresh.swift` is
  read-only in this phase and `BGTaskScheduler` already has the truth.)
- WI-FI ONLY — `AppSettings.downloadsWiFiOnly`.

## How to access

Settings → DIAGNOSTICS → OPEN DEBUG INSPECTOR

Presented as a child sheet from Settings (which is itself a sheet) so the
inspector inherits `.tunerModalSurface()` and we don't need to wrap
SettingsView in a NavigationStack (which would re-introduce Liquid Glass
chrome). Same pattern as the Library import sheet stacking pattern.

## Wi-Fi-only toggle (Phase 15 resolution)

- Added a dedicated `wifiOnlyToggle` view inside
  `SettingsView.playbackSection`, slotted between "Prefer short listens"
  and "Default playback rate". Bound to a new
  `@AppStorage("offscript.downloadsWiFiOnly")` declaration that mirrors
  `AppSettings.downloadsWiFiOnly`'s default of `true`.
- Label: `DOWNLOADS · WI-FI ONLY` (TunerLabel size 9, signal-yellow when
  ON, soft-paper when OFF). Description below: "Downloads pause when on
  cellular. Saves data on metered plans."
- Accessibility: announces "Download only on Wi-Fi. Currently <on|off>."
  with `.isSelected` trait when ON. Identifier
  `SettingsDownloadsWifiOnlyToggle` for the test suite.
- Did NOT collapse into the generic `tunerToggle` helper because the
  Tuner eyebrow label style differs and the spec called for it
  explicitly.

## Tests to land in follow-up

**Status (2026-05-20, Phase 31 sweep):** All 8 telemetry / download /
SyncHistoryService tests landed in `DebugInspectorTests` plus one
known-state mapping pin (commit `732e10a`,
`test(inspector): cover Phase 27 Debug Inspector + SyncHistoryService`).
The `settingsToggleBindsToWifiOnlyFlag()` test (item 9) is **STILL
DEFERRED** — `SettingsView` rendering needs a host harness
(`ViewInspector` or `XCUITest`) for a clean toggle round-trip; the
plain `@AppStorage` UserDefaults binding is in any case driven by
the UI layer, not testable from a pure unit test.

Phase 31 owns `OffScriptTests.swift`. Tests to add:

- `func debugInspectorListsAllTelemetryEvents()` — seed 5
  `TelemetryEvent` rows with varied timestamps, render
  `DebugInspectorView`, assert `telemetryEvents.count == 5` and the order
  is descending by `createdAt`.
- `func debugInspectorRespectsTelemetryFetchLimit()` — seed 150 events,
  assert only 100 are loaded.
- `func debugInspectorTelemetryClearAllWipesStore()` — seed 5 events,
  call the clear path, assert `fetchCount<TelemetryEvent>` returns 0.
- `func debugInspectorDownloadStateSectionGroupsCorrectly()` — seed one
  episode in each of `.downloading`, `.queued`, `.failed`, `.downloaded`,
  verify each section's array has the expected count and the right
  episode.
- `func debugInspectorDownloadedSectionSortsByCompletedAtDesc()` — seed
  3 downloaded episodes with staggered `downloadCompletedAt`, assert
  newest first.
- `func debugInspectorFailedRowRetryRequeues()` — seed a `.failed`
  episode, tap the retry path, assert `downloadState` flips to `.queued`
  via the existing `DownloadService.startDownload` flow.
- `func syncHistoryServiceFallsBackToSubscribedWhenNoneAttempted()` —
  seed 3 subscribed podcasts with `lastSyncAttemptAt == nil`, assert
  `SyncHistoryService.recentlyAttempted` returns all 3 sorted by title.
- `func syncHistoryServiceStatusLabelHandlesUnknownState()` — set
  `podcast.syncStatus = "throttled"`, assert label is `● THROTTLED`.
- `func settingsToggleBindsToWifiOnlyFlag()` — render `SettingsView`,
  flip the toggle by accessibility identifier
  `SettingsDownloadsWifiOnlyToggle`, assert
  `UserDefaults.standard.bool(forKey: "offscript.downloadsWiFiOnly")`
  matches the new state. Reverse it again, assert same.

## Files

- NEW: `OffScript/DebugInspectorView.swift`
- NEW: `OffScript/SyncHistoryService.swift`
- MODIFIED: `OffScript/SettingsView.swift` (added wifiOnlyToggle,
  diagnosticsSection, sheet binding, `@AppStorage` for
  `downloadsWiFiOnly`)

## Evolution in v3

The inspector is intentionally a flat read-only diagnostics surface in
v2 because the highest-value job was simply turning a 16-emitter,
0-consumer log into something an engineer can read. v3 should add
filtering (event-name regex, date range), event-count rollups
(`download_cancelled` × N over last hour), and a JSON export key so
session traces can be pasted into bug reports. A second pass could
turn each sync-history row into a navigation portal to PodcastDetail
once SettingsView gets wrapped in a NavigationStack, and the Download
section should surface the `BackgroundTranscriptionService` queue
alongside downloads since they share the same idle-on-cellular failure
modes. The TelemetryDetailSheet's metadata pairs already use
`textSelection(.enabled)` — v3 should add a single "Copy event as JSON"
key to make sharing one event into a teammate's chat a one-tap action.

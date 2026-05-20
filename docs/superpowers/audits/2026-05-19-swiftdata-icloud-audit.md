# SwiftData + iCloud sync audit — 2026-05-19

Branch: `audit/expanded-surface-2026-05-19`
Base SHA: `e44b0cd`
Scope: `OffScript/OffScriptApp.swift`, `OffScript/Models.swift`, `OffScript/SchemaMigration.swift`, `OffScript/SyncCoordinator.swift`, `OffScript/AppleIdentityService.swift`.

---

## ModelContainer three-tier recovery

`OffScriptApp.sharedModelContainer` follows the three-tier recovery shape CLAUDE.md prescribes:

### Tier 1 — `makeModelContainer(schema:)`
- Builds a `ModelConfiguration` against `persistentStoreURL` = `…/Application Support/OffScript/OffScript.store`.
- If `cloudSyncEnabled && currentUserID != nil`, attempts CloudKit-backed first (`cloudKitDatabase: .automatic`); on failure logs warning, sets runtime state to `.fallbackFailed`, falls through to local-only.
- Pass-through logs: `"CloudKit sync enabled — creating ModelContainer with iCloud backing"`, `"Using local-only ModelContainer"`.
- Subsystem: `com.offscript`, category `SwiftData`. Privacy markers `(privacy: .public)` on error descriptions.

### Tier 2 — `quarantineStoreDirectory()`
- Moves the entire `OffScript/` Application Support subdirectory to `OffScript-corrupted-<unix-timestamp>/` rather than deleting. Recoverable via Files.app.
- Recreates an empty `OffScript/` so the retry has a writable target.
- Logs `"Moved corrupted store dir to <path>"` and `"Quarantined corrupted store directory — retrying with fresh schema"`.
- Rebuilds `Schema` instance for the retry to avoid carrying over SwiftData's internal state from the failed first attempt — non-obvious and load-bearing.

### Tier 3 — in-memory
- Uses `ModelConfiguration(isStoredInMemoryOnly: true)`. Correct API per CLAUDE.md guidance.
- **Previously**: error swallowed by `try?`; success was unlogged; runtime state stayed at whatever the prior tier wrote. Fixed in this audit — see "Fixes applied."
- **Now**: explicit `do/try/catch`, in-memory success logs at `.fault` level (so Console.app surfaces "data won't persist"), and `cloudSyncRuntimeState = .fallbackFailed` set on this path. If the in-memory init itself fails, the fatalError now includes both the quarantine error AND the in-memory error.

### Recoverability of quarantined data
- Rename-not-delete is correct. User can navigate to Files → On My iPhone → OffScript → `OffScript-corrupted-<ts>/` and grab the `.store` + `.store-shm` + `.store-wal` if they have other tooling to read SwiftData stores.
- No automatic re-import; that's a strategic gap not a must-fix.

### CloudKit schema partitioning
- Single private DB via `cloudKitDatabase: .automatic` (which resolves to the user's private DB when an iCloud account is signed in to the app's container).
- No public schema present. OffScript is a single-user listening app — no shared/public records make sense for this product. Not a gap.

---

## VersionedSchema + migration plan

`OffScript/SchemaMigration.swift`:

- **`SchemaV1`** (1.0.0): baseline — 8 model types (`Podcast`, `Episode`, `QueueItem`, `PlaybackEvent`, `PreferenceSignal`, `EpisodeProfile`, `UserTasteProfile`, `TelemetryEvent`).
- **`SchemaV2`** (2.0.0): adds `EpisodeTranscriptCache` — single additive table.
- **`OffScriptMigrationPlan`** declares both versions in `schemas` and one stage in `stages`.

### Stages
- `migrateV1toV2 = MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)`.
- **Lightweight is correct** for this transition — V2 is purely additive (new table, no field rename/type change/relationship reshape). No `willMigrate`/`didMigrate` needed; SwiftData creates the new table on first open of a V1 store.
- **Gotcha to watch for**: `EpisodeTranscriptCache.episodeID` has `@Attribute(.unique)`. On a CloudKit-backed store, unique constraints behave differently (CloudKit prefers no uniqueness enforcement at the schema level). If CloudKit-backed migration is ever exercised, watch the SwiftData logs for unique-constraint warnings — not actionable today but worth pinning for next cycle.

---

## Predicate + relationship hygiene

### `persistentModelID` in `#Predicate`
- **CLEAN**: `grep -rn 'persistentModelID' OffScript/` returns zero hits. Every predicate filters on stored UUID (`$0.id`, `$0.episodeID`, `$0.podcast.id`, etc.) or stored scalar properties.

### `@Relationship` `deleteRule` coverage
Every `@Relationship` annotation in `Models.swift` has an explicit `deleteRule:`:

| Model.Property | deleteRule | Inverse |
|---|---|---|
| `Podcast.episodes` | `.cascade` | `\Episode.podcast` |
| `Episode.queueItems` | `.cascade` | `\QueueItem.episode` |
| `Episode.playbackEvents` | `.nullify` | `\PlaybackEvent.episode` |
| `Episode.preferenceSignals` | `.nullify` | `\PreferenceSignal.episode` |
| `Episode.profile` | `.cascade` | `\EpisodeProfile.episode` |
| `QueueItem.episode` | `.noAction` | — |
| `PlaybackEvent.episode` | `.noAction` | — |
| `EpisodeProfile.episode` | `.noAction` | — |

- One inconsistency worth flagging (informational, not a fix): `Episode.podcast` is declared as a plain `var podcast: Podcast` without a `@Relationship` annotation — SwiftData infers the inverse from `Podcast.episodes`. This works but is inconsistent with the explicit-annotation pattern used everywhere else. Adding `@Relationship(deleteRule: .noAction)` on `Episode.podcast` would make intent explicit. Deferred — touching `Episode` requires a schema-migration audit (does it bump the model fingerprint?), out of scope for this surgical pass.
- `PreferenceSignal.episode` is declared as a non-optional `var episode: Episode` with no `@Relationship` annotation, relying on inverse inference from `Episode.preferenceSignals` (`.nullify`). Same comment as above.

---

## iCloud sync resilience

### Account-availability check timing
- **At launch**: `OffScriptApp.makeModelContainer` only checks `AppSettings.cloudSyncEnabled && AppSettings.currentUserID != nil`. It does **not** call `CloudKitAccountService.currentStatus()` before attempting CloudKit-backed init. If iCloud is `restricted` / `noAccount` / `temporarilyUnavailable`, the CloudKit init throws, gets caught, and falls through to local — correct, but wasteful and lands the user in `.fallbackFailed` runtime state for a transient iCloud issue. **GAP**.
- **At sync time**: `SyncCoordinator` and `BackgroundFeedRefresh` deal with feed-RSS sync, not CloudKit. CloudKit replication is handled by SwiftData's internal engine (`.automatic`) — there's no manual sync coordinator to gate on account status. SwiftData internally retries when CloudKit becomes available; no per-write account check is needed.
- **At UI time**: `SettingsView` (read-only here) and `OnboardingFlowView` (read-only here) DO call `CloudKitAccountService.currentStatus()` before flipping `cloudSyncEnabled`. The CHANGELOG entry "Settings no longer claims iCloud sync is active unless the launch actually opened a CloudKit-backed SwiftData container" is satisfied via `AppSettings.cloudSyncRuntimeState` being set by `makeModelContainer` based on actual success/failure of the CloudKit-backed init.

### Mid-session iCloud sign-out
- No `CKAccountChangedNotification` observer in the codebase.
- If the user signs out of iCloud during a session, SwiftData's CloudKit mirroring will simply stop syncing — local writes still succeed, but they won't replicate.
- `AppleIdentityService.validateStoredCredential()` only runs when explicitly called (Settings refresh). If a launch happens with a revoked Apple credential, the launch's `cloudKitEnabled` gate still passes (because `currentUserID` is still cached), then the CloudKit init may fail at the entitlement layer — the fall-through to local catches it.
- **STRATEGIC**: an `NSNotificationCenter` observer on `CKAccountChanged` that re-runs `AppleIdentityService.validateStoredCredential()` and `CloudKitAccountService.currentStatus()` would tighten the mid-session story. Cross-cutting (touches AppDelegate / a new service), deferred.

### Pending-write loss when iCloud unavailable
- SwiftData on `.automatic` CloudKit persists writes locally first and queues them for CloudKit replication. If iCloud goes unavailable before the queue drains, the local writes survive; CloudKit's CKMirroringEngine retries from its own persistent queue on next opportunity.
- **No data loss risk** in the common case. The only data-loss scenario is: user is in the in-memory fallback (Tier 3) — but in that case they're already in a "data doesn't persist" mode, which is now explicitly logged at `.fault`.

---

## Apple identity

`AppleIdentityService` (file owned, audited):

- `validateStoredCredential()` is correct: queries `ASAuthorizationAppleIDProvider.getCredentialState` against the stored `userID`. Returns `.signedOut` when `currentUserID` is nil.
- **Revoked-credential cleanup**: on `.revoked` or `.notFound`, the service calls `AppSettings.clearCredential()` AND `AppSettings.cloudSyncEnabled = false`. Both wipes happen — credential is removed from Keychain via `UserProfileService.deleteCredential()`, and the sync flag is flipped off so the next launch will land on local-only.
- **Transferred-credential handling**: `.transferred` maps to `isAuthorized = true` (correct per Apple's docs — transferred means the team transferred ownership but the credential is still valid).
- **iCloud check is separate from Apple identity**: `CloudKitAccountService.currentStatus()` lives in the same file but is a distinct namespace and is called independently by Settings/Onboarding. Apple sign-in and iCloud account availability are tracked as separate states — matches the CHANGELOG mention.
- **Call-site timing**: `validateStoredCredential()` is not called at app launch in `OffScriptApp.init()` — only when Settings appears or when the cloud-sync toggle changes. This means a user with a revoked credential can launch the app and have it continue thinking they're signed in until they visit Settings. **GAP**.
  - This is a CHANGELOG-mentioned area ("Settings and Sign in with Apple now log identity, iCloud, signal-profile, and Keychain OSStatus breadcrumbs") — the logging is there, but the per-launch validation isn't. Deferred — wiring this requires touching `OffScriptApp.init()` or `ContentView.onAppear`, and would meaningfully change launch behaviour. Should be its own task with its own audit.

---

## Race conditions

### Background ModelContext creation
- `BackgroundFeedRefresh.performRefresh(container:)` creates a `ModelContext(container)` directly. It's marked `@Sendable` and called from `.backgroundTask(...)` which runs off the main actor. **Risk**: `ModelContext` is not `Sendable`, and SwiftData expects each context to be used from a single actor/queue. The current code uses the context only inside one Task, so it's safe — but it's not bound to an actor, so any future refactor that adds concurrency inside `performRefresh` could race.
  - This file is read-only for this audit. Deferred. Recommend a `@ModelActor` wrapping (pattern used in `LibraryDirectoryCountStore`) to make the actor binding explicit.
- `OffScriptAppIntents.makeContext()` is `@MainActor`-isolated — safe, intent bodies are `@MainActor` too.
- `SyncCoordinator` is `@MainActor`-annotated; all its `ModelContext` use is main-actor isolated. Safe.

### Concurrent writes to the same row
- `SyncCoordinator.refreshSubscriptions` uses `withTaskGroup` with `maxConcurrency = 4`, but each task is `@MainActor`, so writes serialize on the main actor — no concurrent SwiftData mutation.
- `BackgroundFeedRefresh` iterates podcasts serially with `for podcast in podcasts`. No concurrent write risk.
- **Risk**: If a `BackgroundFeedRefresh` runs while the main app is also syncing the same podcasts via `SyncCoordinator`, both have their own `ModelContext` against the same store. SwiftData handles cross-context coalescing via its persistent-history mechanism, but two contexts writing `podcast.syncStatus = "syncing"` at the same time is technically a race on the underlying row's last-writer-wins. Low impact (the field is a string status, eventual-consistency-safe) but worth pinning. **STRATEGIC**.

---

## Fixes applied

- `65b1db1` — `fix(model): log in-memory fallback success and surface its init error`
  - Replaces `try? ModelContainer(...)` with explicit `do/try/catch` so the in-memory init error isn't silently swallowed.
  - Adds `.fault`-level log on successful in-memory takeover so Console.app surfaces "user is in a non-persistent state."
  - Sets `cloudSyncRuntimeState = .fallbackFailed` on the in-memory path so Settings can honestly reflect the runtime state.
  - `fatalError` now reports both the quarantine error and the in-memory error.

---

## Deferred (cross-cutting / out of scope)

- **Add `CloudKitAccountService.currentStatus()` short-circuit at launch** before attempting CloudKit-backed `ModelConfiguration`. Skip the throw-and-catch path when iCloud is known-unavailable. Requires `makeModelContainer` to become async — affects the `sharedModelContainer` stored-property pattern and the App-scene init order. Strategic refactor.
- **Add `@Relationship(deleteRule: .noAction)` annotation to `Episode.podcast` and `PreferenceSignal.episode`** for explicit-intent parity. Schema-fingerprint impact unknown — should run with a SchemaV3 migration check.
- **Per-launch `AppleIdentityService.validateStoredCredential()` call** in `OffScriptApp.init` (or `ContentView.task`) so revoked credentials are caught before Settings is opened. Touches view layer.
- **`CKAccountChanged` observer** to react to mid-session iCloud sign-out. Cross-cutting, needs a new service.
- **`@ModelActor` wrapping for `BackgroundFeedRefresh`** to make the background-actor binding explicit and prevent future concurrency races.
- **Concurrent write to `podcast.syncStatus`** between foreground `SyncCoordinator` and background `BackgroundFeedRefresh` — low-impact eventual-consistency race. Add a serialization gate or move sync state into a single-writer actor.
- **`EpisodeTranscriptCache.episodeID` `@Attribute(.unique)` behaviour under CloudKit**: needs verification when CloudKit-backed migration is exercised end-to-end.
- **Automatic recovery of quarantined `OffScript-corrupted-<ts>/` stores**: today the user has to dig through Files.app. A one-shot "import last quarantined store" affordance in Settings would close the loop.

---

## Classification

### MUST-FIX
- (none surfaced within owned files — three-tier recovery is sound, schema migration is well-formed, relationship annotations are explicit, predicates use stored UUIDs.)

### GAP
- No `CloudKitAccountService.currentStatus()` check before the launch-time CloudKit `ModelContainer` attempt. Currently lands in `.fallbackFailed` for transient iCloud-unavailable cases instead of `.localOnly`.
- No per-launch `validateStoredCredential()` call — revoked Apple credentials aren't caught until the user visits Settings.
- No `CKAccountChanged` observer — mid-session sign-out is invisible to the app's identity layer.
- `BackgroundFeedRefresh` `ModelContext` is not actor-bound; safe today but fragile to future refactors.

### STRATEGIC
- Per-launch identity + iCloud probe with a unified result published to Settings/Sentry, so the first session frame already knows the truth instead of waiting for the user to open Settings.
- Add a "recover quarantined store" affordance in Settings (lists `OffScript-corrupted-*` directories and offers re-open or delete).
- Move shared `syncStatus` writes through a single-writer actor to eliminate the cross-context race entirely.
- Verify and document `@Attribute(.unique)` behaviour on `EpisodeTranscriptCache.episodeID` when CloudKit-backed.
- Bring `Episode.podcast` and `PreferenceSignal.episode` under explicit `@Relationship` annotations for codebase-wide intent parity, alongside a SchemaV3 stage if the fingerprint changes.

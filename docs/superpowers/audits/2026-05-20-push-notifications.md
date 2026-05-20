# Push notifications scaffolding — 2026-05-20

## Scope

Local notifications only. OffScript has no server, so this work uses
`UNUserNotificationCenter` scheduling — no APNs, no remote push, no
device tokens, no provisioning changes.

The only producer planned is `BackgroundFeedRefresh`, which already
detects new episodes for subscribed podcasts during its periodic sync
(Phase 24 + Phase 23 follow-up). Today that detection is silent;
this scaffolding lets it surface to the user.

## What landed this round

- `OffScript/NotificationService.swift` — new file, owns:
  - `NotificationService.shared` (@MainActor singleton)
    - `requestAuthorization() async -> Bool`
    - `scheduleNewEpisodeNotification(for:)` — subscription-gated, opt-in-gated
    - `cancelNewEpisodeNotification(for:)`
  - `NotificationDelegate.shared` — `UNUserNotificationCenterDelegate`
    - Foreground presentation (`willPresent` → banner+sound)
    - Tap routing via `UIApplication.shared.open(url)` to loop back
      through `ContentView.onOpenURL → DeepLinkRouter.handle(_:in:)`

Build verified on iOS Simulator (Debug). No call sites yet — service
is self-contained.

## Brand integrity

CLAUDE.md: "No paid placements, no algorithm pushing. The recommendation
engine works only on signals the user generated themselves."

`scheduleNewEpisodeNotification` enforces this with two guards, in order:

1. **Subscription check** — `episode.podcast.isSubscribed` must be true.
   Defends against caller bugs that might pass us an unsubscribed
   podcast's episode (e.g. opportunistic "you might like this" pushes).
2. **Opt-in check** — reads
   `UserDefaults.standard.bool(forKey: "offscript.notificationsForNewEpisodes")`,
   default `false`. The user must deliberately turn this on in Settings;
   notifications never fire by default.

There is no path in this service for unsubscribed or "recommended"
notifications. Adding one would require a code change visible in
review.

## Deep-link routing — design note

`DeepLinkRouter.handle(_:in:)` (read-only) requires a `ModelContext`
parameter and is `@MainActor`. There is no `.shared` singleton with a
zero-arg `handle(url:)` method. From a `UNUserNotificationCenterDelegate`
callback we have no `ModelContext` in scope.

Approaches considered:

- **Direct call** — would require either (a) plumbing a `ModelContainer`
  into `NotificationDelegate`, or (b) a new `DeepLinkRouter.handle(_:)`
  overload that grabs the container off `OffScriptApp`. Both edit files
  outside this round's ownership.
- **Loopback via `UIApplication.shared.open`** — chosen. The delegate
  re-opens the same `offscript://` URL via `UIApplication.shared.open`,
  which routes through `ContentView`'s existing `.onOpenURL` modifier,
  which already has `ModelContext` from the SwiftUI environment and
  already calls `DeepLinkRouter.handle(_:in:)`.

The loopback approach has one tradeoff: a brief flicker if the OS shows
the system "open in OffScript?" affordance. In practice iOS treats
intra-app `offscript://` opens as silent for the registered scheme
owner, so this is invisible.

## Wiring follow-ups (file-ownership-bound, deferred)

Each of these touches a file owned by another agent or out of scope
for this round. They MUST be done to fully land notifications end-to-end.

### Wiring point 1 — `OffScript/BackgroundFeedRefresh.swift`

`performRefresh` does not currently return which episodes were newly
added by `FeedSyncService.sync`. Two sub-steps:

1. Extend `FeedSyncService.sync(podcast:in:)` (or its return type) to
   surface the set of newly-inserted `Episode` objects for the sync
   pass. (Today it appears to mutate the model context silently.)
2. In `BackgroundFeedRefresh.performRefresh`, after the successful
   `try await service.sync(...)` call, iterate the new episodes and
   call:
   ```swift
   for episode in newEpisodes {
       NotificationService.shared.scheduleNewEpisodeNotification(for: episode)
   }
   ```

Notes for the wiring agent:
- `NotificationService.shared` is `@MainActor`. `performRefresh` is
  not `@MainActor` (`@Sendable static func`). The call site must
  `await MainActor.run { ... }` or be marked `@MainActor`.
- Consider deduping: if the user is already running and has the new
  episode visible in feed, scheduling is still fine — the body says
  "New: <podcast title>" and `cancelNewEpisodeNotification` can be
  fired when they start playback.

### Wiring point 2 — `OffScript/OffScriptApp.swift`

Install the delegate at launch so taps route correctly:

```swift
.task {
    UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
}
```

Place this alongside the other launch-time `.task` modifiers on the
root view. It must run before any notification can fire, which is
trivially true for local notifications scheduled in-session, but
matters for notifications that were scheduled in a previous session
and fire while the app is foregrounded.

### Wiring point 3 — `OffScript/SettingsView.swift`

Add a toggle row bound to the new `AppSettings.notificationsForNewEpisodes`
property. Suggested copy:

- Title: "Notify me about new episodes"
- Subtitle: "Only from podcasts you've subscribed to."

When the toggle flips from off → on, the view should `await`
`NotificationService.shared.requestAuthorization()`. If denied, the
toggle should revert and deep-link the user to Settings.app's
notification panel (`UIApplication.openSettingsURLString`).

### Wiring point 4 — `OffScript/AppSettings.swift`

`AppSettings` is an `enum` with hand-rolled `UserDefaults`-backed static
properties (NOT `@AppStorage`, despite the brief's example). Match the
existing pattern. Add to the `Key` namespace:

```swift
static let notificationsForNewEpisodes = "offscript.notificationsForNewEpisodes"
```

And the accessor (default `false` — opt-in):

```swift
static var notificationsForNewEpisodes: Bool {
    get { defaults.bool(forKey: Key.notificationsForNewEpisodes) }
    set { defaults.set(newValue, forKey: Key.notificationsForNewEpisodes) }
}
```

Once landed, swap `NotificationService.notificationsForNewEpisodesEnabled`
to read from this accessor instead of the raw key. The raw key string
must match exactly (`"offscript.notificationsForNewEpisodes"`).

### Wiring point 5 — Info.plist & entitlements

Neither needs changes for local notifications:

- **Entitlements** — `UNUserNotificationCenter` requires no entitlement.
  Remote push (APNs) would, but that is out of scope.
- **Info.plist** — no `NSUserNotificationsUsageDescription` key
  required; iOS surfaces the system prompt automatically when
  `requestAuthorization` is invoked.

### Wiring point 6 — Cancel-on-play

To avoid alerting users about episodes they've already opened, call:

```swift
NotificationService.shared.cancelNewEpisodeNotification(for: episode)
```

from `PlaybackController.play(_:in:)` (or wherever transport starts).
This is a one-line addition once `PlaybackController` is in scope.

### Wiring point 7 — Cancel-on-unsubscribe

When the user unsubscribes from a podcast, cancel any pending
notifications for that podcast's episodes. Likely call site:
`PodcastUnsubscribeService`. There is no bulk-cancel-by-podcast API in
`UNUserNotificationCenter`, so the wiring agent will need to either:

- Track pending identifiers per podcast (a `Set<String>` in
  `NotificationService` keyed by `Podcast.id.uuidString`), or
- Call `getPendingNotificationRequests` and filter by parsing the
  identifier string for the episode UUID, then look up
  `episode.podcast.id`.

The second approach is simpler but slower (linear scan). With a
typical pending set of <50 entries it doesn't matter.

## v3 follow-ups (defer to a later phase)

- **Grouping** — set `UNMutableNotificationContent.threadIdentifier`
  to `podcast.id.uuidString` so iOS groups multi-episode releases
  from the same show.
- **Rich notifications** — attach episode artwork via
  `UNNotificationAttachment`. Requires writing the artwork to a
  temp file with a stable URL (notification center copies it).
- **Per-podcast preferences** — toggle per-show, not just global on/off.
  Probably lives on `Podcast` itself (`var notificationsEnabled: Bool`)
  with a switch in `PodcastDetailView`.
- **Quiet hours** — respect a user-configured window (e.g. 10pm–7am).
  Could either delay scheduling until window end, or rely on
  iOS Focus modes (cheaper, no extra UI).
- **Notification actions** — "Play now" / "Add to queue" / "Mark
  played" from the notification itself via `UNNotificationCategory`
  + `UNNotificationAction`.

## Verification

- `xcodebuild ... -configuration Debug build` → BUILD SUCCEEDED.
- `git status` clean after commits.
- File-ownership respected: only `NotificationService.swift` and this
  audit doc were created. No edits to read-only files.

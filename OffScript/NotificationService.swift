import Foundation
import OSLog
import SwiftData
#if canImport(UIKit)
import UIKit
#endif
@preconcurrency import UserNotifications

/// Local notification scheduling for OffScript.
///
/// Scope: **local notifications only.** OffScript has no server, so this
/// is `UNUserNotificationCenter` scheduling, not APNs/remote push. The
/// only producer today is `BackgroundFeedRefresh`, which detects new
/// episodes for subscribed podcasts on its periodic sync.
///
/// Brand promise (CLAUDE.md): "No paid placements, no algorithm pushing.
/// The recommendation engine works only on signals the user generated
/// themselves." Notifications respect this:
///   - Only fire for podcasts where `isSubscribed == true`.
///   - Only fire when the user has opted in via Settings.
///   - Never fire for "discovery" recommendations the user didn't ask for.
///
/// Identifier scheme: `"new-episode-<episode-uuid>"` — one notification
/// per episode, so re-scheduling is idempotent and tap-to-cancel is
/// trivial.
@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private let logger = Logger(subsystem: "com.offscript", category: "Notifications")

    /// UserDefaults key for the new-episode notification opt-in toggle.
    /// Mirrors the namespacing used by `AppSettings`. When `AppSettings`
    /// adds a typed `notificationsForNewEpisodes` accessor (see audit doc
    /// `2026-05-20-push-notifications.md`), this lookup should be replaced
    /// with that accessor.
    private static let notificationsForNewEpisodesKey = "offscript.notificationsForNewEpisodes"

    private init() {}

    // MARK: - Authorization

    /// Request user permission for local notifications.
    ///
    /// Idempotent — `UNUserNotificationCenter` short-circuits if
    /// already-granted or already-denied. Call this from a deliberate
    /// UX moment (e.g. flipping the Settings toggle on), **not** from
    /// app launch — Apple's HIG frowns on cold-start permission prompts
    /// and a denial here is sticky.
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            logger.info("Notification authorization granted: \(granted, privacy: .public)")
            return granted
        } catch {
            logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Scheduling

    /// Fire a "new episode" notification for the user's subscribed show.
    ///
    /// Guard order matters:
    ///   1. **Subscription check** — the brand promise. Even if the
    ///      caller is buggy and passes us an unsubscribed podcast's
    ///      episode, we drop it on the floor.
    ///   2. **Opt-in check** — read from UserDefaults under
    ///      `offscript.notificationsForNewEpisodes`. Default false
    ///      (opt-in). Silent skip when off.
    ///
    /// The notification's `userInfo` carries an `offscript://` deep-link
    /// URL so `NotificationDelegate` can route taps through the existing
    /// `DeepLinkRouter` plumbing.
    func scheduleNewEpisodeNotification(for episode: Episode) {
        guard episode.podcast.isSubscribed else {
            logger.notice(
                "Skipped notification for non-subscribed podcast \(episode.podcast.title, privacy: .public)"
            )
            return
        }
        guard Self.notificationsForNewEpisodesEnabled else {
            // User toggled off in Settings — silent skip (no log spam).
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "New: \(episode.podcast.title)"
        content.body = episode.title
        content.sound = .default
        // Body is the episode title — most informative. Duration could
        // go here too, but notifications truncate aggressively on the
        // lock screen, so we keep it short.

        // Deep-link via the existing offscript:// URL scheme. The
        // delegate translates this back to a URL and re-opens it via
        // `UIApplication.shared.open`, which routes through ContentView's
        // `.onOpenURL` → `DeepLinkRouter.handle(_:in:)`. This avoids
        // needing a `DeepLinkRouter.shared` singleton (the existing
        // router takes a `ModelContext` parameter and is invoked from
        // SwiftUI view modifiers, not raw delegate callbacks).
        content.userInfo = [
            "offscript-deeplink": "offscript://episode/\(episode.id.uuidString)"
        ]

        // Trigger with a 1s delay: `UNTimeIntervalNotificationTrigger`
        // rejects intervals < 0 and `nil` trigger fires immediately but
        // also delivers synchronously during scheduling which is weirder
        // to reason about. 1s is the conventional "fire now" value.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.identifier(for: episode),
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { [logger] error in
            if let error {
                logger.error(
                    "Failed to schedule notification: \(error.localizedDescription, privacy: .public)"
                )
            } else {
                logger.debug(
                    "Scheduled new-episode notification for \(episode.title, privacy: .public)"
                )
            }
        }
    }

    /// Cancel any pending notification for the episode.
    ///
    /// Call sites (to be wired — see audit):
    ///   - When the user plays the episode before the notification fires
    ///   - When the user unsubscribes from the podcast
    ///   - When the episode is deleted
    func cancelNewEpisodeNotification(for episode: Episode) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.identifier(for: episode)]
        )
    }

    // MARK: - Helpers

    private static func identifier(for episode: Episode) -> String {
        "new-episode-\(episode.id.uuidString)"
    }

    /// Reads the opt-in flag from UserDefaults. Default is `false`
    /// (opt-in by design — no surprise pushes). When `AppSettings`
    /// grows a typed accessor, this should delegate to it.
    private static var notificationsForNewEpisodesEnabled: Bool {
        UserDefaults.standard.bool(forKey: notificationsForNewEpisodesKey)
    }
}

// MARK: - Notification delegate

/// Routes notification taps and controls foreground presentation.
///
/// Lives outside `NotificationService` because `UNUserNotificationCenter`
/// only accepts an `NSObject`-derived delegate, and forcing
/// `NotificationService` itself to inherit from `NSObject` complicates
/// its `@MainActor` story. Keeping the delegate separate also lets us
/// install it lazily from `OffScriptApp` (see wiring follow-ups).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    @MainActor static let shared = NotificationDelegate()
    private let logger = Logger(subsystem: "com.offscript", category: "Notifications")

    /// Foreground presentation: show banner + sound even when the app is
    /// open. Without this, iOS silently suppresses the notification when
    /// the user is already in the app — which feels broken ("I had it
    /// open and never saw the new episode"). User can still swipe away.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Tap routing.
    ///
    /// `DeepLinkRouter.handle(_:in:)` requires a `ModelContext`, so we
    /// can't call it directly from here. Instead we re-open the URL via
    /// `UIApplication.shared.open`, which loops back through
    /// `ContentView.onOpenURL` → `DeepLinkRouter.handle`, picking up the
    /// live `ModelContext` from the environment.
    ///
    /// This is the same loopback `DeepLinkRouter`'s own doc comment
    /// recommends for cold-launch paths where the SwiftUI environment
    /// isn't yet wired.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["offscript-deeplink"] as? String,
           let url = URL(string: urlString) {
            Task { @MainActor in
                #if canImport(UIKit)
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                #endif
                self.logger.debug("Routed notification tap to \(urlString, privacy: .public)")
            }
        }
        completionHandler()
    }
}

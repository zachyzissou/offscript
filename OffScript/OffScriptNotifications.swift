import Foundation
import OSLog
import SwiftData
import UserNotifications

/// Centralized facade over UNUserNotificationCenter. Used by per-podcast
/// notification toggles in PodcastPreferencesSheet — schedules a local
/// notification when a watched show drops a new episode.
@MainActor
final class OffScriptNotifications {
    static let shared = OffScriptNotifications()

    private let logger = Logger(subsystem: "OffScript", category: "Notifications")
    private let center = UNUserNotificationCenter.current()
    private var didRequestPermission = false

    private init() {}

    /// Returns true if the user has authorized notifications.
    func currentAuthorization() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Requests permission (once per app run) and returns whether it was granted.
    @discardableResult
    func requestPermissionIfNeeded() async -> Bool {
        guard !didRequestPermission else {
            return await currentAuthorization() == .authorized
        }
        didRequestPermission = true
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.warning("Notification permission request failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Schedules a notification for a freshly-imported episode whose podcast
    /// has notifications enabled. Idempotent per episode ID — calling twice
    /// for the same episode does not double-schedule.
    func scheduleNewEpisodeNotificationIfNeeded(for episode: Episode) {
        guard PodcastPreferences.notificationsEnabled(for: episode.podcast.id) else { return }

        let identifier = "offscript.episode.\(episode.id.uuidString)"
        center.getPendingNotificationRequests { [weak self] pending in
            guard let self else { return }
            if pending.contains(where: { $0.identifier == identifier }) { return }

            Task { @MainActor in
                guard await self.requestPermissionIfNeeded() else { return }
                let content = UNMutableNotificationContent()
                content.title = episode.podcast.title
                content.subtitle = "New episode"
                content.body = episode.title
                content.sound = .default
                content.userInfo = [
                    "episodeID": episode.id.uuidString,
                    "podcastID": episode.podcast.id.uuidString
                ]

                // Fire 30 seconds out so we don't spam during a bulk import.
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30, repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                do {
                    try await self.center.add(request)
                } catch {
                    self.logger.warning("Failed to schedule notification: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    /// Cancel any pending new-episode notifications for a podcast (e.g. when
    /// the user turns notifications off for that show).
    func cancelPendingNotifications(forPodcastID podcastID: UUID, in context: ModelContext) {
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.podcast.id == podcastID }
        )
        guard let episodes = try? context.fetch(descriptor) else { return }
        let ids = episodes.map { "offscript.episode.\($0.id.uuidString)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}

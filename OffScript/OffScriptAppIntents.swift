import AppIntents
import Foundation
import SwiftData
import UIKit

/// App Intents — Siri / Shortcuts / Spotlight integration.
///
/// Lets the user say "Hey Siri, resume OffScript" or wire a Shortcut that
/// queues the current episode without unlocking the phone. These run in a
/// separate process from the app, so they touch only the shared
/// PlaybackController + a fresh ModelContext from the App Group container.
///
/// Anything that needs SwiftData uses `OffScriptAppIntents.makeContext()`
/// — never reach for the live SwiftUI ModelContext from inside an intent body.

enum OffScriptAppIntents {
    /// A short-lived ModelContext for the App Intents process. Built off the
    /// same on-disk store the main app uses so reads/writes are coherent.
    @MainActor
    static func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("OffScript", isDirectory: true)
        let storeURL = directory.appendingPathComponent("OffScript.store")
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, migrationPlan: OffScriptMigrationPlan.self, configurations: [config])
        return ModelContext(container)
    }
}

// MARK: - Resume Listening

struct ResumeListeningIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Listening"
    static let description = IntentDescription("Resume the most recent episode in OffScript.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let player = PlaybackController.shared
        if player.currentEpisode != nil {
            if !player.isPlaying { player.togglePlayPause() }
            return .result(dialog: "Resuming OffScript.")
        }

        // Fall back to the last-played episode persisted in UserDefaults.
        let context = try OffScriptAppIntents.makeContext()
        guard let savedURL = UserDefaults.standard.string(forKey: "offscript.lastEpisodeAudioURL"),
              let audioURL = URL(string: savedURL) else {
            return .result(dialog: "Nothing to resume yet — start an episode in OffScript first.")
        }
        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.audioURL == audioURL }
        )
        descriptor.fetchLimit = 1
        guard let episode = try context.fetch(descriptor).first else {
            return .result(dialog: "Couldn't find your last episode.")
        }
        player.play(episode, in: context)
        return .result(dialog: "Playing \(episode.title).")
    }
}

// MARK: - Skip Forward 30s

struct SkipForwardIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip Forward 30 Seconds"
    static let description = IntentDescription("Skip ahead 30 seconds in the current episode.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let player = PlaybackController.shared
        guard player.currentEpisode != nil else {
            return .result(dialog: "Nothing playing right now.")
        }
        player.seek(by: 30)
        return .result(dialog: "Skipped ahead.")
    }
}

// MARK: - Pause

struct PauseListeningIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause OffScript"
    static let description = IntentDescription("Pause the current episode.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let player = PlaybackController.shared
        guard player.currentEpisode != nil, player.isPlaying else {
            return .result(dialog: "Nothing to pause.")
        }
        player.togglePlayPause()
        return .result(dialog: "Paused.")
    }
}

// MARK: - Play Next In Queue

struct PlayNextInQueueIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Next in Queue"
    static let description = IntentDescription("Skip to the next queued episode in OffScript.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let player = PlaybackController.shared
        // Only supply a fresh intent-scoped context when the controller hasn't
        // been configured yet (i.e., the intent is running out-of-process).
        // When the main app is in the foreground (in-process execution), reusing
        // the existing context avoids opening a second writer on the same store,
        // which risks in-memory divergence between the two contexts.
        if !player.isModelContextConfigured {
            let context = try OffScriptAppIntents.makeContext()
            player.configure(context: context)
        }
        player.skipToNextInQueue()

        if let title = player.currentEpisode?.title {
            return .result(dialog: "Playing \(title).")
        }
        return .result(dialog: "Your queue is empty.")
    }
}

// MARK: - Episode Entity (Siri parameter)

/// `AppEntity` representation of an `Episode` so Siri can disambiguate by
/// title when the user says "Play <episode name> in OffScript." Without an
/// entity, the only intents Siri can offer are parameterless verbs like
/// Resume/Pause. With it, episodes become first-class addressable nouns in
/// the system search index and Shortcuts editor.
struct EpisodeEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Episode"
    static let defaultQuery = EpisodeEntityQuery()

    let id: UUID
    let title: String
    let podcastTitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(podcastTitle)")
    }
}

/// Resolves `EpisodeEntity` instances by UUID and by user-typed string in
/// the Shortcuts editor. Both paths run out-of-process, so we open a
/// short-lived `ModelContext` against the shared store.
struct EpisodeEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [EpisodeEntity] {
        guard !identifiers.isEmpty else { return [] }
        let context = try OffScriptAppIntents.makeContext()
        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { identifiers.contains($0.id) }
        )
        descriptor.fetchLimit = identifiers.count
        let episodes = try context.fetch(descriptor)
        return episodes.map { episode in
            EpisodeEntity(
                id: episode.id,
                title: episode.title,
                podcastTitle: episode.podcast.title
            )
        }
    }

    /// Suggestions for the Shortcuts UI: newest 25 episodes from subscribed
    /// shows. Capped because Shortcuts renders these in a scroll list and
    /// the user usually only wants something recent.
    @MainActor
    func suggestedEntities() async throws -> [EpisodeEntity] {
        let context = try OffScriptAppIntents.makeContext()
        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.podcast.isSubscribed == true },
            sortBy: [SortDescriptor(\Episode.pubDate, order: .reverse)]
        )
        descriptor.fetchLimit = 25
        let episodes = try context.fetch(descriptor)
        return episodes.map { episode in
            EpisodeEntity(
                id: episode.id,
                title: episode.title,
                podcastTitle: episode.podcast.title
            )
        }
    }
}

// MARK: - Play Episode (parameterized)

/// Plays a specific episode chosen via Siri / Shortcuts. Differs from
/// `ResumeListeningIntent` in that it takes an `EpisodeEntity` parameter, so
/// the user can wire a Shortcut to "Play <specific episode>" or pick one
/// from a list when invoking the shortcut.
struct PlayEpisodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Episode"
    static let description = IntentDescription("Start playing a specific episode in OffScript.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Episode")
    var episode: EpisodeEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try OffScriptAppIntents.makeContext()
        let targetID = episode.id
        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        guard let model = try context.fetch(descriptor).first else {
            return .result(dialog: "Couldn't find that episode anymore.")
        }
        let player = PlaybackController.shared
        if !player.isModelContextConfigured {
            player.configure(context: context)
        }
        player.play(model, in: context)
        return .result(dialog: "Playing \(model.title).")
    }
}

// MARK: - Open Tab Intents

/// Shared URL builder for the four open-tab intents. Each intent defers to
/// `DeepLinkRouter` via the universal `offscript://tab/<name>` scheme rather
/// than mutating a `ModelContext` or posting tab-switch notifications
/// directly — this keeps the intents free of SwiftData plumbing and lets
/// `ContentView.onOpenURL` remain the single arbiter of tab routing.
///
/// Exposed as a static helper so unit tests can assert the URL contract
/// without having to invoke `perform()` (which would require a host app
/// process and a live `UIApplication`).
enum OpenTabIntentURL {
    static let home = URL(string: "offscript://tab/home")!
    static let library = URL(string: "offscript://tab/library")!
    static let queue = URL(string: "offscript://tab/queue")!
    static let search = URL(string: "offscript://tab/search")!
}

/// Fire-and-forget donation for an open-tab intent. Mirrors the playback
/// donation pattern in `PlaybackController` so successful tab opens teach
/// Siri / Shortcuts the user's habits without blocking the intent return.
@MainActor
private func donateOpenTabIntent<Intent: AppIntent>(_ intent: Intent) {
    Task {
        do {
            try await intent.donate()
        } catch {
            // Donations are best-effort; failures here don't change app
            // behavior. Logged to console rather than OSLog to match the
            // out-of-process intent runtime where category loggers are
            // less useful for live debugging.
            print("Open-tab intent donation failed: \(error.localizedDescription)")
        }
    }
}

struct OpenHomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Home"
    static let description = IntentDescription("Open the Home tab in OffScript.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await UIApplication.shared.open(OpenTabIntentURL.home)
        donateOpenTabIntent(Self())
        return .result()
    }
}

struct OpenLibraryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Library"
    static let description = IntentDescription("Open your Library in OffScript.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await UIApplication.shared.open(OpenTabIntentURL.library)
        donateOpenTabIntent(Self())
        return .result()
    }
}

struct OpenQueueIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Queue"
    static let description = IntentDescription("Open your playback Queue in OffScript.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await UIApplication.shared.open(OpenTabIntentURL.queue)
        donateOpenTabIntent(Self())
        return .result()
    }
}

struct OpenSearchIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Search"
    static let description = IntentDescription("Open Search in OffScript.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await UIApplication.shared.open(OpenTabIntentURL.search)
        donateOpenTabIntent(Self())
        return .result()
    }
}

// MARK: - App Shortcuts

/// Registers Siri phrases. iOS will pick these up automatically and surface
/// them in the Shortcuts app, Siri Suggestions, and Spotlight.
struct OffScriptShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResumeListeningIntent(),
            phrases: [
                "Resume \(.applicationName)",
                "Continue listening in \(.applicationName)",
                "Keep playing \(.applicationName)"
            ],
            shortTitle: "Resume Listening",
            systemImageName: "play.fill"
        )

        AppShortcut(
            intent: PauseListeningIntent(),
            phrases: [
                "Pause \(.applicationName)",
                "Stop \(.applicationName)"
            ],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )

        AppShortcut(
            intent: SkipForwardIntent(),
            phrases: [
                "Skip ahead in \(.applicationName)",
                "Skip 30 seconds in \(.applicationName)"
            ],
            shortTitle: "Skip 30s",
            systemImageName: "goforward.30"
        )

        AppShortcut(
            intent: PlayNextInQueueIntent(),
            phrases: [
                "Play next in \(.applicationName)",
                "Skip to next \(.applicationName) episode"
            ],
            shortTitle: "Next in Queue",
            systemImageName: "forward.end.fill"
        )

        AppShortcut(
            intent: PlayEpisodeIntent(),
            phrases: [
                "Play an episode in \(.applicationName)",
                "Play \(\.$episode) in \(.applicationName)"
            ],
            shortTitle: "Play Episode",
            systemImageName: "play.circle.fill"
        )

        AppShortcut(
            intent: OpenHomeIntent(),
            phrases: [
                "Open home in \(.applicationName)",
                "Show home in \(.applicationName)",
                "Home in \(.applicationName)"
            ],
            shortTitle: "Open Home",
            systemImageName: "waveform.path.ecg"
        )

        AppShortcut(
            intent: OpenLibraryIntent(),
            phrases: [
                "Open my library in \(.applicationName)",
                "Show my library in \(.applicationName)",
                "Library in \(.applicationName)"
            ],
            shortTitle: "Open Library",
            systemImageName: "books.vertical"
        )

        AppShortcut(
            intent: OpenQueueIntent(),
            phrases: [
                "Open my queue in \(.applicationName)",
                "Show my queue in \(.applicationName)",
                "Queue in \(.applicationName)"
            ],
            shortTitle: "Open Queue",
            systemImageName: "text.badge.plus"
        )

        AppShortcut(
            intent: OpenSearchIntent(),
            phrases: [
                "Open search in \(.applicationName)",
                "Search in \(.applicationName)",
                "Find a podcast in \(.applicationName)"
            ],
            shortTitle: "Open Search",
            systemImageName: "magnifyingglass"
        )
    }
}

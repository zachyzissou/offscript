import AppIntents
import Foundation
import SwiftData

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
    }
}

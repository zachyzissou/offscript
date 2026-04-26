import AppIntents
import Foundation
import SwiftData
import SwiftUI

// MARK: - Open App Tabs

enum OffScriptTab: String, AppEnum {
    case home, library, queue, discover

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Tab")
    }

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .home: "Home",
        .library: "Library",
        .queue: "Queue",
        .discover: "Discover"
    ]

    var index: Int {
        switch self {
        case .home: return 0
        case .library: return 1
        case .queue: return 2
        case .discover: return 3
        }
    }
}

struct OpenOffScriptIntent: AppIntent {
    static var title: LocalizedStringResource = "Open OffScript"
    static var description = IntentDescription("Jump straight into a section of OffScript.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Section", default: .home)
    var tab: OffScriptTab

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            UserDefaults.standard.set(tab.index, forKey: "offscript.deepLinkTab")
            NotificationCenter.default.post(
                name: .offscriptIntentSelectTab,
                object: nil,
                userInfo: ["tab": tab.index]
            )
        }
        return .result()
    }
}

// MARK: - What's Next

struct WhatsNextIntent: AppIntent {
    static var title: LocalizedStringResource = "What's Next on OffScript"
    static var description = IntentDescription("Speak the next episode queued up.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog: IntentDialog = await MainActor.run {
            let player = PlaybackController.shared
            if let current = player.currentEpisode {
                return IntentDialog("Currently playing \(current.title) from \(current.podcast.title).")
            }
            return IntentDialog("Open OffScript to pick something to play.")
        }
        return .result(dialog: dialog)
    }
}

// MARK: - Shortcuts Provider

struct OffScriptAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResumePlaybackIntent(),
            phrases: [
                "Resume \(.applicationName)",
                "Keep playing in \(.applicationName)"
            ],
            shortTitle: "Resume",
            systemImageName: "play.fill"
        )

        AppShortcut(
            intent: PausePlaybackIntent(),
            phrases: [
                "Pause \(.applicationName)"
            ],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )

        AppShortcut(
            intent: PlayNextInQueueIntent(),
            phrases: [
                "Play next in \(.applicationName)",
                "Skip to next in \(.applicationName)"
            ],
            shortTitle: "Play Next",
            systemImageName: "forward.end.fill"
        )

        AppShortcut(
            intent: WhatsNextIntent(),
            phrases: [
                "What's next on \(.applicationName)",
                "Show me my next \(.applicationName) episode"
            ],
            shortTitle: "What's Next",
            systemImageName: "list.bullet.rectangle"
        )

        AppShortcut(
            intent: OpenOffScriptIntent(),
            phrases: [
                "Open my queue in \(.applicationName)",
                "Show my listening shelf in \(.applicationName)"
            ],
            shortTitle: "Open OffScript",
            systemImageName: "waveform"
        )

        AppShortcut(
            intent: BuildTimeSlotPlaylistIntent(),
            phrases: [
                "Build me a \(.applicationName) session",
                "Make me a 30 minute \(.applicationName) playlist"
            ],
            shortTitle: "Build session",
            systemImageName: "timer"
        )
    }
}

extension Notification.Name {
    static let offscriptIntentSelectTab = Notification.Name("com.offscript.intent.selectTab")
}

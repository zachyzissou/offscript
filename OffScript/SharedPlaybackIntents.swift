import AppIntents
import Foundation
#if !WIDGET_EXTENSION
import SwiftData
#endif

// These intents are compiled into BOTH the main app and the OffScriptWidgets
// extension, so widget buttons (Live Activity + Home Screen) can invoke them.
// `openAppWhenRun = true` ensures the app process runs `perform()`, so the
// PlaybackController is always available at execution time.
//
// The #if guard skips the implementation when compiled into the widget target —
// the type definition is what the widget needs at compile time; the system
// launches the app and runs the body there.

struct ResumePlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Listening"
    static var description = IntentDescription("Resume the most recent OffScript episode.")
    static var openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run {
            let player = PlaybackController.shared
            if player.currentEpisode != nil, !player.isPlaying {
                player.togglePlayPause()
            }
        }
        #endif
        return .result()
    }
}

struct PausePlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Listening"
    static var description = IntentDescription("Pause OffScript playback.")
    static var openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run {
            let player = PlaybackController.shared
            if player.isPlaying {
                player.togglePlayPause()
            }
        }
        #endif
        return .result()
    }
}

struct SkipForwardIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Forward 30 Seconds"
    static var openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run { PlaybackController.shared.seek(by: 30) }
        #endif
        return .result()
    }
}

struct SkipBackwardIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Back 15 Seconds"
    static var openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run { PlaybackController.shared.seek(by: -15) }
        #endif
        return .result()
    }
}

struct PlayNextInQueueIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Next in Queue"
    static var description = IntentDescription("Skip to the next queued OffScript episode.")
    static var openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run { PlaybackController.shared.skipToNextInQueue() }
        #endif
        return .result()
    }
}

struct BuildTimeSlotPlaylistIntent: AppIntent {
    static var title: LocalizedStringResource = "Build a listening session"
    static var description = IntentDescription("OffScript builds a queue that fits the time window you've got — using shows you've started and the next-best picks.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Minutes", default: 30)
    var minutes: Int

    init() {}
    init(minutes: Int) { self.minutes = minutes }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if !WIDGET_EXTENSION
        let dialog: IntentDialog = await MainActor.run {
            guard let context = ModelContainerRef.shared?.mainContext else {
                return IntentDialog("Open OffScript first so I can build your queue.")
            }
            return IntentDialog("Building a \(self.minutes) minute session…")
        }
        await MainActor.run {
            guard let context = ModelContainerRef.shared?.mainContext else { return }
            Task { @MainActor in
                if let plan = await TimeSlotPlaylistService.shared.buildPlan(targetMinutes: self.minutes, in: context) {
                    TimeSlotPlaylistService.shared.apply(plan: plan, in: context)
                }
            }
        }
        return .result(dialog: dialog)
        #else
        return .result(dialog: IntentDialog("OffScript will build your session."))
        #endif
    }
}

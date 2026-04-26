import SwiftUI
import TipKit

/// First-time gesture hint for the MiniPlayer — shown once until the user
/// has dismissed it via swipe.
struct MiniPlayerSwipeTip: Tip {
    @Parameter
    static var miniPlayerPresentations: Int = 0

    var title: Text {
        Text("Swipe to dismiss")
            .foregroundStyle(Color.offscriptTextPrimary)
    }

    var message: Text? {
        Text("Drag the player right to clear it. Swipe up to open the full view.")
    }

    var image: Image? {
        Image(systemName: "hand.draw")
    }

    var rules: [Rule] {
        #Rule(Self.$miniPlayerPresentations) { $0 >= 2 }
    }

    var options: [any TipOption] {
        [
            Tips.MaxDisplayCount(2)
        ]
    }
}

enum OffScriptTips {
    static func configureIfNeeded() {
        do {
            try Tips.configure([
                .displayFrequency(.daily),
                .datastoreLocation(.applicationDefault)
            ])
        } catch {
            // Non-fatal — TipKit will fall back to default behavior.
        }
    }
}

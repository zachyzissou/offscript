import SwiftUI
import WidgetKit

/// Entry point for the OffScript widget extension. Hosts:
///   - NowPlayingWidget — Lock Screen + Home Screen widget
///   - NowPlayingLiveActivity — Dynamic Island + Lock Screen Live Activity
///
/// State is shared with the main app via App Group `group.com.offscript.shared`
/// using `UserDefaults(suiteName:)`. The main app writes the snapshot whenever
/// playback state changes; the widget reads it on each timeline refresh.
@main
struct OffScriptWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        NowPlayingLiveActivity()
    }
}

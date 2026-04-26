import SwiftUI
import WidgetKit

@main
struct OffScriptWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingLiveActivity()
        NowPlayingWidget()
    }
}

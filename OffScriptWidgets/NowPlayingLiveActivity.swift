import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity attributes for now-playing. Renders on the Lock Screen
/// (banner) and in the Dynamic Island (compact + expanded). Updated by the
/// main app via `Activity.update(...)` whenever playback state changes.
public struct NowPlayingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var episodeTitle: String
        public var podcastTitle: String
        public var isPlaying: Bool
        public var currentTime: TimeInterval
        public var duration: TimeInterval

        public init(
            episodeTitle: String,
            podcastTitle: String,
            isPlaying: Bool,
            currentTime: TimeInterval,
            duration: TimeInterval
        ) {
            self.episodeTitle = episodeTitle
            self.podcastTitle = podcastTitle
            self.isPlaying = isPlaying
            self.currentTime = currentTime
            self.duration = duration
        }

        public var progress: Double {
            guard duration > 0 else { return 0 }
            return min(max(currentTime / duration, 0), 1)
        }
    }

    /// Static for the lifetime of the activity — the artwork URL doesn't
    /// change while a single episode is playing.
    public var artworkURL: URL?

    public init(artworkURL: URL? = nil) {
        self.artworkURL = artworkURL
    }
}

struct NowPlayingLiveActivity: Widget {
    private static let openPlayerURL = URL(string: "offscript://player")!

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingActivityAttributes.self) { context in
            // Lock Screen / banner — wrap in Link so tapping deep-links to
            // the player rather than the default app launch.
            Link(destination: Self.openPlayerURL) {
                LockScreenView(attributes: context.attributes, state: context.state)
            }
            .activityBackgroundTint(OffScriptWidgetTunerStyle.background)
            .activitySystemActionForegroundColor(OffScriptWidgetTunerStyle.signalYellow)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    TunerWidgetArtwork(url: context.attributes.artworkURL, size: 44)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(OffScriptWidgetTunerStyle.transportColor(isPlaying: context.state.isPlaying))
                        .accessibilityLabel(context.state.isPlaying ? "Playing" : "Paused")
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        TunerWidgetMetadata(
                            text: context.state.isPlaying ? "LIVE SIGNAL" : "PAUSED",
                            color: context.state.isPlaying
                                ? OffScriptWidgetTunerStyle.fnMode
                                : OffScriptWidgetTunerStyle.fnMute,
                            size: 8
                        )
                        .accessibilityHidden(true)
                        Text(context.state.episodeTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OffScriptWidgetTunerStyle.paperWhite)
                            .lineLimit(1)
                        Text(context.state.podcastTitle)
                            .font(OffScriptWidgetTunerStyle.metadataFont(size: 10, weight: .medium))
                            .foregroundStyle(OffScriptWidgetTunerStyle.fnInfo)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TunerWidgetProgressRail(progress: context.state.progress)
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "waveform" : "play.fill")
                    .foregroundStyle(OffScriptWidgetTunerStyle.transportColor(isPlaying: context.state.isPlaying))
                    .accessibilityLabel(context.state.isPlaying ? "Playing" : "Paused")
            } compactTrailing: {
                Text(timeRemaining(state: context.state))
                    .font(OffScriptWidgetTunerStyle.metadataFont(size: 11))
                    .foregroundStyle(OffScriptWidgetTunerStyle.paperWhite)
                    .accessibilityLabel("Time remaining \(timeRemaining(state: context.state))")
            } minimal: {
                Image(systemName: context.state.isPlaying ? "waveform" : "play.fill")
                    .foregroundStyle(OffScriptWidgetTunerStyle.transportColor(isPlaying: context.state.isPlaying))
                    .accessibilityLabel(context.state.isPlaying ? "OffScript playing" : "OffScript paused")
            }
        }
    }

    private func timeRemaining(state: NowPlayingActivityAttributes.ContentState) -> String {
        let remaining = max(state.duration - state.currentTime, 0)
        let minutes = Int(remaining / 60)
        return minutes >= 60
            ? "\(minutes / 60)h\(minutes % 60)m"
            : "\(minutes)m"
    }
}

private struct LockScreenView: View {
    let attributes: NowPlayingActivityAttributes
    let state: NowPlayingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            TunerWidgetArtwork(url: attributes.artworkURL, size: 56)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: state.isPlaying ? "waveform" : "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(OffScriptWidgetTunerStyle.transportColor(isPlaying: state.isPlaying))
                        .accessibilityHidden(true) // status conveyed in combined label below
                    TunerWidgetMetadata(
                        text: state.isPlaying ? "OFFSCRIPT · LIVE" : "OFFSCRIPT · HOLD",
                        color: state.isPlaying
                            ? OffScriptWidgetTunerStyle.signalYellow
                            : OffScriptWidgetTunerStyle.fnMute
                    )
                        .accessibilityHidden(true) // wordmark; surfaced via combined label
                    Spacer()
                }
                Text(state.episodeTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OffScriptWidgetTunerStyle.paperWhite)
                    .lineLimit(2)
                Text(state.podcastTitle)
                    .font(OffScriptWidgetTunerStyle.metadataFont(size: 10, weight: .medium))
                    .foregroundStyle(OffScriptWidgetTunerStyle.fnInfo)
                    .lineLimit(1)
                TunerWidgetProgressRail(progress: state.progress)
            }
        }
        .padding(12)
        .background(OffScriptWidgetTunerStyle.background)
        .overlay(Rectangle().stroke(OffScriptWidgetTunerStyle.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "OffScript, \(state.isPlaying ? "playing" : "paused"). \(state.episodeTitle) from \(state.podcastTitle)."
        )
    }
}

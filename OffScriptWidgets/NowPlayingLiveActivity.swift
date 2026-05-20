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
            .activityBackgroundTint(Color.black.opacity(0.92))
            .activitySystemActionForegroundColor(Color.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    if let url = context.attributes.artworkURL {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.secondary.opacity(0.2)
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .accessibilityLabel(context.state.isPlaying ? "Playing" : "Paused")
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.episodeTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(context.state.podcastTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress).tint(.orange)
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "waveform" : "play.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(context.state.isPlaying ? "Playing" : "Paused")
            } compactTrailing: {
                Text(timeRemaining(state: context.state))
                    .font(.caption2.monospacedDigit())
                    .accessibilityLabel("Time remaining \(timeRemaining(state: context.state))")
            } minimal: {
                Image(systemName: context.state.isPlaying ? "waveform" : "play.fill")
                    .foregroundStyle(.orange)
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
            if let url = attributes.artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.2)
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: state.isPlaying ? "waveform" : "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true) // status conveyed in combined label below
                    Text("OFFSCRIPT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true) // wordmark; surfaced via combined label
                    Spacer()
                }
                Text(state.episodeTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(state.podcastTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: state.progress).tint(.orange)
                    .accessibilityValue("\(Int(state.progress * 100)) percent")
            }
        }
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "OffScript, \(state.isPlaying ? "playing" : "paused"). \(state.episodeTitle) from \(state.podcastTitle)."
        )
    }
}

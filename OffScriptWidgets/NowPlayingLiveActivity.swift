import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingAttributes.self) { context in
            // Lock-screen / banner UI
            LockScreenLiveActivityView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(Color.offscriptAccentForWidget)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    NowPlayingArtwork(url: context.state.artworkURL, size: 56)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PlayPauseButton(isPlaying: context.state.isPlaying)
                        .frame(width: 44, height: 44)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.episodeTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(2)
                        Text(context.state.podcastTitle)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 18) {
                        Button(intent: SkipBackwardIntent()) {
                            Image(systemName: "gobackward.15")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 36, height: 32)
                        }
                        .buttonStyle(.plain)

                        NowPlayingProgress(state: context.state)
                            .frame(maxWidth: .infinity)

                        Button(intent: SkipForwardIntent()) {
                            Image(systemName: "goforward.30")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 36, height: 32)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                NowPlayingArtwork(url: context.state.artworkURL, size: 22)
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .symbolEffect(.variableColor.iterative.reversing, options: context.state.isPlaying ? .repeating : .nonRepeating)
                    .foregroundStyle(Color.offscriptAccentForWidget)
            } minimal: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .symbolEffect(.variableColor.iterative.reversing, options: context.state.isPlaying ? .repeating : .nonRepeating)
                    .foregroundStyle(Color.offscriptAccentForWidget)
            }
            .keylineTint(Color.offscriptAccentForWidget)
        }
    }
}

private struct LockScreenLiveActivityView: View {
    let state: NowPlayingAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            NowPlayingArtwork(url: state.artworkURL, size: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text(state.podcastTitle.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(Color.offscriptAccentForWidget)
                    .lineLimit(1)

                Text(state.episodeTitle)
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .lineLimit(2)

                NowPlayingProgress(state: state)
            }

            VStack(spacing: 8) {
                PlayPauseButton(isPlaying: state.isPlaying)
                    .frame(width: 40, height: 40)

                Button(intent: SkipForwardIntent()) {
                    Image(systemName: "goforward.30")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 36, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }
}

struct NowPlayingProgress: View {
    let state: NowPlayingAttributes.ContentState

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(Color.offscriptAccentForWidget)
                        .frame(width: max(proxy.size.width * state.progress, 4))
                }
            }
            .frame(height: 4)

            HStack {
                Text(format(state.elapsed))
                Spacer()
                Text("-\(format(state.remaining))")
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.7))
        }
    }

    private func format(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let total = Int(max(value, 0))
        let minutes = total / 60
        let seconds = total % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return "\(hours):\(String(format: "%02d", remainder)):\(String(format: "%02d", seconds))"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

struct NowPlayingArtwork: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.offscriptAccentForWidget.opacity(0.4), Color.black.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "waveform")
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

struct PlayPauseButton: View {
    let isPlaying: Bool

    var body: some View {
        Group {
            if isPlaying {
                Button(intent: PausePlaybackIntent()) {
                    label
                }
            } else {
                Button(intent: ResumePlaybackIntent()) {
                    label
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var label: some View {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.title3.weight(.bold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.offscriptAccentForWidget, in: Circle())
    }
}

extension Color {
    static let offscriptAccentForWidget = Color(red: 0.96, green: 0.52, blue: 0.19)
}

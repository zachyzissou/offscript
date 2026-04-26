import AppIntents
import SwiftUI
import WidgetKit

struct NowPlayingWidget: Widget {
    let kind: String = "com.offscript.widget.nowplaying"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.95), Color(red: 0.10, green: 0.09, blue: 0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("Now Playing")
        .description("Tap to jump back into your current OffScript episode.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let episodeTitle: String?
    let podcastTitle: String?
    let artworkURL: URL?
    let elapsed: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(
            date: .now,
            episodeTitle: "The State of the Entertainment Business",
            podcastTitle: "Conan O'Brien Needs A Friend",
            artworkURL: nil,
            elapsed: 0,
            duration: 1,
            isPlaying: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        // Project the snapshot's elapsed time forward into the future so the
        // progress bar advances even if the app hasn't pushed a fresh snapshot.
        let now = Date()
        var entries: [NowPlayingEntry] = []

        guard let snapshot = SharedNowPlayingState.read() else {
            entries.append(emptyEntry(at: now))
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(60 * 5))))
            return
        }

        let stride: TimeInterval = snapshot.isPlaying ? 60 : 60 * 5
        let count = snapshot.isPlaying ? 10 : 1

        for index in 0..<count {
            let date = now.addingTimeInterval(stride * Double(index))
            let elapsed = snapshot.projectedElapsed(at: date)
            entries.append(NowPlayingEntry(
                date: date,
                episodeTitle: snapshot.episodeTitle,
                podcastTitle: snapshot.podcastTitle,
                artworkURL: snapshot.artworkURL,
                elapsed: elapsed,
                duration: snapshot.duration,
                isPlaying: snapshot.isPlaying
            ))
        }

        let refresh = entries.last?.date.addingTimeInterval(stride) ?? now.addingTimeInterval(60)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    private func currentEntry() -> NowPlayingEntry {
        guard let snapshot = SharedNowPlayingState.read() else { return emptyEntry(at: .now) }
        return NowPlayingEntry(
            date: .now,
            episodeTitle: snapshot.episodeTitle,
            podcastTitle: snapshot.podcastTitle,
            artworkURL: snapshot.artworkURL,
            elapsed: snapshot.projectedElapsed(),
            duration: snapshot.duration,
            isPlaying: snapshot.isPlaying
        )
    }

    private func emptyEntry(at date: Date) -> NowPlayingEntry {
        NowPlayingEntry(date: date, episodeTitle: nil, podcastTitle: nil, artworkURL: nil, elapsed: 0, duration: 1, isPlaying: false)
    }
}

struct NowPlayingWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowPlayingEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("OffScript ∙ tap to listen")
        case .accessoryCircular:
            ZStack {
                Circle().fill(Color.offscriptAccentForWidget.opacity(0.25))
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
                    .foregroundStyle(Color.offscriptAccentForWidget)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.episodeTitle ?? "Open OffScript")
                    .font(.headline)
                    .lineLimit(1)
                Text(entry.podcastTitle ?? "Pick something to listen to")
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        default:
            HStack(alignment: .top, spacing: 12) {
                if family == .systemMedium {
                    NowPlayingArtwork(url: entry.artworkURL, size: 76)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: entry.isPlaying ? "waveform" : "pause.fill")
                            .symbolEffect(.variableColor.iterative.reversing, options: entry.isPlaying ? .repeating : .nonRepeating)
                            .foregroundStyle(Color.offscriptAccentForWidget)
                        Text(entry.podcastTitle?.uppercased() ?? "OFFSCRIPT")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .tracking(1.0)
                            .foregroundStyle(Color.offscriptAccentForWidget)
                            .lineLimit(1)
                    }

                    Text(entry.episodeTitle ?? "Tap to open OffScript")
                        .font(.system(.headline, design: .serif, weight: .semibold))
                        .lineLimit(family == .systemMedium ? 3 : 4)
                        .foregroundStyle(.white)

                    Spacer(minLength: 0)

                    if entry.duration > 0 && entry.episodeTitle != nil {
                        widgetProgress(elapsed: entry.elapsed, duration: entry.duration)
                    }

                    HStack(spacing: 6) {
                        if entry.isPlaying {
                            Button(intent: PausePlaybackIntent()) {
                                widgetTransportLabel(systemImage: "pause.fill", title: "Pause")
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(intent: ResumePlaybackIntent()) {
                                widgetTransportLabel(systemImage: "play.fill", title: entry.episodeTitle == nil ? "Open" : "Resume")
                            }
                            .buttonStyle(.plain)
                        }

                        if entry.episodeTitle != nil && family == .systemMedium {
                            Button(intent: SkipForwardIntent()) {
                                Image(systemName: "goforward.30")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.white.opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(2)
        }
    }

    @ViewBuilder
    private func widgetProgress(elapsed: TimeInterval, duration: TimeInterval) -> some View {
        let fraction = max(0, min(elapsed / max(duration, 1), 1))
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                    Capsule()
                        .fill(Color.offscriptAccentForWidget)
                        .frame(width: max(proxy.size.width * fraction, 4))
                }
            }
            .frame(height: 4)

            HStack {
                Text(formatShort(elapsed))
                Spacer()
                Text("-\(formatShort(max(duration - elapsed, 0)))")
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func widgetTransportLabel(systemImage: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.black)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.offscriptAccentForWidget, in: Capsule())
    }

    private func formatShort(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let total = Int(max(value, 0))
        let minutes = total / 60
        let seconds = total % 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

#Preview(as: .systemMedium) {
    NowPlayingWidget()
} timeline: {
    NowPlayingEntry(
        date: .now,
        episodeTitle: "The State of Entertainment Business",
        podcastTitle: "Conan O'Brien Needs A Friend",
        artworkURL: nil,
        elapsed: 720,
        duration: 3600,
        isPlaying: true
    )
}

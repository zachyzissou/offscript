import SwiftUI
import WidgetKit

enum OffScriptWidgetTunerStyle {
    static let background = Color(red: 0, green: 0, blue: 0)
    static let panel = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let paperWhite = Color(red: 0.953, green: 0.945, blue: 0.918)
    static let softPaper = Color(red: 0.478, green: 0.471, blue: 0.447)
    static let signalYellow = Color(red: 0.910, green: 0.824, blue: 0.290)
    static let fnRecord = Color(red: 0.910, green: 0.353, blue: 0.235)
    static let fnMode = Color(red: 0.373, green: 0.812, blue: 0.494)
    static let fnInfo = Color(red: 0.365, green: 0.769, blue: 0.910)
    static let fnMute = Color(red: 0.478, green: 0.471, blue: 0.447)
    static let hairline = Color(red: 1, green: 1, blue: 1).opacity(0.08)

    static func transportColor(isPlaying: Bool) -> Color {
        isPlaying ? fnMode : signalYellow
    }

    static func metadataFont(size: CGFloat = 9, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

struct TunerWidgetMetadata: View {
    let text: String
    var color: Color = OffScriptWidgetTunerStyle.signalYellow
    var size: CGFloat = 9

    var body: some View {
        Text(text)
            .font(OffScriptWidgetTunerStyle.metadataFont(size: size))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

struct TunerWidgetProgressRail: View {
    let progress: Double

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let fillWidth = proxy.size.width * clampedProgress

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(OffScriptWidgetTunerStyle.hairline)
                Rectangle()
                    .fill(OffScriptWidgetTunerStyle.signalYellow)
                    .frame(width: max(fillWidth, clampedProgress > 0 ? 2 : 0))
            }
        }
        .frame(height: 3)
        .accessibilityValue("\(Int(clampedProgress * 100)) percent")
    }
}

struct TunerWidgetArtwork: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        ZStack {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(OffScriptWidgetTunerStyle.hairline, lineWidth: 1)
        )
    }

    private var placeholder: some View {
        ZStack {
            OffScriptWidgetTunerStyle.panel
            VStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    Rectangle()
                        .fill(index == 2 ? OffScriptWidgetTunerStyle.signalYellow : OffScriptWidgetTunerStyle.hairline)
                        .frame(width: size * (0.28 + CGFloat(index) * 0.08), height: 1)
                }
            }
        }
    }
}

/// Lock Screen + Home Screen widget showing the currently-playing episode.
///
/// Tapping the widget deep-links into the OffScript player via the
/// `offscript://player` URL (handled in OffScriptApp.onOpenURL — TODO).
struct NowPlayingWidget: Widget {
    let kind: String = "NowPlayingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
                .containerBackground(OffScriptWidgetTunerStyle.background, for: .widget)
                // Tap → deep-link into the player. Handled by
                // DeepLinkRouter.handle in the main app's onOpenURL.
                .widgetURL(URL(string: "offscript://player"))
        }
        .configurationDisplayName("Now Playing")
        .description("See the OffScript episode you're currently listening to.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: .now, snapshot: NowPlayingSnapshot.empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(NowPlayingEntry(date: .now, snapshot: NowPlayingStorage.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let snapshot = NowPlayingStorage.read()
        let entry = NowPlayingEntry(date: .now, snapshot: snapshot)
        // Refresh in 5 minutes — widget extensions are budget-limited; the
        // main app pokes WidgetCenter on real state changes for instant updates.
        let next = Date().addingTimeInterval(5 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingSnapshot
}

struct NowPlayingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowPlayingEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            inlineView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        default:
            mediumView
        }
    }

    // MARK: - Lock Screen / watchOS-style accessories

    private var inlineView: some View {
        Group {
            if entry.snapshot.isActive {
                Text("\(entry.snapshot.isPlaying ? "▶" : "⏸") \(entry.snapshot.episodeTitle)")
            } else {
                Text("OffScript — nothing playing")
            }
        }
        .font(OffScriptWidgetTunerStyle.metadataFont(size: 11))
        .foregroundStyle(OffScriptWidgetTunerStyle.paperWhite)
    }

    private var circularView: some View {
        ZStack {
            ProgressView(value: entry.snapshot.progress)
                .progressViewStyle(.circular)
                .tint(OffScriptWidgetTunerStyle.signalYellow)
            Image(systemName: entry.snapshot.isPlaying ? "waveform" : "play.fill")
                .font(.headline)
                .foregroundStyle(OffScriptWidgetTunerStyle.transportColor(isPlaying: entry.snapshot.isPlaying))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            entry.snapshot.isActive
                ? "\(entry.snapshot.isPlaying ? "Playing" : "Paused"), \(Int(entry.snapshot.progress * 100)) percent"
                : "OffScript, nothing playing"
        )
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            TunerWidgetMetadata(
                text: entry.snapshot.isPlaying ? "NOW PLAYING" : "STANDBY",
                color: entry.snapshot.isActive
                    ? OffScriptWidgetTunerStyle.transportColor(isPlaying: entry.snapshot.isPlaying)
                    : OffScriptWidgetTunerStyle.fnMute,
                size: 8
            )
            Text(entry.snapshot.isActive ? entry.snapshot.episodeTitle : "OffScript")
                .font(.headline.weight(.semibold))
                .foregroundStyle(OffScriptWidgetTunerStyle.paperWhite)
                .lineLimit(2)
            if entry.snapshot.isActive {
                Text(entry.snapshot.podcastTitle)
                    .font(OffScriptWidgetTunerStyle.metadataFont(size: 10, weight: .medium))
                    .foregroundStyle(OffScriptWidgetTunerStyle.fnInfo)
                    .lineLimit(1)
                TunerWidgetProgressRail(progress: entry.snapshot.progress)
            } else {
                Text("Nothing playing")
                    .font(OffScriptWidgetTunerStyle.metadataFont(size: 10, weight: .medium))
                    .foregroundStyle(OffScriptWidgetTunerStyle.softPaper)
            }
        }
    }

    // MARK: - Home Screen widgets

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: entry.snapshot.isPlaying ? "waveform" : "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(OffScriptWidgetTunerStyle.transportColor(isPlaying: entry.snapshot.isPlaying))
                    .accessibilityHidden(true)
                Spacer()
                TunerWidgetMetadata(text: "OFFSCRIPT", color: OffScriptWidgetTunerStyle.softPaper)
                    .accessibilityHidden(true)
            }

            Spacer()

            if entry.snapshot.isActive {
                Text(entry.snapshot.episodeTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OffScriptWidgetTunerStyle.paperWhite)
                    .lineLimit(3)
                Text(entry.snapshot.podcastTitle)
                    .font(OffScriptWidgetTunerStyle.metadataFont(size: 10, weight: .medium))
                    .foregroundStyle(OffScriptWidgetTunerStyle.fnInfo)
                    .lineLimit(1)
            } else {
                Text("Nothing playing")
                    .font(OffScriptWidgetTunerStyle.metadataFont(size: 11, weight: .medium))
                    .foregroundStyle(OffScriptWidgetTunerStyle.softPaper)
            }

            if entry.snapshot.isActive {
                TunerWidgetProgressRail(progress: entry.snapshot.progress)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(Rectangle().stroke(OffScriptWidgetTunerStyle.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            entry.snapshot.isActive
                ? "OffScript, \(entry.snapshot.isPlaying ? "playing" : "paused"). \(entry.snapshot.episodeTitle) from \(entry.snapshot.podcastTitle)."
                : "OffScript, nothing playing."
        )
    }

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 12) {
            TunerWidgetArtwork(url: entry.snapshot.artworkURL, size: 64)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: entry.snapshot.isPlaying ? "waveform" : "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(OffScriptWidgetTunerStyle.transportColor(isPlaying: entry.snapshot.isPlaying))
                        .accessibilityHidden(true)
                    TunerWidgetMetadata(
                        text: entry.snapshot.isActive ? "NOW PLAYING" : "STANDBY",
                        color: entry.snapshot.isActive ? OffScriptWidgetTunerStyle.signalYellow : OffScriptWidgetTunerStyle.fnMute
                    )
                        .accessibilityHidden(true)
                    Spacer()
                }

                if entry.snapshot.isActive {
                    Text(entry.snapshot.episodeTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OffScriptWidgetTunerStyle.paperWhite)
                        .lineLimit(2)
                    Text(entry.snapshot.podcastTitle)
                        .font(OffScriptWidgetTunerStyle.metadataFont(size: 10, weight: .medium))
                        .foregroundStyle(OffScriptWidgetTunerStyle.fnInfo)
                        .lineLimit(1)
                    TunerWidgetProgressRail(progress: entry.snapshot.progress)
                } else {
                    Text("Tap to open OffScript")
                        .font(OffScriptWidgetTunerStyle.metadataFont(size: 10, weight: .medium))
                        .foregroundStyle(OffScriptWidgetTunerStyle.softPaper)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(Rectangle().stroke(OffScriptWidgetTunerStyle.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            entry.snapshot.isActive
                ? "Now playing on OffScript: \(entry.snapshot.episodeTitle) from \(entry.snapshot.podcastTitle). \(entry.snapshot.isPlaying ? "Playing" : "Paused")."
                : "OffScript. Tap to open."
        )
    }
}

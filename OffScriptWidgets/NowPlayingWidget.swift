import SwiftUI
import WidgetKit

/// Lock Screen + Home Screen widget showing the currently-playing episode.
///
/// Tapping the widget deep-links into the OffScript player via the
/// `offscript://player` URL (handled in OffScriptApp.onOpenURL — TODO).
struct NowPlayingWidget: Widget {
    let kind: String = "NowPlayingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
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
    }

    private var circularView: some View {
        ZStack {
            ProgressView(value: entry.snapshot.progress)
                .progressViewStyle(.circular)
            Image(systemName: entry.snapshot.isPlaying ? "waveform" : "play.fill")
                .font(.headline)
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
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.snapshot.isActive ? entry.snapshot.episodeTitle : "OffScript")
                .font(.headline)
                .lineLimit(2)
            if entry.snapshot.isActive {
                Text(entry.snapshot.podcastTitle)
                    .font(.caption)
                    .lineLimit(1)
                ProgressView(value: entry.snapshot.progress)
                    .tint(.orange)
            } else {
                Text("Nothing playing")
                    .font(.caption)
            }
        }
    }

    // MARK: - Home Screen widgets

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: entry.snapshot.isPlaying ? "waveform" : "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Spacer()
                Text("OFFSCRIPT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Spacer()

            if entry.snapshot.isActive {
                Text(entry.snapshot.episodeTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                Text(entry.snapshot.podcastTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Nothing playing")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if entry.snapshot.isActive {
                ProgressView(value: entry.snapshot.progress)
                    .tint(.orange)
                    .accessibilityValue("\(Int(entry.snapshot.progress * 100)) percent")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            entry.snapshot.isActive
                ? "OffScript, \(entry.snapshot.isPlaying ? "playing" : "paused"). \(entry.snapshot.episodeTitle) from \(entry.snapshot.podcastTitle)."
                : "OffScript, nothing playing."
        )
    }

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 12) {
            // Artwork (loaded async; will be empty placeholder on first paint)
            if let url = entry.snapshot.artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.2)
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: entry.snapshot.isPlaying ? "waveform" : "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("NOW PLAYING")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Spacer()
                }

                if entry.snapshot.isActive {
                    Text(entry.snapshot.episodeTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(entry.snapshot.podcastTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressView(value: entry.snapshot.progress)
                        .tint(.orange)
                        .accessibilityValue("\(Int(entry.snapshot.progress * 100)) percent")
                } else {
                    Text("Tap to open OffScript")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            entry.snapshot.isActive
                ? "Now playing on OffScript: \(entry.snapshot.episodeTitle) from \(entry.snapshot.podcastTitle). \(entry.snapshot.isPlaying ? "Playing" : "Paused")."
                : "OffScript. Tap to open."
        )
    }
}

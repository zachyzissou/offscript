import Charts
import SwiftData
import SwiftUI

/// Editorial recap of the user's last 30 days of listening — minutes per day,
/// top shows, top topics. Surfaced from Settings; designed to feel like a
/// short editor's note rather than a dashboard.
struct ListeningInsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var podcasts: [Podcast]

    @State private var events: [PlaybackEvent] = []
    @State private var hasLoaded = false

    private let lookbackDays = 30

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                    OffScriptUtilityHeader(
                        eyebrow: "Last \(lookbackDays) days",
                        title: greeting,
                        subtitle: subtitleLine
                    )
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    statSummary
                        .padding(.horizontal, OffScriptTheme.pagePadding)

                    if !dailyMinutes.isEmpty {
                        dailyChart
                            .padding(.horizontal, OffScriptTheme.pagePadding)
                    }

                    if !topShows.isEmpty {
                        topShowsSection
                    }

                    if !topTopics.isEmpty {
                        topTopicsSection
                    }

                    if !abandonedShows.isEmpty {
                        abandonedSection
                    }

                    Spacer(minLength: 32)
                }
                .padding(.vertical, 16)
            }
            .offscriptPageBackground()
            .navigationTitle("Your Listening")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .tint(Color.offscriptAccent)
                }
            }
            .toolbarBackground(Color.offscriptBackgroundTop.opacity(0.98), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task {
            // Scope at query time to the lookback window so we don't pull
            // every PlaybackEvent the app has ever recorded.
            guard !hasLoaded else { return }
            hasLoaded = true
            let cutoff = lookbackCutoff
            let descriptor = FetchDescriptor<PlaybackEvent>(
                predicate: #Predicate<PlaybackEvent> { $0.date >= cutoff },
                sortBy: [SortDescriptor(\PlaybackEvent.date, order: .reverse)]
            )
            events = (try? modelContext.fetch(descriptor)) ?? []
        }
    }

    // MARK: - Derived stats

    private var lookbackCutoff: Date {
        Calendar.current.date(byAdding: .day, value: -lookbackDays, to: .now) ?? .distantPast
    }

    private var recentEvents: [PlaybackEvent] { events }

    private var totalMinutesListened: Int {
        // Approximate minutes from the highest position observed per episode
        // in the window — avoids double-counting starts/seeks.
        var maxByEpisode: [UUID: TimeInterval] = [:]
        for event in recentEvents {
            guard let episodeID = event.episode?.id else { continue }
            let current = maxByEpisode[episodeID] ?? 0
            maxByEpisode[episodeID] = max(current, event.position)
        }
        let totalSeconds = maxByEpisode.values.reduce(0, +)
        return Int(totalSeconds / 60)
    }

    private var completionCount: Int {
        recentEvents.filter { $0.kind == .completed }.count
    }

    private var startedCount: Int {
        recentEvents.filter { $0.kind == .started || $0.kind == .resumed }.count
    }

    private var dailyMinutes: [(Date, Int)] {
        let cal = Calendar.current
        var bucket: [Date: TimeInterval] = [:]
        var maxByEpisodeAndDay: [String: TimeInterval] = [:]

        for event in recentEvents {
            guard let episodeID = event.episode?.id else { continue }
            let day = cal.startOfDay(for: event.date)
            let key = "\(day.timeIntervalSinceReferenceDate)|\(episodeID)"
            let current = maxByEpisodeAndDay[key] ?? 0
            if event.position > current {
                let delta = event.position - current
                maxByEpisodeAndDay[key] = event.position
                bucket[day, default: 0] += delta
            }
        }

        return (0..<lookbackDays).reversed().map { offset -> (Date, Int) in
            let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: .now)) ?? .now
            let minutes = Int((bucket[day] ?? 0) / 60)
            return (day, minutes)
        }
    }

    private var topShows: [(Podcast, Int)] {
        var counts: [UUID: Int] = [:]
        for event in recentEvents {
            guard let podcastID = event.episode?.podcast.id else { continue }
            counts[podcastID, default: 0] += 1
        }
        return counts
            .compactMap { id, count -> (Podcast, Int)? in
                guard let podcast = podcasts.first(where: { $0.id == id }) else { return nil }
                return (podcast, count)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { $0 }
    }

    private var topTopics: [(String, Int)] {
        var counts: [String: Int] = [:]
        for event in recentEvents {
            guard let tags = event.episode?.profile?.tags else { continue }
            for tag in tags {
                let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard normalized.count > 2 else { continue }
                counts[normalized, default: 0] += 1
            }
        }
        return counts
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { ($0.key, $0.value) }
    }

    private var abandonedShows: [Podcast] {
        let abandonedEvents = recentEvents.filter { $0.kind == .abandoned }
        var ids: [UUID] = []
        for event in abandonedEvents {
            if let podcastID = event.episode?.podcast.id, !ids.contains(podcastID) {
                ids.append(podcastID)
            }
        }
        return ids.compactMap { id in podcasts.first(where: { $0.id == id }) }.prefix(3).map { $0 }
    }

    // MARK: - Editorial copy

    private var greeting: String {
        if totalMinutesListened >= 600 { return "A serious listening month." }
        if totalMinutesListened >= 200 { return "You stayed in the rotation." }
        if totalMinutesListened >= 60 { return "A steady listen." }
        if totalMinutesListened > 0 { return "A quiet stretch." }
        return "Nothing logged yet."
    }

    private var subtitleLine: String {
        if totalMinutesListened == 0 {
            return "Once you play a few episodes, OffScript starts mapping what you actually listen to."
        }
        let hours = totalMinutesListened / 60
        let minutes = totalMinutesListened % 60
        let totalLabel: String
        if hours > 0 {
            totalLabel = minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else {
            totalLabel = "\(minutes)m"
        }
        return "\(totalLabel) of audio across \(startedCount) sessions, \(completionCount) finished."
    }

    // MARK: - Subviews

    private var statSummary: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)],
            alignment: .leading,
            spacing: 12
        ) {
            insightCard(label: "Minutes", value: "\(totalMinutesListened)")
            insightCard(label: "Finished", value: "\(completionCount)")
            insightCard(label: "Sessions", value: "\(startedCount)")
            insightCard(label: "Top topics", value: "\(topTopics.count)")
        }
    }

    private func insightCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .serif, weight: .bold))
                .foregroundStyle(Color.offscriptTextPrimary)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.offscriptMicro.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Color.offscriptTextMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offscriptUtilitySurface()
    }

    private var dailyChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily minutes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.offscriptTextSecondary)

            Chart {
                ForEach(dailyMinutes, id: \.0) { day, minutes in
                    BarMark(
                        x: .value("Day", day, unit: .day),
                        y: .value("Minutes", minutes)
                    )
                    .foregroundStyle(Color.offscriptAccent.gradient)
                    .cornerRadius(2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel().foregroundStyle(Color.offscriptTextMuted)
                    AxisGridLine().foregroundStyle(Color.offscriptHairline)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel(date.formatted(.dateTime.day().month(.abbreviated)))
                            .foregroundStyle(Color.offscriptTextMuted)
                    }
                    AxisTick().foregroundStyle(Color.offscriptHairline)
                }
            }
            .frame(height: 160)
        }
        .padding(16)
        .offscriptUtilitySurface()
    }

    private var topShowsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            OffScriptSectionHeader(title: "Most-played shows", subtitle: "Where most of your minutes went.")
                .padding(.horizontal, OffScriptTheme.pagePadding)

            VStack(spacing: 10) {
                ForEach(Array(topShows.enumerated()), id: \.element.0.id) { index, pair in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.offscriptTextMuted)
                            .frame(width: 22, alignment: .leading)
                        OffScriptArtworkView(
                            url: pair.0.artworkURL,
                            cornerRadius: OffScriptTheme.Radius.small
                        )
                        .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pair.0.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.offscriptTextPrimary)
                                .lineLimit(1)
                            Text("\(pair.1) sessions")
                                .font(.offscriptMeta)
                                .foregroundStyle(Color.offscriptTextMuted)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.offscriptCard, in: RoundedRectangle(cornerRadius: OffScriptTheme.Radius.small, style: .continuous))
                }
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)
        }
    }

    private var topTopicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            OffScriptSectionHeader(title: "Topics you keep returning to", subtitle: "Pulled from on-device topic extraction.")
                .padding(.horizontal, OffScriptTheme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(topTopics, id: \.0) { tag, count in
                        HStack(spacing: 6) {
                            Text(tag)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.offscriptTextPrimary)
                            Text("\(count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color.offscriptTextMuted)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.offscriptAccentSecondaryMuted, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.offscriptAccentSecondary.opacity(0.18), lineWidth: 0.5)
                        )
                    }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)
            }
        }
    }

    private var abandonedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            OffScriptSectionHeader(
                title: "Stalled out",
                subtitle: "Shows you've abandoned more than once. Consider trimming."
            )
            .padding(.horizontal, OffScriptTheme.pagePadding)

            VStack(spacing: 10) {
                ForEach(abandonedShows) { podcast in
                    HStack(spacing: 12) {
                        OffScriptArtworkView(
                            url: podcast.artworkURL,
                            cornerRadius: OffScriptTheme.Radius.small
                        )
                        .frame(width: 36, height: 36)
                        Text(podcast.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.offscriptTextPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.offscriptCard, in: RoundedRectangle(cornerRadius: OffScriptTheme.Radius.small, style: .continuous))
                }
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)
        }
    }
}

import SwiftData
import SwiftUI

struct QueueView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var queueItems: [QueueItem]
    @State private var sessionPickerPresented = false
    @State private var sessionPlan: TimeSlotPlaylistService.Plan?
    @State private var isBuildingSession = false

    /// Cached sorted snapshot — recomputed only when @Query fires, not on
    /// every body evaluation. Avoids a full sort per render even when nothing
    /// changed.
    @State private var orderedItems: [QueueItem] = []

    private func recomputeOrdered() {
        orderedItems = queueItems.sorted { lhs, rhs in
            if lhs.position == rhs.position {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.position < rhs.position
        }
    }

    private var queueTotalDuration: String? {
        let total = orderedItems.compactMap { $0.episode.duration }.reduce(0, +)
        guard total > 0 else { return nil }
        return EpisodeDurationFormatter.short(total)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                QueueHeader(count: orderedItems.count)

                TimeSlotSessionCard(isBuilding: isBuildingSession) { minutes in
                    Task { await buildSession(minutes: minutes) }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)

                if orderedItems.isEmpty {
                    VStack(spacing: 20) {
                        OffScriptEmptyState(
                            icon: "text.badge.plus",
                            headline: "Nothing queued yet",
                            message: "Your queue is a working set, not a backlog. Add a few episodes you actually plan to hear next.",
                            generatedCopyKey: "queue.empty",
                            generatedCopyPrompt: "Surface: empty Queue tab in a curated podcast app. Write a two-sentence editorial nudge that frames the queue as a curated working set."
                        )

                        NavigationLink("Browse Home") {
                            HomeView(onOpenSettings: {})
                        }
                        .buttonStyle(PrimaryPillButtonStyle())
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                    .padding(.top, 24)
                } else {
                    if let first = orderedItems.first {
                        QueueLeadCard(item: first)
                            .padding(.horizontal, OffScriptTheme.spaciousPadding)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            OffScriptSectionHeader(
                                title: "Stack",
                                subtitle: "Hold to reorder. Tap ✕ to remove."
                            )

                            Spacer()

                            if orderedItems.count > 1 {
                                Button("Clear All") {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        for item in orderedItems {
                                            try? QueueService.remove(item, in: modelContext)
                                        }
                                    }
                                }
                                .font(.offscriptMeta.weight(.semibold))
                                .foregroundStyle(Color.offscriptDestructive)
                            }
                        }
                        .padding(.horizontal, OffScriptTheme.pagePadding)

                        if let totalDuration = queueTotalDuration {
                            HStack(spacing: 8) {
                                Image(systemName: "clock")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.offscriptAccent)
                                Text("\(totalDuration) total listening time")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.offscriptTextPrimary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.offscriptAccentSoft)
                            .clipShape(Capsule())
                            .padding(.horizontal, OffScriptTheme.pagePadding)
                        }

                        ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
                            EpisodeCompactCard(
                                episode: item.episode,
                                onRemove: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        try? QueueService.remove(item, in: modelContext)
                                    }
                                },
                                rank: index + 1
                            )
                                .draggable(item.id.uuidString) {
                                    EpisodeCompactCard(
                                        episode: item.episode,
                                        rank: index + 1
                                    )
                                    .frame(width: 320)
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    guard let sourceRaw = items.first,
                                          let sourceID = UUID(uuidString: sourceRaw),
                                          let sourceIndex = orderedItems.firstIndex(where: { $0.id == sourceID }),
                                          let targetIndex = orderedItems.firstIndex(where: { $0.id == item.id }),
                                          sourceIndex != targetIndex else {
                                        return false
                                    }

                                    let destination = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        try? QueueService.move(from: IndexSet(integer: sourceIndex), to: destination, in: modelContext)
                                    }
                                    return true
                                }
                                .contextMenu {
                                    if index > 0 {
                                        Button {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                                try? QueueService.move(from: IndexSet(integer: index), to: index - 1, in: modelContext)
                                            }
                                        } label: {
                                            Label("Move Up", systemImage: "arrow.up")
                                        }
                                    }
                                    if index < orderedItems.count - 1 {
                                        Button {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                                try? QueueService.move(from: IndexSet(integer: index), to: index + 2, in: modelContext)
                                            }
                                        } label: {
                                            Label("Move Down", systemImage: "arrow.down")
                                        }
                                    }
                                    Button(role: .destructive) {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            try? QueueService.remove(item, in: modelContext)
                                        }
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                                .padding(.horizontal, OffScriptTheme.pagePadding)
                                .staggeredEntrance(index: index)
                        }
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 0)
        }
        .offscriptPageBackground()
        .navigationTitle("Queue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.offscriptBackgroundTop.opacity(0.98), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { recomputeOrdered() }
        .onChange(of: queueItems) { _, _ in recomputeOrdered() }
    }
}

private extension QueueView {
    func buildSession(minutes: Int) async {
        isBuildingSession = true
        defer { isBuildingSession = false }
        guard let plan = await TimeSlotPlaylistService.shared.buildPlan(targetMinutes: minutes, in: modelContext) else {
            return
        }
        sessionPlan = plan
        TimeSlotPlaylistService.shared.apply(plan: plan, in: modelContext, autoplay: false)
    }
}

private struct TimeSlotSessionCard: View {
    let isBuilding: Bool
    let onSelect: (Int) -> Void

    private let presets: [Int] = [15, 30, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "timer")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.offscriptAccent)
                    .padding(10)
                    .background(Color.offscriptAccentSoft, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("How much time have you got?")
                        .font(.offscriptCardTitle)
                        .foregroundStyle(Color.offscriptTextPrimary)
                    Text("OffScript builds a queue that fits — finishing what you started, then layering in the best next picks.")
                        .font(.offscriptMeta)
                        .foregroundStyle(Color.offscriptTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            if isBuilding {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Color.offscriptAccent)
                    Text("Composing your session…")
                        .font(.offscriptMeta)
                        .foregroundStyle(Color.offscriptTextMuted)
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { minutes in
                        Button {
                            onSelect(minutes)
                        } label: {
                            Text("\(minutes)m")
                                .font(.system(.subheadline, design: .default, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.offscriptTextPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule().fill(.clear).offscriptGlass(in: Capsule())
                                )
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.impact(flexibility: .soft), trigger: minutes)
                    }
                }
            }
        }
        .padding(18)
        .offscriptUtilitySurface()
    }
}

private struct QueueHeader: View {
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OffScriptUtilityHeader(
                eyebrow: "Stack",
                title: "Queue with intent",
                subtitle: "Your working set — what plays next, what can wait, what deserves the top slot."
            )

            TTagPill(label: "\(count) QUEUED", tone: .neutral)
        }
        .padding(.horizontal, OffScriptTheme.pagePadding)
    }
}

private struct QueueLeadCard: View {
    @Environment(\.modelContext) private var modelContext
    let item: QueueItem

    /// Tuner queue lead — flat black panel with hairline border, square
    /// hairline-bordered artwork, mono uppercase NEXT UP eyebrow, single
    /// signal-yellow PLAY FROM TOP CTA + outlined REMOVE.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    TTagPill(label: "NEXT UP", tone: .signal)

                    Text(item.episode.title)
                        .font(.offscriptDisplay)
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.episode.podcast.title.uppercased())
                        .font(.offscriptTagLabel)
                        .tracking(1.4)
                        .foregroundStyle(Color.offscriptAccentSecondary)
                        .lineLimit(1)

                    if let duration = item.episode.duration {
                        Text(EpisodeDurationFormatter.short(duration).uppercased())
                            .font(.offscriptMeta)
                            .tracking(1.0)
                            .foregroundStyle(Color.offscriptTextMuted)
                    }
                }

                Spacer(minLength: 0)

                OffScriptArtworkView(
                    url: item.episode.artworkURL ?? item.episode.podcast.artworkURL,
                    cornerRadius: 4
                )
                .frame(width: 88, height: 88)
                .overlay(
                    Rectangle().stroke(Color.offscriptHairline, lineWidth: 0.5)
                )
            }

            HStack(spacing: 8) {
                Button("Play from Top") {
                    PlaybackController.shared.play(item.episode, in: modelContext)
                }
                .buttonStyle(PrimaryPillButtonStyle())
                .sensoryFeedback(.impact(flexibility: .soft), trigger: item.episode.id)

                Button("Remove") {
                    try? QueueService.remove(item, in: modelContext)
                }
                .buttonStyle(SecondaryPillButtonStyle())
            }
        }
        .padding(16)
        .background(Color.offscriptCard)
        .overlay(
            Rectangle().stroke(Color.offscriptHairline, lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Next up: \(item.episode.title) from \(item.episode.podcast.title)")
    }
}


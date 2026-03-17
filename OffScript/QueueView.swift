import SwiftData
import SwiftUI

struct QueueView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var queueItems: [QueueItem]

    private var orderedItems: [QueueItem] {
        queueItems.sorted { lhs, rhs in
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

                if orderedItems.isEmpty {
                    VStack(spacing: 20) {
                        OffScriptEmptyState(
                            icon: "text.badge.plus",
                            headline: "Nothing queued yet",
                            message: "Your queue is a working set, not a backlog. Add a few episodes you actually plan to hear next."
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
                            Text("Total: \(totalDuration)")
                                .font(.offscriptMeta)
                                .foregroundStyle(Color.offscriptTextMuted)
                                .padding(.horizontal, OffScriptTheme.pagePadding)
                        }

                        ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
                            QueueItemCard(item: item, rank: index + 1, onRemove: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    try? QueueService.remove(item, in: modelContext)
                                }
                            })
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
            .padding(.bottom, 90)
        }
        .offscriptPageBackground()
        .navigationTitle("Queue")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct QueueHeader: View {
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OffScriptUtilityHeader(
                eyebrow: "Queue",
                title: "Queue with intent",
                subtitle: "This is your working set: what plays next, what can wait, and what deserves the top slot right now."
            )

            OffScriptReasonBadge(text: "\(count) queued")
        }
        .padding(.horizontal, OffScriptTheme.pagePadding)
    }
}

private struct QueueLeadCard: View {
    @Environment(\.modelContext) private var modelContext
    let item: QueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    OffScriptReasonBadge(text: "Next Up")

                    Text(item.episode.title)
                        .font(.offscriptDisplay)
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.episode.podcast.title)
                        .font(.headline)
                        .foregroundStyle(Color.offscriptTextSecondary)

                    if let duration = item.episode.duration {
                        Text(EpisodeDurationFormatter.short(duration))
                            .font(.offscriptMeta)
                            .foregroundStyle(Color.offscriptTextMuted)
                    }
                }

                Spacer(minLength: 0)

                OffScriptArtworkView(url: item.episode.artworkURL ?? item.episode.podcast.artworkURL, cornerRadius: OffScriptTheme.Radius.large)
                    .frame(width: 96, height: 96)
            }

            HStack(spacing: 10) {
                Button("Play from Top") {
                    PlaybackController.shared.play(item.episode, in: modelContext)
                }
                .buttonStyle(PrimaryPillButtonStyle())
                .sensoryFeedback(.impact(flexibility: .soft), trigger: item.episode.id)

                Button("Remove") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        try? QueueService.remove(item, in: modelContext)
                    }
                }
                .buttonStyle(SecondaryPillButtonStyle())
            }
        }
        .padding(22)
        .offscriptSurface(radius: OffScriptTheme.Radius.large, prominent: true)
    }
}

private struct QueueItemCard: View {
    @Environment(\.modelContext) private var modelContext

    let item: QueueItem
    let rank: Int
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.offscriptTextPrimary)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Color.offscriptHairline, lineWidth: 1)
                )

            OffScriptArtworkView(url: item.episode.artworkURL ?? item.episode.podcast.artworkURL, cornerRadius: OffScriptTheme.Radius.small)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.episode.title)
                    .font(.headline)
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .lineLimit(2)

                Text(item.episode.podcast.title)
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextSecondary)
                    .lineLimit(1)

                if let duration = item.episode.duration {
                    Text(EpisodeDurationFormatter.short(duration))
                        .font(.offscriptMeta)
                        .foregroundStyle(Color.offscriptTextMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                PlaybackController.shared.play(item.episode, in: modelContext)
            } label: {
                Image(systemName: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(Color.offscriptAccent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(item.episode.title)")

            if let onRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.offscriptTextMuted)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(item.episode.title) from queue")
            }
        }
        .padding(16)
        .offscriptUtilitySurface()
    }
}

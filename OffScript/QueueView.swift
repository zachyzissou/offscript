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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                QueueHeader(count: orderedItems.count)

                if orderedItems.isEmpty {
                    VStack(spacing: 20) {
                        ContentUnavailableView("Queue is empty", systemImage: "text.badge.plus", description: Text("Save episodes from Home or Library and they'll stack up here in the order you actually want to hear them."))

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
                            .padding(.horizontal, OffScriptTheme.pagePadding)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        OffScriptSectionHeader(
                            title: "Stack",
                            subtitle: "Drag to reorder, swipe to remove."
                        )
                        .padding(.horizontal, OffScriptTheme.pagePadding)

                        ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
                            QueueItemCard(item: item, rank: index + 1)
                                .contextMenu {
                                    if index > 0 {
                                        Button {
                                            withAnimation {
                                                try? QueueService.move(from: IndexSet(integer: index), to: index - 1, in: modelContext)
                                            }
                                        } label: {
                                            Label("Move Up", systemImage: "arrow.up")
                                        }
                                    }
                                    if index < orderedItems.count - 1 {
                                        Button {
                                            withAnimation {
                                                try? QueueService.move(from: IndexSet(integer: index), to: index + 2, in: modelContext)
                                            }
                                        } label: {
                                            Label("Move Down", systemImage: "arrow.down")
                                        }
                                    }
                                    Button(role: .destructive) {
                                        withAnimation {
                                            try? QueueService.remove(item, in: modelContext)
                                        }
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                                .padding(.horizontal, OffScriptTheme.pagePadding)
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

                Button("Remove") {
                    try? QueueService.remove(item, in: modelContext)
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

    var body: some View {
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.offscriptAccent)
                .frame(width: 34, height: 34)
                .background(Color.offscriptAccentSoft)
                .clipShape(Circle())

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
        }
        .padding(16)
        .offscriptUtilitySurface()
    }
}

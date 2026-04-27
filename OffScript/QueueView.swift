import OSLog
import SwiftData
import SwiftUI

private let queueLogger = Logger(subsystem: "com.offscript", category: "Queue")

// MARK: - QueueView (Tuner working set)

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
            VStack(alignment: .leading, spacing: 16) {
                QueueTunerHeader(
                    count: orderedItems.count,
                    totalDuration: queueTotalDuration
                )

                if orderedItems.isEmpty {
                    emptyState
                } else {
                    if let first = orderedItems.first {
                        QueueLeadStrip(item: first)
                    }

                    queueListSection
                }
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 90)
        }
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.offscriptStudioBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            TunerLabel(text: "● QUEUE EMPTY", color: .offscriptSoftPaper)
            Text("Nothing queued yet")
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(Color.offscriptPaperWhite)
            Text("This is your working set, not a backlog. Queue a few episodes you actually plan to hear next.")
                .font(.system(size: 13.5))
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineSpacing(2)

            NavigationLink {
                SearchView()
            } label: {
                HStack {
                    TunerLabel(text: "→ EXPLORE SHOWS", color: .offscriptSignalYellow, size: 11)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.top, 16)
    }

    private var queueListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
            HStack {
                TunerLabel(text: "STACK · TAP × TO REMOVE", color: .offscriptSignalYellow)
                Spacer()
                if orderedItems.count > 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            for item in orderedItems {
                                do { try QueueService.remove(item, in: modelContext) }
                                catch { queueLogger.error("Failed to remove queue item: \(error.localizedDescription, privacy: .public)") }
                            }
                        }
                    } label: {
                        TunerLabel(text: "× CLEAR ALL", color: .offscriptFnRecord, size: 9)
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVStack(spacing: 0) {
                ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
                    QueueItemRow(
                        item: item,
                        rank: index + 1,
                        onRemove: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                do { try QueueService.remove(item, in: modelContext) }
                                catch { queueLogger.error("Failed to remove queue item: \(error.localizedDescription, privacy: .public)") }
                            }
                        }
                    )
                    .contextMenu {
                        if index > 0 {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    do { try QueueService.move(from: IndexSet(integer: index), to: index - 1, in: modelContext) }
                                    catch { queueLogger.error("Failed to move queue item: \(error.localizedDescription, privacy: .public)") }
                                }
                            } label: {
                                Label("Move Up", systemImage: "arrow.up")
                            }
                        }
                        if index < orderedItems.count - 1 {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    do { try QueueService.move(from: IndexSet(integer: index), to: index + 2, in: modelContext) }
                                    catch { queueLogger.error("Failed to move queue item: \(error.localizedDescription, privacy: .public)") }
                                }
                            } label: {
                                Label("Move Down", systemImage: "arrow.down")
                            }
                        }
                        Button(role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                do { try QueueService.remove(item, in: modelContext) }
                                catch { queueLogger.error("Failed to remove queue item: \(error.localizedDescription, privacy: .public)") }
                            }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    if index < orderedItems.count - 1 {
                        Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Header

private struct QueueTunerHeader: View {
    let count: Int
    let totalDuration: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TunerLabel(text: "QUEUE · WORKING SET", color: .offscriptSignalYellow)
                Spacer()
                TunerLabel(text: "\(count) STACKED", color: .offscriptFnInfo)
            }

            Text("Queue")
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Color.offscriptPaperWhite)

            if let totalDuration {
                TunerLabel(text: "TOTAL  \(totalDuration.uppercased())", color: .offscriptSoftPaper)
                    .padding(.top, 2)
            }

            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                .padding(.top, 6)
        }
    }
}

// MARK: - Lead strip

private struct QueueLeadStrip: View {
    @Environment(\.modelContext) private var modelContext
    let item: QueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TunerLabel(text: "● NEXT UP", color: .offscriptSignalYellow)
                Spacer()
                if let dur = item.episode.duration {
                    TunerLabel(text: EpisodeDurationFormatter.short(dur).uppercased(), color: .offscriptSoftPaper)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                OffScriptArtworkView(
                    url: item.episode.artworkURL ?? item.episode.podcast.artworkURL,
                    cornerRadius: 3
                )
                .frame(width: 88, height: 88)
                .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

                VStack(alignment: .leading, spacing: 6) {
                    // Podcast title uses Info cyan per the function-coded color
                    // system. Record red is reserved for destructive / error
                    // signals (× CLEAR ALL, × REMOVE) and was misapplied here.
                    TunerLabel(text: item.episode.podcast.title.uppercased(),
                               color: .offscriptFnInfo, size: 9)
                        .lineLimit(1)
                    Text(item.episode.title)
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .lineLimit(3)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    PlaybackController.shared.play(item.episode, in: modelContext)
                } label: {
                    TunerLabel(text: "→ PLAY", color: .offscriptSignalYellow, size: 11)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        do { try QueueService.remove(item, in: modelContext) }
                        catch { queueLogger.error("Failed to remove queue item: \(error.localizedDescription, privacy: .public)") }
                    }
                } label: {
                    TunerLabel(text: "× REMOVE", color: .offscriptFnRecord, size: 11)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(12)
        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
    }
}

// MARK: - Item row

private struct QueueItemRow: View {
    @Environment(\.modelContext) private var modelContext

    let item: QueueItem
    let rank: Int
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", rank))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.offscriptSignalYellow)
                .frame(width: 28, alignment: .leading)

            OffScriptArtworkView(
                url: item.episode.artworkURL ?? item.episode.podcast.artworkURL,
                cornerRadius: 3
            )
            .frame(width: 48, height: 48)
            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                TunerLabel(text: item.episode.podcast.title.uppercased(), color: .offscriptFnInfo, size: 8)
                    .lineLimit(1)
                Text(item.episode.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(2)
                if let duration = item.episode.duration {
                    TunerLabel(text: EpisodeDurationFormatter.short(duration).uppercased(),
                               color: .offscriptSoftPaper, size: 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                PlaybackController.shared.play(item.episode, in: modelContext)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 30)
                    .background(Color.offscriptSignalYellow)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(item.episode.title)")

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.offscriptFnRecord)
                        .frame(width: 26, height: 30)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from queue")
            }
        }
        .padding(.vertical, 10)
    }
}

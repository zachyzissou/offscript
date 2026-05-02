import OSLog
import SwiftData
import SwiftUI

private let queueLogger = Logger(subsystem: "com.offscript", category: "Queue")

// MARK: - QueueView (Tuner working set)

struct QueueView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var queueItems: [QueueItem]
    /// Used by the empty state to pick the right escape hatch — if the
    /// user already has shows tuned, the right next move is BROWSE
    /// LIBRARY (find an episode to queue), not EXPLORE SHOWS (which
    /// would push them back to Search even though their library is
    /// already populated).
    @Query(filter: #Predicate<Podcast> { $0.isSubscribed }) private var subscribedPodcasts: [Podcast]
    /// `× CLEAR ALL` is irreversible and operates on the entire working
    /// set — under a heavy listener's queue (10+ items) the silent wipe
    /// is the wrong default. Drop into a confirm strip first; tap
    /// `× CONFIRM` to commit, or CANCEL to back out.
    @State private var isConfirmingClearAll = false

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
            .padding(.top, OffScriptTheme.rootContentTopPadding)
            .padding(.bottom, 90)
        }
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
        .accessibilityIdentifier("QueueScreen")
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(Color.offscriptStudioBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // Auto-dismiss the clear-all confirm strip when the queue
        // empties or shrinks to ≤1 via another path while the dialog
        // is open (e.g. an episode finishes playback and is removed in
        // the background). Lives on the parent so the watcher fires
        // even if `queueListSection` (which hosts the strip) is no
        // longer in the hierarchy because the queue went empty.
        .onChange(of: orderedItems.count) { _, newCount in
            if newCount <= 1 && isConfirmingClearAll {
                isConfirmingClearAll = false
            }
        }
    }

    private var emptyState: some View {
        let hasSubscriptions = !subscribedPodcasts.isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            TunerLabel(text: "● QUEUE EMPTY", color: .offscriptSoftPaper)
            Text("Nothing queued yet")
                .font(.system(size: 22, weight: .semibold))
                .tracking(0)
                .foregroundStyle(Color.offscriptPaperWhite)
            Text(hasSubscriptions
                 ? "This is your working set, not a backlog. Queue a few episodes from Library or Home that you actually plan to hear next."
                 : "This is your working set, not a backlog. Find shows you trust first, then queue episodes you actually plan to hear next.")
                .font(.system(size: 13.5))
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineSpacing(2)

            // Context-aware escape hatch — a user with subscriptions
            // wants Library (find an episode to queue), not Search
            // (which they'd already used to get those subscriptions).
            // First-launch users with zero subscriptions still get
            // EXPLORE SHOWS because Library is empty for them.
            if hasSubscriptions {
                Button {
                    NotificationCenter.default.post(
                        name: .offscriptSwitchTab,
                        object: nil,
                        userInfo: ["tab": "library"]
                    )
                } label: {
                    HStack {
                        TunerLabel(text: "→ BROWSE LIBRARY", color: .offscriptSignalYellow, size: 11)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Browse library to find episodes to queue")
                .accessibilityIdentifier("QueueEmptyBrowseLibrary")
                .padding(.top, 4)
            } else {
                NavigationLink {
                    SearchView(hidesRootNavigationBar: false)
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
                        withAnimation(.easeOut(duration: 0.18)) {
                            isConfirmingClearAll = true
                        }
                    } label: {
                        TunerLabel(text: "× CLEAR ALL", color: .offscriptFnRecord, size: 9)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isConfirmingClearAll)
                    .accessibilityLabel("Clear all \(orderedItems.count) queued episodes")
                    .accessibilityHint("Asks for confirmation before clearing the queue")
                    .accessibilityIdentifier("QueueClearAll")
                }
            }

            if isConfirmingClearAll {
                clearAllConfirmStrip
            }

            LazyVStack(spacing: 0) {
                ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
                    QueueItemRow(
                        item: item,
                        rank: index + 1,
                        canMoveUp: index > 0,
                        canMoveDown: index < orderedItems.count - 1,
                        onMoveUp: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                do { try QueueService.move(from: IndexSet(integer: index), to: index - 1, in: modelContext) }
                                catch { queueLogger.error("Failed to move queue item: \(error.localizedDescription, privacy: .public)") }
                            }
                        },
                        onMoveDown: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                do { try QueueService.move(from: IndexSet(integer: index), to: index + 2, in: modelContext) }
                                catch { queueLogger.error("Failed to move queue item: \(error.localizedDescription, privacy: .public)") }
                            }
                        },
                        onRemove: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                do { try QueueService.remove(item, in: modelContext) }
                                catch { queueLogger.error("Failed to remove queue item: \(error.localizedDescription, privacy: .public)") }
                            }
                        }
                    )
                    if index < orderedItems.count - 1 {
                        Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    /// Tuner-styled inline confirm — keeps the destructive bulk-clear
    /// inside the Queue surface instead of bouncing through a system
    /// `.alert` that would render in non-Tuner chrome. Hairline strip,
    /// `● CONFIRM CLEAR` eyebrow in `offscriptFnRecord`, two equal-width
    /// CANCEL / CONFIRM keys at 44pt min-height. Closes part of #126
    /// (large queue states) — silent bulk-wipe was the wrong default
    /// once a heavy listener has 10+ items stacked.
    private var clearAllConfirmStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            TunerLabel(text: "● CONFIRM CLEAR", color: .offscriptFnRecord)
            Text("Clear all \(orderedItems.count) queued episodes? This can't be undone.")
                .font(.system(size: 13))
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineSpacing(2)

            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isConfirmingClearAll = false
                    }
                } label: {
                    TunerLabel(text: "CANCEL", color: .offscriptPaperWhite, size: 11)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel clear all queued episodes")
                .accessibilityIdentifier("QueueClearAllCancel")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        do {
                            try QueueService.clearAll(in: modelContext)
                        } catch {
                            queueLogger.error("Failed to clear queue: \(error.localizedDescription, privacy: .public)")
                        }
                        isConfirmingClearAll = false
                    }
                } label: {
                    TunerLabel(text: "× CONFIRM", color: .offscriptFnRecord, size: 11)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Confirm clear all \(orderedItems.count) queued episodes")
                .accessibilityIdentifier("QueueClearAllConfirm")
            }
        }
        .padding(12)
        .overlay(Rectangle().stroke(Color.offscriptFnRecord.opacity(0.6), lineWidth: 1))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Header

private struct QueueTunerHeader: View {
    let count: Int
    let totalDuration: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Both eyebrows lock to one line so larger Dynamic Type
                // sizes don't wrap one onto the next and overlap the
                // "Queue" headline below.
                TunerLabel(text: "QUEUE · WORKING SET", color: .offscriptSignalYellow)
                    .lineLimit(1)
                Spacer()
                TunerLabel(text: "\(count) STACKED", color: .offscriptFnInfo)
                    .lineLimit(1)
            }

            Text("Queue")
                .font(.system(size: 32, weight: .bold))
                .tracking(0)
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

// QueueLeadStrip's PLAY/RESUME + × REMOVE keys meet 44pt min-height
// per HIG; matches the rest of the app's Tuner action-key vocabulary.
private struct QueueLeadStrip: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var player = PlaybackController.shared
    let item: QueueItem

    private var isCurrentlyPlaying: Bool {
        player.currentEpisode?.id == item.episode.id
    }

    private var hasResumePosition: Bool {
        item.episode.playedPosition > 0 && !item.episode.isPlayed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Group {
                    if isCurrentlyPlaying {
                        TunerLabel(text: "● NOW PLAYING", color: .offscriptFnMode)
                    } else if hasResumePosition {
                        TunerLabel(text: "● NEXT UP · IN PROGRESS", color: .offscriptSignalYellow)
                    } else {
                        TunerLabel(text: "● NEXT UP", color: .offscriptSignalYellow)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    isCurrentlyPlaying
                        ? "Now playing \(item.episode.title)"
                        : (hasResumePosition
                            ? "Next up, in progress: \(item.episode.title)"
                            : "Next up: \(item.episode.title)")
                )
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
                        .tracking(0)
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .lineLimit(3)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    let episode = item.episode
                    do {
                        try QueueService.remove(item, in: modelContext)
                        PlaybackController.shared.play(episode, in: modelContext)
                    } catch {
                        queueLogger.error("Failed to start queued episode: \(error.localizedDescription, privacy: .public)")
                    }
                } label: {
                    TunerLabel(
                        text: isCurrentlyPlaying ? "● PLAYING" : (hasResumePosition ? "→ RESUME" : "→ PLAY"),
                        color: isCurrentlyPlaying ? .offscriptFnMode : .offscriptSignalYellow,
                        size: 11
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .overlay(Rectangle().stroke(isCurrentlyPlaying ? Color.offscriptFnMode : Color.offscriptSignalYellow, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isCurrentlyPlaying)
                .accessibilityLabel(
                    isCurrentlyPlaying
                        ? "Currently playing"
                        : (hasResumePosition ? "Resume \(item.episode.title)" : "Play \(item.episode.title)")
                )
                .accessibilityHint(
                    isCurrentlyPlaying
                        ? "This episode is already playing."
                        : (hasResumePosition
                            ? "Resumes playback from your saved position."
                            : "Starts playback from the beginning.")
                )

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        do { try QueueService.remove(item, in: modelContext) }
                        catch { queueLogger.error("Failed to remove queue item: \(error.localizedDescription, privacy: .public)") }
                    }
                } label: {
                    TunerLabel(text: "× REMOVE", color: .offscriptFnRecord, size: 11)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(item.episode.title) from queue")

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
    var canMoveUp = false
    var canMoveDown = false
    var onMoveUp: (() -> Void)? = nil
    var onMoveDown: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Tap-to-detail zone — rank + artwork + title/metadata.
            // The action buttons (play / move / remove) are siblings
            // outside the NavigationLink so they don't trigger the
            // detail push when tapped. Matches the
            // PodcastEpisodeTunerRow pattern.
            NavigationLink {
                EpisodeDetailView(episode: item.episode)
            } label: {
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
                            .multilineTextAlignment(.leading)
                        if let duration = item.episode.duration {
                            TunerLabel(text: EpisodeDurationFormatter.short(duration).uppercased(),
                                       color: .offscriptSoftPaper, size: 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(item.episode.title) from \(item.episode.podcast.title) detail")

            Button {
                PlaybackController.shared.play(item.episode, in: modelContext)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.offscriptStudioBlack)
                    .frame(width: 30, height: 30)
                    .background(Color.offscriptSignalYellow)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(item.episode.title)")

            queueIconButton(systemName: "chevron.up", color: .offscriptSoftPaper, disabled: !canMoveUp, action: onMoveUp)
                .accessibilityLabel("Move \(item.episode.title) up in queue")
            queueIconButton(systemName: "chevron.down", color: .offscriptSoftPaper, disabled: !canMoveDown, action: onMoveDown)
                .accessibilityLabel("Move \(item.episode.title) down in queue")

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.offscriptFnRecord)
                        .frame(width: 26, height: 30)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(item.episode.title) from queue")
            }
        }
        .padding(.vertical, 10)
    }

    private func queueIconButton(
        systemName: String,
        color: Color,
        disabled: Bool,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color.opacity(disabled ? 0.35 : 1))
                .frame(width: 24, height: 28)
                .overlay(Rectangle().stroke(Color.offscriptHairline.opacity(disabled ? 0.35 : 1), lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(disabled)
        .buttonStyle(.plain)
    }
}

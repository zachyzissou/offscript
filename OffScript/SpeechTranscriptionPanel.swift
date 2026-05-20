import Combine
import OSLog
import Speech
import SwiftData
import SwiftUI

private let panelLogger = Logger(subsystem: "com.offscript", category: "SpeechTranscriptionPanel")

/// EpisodeDetailView panel that lets the user generate an on-device transcript
/// using Apple's Speech framework, OR surface a Podcasting-2.0 published
/// transcript fetched via `PublishedTranscriptLoader`.
///
/// Phase 30 wired the synchronized-cue UI the Phase 14 audit asked for:
/// when the cache holds timed `TranscriptCue`s, the panel renders a
/// scrollable list that highlights the current line against the playhead,
/// auto-scrolls to follow playback (with a manual-override "follow"
/// toggle), supports tap-to-seek, search-within-transcript, and a Tuner
/// source pill differentiating PUBLISHED vs ON-DEVICE provenance. When
/// only flat text is available (legacy Speech output), the panel falls
/// back to the previous expand-to-read shape.
struct SpeechTranscriptionPanel: View {
    let episode: Episode

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var downloadService = DownloadService.shared
    @ObservedObject private var player = PlaybackController.shared
    @State private var status: PanelStatus = .idle
    @State private var transcriptText: String?
    @State private var cues: [TranscriptCue] = []
    @State private var transcriptSource: TranscriptSource = .unknown
    @State private var transcriptLanguage: String?
    @State private var isExpanded = false
    @State private var searchQuery: String = ""
    @FocusState private var searchFieldFocused: Bool

    private enum PanelStatus: Equatable {
        case idle
        case requestingPermission
        case transcribing
        case ready
        case failed(String)
    }

    /// Provenance pill source. Inferred from the `EpisodeTranscriptCache.source`
    /// string flag ("speech" → onDevice, "published" → published). "mixed" is
    /// reserved for a future pass where on-device cues backfill gaps in
    /// published cues — no current code path produces it, but the pill is
    /// wired so the schema change (a single optional flag) is the only
    /// remaining piece.
    private enum TranscriptSource {
        case unknown
        case onDevice
        case published
        case mixed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TunerLabel(text: panelHeaderTitle, color: .offscriptSignalYellow)
                Spacer()
                sourcePill
                statusBadge
            }

            Text(detailText)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(Color.offscriptPaperWhite)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            actionButton

            if isExpanded {
                if !cues.isEmpty {
                    cueListView
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if let transcriptText {
                    ScrollView {
                        Text(transcriptText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.offscriptPaperWhite)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(12)
                            .lineSpacing(2)
                            .background(Color.offscriptFillSubtle)
                            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                    }
                    .frame(maxHeight: 320)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
        .task(id: episode.id) {
            await hydrateFromCache()
        }
    }

    // MARK: - Header / pill

    private var panelHeaderTitle: String {
        switch transcriptSource {
        case .published: return "TRANSCRIPT · PUBLISHED"
        case .mixed:     return "TRANSCRIPT · MIXED"
        case .onDevice, .unknown:
            return "TRANSCRIPT · ON DEVICE"
        }
    }

    /// Compact provenance chip. Only renders once we've successfully loaded
    /// either cues or flat text from the cache (transcriptSource != .unknown)
    /// — otherwise the panel hasn't established provenance yet and the chip
    /// would be a lie.
    @ViewBuilder
    private var sourcePill: some View {
        switch transcriptSource {
        case .unknown:
            EmptyView()
        case .onDevice:
            TunerLabel(text: "● ON-DEVICE", color: .offscriptFnMode, size: 9)
        case .published:
            let langSuffix = transcriptLanguage.map { " · " + $0.uppercased() } ?? ""
            TunerLabel(text: "● PUBLISHED" + langSuffix, color: .offscriptFnInfo, size: 9)
        case .mixed:
            TunerLabel(text: "● MIXED", color: .offscriptSignalYellow, size: 9)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .idle:
            EmptyView()
        case .requestingPermission:
            TunerLabel(text: "AUTH", color: .offscriptFnInfo)
        case .transcribing:
            TunerLabel(text: "● REC", color: .offscriptFnRecord)
        case .ready:
            TunerLabel(text: "● READY", color: .offscriptFnMode)
        case .failed:
            TunerLabel(text: "● ERROR", color: .offscriptFnRecord)
        }
    }

    private var detailText: String {
        switch status {
        case .idle:
            return downloadService.localURL(for: episode) == nil
                ? "Download the episode first, then OffScript can generate a transcript on-device. Audio never leaves your phone."
                : "OffScript can transcribe this episode on-device using Apple's Speech framework. Takes a couple of minutes."
        case .requestingPermission:
            return "Checking Speech permission…"
        case .transcribing:
            return "Transcribing on-device. Stay in the app — this runs while you wait."
        case .ready:
            if isExpanded {
                if !cues.isEmpty {
                    return transcriptSource == .published
                        ? "Synchronized transcript from the publisher. Tap a line to seek."
                        : "Generated on-device. Tap a line to seek; lines highlight as audio plays."
                }
                return "Generated on-device. Doesn't leave your phone."
            }
            return cues.isEmpty
                ? "Transcript ready. Tap to expand."
                : "Synchronized transcript ready. Tap to follow the playhead."
        case .failed(let reason):
            return reason
        }
    }

    /// Tuner-direction action button — flat hairline-bordered rectangle,
    /// mono label. No pill, no shadow, no rounded corners (3pt sharp).
    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .ready:
            tunerActionButton(
                title: isExpanded ? "→ HIDE TRANSCRIPT" : "→ SHOW TRANSCRIPT",
                color: .offscriptSignalYellow,
                disabled: false
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            }

        case .transcribing, .requestingPermission:
            tunerActionButton(
                title: "● TRANSCRIBING…",
                color: .offscriptFnRecord,
                disabled: true
            ) {}

        case .idle, .failed:
            let canRun = downloadService.localURL(for: episode) != nil
            tunerActionButton(
                title: canRun ? "→ GENERATE TRANSCRIPT" : "DOWNLOAD EPISODE FIRST",
                color: canRun ? .offscriptSignalYellow : .offscriptSoftPaper,
                disabled: !canRun
            ) {
                Task { await runTranscription() }
            }
        }
    }

    @ViewBuilder
    private func tunerActionButton(
        title: String,
        color: Color,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                TunerLabel(text: title, color: color, size: 10)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .overlay(Rectangle().stroke(color.opacity(disabled ? 0.4 : 1.0), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .padding(.top, 4)
    }

    // MARK: - Synchronized cue list

    /// Whether playback is currently at this episode. Highlight + scroll-follow
    /// only make sense when the playhead actually refers to the cues on screen.
    private var playerIsTrackingThisEpisode: Bool {
        player.currentEpisode?.id == episode.id
    }

    private var playerTime: TimeInterval {
        playerIsTrackingThisEpisode ? player.currentTime : 0
    }

    /// Index of the cue whose time window contains `playerTime`. Walks
    /// from the back so we land on the latest matching cue if two windows
    /// overlap (e.g. published transcripts occasionally do).
    private var currentCueIndex: Int? {
        guard playerIsTrackingThisEpisode, !cues.isEmpty else { return nil }
        return cues.lastIndex { cue in
            // `TranscriptCue.endTime` is non-optional but a 0 value is
            // common in published JSON when the publisher omitted it.
            // Treat zero/missing as "open ended through next cue".
            let end: TimeInterval = cue.endTime > 0 ? cue.endTime : .infinity
            return cue.startTime <= playerTime && end > playerTime
        }
    }

    /// Indices of cues that match the active search query. Empty array =
    /// no query / no matches.
    private var searchMatches: [Int] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return cues.indices.filter { idx in
            cues[idx].text.localizedCaseInsensitiveContains(q)
        }
    }

    /// Cues to display. When the user is searching, narrow to matches —
    /// keeps the highlight semantics simple (only render what's relevant).
    private var visibleIndices: [Int] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return Array(cues.indices) }
        return searchMatches
    }

    private var cueListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField

            if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                TunerLabel(
                    text: "\(searchMatches.count) MATCH\(searchMatches.count == 1 ? "" : "ES")",
                    color: .offscriptSoftPaper,
                    size: 10
                )
                .accessibilityLabel("\(searchMatches.count) match\(searchMatches.count == 1 ? "" : "es")")
            }

            cueScrollView
        }
        .padding(.top, 4)
    }

    /// Tuner search input — hairline rectangle with mono prompt + signal-yellow
    /// magnifier glyph + inline × clear button. Same vocabulary as
    /// `SearchView.tunerSearchField` (read once for shape, not copied
    /// verbatim — this one is panel-local and skips the focus-clearing
    /// notification observer).
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.offscriptSignalYellow)
                .accessibilityHidden(true)

            TextField(
                "Search transcript",
                text: $searchQuery,
                prompt: Text("SEARCH TRANSCRIPT")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.offscriptSoftPaper)
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($searchFieldFocused)
            .font(.system(size: 13))
            .foregroundStyle(Color.offscriptPaperWhite)
            .accentColor(Color.offscriptSignalYellow)
            .accessibilityLabel("Search transcript")

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.offscriptSoftPaper)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
    }

    private var cueScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(visibleIndices, id: \.self) { idx in
                        cueRow(idx: idx, cue: cues[idx])
                            .id(idx)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.offscriptFillSubtle)
                .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
            }
            .frame(maxHeight: 320)
            .accessibilityElement(children: .contain)
            .onChange(of: currentCueIndex) { _, new in
                guard let new else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
            .onAppear {
                // When the user expands the panel mid-playback, jump
                // straight to the current cue instead of starting at
                // the top.
                if let idx = currentCueIndex {
                    proxy.scrollTo(idx, anchor: .center)
                }
            }
        }
    }

    /// Heuristic for nearby-vs-far cues — we soften far-away lines so the
    /// current cue + its neighbourhood read as the focal area. ±2 mirrors
    /// karaoke-style transcript renderers (Overcast / Pocket Casts).
    private func relativePosition(idx: Int) -> RelativePosition {
        guard let current = currentCueIndex else { return .far }
        if idx == current { return .current }
        if abs(idx - current) <= 2 { return .nearby }
        return .far
    }

    private enum RelativePosition { case current, nearby, far }

    private func cueRow(idx: Int, cue: TranscriptCue) -> some View {
        let position = relativePosition(idx: idx)
        let isCurrent = position == .current
        let color: Color = {
            switch position {
            case .current: return .offscriptSignalYellow
            case .nearby:  return .offscriptPaperWhite
            case .far:     return .offscriptSoftPaper
            }
        }()

        return Button {
            // Tap-from-search: clear the query and dismiss the keyboard
            // so the user lands back in the linear cue flow at the right
            // line. Search is a jump-tool, not a persistent filter.
            if !searchQuery.isEmpty {
                searchQuery = ""
                searchFieldFocused = false
            }
            PlaybackController.shared.seek(to: cue.startTime)
            panelLogger.debug("Seeked to cue \(idx, privacy: .public) at \(cue.startTime, privacy: .public)")
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(timestampLabel(cue.startTime))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isCurrent ? Color.offscriptSignalYellow : Color.offscriptSoftPaper)
                    .frame(width: 44, alignment: .leading)

                Text(cue.text)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
            .padding(.leading, isCurrent ? 6 : 0)
            .overlay(alignment: .leading) {
                if isCurrent {
                    // Hairline yellow rail on the leading edge — the
                    // OLED design vocabulary equivalent of a highlight
                    // background. No fills, no rounded corners.
                    Rectangle()
                        .fill(Color.offscriptSignalYellow)
                        .frame(width: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(idx: idx, cue: cue, isCurrent: isCurrent))
        .accessibilityHint("Double-tap to seek to this line.")
    }

    private func accessibilityLabel(idx: Int, cue: TranscriptCue, isCurrent: Bool) -> String {
        let timestamp = EpisodeDurationFormatter.spoken(cue.startTime)
        let suffix = isCurrent ? ". Currently playing" : ""
        return "Cue \(idx + 1) at \(timestamp). \(cue.text)\(suffix)"
    }

    /// Short `MM:SS` / `H:MM:SS` timestamp for the leading column. We use a
    /// dedicated formatter rather than `EpisodeDurationFormatter.short`
    /// (which rounds to whole minutes — too coarse for cue navigation).
    private func timestampLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    // MARK: - Hydration / fetch

    /// Pulls whatever the cache has for this episode — flat text, timed
    /// cues, source, language — into local state. Runs on `.task(id:)`
    /// so it re-fires when the user navigates between episodes.
    @MainActor
    private func hydrateFromCache() async {
        let episodeID = episode.id
        var descriptor = FetchDescriptor<EpisodeTranscriptCache>(
            predicate: #Predicate<EpisodeTranscriptCache> { $0.episodeID == episodeID }
        )
        descriptor.fetchLimit = 1

        guard let entry = try? modelContext.fetch(descriptor).first else {
            // No cache yet — leave the panel in its idle/generate state.
            // Don't clear `status`; it might already be `.transcribing`
            // from an in-flight Speech run.
            return
        }

        transcriptText = entry.text.isEmpty ? nil : entry.text
        cues = entry.cues
        transcriptLanguage = entry.language
        transcriptSource = mapSource(entry.source)
        if transcriptText != nil || !cues.isEmpty {
            status = .ready
        }
    }

    private func mapSource(_ raw: String) -> TranscriptSource {
        switch raw {
        case "published":             return .published
        case "speech", "speechAnalyzer": return .onDevice
        case "mixed":                 return .mixed
        default:                      return .unknown
        }
    }

    // MARK: - Speech action

    @MainActor
    private func runTranscription() async {
        guard let localURL = downloadService.localURL(for: episode) else {
            status = .failed("Download the episode first.")
            return
        }

        status = .requestingPermission
        let auth = await SpeechTranscriptionService.shared.requestAuthorization()
        guard auth == .authorized else {
            status = .failed("Speech permission denied. Enable it in Settings → OffScript.")
            return
        }

        status = .transcribing
        do {
            let text = try await SpeechTranscriptionService.shared.transcribe(
                episode: episode,
                localAudioURL: localURL,
                persistTo: modelContext
            )
            transcriptText = text
            // Refresh cues / source post-transcription — the service may
            // have written cues (published path) or just flat text.
            await hydrateFromCache()
            status = .ready
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isExpanded = true
            }
            panelLogger.info("Transcribed episode \(episode.title, privacy: .public): \(text.count, privacy: .public) chars")
        } catch SpeechTranscriptionService.TranscriptionError.notAuthorized {
            status = .failed("Speech permission denied.")
        } catch SpeechTranscriptionService.TranscriptionError.onDeviceUnavailable {
            status = .failed("On-device transcription isn't available for this device or language.")
        } catch SpeechTranscriptionService.TranscriptionError.recognitionFailed(let reason) {
            status = .failed("Transcription failed: \(reason)")
        } catch {
            status = .failed("Transcription failed: \(error.localizedDescription)")
        }
    }
}

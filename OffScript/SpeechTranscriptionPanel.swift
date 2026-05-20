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
/// Phase 30 began wiring the synchronized-cue UI the Phase 14 audit asked
/// for: this initial commit reads cues + source/language from the cache and
/// renders a provenance chip in the header (PUBLISHED vs ON-DEVICE). Cue
/// rendering, scroll-follow, tap-to-seek, and search land in follow-up
/// commits on this same file.
struct SpeechTranscriptionPanel: View {
    let episode: Episode

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var downloadService = DownloadService.shared
    @State private var status: PanelStatus = .idle
    @State private var transcriptText: String?
    @State private var cues: [TranscriptCue] = []
    @State private var transcriptSource: TranscriptSource = .unknown
    @State private var transcriptLanguage: String?
    @State private var isExpanded = false

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

            if let transcriptText, isExpanded {
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
            return isExpanded ? "Generated on-device. Doesn't leave your phone." : "Transcript ready. Tap to expand."
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

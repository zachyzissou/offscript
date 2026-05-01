import OSLog
import Speech
import SwiftData
import SwiftUI

private let panelLogger = Logger(subsystem: "com.offscript", category: "SpeechTranscriptionPanel")

/// EpisodeDetailView panel that lets the user generate an on-device transcript
/// using Apple's Speech framework. Audio must be downloaded first — streaming
/// transcription is too slow for podcast-length audio. Generated text stays
/// in process memory (cached on `SpeechTranscriptionService.shared`); a
/// future pass will persist it to a SwiftData model so it survives restart.
struct SpeechTranscriptionPanel: View {
    let episode: Episode

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var downloadService = DownloadService.shared
    @State private var status: PanelStatus = .idle
    @State private var transcriptText: String?
    @State private var isExpanded = false

    private enum PanelStatus: Equatable {
        case idle
        case requestingPermission
        case transcribing
        case ready
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TunerLabel(text: "TRANSCRIPT · ON DEVICE", color: .offscriptSignalYellow)
                Spacer()
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
            // Hydrate from persistent cache first (survives app restart),
            // then in-memory cache. Either way the user sees the result
            // instantly without re-running Speech.
            if let stored = SpeechTranscriptionService.shared.persistedTranscript(for: episode.id, in: modelContext) {
                transcriptText = stored
                status = .ready
            }
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

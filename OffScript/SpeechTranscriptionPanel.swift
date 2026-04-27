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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.and.mic")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.offscriptAccent)
                Text("On-Device Transcript".uppercased())
                    .font(.offscriptMicro.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.offscriptAccent)
                Spacer()
                statusBadge
            }

            Text(detailText)
                .font(.offscriptBody)
                .foregroundStyle(Color.offscriptTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            actionButton

            if let transcriptText, isExpanded {
                ScrollView {
                    Text(transcriptText)
                        .font(.offscriptBody)
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(14)
                        .background(Color.offscriptFillSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: OffScriptTheme.Radius.small, style: .continuous))
                }
                .frame(maxHeight: 320)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offscriptUtilitySurface()
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
        case .requestingPermission, .transcribing:
            ProgressView().controlSize(.small).tint(Color.offscriptAccent)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.offscriptAccent)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.offscriptDestructive)
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

    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .ready:
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            } label: {
                Label(isExpanded ? "Hide Transcript" : "Show Transcript",
                      systemImage: isExpanded ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(SecondaryPillButtonStyle())

        case .transcribing, .requestingPermission:
            // Disabled spinner row — no further action while in flight.
            Button { } label: {
                Label("Transcribing…", systemImage: "waveform")
            }
            .buttonStyle(SecondaryPillButtonStyle())
            .disabled(true)

        case .idle, .failed:
            Button {
                Task { await runTranscription() }
            } label: {
                Label("Generate Transcript", systemImage: "sparkles")
            }
            .buttonStyle(PrimaryPillButtonStyle())
            .disabled(downloadService.localURL(for: episode) == nil)
        }
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

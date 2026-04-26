import OSLog
import SwiftUI

/// Inline transcript reader with optional auto-scroll synced to playback.
/// Supports SRT, WebVTT, and plain-text/HTML transcripts. When the transcript
/// has timecodes, the current line auto-highlights as the player progresses.
struct TranscriptReaderSheet: View {
    let transcript: EpisodeTranscriptReference
    let episodeTitle: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var timePublisher = PlaybackTimePublisher.shared

    @State private var lines: [TranscriptLine] = []
    @State private var loadState: LoadState = .loading
    @State private var followsPlayback: Bool = true

    enum LoadState { case loading, loaded, failed(String) }

    var body: some View {
        NavigationStack {
            Group {
                switch loadState {
                case .loading:
                    loadingView
                case .failed(let message):
                    failureView(message)
                case .loaded:
                    if lines.isEmpty {
                        ContentUnavailableView(
                            "Transcript is empty",
                            systemImage: "captions.bubble",
                            description: Text("This episode's transcript file came back empty.")
                        )
                    } else {
                        transcriptView
                    }
                }
            }
            .offscriptPageBackground()
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .tint(Color.offscriptAccent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if hasTimecodes {
                        Toggle(isOn: $followsPlayback) {
                            Image(systemName: followsPlayback ? "lock.fill" : "lock.open")
                        }
                        .toggleStyle(.button)
                        .tint(Color.offscriptAccent)
                        .accessibilityLabel(followsPlayback ? "Auto-follow playback on" : "Auto-follow playback off")
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
        .task { await load() }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large).tint(Color.offscriptAccent)
            Text("Loading transcript…")
                .font(.offscriptBody)
                .foregroundStyle(Color.offscriptTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureView(_ message: String) -> some View {
        ContentUnavailableView(
            "Couldn't load transcript",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
    }

    @ViewBuilder
    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(episodeTitle)
                        .font(.offscriptDisplay)
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .padding(.horizontal, OffScriptTheme.pagePadding)

                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(lines) { line in
                            transcriptLineView(line)
                                .id(line.id)
                                .onTapGesture {
                                    if let start = line.startTime {
                                        PlaybackController.shared.seek(to: start)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    Spacer(minLength: 32)
                }
                .padding(.vertical, 16)
            }
            .onChange(of: currentLineID) { _, newValue in
                guard followsPlayback, let newValue else { return }
                withAnimation(.easeOut(duration: 0.4)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func transcriptLineView(_ line: TranscriptLine) -> some View {
        let isCurrent = currentLineID == line.id
        return VStack(alignment: .leading, spacing: 6) {
            if let start = line.startTime {
                Text(formatTimestamp(start))
                    .font(.system(.caption, design: .monospaced).monospacedDigit())
                    .foregroundStyle(Color.offscriptAccent.opacity(isCurrent ? 1.0 : 0.55))
            }
            Text(line.text)
                .font(.system(isCurrent ? .body : .callout, design: .serif))
                .foregroundStyle(isCurrent ? Color.offscriptTextPrimary : Color.offscriptTextSecondary)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.offscriptAccentSoft)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isCurrent)
    }

    // MARK: - Derived state

    private var hasTimecodes: Bool {
        lines.contains(where: { $0.startTime != nil })
    }

    private var currentLineID: TranscriptLine.ID? {
        guard hasTimecodes else { return nil }
        let now = timePublisher.currentTime
        // Find the latest line whose start <= now.
        return lines
            .filter { ($0.startTime ?? -1) <= now }
            .last?
            .id
    }

    private func formatTimestamp(_ value: TimeInterval) -> String {
        let total = Int(value)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Loading

    private func load() async {
        do {
            let (data, response) = try await URLSession.shared.data(from: transcript.url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                loadState = .failed("Server returned an error.")
                return
            }
            let mime = transcript.mimeType?.lowercased() ?? http.mimeType?.lowercased() ?? ""
            let text = String(data: data, encoding: .utf8) ?? ""
            let parsed = TranscriptParser.parse(text: text, mimeType: mime, sourceURL: transcript.url)
            await MainActor.run {
                self.lines = parsed
                self.loadState = .loaded
            }
        } catch {
            await MainActor.run {
                self.loadState = .failed(error.localizedDescription)
            }
        }
    }
}

struct TranscriptLine: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let startTime: TimeInterval?
    let endTime: TimeInterval?
}

enum TranscriptParser {
    static func parse(text: String, mimeType: String, sourceURL: URL) -> [TranscriptLine] {
        let mime = mimeType.lowercased()
        let ext = sourceURL.pathExtension.lowercased()

        if mime.contains("srt") || ext == "srt" {
            return parseSRT(text)
        }
        if mime.contains("vtt") || ext == "vtt" {
            return parseVTT(text)
        }
        if mime.contains("html") || ext == "html" || ext == "htm" || text.contains("<") {
            return parsePlainText(text.strippingHTML)
        }
        return parsePlainText(text)
    }

    // MARK: - SRT
    // 00:01:23,456 --> 00:01:27,890
    private static func parseSRT(_ text: String) -> [TranscriptLine] {
        let blocks = text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return blocks.compactMap { block -> TranscriptLine? in
            guard !block.isEmpty else { return nil }
            let lines = block.components(separatedBy: .newlines).filter { !$0.isEmpty }
            guard lines.count >= 2 else { return nil }
            let timecodeIndex = lines.firstIndex(where: { $0.contains("-->") }) ?? 0
            let cueLines = Array(lines.suffix(from: timecodeIndex + 1))
            let body = cueLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let timecode = lines[timecodeIndex]
            let times = parseTimecodeRange(timecode)
            return TranscriptLine(text: body, startTime: times.0, endTime: times.1)
        }
    }

    // MARK: - VTT
    // WEBVTT
    // 00:01:23.456 --> 00:01:27.890
    private static func parseVTT(_ text: String) -> [TranscriptLine] {
        var trimmed = text
        if let range = trimmed.range(of: "WEBVTT", options: .caseInsensitive) {
            trimmed.removeSubrange(trimmed.startIndex..<range.upperBound)
        }
        return parseSRT(trimmed.replacingOccurrences(of: ".", with: ","))
    }

    // MARK: - Plain text
    private static func parsePlainText(_ text: String) -> [TranscriptLine] {
        let paragraphs = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Coalesce short consecutive lines into bigger paragraphs for readability.
        var coalesced: [String] = []
        var current = ""
        for line in paragraphs {
            if current.isEmpty {
                current = line
            } else if line.count < 80, !(line.last.map(".!?".contains) ?? true) {
                current += " " + line
            } else {
                coalesced.append((current + " " + line).trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            }
            if current.count > 380 {
                coalesced.append(current)
                current = ""
            }
        }
        if !current.isEmpty { coalesced.append(current) }

        return coalesced.map { TranscriptLine(text: $0, startTime: nil, endTime: nil) }
    }

    // MARK: - Timecode helpers

    private static func parseTimecodeRange(_ raw: String) -> (TimeInterval?, TimeInterval?) {
        let parts = raw.components(separatedBy: "-->")
        guard parts.count == 2 else { return (nil, nil) }
        let start = parseTimecode(parts[0].trimmingCharacters(in: .whitespaces))
        let end = parseTimecode(parts[1].trimmingCharacters(in: .whitespaces))
        return (start, end)
    }

    private static func parseTimecode(_ raw: String) -> TimeInterval? {
        let cleaned = raw.replacingOccurrences(of: ",", with: ".")
        let segments = cleaned.split(separator: ":")
        guard segments.count >= 2 else { return nil }
        let parts = segments.compactMap { Double($0) }
        guard parts.count == segments.count else { return nil }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        return parts[0] * 60 + parts[1]
    }
}

import Foundation
import OSLog
import SwiftData

private let publishedTranscriptLogger = Logger(subsystem: "com.offscript", category: "PublishedTranscript")

/// Fetches and parses feed-provided transcripts referenced via
/// `<podcast:transcript>` elements (Podcasting 2.0 namespace).
///
/// When a feed publishes an authoritative transcript we should always prefer it
/// over running Speech recognition on-device — it's faster (single HTTP fetch
/// vs. real-time CPU burn), more accurate (publisher-edited), and carries
/// speaker labels that Speech can't produce.
///
/// Format support:
///   - `application/json` — Podcasting 2.0 transcript JSON (timed segments)
///   - `text/vtt`         — WebVTT cues
///   - `application/srt` / `text/srt` — TODO (similar to VTT, slightly different
///     timestamp format)
///   - `text/html`        — TODO (no timing; would render as flat text)
///
/// Selection policy: when multiple references are present we prefer
/// JSON > VTT > SRT > HTML for richness of timing data, then narrow to the
/// reference matching the requested locale's language code if one exists.
enum PublishedTranscriptLoader {
    /// Returned cue list from a successful fetch. `language` is the BCP-47
    /// tag of the picked reference (may differ from the requested locale if
    /// no exact match was available).
    struct LoadedTranscript: Hashable, Sendable {
        let cues: [TranscriptCue]
        let plainText: String
        let language: String?
        let sourceURL: URL
    }

    /// Fetch the best available published transcript for an episode and persist
    /// it to `EpisodeTranscriptCache`. Returns `nil` if the episode has no
    /// transcript references, none could be fetched, or none could be parsed.
    ///
    /// Idempotent — checks the cache first and short-circuits if a published
    /// transcript is already on disk.
    @MainActor
    static func fetchPublishedTranscript(
        for episode: Episode,
        preferredLanguage: String? = Locale.current.language.languageCode?.identifier,
        persistTo context: ModelContext? = nil
    ) async -> LoadedTranscript? {
        let references = episode.transcriptReferences
        guard !references.isEmpty else { return nil }

        // Honour an already-cached published transcript before hitting network.
        if let context, let existing = persistedPublishedTranscript(for: episode.id, in: context) {
            return existing
        }

        guard let pick = bestReference(from: references, preferredLanguage: preferredLanguage) else {
            return nil
        }

        guard let data = await fetch(url: pick.url) else { return nil }
        guard let cues = parse(data: data, mimeType: pick.mimeType) else {
            publishedTranscriptLogger.debug("Could not parse transcript at \(pick.url.absoluteString, privacy: .public) type=\(pick.mimeType ?? "nil", privacy: .public)")
            return nil
        }
        guard !cues.isEmpty else { return nil }

        let plain = flatten(cues: cues)
        let loaded = LoadedTranscript(
            cues: cues,
            plainText: plain,
            language: pick.language,
            sourceURL: pick.url
        )

        if let context {
            persist(loaded, for: episode, in: context)
        }

        return loaded
    }

    // MARK: - Reference selection

    /// Picks the highest-fidelity reference, breaking ties by language match.
    /// Visible-for-tests so the selection rule can be exercised without network.
    static func bestReference(
        from references: [EpisodeTranscriptReference],
        preferredLanguage: String?
    ) -> EpisodeTranscriptReference? {
        guard !references.isEmpty else { return nil }

        let scored = references.map { ref -> (EpisodeTranscriptReference, Int, Int) in
            (ref, formatScore(for: ref.mimeType), languageScore(for: ref.language, preferred: preferredLanguage))
        }

        // Higher format score wins; on ties, higher language score wins; on
        // further ties, fall back to the first reference as parsed.
        return scored.max { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.2 < rhs.2
        }?.0
    }

    /// JSON > VTT > SRT > HTML > unknown. Higher is better.
    private static func formatScore(for mimeType: String?) -> Int {
        let normalized = (mimeType ?? "").lowercased()
        if normalized.contains("json") { return 40 }
        if normalized.contains("vtt") { return 30 }
        if normalized.contains("srt") { return 20 }
        if normalized.contains("html") { return 10 }
        return 0
    }

    /// 20 for exact match, 10 for language-code-only match (e.g. "en" matches
    /// "en-US"), 0 for no preference, -5 for explicit mismatch.
    private static func languageScore(for language: String?, preferred: String?) -> Int {
        guard let preferred, !preferred.isEmpty else { return 0 }
        guard let language, !language.isEmpty else { return 0 }
        if language.caseInsensitiveCompare(preferred) == .orderedSame { return 20 }
        let langPrefix = language.split(separator: "-").first.map(String.init)?.lowercased()
        let prefPrefix = preferred.split(separator: "-").first.map(String.init)?.lowercased()
        if let l = langPrefix, let p = prefPrefix, l == p { return 10 }
        return -5
    }

    // MARK: - Fetch + parse

    private static func fetch(url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json, text/vtt, text/plain;q=0.5", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                publishedTranscriptLogger.debug("Transcript fetch HTTP \(http.statusCode) for \(url.absoluteString, privacy: .public)")
                return nil
            }
            return data
        } catch {
            publishedTranscriptLogger.debug("Transcript fetch failed for \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Visible-for-tests. Dispatches to the format-specific decoder by MIME
    /// type. When `mimeType` is nil or unknown, we sniff: if the bytes start
    /// with `WEBVTT` we treat it as VTT, otherwise we attempt JSON.
    static func parse(data: Data, mimeType: String?) -> [TranscriptCue]? {
        let normalized = (mimeType ?? "").lowercased()
        if normalized.contains("json") {
            return decodeJSON(data: data)
        }
        if normalized.contains("vtt") {
            return decodeVTT(data: data)
        }
        // Sniff fallback.
        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("WEBVTT") {
                return decodeVTT(text: trimmed)
            }
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                return decodeJSON(data: data)
            }
        }
        return nil
    }

    // MARK: - Podcasting 2.0 JSON transcript

    private struct JSONEnvelope: Decodable {
        let version: String?
        let segments: [JSONSegment]
    }

    private struct JSONSegment: Decodable {
        let speaker: String?
        let startTime: TimeInterval
        let endTime: TimeInterval?
        let body: String

        enum CodingKeys: String, CodingKey {
            case speaker, startTime, endTime, body
        }
    }

    /// Decode the Podcasting 2.0 transcript JSON envelope. Visible-for-tests.
    static func decodeJSON(data: Data) -> [TranscriptCue]? {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(JSONEnvelope.self, from: data) else { return nil }
        let cues = envelope.segments.map { seg -> TranscriptCue in
            TranscriptCue(
                startTime: seg.startTime,
                endTime: seg.endTime ?? seg.startTime,
                speaker: seg.speaker?.isEmpty == false ? seg.speaker : nil,
                text: seg.body.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        .filter { !$0.text.isEmpty }
        return cues
    }

    // MARK: - WebVTT

    /// Decode a WebVTT blob. Visible-for-tests. Tolerant of:
    ///   - the optional `WEBVTT` header line
    ///   - blank lines between cues
    ///   - optional cue identifier lines (we drop them)
    ///   - either `.` or `,` as the seconds-fractional separator (some non-standard exports)
    static func decodeVTT(data: Data) -> [TranscriptCue]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return decodeVTT(text: text)
    }

    static func decodeVTT(text: String) -> [TranscriptCue]? {
        // VTT splits cues on blank lines. Normalize line endings, then chunk.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [TranscriptCue] = []
        cues.reserveCapacity(blocks.count)

        for block in blocks {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("WEBVTT") { continue }
            if trimmed.hasPrefix("NOTE") { continue }
            if trimmed.hasPrefix("STYLE") || trimmed.hasPrefix("REGION") { continue }

            var lines = trimmed.components(separatedBy: "\n")
            guard !lines.isEmpty else { continue }

            // First line may be a cue identifier; the timing line is the
            // first that contains "-->".
            if !lines[0].contains("-->") {
                lines.removeFirst()
                guard !lines.isEmpty, lines[0].contains("-->") else { continue }
            }

            let timing = lines.removeFirst()
            guard let (start, end) = parseVTTTiming(timing) else { continue }

            let body = lines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }

            cues.append(TranscriptCue(startTime: start, endTime: end, speaker: nil, text: body))
        }

        return cues.isEmpty ? nil : cues
    }

    /// Parse a VTT timing line like "00:00:01.000 --> 00:00:04.500 align:start".
    private static func parseVTTTiming(_ line: String) -> (TimeInterval, TimeInterval)? {
        guard let arrowRange = line.range(of: "-->") else { return nil }
        let lhs = String(line[..<arrowRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let rhsRaw = String(line[arrowRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        // Drop cue-settings tokens after the end timestamp.
        let rhs = rhsRaw.split(separator: " ", maxSplits: 1).first.map(String.init) ?? rhsRaw
        guard let start = parseVTTTimestamp(lhs), let end = parseVTTTimestamp(rhs) else { return nil }
        return (start, end)
    }

    /// Parse `HH:MM:SS.mmm` or `MM:SS.mmm`. Accepts `,` in place of `.`.
    private static func parseVTTTimestamp(_ raw: String) -> TimeInterval? {
        let cleaned = raw.replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.split(separator: ":")
        guard !parts.isEmpty else { return nil }
        let secondsPart = parts.last.map(String.init) ?? "0"
        guard let seconds = Double(secondsPart) else { return nil }

        var total = seconds
        if parts.count >= 2, let minutes = Double(parts[parts.count - 2]) {
            total += minutes * 60
        }
        if parts.count >= 3, let hours = Double(parts[parts.count - 3]) {
            total += hours * 3600
        }
        return total
    }

    // MARK: - Helpers

    private static func flatten(cues: [TranscriptCue]) -> String {
        cues.map { cue in
            if let speaker = cue.speaker, !speaker.isEmpty {
                return "\(speaker): \(cue.text)"
            }
            return cue.text
        }.joined(separator: "\n")
    }

    // MARK: - Cache integration

    /// Looks up an already-fetched published transcript in the SwiftData cache.
    @MainActor
    private static func persistedPublishedTranscript(
        for episodeID: UUID,
        in context: ModelContext
    ) -> LoadedTranscript? {
        var descriptor = FetchDescriptor<EpisodeTranscriptCache>(
            predicate: #Predicate<EpisodeTranscriptCache> { $0.episodeID == episodeID }
        )
        descriptor.fetchLimit = 1
        guard let entry = try? context.fetch(descriptor).first, entry.source == "published" else {
            return nil
        }
        let cues = entry.cues
        guard !cues.isEmpty else { return nil }
        return LoadedTranscript(
            cues: cues,
            plainText: entry.text,
            language: entry.language,
            sourceURL: URL(string: "about:cached") ?? URL(fileURLWithPath: "/")
        )
    }

    /// Insert-or-update the cache entry for this episode. Replaces any prior
    /// entry (incl. a Speech-generated one) — publisher transcripts win.
    @MainActor
    private static func persist(
        _ loaded: LoadedTranscript,
        for episode: Episode,
        in context: ModelContext
    ) {
        // Replace any existing cache row so we don't drift between speech and
        // published variants. SwiftData enforces uniqueness on episodeID; we
        // delete first to avoid an insert conflict.
        let episodeID = episode.id
        var descriptor = FetchDescriptor<EpisodeTranscriptCache>(
            predicate: #Predicate<EpisodeTranscriptCache> { $0.episodeID == episodeID }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
        }

        let entry = EpisodeTranscriptCache(
            episodeID: episode.id,
            text: loaded.plainText,
            generatedAt: .now,
            source: "published",
            coverageSeconds: episode.duration,
            language: loaded.language,
            cues: loaded.cues
        )
        context.insert(entry)
        do {
            try context.save()
        } catch {
            publishedTranscriptLogger.error("Failed to persist published transcript: \(error.localizedDescription, privacy: .public)")
        }
    }
}

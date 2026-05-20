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
///   - `application/srt` / `text/srt` — SubRip cues (comma OR period ms separator)
///   - `text/html`        — HTML transcript; if `data-start`/`data-time`
///     attributes are present we build cues from them, otherwise we fall back
///     to a single cue spanning the whole episode (searchable, not scrubbable).
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
        guard let cues = parse(data: data, mimeType: pick.mimeType, episodeDuration: episode.duration) else {
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
    /// type. When `mimeType` is nil or unknown, we sniff: WEBVTT prefix → VTT,
    /// `{`/`[` → JSON, an integer + SRT-timing line → SRT, leading `<` → HTML.
    ///
    /// `episodeDuration` is consulted only by the HTML fallback path when the
    /// document has no timing markers — we emit a single cue spanning the
    /// episode so the prose is at least searchable.
    static func parse(
        data: Data,
        mimeType: String?,
        episodeDuration: TimeInterval? = nil
    ) -> [TranscriptCue]? {
        let normalized = (mimeType ?? "").lowercased()
        if normalized.contains("json") {
            return decodeJSON(data: data)
        }
        if normalized.contains("vtt") {
            return decodeVTT(data: data)
        }
        if normalized.contains("srt") || normalized.contains("subrip") {
            return decodeSRT(data: data)
        }
        if normalized.contains("html") || normalized.contains("xhtml") {
            return decodeHTML(data: data, episodeDuration: episodeDuration)
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
            if trimmed.hasPrefix("<") {
                return decodeHTML(data: data, episodeDuration: episodeDuration)
            }
            // SRT sniff: first line is an integer, second line contains "-->".
            let firstLines = trimmed.split(separator: "\n", maxSplits: 2).map(String.init)
            if firstLines.count >= 2,
               Int(firstLines[0].trimmingCharacters(in: .whitespaces)) != nil,
               firstLines[1].contains("-->") {
                return decodeSRT(text: trimmed)
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

    // MARK: - SubRip (SRT)

    /// Decode a SubRip blob. Visible-for-tests. Tolerant of:
    ///   - Windows line endings (`\r\n`)
    ///   - `,` (canonical) OR `.` (widely tolerated) as the ms separator
    ///   - HTML-style inline tags (`<i>`, `<b>`, `<font color="...">`) — stripped
    ///   - Multi-line cue text — joined with a space
    ///   - Trailing whitespace / blank blocks at end of file
    static func decodeSRT(data: Data) -> [TranscriptCue]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return decodeSRT(text: text)
    }

    static func decodeSRT(text: String) -> [TranscriptCue]? {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [TranscriptCue] = []
        cues.reserveCapacity(blocks.count)

        for block in blocks {
            let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBlock.isEmpty { continue }
            guard let cue = parseSRTBlock(trimmedBlock) else { continue }
            cues.append(cue)
        }

        return cues.isEmpty ? nil : cues
    }

    private static func parseSRTBlock(_ block: String) -> TranscriptCue? {
        var lines = block.components(separatedBy: "\n")
        guard lines.count >= 2 else { return nil }

        // Optional sequence number on the first line. Skip it if present so we
        // can tolerate blocks that begin straight with the timing line.
        if Int(lines[0].trimmingCharacters(in: .whitespaces)) != nil,
           lines.count >= 3,
           lines[1].contains("-->") {
            lines.removeFirst()
        }

        guard !lines.isEmpty, lines[0].contains("-->") else { return nil }
        let timing = lines.removeFirst()
        guard let (start, end) = parseSRTTiming(timing) else { return nil }

        let joined = lines.joined(separator: " ")
        let stripped = stripInlineHTMLTags(joined)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }

        return TranscriptCue(startTime: start, endTime: end, speaker: nil, text: stripped)
    }

    private static func parseSRTTiming(_ line: String) -> (TimeInterval, TimeInterval)? {
        guard let arrowRange = line.range(of: "-->") else { return nil }
        let lhs = String(line[..<arrowRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let rhsRaw = String(line[arrowRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        // Drop any trailing positioning tokens (rare in SRT but harmless to allow).
        let rhs = rhsRaw.split(separator: " ", maxSplits: 1).first.map(String.init) ?? rhsRaw
        guard let start = parseSRTTimestamp(lhs), let end = parseSRTTimestamp(rhs) else { return nil }
        return (start, end)
    }

    /// `HH:MM:SS,mmm` (canonical) or `HH:MM:SS.mmm` (widely tolerated).
    private static func parseSRTTimestamp(_ raw: String) -> TimeInterval? {
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    // MARK: - HTML transcript

    /// Decode an HTML transcript. The Podcasting 2.0 spec is loose here —
    /// timing, if present at all, lives on `<p data-start="N">` or
    /// `<span data-time="N">` attributes. If we find any, we build cues from
    /// them; otherwise we emit a single cue spanning the whole episode so the
    /// prose is at least searchable (just not scrubbable).
    static func decodeHTML(data: Data, episodeDuration: TimeInterval?) -> [TranscriptCue]? {
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        return decodeHTML(text: html, episodeDuration: episodeDuration)
    }

    static func decodeHTML(text html: String, episodeDuration: TimeInterval?) -> [TranscriptCue]? {
        let timed = extractTimedHTMLCues(from: html)
        if !timed.isEmpty {
            return timed
        }
        let plain = stripInlineHTMLTags(html)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = collapseWhitespace(plain)
        guard !collapsed.isEmpty else { return nil }
        return [TranscriptCue(
            startTime: 0,
            endTime: episodeDuration ?? 0,
            speaker: nil,
            text: collapsed
        )]
    }

    private static func extractTimedHTMLCues(from html: String) -> [TranscriptCue] {
        // Matches <p data-start="N">…</p> or <span data-time="N">…</span>.
        // Content capture stops at the closing tag's `<`, which keeps it simple
        // and good enough for the loose HTML-transcript convention.
        let pattern = #"<(p|span)\s+[^>]*data-(?:start|time)\s*=\s*"([\d.]+)"[^>]*>([\s\S]*?)</\1>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        var cues: [TranscriptCue] = []
        regex.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match = match,
                  let timeRange = Range(match.range(at: 2), in: html),
                  let textRange = Range(match.range(at: 3), in: html),
                  let start = TimeInterval(html[timeRange]) else { return }
            let inner = stripInlineHTMLTags(String(html[textRange]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let body = collapseWhitespace(inner)
            guard !body.isEmpty else { return }
            cues.append(TranscriptCue(
                startTime: start,
                endTime: start,  // No end marker in this convention.
                speaker: nil,
                text: body
            ))
        }
        return cues
    }

    /// Remove HTML tags and decode the small set of common entities that show
    /// up in transcript prose. We intentionally do NOT decode the full HTML
    /// entity table — anything more exotic is a publisher error worth
    /// surfacing rather than silently papering over.
    private static func stripInlineHTMLTags(_ input: String) -> String {
        let stripped = input.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    /// Collapse runs of whitespace into a single space. Used by the HTML
    /// decoder where tag-stripping leaves multiple spaces behind.
    private static func collapseWhitespace(_ input: String) -> String {
        input.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
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

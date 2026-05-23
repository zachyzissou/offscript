import Foundation
import SwiftData

@Model
final class Podcast {
    private static let listSeparator = "\u{1F}"

    var id: UUID = UUID()
    var title: String = ""
    var author: String?
    var summary: String?
    var feedURL: URL = URL(string: "https://placeholder.invalid")!
    var websiteURL: URL?
    var artworkURL: URL?
    private var categoriesStorage: String = ""
    var isSubscribed: Bool = true
    var subscribedAt: Date?
    var latestPubDate: Date?
    var lastSyncAt: Date?
    var lastSyncAttemptAt: Date?
    var feedETag: String?
    var feedLastModified: String?
    var syncStatus: String = "idle"
    var syncFailureCount: Int = 0
    var syncErrorMessage: String?
    var nextRetryAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Episode.podcast)
    var episodes: [Episode] = []

    init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        summary: String? = nil,
        feedURL: URL,
        websiteURL: URL? = nil,
        artworkURL: URL? = nil,
        categories: [String] = [],
        isSubscribed: Bool = true
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.summary = summary
        self.feedURL = feedURL
        self.websiteURL = websiteURL
        self.artworkURL = artworkURL
        self.categoriesStorage = categories.joined(separator: Self.listSeparator)
        self.isSubscribed = isSubscribed
        self.syncStatus = "idle"
        self.syncFailureCount = 0
    }

    var categories: [String] {
        get {
            guard !categoriesStorage.isEmpty else { return [] }
            return categoriesStorage.components(separatedBy: Self.listSeparator)
        }
        set {
            categoriesStorage = newValue.joined(separator: Self.listSeparator)
        }
    }
}

@Model
final class Episode {
    enum DownloadState: String, Codable {
        case notDownloaded
        case queued
        case downloading
        case downloaded
        case failed
    }

    var id: UUID = UUID()
    var guid: String = ""
    var title: String = ""
    var summary: String?
    var pubDate: Date = Date.distantPast
    var duration: TimeInterval?
    var audioURL: URL = URL(string: "https://placeholder.invalid")!
    var artworkURL: URL?
    var localFileURL: URL?
    private(set) var downloadStateRawValue: String = DownloadState.notDownloaded.rawValue
    private var chaptersStorage: String = ""
    private var transcriptReferencesStorage: String = ""
    var downloadProgress: Double = 0
    var downloadRequestedAt: Date?
    var downloadCompletedAt: Date?
    var downloadErrorMessage: String?
    var playedPosition: TimeInterval = 0
    var isPlayed: Bool = false
    var isDownloaded: Bool = false
    var isQueued: Bool = false
    var lastPlayedAt: Date?
    var seasonNumber: Int?
    var episodeNumber: Int?

    var podcast: Podcast

    @Relationship(deleteRule: .cascade, inverse: \QueueItem.episode)
    var queueItems: [QueueItem] = []

    @Relationship(deleteRule: .nullify, inverse: \PlaybackEvent.episode)
    var playbackEvents: [PlaybackEvent] = []

    @Relationship(deleteRule: .cascade, inverse: \PreferenceSignal.episode)
    var preferenceSignals: [PreferenceSignal] = []

    @Relationship(deleteRule: .cascade, inverse: \EpisodeProfile.episode)
    var profile: EpisodeProfile?

    init(
        id: UUID = UUID(),
        guid: String = UUID().uuidString,
        title: String,
        summary: String? = nil,
        pubDate: Date,
        duration: TimeInterval? = nil,
        audioURL: URL,
        artworkURL: URL? = nil,
        localFileURL: URL? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        podcast: Podcast
    ) {
        self.id = id
        self.guid = guid
        self.title = title
        self.summary = summary
        self.pubDate = pubDate
        self.duration = duration
        self.audioURL = audioURL
        self.artworkURL = artworkURL
        self.localFileURL = localFileURL
        self.downloadStateRawValue = DownloadState.notDownloaded.rawValue
        self.chaptersStorage = ""
        self.transcriptReferencesStorage = ""
        self.downloadProgress = 0
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.podcast = podcast
    }

    var downloadState: DownloadState {
        get { DownloadState(rawValue: downloadStateRawValue) ?? .notDownloaded }
        set { downloadStateRawValue = newValue.rawValue }
    }

    var chapters: [EpisodeChapter] {
        get {
            Self.decodeJSON([EpisodeChapter].self, from: chaptersStorage) ?? []
        }
        set {
            let normalized = EpisodeChapterParser.normalize(newValue, duration: duration)
            chaptersStorage = Self.encodeJSON(normalized)
        }
    }

    var transcriptReferences: [EpisodeTranscriptReference] {
        get {
            Self.decodeJSON([EpisodeTranscriptReference].self, from: transcriptReferencesStorage) ?? []
        }
        set {
            let normalized = newValue
                .sorted { lhs, rhs in
                    if lhs.language == rhs.language {
                        return lhs.url.absoluteString < rhs.url.absoluteString
                    }
                    return (lhs.language ?? "") < (rhs.language ?? "")
                }
            transcriptReferencesStorage = Self.encodeJSON(normalized)
        }
    }

    var resolvedChapters: [EpisodeChapter] {
        let persisted = EpisodeChapterParser.normalize(chapters, duration: duration)
        guard persisted.isEmpty else { return persisted }
        return EpisodeChapterParser.chapters(from: summary, duration: duration)
    }

    private static func encodeJSON<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, from storage: String) -> T? {
        guard !storage.isEmpty, let data = storage.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

@Model
final class QueueItem {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var position: Int = 0
    @Relationship(deleteRule: .noAction)
    var episode: Episode

    init(id: UUID = UUID(), episode: Episode, position: Int) {
        self.id = id
        self.episode = episode
        self.position = position
    }
}

@Model
final class PlaybackEvent {
    enum Kind: String, Codable {
        case started
        case completed
        case skippedQuickly
        case seekedForward
        case seekedBackward
        case abandoned
        case advancedFromQueue
        case resumed
    }

    var date: Date = Date()
    private(set) var kindRawValue: String = Kind.started.rawValue
    var position: TimeInterval = 0
    @Relationship(deleteRule: .noAction)
    var episode: Episode?

    init(kind: Kind, position: TimeInterval, episode: Episode) {
        self.kindRawValue = kind.rawValue
        self.position = position
        self.episode = episode
    }

    var kind: Kind {
        get { Kind(rawValue: kindRawValue) ?? .started }
        set { kindRawValue = newValue.rawValue }
    }
}

@Model
final class PreferenceSignal {
    enum Action: String, Codable { case like, notInterested, moreLikeThis, lessLikeThis }
    var date: Date = Date()
    private var actionRawValue: String = Action.like.rawValue
    // Non-optional Episode so RecommendationService keypaths (\.episode.id)
    // resolve cleanly. Episode.preferenceSignals owns the cascade delete;
    // this side is explicit so SwiftData never tries to null a required row.
    @Relationship(deleteRule: .noAction)
    var episode: Episode

    init(action: Action, episode: Episode) {
        self.actionRawValue = action.rawValue
        self.episode = episode
    }

    var action: Action {
        get { Action(rawValue: actionRawValue) ?? .like }
        set { actionRawValue = newValue.rawValue }
    }
}

@Model
final class UserTasteProfile {
    private static let listSeparator = "\u{1F}"

    var id: String = "primary"
    private var preferredGenresStorage: String
    private var topTagsStorage: String
    private var showAffinityStorage: String
    var averageCompletedDurationMinutes: Double
    var prefersShortEpisodes: Bool
    var unfinishedEpisodeAffinity: Double
    var lastUpdatedAt: Date

    init(id: String = "primary") {
        self.id = id
        self.preferredGenresStorage = ""
        self.topTagsStorage = ""
        self.showAffinityStorage = ""
        self.averageCompletedDurationMinutes = 30
        self.prefersShortEpisodes = false
        self.unfinishedEpisodeAffinity = 0
        self.lastUpdatedAt = .now
    }

    var preferredGenres: [String] {
        get {
            guard !preferredGenresStorage.isEmpty else { return [] }
            return preferredGenresStorage.components(separatedBy: Self.listSeparator)
        }
        set {
            preferredGenresStorage = newValue.joined(separator: Self.listSeparator)
        }
    }

    var topTags: [String] {
        get {
            guard !topTagsStorage.isEmpty else { return [] }
            return topTagsStorage.components(separatedBy: Self.listSeparator)
        }
        set {
            topTagsStorage = newValue.joined(separator: Self.listSeparator)
        }
    }

    var showAffinity: [String] {
        get {
            guard !showAffinityStorage.isEmpty else { return [] }
            return showAffinityStorage.components(separatedBy: Self.listSeparator)
        }
        set {
            showAffinityStorage = newValue.joined(separator: Self.listSeparator)
        }
    }
}

@Model
final class EpisodeProfile {
    private static let listSeparator = "\u{1F}"

    var episodeID: UUID = UUID()
    private var tagsStorage: String = ""
    private var entitiesStorage: String = ""
    var summary: String?

    // Recommendation-engine scoring inputs (added on origin/main).
    // Default values keep older stores migration-safe.
    //
    // Wiring status (see `docs/superpowers/audits/2026-05-20-deadcode-wiring-resweep.md`
    // N1 resolution):
    //   - confidenceScore: WIRED. Populated by TopicExtractionService.enrich(...)
    //     from the size/diversity of extracted tags+entities. Higher value =
    //     extractor produced more distinct signal for this episode.
    //   - qualityScore: DORMANT. No honest on-device source exists yet
    //     (audio-quality classification would need iOS 26 SoundAnalysis +
    //     ground-truth labels). The reader at RecommendationService.swift:540
    //     guards on `> 0` so dormancy doesn't silently kill the tiebreaker.
    //   - estimatedListeningContext: DORMANT. Would require modeling user
    //     playback contexts (commute/workout/wind-down) — out of scope for
    //     Phase 36; honest population needs behavior data we don't yet collect
    //     with user consent.
    //   - freshnessBucket: DORMANT. Caching a bucket from `pubDate` would just
    //     duplicate the inline freshness math at RecommendationService.swift
    //     :545 and introduce a staleness bug as `now` moves forward. Read
    //     sites have `episode.pubDate` trivially available — caching adds no
    //     value. Kept as a column for forward-compat with a future
    //     classifier that uses non-time-based signals (e.g. "evergreen").
    //   - introSkipSeconds / outroSkipSeconds: DORMANT. Would require audio
    //     fingerprinting across episodes of the same show — substantial
    //     implementation cost, no current consumer.
    //
    // Dormant fields are retained (rather than deleted) because dropping
    // persisted columns should be a deliberate SchemaVN migration. When a
    // producer lands, flip the comment and wire it in the existing enrich()
    // pipeline.
    var qualityScore: Double = 0.0
    var confidenceScore: Double = 0.0
    var estimatedListeningContext: String?
    var freshnessBucket: String?
    var introSkipSeconds: TimeInterval = 0
    var outroSkipSeconds: TimeInterval = 0

    @Relationship(deleteRule: .noAction)
    var episode: Episode?

    init(episodeID: UUID) {
        self.episodeID = episodeID
    }

    var tags: [String] {
        get {
            guard !tagsStorage.isEmpty else { return [] }
            return tagsStorage.components(separatedBy: Self.listSeparator)
        }
        set {
            tagsStorage = newValue.joined(separator: Self.listSeparator)
        }
    }

    var entities: [String] {
        get {
            guard !entitiesStorage.isEmpty else { return [] }
            return entitiesStorage.components(separatedBy: Self.listSeparator)
        }
        set {
            entitiesStorage = newValue.joined(separator: Self.listSeparator)
        }
    }
}

struct PodcastSearchResult: Identifiable, Hashable {
    var id: String { feedURL.absoluteString }
    let title: String
    let author: String
    let feedURL: URL
    let artworkURL: URL?
    let websiteURL: URL?
    let summary: String?
}

struct HomeFeedSection: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let scoredEpisodes: [ScoredEpisode]
    let discoveryResults: [ScoredDiscoveryResult]

    init(title: String, subtitle: String, scoredEpisodes: [ScoredEpisode]) {
        self.title = title
        self.subtitle = subtitle
        self.scoredEpisodes = scoredEpisodes
        self.discoveryResults = []
    }

    init(title: String, subtitle: String, discoveryResults: [ScoredDiscoveryResult]) {
        self.title = title
        self.subtitle = subtitle
        self.scoredEpisodes = []
        self.discoveryResults = discoveryResults
    }

    var isDiscoverySection: Bool { !discoveryResults.isEmpty }

    var episodes: [Episode] {
        scoredEpisodes.map(\.episode)
    }

    func explanation(for episode: Episode) -> String {
        scoredEpisodes.first(where: { $0.episode.id == episode.id })?.explanation
            ?? "Subscribed channel: \(episode.podcast.title)"
    }

    func signalTrace(for episode: Episode) -> [RecommendationSignal] {
        scoredEpisodes.first(where: { $0.episode.id == episode.id })?.signalTrace ?? []
    }
}

@Model
final class TelemetryEvent {
    private static let pairSeparator = "\u{1E}"
    private static let valueSeparator = "\u{1F}"

    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    private var metadataStorage: String = ""

    init(id: UUID = UUID(), name: String, createdAt: Date = .now, metadata: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.metadataStorage = ""
        self.metadata = metadata
    }

    var metadata: [String: String] {
        get {
            guard !metadataStorage.isEmpty else { return [:] }
            return metadataStorage
                .components(separatedBy: Self.pairSeparator)
                .reduce(into: [:]) { partialResult, pair in
                    let parts = pair.components(separatedBy: Self.valueSeparator)
                    guard parts.count == 2 else { return }
                    partialResult[parts[0]] = parts[1]
                }
        }
        set {
            metadataStorage = newValue
                .sorted { $0.key < $1.key }
                .map { key, value in
                    "\(key)\(Self.valueSeparator)\(value)"
                }
                .joined(separator: Self.pairSeparator)
        }
    }
}

struct EpisodeChapter: Identifiable, Hashable, Codable, Sendable {
    let title: String
    let startTime: TimeInterval
    let endTime: TimeInterval?
    let imageURL: URL?
    let linkURL: URL?
    /// Whether this chapter should appear in a table-of-contents navigation list.
    /// Per the podcast namespace spec (`toc` field), defaults to `true`. Chapters with
    /// `toc == false` should still affect playback boundaries but can be filtered from UI lists.
    let isInTableOfContents: Bool

    var id: String {
        "\(Int(startTime * 1000))-\(title)"
    }

    init(
        title: String,
        startTime: TimeInterval,
        endTime: TimeInterval? = nil,
        imageURL: URL? = nil,
        linkURL: URL? = nil,
        isInTableOfContents: Bool = true
    ) {
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.imageURL = imageURL
        self.linkURL = linkURL
        self.isInTableOfContents = isInTableOfContents
    }

    // Custom decoder so older persisted chapters (title + startTime only) keep decoding
    // without breaking on missing optional fields.
    private enum CodingKeys: String, CodingKey {
        case title
        case startTime
        case endTime
        case imageURL
        case linkURL
        case isInTableOfContents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)
        self.startTime = try container.decode(TimeInterval.self, forKey: .startTime)
        self.endTime = try container.decodeIfPresent(TimeInterval.self, forKey: .endTime)
        self.imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
        self.linkURL = try container.decodeIfPresent(URL.self, forKey: .linkURL)
        self.isInTableOfContents = try container.decodeIfPresent(Bool.self, forKey: .isInTableOfContents) ?? true
    }
}

struct EpisodeTranscriptReference: Identifiable, Hashable, Codable, Sendable {
    let url: URL
    let mimeType: String?
    let language: String?
    let rel: String?

    var id: String {
        url.absoluteString
    }

    var displayTitle: String {
        var components: [String] = []
        if let rel, !rel.isEmpty {
            components.append(rel.replacingOccurrences(of: "-", with: " ").capitalized)
        } else {
            components.append("Transcript")
        }
        if let language, !language.isEmpty {
            components.append(language.uppercased())
        }
        return components.joined(separator: " • ")
    }

    var accessoryLabel: String {
        if let mimeType, !mimeType.isEmpty {
            return mimeType
                .split(separator: "/")
                .last
                .map { String($0).uppercased() } ?? mimeType.uppercased()
        }
        return "Open"
    }
}

enum EpisodeChapterParser {
    private static let chapterPattern = #"(?m)^\s*((?:\d{1,2}:)?\d{1,2}:\d{2})\s+(.*\S)\s*$"#

    static func chapters(from summary: String?, duration: TimeInterval?) -> [EpisodeChapter] {
        guard let summary, !summary.isEmpty else { return [] }
        guard let regex = try? NSRegularExpression(pattern: chapterPattern) else { return [] }

        let range = NSRange(summary.startIndex..<summary.endIndex, in: summary)
        let matches = regex.matches(in: summary, range: range)
        guard !matches.isEmpty else { return [] }

        let parsed = matches.compactMap { match -> EpisodeChapter? in
            guard match.numberOfRanges == 3,
                  let timeRange = Range(match.range(at: 1), in: summary),
                  let titleRange = Range(match.range(at: 2), in: summary),
                  let startTime = seconds(from: String(summary[timeRange])) else {
                return nil
            }

            let title = String(summary[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            if let duration, duration > 0, startTime > duration {
                return nil
            }

            return EpisodeChapter(title: title, startTime: startTime)
        }

        return normalize(parsed, duration: duration)
    }

    static func normalize(_ chapters: [EpisodeChapter], duration: TimeInterval?) -> [EpisodeChapter] {
        chapters
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { chapter in
                guard let duration, duration > 0 else { return true }
                return chapter.startTime <= duration
            }
            .sorted { $0.startTime < $1.startTime }
            .reduce(into: [EpisodeChapter]()) { result, chapter in
                guard result.last?.startTime != chapter.startTime else { return }
                result.append(chapter)
            }
    }

    static func seconds(from timestamp: String) -> TimeInterval? {
        let parts = timestamp.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        if parts.count == 3 {
            return (parts[0] * 3600) + (parts[1] * 60) + parts[2]
        }
        if parts.count == 2 {
            return (parts[0] * 60) + parts[1]
        }
        return parts[0]
    }
}

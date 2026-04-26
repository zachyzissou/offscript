import Foundation
import SwiftData

@Model
final class Podcast {
    private static let listSeparator = "\u{1F}"

    @Attribute(.unique) var id: UUID
    var title: String
    var author: String?
    var summary: String?
    var feedURL: URL
    var websiteURL: URL?
    var artworkURL: URL?
    private var categoriesStorage: String
    var isSubscribed: Bool
    var subscribedAt: Date?
    var latestPubDate: Date?
    var lastSyncAt: Date?
    var feedETag: String?
    var feedLastModified: String?
    var syncStatus: String

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
    @Attribute(.unique) var id: UUID
    var guid: String
    var title: String
    var summary: String?
    var pubDate: Date
    var duration: TimeInterval?
    var audioURL: URL
    var artworkURL: URL?
    var localFileURL: URL?
    var playedPosition: TimeInterval = 0
    var isPlayed: Bool = false
    var isDownloaded: Bool = false
    var isQueued: Bool = false
    var lastPlayedAt: Date?
    var seasonNumber: Int?
    var episodeNumber: Int?

    var podcast: Podcast

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
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.podcast = podcast
    }
}

@Model
final class QueueItem {
    @Attribute(.unique) var id: UUID
    var createdAt: Date = Date()
    var position: Int
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
        case started, completed, skippedQuickly, seekedForward, seekedBackward
    }

    var date: Date = Date()
    private var kindRawValue: String
    var position: TimeInterval
    var episode: Episode

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
    private var actionRawValue: String
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
    private var preferredGenresStorage: String = ""
    private var topTagsStorage: String = ""
    private var showAffinityStorage: String = ""
    var averageCompletedDurationMinutes: Double = 30
    var prefersShortEpisodes: Bool = false
    var unfinishedEpisodeAffinity: Double = 0
    var lastUpdatedAt: Date = Date()

    init(id: String = "primary") {
        self.id = id
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

    @Attribute(.unique) var episodeID: UUID
    private var tagsStorage: String = ""
    private var entitiesStorage: String = ""
    var summary: String?
    var qualityScore: Double = 0.0
    var confidenceScore: Double = 0.0
    var estimatedListeningContext: String?
    var freshnessBucket: String?
    var introSkipSeconds: TimeInterval = 0
    var outroSkipSeconds: TimeInterval = 0

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

    var episodes: [Episode] {
        scoredEpisodes.map(\.episode)
    }

    func explanation(for episode: Episode) -> String {
        scoredEpisodes.first(where: { $0.episode.id == episode.id })?.explanation ?? "Picked for you"
    }
}

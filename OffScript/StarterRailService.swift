import Foundation
import OSLog
import SwiftData

private let starterRailLogger = Logger(subsystem: "com.offscript", category: "StarterRail")

/// Curated starter podcasts grouped by category. Used for the cold-start
/// Home rail when the user hasn't subscribed to anything yet — the
/// alternative was a dead-end empty state pushing them at Search.
///
/// Curation philosophy: well-loved, broadly accessible shows that hold
/// up over years rather than ride-the-charts trendy picks. One per slot
/// in each section so the rail doesn't feel like an algorithmic feed
/// and the user can tell each was deliberately chosen.
struct StarterPick: Identifiable, Hashable {
    var id: String { feedURL.absoluteString }
    let title: String
    let author: String
    let feedURL: URL
    let summary: String
    let category: StarterCategory
}

enum StarterCategory: String, CaseIterable, Identifiable {
    case news = "News & Culture"
    case tech = "Tech & Design"
    case story = "Story & Reporting"
    case ideas = "Ideas & Conversation"
    case humor = "Humor"

    var id: String { rawValue }

    var label: String { rawValue.uppercased() }
}

enum StarterRailService {
    /// Hand-picked seed list. URLs verified at curation time; if a feed
    /// goes 404 the user gets a per-row failure when they tap subscribe
    /// — `FeedSyncService.importPodcast` surfaces the error inline.
    static let picks: [StarterPick] = [
        // ── News & Culture ─────────────────────────────────────
        .init(
            title: "The Daily",
            author: "The New York Times",
            feedURL: URL(string: "https://feeds.simplecast.com/54nAGcIl")!,
            summary: "Twenty minutes of context on the day's top story.",
            category: .news
        ),
        .init(
            title: "Up First",
            author: "NPR",
            feedURL: URL(string: "https://feeds.npr.org/510318/podcast.xml")!,
            summary: "NPR's morning briefing — the news in 15 minutes.",
            category: .news
        ),
        .init(
            title: "The Ezra Klein Show",
            author: "The New York Times",
            feedURL: URL(string: "https://feeds.simplecast.com/82FI35Px")!,
            summary: "Long-form interviews on politics, ideas, and culture.",
            category: .news
        ),

        // ── Tech & Design ──────────────────────────────────────
        .init(
            title: "Hard Fork",
            author: "The New York Times",
            feedURL: URL(string: "https://feeds.simplecast.com/l2i9YnTd")!,
            summary: "Kevin Roose and Casey Newton on tech's weekly weirdness.",
            category: .tech
        ),
        .init(
            title: "Acquired",
            author: "Ben Gilbert and David Rosenthal",
            feedURL: URL(string: "https://feeds.transistor.fm/acquired")!,
            summary: "Deep, multi-hour breakdowns of legendary companies.",
            category: .tech
        ),
        .init(
            title: "Dithering",
            author: "Ben Thompson and John Gruber",
            feedURL: URL(string: "https://dithering.fireside.fm/rss")!,
            summary: "Fifteen minutes, three times a week, on tech and media.",
            category: .tech
        ),

        // ── Story & Reporting ──────────────────────────────────
        .init(
            title: "This American Life",
            author: "This American Life",
            feedURL: URL(string: "https://feed.thisamericanlife.org/talpodcast")!,
            summary: "Stories about everyday life, told by the people living them.",
            category: .story
        ),
        .init(
            title: "Radiolab",
            author: "WNYC Studios",
            feedURL: URL(string: "https://feeds.simplecast.com/EmVW7VGp")!,
            summary: "Investigations on the boundary of science and storytelling.",
            category: .story
        ),
        .init(
            title: "Serial",
            author: "Serial Productions & The New York Times",
            feedURL: URL(string: "https://feeds.simplecast.com/xl36XBC2")!,
            summary: "One story, told week by week — long-form audio journalism.",
            category: .story
        ),

        // ── Ideas & Conversation ───────────────────────────────
        .init(
            title: "Hidden Brain",
            author: "Hidden Brain Media",
            feedURL: URL(string: "https://feeds.simplecast.com/p1tWKwzO")!,
            summary: "Shankar Vedantam on the unseen patterns in human behavior.",
            category: .ideas
        ),
        .init(
            title: "Conversations with Tyler",
            author: "Mercatus Center at George Mason University",
            feedURL: URL(string: "https://feeds.megaphone.fm/conversationswithtyler")!,
            summary: "Tyler Cowen interviews the most interesting people he can find.",
            category: .ideas
        ),
        .init(
            title: "99% Invisible",
            author: "Roman Mars",
            feedURL: URL(string: "https://feeds.simplecast.com/BqbsxVfO")!,
            summary: "On the unnoticed design that shapes the world.",
            category: .ideas
        ),

        // ── Humor ──────────────────────────────────────────────
        .init(
            title: "Smartless",
            author: "Jason Bateman, Sean Hayes, Will Arnett",
            feedURL: URL(string: "https://feeds.simplecast.com/hNaFxXpO")!,
            summary: "Three friends bring on guests they each pick blind.",
            category: .humor
        ),
        .init(
            title: "Conan O'Brien Needs A Friend",
            author: "Team Coco & Earwolf",
            feedURL: URL(string: "https://feeds.simplecast.com/dHoohVNH")!,
            summary: "Conan invites the comedians and friends he likes most.",
            category: .humor
        )
    ]

    /// Picks grouped by category, in display order. Section ordering is
    /// deliberate — News on top because it's the most universally
    /// useful starting point.
    static var groupedPicks: [(StarterCategory, [StarterPick])] {
        StarterCategory.allCases.map { category in
            (category, picks.filter { $0.category == category })
        }
    }

    /// Convert a starter pick into the same `PodcastSearchResult` shape
    /// the Search-tap and OPML import paths use. Lets cold-start
    /// subscriptions land via the same `FeedSyncService.importPodcast`
    /// pipeline — sync, episode fetch, library row — without a parallel
    /// code path.
    static func searchResult(for pick: StarterPick) -> PodcastSearchResult {
        PodcastSearchResult(
            title: pick.title,
            author: pick.author,
            feedURL: pick.feedURL,
            artworkURL: nil,
            websiteURL: nil,
            summary: pick.summary
        )
    }
}

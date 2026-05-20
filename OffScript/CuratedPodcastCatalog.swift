import Foundation

enum Genre: String, CaseIterable, Identifiable {
    case technology
    case cultureAndSociety
    case comedy
    case trueCrime
    case newsAndPolitics
    case science
    case business
    case healthAndWellness
    case sports
    case music
    case history
    case education

    var id: String { rawValue }

    var title: String {
        switch self {
        case .technology: return "Technology"
        case .cultureAndSociety: return "Culture & Society"
        case .comedy: return "Comedy"
        case .trueCrime: return "True Crime"
        case .newsAndPolitics: return "News & Politics"
        case .science: return "Science"
        case .business: return "Business"
        case .healthAndWellness: return "Health & Wellness"
        case .sports: return "Sports"
        case .music: return "Music"
        case .history: return "History"
        case .education: return "Education"
        }
    }

    var systemImage: String {
        switch self {
        case .technology: return "cpu"
        case .cultureAndSociety: return "globe.americas"
        case .comedy: return "face.smiling"
        case .trueCrime: return "magnifyingglass"
        case .newsAndPolitics: return "newspaper"
        case .science: return "atom"
        case .business: return "chart.line.uptrend.xyaxis"
        case .healthAndWellness: return "heart"
        case .sports: return "sportscourt"
        case .music: return "music.note"
        case .history: return "clock.arrow.circlepath"
        case .education: return "graduationcap"
        }
    }

    var appleGenreID: Int {
        switch self {
        case .technology: return 1318
        case .cultureAndSociety: return 1324
        case .comedy: return 1303
        case .trueCrime: return 1488
        case .newsAndPolitics: return 1489
        case .science: return 1533
        case .business: return 1321
        case .healthAndWellness: return 1512
        case .sports: return 1545
        case .music: return 1310
        case .history: return 1487
        case .education: return 1304
        }
    }
}

enum CuratedPodcastCatalog {
    static var all: [PodcastSearchResult] {
        Genre.allCases.flatMap { podcasts(for: $0) }
    }

    static func podcasts(for genre: Genre) -> [PodcastSearchResult] {
        switch genre {
        case .technology:
            return [
                entry(title: "Lex Fridman Podcast", author: "Lex Fridman", feed: "https://lexfridman.com/feed/podcast/", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/3e/e3/9c/3ee39c89-de08-47a6-7f3d-3849cef6d255/mza_16657851278549137484.png/600x600bb.jpg"),
                entry(title: "Acquired", author: "Ben Gilbert & David Rosenthal", feed: "https://feeds.transistor.fm/acquired", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/d6/e9/f9/d6e9f92c-8f46-a302-f7a2-144cefbd74bf/mza_16135045473976550452.jpg/600x600bb.jpg"),
                entry(title: "The Vergecast", author: "The Verge", feed: "https://feeds.megaphone.fm/vergecast", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/b0/01/c9/b001c98c-aafb-35f0-3db5-fd66e8f74689/mza_5540089112518679483.jpeg/600x600bb.jpg"),
                entry(title: "Accidental Tech Podcast", author: "Marco Arment, Casey Liss, John Siracusa", feed: "https://cdn.atp.fm/rss/public?wtvryzdm", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/91/22/42/9122426f-df98-4302-6ba3-da67b0648e70/mza_5041274938111919910.png/600x600bb.jpg"),
            ]
        case .cultureAndSociety:
            return [
                entry(title: "Radiolab", author: "WNYC Studios", feed: "https://feeds.simplecast.com/EmVW7VGp", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/2b/b2/4d/2bb24d28-f3bb-916f-6bf3-9e125ba5219b/mza_4476298389845914795.jpg/600x600bb.jpg"),
                entry(title: "99% Invisible", author: "Roman Mars", feed: "https://feeds.simplecast.com/BqbsxVfO", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/79/d0/35/79d035ea-9043-b43e-7380-33cd47bd968b/mza_2606971010425550919.jpg/600x600bb.jpg"),
                entry(title: "Freakonomics Radio", author: "Freakonomics Radio + Stitcher", feed: "https://feeds.simplecast.com/Y8lFbOT4", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/f7/0c/c5/f70cc540-ce36-d96f-b111-c970aad5505c/mza_17703422762227531425.jpg/600x600bb.jpg"),
                entry(title: "This American Life", author: "This American Life", feed: "https://www.thisamericanlife.org/podcast/rss.xml", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/64/aa/3a/64aa3a66-a08a-947c-cf21-a5722a1b77ae/mza_11390421932467026234.png/600x600bb.jpg"),
            ]
        case .comedy:
            return [
                entry(title: "Conan O'Brien Needs a Friend", author: "Team Coco & Earwolf", feed: "https://feeds.simplecast.com/dHoohVNH", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/c6/02/8a/c6028ab7-bffd-db83-53e4-34a4ea9bef21/mza_16944101310108746053.jpg/600x600bb.jpg"),
                entry(title: "SmartLess", author: "Jason Bateman, Sean Hayes, Will Arnett", feed: "https://feeds.simplecast.com/hNaFxXpO", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/b1/93/5f/b1935f9f-35be-9144-e813-626bd8dabfb4/mza_4132654708551836825.jpg/600x600bb.jpg"),
                entry(title: "Call Her Daddy", author: "Alex Cooper", feed: "https://feeds.simplecast.com/mKn_QmLS", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/05/10/91/05109145-8c22-5464-1f20-aaedeab769f8/mza_10276081716633787086.jpg/600x600bb.jpg"),
            ]
        case .trueCrime:
            return [
                entry(title: "Serial", author: "Serial Productions & The New York Times", feed: "https://anchor.fm/s/b86ac44/podcast/rss", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/ea/f8/3b/eaf83be3-3814-40a3-2fe4-8f14e352791d/mza_6611732547285221262.jpg/600x600bb.jpg"),
                entry(title: "Crime Junkie", author: "audiochuck", feed: "https://feeds.simplecast.com/qm_9xx0g", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/8c/35/04/8c350430-2fbf-98d0-0a25-00b76550ffeb/mza_13445204151221888086.jpg/600x600bb.jpg"),
                entry(title: "Casefile True Crime", author: "Casefile Presents", feed: "https://feeds.acast.com/public/shows/679acff465f74095106abfaa", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/32/81/a3/3281a345-6fa5-1d0d-b0bc-f02b0850a0ae/mza_17562537467118278179.jpeg/600x600bb.jpg"),
            ]
        case .newsAndPolitics:
            return [
                entry(title: "The Daily", author: "The New York Times", feed: "https://feeds.simplecast.com/Sl5CSM3S", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/ab/64/66/ab6466a9-9a7d-e20e-7a3d-bc5be37d29ce/mza_15084852813176276273.jpg/600x600bb.jpg"),
                entry(title: "Pod Save America", author: "Crooked Media", feed: "https://audioboom.com/channels/5166624.rss", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/44/dc/61/44dc6141-25e9-5bb3-e19e-a2337233d19e/mza_5506771870755587769.jpg/600x600bb.jpg"),
                entry(title: "Up First", author: "NPR", feed: "https://feeds.npr.org/510318/podcast.xml", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/0e/35/25/0e352569-e694-81d9-ea55-5f935981c15a/mza_1788275989855583986.png/600x600bb.jpg"),
            ]
        case .science:
            return [
                entry(title: "Huberman Lab", author: "Scicomm Media", feed: "https://feeds.megaphone.fm/hubermanlab", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/9a/d3/19/9ad31912-0b5a-a16e-2d7c-9fd074698b9c/mza_8994222203629500925.jpg/600x600bb.jpg"),
                entry(title: "StarTalk Radio", author: "Neil deGrasse Tyson", feed: "https://feeds.simplecast.com/4T39_jAj", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/d7/88/9b/d7889bab-dca5-77ba-3d0c-7fae8f16ab11/mza_8810454848871508.jpg/600x600bb.jpg"),
                entry(title: "Science Vs", author: "Spotify Studios", feed: "https://feeds.megaphone.fm/sciencevs", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/af/2b/20/af2b201e-e459-15f3-b158-783b483f3fa7/mza_16606749804494045407.jpg/600x600bb.jpg"),
            ]
        case .business:
            return [
                entry(title: "How I Built This", author: "Guy Raz | Wondery", feed: "https://rss.art19.com/how-i-built-this", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/64/45/06/644506b5-c44f-f661-f74e-f63a4b2511bc/mza_14892199991035639268.jpeg/600x600bb.jpg"),
                entry(title: "The Prof G Pod", author: "Vox Media Podcast Network", feed: "https://feeds.megaphone.fm/WWO6655869236", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/f7/e6/40/f7e640c7-3ea8-c60d-5d7b-6b68a3b3fa19/mza_5307779437984707627.jpg/600x600bb.jpg"),
                entry(title: "Masters of Scale", author: "WaitWhat", feed: "https://rss.art19.com/masters-of-scale", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/13/4b/81/134b8173-d713-cbb2-2d3b-4a8692bd87c0/mza_996010941061703843.jpeg/600x600bb.jpg"),
            ]
        case .healthAndWellness:
            return [
                entry(title: "The Peter Attia Drive", author: "Peter Attia, MD", feed: "https://rss.libsyn.com/shows/121729/destinations/713489.xml", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/89/b8/c0/89b8c0bb-f65c-66ef-8b96-fffea8f0cf5f/mza_872007510196734520.png/600x600bb.jpg"),
                entry(title: "Ten Percent Happier", author: "Dan Harris", feed: "https://rss.libsyn.com/shows/570160/destinations/4933335.xml", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/38/7c/a1/387ca10e-09cb-2560-726e-c45f9b907ce1/mza_4065376718212434894.jpg/600x600bb.jpg"),
                entry(title: "On Purpose with Jay Shetty", author: "Jay Shetty", feed: "https://www.omnycontent.com/d/playlist/e73c998e-6e60-432f-8610-ae210140c5b1/32f1779e-bc01-4d36-89e6-afcb01070c82/e0c8382f-48d4-42bb-89d5-afcb01075cb4/podcast.rss", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/5e/a1/69/5ea169e2-18c4-40b0-0982-2fda3476d9a4/mza_9372864784596222041.jpg/600x600bb.jpg"),
            ]
        case .sports:
            return [
                entry(title: "The Bill Simmons Podcast", author: "The Ringer", feed: "https://feeds.megaphone.fm/the-bill-simmons-podcast", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/22/ca/58/22ca58e3-6aa9-ab35-b900-c715ddee0d3f/mza_6881305964363479864.jpg/600x600bb.jpg"),
                entry(title: "New Heights", author: "Wave Sports + Entertainment", feed: "https://rss.art19.com/new-heights", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/97/ea/30/97ea30ac-49bb-540c-4237-315c149e8f35/mza_1529156993721596171.jpeg/600x600bb.jpg"),
            ]
        case .music:
            return [
                entry(title: "Dissect", author: "Spotify Studios", feed: "https://feeds.megaphone.fm/dissectwide", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/3e/d8/f5/3ed8f5f4-4113-9049-ddf9-6900d2d2969d/mza_6863756797238193337.jpg/600x600bb.jpg"),
                entry(title: "Song Exploder", author: "Hrishikesh Hirway", feed: "https://feed.songexploder.net/SongExploder", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/05/7b/35/057b3588-c74c-0334-d8ef-c6b8166d4afc/mza_12324100546486323942.jpg/600x600bb.jpg"),
                entry(title: "Broken Record", author: "Pushkin Industries", feed: "https://www.omnycontent.com/d/playlist/e73c998e-6e60-432f-8610-ae210140c5b1/ff0ba2f2-f33c-4193-aba2-ae32006cd633/11c188a1-cb86-4869-9c57-ae32006cd63c/podcast.rss", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/e1/e2/8e/e1e28ee7-c7ed-9a91-dbdf-0bac03b6fa38/mza_12090824434324250279.jpg/600x600bb.jpg"),
            ]
        case .history:
            return [
                entry(title: "Hardcore History", author: "Dan Carlin", feed: "https://feeds.feedburner.com/dancarlin/history?format=xml", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/49/b7/eb/49b7eb32-8f08-6fac-aadb-2f002131fe5f/mza_15196161972010256532.jpg/600x600bb.jpg"),
                entry(title: "Revisionist History", author: "Pushkin Industries", feed: "https://www.omnycontent.com/d/playlist/e73c998e-6e60-432f-8610-ae210140c5b1/0e563f45-9d14-4ce8-8ef0-ae32006cd7e7/0d4cc74d-fff7-4b89-8818-ae32006cd7f0/podcast.rss", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/a0/7f/c9/a07fc9da-34db-7247-3f7f-c89e18402e8a/mza_14499328907997822509.jpg/600x600bb.jpg"),
                entry(title: "The Rest Is History", author: "Goalhanger Podcasts", feed: "https://feeds.megaphone.fm/GLT4787413333", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/b3/8c/50/b38c507b-d4a2-b552-dd2e-894f48493653/mza_8804981712034613158.jpg/600x600bb.jpg"),
            ]
        case .education:
            return [
                entry(title: "TED Radio Hour", author: "NPR", feed: "https://feeds.npr.org/510298/podcast.xml", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/94/ea/88/94ea8879-e7f2-378c-231c-c041c7b295b5/mza_9110350352446077100.jpg/600x600bb.jpg"),
                entry(title: "Hidden Brain", author: "Shankar Vedantam", feed: "https://feeds.simplecast.com/kwWc0lhf", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/d9/97/f0/d997f0f5-284b-b90c-16f6-e2e675b831b3/mza_3280114077256997969.jpg/600x600bb.jpg"),
                entry(title: "Stuff You Should Know", author: "iHeartPodcasts", feed: "https://www.omnycontent.com/d/playlist/e73c998e-6e60-432f-8610-ae210140c5b1/a91018a4-ea4f-4130-bf55-ae270180c327/44710ecc-10bb-48d1-93c7-ae270180c33e/podcast.rss", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/aa/82/91/aa82912f-23ee-6f6a-583c-a4e993164d0e/mza_12111158076643383507.jpg/600x600bb.jpg"),
            ]
        }
    }

    private static func entry(title: String, author: String, feed: String, artwork: String) -> PodcastSearchResult {
        PodcastSearchResult(
            title: title,
            author: author,
            feedURL: URL(string: feed)!,
            artworkURL: URL(string: artwork),
            websiteURL: nil,
            summary: nil
        )
    }
}

// MARK: - Editorial collections
//
// Curator-shaped groupings layered over the per-genre catalog. Unlike a
// flat genre rail, an editorial collection is a *named viewpoint* — "Just
// under an hour", "Storytelling that earns its length" — that lets a
// listener pick a mood instead of a band.
//
// Membership is declared as a `Filter` predicate. The predicate is
// declarative on purpose: it composes (intersection via `.combined`) and
// it's testable in isolation. The candidate it operates on is a
// `CuratedEntry` — a thin enrichment of `PodcastSearchResult` that carries
// the editorial metadata the curator knows but the search-result struct
// doesn't expose (typical episode duration, the entry's home genre, and a
// small set of curator-attached keywords).
//
// Duration metadata here is the *curator's* call, not a measurement. The
// `SearchPreviewLoader` shipped in Phase 17 surfaces real per-show
// durations at runtime, and a future cycle can swap this estimate for the
// measured value — the `Filter.duration` shape is already correct for
// that.

struct CuratedEntry: Hashable, Sendable {
    let result: PodcastSearchResult
    let genre: Genre
    /// Curator's estimate of typical episode length. `nil` when the show
    /// varies wildly (mini + full episodes) and a single bucket would
    /// mislead.
    let typicalDuration: ClosedRange<TimeInterval>?
    /// Curator-attached keywords, lowercased. Used by `Filter.keywords` for
    /// editorial collections that cut across genres (e.g. "interview",
    /// "running", "introductory").
    let keywords: Set<String>
}

struct EditorialCollection: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let curatorNote: String?
    let filter: Filter

    enum Filter: Hashable, Sendable {
        case duration(min: TimeInterval?, max: TimeInterval?)
        case genres([Genre])
        case keywords([String])
        indirect case combined([Filter])

        func matches(_ candidate: CuratedEntry) -> Bool {
            switch self {
            case let .duration(minDuration, maxDuration):
                guard let range = candidate.typicalDuration else { return false }
                if let minDuration, range.upperBound < minDuration { return false }
                if let maxDuration, range.lowerBound > maxDuration { return false }
                return true

            case let .genres(allowed):
                return allowed.contains(candidate.genre)

            case let .keywords(needles):
                let lowered = needles.map { $0.lowercased() }
                return lowered.contains(where: candidate.keywords.contains)

            case let .combined(filters):
                return filters.allSatisfy { $0.matches(candidate) }
            }
        }
    }
}

extension CuratedPodcastCatalog {
    /// Every curated entry across all bands, in catalog order. Editorial
    /// collections filter over this list — they never touch live search.
    static var entries: [CuratedEntry] {
        Genre.allCases.flatMap { curatedEntries(for: $0) }
    }

    /// All starter editorial collections, in surface order. Kept small (5-8)
    /// on purpose: an editorial collection should be a real curator pick, not
    /// a thin slice of the catalog. Add a collection only when it answers a
    /// question a listener would actually ask out loud.
    static var editorialCollections: [EditorialCollection] {
        [
            EditorialCollection(
                id: "just-under-an-hour",
                title: "Just under an hour",
                subtitle: "Pick one for a commute",
                curatorNote: "Sized to fit a drive home without spilling into the next day.",
                filter: .duration(min: 45 * 60, max: 65 * 60)
            ),
            EditorialCollection(
                id: "long-form-interviews",
                title: "Long-form interviews",
                subtitle: "Settle in",
                curatorNote: "When the conversation is the point, not the length.",
                filter: .combined([
                    .duration(min: 90 * 60, max: nil),
                    .keywords(["interview"])
                ])
            ),
            EditorialCollection(
                id: "news-on-the-go",
                title: "News on the go",
                subtitle: "Under 25 minutes",
                curatorNote: "Get the day down without losing the morning.",
                filter: .combined([
                    .duration(min: nil, max: 25 * 60),
                    .genres([.newsAndPolitics])
                ])
            ),
            EditorialCollection(
                id: "for-new-listeners",
                title: "For new listeners",
                subtitle: "Names you'll recognize",
                curatorNote: "Easy doors in. Each one has a back catalog worth the time.",
                filter: .keywords(["introductory"])
            ),
            EditorialCollection(
                id: "storytelling",
                title: "Storytelling",
                subtitle: "Reporting that reads like fiction",
                curatorNote: "Tape-rich, scripted, edited to hold attention.",
                filter: .keywords(["storytelling"])
            ),
            EditorialCollection(
                id: "hands-free-workouts",
                title: "Hands-free workouts",
                subtitle: "Pace yourself",
                curatorNote: "Long enough for a run, short enough not to drag.",
                filter: .combined([
                    .duration(min: 30 * 60, max: 50 * 60),
                    .keywords(["fitness", "running", "training"])
                ])
            ),
        ]
    }

    /// Returns the resolved curated entries that pass the collection's
    /// filter, in catalog order.
    static func resolve(_ collection: EditorialCollection) -> [CuratedEntry] {
        entries.filter { collection.filter.matches($0) }
    }

    static func curatedEntries(for genre: Genre) -> [CuratedEntry] {
        switch genre {
        case .technology:
            return [
                .init(result: podcasts(for: .technology)[0], genre: .technology,
                      typicalDuration: 120 * 60 ... 240 * 60,
                      keywords: ["interview", "introductory"]),
                .init(result: podcasts(for: .technology)[1], genre: .technology,
                      typicalDuration: 180 * 60 ... 300 * 60,
                      keywords: ["interview", "storytelling"]),
                .init(result: podcasts(for: .technology)[2], genre: .technology,
                      typicalDuration: 60 * 60 ... 90 * 60,
                      keywords: ["introductory"]),
                .init(result: podcasts(for: .technology)[3], genre: .technology,
                      typicalDuration: 90 * 60 ... 150 * 60,
                      keywords: []),
            ]
        case .cultureAndSociety:
            return [
                .init(result: podcasts(for: .cultureAndSociety)[0], genre: .cultureAndSociety,
                      typicalDuration: 45 * 60 ... 70 * 60,
                      keywords: ["storytelling", "introductory"]),
                .init(result: podcasts(for: .cultureAndSociety)[1], genre: .cultureAndSociety,
                      typicalDuration: 30 * 60 ... 50 * 60,
                      keywords: ["storytelling", "introductory"]),
                .init(result: podcasts(for: .cultureAndSociety)[2], genre: .cultureAndSociety,
                      typicalDuration: 40 * 60 ... 65 * 60,
                      keywords: ["introductory"]),
                .init(result: podcasts(for: .cultureAndSociety)[3], genre: .cultureAndSociety,
                      typicalDuration: 50 * 60 ... 65 * 60,
                      keywords: ["storytelling", "introductory"]),
            ]
        case .comedy:
            return [
                .init(result: podcasts(for: .comedy)[0], genre: .comedy,
                      typicalDuration: 70 * 60 ... 110 * 60,
                      keywords: ["interview", "introductory"]),
                .init(result: podcasts(for: .comedy)[1], genre: .comedy,
                      typicalDuration: 60 * 60 ... 80 * 60,
                      keywords: ["interview"]),
                .init(result: podcasts(for: .comedy)[2], genre: .comedy,
                      typicalDuration: 50 * 60 ... 80 * 60,
                      keywords: ["interview"]),
            ]
        case .trueCrime:
            return [
                .init(result: podcasts(for: .trueCrime)[0], genre: .trueCrime,
                      typicalDuration: 40 * 60 ... 60 * 60,
                      keywords: ["storytelling", "introductory"]),
                .init(result: podcasts(for: .trueCrime)[1], genre: .trueCrime,
                      typicalDuration: 35 * 60 ... 55 * 60,
                      keywords: ["storytelling"]),
                .init(result: podcasts(for: .trueCrime)[2], genre: .trueCrime,
                      typicalDuration: 60 * 60 ... 90 * 60,
                      keywords: ["storytelling"]),
            ]
        case .newsAndPolitics:
            return [
                .init(result: podcasts(for: .newsAndPolitics)[0], genre: .newsAndPolitics,
                      typicalDuration: 20 * 60 ... 35 * 60,
                      keywords: ["introductory"]),
                .init(result: podcasts(for: .newsAndPolitics)[1], genre: .newsAndPolitics,
                      typicalDuration: 60 * 60 ... 90 * 60,
                      keywords: []),
                .init(result: podcasts(for: .newsAndPolitics)[2], genre: .newsAndPolitics,
                      typicalDuration: 10 * 60 ... 18 * 60,
                      keywords: ["introductory"]),
            ]
        case .science:
            return [
                .init(result: podcasts(for: .science)[0], genre: .science,
                      typicalDuration: 120 * 60 ... 180 * 60,
                      keywords: ["interview", "introductory"]),
                .init(result: podcasts(for: .science)[1], genre: .science,
                      typicalDuration: 45 * 60 ... 60 * 60,
                      keywords: ["interview", "introductory"]),
                .init(result: podcasts(for: .science)[2], genre: .science,
                      typicalDuration: 25 * 60 ... 40 * 60,
                      keywords: ["introductory"]),
            ]
        case .business:
            return [
                .init(result: podcasts(for: .business)[0], genre: .business,
                      typicalDuration: 60 * 60 ... 80 * 60,
                      keywords: ["interview", "storytelling", "introductory"]),
                .init(result: podcasts(for: .business)[1], genre: .business,
                      typicalDuration: 45 * 60 ... 70 * 60,
                      keywords: ["interview"]),
                .init(result: podcasts(for: .business)[2], genre: .business,
                      typicalDuration: 30 * 60 ... 50 * 60,
                      keywords: ["interview"]),
            ]
        case .healthAndWellness:
            return [
                .init(result: podcasts(for: .healthAndWellness)[0], genre: .healthAndWellness,
                      typicalDuration: 90 * 60 ... 180 * 60,
                      keywords: ["interview", "fitness", "training"]),
                .init(result: podcasts(for: .healthAndWellness)[1], genre: .healthAndWellness,
                      typicalDuration: 30 * 60 ... 50 * 60,
                      keywords: ["introductory"]),
                .init(result: podcasts(for: .healthAndWellness)[2], genre: .healthAndWellness,
                      typicalDuration: 40 * 60 ... 70 * 60,
                      keywords: ["interview", "introductory"]),
            ]
        case .sports:
            return [
                .init(result: podcasts(for: .sports)[0], genre: .sports,
                      typicalDuration: 90 * 60 ... 150 * 60,
                      keywords: ["interview"]),
                .init(result: podcasts(for: .sports)[1], genre: .sports,
                      typicalDuration: 70 * 60 ... 110 * 60,
                      keywords: ["interview"]),
            ]
        case .music:
            return [
                .init(result: podcasts(for: .music)[0], genre: .music,
                      typicalDuration: 35 * 60 ... 50 * 60,
                      keywords: ["storytelling"]),
                .init(result: podcasts(for: .music)[1], genre: .music,
                      typicalDuration: 20 * 60 ... 30 * 60,
                      keywords: ["storytelling", "introductory"]),
                .init(result: podcasts(for: .music)[2], genre: .music,
                      typicalDuration: 60 * 60 ... 90 * 60,
                      keywords: ["interview"]),
            ]
        case .history:
            return [
                .init(result: podcasts(for: .history)[0], genre: .history,
                      typicalDuration: 240 * 60 ... 360 * 60,
                      keywords: ["storytelling"]),
                .init(result: podcasts(for: .history)[1], genre: .history,
                      typicalDuration: 35 * 60 ... 55 * 60,
                      keywords: ["storytelling", "introductory"]),
                .init(result: podcasts(for: .history)[2], genre: .history,
                      typicalDuration: 50 * 60 ... 70 * 60,
                      keywords: ["storytelling", "introductory"]),
            ]
        case .education:
            return [
                .init(result: podcasts(for: .education)[0], genre: .education,
                      typicalDuration: 45 * 60 ... 60 * 60,
                      keywords: ["interview", "introductory"]),
                .init(result: podcasts(for: .education)[1], genre: .education,
                      typicalDuration: 40 * 60 ... 55 * 60,
                      keywords: ["storytelling", "introductory"]),
                .init(result: podcasts(for: .education)[2], genre: .education,
                      typicalDuration: 40 * 60 ... 60 * 60,
                      keywords: ["introductory"]),
            ]
        }
    }
}

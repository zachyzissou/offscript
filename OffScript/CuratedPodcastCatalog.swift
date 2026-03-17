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
                entry(title: "Lex Fridman Podcast", author: "Lex Fridman", feed: "https://lexfridman.com/feed/podcast/", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts125/v4/c3/9d/e3/c39de370-3dfc-2a36-0a0d-09da0f0f2fb5/mza_7055951557267025897.jpg/600x600bb.jpg"),
                entry(title: "Acquired", author: "Ben Gilbert & David Rosenthal", feed: "https://feeds.pacific-content.com/acquired", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/a2/ab/fd/a2abfdb0-a0c4-1aab-400a-2a57a6d1a498/mza_10068498047498498498.jpg/600x600bb.jpg"),
                entry(title: "The Vergecast", author: "The Verge", feed: "https://feeds.megaphone.fm/vergecast", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/3d/f0/2c/3df02cdb-e857-3c3c-3f37-a0a3c1fba498/mza_17343223853483629612.jpg/600x600bb.jpg"),
                entry(title: "Accidental Tech Podcast", author: "Marco Arment, Casey Liss, John Siracusa", feed: "https://atp.fm/episodes?format=rss", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/20/42/52/204252e6-0b74-5fa5-3e65-8c64b5f2f93c/mza_8438045701290662498.png/600x600bb.jpg"),
            ]
        case .cultureAndSociety:
            return [
                entry(title: "Radiolab", author: "WNYC Studios", feed: "https://feeds.simplecast.com/EmVW7VGp", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/91/3d/e5/913de51c-9358-8a99-5a82-99a2c3e5d7e9/mza_15932833847498327798.jpg/600x600bb.jpg"),
                entry(title: "99% Invisible", author: "Roman Mars", feed: "https://feeds.simplecast.com/BqbsxVfO", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/2b/69/d7/2b69d7e5-62c3-97ba-a4de-61e0e5acf5d4/mza_9289093033793017447.jpg/600x600bb.jpg"),
                entry(title: "Freakonomics Radio", author: "Freakonomics Radio + Stitcher", feed: "https://feeds.simplecast.com/Y8lFbOT4", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts125/v4/9a/55/75/9a5575e0-4af5-ab29-7894-5d6c0b3cd55e/mza_7565089999152753446.jpg/600x600bb.jpg"),
                entry(title: "This American Life", author: "This American Life", feed: "https://www.thisamericanlife.org/podcast/rss.xml", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/41/87/4e/41874eed-6b53-3e75-f2a0-d0188a6bf3f5/mza_5763994068438908376.jpg/600x600bb.jpg"),
            ]
        case .comedy:
            return [
                entry(title: "Conan O'Brien Needs a Friend", author: "Team Coco & Earwolf", feed: "https://feeds.simplecast.com/dHoohVNH", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/4e/c8/72/4ec87247-8e49-6b73-1be3-a3e6b3b5adf7/mza_3340978315797574212.jpg/600x600bb.jpg"),
                entry(title: "SmartLess", author: "Jason Bateman, Sean Hayes, Will Arnett", feed: "https://feeds.simplecast.com/zt3mMlMD", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/d7/d6/51/d7d651b6-5cb0-ae64-adc1-eb5dc13e2780/mza_16991829328888412991.jpg/600x600bb.jpg"),
                entry(title: "Pardon My Take", author: "Barstool Sports", feed: "https://mcsorleys.barstoolsports.com/feed/pardon-my-take", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/e8/5b/c1/e85bc167-3945-1b08-7526-e7c0cf73c14a/mza_2987826474137463792.jpg/600x600bb.jpg"),
            ]
        case .trueCrime:
            return [
                entry(title: "Serial", author: "Serial Productions & The New York Times", feed: "https://feeds.simplecast.com/xl36XBC2", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/30/a8/5b/30a85b9e-1dfe-0a74-5d8a-2c4e0fbfb157/mza_10796879403498698704.jpg/600x600bb.jpg"),
                entry(title: "Crime Junkie", author: "audiochuck", feed: "https://feeds.simplecast.com/qm_9xx0g", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/d7/c0/34/d7c03431-1bbd-d73a-33ef-fd3337b2b3fb/mza_3052451586876927082.jpg/600x600bb.jpg"),
                entry(title: "Casefile True Crime", author: "Casefile Presents", feed: "https://audioboom.com/channels/4998987.rss", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/28/d1/61/28d16155-eda0-0e5a-fa48-b1fa16c9e5ba/mza_15483003543698968893.jpg/600x600bb.jpg"),
            ]
        case .newsAndPolitics:
            return [
                entry(title: "The Daily", author: "The New York Times", feed: "https://feeds.simplecast.com/54nAGcIl", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/43/47/31/434731c3-6e64-3d4f-b809-f5e3f0d3ab42/mza_9085813861285268024.jpg/600x600bb.jpg"),
                entry(title: "Pod Save America", author: "Crooked Media", feed: "https://feeds.megaphone.fm/pod-save-america", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/4a/72/90/4a7290e4-dcfd-1a81-3f08-dfd0c5fc4d22/mza_12018119764198490497.jpg/600x600bb.jpg"),
                entry(title: "Up First", author: "NPR", feed: "https://feeds.npr.org/510318/podcast.xml", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/56/6f/7f/566f7f50-2d70-5c3a-2b4e-78a78f953e94/mza_15491610645704370757.jpg/600x600bb.jpg"),
            ]
        case .science:
            return [
                entry(title: "Huberman Lab", author: "Scicomm Media", feed: "https://feeds.megaphone.fm/hubermanlab", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/3e/3f/7c/3e3f7c42-6a32-98df-8c25-e48eb9c0a9ee/mza_15060074375674713297.jpg/600x600bb.jpg"),
                entry(title: "StarTalk Radio", author: "Neil deGrasse Tyson", feed: "https://feeds.simplecast.com/4T39_jAj", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts125/v4/72/c2/8c/72c28c24-73d5-b8b5-e83b-c2b19fcdcfbf/mza_6985883752087901871.jpg/600x600bb.jpg"),
                entry(title: "Science Vs", author: "Spotify Studios", feed: "https://feeds.megaphone.fm/sciencevs", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/ee/c9/f3/eec9f3b7-c8e0-06f8-7ee5-d4cd11d00d26/mza_12741548736685082927.jpg/600x600bb.jpg"),
            ]
        case .business:
            return [
                entry(title: "How I Built This", author: "Guy Raz | Wondery", feed: "https://feeds.npr.org/510313/podcast.xml", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/2e/41/5c/2e415c44-f9a6-f63c-7c93-a2f3e4b7f8c8/mza_14175099654781143544.jpg/600x600bb.jpg"),
                entry(title: "The Prof G Pod", author: "Vox Media Podcast Network", feed: "https://feeds.megaphone.fm/profgpod", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/fa/da/70/fada700a-e80f-3b7c-3e37-bf53d0c1db72/mza_11479685143587654563.jpg/600x600bb.jpg"),
                entry(title: "Masters of Scale", author: "WaitWhat", feed: "https://rss.art19.com/masters-of-scale", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/a0/d5/1a/a0d51a51-b2fc-3f29-6a04-dbd55f52a1df/mza_13879992792979527808.jpg/600x600bb.jpg"),
            ]
        case .healthAndWellness:
            return [
                entry(title: "The Peter Attia Drive", author: "Peter Attia, MD", feed: "https://peterattiadrive.libsyn.com/rss", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/14/37/de/1437de33-2d80-a8e1-df4f-9aa5d0f0fa3a/mza_11994272752327478347.jpg/600x600bb.jpg"),
                entry(title: "Ten Percent Happier", author: "Dan Harris", feed: "https://feeds.megaphone.fm/ten-percent-happier", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/4c/e4/31/4ce431c5-d7c0-6e7c-d7a0-5c97f3fb7417/mza_7085935429645287174.jpg/600x600bb.jpg"),
                entry(title: "On Purpose with Jay Shetty", author: "Jay Shetty", feed: "https://feeds.simplecast.com/xRbIdeRv", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/68/3c/c4/683cc4eb-6d79-e382-ed64-6c787e7e8a93/mza_12990568032890389939.jpg/600x600bb.jpg"),
            ]
        case .sports:
            return [
                entry(title: "The Bill Simmons Podcast", author: "The Ringer", feed: "https://feeds.megaphone.fm/the-bill-simmons-podcast", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/38/4a/f0/384af066-76b6-b2d6-0e37-c1a3c2bf7c59/mza_4920670993482505526.jpg/600x600bb.jpg"),
                entry(title: "New Heights", author: "Wave Sports + Entertainment", feed: "https://feeds.megaphone.fm/new-heights", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/be/75/b0/be75b0c0-0adf-3d22-3f00-58e87d7aed76/mza_14979479490899677635.jpg/600x600bb.jpg"),
            ]
        case .music:
            return [
                entry(title: "Dissect", author: "Spotify Studios", feed: "https://feeds.megaphone.fm/dissect", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/3f/c5/1c/3fc51c60-61e6-e8ab-8ab1-9cf6f6b6cbf3/mza_3459975193367749249.jpg/600x600bb.jpg"),
                entry(title: "Song Exploder", author: "Hrishikesh Hirway", feed: "https://feed.songexploder.net/SongExploder", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/90/34/6f/90346f64-d5b6-fc1c-4e28-ad6f2a60aa5e/mza_15087641671946791407.jpg/600x600bb.jpg"),
                entry(title: "Broken Record", author: "Pushkin Industries", feed: "https://feeds.megaphone.fm/broken-record", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/a0/71/39/a0713904-0b3a-8e68-c795-e53bc7f2d08b/mza_4775695803207862497.jpg/600x600bb.jpg"),
            ]
        case .history:
            return [
                entry(title: "Hardcore History", author: "Dan Carlin", feed: "https://feeds.feedburner.com/dancarlin/history", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts125/v4/5e/35/03/5e350305-0845-7eaa-0c92-b1b5d5d38cbe/mza_12567987073499596219.jpg/600x600bb.jpg"),
                entry(title: "Revisionist History", author: "Pushkin Industries", feed: "https://feeds.megaphone.fm/revisionisthistory", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts125/v4/68/62/7f/68627fda-0dd7-b8f7-b6a3-c27e04e9f9ec/mza_17291218380425000798.jpg/600x600bb.jpg"),
                entry(title: "The Rest Is History", author: "Goalhanger Podcasts", feed: "https://feeds.megaphone.fm/the-rest-is-history", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/f6/73/b0/f673b02c-1a94-6caa-c4d3-03ea0d26ac27/mza_12636953965508907982.jpg/600x600bb.jpg"),
            ]
        case .education:
            return [
                entry(title: "TED Radio Hour", author: "NPR", feed: "https://feeds.npr.org/510298/podcast.xml", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/49/a6/05/49a60584-5a3c-af67-0262-ff5fb3079370/mza_16853948296583403669.jpg/600x600bb.jpg"),
                entry(title: "Hidden Brain", author: "Shankar Vedantam", feed: "https://feeds.simplecast.com/kwWc0lhf", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/06/f5/74/06f574c7-a575-52c0-c4d1-a7cfe2addc07/mza_16375498632764614517.jpg/600x600bb.jpg"),
                entry(title: "Stuff You Should Know", author: "iHeartPodcasts", feed: "https://feeds.megaphone.fm/stuffyoushouldknow", artwork: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/59/e3/fc/59e3fc55-b0ca-3b00-8242-d06f1bbd9338/mza_13487802947062498030.jpg/600x600bb.jpg"),
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

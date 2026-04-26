#if DEBUG
import Foundation
import SwiftData

/// Seeds a small set of placeholder podcasts + episodes so the simulator can
/// be screenshot-tested without subscribing to real feeds. Triggered when
/// `offscript.debugSeedSample` is set in UserDefaults.
@MainActor
enum DebugSeedData {
    static func seedIfNeeded(in context: ModelContext) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "offscript.debugSeedSample") else { return }

        let descriptor = FetchDescriptor<Podcast>()
        if let existing = try? context.fetchCount(descriptor), existing > 0 {
            return
        }

        struct Seed {
            let title: String
            let author: String
            let categories: [String]
            let artworkURL: String
            let episodes: [(title: String, summary: String, ageDays: Int, durationMin: Int, played: Double)]
        }

        let seeds: [Seed] = [
            Seed(
                title: "Conan O'Brien Needs A Friend",
                author: "Team Coco & Earwolf",
                categories: ["Comedy", "Interviews"],
                artworkURL: "https://image.simplecastcdn.com/images/c5fdc196-4bbc-4d6e-bd64-9f86fea4c2ac/d5c91e72-69b0-4e9d-93b3-4e07c79f3c0b/3000x3000/coco-needs-a-friend-itunes-art-9.jpg",
                episodes: [
                    ("The State Of The Entertainment Business With Jeff Ross",
                     "Conan and longtime friend Jeff Ross sit down to talk about the brutal honest state of late night, why every entertainer is rebuilding their careers from scratch, and the comedy community's response to a very strange year.",
                     3, 64, 0.36),
                    ("Sarah Silverman Returns",
                     "Sarah Silverman drops back in for a wide ranging conversation about her parents, her standup specials, and what makes a friend a friend.",
                     8, 71, 0),
                    ("Will Ferrell Has A Cold",
                     "Will Ferrell joins the show with the world's worst sinus infection and somehow still becomes the funniest guest of the year.",
                     14, 58, 1)
                ]
            ),
            Seed(
                title: "Hard Fork",
                author: "The New York Times",
                categories: ["Technology", "News"],
                artworkURL: "https://image.simplecastcdn.com/images/d6c7d7ec/d6c7d7ec-2e74-4cb3-aef2-34e4c20f5fdd/3000x3000/hard-fork-album-art.jpg",
                episodes: [
                    ("The AI Bubble Conversation Nobody Wants To Have",
                     "Kevin and Casey debate whether the current AI investment cycle resembles the dot com bubble, what a soft landing would look like, and the hidden infrastructure costs nobody is reporting.",
                     1, 47, 0.78),
                    ("Apple Intelligence Year Two",
                     "A year in, what's actually working in Apple Intelligence — and what shipped half-baked. Plus, an off the record call with a frustrated Apple engineer.",
                     5, 52, 0)
                ]
            ),
            Seed(
                title: "Freakonomics Radio",
                author: "Stephen J. Dubner",
                categories: ["Society & Culture", "Business"],
                artworkURL: "https://image.simplecastcdn.com/images/9e4c1c1f/9e4c1c1f-9e88-4c0a-b0c9-1a2b3c4d5e6f/3000x3000/freakonomics-radio.jpg",
                episodes: [
                    ("672. What Makes Judy Faulkner Run?",
                     "Inside the head of the most powerful person in American healthcare you've never heard of — Epic Systems CEO Judy Faulkner.",
                     2, 60, 0)
                ]
            ),
            Seed(
                title: "Radiolab",
                author: "WNYC Studios",
                categories: ["Science", "Documentary"],
                artworkURL: "https://image.simplecastcdn.com/images/b2c3d4e5/b2c3d4e5-1a2b-3c4d-5e6f-7a8b9c0d1e2f/3000x3000/radiolab.jpg",
                episodes: [
                    ("Forests on Forests",
                     "What happens when a forest grows on top of a forest? A search through the forgotten layers of life that keep modern ecosystems standing.",
                     6, 39, 0.69)
                ]
            )
        ]

        for seed in seeds {
            let podcast = Podcast(
                title: seed.title,
                author: seed.author,
                summary: nil,
                feedURL: URL(string: "https://example.com/\(UUID().uuidString)")!,
                artworkURL: URL(string: seed.artworkURL),
                categories: seed.categories,
                isSubscribed: true
            )
            podcast.subscribedAt = .now
            podcast.latestPubDate = .now
            context.insert(podcast)

            for episode in seed.episodes {
                let pub = Date.now.addingTimeInterval(-Double(episode.ageDays * 24 * 60 * 60))
                let duration = TimeInterval(episode.durationMin * 60)

                let ep = Episode(
                    guid: UUID().uuidString,
                    title: episode.title,
                    summary: episode.summary,
                    pubDate: pub,
                    duration: duration,
                    audioURL: URL(string: "https://example.com/\(UUID().uuidString).mp3")!,
                    podcast: podcast
                )
                ep.playedPosition = duration * episode.played
                ep.isPlayed = episode.played >= 0.95
                context.insert(ep)
            }
        }

        // Stack a couple onto the queue
        let episodeDescriptor = FetchDescriptor<Episode>(
            sortBy: [SortDescriptor(\Episode.pubDate, order: .reverse)]
        )
        if let episodes = try? context.fetch(episodeDescriptor) {
            for (index, episode) in episodes.prefix(3).enumerated() {
                let item = QueueItem(episode: episode, position: index)
                episode.isQueued = true
                context.insert(item)
            }
        }

        try? context.save()
    }
}
#endif

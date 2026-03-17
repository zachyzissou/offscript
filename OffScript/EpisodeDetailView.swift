import SwiftData
import SwiftUI

struct EpisodeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var player = PlaybackController.shared
    let episode: Episode

    private var progressValue: Double {
        guard let duration = episode.duration, duration > 0 else { return 0 }
        return episode.playedPosition / duration
    }

    private var isCurrentlyPlaying: Bool {
        player.currentEpisode?.id == episode.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                HStack(alignment: .top, spacing: 18) {
                    OffScriptArtworkView(
                        url: episode.artworkURL ?? episode.podcast.artworkURL,
                        cornerRadius: OffScriptTheme.Radius.large
                    )
                    .frame(width: 122, height: 122)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(episode.podcast.title.uppercased())
                            .font(.offscriptMicro.weight(.semibold))
                            .foregroundStyle(Color.offscriptAccent)

                        Text(episode.title)
                            .font(.offscriptDisplay)
                            .foregroundStyle(Color.offscriptTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            Label(metadata, systemImage: "clock")
                                .font(.offscriptMeta)
                                .foregroundStyle(Color.offscriptTextMuted)
                        }

                        HStack(spacing: 8) {
                            if episode.isPlayed {
                                OffScriptReasonBadge(text: "Played")
                            } else if episode.playedPosition > 0 {
                                OffScriptReasonBadge(text: "In progress")
                            }
                            if episode.isQueued {
                                OffScriptReasonBadge(text: "Queued")
                            }
                        }
                    }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)

                if progressValue > 0, !episode.isPlayed {
                    VStack(alignment: .leading, spacing: 8) {
                        OffScriptProgressBar(value: progressValue, height: 6)
                        Text(timeRemaining)
                            .font(.offscriptMeta)
                            .foregroundStyle(Color.offscriptTextMuted)
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                }

                HStack(spacing: 10) {
                    Button(isCurrentlyPlaying ? "Now Playing" : (episode.playedPosition > 0 ? "Resume" : "Play")) {
                        PlaybackController.shared.play(episode, in: modelContext)
                    }
                    .buttonStyle(PrimaryPillButtonStyle())
                    .disabled(isCurrentlyPlaying)

                    if !episode.isQueued {
                        Button("Add to Queue") {
                            withAnimation {
                                try? QueueService.add(episode, in: modelContext)
                            }
                        }
                        .buttonStyle(SecondaryPillButtonStyle())
                    } else {
                        Button("Queued") {}
                            .buttonStyle(SecondaryPillButtonStyle())
                            .disabled(true)
                    }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)

                if let summary = episode.summary {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("About this episode")
                            .font(.offscriptSectionTitle)
                            .foregroundStyle(Color.offscriptTextPrimary)

                        Text(summary)
                            .font(.offscriptBody)
                            .foregroundStyle(Color.offscriptTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Feedback")
                        .font(.offscriptSectionTitle)
                        .foregroundStyle(Color.offscriptTextPrimary)

                    Text("Help OffScript learn what you like.")
                        .font(.offscriptBody)
                        .foregroundStyle(Color.offscriptTextSecondary)

                    HStack(spacing: 10) {
                        Button("Like") { register(.like) }
                            .buttonStyle(SecondaryPillButtonStyle())
                        Button("More like this") { register(.moreLikeThis) }
                            .buttonStyle(SecondaryPillButtonStyle())
                        Button("Less like this") { register(.lessLikeThis) }
                            .buttonStyle(SecondaryPillButtonStyle())
                    }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)

                NavigationLink {
                    PodcastDetailView(podcast: episode.podcast)
                } label: {
                    HStack(spacing: 14) {
                        OffScriptArtworkView(url: episode.podcast.artworkURL, cornerRadius: OffScriptTheme.Radius.small)
                            .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("From")
                                .font(.offscriptMeta)
                                .foregroundStyle(Color.offscriptTextMuted)
                            Text(episode.podcast.title)
                                .font(.offscriptCardTitle)
                                .foregroundStyle(Color.offscriptTextPrimary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.offscriptTextMuted)
                    }
                    .padding(16)
                    .offscriptUtilitySurface()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, OffScriptTheme.pagePadding)
            }
            .padding(.top, 16)
            .padding(.bottom, 90)
        }
        .offscriptPageBackground()
        .navigationTitle("Episode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.offscriptBackgroundTop.opacity(0.98), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var metadata: String {
        let dateString = episode.pubDate.formatted(date: .abbreviated, time: .omitted)
        if let duration = episode.duration {
            return "\(dateString) \u{2022} \(EpisodeDurationFormatter.short(duration))"
        }
        return dateString
    }

    private var timeRemaining: String {
        guard let duration = episode.duration else { return "In progress" }
        let remaining = max(0, duration - episode.playedPosition)
        return "\(EpisodeDurationFormatter.short(remaining)) remaining"
    }

    private func register(_ action: PreferenceSignal.Action) {
        modelContext.insert(PreferenceSignal(action: action, episode: episode))
        try? modelContext.save()
    }
}

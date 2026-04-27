import SwiftData
import SwiftUI

struct EpisodeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var player = PlaybackController.shared
    @ObservedObject private var downloadService = DownloadService.shared
    @State private var feedbackGiven: PreferenceSignal.Action? = nil
    @State private var transcriptURL: URL? = nil
    let episode: Episode

    private var progressValue: Double {
        guard let duration = episode.duration, duration > 0 else { return 0 }
        return episode.playedPosition / duration
    }

    private var isCurrentlyPlaying: Bool {
        player.currentEpisode?.id == episode.id
    }

    private var chapters: [EpisodeChapter] {
        episode.resolvedChapters
    }

    private var transcriptReferences: [EpisodeTranscriptReference] {
        episode.transcriptReferences
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 18) {
                        OffScriptArtworkView(
                            url: episode.artworkURL ?? episode.podcast.artworkURL,
                            cornerRadius: OffScriptTheme.Radius.large
                        )
                        .frame(width: 96, height: 96)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(episode.podcast.title.uppercased())
                                .font(.offscriptMicro.weight(.semibold))
                                .foregroundStyle(Color.offscriptAccent)
                                .lineLimit(1)

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

                    Text(episode.title)
                        .font(.offscriptDisplay)
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .lineLimit(4)
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

                    DownloadButton(episode: episode)
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)

                if let downloadStatus = downloadService.statusText(for: episode) {
                    Text(downloadStatus)
                        .font(.offscriptMeta)
                        .foregroundStyle(Color.offscriptTextMuted)
                        .padding(.horizontal, OffScriptTheme.pagePadding)
                }

                EpisodeBriefingView(episode: episode)
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                if let summary = episode.summary {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("About this episode")
                            .font(.offscriptSectionTitle)
                            .foregroundStyle(Color.offscriptTextPrimary)

                        Text(summary.strippingHTML)
                            .font(.offscriptBody)
                            .foregroundStyle(Color.offscriptTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                }

                if !chapters.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Chapters")
                            .font(.offscriptSectionTitle)
                            .foregroundStyle(Color.offscriptTextPrimary)

                        ForEach(chapters) { chapter in
                            Button {
                                PlaybackController.shared.play(episode, in: modelContext)
                                PlaybackController.shared.seek(to: chapter.startTime)
                            } label: {
                                HStack(spacing: 12) {
                                    Text(timestamp(chapter.startTime))
                                        .font(.offscriptMeta.monospacedDigit())
                                        .foregroundStyle(Color.offscriptAccent)
                                        .frame(width: 50, alignment: .leading)

                                    Text(chapter.title)
                                        .font(.offscriptBody)
                                        .foregroundStyle(Color.offscriptTextPrimary)
                                        .multilineTextAlignment(.leading)

                                    Spacer()
                                }
                                .padding(14)
                                .offscriptUtilitySurface(radius: OffScriptTheme.Radius.small)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                }

                if !transcriptReferences.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Transcripts")
                            .font(.offscriptSectionTitle)
                            .foregroundStyle(Color.offscriptTextPrimary)

                        ForEach(transcriptReferences) { transcript in
                            Button {
                                transcriptURL = transcript.url
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "captions.bubble.fill")
                                        .font(.body)
                                        .foregroundStyle(Color.offscriptAccent)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(transcript.displayTitle)
                                            .font(.offscriptBody.weight(.semibold))
                                            .foregroundStyle(Color.offscriptTextPrimary)
                                        Text(transcript.accessoryLabel)
                                            .font(.offscriptMeta)
                                            .foregroundStyle(Color.offscriptTextMuted)
                                    }

                                    Spacer()

                                    Image(systemName: "doc.text")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Color.offscriptTextMuted)
                                }
                                .padding(14)
                                .offscriptUtilitySurface(radius: OffScriptTheme.Radius.small)
                            }
                            .buttonStyle(.plain)
                        }
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
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                register(.like)
                                feedbackGiven = .like
                            }
                        } label: {
                            Label("Like", systemImage: feedbackGiven == .like ? "hand.thumbsup.fill" : "hand.thumbsup")
                        }
                        .buttonStyle(PrimaryPillButtonStyle())
                        .disabled(feedbackGiven != nil)

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                register(.lessLikeThis)
                                feedbackGiven = .lessLikeThis
                            }
                        } label: {
                            Label("Not for me", systemImage: feedbackGiven == .lessLikeThis ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        }
                        .buttonStyle(SecondaryPillButtonStyle())
                        .disabled(feedbackGiven != nil)
                    }

                    if let feedback = feedbackGiven {
                        Text(feedback == .like ? "Got it — more like this coming." : "Noted — we'll adjust your feed.")
                            .font(.offscriptMeta)
                            .foregroundStyle(Color.offscriptTextMuted)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .sensoryFeedback(.success, trigger: feedbackGiven != nil)
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
            .padding(.bottom, 0)
        }
        .sheet(item: Binding(
            get: { transcriptURL.map { IdentifiableURL(url: $0) } },
            set: { transcriptURL = $0?.url }
        )) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
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
        try? TasteProfileService.refresh(in: modelContext)
    }

    private func timestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainder = totalSeconds % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", remainder))"
        }
        return "\(minutes):\(String(format: "%02d", remainder))"
    }
}

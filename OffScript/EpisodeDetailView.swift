import OSLog
import SwiftData
import SwiftUI

private let episodeDetailLogger = Logger(subsystem: "com.offscript", category: "EpisodeDetail")

struct EpisodeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var player = PlaybackController.shared
    @State private var feedbackGiven: PreferenceSignal.Action? = nil
    @State private var episodeProfile: EpisodeProfile?
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
                                do { try QueueService.add(episode, in: modelContext) } catch { episodeDetailLogger.error("Failed to add episode to queue: \(error.localizedDescription, privacy: .public)") }
                            }
                        }
                        .buttonStyle(SecondaryPillButtonStyle())
                    } else {
                        Button("Queued") {}
                            .buttonStyle(SecondaryPillButtonStyle())
                            .disabled(true)
                    }

                    if episode.isPlayed {
                        Button("Mark Unplayed") {
                            withAnimation {
                                episode.isPlayed = false
                                episode.playedPosition = 0
                                do { try modelContext.save() } catch { episodeDetailLogger.error("Failed to mark episode unplayed: \(error.localizedDescription, privacy: .public)") }
                            }
                        }
                        .buttonStyle(SecondaryPillButtonStyle())
                    }
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)

                if let aiSummary = episodeProfile?.summary, !aiSummary.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("AI Summary", systemImage: "sparkles")
                            .font(.offscriptSectionTitle)
                            .foregroundStyle(Color.offscriptAccent)

                        Text(aiSummary)
                            .font(.offscriptBody)
                            .foregroundStyle(Color.offscriptTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.offscriptAccent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                            .stroke(Color.offscriptAccent.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                }

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
            .padding(.bottom, 90)
        }
        .offscriptPageBackground()
        .navigationTitle("Episode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.offscriptBackgroundTop.opacity(0.98), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            let targetID = episode.id
            var descriptor = FetchDescriptor<EpisodeProfile>(
                predicate: #Predicate { $0.episodeID == targetID }
            )
            descriptor.fetchLimit = 1
            episodeProfile = try? modelContext.fetch(descriptor).first
        }
    }

    private var metadata: String {
        var parts: [String] = []
        if let s = episode.seasonNumber, let e = episode.episodeNumber {
            parts.append("S\(s) E\(e)")
        } else if let e = episode.episodeNumber {
            parts.append("E\(e)")
        }
        parts.append(episode.pubDate.formatted(date: .abbreviated, time: .omitted))
        if let duration = episode.duration {
            parts.append(EpisodeDurationFormatter.short(duration))
        }
        return parts.joined(separator: " \u{2022} ")
    }

    private var timeRemaining: String {
        guard let duration = episode.duration else { return "In progress" }
        let remaining = max(0, duration - episode.playedPosition)
        return "\(EpisodeDurationFormatter.short(remaining)) remaining"
    }

    private func register(_ action: PreferenceSignal.Action) {
        modelContext.insert(PreferenceSignal(action: action, episode: episode))
        do { try modelContext.save() } catch { episodeDetailLogger.error("Failed to save preference signal: \(error.localizedDescription, privacy: .public)") }
    }
}

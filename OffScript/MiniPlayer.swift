import SwiftUI
import TipKit

struct MiniPlayer: View {
    @ObservedObject private var player = PlaybackController.shared
    @ObservedObject private var timePublisher = PlaybackTimePublisher.shared
    @State private var swipeDismissOffset: CGFloat = 0
    private let swipeTip = MiniPlayerSwipeTip()

    var body: some View {
        if let episode = player.currentEpisode {
            VStack(spacing: 0) {
                // Progress bar — full width, top edge
                progressBar

                // Content
                HStack(spacing: 12) {
                    // Artwork + info — tap opens full player
                    Button {
                        player.isPlayerPresented = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                OffScriptArtworkView(
                                    url: episode.artworkURL ?? episode.podcast.artworkURL,
                                    cornerRadius: 8
                                )
                                .frame(width: 44, height: 44)

                                if player.isPlaying {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.offscriptAccent)
                                        .padding(4)
                                        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                        .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
                                        .transition(.opacity.combined(with: .scale))
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(episode.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.offscriptTextPrimary)
                                    .lineLimit(1)

                                HStack(spacing: 4) {
                                    Text(episode.podcast.title)
                                        .foregroundStyle(Color.offscriptTextMuted)
                                        .lineLimit(1)

                                    if timePublisher.duration > 0 {
                                        Text("· \(remainingTimeLabel)")
                                            .foregroundStyle(Color.offscriptTextMuted)
                                    }
                                }
                                .font(.caption)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)

                    // Transport
                    HStack(spacing: 2) {
                        Button {
                            player.togglePlayPause()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.body.weight(.bold))
                                .foregroundStyle(.black)
                                .frame(width: 36, height: 36)
                                .background(Color.offscriptAccent, in: Circle())
                                .contentTransition(.symbolEffect(.replace.downUp))
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.impact(flexibility: .soft), trigger: player.isPlaying)

                        Button {
                            player.seek(by: 30)
                        } label: {
                            Image(systemName: "goforward.30")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.offscriptTextSecondary)
                                .frame(width: 36, height: 36)
                                .symbolEffect(.bounce, value: timePublisher.currentTime)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background {
                Rectangle()
                    .fill(.clear)
                    .offscriptGlass(in: Rectangle())
                    .overlay {
                        // Subtle warm tint so the glass picks up the editorial palette
                        Rectangle().fill(Color.offscriptCardRaised.opacity(0.32))
                    }
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.offscriptHairline)
                            .frame(height: 0.5)
                    }
            }
            .offset(x: swipeDismissOffset)
            .opacity(swipeDismissOpacity)
            .gesture(dismissGesture)
            .gesture(openPlayerGesture)
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Now playing: \(episode.title)")
            .popoverTip(swipeTip, arrowEdge: .bottom)
            .task {
                MiniPlayerSwipeTip.miniPlayerPresentations += 1
            }
        }
    }

    // MARK: - Progress

    private var progressBar: some View {
        GeometryReader { proxy in
            let clamped = min(max(progressValue, 0), 1)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                Rectangle()
                    .fill(Color.offscriptAccent)
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: 2.5)
    }

    // MARK: - Gestures

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                if value.translation.width > 0 {
                    swipeDismissOffset = value.translation.width
                }
            }
            .onEnded { value in
                if value.translation.width > 120 || value.predictedEndTranslation.width > 200 {
                    withAnimation(.easeOut(duration: 0.25)) {
                        swipeDismissOffset = 400
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        player.completeCurrentEpisode(shouldAutoAdvance: false)
                        swipeDismissOffset = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        swipeDismissOffset = 0
                    }
                }
            }
    }

    private var openPlayerGesture: some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .local)
            .onEnded { value in
                if value.translation.height < -40 {
                    player.isPlayerPresented = true
                }
            }
    }

    // MARK: - Helpers

    private var swipeDismissOpacity: Double {
        1 - Double(min(swipeDismissOffset / 300, 1)) * 0.6
    }

    private var progressValue: Double {
        guard timePublisher.duration > 0 else { return 0 }
        return timePublisher.currentTime / timePublisher.duration
    }

    private var remainingTimeLabel: String {
        let remaining = max(0, timePublisher.duration - timePublisher.currentTime)
        return "\(EpisodeDurationFormatter.short(remaining)) left"
    }
}


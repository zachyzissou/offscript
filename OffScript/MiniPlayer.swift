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

                // Tuner OLED MiniPlayer — flat black, square hairline-bordered
                // artwork, mono uppercase show name, square play key in
                // signal yellow, hairline-bordered skip cell. No glass, no
                // gradient, no glow.
                HStack(spacing: 12) {
                    Button {
                        player.isPlayerPresented = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                OffScriptArtworkView(
                                    url: episode.artworkURL ?? episode.podcast.artworkURL,
                                    cornerRadius: 4
                                )
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Rectangle().stroke(Color.offscriptHairline, lineWidth: 0.5)
                                )

                                if player.isPlaying {
                                    // Tiny REC pip overlaid bottom-right.
                                    Circle()
                                        .fill(Color.offscriptDestructive)
                                        .frame(width: 5, height: 5)
                                        .offset(x: 17, y: 17)
                                        .transition(.opacity)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(episode.podcast.title.uppercased())
                                    .font(.offscriptTagLabel)
                                    .tracking(1.4)
                                    .foregroundStyle(Color.offscriptAccentSecondary)
                                    .lineLimit(1)

                                Text(episode.title)
                                    .font(.offscriptCardTitle)
                                    .foregroundStyle(Color.offscriptTextPrimary)
                                    .lineLimit(1)

                                if timePublisher.duration > 0 {
                                    Text(remainingTimeLabel)
                                        .font(.offscriptMicro)
                                        .foregroundStyle(Color.offscriptTextMuted)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)

                    // Transport — square hairline cells, signal yellow play key.
                    HStack(spacing: 6) {
                        Button {
                            player.togglePlayPause()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 38, height: 38)
                                .background(Color.offscriptAccent)
                                .contentTransition(.symbolEffect(.replace.downUp))
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.impact(flexibility: .soft), trigger: player.isPlaying)

                        Button {
                            player.seek(by: 30)
                        } label: {
                            Image(systemName: "goforward.30")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.offscriptTextPrimary)
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Rectangle().stroke(Color.offscriptHairline, lineWidth: 0.5)
                                )
                                .symbolEffect(.bounce, value: timePublisher.currentTime)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background {
                // Pure black, no glass.
                Color.black
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
        // Tuner instrument signal — 1pt hairline strip across the very top
        // edge of the bar. NOT a separate progress widget; the strip IS the
        // top edge of the dock.
        GeometryReader { proxy in
            let clamped = min(max(progressValue, 0), 1)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.offscriptHairline)
                Rectangle()
                    .fill(Color.offscriptAccent)
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: 1)
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


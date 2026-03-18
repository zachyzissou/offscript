import SwiftUI

struct MiniPlayer: View {
    @ObservedObject private var player = PlaybackController.shared
    @ObservedObject private var timePublisher = PlaybackTimePublisher.shared

    /// Dismissal offset driven by a right-swipe gesture.
    @State private var swipeDismissOffset: CGFloat = 0

    var body: some View {
        if let episode = player.currentEpisode {
            miniPlayerCard(for: episode)
                // Swipe-right to dismiss
                .offset(x: swipeDismissOffset)
                .opacity(swipeDismissOpacity)
                .gesture(dismissGesture)
                // Swipe-up to open full player
                .gesture(openPlayerGesture)
                .contentShape(Rectangle())
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Now playing: \(episode.title)")
        }
    }

    // MARK: - Card

    @ViewBuilder
    private func miniPlayerCard(for episode: Episode) -> some View {
        VStack(spacing: 0) {
            // Progress track (full-width background + accent fill)
            progressBar

            // Content row
            HStack(spacing: 12) {
                // Artwork + text — tapping opens the full player
                Button {
                    player.isPlayerPresented = true
                } label: {
                    HStack(spacing: 12) {
                        artworkThumbnail(for: episode)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(episode.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.offscriptTextPrimary)
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                Text(episode.podcast.title)
                                    .font(.offscriptMeta)
                                    .foregroundStyle(Color.offscriptTextMuted)
                                    .lineLimit(1)

                                if timePublisher.duration > 0 {
                                    Text("·")
                                        .font(.offscriptMeta)
                                        .foregroundStyle(Color.offscriptTextMuted)
                                    Text(remainingTimeLabel)
                                        .font(.offscriptMeta)
                                        .foregroundStyle(Color.offscriptTextMuted)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open player")
                .accessibilityHint("Expand the now playing screen for \(episode.title)")

                // Transport controls
                HStack(spacing: 4) {
                    // Play / Pause
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(width: 38, height: 38)
                            .background(Color.offscriptAccent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(flexibility: .soft), trigger: player.isPlaying)
                    .accessibilityLabel(player.isPlaying ? "Pause playback" : "Resume playback")
                    .accessibilityValue(episode.title)

                    // Skip forward 30s
                    Button {
                        player.seek(by: 30)
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color.offscriptTextSecondary)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.4), trigger: timePublisher.currentTime)
                    .accessibilityLabel("Skip forward 30 seconds")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(miniPlayerBackground)
        .clipShape(RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                .stroke(Color.offscriptHairline, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .shadow(color: Color.black.opacity(0.28), radius: 20, y: 10)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { proxy in
            let clamped = min(max(progressValue, 0), 1)
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 3)

                // Accent fill
                Rectangle()
                    .fill(Color.offscriptAccent)
                    .frame(width: proxy.size.width * clamped, height: 3)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artworkThumbnail(for episode: Episode) -> some View {
        ZStack {
            OffScriptArtworkView(
                url: episode.artworkURL ?? episode.podcast.artworkURL,
                cornerRadius: OffScriptTheme.Radius.small
            )
            .frame(width: 48, height: 48)

            // Waveform indicator when playing
            if player.isPlaying {
                WaveformIndicator()
                    .frame(width: 20, height: 14)
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            }
        }
    }

    // MARK: - Background

    private var miniPlayerBackground: some View {
        ZStack {
            // Blurred material for depth
            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                .fill(.ultraThinMaterial)

            // Dark tint overlay so it fits the app's warm-dark palette
            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.offscriptCardRaised.opacity(0.82), Color.offscriptCard.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    // MARK: - Gestures

    /// Swipe right to dismiss (stop playback).
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                // Only allow rightward dragging
                let horizontal = value.translation.width
                if horizontal > 0 {
                    swipeDismissOffset = horizontal
                }
            }
            .onEnded { value in
                if value.translation.width > 120 || value.predictedEndTranslation.width > 200 {
                    // Dismiss
                    withAnimation(.easeOut(duration: 0.25)) {
                        swipeDismissOffset = 400
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        player.completeCurrentEpisode(shouldAutoAdvance: false)
                        swipeDismissOffset = 0
                    }
                } else {
                    // Snap back
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        swipeDismissOffset = 0
                    }
                }
            }
    }

    /// Swipe up to open the full player.
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
        let progress = min(swipeDismissOffset / 300, 1)
        return 1 - Double(progress) * 0.6
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

// MARK: - Waveform Indicator

/// Three-bar animated waveform that indicates active playback.
private struct WaveformIndicator: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.offscriptAccent)
                    .frame(width: 3)
                    .scaleEffect(y: animate ? CGFloat.random(in: 0.4...1.0) : 0.3, anchor: .bottom)
                    .animation(
                        .easeInOut(duration: Double.random(in: 0.3...0.6))
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animate
                    )
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .onAppear { animate = true }
    }
}

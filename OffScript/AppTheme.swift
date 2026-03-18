import SwiftUI

enum OffScriptTheme {
    static let pagePadding: CGFloat = 20
    static let spaciousPadding: CGFloat = 28  // for hero sections and lead cards
    static let sectionSpacing: CGFloat = 28
    static let itemSpacing: CGFloat = 16

    enum Radius {
        static let small: CGFloat = 16
        static let medium: CGFloat = 24
        static let large: CGFloat = 32
    }
}

extension Color {
    static let offscriptBackground = Color(red: 0.05, green: 0.05, blue: 0.06)
    static let offscriptBackgroundTop = Color(red: 0.10, green: 0.09, blue: 0.08)
    static let offscriptBackgroundBottom = Color(red: 0.03, green: 0.03, blue: 0.05)

    static let offscriptCard = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let offscriptCardRaised = Color(red: 0.14, green: 0.14, blue: 0.16)
    static let offscriptCardStrong = Color(red: 0.18, green: 0.17, blue: 0.15)
    static let offscriptCardUtility = Color(red: 0.10, green: 0.10, blue: 0.12)

    static let offscriptAccent = Color(red: 0.96, green: 0.52, blue: 0.19)
    static let offscriptAccentSoft = Color(red: 0.96, green: 0.52, blue: 0.19).opacity(0.18)
    static let offscriptTextPrimary = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let offscriptTextSecondary = Color.white.opacity(0.78)
    static let offscriptTextMuted = Color.white.opacity(0.52)
    static let offscriptHairline = Color.white.opacity(0.12)
    static let offscriptProgressTrack = Color.white.opacity(0.12)

    // Warm cream secondary accent — for informational highlights that aren't CTAs
    static let offscriptAccentSecondary = Color(red: 0.92, green: 0.84, blue: 0.68)
    static let offscriptAccentSecondaryMuted = Color(red: 0.92, green: 0.84, blue: 0.68).opacity(0.14)

    // Destructive — desaturated coral that belongs in the warm palette
    static let offscriptDestructive = Color(red: 0.88, green: 0.36, blue: 0.32)
    static let offscriptDestructiveSoft = Color(red: 0.88, green: 0.36, blue: 0.32).opacity(0.16)
}

extension Font {
    static let offscriptHero = Font.system(.largeTitle, design: .serif, weight: .bold)
    static let offscriptDisplay = Font.system(.title, design: .serif, weight: .bold)
    static let offscriptUtilityTitle = Font.system(.title2, design: .default, weight: .bold)
    static let offscriptSectionTitle = Font.system(.title3, design: .serif, weight: .semibold)
    static let offscriptCardTitle = Font.system(.headline, design: .default, weight: .semibold)
    static let offscriptBody = Font.system(.callout, design: .default)
    static let offscriptMeta = Font.system(.caption, design: .monospaced)
    static let offscriptMicro = Font.system(.caption2, design: .monospaced)
}

struct OffScriptBackgroundView: View {
    var body: some View {
        LinearGradient(
            colors: [.offscriptBackgroundTop, .offscriptBackgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct OffScriptArtworkPlaceholder: View {
    var cornerRadius: CGFloat = OffScriptTheme.Radius.medium

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.offscriptAccentSoft, Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "waveform")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.offscriptTextMuted)
        }
    }
}

struct OffScriptArtworkView: View {
    let url: URL?
    var cornerRadius: CGFloat = OffScriptTheme.Radius.medium

    var body: some View {
        GeometryReader { proxy in
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                case .failure:
                    ZStack {
                        OffScriptArtworkPlaceholder(cornerRadius: cornerRadius)
                            .frame(width: proxy.size.width, height: proxy.size.height)

                        VStack(spacing: 4) {
                            Spacer()
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.offscriptTextMuted.opacity(0.6))
                        }
                        .padding(.bottom, 8)
                    }
                case .empty:
                    OffScriptArtworkPlaceholder(cornerRadius: cornerRadius)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                @unknown default:
                    OffScriptArtworkPlaceholder(cornerRadius: cornerRadius)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct OffScriptReasonBadge: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(Color.offscriptTextPrimary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.offscriptHairline, lineWidth: 1)
            )
    }
}

struct OffScriptExplanationTag: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.offscriptAccent)
                .frame(width: 3, height: 14)

            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.offscriptAccentSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.offscriptAccentSecondaryMuted)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct OffScriptEmptyState: View {
    let icon: String
    let headline: String
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.offscriptAccent.opacity(0.6))
                .frame(width: 72, height: 72)
                .background(Color.offscriptAccentSoft)
                .clipShape(Circle())

            VStack(spacing: 8) {
                Text(headline)
                    .font(.offscriptDisplay)
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 320)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}

struct OffScriptSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.offscriptSectionTitle)
                .foregroundStyle(Color.offscriptTextPrimary)
            Text(subtitle)
                .font(.offscriptBody)
                .foregroundStyle(Color.offscriptTextSecondary)
        }
    }
}

struct OffScriptUtilityHeader: View {
    let eyebrow: String?
    let title: String
    let subtitle: String

    init(eyebrow: String? = nil, title: String, subtitle: String) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.offscriptMeta.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.offscriptAccent)
            }

            Text(title)
                .font(.offscriptUtilityTitle)
                .foregroundStyle(Color.offscriptTextPrimary)

            Text(subtitle)
                .font(.offscriptBody)
                .foregroundStyle(Color.offscriptTextSecondary)
        }
    }
}

struct OffScriptProgressBar: View {
    let value: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(value, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.offscriptProgressTrack)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.offscriptAccent, Color.offscriptAccent.opacity(0.75)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int(min(max(value, 0), 1) * 100)) percent")
        .accessibilityLabel("Progress")
    }
}

struct OffScriptSurfaceModifier: ViewModifier {
    var radius: CGFloat = OffScriptTheme.Radius.medium
    var prominent: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: prominent
                                ? [Color.offscriptCardStrong, Color.offscriptCardRaised]
                                : [Color.offscriptCardRaised, Color.offscriptCard],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .offscriptGrain(opacity: prominent ? 0.035 : 0.025)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.offscriptHairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(prominent ? 0.34 : 0.22), radius: prominent ? 24 : 16, y: prominent ? 12 : 8)
    }
}

struct OffScriptUtilitySurfaceModifier: ViewModifier {
    var radius: CGFloat = OffScriptTheme.Radius.medium

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.offscriptCardUtility)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.offscriptHairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 10, y: 4)
    }
}

extension View {
    func offscriptPageBackground() -> some View {
        background(OffScriptBackgroundView().ignoresSafeArea())
    }

    func offscriptSurface(radius: CGFloat = OffScriptTheme.Radius.medium, prominent: Bool = false) -> some View {
        modifier(OffScriptSurfaceModifier(radius: radius, prominent: prominent))
    }

    func offscriptUtilitySurface(radius: CGFloat = OffScriptTheme.Radius.medium) -> some View {
        modifier(OffScriptUtilitySurfaceModifier(radius: radius))
    }

    func measureHeight(_ height: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ViewHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(ViewHeightPreferenceKey.self) { height.wrappedValue = $0 }
    }
}

private struct ViewHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PrimaryPillButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(Color.offscriptAccent.opacity(configuration.isPressed ? 0.78 : 1.0))
            .clipShape(Capsule())
            .shadow(color: Color.offscriptAccent.opacity(configuration.isPressed ? 0 : 0.25), radius: 8, y: 4)
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.94 : 1.0))
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct SecondaryPillButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.offscriptTextPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.08))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.offscriptHairline, lineWidth: 1)
            )
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.96 : 1.0))
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Shimmer / Skeleton Loading

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0

    func body(content: Content) -> some View {
        let lead = min(max(phase - 0.3, 0), 1)
        let center = min(max(phase, lead), 1)
        let trail = min(max(phase + 0.3, center), 1)

        content
            .overlay(
                GeometryReader { proxy in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: lead),
                            .init(color: Color.white.opacity(0.08), location: center),
                            .init(color: .clear, location: trail)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 2.0
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

struct GrainOverlay: ViewModifier {
    var opacity: Double = 0.03

    func body(content: Content) -> some View {
        content.overlay(
            Canvas { context, size in
                var rng = SplitMix64(seed: 42)
                let count = min(Int(size.width * size.height * 0.005), 1200)
                for _ in 0..<count {
                    let x = CGFloat.random(in: 0..<size.width, using: &rng)
                    let y = CGFloat.random(in: 0..<size.height, using: &rng)
                    let gray = CGFloat.random(in: 0.3...1.0, using: &rng)
                    context.fill(
                        Path(CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                        with: .color(Color(white: gray, opacity: opacity))
                    )
                }
            }
            .allowsHitTesting(false)
            .drawingGroup()
        )
    }
}

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

extension View {
    func offscriptGrain(opacity: Double = 0.03) -> some View {
        modifier(GrainOverlay(opacity: opacity))
    }
}

// MARK: - Staggered Entrance Animation

struct StaggeredEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    let baseDelay: Double

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 1 : (isVisible ? 1 : 0))
            .offset(y: reduceMotion ? 0 : (isVisible ? 0 : 12))
            .animation(
                reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82)
                    .delay(Double(index) * baseDelay),
                value: isVisible
            )
            .onAppear { isVisible = true }
    }
}

extension View {
    func staggeredEntrance(index: Int, delay: Double = 0.06) -> some View {
        modifier(StaggeredEntrance(index: index, baseDelay: delay))
    }
}

struct SkeletonRailCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: 160, height: 160)

            VStack(alignment: .leading, spacing: 8) {
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 70, height: 16)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 80, height: 10)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 140, height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 100, height: 10)
            }

            Capsule()
                .fill(Color.white.opacity(0.06))
                .frame(width: 56, height: 32)
        }
        .padding(16)
        .frame(width: 196, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                .fill(Color.offscriptCard)
        )
        .shimmer()
    }
}

struct SkeletonHeroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Matches the new full-width artwork hero card layout
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(height: 200)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: OffScriptTheme.Radius.large,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: OffScriptTheme.Radius.large,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 22)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 200, height: 22)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 140, height: 12)

                HStack(spacing: 10) {
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 64, height: 36)
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 72, height: 36)
                }
            }
            .padding(20)
        }
        .offscriptSurface(radius: OffScriptTheme.Radius.large, prominent: true)
        .shimmer()
    }
}

struct SkeletonSearchRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Color.offscriptAccent)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 200, height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 140, height: 10)
            }
        }
        .shimmer()
    }
}

// MARK: - Duration Formatter

enum EpisodeDurationFormatter {
    static func short(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
        }
        return "\(minutes)m"
    }
}

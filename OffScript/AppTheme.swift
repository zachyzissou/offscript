import SwiftUI

enum OffScriptTheme {
    static let pagePadding: CGFloat = 20
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
    static let offscriptBackgroundTop = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let offscriptBackgroundBottom = Color(red: 0.04, green: 0.04, blue: 0.05)

    static let offscriptCard = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let offscriptCardRaised = Color(red: 0.14, green: 0.14, blue: 0.16)
    static let offscriptCardStrong = Color(red: 0.18, green: 0.17, blue: 0.15)
    static let offscriptCardUtility = Color(red: 0.10, green: 0.10, blue: 0.12)

    static let offscriptAccent = Color(red: 0.96, green: 0.52, blue: 0.19)
    static let offscriptAccentSoft = Color(red: 0.96, green: 0.52, blue: 0.19).opacity(0.18)
    static let offscriptTextPrimary = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let offscriptTextSecondary = Color.white.opacity(0.78)
    static let offscriptTextMuted = Color.white.opacity(0.52)
    static let offscriptHairline = Color.white.opacity(0.08)
    static let offscriptProgressTrack = Color.white.opacity(0.12)
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
            AsyncImage(url: url) { image in
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
            } placeholder: {
                OffScriptArtworkPlaceholder(cornerRadius: cornerRadius)
                    .frame(width: proxy.size.width, height: proxy.size.height)
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
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color.offscriptAccent.opacity(configuration.isPressed ? 0.78 : 1.0))
            .clipShape(Capsule())
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.96 : 1.0))
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
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
        content
            .overlay(
                GeometryReader { proxy in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: max(phase - 0.3, 0)),
                            .init(color: Color.white.opacity(0.08), location: phase),
                            .init(color: .clear, location: min(phase + 0.3, 1))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 8) {
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 90, height: 16)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 100, height: 10)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 18)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 160, height: 18)
                }
            }

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

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
    static let offscriptTextSecondary = Color.white.opacity(0.74)
    static let offscriptTextMuted = Color.white.opacity(0.7)
    static let offscriptHairline = Color.white.opacity(0.08)
    static let offscriptProgressTrack = Color.white.opacity(0.12)
}

extension Font {
    static let offscriptHero = Font.system(.largeTitle, design: .serif, weight: .bold)
    static let offscriptDisplay = Font.system(.title, design: .serif, weight: .bold)
    static let offscriptUtilityTitle = Font.system(.title2, design: .default, weight: .bold)
    static let offscriptSectionTitle = Font.system(.title3, design: .serif, weight: .semibold)
    static let offscriptCardTitle = Font.system(.headline, design: .default, weight: .semibold)
    static let offscriptBody = Font.system(.subheadline, design: .default)
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
        AsyncImage(url: url) { image in
            image
                .resizable()
                .scaledToFill()
                .overlay(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        } placeholder: {
            OffScriptArtworkPlaceholder(cornerRadius: cornerRadius)
        }
        .contentShape(Rectangle())
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct OffScriptReasonBadge: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.offscriptMicro.weight(.semibold))
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color.offscriptAccent.opacity(configuration.isPressed ? 0.78 : 1.0))
            .clipShape(Capsule())
    }
}

struct SecondaryPillButtonStyle: ButtonStyle {
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
    }
}

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

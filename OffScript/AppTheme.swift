import SafariServices
import SwiftUI
import UIKit

// MARK: - HTML Stripping

extension String {
    /// Strips HTML tags and decodes common entities for display as plain text.
    var strippingHTML: String {
        guard contains("<") || contains("&") else { return self }
        guard let data = data(using: .utf8),
              let attributed = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.html,
                            .characterEncoding: String.Encoding.utf8.rawValue],
                  documentAttributes: nil
              ) else {
            // Fallback: regex strip tags
            return replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - In-App Safari Browser

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - Theme

enum OffScriptTheme {
    static let pagePadding: CGFloat = 20
    static let spaciousPadding: CGFloat = 28  // for hero sections and lead cards
    static let sectionSpacing: CGFloat = 28
    static let itemSpacing: CGFloat = 16

    enum Radius {
        // Tuner is sharp. These were 16/24/32 in the previous warm theme; now
        // they're tightened to 6/8/12. Keeping the names so call sites still
        // build — but the visual rhythm is dramatically tighter, which is
        // intentional for the instrument-cluster aesthetic.
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
    }
}

// MARK: - Tuner OLED palette
//
// Pure black field, signal-yellow as the only "interactive" accent, plus a
// small functional accent set used exclusively for tag pills, ring meter
// strokes, and traces. Modeled on high-end OLED instrument clusters
// (Polestar / McLaren / studio monitor) — flat surfaces, hairline strokes,
// no gradients, no glow.
//
// Token names are preserved from the previous warm-amber theme so existing
// screens keep building. As each screen is converted to the Tuner primitives
// (`OffScriptTunerKit.swift`), it stops depending on these compatibility
// shims and uses the named Tuner palette directly.
extension Color {
    // Surfaces — pure black field, almost-imperceptible elevation steps.
    static let offscriptBackground = Color.black
    static let offscriptBackgroundTop = Color.black
    static let offscriptBackgroundBottom = Color.black

    static let offscriptCard = Color(red: 0.039, green: 0.039, blue: 0.039)         // #0a0a0a panel
    static let offscriptCardRaised = Color(red: 0.062, green: 0.062, blue: 0.066)   // #101011 raised
    static let offscriptCardStrong = Color(red: 0.078, green: 0.078, blue: 0.082)   // #141415 strong
    static let offscriptCardUtility = Color.black                                   // recessed = nothing

    // Signal yellow — the ONLY interactive accent. Use for play, scrubber,
    // active state, focus rings. Never use it for decorative section labels.
    static let offscriptAccent = Color(red: 0.910, green: 0.824, blue: 0.290)       // #e8d24a
    static let offscriptAccentSoft = Color(red: 0.910, green: 0.824, blue: 0.290).opacity(0.18)

    // Type — warm-tinted whites so pure white doesn't burn.
    static let offscriptTextPrimary = Color(red: 0.953, green: 0.945, blue: 0.918)  // #f3f1ea
    static let offscriptTextSecondary = Color(white: 0.953).opacity(0.62)
    static let offscriptTextMuted = Color(white: 0.953).opacity(0.32)               // textFaint
    static let offscriptHairline = Color.white.opacity(0.08)
    static let offscriptProgressTrack = Color.white.opacity(0.08)
    static let offscriptFillSubtle = Color.white.opacity(0.04)
    static let offscriptFillLight = Color.white.opacity(0.06)

    // Functional accent set — tag pills + ring meter strokes only. Each
    // color carries semantic meaning, not decoration:
    //   accentSecondary (cyan) → informational tag (episode #, host name)
    //   accentOK        (mint) → mode / status pill ("LIVE", "AUTO")
    //   destructive     (red)  → warnings, errors, RECord state
    static let offscriptAccentSecondary = Color(red: 0.361, green: 0.776, blue: 1.0)         // #5cc6ff cyan
    static let offscriptAccentSecondaryMuted = Color(red: 0.361, green: 0.776, blue: 1.0).opacity(0.14)

    static let offscriptAccentOK = Color(red: 0.486, green: 0.871, blue: 0.643)              // #7cd9a4 mint
    static let offscriptAccentOKMuted = Color(red: 0.486, green: 0.871, blue: 0.643).opacity(0.14)

    static let offscriptDestructive = Color(red: 0.910, green: 0.353, blue: 0.235)           // #e85a3c warm red
    static let offscriptDestructiveSoft = Color(red: 0.910, green: 0.353, blue: 0.235).opacity(0.16)
}

// MARK: - Tuner type stack
//
// Mono-forward, instrument-cluster aesthetic. Two distinct stacks with
// non-overlapping jobs:
//
//   Display (huge thin sans):   primary readouts — "32m", "1.25×", episode title
//   Body (system sans regular): readable prose — episode descriptions, settings copy
//   Mono (tabular caption):     labels, tag pills, timecodes, anywhere digits column up
//
// Token names match the previous theme so existing call sites keep working;
// what changes is the *vocabulary* — no more serif anywhere, no more
// Playfair, no more decorative fonts. The instrument cluster speaks two
// languages and that's it.
extension Font {
    /// Huge, ultra-thin numeric display — Ferrari-cluster "210 km/h" energy.
    /// Use for the single biggest number on a screen (player timecode, hero
    /// stat). Tabular digits so values don't shift width as they tick.
    static let offscriptHero = Font.system(size: 56, weight: .ultraLight, design: .default)
        .monospacedDigit()

    /// Display line — episode titles in player + episode detail. Thin sans
    /// at headline weight, NOT serif. The instrument cluster has no serif.
    static let offscriptDisplay = Font.system(.title2, design: .default).weight(.light)

    /// Section / utility titles. Sans semibold — readable, no display drama.
    static let offscriptUtilityTitle = Font.system(.title3, design: .default, weight: .semibold)
    static let offscriptSectionTitle = Font.system(.headline, design: .default, weight: .semibold)

    /// Card titles (episode / podcast names in lists).
    static let offscriptCardTitle = Font.system(.subheadline, design: .default, weight: .semibold)

    /// Body copy — system default, no special design.
    static let offscriptBody = Font.system(.callout, design: .default)

    /// Monospaced caption with tabular digits. Use for every timecode,
    /// duration, percentage, scrubber readout, and date metadata so digit
    /// columns line up frame-perfect.
    static let offscriptMeta = Font.system(.caption, design: .monospaced).monospacedDigit()
    static let offscriptMicro = Font.system(.caption2, design: .monospaced).monospacedDigit()

    /// Tiny tag-pill label — uppercase, mono, heavily tracked. Used inside
    /// `OffScriptTagPill` (see OffScriptTunerKit). Apply with `.tracking(1.4)`.
    static let offscriptTagLabel = Font.system(size: 9.5, weight: .semibold, design: .monospaced)
}

struct OffScriptBackgroundView: View {
    // Tuner is OLED — pure black, no gradient. The `trueBlackMode` setting is
    // now redundant (we're always true black) but we honor it for any UI that
    // still references it.
    var body: some View {
        Color.black
    }
}

struct OffScriptArtworkPlaceholder: View {
    var cornerRadius: CGFloat = OffScriptTheme.Radius.medium

    /// Sharp-edged placeholder consistent with the Tuner aesthetic — flat
    /// black panel + hairline + waveform glyph. No gradient, no shadow.
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.offscriptCard)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.offscriptHairline, lineWidth: 0.5)

            Image(systemName: "waveform")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.offscriptTextMuted)
        }
    }
}

// MARK: - Image Cache

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memoryCache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB memory
        return cache
    }()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,  // 50 MB memory
            diskCapacity: 200 * 1024 * 1024     // 200 MB disk
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 12
        return URLSession(configuration: config)
    }()

    func image(for url: URL) -> UIImage? {
        memoryCache.object(forKey: url as NSURL)
    }

    func loadImage(from url: URL) async -> UIImage? {
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached
        }

        guard let (data, _) = try? await session.data(from: url),
              let image = UIImage(data: data) else {
            return nil
        }

        let cost = data.count
        memoryCache.setObject(image, forKey: url as NSURL, cost: cost)
        return image
    }

    /// Warm the cache for a list of URLs in parallel at low priority. Used by
    /// rails to prefetch the next few cards' artwork before the user scrolls,
    /// eliminating most of the visible image-pop.
    func prefetch(_ urls: [URL?]) {
        let needed = urls.compactMap { $0 }.filter { memoryCache.object(forKey: $0 as NSURL) == nil }
        guard !needed.isEmpty else { return }
        Task(priority: .utility) { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                for url in needed.prefix(8) {
                    group.addTask { _ = await self?.loadImage(from: url) }
                }
            }
        }
    }
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else if didFail {
                placeholder()
            } else {
                placeholder()
                    .task(id: url) {
                        guard let url else { didFail = true; return }
                        if let image = await ImageCache.shared.loadImage(from: url) {
                            uiImage = image
                        } else {
                            didFail = true
                        }
                    }
            }
        }
    }
}

struct OffScriptArtworkView: View {
    let url: URL?
    var cornerRadius: CGFloat = OffScriptTheme.Radius.medium

    var body: some View {
        GeometryReader { proxy in
            CachedAsyncImage(url: url) { image in
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

    /// Tuner tag pill — outlined hairline rectangle, mono uppercase label.
    /// No fill, no shadow. Reads as instrument-cluster instrumentation.
    var body: some View {
        Text(text.uppercased())
            .font(.offscriptTagLabel)
            .tracking(1.4)
            .foregroundStyle(Color.offscriptTextPrimary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.offscriptHairline, lineWidth: 0.5)
            )
    }
}

struct OffScriptExplanationTag: View {
    let text: String

    /// Why-this-was-recommended tag. Cyan = informational accent, tiny
    /// hairline rect, mono uppercase. Distinct from the neutral
    /// `OffScriptReasonBadge` because it carries semantic meaning ("we
    /// chose this because...").
    var body: some View {
        Text(text.uppercased())
            .font(.offscriptTagLabel)
            .tracking(1.4)
            .foregroundStyle(Color.offscriptAccentSecondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.offscriptAccentSecondary.opacity(0.45), lineWidth: 0.5)
            )
    }
}

struct OffScriptEmptyState: View {
    let icon: String
    let headline: String
    let message: String
    /// Optional Foundation Models prompt — when supplied the message is replaced
    /// with an editorially-voiced variant generated on device the first time
    /// the empty state is seen, then cached.
    var generatedCopyKey: String? = nil
    var generatedCopyPrompt: String? = nil

    @State private var liveMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Color.offscriptAccent.opacity(0.7))
                .frame(width: 76, height: 76)
                .background {
                    Circle()
                        .fill(Color.offscriptAccentSoft)
                        .shadow(color: Color.offscriptAccent.opacity(0.25), radius: 18, y: 6)
                }
                .symbolEffect(.pulse, options: .repeating, isActive: liveMessage == nil)

            VStack(spacing: 8) {
                Text(headline)
                    .font(.offscriptDisplay)
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .multilineTextAlignment(.center)

                Text(liveMessage ?? message)
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
        }
        .frame(maxWidth: 320)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .task(id: generatedCopyKey) {
            guard let key = generatedCopyKey, let prompt = generatedCopyPrompt else { return }
            let generated = await EmptyStateCopyService.shared.copy(
                for: key,
                fallback: message,
                prompt: prompt
            )
            withAnimation(.easeInOut(duration: 0.5)) { liveMessage = generated }
        }
    }
}

struct OffScriptSectionHeader: View {
    let title: String
    let subtitle: String

    /// Tuner section header — small mono uppercase title (instrument label
    /// style) with a muted body subtitle beneath. Replaces the previous
    /// serif `offscriptSectionTitle` look.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.offscriptTagLabel)
                .tracking(1.6)
                .foregroundStyle(Color.offscriptTextPrimary)
            Text(subtitle)
                .font(.offscriptBody)
                .foregroundStyle(Color.offscriptTextMuted)
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

    /// Tuner utility header — eyebrow tag pill above a thin sans display
    /// title. The eyebrow is the *only* place signal yellow shows up here;
    /// it carries the screen's identity. Subtitle is muted body sans.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.offscriptTagLabel)
                    .tracking(1.6)
                    .foregroundStyle(Color.offscriptAccent)
            }

            Text(title)
                .font(.offscriptDisplay)
                .foregroundStyle(Color.offscriptTextPrimary)

            Text(subtitle)
                .font(.offscriptBody)
                .foregroundStyle(Color.offscriptTextMuted)
        }
    }
}

struct OffScriptProgressBar: View {
    let value: Double
    var height: CGFloat = 2

    /// Tuner progress — single-pixel hairline track, flat yellow fill. No
    /// gradient, no glow. Reads as an instrument readout, not a "progress
    /// bar."
    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(value, 0), 1)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.offscriptProgressTrack)
                Rectangle()
                    .fill(Color.offscriptAccent)
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int(min(max(value, 0), 1) * 100)) percent")
        .accessibilityLabel("Progress")
    }
}

struct OffScriptScrubber: View {
    @Binding var value: TimeInterval
    let duration: TimeInterval
    var onSeek: ((TimeInterval) -> Void)? = nil

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    // Tuner instrument scrubber — hairline track, square yellow thumb.
    private let trackHeight: CGFloat = 2
    private let activeTrackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 12

    private var safeDuration: TimeInterval { max(duration, 1) }

    private var displayFraction: Double {
        let t = isScrubbing ? scrubValue : value
        return min(max(t / safeDuration, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let height = isScrubbing ? activeTrackHeight : trackHeight
            let trackWidth = proxy.size.width

            ZStack(alignment: .leading) {
                // Background track — hairline, no fill.
                Rectangle()
                    .fill(Color.offscriptProgressTrack)
                    .frame(height: height)

                // Filled progress — flat yellow, no gradient.
                Rectangle()
                    .fill(Color.offscriptAccent)
                    .frame(width: max(trackWidth * displayFraction, height), height: height)

                // Thumb — square instrument key, no shadow.
                Rectangle()
                    .fill(Color.offscriptAccent)
                    .frame(width: thumbSize, height: thumbSize)
                    .scaleEffect(isScrubbing ? 1.15 : 1)
                    .offset(x: thumbOffset(trackWidth: trackWidth))
            }
            .frame(height: max(thumbSize, activeTrackHeight))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isScrubbing {
                            isScrubbing = true
                            scrubValue = value
                        }
                        let fraction = min(max(gesture.location.x / trackWidth, 0), 1)
                        scrubValue = fraction * safeDuration
                    }
                    .onEnded { gesture in
                        let fraction = min(max(gesture.location.x / trackWidth, 0), 1)
                        let finalValue = fraction * safeDuration
                        value = finalValue
                        onSeek?(finalValue)
                        isScrubbing = false
                    }
            )
            .animation(.easeOut(duration: 0.15), value: isScrubbing)
        }
        .frame(height: max(thumbSize, activeTrackHeight))
        .accessibilityElement()
        .accessibilityValue("\(Int(displayFraction * 100)) percent")
        .accessibilityLabel("Playback position")
    }

    private func thumbOffset(trackWidth: CGFloat) -> CGFloat {
        let usable = trackWidth - thumbSize
        return usable * displayFraction
    }
}

struct OffScriptSurfaceModifier: ViewModifier {
    var radius: CGFloat = OffScriptTheme.Radius.medium
    var prominent: Bool = false

    /// Tuner OLED surface — flat panel + hairline. No gradient. No grain.
    /// No drop shadow (instrument clusters don't have lifted cards). The
    /// `prominent` variant just bumps the panel one step on the elevation
    /// ramp so a hero card reads slightly above its siblings.
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(prominent ? Color.offscriptCardRaised : Color.offscriptCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.offscriptHairline, lineWidth: 0.5)
            )
    }
}

struct OffScriptUtilitySurfaceModifier: ViewModifier {
    var radius: CGFloat = OffScriptTheme.Radius.medium

    /// Recessed surface — pure black with a hairline. Used for inputs,
    /// search fields, settings rows.
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.offscriptCardUtility)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.offscriptHairline, lineWidth: 0.5)
            )
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

    /// Tuner primary CTA — square-ish hairline-bordered slab with a yellow
    /// fill and uppercase mono label. Replaces the warm capsule pill that
    /// the previous theme used. Stays a Capsule shape for layout
    /// compatibility, but visually reads as an OLED action key.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(.black)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(Color.offscriptAccent.opacity(configuration.isPressed ? 0.72 : 1.0))
            .clipShape(Capsule())
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.96 : 1.0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryPillButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Tuner secondary action — outlined hairline pill, no fill, mono cap
    /// label. Sits next to a primary pill without competing for weight.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(Color.offscriptTextPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color.white.opacity(configuration.isPressed ? 0.06 : 0))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.offscriptHairline, lineWidth: 0.5)
            )
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.97 : 1.0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
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
                .fill(Color.offscriptFillSubtle)
                .frame(width: 190, height: 142)

            VStack(alignment: .leading, spacing: 8) {
                Capsule()
                    .fill(Color.offscriptFillSubtle)
                    .frame(width: 70, height: 16)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.offscriptFillSubtle)
                    .frame(width: 80, height: 10)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.offscriptFillSubtle)
                    .frame(width: 140, height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.offscriptFillSubtle)
                    .frame(width: 100, height: 10)
            }

            Capsule()
                .fill(Color.offscriptFillSubtle)
                .frame(width: 56, height: 32)
        }
        .padding(16)
        .frame(width: 222, alignment: .leading)
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
                .fill(Color.offscriptFillSubtle)
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
                    .fill(Color.offscriptFillSubtle)
                    .frame(height: 22)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.offscriptFillSubtle)
                    .frame(width: 200, height: 22)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.offscriptFillSubtle)
                    .frame(width: 140, height: 12)

                HStack(spacing: 10) {
                    Capsule()
                        .fill(Color.offscriptFillSubtle)
                        .frame(width: 64, height: 36)
                    Capsule()
                        .fill(Color.offscriptFillSubtle)
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
                    .fill(Color.offscriptFillSubtle)
                    .frame(width: 200, height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.offscriptFillSubtle)
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

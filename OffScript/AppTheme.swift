import SafariServices
import ImageIO
import SwiftUI
import UIKit

private extension CGFloat {
    func offscriptScaled(_ textStyle: UIFont.TextStyle = .caption2) -> CGFloat {
        UIFontMetrics(forTextStyle: textStyle).scaledValue(for: self)
    }
}

// MARK: - HTML Stripping

private enum HTMLPlainTextCache {
    static let cache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 500
        cache.totalCostLimit = 2_000_000
        return cache
    }()

    static func plainText(for html: String, builder: () -> String) -> String {
        let key = html as NSString
        if let cached = cache.object(forKey: key) {
            return cached as String
        }
        let value = builder()
        cache.setObject(value as NSString, forKey: key, cost: html.utf8.count + value.utf8.count)
        return value
    }
}

extension String {
    /// Strips HTML tags and decodes common entities for display as plain text.
    var strippingHTML: String {
        guard contains("<") || contains("&") else { return self }
        return HTMLPlainTextCache.plainText(for: self) {
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
    static let pagePadding: CGFloat = 16        // Tuner is tighter than the editorial direction
    static let rootContentTopPadding: CGFloat = 2
    static let modalContentTopPadding: CGFloat = 8
    static let detailContentTopPadding: CGFloat = 18
    static let spaciousPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static let itemSpacing: CGFloat = 12

    // Tuner panels are sharp (instrument cluster vocabulary), not rounded.
    enum Radius {
        static let small: CGFloat  = 3
        static let medium: CGFloat = 4
        static let large: CGFloat  = 6
    }
}

extension Color {
    // Tuner OLED palette — pure black field + signal-yellow primary accent +
    // function-coded accents (red/green/yellow/cyan) for tag pills and ring meters.
    // Token names kept stable so existing call sites adopt the new look automatically.

    static let offscriptStudioBlack = Color(red: 0, green: 0, blue: 0)
    static let offscriptInkCharcoal = Color(red: 0, green: 0, blue: 0)
    static let offscriptGraphitePlate = Color(red: 0.039, green: 0.039, blue: 0.039)   // #0a0a0a — barely-there panel
    static let offscriptLiftedGraphite = Color(red: 0.075, green: 0.075, blue: 0.082)  // #131316 — secondary panel
    static let offscriptWarmSlate = Color(red: 0.102, green: 0.102, blue: 0.110)       // #1a1a1c — metal
    static let offscriptPaperWhite = Color(red: 0.953, green: 0.945, blue: 0.918)      // #f3f1ea — primary text
    static let offscriptSoftPaper = Color(red: 0.478, green: 0.471, blue: 0.447)       // #7a7872 — dim text
    static let offscriptFadedPaper = Color(red: 0.953, green: 0.945, blue: 0.918).opacity(0.32) // textFaint

    // Signal yellow — primary instrument color (Tuner's accent)
    static let offscriptSignalYellow = Color(red: 0.910, green: 0.824, blue: 0.290)    // #e8d24a
    static let offscriptSignalYellowDim = Color(red: 0.910, green: 0.824, blue: 0.290).opacity(0.35)

    // Functional accent set — Ferrari instrument-cluster mapping
    static let offscriptFnRecord = Color(red: 0.910, green: 0.353, blue: 0.235)        // #e85a3c — red, record/critical/warning
    static let offscriptFnMode   = Color(red: 0.373, green: 0.812, blue: 0.494)        // #5fcf7e — green, mode/state/positive
    static let offscriptFnInfo   = Color(red: 0.365, green: 0.769, blue: 0.910)        // #5dc4e8 — cyan, passive info
    static let offscriptFnMute   = Color(red: 0.478, green: 0.471, blue: 0.447)        // gray, off

    // Legacy aliases (back-compat for screens not yet ported)
    static let offscriptSignalOrange = offscriptSignalYellow
    static let offscriptCopperGlow = offscriptSignalYellow.opacity(0.6)
    static let offscriptCreamNote = offscriptPaperWhite
    static let offscriptAcidBookmark = offscriptFnMode

    static let offscriptBackground = offscriptStudioBlack
    static let offscriptBackgroundTop = offscriptStudioBlack
    static let offscriptBackgroundBottom = offscriptStudioBlack

    // Cards: in the Tuner vocabulary, panels are transparent with hairline borders.
    // We keep these tokens addressable but remap them to near-black — the
    // surface modifiers below switch to flat-black + hairline rather than gradients.
    static let offscriptCard = offscriptStudioBlack
    static let offscriptCardRaised = offscriptGraphitePlate
    static let offscriptCardStrong = offscriptStudioBlack
    static let offscriptCardUtility = offscriptStudioBlack

    static let offscriptAccent = offscriptSignalYellow
    static let offscriptAccentSoft = offscriptSignalYellow.opacity(0.18)
    static let offscriptTextPrimary = offscriptPaperWhite
    static let offscriptTextSecondary = offscriptSoftPaper
    static let offscriptTextMuted = offscriptSoftPaper.opacity(0.7)
    static let offscriptHairline = Color.white.opacity(0.08)
    static let offscriptProgressTrack = Color.white.opacity(0.08)
    static let offscriptFillSubtle = Color.white.opacity(0.04)
    static let offscriptFillLight = Color.white.opacity(0.06)

    // Secondary accent — cyan info pill in the Tuner vocabulary
    static let offscriptAccentSecondary = offscriptFnInfo
    static let offscriptAccentSecondaryMuted = offscriptFnInfo.opacity(0.14)

    // Destructive — Tuner's record-red
    static let offscriptDestructive = offscriptFnRecord
    static let offscriptDestructiveSoft = offscriptFnRecord.opacity(0.16)

    // Surface tints — used by call sites that came in from origin/main
    // (replace inline Color.white.opacity literals). Kept for back-compat.
    static let offscriptSurfaceFaint  = Color.white.opacity(0.04)
    static let offscriptSurfaceSubtle = Color.white.opacity(0.05)
    static let offscriptSurfaceThin   = Color.white.opacity(0.06)
    static let offscriptSurfaceLight  = Color.white.opacity(0.08)
    static let offscriptSurfaceMedium = Color.white.opacity(0.12)
}

extension Font {
    // Tuner typography — instrument-cluster grotesque + monospaced metadata.
    // Headlines: SF Pro Display at light weights with tight tracking (Space Grotesk feel).
    // Metadata: SF Mono with wide tracking + uppercase (JetBrains Mono feel).
    static let offscriptHero          = Font.system(size: 56, weight: .bold,    design: .default)
    static let offscriptDisplay       = Font.system(size: 26, weight: .light,   design: .default)
    static let offscriptUtilityTitle  = Font.system(.title2,  design: .default, weight: .bold)
    static let offscriptSectionTitle  = Font.system(size: 22, weight: .bold,    design: .default)
    static let offscriptCardTitle     = Font.system(.headline, design: .default, weight: .semibold)
    static let offscriptBody          = Font.system(.callout,  design: .default)
    static let offscriptMeta          = Font.system(.caption,  design: .monospaced).weight(.medium)
    static let offscriptMicro         = Font.system(.caption2, design: .monospaced).weight(.medium)

    // Instrument-cluster specific — explicit Tuner vocabulary
    static let tunerLabel             = Font.system(size: 9,  weight: .semibold, design: .monospaced)
    static let tunerLabelLg           = Font.system(size: 11, weight: .semibold, design: .monospaced)
    static let tunerTag               = Font.system(size: 8,  weight: .semibold, design: .monospaced)
    static let tunerReadout           = Font.system(size: 38, weight: .light,    design: .default)
    static let tunerReadoutMd         = Font.system(size: 24, weight: .light,    design: .default)
}

struct OffScriptBackgroundView: View {
    var body: some View {
        // Tuner: pure OLED black field. No gradient, no grain — strokes do the work.
        Color.offscriptStudioBlack
    }
}

struct OffScriptArtworkPlaceholder: View {
    var cornerRadius: CGFloat = 3

    var body: some View {
        // Tuner: cassette-cartridge placeholder — flat black, hairline border,
        // with a clipped corner notch and a small mono "NO SIGNAL" tag.
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.offscriptStudioBlack)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.offscriptHairline, lineWidth: 1)
                )

            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.offscriptSoftPaper)
        }
    }
}

// MARK: - Image Cache

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
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
        return URLSession(configuration: config)
    }()
    private let inFlightLock = NSLock()
    private var inFlightTasks: [NSString: Task<UIImage?, Never>] = [:]

    func image(for url: URL, maxPixelDimension: CGFloat? = nil) -> UIImage? {
        memoryCache.object(forKey: cacheKey(for: url, maxPixelDimension: maxPixelDimension))
    }

    func loadImage(from url: URL, maxPixelDimension: CGFloat? = nil) async -> UIImage? {
        let key = cacheKey(for: url, maxPixelDimension: maxPixelDimension)
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        let task = Task<UIImage?, Never> { [session] in
            guard let (data, _) = try? await session.data(from: url) else {
                return nil
            }
            return Self.decodeImage(from: data, maxPixelDimension: maxPixelDimension)
        }
        if let existingTask = registerInFlightTask(task, for: key) {
            task.cancel()
            return await existingTask.value
        }

        let image = await task.value
        clearInFlightTask(for: key)

        guard let image else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        memoryCache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// Returns an existing task for this key, or registers the provided task as the owner.
    private func registerInFlightTask(_ task: Task<UIImage?, Never>, for key: NSString) -> Task<UIImage?, Never>? {
        inFlightLock.lock()
        defer { inFlightLock.unlock() }
        if let existingTask = inFlightTasks[key] {
            return existingTask
        }
        inFlightTasks[key] = task
        return nil
    }

    private func clearInFlightTask(for key: NSString) {
        inFlightLock.lock()
        defer { inFlightLock.unlock() }
        inFlightTasks[key] = nil
    }

    private func cacheKey(for url: URL, maxPixelDimension: CGFloat?) -> NSString {
        guard let maxPixelDimension, maxPixelDimension > 0 else {
            return url.absoluteString as NSString
        }
        return "\(url.absoluteString)#\(Int(maxPixelDimension.rounded(.up)))" as NSString
    }

    private static func decodeImage(from data: Data, maxPixelDimension: CGFloat?) -> UIImage? {
        guard let maxPixelDimension, maxPixelDimension > 0 else {
            return UIImage(data: data)
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelDimension.rounded(.up))),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    var maxPixelDimension: CGFloat? = nil
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?
    @State private var didFail = false

    private var loadID: String {
        "\(url?.absoluteString ?? "nil")#\(Int((maxPixelDimension ?? 0).rounded(.up)))"
    }

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else if didFail {
                placeholder()
            } else {
                placeholder()
            }
        }
        .task(id: loadID) {
            guard let url else {
                uiImage = nil
                didFail = true
                return
            }

            if let image = ImageCache.shared.image(for: url, maxPixelDimension: maxPixelDimension) {
                uiImage = image
                didFail = false
                return
            }

            uiImage = nil
            didFail = false
            guard let image = await ImageCache.shared.loadImage(from: url, maxPixelDimension: maxPixelDimension) else {
                if !Task.isCancelled {
                    didFail = true
                }
                return
            }
            guard !Task.isCancelled else {
                return
            }
            uiImage = image
            didFail = false
        }
    }
}

struct OffScriptArtworkView: View {
    @Environment(\.displayScale) private var displayScale

    let url: URL?
    var cornerRadius: CGFloat = OffScriptTheme.Radius.medium
    var fixedSize: CGSize? = nil

    var body: some View {
        if let fixedSize {
            artwork(size: fixedSize)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            GeometryReader { proxy in
                artwork(size: proxy.size)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    private func artwork(size: CGSize) -> some View {
        let maxPixelDimension = min(max(size.width, size.height) * displayScale, 1024)
        return CachedAsyncImage(url: url, maxPixelDimension: maxPixelDimension) { image in
            image
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .overlay(
                    // Subtle bottom shadow on artwork — uses studio-black
                    // token for consistency with the OLED Tuner field
                    // instead of bare Color.black.opacity (CLAUDE.md
                    // forbids inline opacity on raw white/black).
                    LinearGradient(
                        colors: [Color.clear, Color.offscriptStudioBlack.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        } placeholder: {
            OffScriptArtworkPlaceholder(cornerRadius: cornerRadius)
                .frame(width: size.width, height: size.height)
        }
    }
}

extension OffScriptArtworkView {
    init(url: URL?, cornerRadius: CGFloat = OffScriptTheme.Radius.medium, size: CGFloat) {
        self.url = url
        self.cornerRadius = cornerRadius
        self.fixedSize = CGSize(width: size, height: size)
    }

    init(url: URL?, cornerRadius: CGFloat = OffScriptTheme.Radius.medium, size: CGSize) {
        self.url = url
        self.cornerRadius = cornerRadius
        self.fixedSize = size
    }
}

// Removed unused legacy chrome: OffScriptReasonBadge, OffScriptExplanationTag,
// OffScriptEmptyState, OffScriptSectionHeader, OffScriptUtilityHeader,
// OffScriptProgressBar, OffScriptScrubber. None had call sites after the
// Tuner port; keeping dead definitions around made the AppTheme look like
// there were two design vocabularies still in active use, which (correctly)
// reads as "the Tuner UI isn't fully implemented." It is — the residue was
// just confusing.

// MARK: - Tuner instrument-cluster primitives
// OLED-cluster vocabulary lifted from the Tuner design direction. Each lives on
// pure black; strokes do the work. Composed into Player, MiniPlayer, Home dial,
// Channel Bank rows, etc.

/// Outlined tag pill — "MODE: DRY" / "EZRA KLEIN" style. The label, not the value.
struct TunerTag: View {
    let text: String
    var color: Color = .offscriptSignalYellow
    var dim: Bool = false
    var wraps: Bool = false

    var body: some View {
        if wraps {
            baseTag
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            baseTag
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
        }
    }

    private var baseTag: some View {
        Text(text.uppercased())
            .font(.system(size: CGFloat(8.5).offscriptScaled(), weight: .semibold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(dim ? color.opacity(0.6) : color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .overlay(
                // Sharp hairline rectangle — Tuner vocabulary is rectilinear,
                // never a rounded capsule. The capsule outline that lived
                // here violated the rule on every surface that uses TunerTag
                // (hero cards, rail cards, AI reason badges).
                Rectangle().stroke(color.opacity(dim ? 0.33 : 0.66), lineWidth: 1)
            )
    }
}

struct TunerRailReasonTag: View {
    let text: String
    var color: Color = .offscriptSignalYellow

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: CGFloat(7.8).offscriptScaled(), weight: .semibold, design: .monospaced))
            .tracking(0.4)
            .foregroundStyle(color.opacity(0.68))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                Rectangle().stroke(color.opacity(0.32), lineWidth: 1)
            )
    }
}

struct RecommendationSignalTraceView: View {
    let signals: [RecommendationSignal]
    var limit: Int = 3
    var color: Color = .offscriptFnInfo

    var body: some View {
        if !signals.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(signals.prefix(limit)), id: \.self) { signal in
                    Text(signal.displayText.uppercased())
                        .font(.system(size: CGFloat(8.5).offscriptScaled(), weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(color.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            Rectangle()
                                .fill(color.opacity(0.4))
                                .frame(width: 1),
                            alignment: .leading
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Inline navigation key for pushed Tuner detail screens. The visible control
/// stays compact, but the outer frame preserves a 44pt hit target.
struct TunerInlineBackButton: View {
    let label: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                TunerLabel(text: label, color: .offscriptSignalYellow, size: 10)
            }
            .foregroundStyle(Color.offscriptSignalYellow)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
            .frame(minWidth: 44, minHeight: 44, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

// TunerRingMeter, TunerTrace, TunerTransportButton, TunerModeToggle,
// TunerArtworkTile were defined for the design spec but never composed
// into any actual screen. The Player built its own transport row, the
// scrubber went native Slider, the rail cards use sharp OffScriptArtworkView
// tiles, and the filter chips landed as inline Tuner buttons. Removed to
// clear the noise.

/// Tagged Ferrari-cluster readout: tag pill above, thin large value below.
struct TunerReadout: View {
    let tag: String
    var tagColor: Color = .offscriptFnMode
    let value: String
    var unit: String? = nil
    var size: Size = .lg

    enum Size { case lg, md, sm }

    private var fontSize: CGFloat {
        switch size { case .lg: return 38; case .md: return 24; case .sm: return 16 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TunerTag(text: tag, color: tagColor)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: fontSize.offscriptScaled(.title1), weight: .light, design: .default))
                    .tracking(0)
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.system(size: (fontSize * 0.45).offscriptScaled(.caption1), weight: .regular, design: .default))
                        .foregroundStyle(Color.offscriptSoftPaper)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
        }
    }
}

/// Tiny mono label — section eyebrow / status strip / data caption.
struct TunerLabel: View {
    let text: String
    var color: Color = .offscriptSoftPaper
    var size: CGFloat = 9

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size.offscriptScaled(), weight: .semibold, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(color)
            .monospacedDigit()
    }
}

struct TunerRatePicker: View {
    let rates: [Float]
    let selectedRate: Float
    var accessibilityActionPrefix = "Set playback rate to"
    let onSelect: (Float) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 8) {
            ForEach(rates, id: \.self) { rate in
                let isSelected = abs(selectedRate - rate) < 0.001
                Button {
                    onSelect(rate)
                } label: {
                    HStack(spacing: 6) {
                        TunerLabel(
                            text: String(format: "%.2g×", rate),
                            color: isSelected ? .offscriptStudioBlack : .offscriptPaperWhite,
                            size: 10
                        )
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.offscriptStudioBlack)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(isSelected ? Color.offscriptSignalYellow : Color.clear)
                    .overlay(Rectangle().stroke(isSelected ? Color.offscriptSignalYellow : Color.offscriptHairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(accessibilityActionPrefix) \(String(format: "%.2g×", rate))")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// Cassette/cartridge artwork tile — flat fill with a hairline border, corner
// (TunerArtworkTile removed — placeholder cassette tile was never composed
// into any view; OffScriptArtworkPlaceholder + OffScriptArtworkView fill
// the artwork-when-no-URL slot everywhere with sharp 3pt corners.)

struct OffScriptSurfaceModifier: ViewModifier {
    // Tuner panel: transparent fill with a single 1px hairline. Sharper corner radius
    // (Tuner uses 3–4px). No gradient, no shadow — instruments float on the OLED field.
    var radius: CGFloat = 4
    var prominent: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(prominent ? Color.offscriptGraphitePlate : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.offscriptHairline, lineWidth: 1)
            )
    }
}

struct OffScriptUtilitySurfaceModifier: ViewModifier {
    var radius: CGFloat = 4

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.offscriptStudioBlack)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.offscriptHairline, lineWidth: 1)
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

    /// Keep SwiftUI sheet/full-screen hosts from falling back to iOS 26's
    /// translucent Liquid Glass presentation surface. App-controlled modals
    /// should read as the same flat OLED instrument panel as the main shell.
    func tunerModalSurface() -> some View {
        preferredColorScheme(.dark)
            .presentationBackground(Color.offscriptStudioBlack)
            .presentationCornerRadius(0)
            .presentationDragIndicator(.hidden)
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

// PrimaryPillButtonStyle / SecondaryPillButtonStyle were the pre-Tuner
// rounded pill buttons (orange Resume / glass Queue). All call sites have
// migrated to Tuner sharp-rectangle keys defined inline on each surface.
// Removed to keep the rounded vocabulary out of the codebase entirely.

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
                            // Shimmer highlight uses the hairline token —
                            // CLAUDE.md forbids bare `Color.white.opacity`.
                            .init(color: Color.offscriptHairline, location: center),
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

// GrainOverlay / offscriptGrain were the editorial-paper grain texture from
// the original "warm-to-cool gradient + grain" direction. Tuner is flat OLED
// black so grain has no place. Removed; nothing referenced it after the
// Tuner port.

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

// SkeletonRailCard / SkeletonHeroCard / SkeletonSearchRow were the
// pre-Tuner loading skeletons (rounded fills, capsule chips). The Tuner
// rails use sharp hairline placeholders rendered inline on each surface
// instead, so these primitives have no callers. Removed.

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

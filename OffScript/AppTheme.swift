import SafariServices
import ImageIO
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
    static let pagePadding: CGFloat = 16        // Tuner is tighter than the editorial direction
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

    var body: some View {
        GeometryReader { proxy in
            let maxPixelDimension = min(max(proxy.size.width, proxy.size.height) * displayScale, 1024)
            CachedAsyncImage(url: url, maxPixelDimension: maxPixelDimension) { image in
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
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.offscriptFillLight)
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

// Tuner section header — mono kicker (numbered if you pass one) + heavy display
// title with negative tracking. Subtitle in mono caption to feel like a caption
// strip rather than body copy.
struct OffScriptSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .default))
                .tracking(-0.3)
                .foregroundStyle(Color.offscriptPaperWhite)
            Text(subtitle.uppercased())
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.offscriptSoftPaper)
                .lineLimit(2)
        }
    }
}

// Tuner utility header — numbered eyebrow over a heavy display title and a
// mono caption strip, matching the Channel Bank vocabulary.
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
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow {
                TunerLabel(text: eyebrow, color: .offscriptSignalYellow)
            }

            Text(title)
                .font(.system(size: 26, weight: .bold, design: .default))
                .tracking(-0.5)
                .foregroundStyle(Color.offscriptPaperWhite)

            Text(subtitle.uppercased())
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.offscriptSoftPaper)
        }
    }
}

struct OffScriptProgressBar: View {
    // Tuner: a single-pixel filled segment on a hairline rail. No capsules, no gradients.
    let value: Double
    var height: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(value, 0), 1)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.offscriptHairline)
                    .frame(height: 1)
                Rectangle()
                    .fill(Color.offscriptSignalYellow)
                    .frame(width: proxy.size.width * clamped, height: height)
            }
        }
        .frame(height: max(height, 2))
        .accessibilityElement()
        .accessibilityValue("\(Int(min(max(value, 0), 1) * 100)) percent")
        .accessibilityLabel("Progress")
    }
}

struct OffScriptScrubber: View {
    // Tuner: instrument-scale scrubber. A tick rule (major 10s / minor 5s / fine 1s),
    // a single thin playhead, mono "NOW" caption above it, no thumb.
    @Binding var value: TimeInterval
    let duration: TimeInterval
    var onSeek: ((TimeInterval) -> Void)? = nil

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    private let scaleHeight: CGFloat = 22
    private let majorTick: CGFloat = 10
    private let minorTick: CGFloat = 6
    private let fineTick: CGFloat  = 3
    private let tickCount = 60

    private var safeDuration: TimeInterval { max(duration, 1) }
    private var displayFraction: Double {
        let t = isScrubbing ? scrubValue : value
        return min(max(t / safeDuration, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = proxy.size.width
            let playheadX = trackWidth * CGFloat(displayFraction)

            ZStack(alignment: .topLeading) {
                ForEach(0...tickCount, id: \.self) { i in
                    let isMajor = i % 10 == 0
                    let isMinor = !isMajor && i % 5 == 0
                    let h: CGFloat = isMajor ? majorTick : (isMinor ? minorTick : fineTick)
                    Rectangle()
                        .fill(Color.offscriptHairline)
                        .frame(width: 1, height: h)
                        .offset(x: trackWidth * CGFloat(i) / CGFloat(tickCount))
                }

                Rectangle()
                    .fill(Color.offscriptSignalYellow)
                    .frame(width: max(playheadX, 1), height: 1)
                    .offset(y: 12)

                Rectangle()
                    .fill(Color.offscriptPaperWhite)
                    .frame(width: 1, height: scaleHeight + 4)
                    .offset(x: playheadX - 0.5, y: -2)

                Text("NOW")
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .padding(.horizontal, 3)
                    .background(Color.offscriptStudioBlack)
                    .offset(x: playheadX - 11, y: -10)
            }
            .frame(width: trackWidth, height: scaleHeight, alignment: .topLeading)
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
        }
        .frame(height: scaleHeight + 6)
        .accessibilityElement()
        .accessibilityValue("\(Int(displayFraction * 100)) percent")
        .accessibilityLabel("Playback position")
    }
}

// MARK: - Tuner instrument-cluster primitives
// OLED-cluster vocabulary lifted from the Tuner design direction. Each lives on
// pure black; strokes do the work. Composed into Player, MiniPlayer, Home dial,
// Channel Bank rows, etc.

/// Outlined tag pill — "MODE: DRY" / "EZRA KLEIN" style. The label, not the value.
struct TunerTag: View {
    let text: String
    var color: Color = .offscriptSignalYellow
    var dim: Bool = false

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(dim ? color.opacity(0.6) : color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .overlay(
                Capsule().stroke(color.opacity(dim ? 0.33 : 0.66), lineWidth: 1)
            )
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
    }
}

/// Ring meter — colored arc on a hairline base. value 0…1; glyph is the
/// optical-center text (e.g. "34%", "1.2×", "OFF", "−6"); units optionally sit
/// inside the ring. Built so a row of meters shares one optical baseline.
struct TunerRingMeter: View {
    let value: Double
    var size: CGFloat = 56
    var color: Color = .offscriptSignalYellow
    var label: String? = nil
    var glyph: String? = nil
    var units: String? = nil
    var active: Bool = true

    private var stroke: CGFloat { 1.25 }
    private var fraction: Double { min(max(value, 0), 1) }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.offscriptHairline, lineWidth: stroke)
                    .frame(width: size, height: size)

                if active {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .frame(width: size, height: size)
                }

                Rectangle()
                    .fill(color)
                    .frame(width: stroke, height: 4)
                    .offset(y: -size / 2 + 2)

                VStack(spacing: 0) {
                    Text(glyph ?? "\(Int(fraction * 100))")
                        .font(.system(
                            size: (glyph?.count ?? 2) >= 4 ? size * 0.26 : size * 0.30,
                            weight: .medium,
                            design: .monospaced
                        ))
                        .tracking(-0.3)
                        .foregroundStyle(active ? Color.offscriptPaperWhite : Color.offscriptSoftPaper)
                        .monospacedDigit()
                    if let units {
                        Text(units.uppercased())
                            .font(.system(size: 6.5, weight: .regular, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(Color.offscriptFadedPaper)
                    }
                }
            }

            if let label {
                Text(label.uppercased())
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.offscriptSoftPaper)
                    .monospacedDigit()
            }
        }
    }
}

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
                    .font(.system(size: fontSize, weight: .light, design: .default))
                    .tracking(-1)
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.system(size: fontSize * 0.45, weight: .regular, design: .default))
                        .foregroundStyle(Color.offscriptSoftPaper)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
        }
    }
}

/// Sparse single-pixel polyline trace — oscilloscope sparkline.
struct TunerTrace: View {
    let data: [Double]
    var color: Color = .offscriptSignalYellow
    var height: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let lo = data.min() ?? 0
            let hi = data.max() ?? 1
            let span = max(hi - lo, 0.0001)

            Path { path in
                guard data.count > 1 else { return }
                for (i, v) in data.enumerated() {
                    let x = w * CGFloat(i) / CGFloat(data.count - 1)
                    let y = h - CGFloat((v - lo) / span) * (h - 4) - 2
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, lineWidth: 0.75)
        }
        .frame(height: height)
    }
}

/// Hairline transport cell with a fixed icon area + cap label area. Every cell
/// shares one skeleton — play key's signal-yellow ring lives in the same fixed
/// icon slot so the row stays perfectly level.
struct TunerTransportButton: View {
    enum Kind { case skipBack(Int), skipForward(Int), prev, next, play(isPlaying: Bool) }

    let kind: Kind
    let action: () -> Void

    private var cap: String {
        switch kind {
        case .skipBack(let s): return "\(s)"
        case .skipForward(let s): return "\(s)"
        case .prev: return "PREV"
        case .next: return "NEXT"
        case .play(let p): return p ? "PAUSE" : "PLAY"
        }
    }

    private var iconColor: Color {
        if case .play = kind { return .offscriptSignalYellow }
        return .offscriptPaperWhite
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .play(let isPlaying):
            ZStack {
                Circle()
                    .stroke(Color.offscriptSignalYellow, lineWidth: 1.25)
                    .frame(width: 38, height: 38)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.offscriptSignalYellow)
                    .offset(x: isPlaying ? 0 : 1)
            }
        case .prev:
            Image(systemName: "backward.end.fill")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(iconColor)
        case .next:
            Image(systemName: "forward.end.fill")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(iconColor)
        case .skipBack:
            Image(systemName: "gobackward")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(iconColor)
        case .skipForward:
            Image(systemName: "goforward")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(iconColor)
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                icon.frame(height: 38)
                Text(cap)
                    .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(iconColor.opacity(0.7))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Outlined mode-toggle pill — only the active one is colored.
struct TunerModeToggle: View {
    let label: String
    let isOn: Bool
    var activeColor: Color = .offscriptSignalYellow
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(isOn ? activeColor : Color.offscriptSoftPaper)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(
                    Capsule().stroke(isOn ? activeColor : Color.offscriptHairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Tiny mono label — section eyebrow / status strip / data caption.
struct TunerLabel: View {
    let text: String
    var color: Color = .offscriptSoftPaper
    var size: CGFloat = 9

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(color)
            .monospacedDigit()
    }
}

/// Cassette/cartridge artwork tile — flat fill with a hairline border, corner
/// notch, and a small mono channel number + abbreviated podcast name overlay.
/// Used as a placeholder when no real artwork URL is available.
struct TunerArtworkTile: View {
    let title: String
    let host: String
    let accent: Color
    var size: CGFloat = 72
    var channel: Int? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(LinearGradient(
                    colors: [accent.opacity(0.85), accent.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    Rectangle().stroke(Color.offscriptHairline, lineWidth: 1)
                )

            // Top-right corner notch
            Path { p in
                p.move(to: CGPoint(x: size, y: 0))
                p.addLine(to: CGPoint(x: size, y: 10))
                p.addLine(to: CGPoint(x: size - 10, y: 0))
                p.closeSubpath()
            }
            .fill(Color.offscriptStudioBlack)

            VStack(alignment: .leading, spacing: 0) {
                if let channel {
                    Text("\(String(format: "%03d", channel)) · \(host.split(separator: " ").first.map(String.init)?.uppercased() ?? "")")
                        .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(Color.offscriptStudioBlack.opacity(0.7))
                        .padding(.top, 4)
                        .padding(.horizontal, 4)
                }

                Spacer(minLength: 0)

                Text(title.split(separator: " ").prefix(2).joined(separator: " ").uppercased())
                    .font(.system(size: max(size * 0.13, 9), weight: .bold, design: .default))
                    .tracking(-0.5)
                    .foregroundStyle(Color.offscriptStudioBlack.opacity(0.85))
                    .lineLimit(2)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }
}

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
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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

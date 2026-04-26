import CoreImage
import Foundation
import OSLog
import SwiftUI
import UIKit

/// Extracts a small palette of dominant colors from a podcast artwork image.
/// Used to drive the player view's mesh gradient so it visually echoes the show.
@MainActor
final class ArtworkColorExtractor {
    static let shared = ArtworkColorExtractor()

    struct Palette: Equatable {
        var deep: Color      // Darkest tone, used for corners
        var midPrimary: Color
        var midSecondary: Color
        var accent: Color    // Most saturated tone, used as highlight
    }

    private let logger = Logger(subsystem: "OffScript", category: "ArtworkColor")
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var cache: [URL: Palette] = [:]
    private let inflight = NSCountedSet()

    private init() {}

    func cached(for url: URL?) -> Palette? {
        guard let url else { return nil }
        return cache[url]
    }

    func extract(from url: URL?) async -> Palette? {
        guard let url else { return nil }
        if let cached = cache[url] { return cached }

        guard let image = await ImageCache.shared.loadImage(from: url) else { return nil }
        guard let ciImage = CIImage(image: image) else { return nil }

        let extent = ciImage.extent
        let w = extent.width
        let h = extent.height

        // Sample 5 regions: 4 quadrants + center.
        let regions: [CGRect] = [
            CGRect(x: 0, y: 0, width: w * 0.5, height: h * 0.5),
            CGRect(x: w * 0.5, y: 0, width: w * 0.5, height: h * 0.5),
            CGRect(x: 0, y: h * 0.5, width: w * 0.5, height: h * 0.5),
            CGRect(x: w * 0.5, y: h * 0.5, width: w * 0.5, height: h * 0.5),
            CGRect(x: w * 0.25, y: h * 0.25, width: w * 0.5, height: h * 0.5)
        ]

        let colors: [UIColor] = regions.compactMap { region in
            averageColor(of: ciImage, in: region)
        }

        guard colors.count >= 4 else { return nil }

        let palette = makePalette(from: colors)
        cache[url] = palette
        return palette
    }

    private func averageColor(of image: CIImage, in region: CGRect) -> UIColor? {
        let parameters: [String: Any] = [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: region)
        ]
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: parameters),
              let output = filter.outputImage else {
            return nil
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return UIColor(
            red: CGFloat(bitmap[0]) / 255.0,
            green: CGFloat(bitmap[1]) / 255.0,
            blue: CGFloat(bitmap[2]) / 255.0,
            alpha: 1.0
        )
    }

    private func makePalette(from colors: [UIColor]) -> Palette {
        // Sort by perceived brightness (Y in YIQ).
        let sorted = colors
            .map { color -> (UIColor, CGFloat, CGFloat) in
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                color.getRed(&r, green: &g, blue: &b, alpha: nil)
                let brightness = 0.299 * r + 0.587 * g + 0.114 * b
                let saturation: CGFloat = {
                    let maxC = max(r, g, b)
                    let minC = min(r, g, b)
                    guard maxC > 0 else { return 0 }
                    return (maxC - minC) / maxC
                }()
                return (color, brightness, saturation)
            }

        let darkest = sorted.min(by: { $0.1 < $1.1 })!.0
        let mostSaturated = sorted.max(by: { $0.2 < $1.2 })!.0
        let mids = sorted
            .filter { $0.0 != darkest && $0.0 != mostSaturated }
            .map { $0.0 }

        let mid1 = mids.first ?? mostSaturated
        let mid2 = mids.dropFirst().first ?? darkest

        // Pull the deep tone toward black so it feels grounded against the page.
        let deep = blend(darkest, with: .black, fraction: 0.35)

        return Palette(
            deep: Color(deep),
            midPrimary: Color(mid1),
            midSecondary: Color(mid2),
            accent: Color(boost(mostSaturated, saturationBoost: 0.2))
        )
    }

    private func blend(_ a: UIColor, with b: UIColor, fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: nil)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: nil)
        return UIColor(
            red: r1 + (r2 - r1) * fraction,
            green: g1 + (g2 - g1) * fraction,
            blue: b1 + (b2 - b1) * fraction,
            alpha: 1
        )
    }

    private func boost(_ color: UIColor, saturationBoost: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: min(1, s + saturationBoost), brightness: b, alpha: a)
    }
}

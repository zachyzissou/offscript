import SwiftUI

/// Compatibility wrapper around iOS 26's Liquid Glass APIs. Uses
/// `.glassEffect()` when available, falls back to a richly-blended material
/// stack so the surface still reads as translucent on older runtimes.
///
/// The whole app routes through these modifiers so we can iterate on the
/// glass treatment in one place rather than hunting through views.
struct OffScriptGlassModifier: ViewModifier {
    var shape: AnyShape = AnyShape(Capsule(style: .continuous))
    var tinted: Bool = false
    var prominent: Bool = false

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    prominent ? .regular.tint(Color.offscriptAccent.opacity(0.18)) : .regular,
                    in: shape
                )
        } else {
            content
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay(
                            shape.fill(tinted ? Color.offscriptAccentSoft : Color.offscriptFillLight)
                        )
                }
                .overlay {
                    shape.stroke(Color.offscriptHairline, lineWidth: 0.5)
                }
        }
    }
}

extension View {
    /// Apply Liquid Glass to any surface. Capsule by default; pass another
    /// shape (RoundedRectangle, Circle) when you need it.
    func offscriptGlass(in shape: some Shape = Capsule(style: .continuous), tinted: Bool = false, prominent: Bool = false) -> some View {
        modifier(OffScriptGlassModifier(shape: AnyShape(shape), tinted: tinted, prominent: prominent))
    }
}

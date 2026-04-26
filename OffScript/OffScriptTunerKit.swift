import SwiftUI

// MARK: - Tuner UI primitives
//
// These are the new instrument-cluster components introduced by the Tuner
// design system. Existing screens still build against the legacy
// `OffScript…` widgets in `AppTheme.swift`; as each screen is converted it
// drops those in favor of these.
//
// Design language is borrowed wholesale from the OffScript Redesign HTML
// pack (Tuner direction): pure black field, signal-yellow accent, hairline
// strokes, mono uppercase labels, no gradients, no shadows, no rounded
// corners larger than 4pt anywhere.

// MARK: TTagPill
//
// Tiny outlined pill that carries one piece of categorical information.
// The Tuner UI uses these for episode numbers, host names, modes,
// recommendation reasons. Color carries semantic meaning:
//   .neutral → episode metadata (text primary outline)
//   .info    → "why we recommended this" (cyan)
//   .ok      → mode / status (mint)
//   .warn    → record / live / destructive (red)
//   .signal  → action / focus (signal yellow — sparingly)

enum TTagPillTone {
    case neutral, info, ok, warn, signal

    var stroke: Color {
        switch self {
        case .neutral: return .offscriptHairline
        case .info: return Color.offscriptAccentSecondary.opacity(0.45)
        case .ok: return Color.offscriptAccentOK.opacity(0.45)
        case .warn: return Color.offscriptDestructive.opacity(0.55)
        case .signal: return Color.offscriptAccent.opacity(0.55)
        }
    }

    var foreground: Color {
        switch self {
        case .neutral: return .offscriptTextPrimary
        case .info: return .offscriptAccentSecondary
        case .ok: return .offscriptAccentOK
        case .warn: return .offscriptDestructive
        case .signal: return .offscriptAccent
        }
    }
}

struct TTagPill: View {
    let label: String
    var tone: TTagPillTone = .neutral

    var body: some View {
        Text(label.uppercased())
            .font(.offscriptTagLabel)
            .tracking(1.4)
            .foregroundStyle(tone.foreground)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(tone.stroke, lineWidth: 0.5)
            )
            .accessibilityLabel(label)
    }
}

// MARK: TReadout
//
// Big-thin display value paired with a tiny mono uppercase label sitting
// above it. The Ferrari-cluster "210 km/h + SPEED" pattern. Use anywhere a
// single number deserves real estate (player timecode, "32m left", "1.25×",
// listener progress %).

struct TReadout: View {
    let value: String
    let unit: String?
    let label: String
    var tint: Color = .offscriptTextPrimary
    var size: CGFloat = 32
    var alignment: HorizontalAlignment = .leading

    init(value: String, unit: String? = nil, label: String, tint: Color = .offscriptTextPrimary, size: CGFloat = 32, alignment: HorizontalAlignment = .leading) {
        self.value = value
        self.unit = unit
        self.label = label
        self.tint = tint
        self.size = size
        self.alignment = alignment
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(label.uppercased())
                .font(.offscriptTagLabel)
                .tracking(1.6)
                .foregroundStyle(Color.offscriptTextMuted)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: size, weight: .ultraLight, design: .default).monospacedDigit())
                    .foregroundStyle(tint)
                if let unit {
                    Text(unit.uppercased())
                        .font(.system(size: max(10, size * 0.30), weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(Color.offscriptTextMuted)
                }
            }
        }
    }
}

// MARK: TRingMeter
//
// Circular hairline meter with a colored arc representing fill. Replaces
// every skeuomorphic knob / gauge in the previous theme. The center
// holds a value (or any view) — for plain text values use the value
// initializer; for richer centers use the `content` initializer.

struct TRingMeter<Center: View>: View {
    let value: Double
    var minValue: Double = 0
    var maxValue: Double = 1
    var tint: Color = .offscriptAccent
    var trackTint: Color = .offscriptHairline
    var lineWidth: CGFloat = 1.5
    var diameter: CGFloat = 56
    let label: String?
    @ViewBuilder let center: () -> Center

    init(
        value: Double,
        minValue: Double = 0,
        maxValue: Double = 1,
        tint: Color = .offscriptAccent,
        trackTint: Color = .offscriptHairline,
        lineWidth: CGFloat = 1.5,
        diameter: CGFloat = 56,
        label: String? = nil,
        @ViewBuilder center: @escaping () -> Center
    ) {
        self.value = value
        self.minValue = minValue
        self.maxValue = maxValue
        self.tint = tint
        self.trackTint = trackTint
        self.lineWidth = lineWidth
        self.diameter = diameter
        self.label = label
        self.center = center
    }

    private var fraction: Double {
        let range = maxValue - minValue
        guard range > 0 else { return 0 }
        return min(max((value - minValue) / range, 0), 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Track ring (hairline)
                Circle()
                    .stroke(trackTint, lineWidth: lineWidth)
                    .frame(width: diameter, height: diameter)

                // Filled arc
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .frame(width: diameter, height: diameter)
                    .rotationEffect(.degrees(-90))

                center()
                    .frame(width: diameter, height: diameter)
            }

            if let label {
                Text(label.uppercased())
                    .font(.offscriptTagLabel)
                    .tracking(1.4)
                    .foregroundStyle(Color.offscriptTextMuted)
            }
        }
    }
}

extension TRingMeter where Center == AnyView {
    /// Convenience initializer: render a plain text value at the ring's
    /// center.
    init(
        value: Double,
        minValue: Double = 0,
        maxValue: Double = 1,
        tint: Color = .offscriptAccent,
        trackTint: Color = .offscriptHairline,
        lineWidth: CGFloat = 1.5,
        diameter: CGFloat = 56,
        label: String? = nil,
        centerText: String,
        centerTextTint: Color = .offscriptTextPrimary
    ) {
        self.init(
            value: value, minValue: minValue, maxValue: maxValue,
            tint: tint, trackTint: trackTint, lineWidth: lineWidth,
            diameter: diameter, label: label
        ) {
            AnyView(
                Text(centerText)
                    .font(.system(size: 13, weight: .light, design: .default).monospacedDigit())
                    .foregroundStyle(centerTextTint)
            )
        }
    }
}

// MARK: TTransportCell
//
// Hairline-bordered transport key. Every player transport button is built
// from this — the play key just gets a yellow ring inside the same cell so
// the row stays perfectly level.

struct TTransportCell<Glyph: View>: View {
    let cap: String
    var emphasized: Bool = false
    var action: () -> Void
    @ViewBuilder let glyph: () -> Glyph

    init(cap: String, emphasized: Bool = false, action: @escaping () -> Void, @ViewBuilder glyph: @escaping () -> Glyph) {
        self.cap = cap
        self.emphasized = emphasized
        self.action = action
        self.glyph = glyph
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    if emphasized {
                        Circle()
                            .stroke(Color.offscriptAccent, lineWidth: 1)
                            .frame(width: 44, height: 44)
                    }
                    glyph()
                        .foregroundStyle(emphasized ? Color.offscriptAccent : Color.offscriptTextPrimary)
                        .frame(width: 38, height: 38)
                }
                .frame(height: 44)

                Text(cap.uppercased())
                    .font(.offscriptTagLabel)
                    .tracking(1.4)
                    .foregroundStyle(Color.offscriptTextMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cap)
    }
}

// MARK: TSpark
//
// Tiny single-pixel polyline trace, used as a decorative instrument signal
// on dashboards (the "live waveform" sat next to readouts on the player).
// Pure data: pass an array of 0–1 amplitudes.

struct TSpark: View {
    let samples: [Double]
    var tint: Color = .offscriptAccentSecondary
    var lineWidth: CGFloat = 1.0

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                guard samples.count >= 2 else { return }
                let stepX = proxy.size.width / CGFloat(samples.count - 1)
                let mid = proxy.size.height / 2
                let amp = proxy.size.height * 0.42
                for (idx, s) in samples.enumerated() {
                    let x = stepX * CGFloat(idx)
                    let clamped = min(max(s, -1), 1)
                    let y = mid - CGFloat(clamped) * amp
                    if idx == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: TSectionHeader
//
// Tuner section header — mono uppercase eyebrow + sans display title +
// hairline rule beneath. Replaces `OffScriptSectionHeader` for screens
// rebuilt under the Tuner system.

struct TSectionHeader: View {
    let eyebrow: String
    let title: String
    var rule: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.offscriptTagLabel)
                .tracking(1.6)
                .foregroundStyle(Color.offscriptAccent)

            Text(title)
                .font(.offscriptDisplay)
                .foregroundStyle(Color.offscriptTextPrimary)

            if rule {
                Rectangle()
                    .fill(Color.offscriptHairline)
                    .frame(height: 0.5)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: TPanel
//
// A thin-walled black panel with hairline + corner ticks (instrument-cluster
// look). Use as the wrapper for any group of readings or controls that
// belong together on the dashboard.

struct TPanel<Content: View>: View {
    let title: String?
    var padding: CGFloat = 16
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, padding: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.padding = padding
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title.uppercased())
                    .font(.offscriptTagLabel)
                    .tracking(1.6)
                    .foregroundStyle(Color.offscriptTextMuted)
            }
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.offscriptCard)
        .overlay(
            Rectangle()
                .stroke(Color.offscriptHairline, lineWidth: 0.5)
        )
    }
}

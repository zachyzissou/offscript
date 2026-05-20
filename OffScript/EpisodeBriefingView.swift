import SwiftUI

/// Pre-listen briefing card powered by Apple Intelligence (FoundationModels).
/// Generates 3 concrete bullet takeaways + a one-line hook on-device, so it
/// works offline and never sends episode metadata off the phone.
///
/// Hidden silently when:
///   - The device doesn't have Apple Intelligence (older hardware, region not supported)
///   - The episode has no usable description text to ground generation
///   - Generation fails for any reason
/// Cached per episode ID for the lifetime of the process — generation is a few
/// hundred ms even on-device, and the briefing for a given episode never changes
/// unless the source description does.
struct EpisodeBriefingView: View {
    let episode: Episode

    @State private var bullets: [String] = []
    @State private var hook: String = ""
    @State private var isLoading = true
    @State private var didFail = false

    private static let extractor = TopicExtractionService()
    /// Process-lifetime cache. Briefings are deterministic-ish per episode and
    /// cheap to keep around — there will be at most a few hundred entries even
    /// for a power user before app restart.
    private static var cache: [UUID: (bullets: [String], hook: String)] = [:]

    var body: some View {
        Group {
            if didFail {
                EmptyView()
            } else if isLoading {
                loadingView
            } else if !bullets.isEmpty {
                content
            } else {
                EmptyView()
            }
        }
        .task(id: episode.id) {
            await loadBriefing()
        }
    }

    // Tuner spec-sheet section — TunerLabel eyebrow + content + hairline
    // rule above. Matches summarySection / feedbackSection vocabulary so
    // the AI cards read as part of the same instrument cluster, not as
    // foreign rounded panels.
    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TunerLabel(text: "BRIEFING · APPLE INTELLIGENCE", color: .offscriptSignalYellow)
                Spacer()
                TunerLabel(text: "ON DEVICE", color: .offscriptFnInfo)
            }

            if !hook.isEmpty {
                Text(hook)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { idx, bullet in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(String(format: "%02d", idx + 1))
                            .tunerFont(size: 10, tracking: 1.0)
                            .foregroundStyle(Color.offscriptSignalYellow)
                            .frame(width: 22, alignment: .leading)
                        Text(bullet)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(Color.offscriptPaperWhite)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Apple Intelligence briefing: \(hook). " + bullets.joined(separator: ". "))
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TunerLabel(text: "BRIEFING · APPLE INTELLIGENCE", color: .offscriptSignalYellow)
                Spacer()
                TunerLabel(text: "GENERATING", color: .offscriptSoftPaper)
            }

            VStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.offscriptFillSubtle)
                        .frame(height: 11)
                }
            }
            .padding(.top, 6)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
        .shimmer()
    }

    private func loadBriefing() async {
        isLoading = true
        didFail = false

        if let cached = Self.cache[episode.id] {
            bullets = cached.bullets
            hook = cached.hook
            isLoading = false
            return
        }

        // Don't even try without enough source material to ground generation.
        // Without this, FoundationModels happily hallucinates from a 4-word title.
        let descriptionLength = episode.summary?.strippingHTML.count ?? 0
        guard descriptionLength >= 60 else {
            didFail = true
            isLoading = false
            return
        }

        if let result = await Self.extractor.briefing(for: episode) {
            // Sanity check generation — very short bullets are usually the model
            // bailing out. Drop the whole briefing rather than show one-word hits.
            let validBullets = result.bullets.filter { $0.count >= 12 }
            guard validBullets.count >= 2 else {
                didFail = true
                isLoading = false
                return
            }

            Self.cache[episode.id] = (validBullets, result.hook)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                bullets = validBullets
                hook = result.hook
                isLoading = false
            }
        } else {
            didFail = true
            isLoading = false
        }
    }
}

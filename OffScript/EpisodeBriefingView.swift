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

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.offscriptAccent)
                Text("Apple Intelligence Briefing".uppercased())
                    .font(.offscriptMicro.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.offscriptAccent)
                Spacer()
            }

            if !hook.isEmpty {
                Text(hook)
                    .font(.offscriptBody.weight(.semibold))
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.offscriptAccent)
                            .frame(width: 3, height: 14)
                            .padding(.top, 4)
                        Text(bullet)
                            .font(.offscriptBody)
                            .foregroundStyle(Color.offscriptTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text("Generated on-device. Doesn't leave your phone.")
                .font(.offscriptMicro)
                .foregroundStyle(Color.offscriptTextMuted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offscriptUtilitySurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Apple Intelligence briefing: \(hook). " + bullets.joined(separator: ". "))
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.offscriptAccent)
                Text("Apple Intelligence Briefing".uppercased())
                    .font(.offscriptMicro.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.offscriptAccent)
                Spacer()
                ProgressView().controlSize(.small).tint(Color.offscriptAccent)
            }

            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.offscriptFillSubtle)
                    .frame(height: 12)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offscriptUtilitySurface()
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

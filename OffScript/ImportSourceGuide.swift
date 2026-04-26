import SwiftUI

/// "Bring your shows" step content + per-app export guides shown in the
/// onboarding flow. Each guide is editorial copy — concise, plain-spoken,
/// honest about the limits (e.g. Apple Podcasts requires manual export;
/// Spotify exclusives can't be imported).
///
/// Tier 1: file picker + Share-Extension routing + per-app guides.
/// Tier 2 (Pocket Casts API) and Tier 3 (Spotify OAuth) plug into the same
/// review pipeline once they ship — see PR description.
enum ImportSource: String, CaseIterable, Identifiable {
    case applePodcasts
    case overcast
    case pocketCasts
    case castro
    case castbox
    case spotify
    case opmlFile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applePodcasts: return "Apple Podcasts"
        case .overcast: return "Overcast"
        case .pocketCasts: return "Pocket Casts"
        case .castro: return "Castro"
        case .castbox: return "Castbox"
        case .spotify: return "Spotify"
        case .opmlFile: return "OPML file"
        }
    }

    /// Short marketing line shown beneath the source name in the picker row.
    var tagline: String {
        switch self {
        case .applePodcasts: return "Two-tap export, then share to OffScript"
        case .overcast: return "Export Subscriptions URL, share to OffScript"
        case .pocketCasts: return "Sync from web → Export OPML"
        case .castro: return "Settings → Export → OPML"
        case .castbox: return "Settings → Backup → Export OPML"
        case .spotify: return "Spotify exclusives can't be imported as RSS"
        case .opmlFile: return "Already have an .opml? Drop it in"
        }
    }

    var systemImage: String {
        switch self {
        case .applePodcasts: return "applelogo"
        case .overcast: return "waveform"
        case .pocketCasts: return "circle.dashed.inset.filled"
        case .castro: return "antenna.radiowaves.left.and.right"
        case .castbox: return "square.stack.3d.up"
        case .spotify: return "circle.grid.cross"
        case .opmlFile: return "doc.text"
        }
    }

    /// Step-by-step instructions for getting an OPML out of this source.
    var steps: [String] {
        switch self {
        case .applePodcasts:
            return [
                "Open Apple Podcasts on your iPhone.",
                "Tap Library → tap the channel/circle icon at top right.",
                "Long-press \"Subscriptions\" → choose \"Share Subscriptions OPML\".",
                "In the share sheet, scroll across the apps row and tap OffScript."
            ]
        case .overcast:
            return [
                "On overcast.fm, sign in and open Settings → Account.",
                "Tap \"Export OPML\" — Safari downloads a Subscriptions.opml file.",
                "Open Files → Downloads → long-press the file → Share → OffScript."
            ]
        case .pocketCasts:
            return [
                "On play.pocketcasts.com, sign in.",
                "Profile → Import & Export → Export OPML.",
                "Save the file to your phone, then Share → OffScript."
            ]
        case .castro:
            return [
                "Open Castro → Settings → Sharing & Sync → OPML Export.",
                "Castro emails you the OPML — open the email on your phone, tap the attachment, Share → OffScript."
            ]
        case .castbox:
            return [
                "Open Castbox → Profile → Settings → Backup & Restore.",
                "Tap \"Export Subscriptions\" → Save to Files.",
                "Open Files, locate the OPML, Share → OffScript."
            ]
        case .spotify:
            return [
                "Spotify doesn't expose subscription exports in any official way.",
                "Workaround: third-party tools like \"OPML for Spotify\" can convert your show list — paste your Spotify profile URL there, download the OPML, then Share → OffScript.",
                "Heads up: Spotify-exclusive shows have no public RSS feed and cannot be imported."
            ]
        case .opmlFile:
            return [
                "Tap \"Choose file\" below.",
                "Pick the .opml from Files, iCloud Drive, or any cloud-storage app you've connected.",
                "We'll show you a review screen and skip anything you already follow."
            ]
        }
    }

    /// True if this source supports the in-app file picker as the primary
    /// action (rather than \"open another app and share back\").
    var usesFilePicker: Bool { self == .opmlFile }
}

/// Half-sheet shown when the user taps a source on the onboarding picker.
/// Pure content — the "Choose file" affordance is wired by the parent so the
/// same guide can drive both onboarding and a future Settings entry-point.
struct ImportSourceGuideSheet: View {
    let source: ImportSource
    let onPickFile: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(source.steps.enumerated()), id: \.offset) { index, line in
                            stepRow(index: index + 1, line: line)
                        }
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    if source.usesFilePicker, let onPickFile {
                        Button("Choose file") {
                            onPickFile()
                            dismiss()
                        }
                        .buttonStyle(PrimaryPillButtonStyle())
                        .padding(.horizontal, OffScriptTheme.pagePadding)
                    } else {
                        Text("Once the file shows up in OffScript, we'll dedupe against anything you already follow and let you toggle each show on or off before importing.")
                            .font(.offscriptMeta)
                            .foregroundStyle(Color.offscriptTextMuted)
                            .padding(.horizontal, OffScriptTheme.pagePadding)
                    }

                    Spacer(minLength: 16)
                }
                .padding(.vertical, 20)
            }
            .background(Color.offscriptBackground.ignoresSafeArea())
            .navigationTitle(source.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(Color.offscriptAccent)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(source.title.uppercased())
                .font(.offscriptMicro.weight(.semibold))
                .foregroundStyle(Color.offscriptAccent)
            Text("Move your shows in")
                .font(.offscriptDisplay)
                .foregroundStyle(Color.offscriptTextPrimary)
            Text(source.tagline)
                .font(.offscriptBody)
                .foregroundStyle(Color.offscriptTextSecondary)
        }
        .padding(.horizontal, OffScriptTheme.pagePadding)
    }

    private func stepRow(index: Int, line: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(format: "%02d", index))
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(Color.offscriptAccent)
                .frame(width: 24, alignment: .leading)
                .padding(.top, 2)
            Text(line)
                .font(.offscriptBody)
                .foregroundStyle(Color.offscriptTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.offscriptCard, in: RoundedRectangle(cornerRadius: OffScriptTheme.Radius.small, style: .continuous))
    }
}

/// Onboarding step that asks the user how (or whether) to bring shows over.
struct BringYourShowsStep: View {
    let onContinue: () -> Void
    let onBack: () -> Void
    let onPickFile: () -> Void
    let onShowGuide: (ImportSource) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Step 2 · Bring your shows")
                        .font(.offscriptMicro.weight(.semibold))
                        .foregroundStyle(Color.offscriptAccent)
                    Text("Already have a library somewhere?")
                        .font(.offscriptDisplay)
                        .foregroundStyle(Color.offscriptTextPrimary)
                    Text("OffScript can pick up where your old podcast app left off. Pick the app you came from — we'll walk you through the export, dedupe what you already follow, and skip anything that doesn't have a public RSS feed.")
                        .font(.offscriptBody)
                        .foregroundStyle(Color.offscriptTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)

                VStack(spacing: 10) {
                    ForEach(ImportSource.allCases) { source in
                        sourceRow(source)
                    }
                }
                .padding(.horizontal, 24)

                HStack {
                    Button("Back", action: onBack)
                        .buttonStyle(GhostPillButtonStyle())
                    Spacer()
                    Button("Skip for now", action: onContinue)
                        .buttonStyle(PrimaryPillButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Text("You can always come back to this from Settings → Import.")
                    .font(.offscriptMicro)
                    .foregroundStyle(Color.offscriptTextMuted)
                    .padding(.horizontal, 24)
            }
            .padding(.vertical, 28)
            .frame(maxWidth: 640, alignment: .leading)
        }
    }

    private func sourceRow(_ source: ImportSource) -> some View {
        Button {
            if source.usesFilePicker {
                onPickFile()
            } else {
                onShowGuide(source)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: source.systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.offscriptAccent)
                    .frame(width: 36, height: 36)
                    .background(Color.offscriptAccentSoft, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(source.title)
                        .font(.headline)
                        .foregroundStyle(Color.offscriptTextPrimary)
                    Text(source.tagline)
                        .font(.offscriptMeta)
                        .foregroundStyle(Color.offscriptTextMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.offscriptTextMuted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.offscriptCard, in: RoundedRectangle(cornerRadius: OffScriptTheme.Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: OffScriptTheme.Radius.small, style: .continuous)
                    .stroke(Color.offscriptHairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Lightweight ghost pill style, used for the "Back" affordance on
/// onboarding steps where we want a less assertive look than the primary.
struct GhostPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.offscriptTextPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Capsule().stroke(Color.offscriptHairline, lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

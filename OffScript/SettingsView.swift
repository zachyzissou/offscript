import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var podcasts: [Podcast]
    @Query private var episodes: [Episode]
    @AppStorage("offscript.autoPlayNext") private var autoPlayNext = true
    @AppStorage("offscript.preferShortEpisodes") private var preferShortEpisodes = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                    OffScriptUtilityHeader(
                        eyebrow: "Settings",
                        title: "Tune how OffScript behaves",
                        subtitle: "These switches change what gets surfaced, what plays next, and how much momentum the app keeps while you listen."
                    )
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        statCard("Subscribed", value: "\(podcasts.filter(\.isSubscribed).count)")
                        statCard("Episodes", value: "\(episodes.count)")
                        statCard("Unplayed", value: "\(episodes.filter { !$0.isPlayed }.count)")
                        statCard("Queued", value: "\(episodes.filter(\.isQueued).count)")
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    VStack(alignment: .leading, spacing: 14) {
                        OffScriptSectionHeader(
                            title: "Playback",
                            subtitle: "Keep the queue moving or bias recommendations toward shorter openings in your day."
                        )

                        settingsToggleCard(
                            title: "Auto-play next queued episode",
                            detail: "When an episode finishes, keep listening by moving straight into the next queued item.",
                            isOn: $autoPlayNext
                        )

                        settingsToggleCard(
                            title: "Prefer short listens",
                            detail: "Push compact episodes and quick wins a little higher in your recommendations.",
                            isOn: $preferShortEpisodes
                        )
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    VStack(alignment: .leading, spacing: 14) {
                        OffScriptSectionHeader(
                            title: "About",
                            subtitle: "The current build is local-first, RSS-backed, and still evolving toward a fuller listening system."
                        )

                        Text("OffScript currently runs as a local-first prototype with RSS-backed subscriptions and on-device recommendation logic.")
                            .font(.offscriptBody)
                            .foregroundStyle(Color.offscriptTextSecondary)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .offscriptUtilitySurface()
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
            .offscriptPageBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func statCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.offscriptTextPrimary)
            Text(title.uppercased())
                .font(.offscriptMicro.weight(.semibold))
                .foregroundStyle(Color.offscriptTextMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .offscriptUtilitySurface()
    }

    private func settingsToggleCard(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.offscriptTextPrimary)
                Text(detail)
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color.offscriptAccent)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offscriptUtilitySurface()
    }
}

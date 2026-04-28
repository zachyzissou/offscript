import AuthenticationServices
import OSLog
import SwiftData
import SwiftUI

private let settingsLogger = Logger(subsystem: "com.offscript", category: "Settings")

// MARK: - SettingsView (Tuner config panel)

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var podcasts: [Podcast]
    @AppStorage("offscript.autoPlayNext") private var autoPlayNext = true
    @AppStorage("offscript.preferShortEpisodes") private var preferShortEpisodes = false
    @AppStorage("offscript.cloudSyncEnabled") private var cloudSyncEnabled = false
    @State private var signedInUserID: String?
    @State private var signedInDisplayName: String?
    @State private var showSignOutConfirmation = false
    @State private var signInMessage: String?

    @State private var episodeCount: Int = 0
    @State private var unplayedCount: Int = 0
    @State private var queuedCount: Int = 0
    @State private var signalTags: [String] = []
    @State private var signalShows: [String] = []
    @State private var explicitSignalCount = 0
    @State private var completedSignalCount = 0
    @State private var signalUpdatedAt: Date?
    @State private var signalMessage: String?

    private var isSignedIn: Bool { signedInUserID != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsHeader
                    statsBlock
                    playbackSection
                    signalProfileSection
                    iCloudSection
                    aboutSection
                }
                .padding(.horizontal, OffScriptTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(Color.offscriptStudioBlack.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.offscriptStudioBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                refreshCounts()
                refreshSignInState()
                refreshSignalProfile()
            }
            // No `.toolbar` ToolbarItem — iOS 26 wraps toolbar buttons in
            // glass-capsule chrome that ignores .plain styling. DONE key
            // moved inline into `settingsHeader` below.
            .alert("Sign Out", isPresented: $showSignOutConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) { signOut() }
            } message: {
                Text("Sync will stop on next launch. Your local data will remain on this device.")
            }
        }
    }

    // MARK: header + stats

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TunerLabel(text: "SETTINGS · CONFIG PANEL", color: .offscriptSignalYellow)
                    .lineLimit(1)
                Spacer()
                TunerLabel(text: isSignedIn ? "● ICLOUD" : "○ LOCAL",
                           color: isSignedIn ? .offscriptFnMode : .offscriptSoftPaper)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Settings")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Color.offscriptPaperWhite)
                Spacer()
                // DONE key inline — replaces the toolbar Done button which
                // iOS 26 wrapped in glass chrome. Same Tuner vocabulary as
                // every other action key in the app.
                Button {
                    dismiss()
                } label: {
                    TunerLabel(text: "DONE", color: .offscriptSignalYellow, size: 11)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close settings")
            }
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                .padding(.top, 4)
        }
    }

    private var statsBlock: some View {
        HStack(spacing: 0) {
            stat(label: "SUBSCRIBED", value: "\(podcasts.filter(\.isSubscribed).count)")
            divider
            stat(label: "EPISODES", value: "\(episodeCount)")
            divider
            stat(label: "UNPLAYED", value: "\(unplayedCount)")
            divider
            stat(label: "QUEUED", value: "\(queuedCount)")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
    }

    @ViewBuilder
    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.offscriptPaperWhite)
                .monospacedDigit()
            TunerLabel(text: label, color: .offscriptSoftPaper, size: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle().fill(Color.offscriptHairline).frame(width: 1, height: 36)
    }

    // MARK: playback

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TunerLabel(text: "PLAYBACK · BEHAVIOUR", color: .offscriptSignalYellow)

            VStack(spacing: 0) {
                tunerToggle(
                    title: "Auto-play next queued episode",
                    detail: "When an episode finishes, keep listening by moving straight into the next queued item.",
                    isOn: $autoPlayNext
                )
                Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                tunerToggle(
                    title: "Prefer short listens",
                    detail: "Push compact episodes and quick wins a little higher in your recommendations.",
                    isOn: $preferShortEpisodes
                )
                Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                defaultRateRow
                Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                resetRatesRow
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
    }

    /// Default playback rate — the rate new podcasts inherit before the
    /// user picks something specific in the player. Per-podcast overrides
    /// from the player win over this. Stored in
    /// `PodcastPlaybackPreferences.globalDefault`.
    private var defaultRateRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Default playback rate")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                Text("New podcasts inherit this rate. Per-podcast picks from the player override it.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.offscriptPaperWhite.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            Spacer(minLength: 12)
            Menu {
                ForEach([Float(1.0), 1.1, 1.25, 1.5, 1.75, 2.0, 2.5], id: \.self) { rate in
                    Button {
                        PodcastPlaybackPreferences.setGlobalDefault(rate)
                        defaultRateRefresh = UUID()  // force re-read of static
                    } label: {
                        HStack {
                            Text(String(format: "%.2g×", rate))
                            if abs(currentDefaultRate - rate) < 0.001 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                TunerLabel(
                    text: String(format: "%.2g×", currentDefaultRate),
                    color: .offscriptSignalYellow,
                    size: 11
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }

    /// Wipe every per-podcast playback-rate override so all shows
    /// fall back to the global default. Useful escape hatch when the
    /// user accidentally fast-tasted everything to 2× and wants out.
    private var resetRatesRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reset per-podcast rates")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                Text("Clears every show's custom playback speed back to the default.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.offscriptPaperWhite.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            Spacer(minLength: 12)
            Button {
                UserDefaults.standard.removeObject(forKey: "offscript.podcastRates")
            } label: {
                TunerLabel(
                    text: "× RESET",
                    color: .offscriptFnRecord,
                    size: 10
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }

    /// Force a re-render of the default-rate menu when the user picks a
    /// new value. UserDefaults isn't an ObservableObject so the View
    /// won't re-render automatically; bumping this UUID does it.
    @State private var defaultRateRefresh = UUID()
    private var currentDefaultRate: Float {
        // Reference defaultRateRefresh so SwiftUI tracks it as a dep.
        _ = defaultRateRefresh
        return PodcastPlaybackPreferences.globalDefault
    }

    @ViewBuilder
    private func tunerToggle(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.offscriptPaperWhite.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
        .tint(Color.offscriptSignalYellow)
        .padding(.vertical, 10)
    }

    // MARK: signal profile

    private var signalProfileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TunerLabel(text: "SIGNAL PROFILE · LOCAL TASTE", color: .offscriptSignalYellow)

            HStack(spacing: 0) {
                stat(label: "EXPLICIT", value: "\(explicitSignalCount)")
                divider
                stat(label: "COMPLETED", value: "\(completedSignalCount)")
                divider
                stat(label: "TAGS", value: "\(signalTags.count)")
            }
            .padding(.vertical, 8)

            signalListRow(title: "Saved tags", values: signalTags, empty: "No tag signal yet")
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
            signalListRow(title: "Shows you finish", values: signalShows, empty: "No completion signal yet")

            HStack(spacing: 8) {
                Button {
                    rebuildSignalProfile()
                } label: {
                    TunerLabel(text: "↻ REBUILD SIGNAL", color: .offscriptSignalYellow, size: 10)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                }
                .buttonStyle(.plain)

                if let signalUpdatedAt {
                    TunerLabel(
                        text: "UPDATED \(signalUpdatedAt.formatted(date: .abbreviated, time: .shortened).uppercased())",
                        color: .offscriptSoftPaper,
                        size: 8
                    )
                }
                Spacer()
            }
            .padding(.top, 4)

            if let signalMessage {
                Text(signalMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.offscriptSoftPaper)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
    }

    private func signalListRow(title: String, values: [String], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.offscriptPaperWhite)
            if values.isEmpty {
                Text(empty)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.offscriptPaperWhite.opacity(0.65))
            } else {
                Text(values.prefix(6).joined(separator: " · "))
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(Color.offscriptPaperWhite.opacity(0.82))
                    .textCase(.uppercase)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: iCloud

    private var iCloudSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TunerLabel(text: "ICLOUD SYNC · CROSS-DEVICE STATE", color: .offscriptSignalYellow)

            if isSignedIn {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        TunerLabel(text: "● SIGNED IN", color: .offscriptFnMode)
                        Text(displayNameLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.offscriptPaperWhite)
                    }
                    Text("iCloud syncs automatically when connected.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.offscriptPaperWhite.opacity(0.7))

                    Button {
                        showSignOutConfirmation = true
                    } label: {
                        TunerLabel(text: "× SIGN OUT", color: .offscriptFnRecord, size: 10)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sign in to enable iCloud sync across your devices.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.offscriptPaperWhite)

                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName]
                    } onCompletion: { result in
                        handleSignInResult(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 48)

                    if let signInMessage {
                        Text(signInMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.offscriptSoftPaper)
                            .transition(.opacity)
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
    }

    // MARK: about

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TunerLabel(text: "ABOUT · BUILD", color: .offscriptSignalYellow)
            Text("OffScript runs as a local-first prototype with RSS-backed subscriptions and on-device recommendation logic. The Apple Intelligence briefing, on-device transcription, translation, Siri intents, and Spotlight donations are all native Apple frameworks — no third-party services touch your listening data.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineSpacing(2)

            HStack {
                TunerLabel(text: "VERSION  \(buildVersionString.uppercased())", color: .offscriptSoftPaper)
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
    }

    private var buildVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    private var displayNameLabel: String {
        guard let signedInDisplayName, !signedInDisplayName.isEmpty else {
            return "Apple ID User"
        }
        return signedInDisplayName
    }

    // MARK: helpers

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                withAnimation { signInMessage = "Sign-in returned no Apple ID credential." }
                return
            }

            let displayName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")

            do {
                try AppSettings.saveCredential(
                    userID: credential.user,
                    displayName: displayName.isEmpty ? nil : displayName
                )
                cloudSyncEnabled = true
                refreshSignInState()
                withAnimation { signInMessage = "Signed in. Sync activates on next launch." }
                settingsLogger.info("Sign in with Apple succeeded for user \(credential.user, privacy: .private)")
            } catch {
                settingsLogger.error("Failed to persist Apple credential: \(error.localizedDescription, privacy: .public)")
                withAnimation { signInMessage = "Sign-in could not be saved. Please try again." }
            }
        case .failure(let error):
            settingsLogger.error("Sign in with Apple failed: \(error.localizedDescription, privacy: .public)")
            withAnimation { signInMessage = "Sign-in failed. Please try again." }
        }
    }

    private func signOut() {
        AppSettings.clearCredential()
        refreshSignInState()
        cloudSyncEnabled = false
        settingsLogger.info("User signed out; sync disabled")
    }

    private func refreshSignInState() {
        signedInUserID = AppSettings.currentUserID
        signedInDisplayName = AppSettings.displayName
    }

    private func refreshSignalProfile() {
        let profiles = (try? modelContext.fetch(FetchDescriptor<UserTasteProfile>())) ?? []
        let profile = profiles.first
        signalTags = profile?.topTags ?? []
        signalShows = profile?.showAffinity ?? []
        signalUpdatedAt = profile?.lastUpdatedAt
        explicitSignalCount = (try? modelContext.fetchCount(FetchDescriptor<PreferenceSignal>())) ?? 0
        let completedRawValue = PlaybackEvent.Kind.completed.rawValue
        completedSignalCount = (try? modelContext.fetchCount(FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate<PlaybackEvent> { $0.kindRawValue == completedRawValue }
        ))) ?? 0
    }

    private func rebuildSignalProfile() {
        do {
            try TasteProfileService.refresh(in: modelContext, force: true)
            refreshSignalProfile()
            withAnimation { signalMessage = "Signal rebuilt from local listening history." }
        } catch {
            settingsLogger.error("Signal rebuild failed: \(error.localizedDescription, privacy: .public)")
            withAnimation { signalMessage = "Signal rebuild failed. Please try again." }
        }
    }

    /// fetchCount-backed counts so Settings doesn't materialize the entire Episode table.
    private func refreshCounts() {
        episodeCount  = (try? modelContext.fetchCount(FetchDescriptor<Episode>())) ?? 0
        unplayedCount = (try? modelContext.fetchCount(
            FetchDescriptor<Episode>(predicate: #Predicate<Episode> { !$0.isPlayed })
        )) ?? 0
        queuedCount   = (try? modelContext.fetchCount(
            FetchDescriptor<Episode>(predicate: #Predicate<Episode> { $0.isQueued })
        )) ?? 0
    }
}

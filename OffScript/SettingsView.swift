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
    @AppStorage("offscript.appleUserID") private var appleUserID: String = ""
    @AppStorage("offscript.appleUserName") private var appleUserName: String = ""
    @State private var showSignOutConfirmation = false
    @State private var signInMessage: String?

    @State private var episodeCount: Int = 0
    @State private var unplayedCount: Int = 0
    @State private var queuedCount: Int = 0

    private var isSignedIn: Bool { !appleUserID.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsHeader
                    statsBlock
                    playbackSection
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
            .task { refreshCounts() }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        dismiss()
                    } label: {
                        TunerLabel(text: "DONE", color: .offscriptSignalYellow, size: 11)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
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
            HStack {
                TunerLabel(text: "SETTINGS · CONFIG PANEL", color: .offscriptSignalYellow)
                Spacer()
                TunerLabel(text: isSignedIn ? "● ICLOUD" : "○ LOCAL", color: isSignedIn ? .offscriptFnMode : .offscriptSoftPaper)
            }
            Text("Settings")
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Color.offscriptPaperWhite)
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
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
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

    // MARK: iCloud

    private var iCloudSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TunerLabel(text: "ICLOUD SYNC · CROSS-DEVICE STATE", color: .offscriptSignalYellow)

            if isSignedIn {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        TunerLabel(text: "● SIGNED IN", color: .offscriptFnMode)
                        Text(appleUserName.isEmpty ? "Apple ID User" : appleUserName)
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

    // MARK: helpers

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                appleUserID = credential.user
                if let fullName = credential.fullName {
                    let name = [fullName.givenName, fullName.familyName]
                        .compactMap { $0 }
                        .joined(separator: " ")
                    if !name.isEmpty {
                        appleUserName = name
                    }
                }
                cloudSyncEnabled = true
                withAnimation { signInMessage = "Signed in. Sync activates on next launch." }
                settingsLogger.info("Sign in with Apple succeeded for user \(credential.user, privacy: .private)")
            }
        case .failure(let error):
            settingsLogger.error("Sign in with Apple failed: \(error.localizedDescription, privacy: .public)")
            withAnimation { signInMessage = "Sign-in failed. Please try again." }
        }
    }

    private func signOut() {
        appleUserID = ""
        appleUserName = ""
        cloudSyncEnabled = false
        settingsLogger.info("User signed out; sync disabled")
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

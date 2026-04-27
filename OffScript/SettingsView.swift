import AuthenticationServices
import OSLog
import SwiftData
import SwiftUI

private let settingsLogger = Logger(subsystem: "com.offscript", category: "Settings")

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

    // Episode counts via fetchCount instead of @Query var episodes: [Episode] —
    // Settings only needs three integers, not the full episode list. Loading
    // every episode just to call .count was making this view unusable once
    // the library got past a couple hundred episodes.
    @State private var episodeCount: Int = 0
    @State private var unplayedCount: Int = 0
    @State private var queuedCount: Int = 0

    private var isSignedIn: Bool { !appleUserID.isEmpty }

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
                        statCard("Episodes", value: "\(episodeCount)")
                        statCard("Unplayed", value: "\(unplayedCount)")
                        statCard("Queued", value: "\(queuedCount)")
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

                    // MARK: - iCloud Sync Section
                    VStack(alignment: .leading, spacing: 14) {
                        OffScriptSectionHeader(
                            title: "iCloud Sync",
                            subtitle: "Keep your subscriptions and queue in sync across devices."
                        )

                        if isSignedIn {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.offscriptAccent)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Signed in as \(appleUserName.isEmpty ? "Apple ID User" : appleUserName)")
                                            .font(.offscriptCardTitle)
                                            .foregroundStyle(Color.offscriptTextPrimary)
                                        Text("iCloud syncs automatically when connected.")
                                            .font(.offscriptMeta)
                                            .foregroundStyle(Color.offscriptTextMuted)
                                    }
                                }

                                Button(role: .destructive) {
                                    showSignOutConfirmation = true
                                } label: {
                                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundStyle(Color.red.opacity(0.85))
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .offscriptUtilitySurface()
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Sign in to enable iCloud sync across your devices.")
                                    .font(.offscriptBody)
                                    .foregroundStyle(Color.offscriptTextSecondary)

                                SignInWithAppleButton(.signIn) { request in
                                    request.requestedScopes = [.fullName]
                                } onCompletion: { result in
                                    handleSignInResult(result)
                                }
                                .signInWithAppleButtonStyle(.white)
                                .frame(height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: OffScriptTheme.Radius.small, style: .continuous))

                                if let signInMessage {
                                    Text(signInMessage)
                                        .font(.offscriptMeta)
                                        .foregroundStyle(Color.offscriptTextMuted)
                                        .transition(.opacity)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .offscriptUtilitySurface()
                        }
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
                            .padding(16)
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
            .task {
                refreshCounts()
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Sign Out", isPresented: $showSignOutConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    signOut()
                }
            } message: {
                Text("Sync will stop on next launch. Your local data will remain on this device.")
            }
        }
    }

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
                withAnimation {
                    signInMessage = "Signed in. Sync will activate on next launch."
                }
                settingsLogger.info("Sign in with Apple succeeded for user \(credential.user, privacy: .private)")
            }
        case .failure(let error):
            settingsLogger.error("Sign in with Apple failed: \(error.localizedDescription, privacy: .public)")
            withAnimation {
                signInMessage = "Sign-in failed. Please try again."
            }
        }
    }

    private func signOut() {
        appleUserID = ""
        appleUserName = ""
        cloudSyncEnabled = false
        settingsLogger.info("User signed out; sync disabled")
    }

    /// Counts via fetchCount instead of @Query → never materializes the
    /// Episode array. SwiftData translates these into SQL COUNT queries.
    private func refreshCounts() {
        episodeCount  = (try? modelContext.fetchCount(FetchDescriptor<Episode>())) ?? 0
        unplayedCount = (try? modelContext.fetchCount(
            FetchDescriptor<Episode>(predicate: #Predicate<Episode> { !$0.isPlayed })
        )) ?? 0
        queuedCount   = (try? modelContext.fetchCount(
            FetchDescriptor<Episode>(predicate: #Predicate<Episode> { $0.isQueued })
        )) ?? 0
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
                    .font(.offscriptCardTitle)
                    .foregroundStyle(Color.offscriptTextPrimary)
                Text(detail)
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color.offscriptAccent)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offscriptUtilitySurface()
    }
}

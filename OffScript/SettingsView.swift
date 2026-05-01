import AuthenticationServices
import OSLog
import SwiftData
import SwiftUI

private let settingsLogger = Logger(subsystem: "com.offscript", category: "Settings")

// MARK: - SettingsView (Tuner config panel)

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("offscript.autoPlayNext") private var autoPlayNext = true
    @AppStorage("offscript.preferShortEpisodes") private var preferShortEpisodes = false
    @AppStorage("offscript.cloudSyncEnabled") private var cloudSyncEnabled = false
    @State private var recommendationMode = AppSettings.recommendationMode
    @State private var signedInUserID: String?
    @State private var signedInDisplayName: String?
    @State private var appleCredentialState: AppleCredentialValidationState = .signedOut
    @State private var cloudKitAvailability: CloudKitAccountAvailability = .couldNotDetermine
    @State private var showSignOutConfirmation = false
    @State private var signInMessage: String?
    /// Auto-clears `signInMessage` after a short window so a stale
    /// "Sign-in failed. Please try again." doesn't linger across the
    /// next session. The timer is cancelled and replaced whenever a
    /// new message is set.
    @State private var signInMessageClearTask: Task<Void, Never>?
    @State private var isDefaultRatePickerExpanded = false
    /// Reset-per-podcast-rates is destructive (wipes every show's
    /// custom speed) and otherwise irreversible — drop into a confirm
    /// strip first, mirroring the Queue × CLEAR ALL pattern from #200.
    @State private var isConfirmingResetRates = false

    @State private var subscribedPodcastCount: Int = 0
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
    private var isSyncActive: Bool {
        cloudSyncEnabled
            && appleCredentialState.isAuthorized
            && cloudKitAvailability.allowsSync
            && AppSettings.cloudSyncRuntimeState == .cloudBacked
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsHeader
                statsBlock
                playbackSection
                recommendationSection
                signalProfileSection
                iCloudSection
                aboutSection
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)
            .padding(.top, OffScriptTheme.modalContentTopPadding)
            .padding(.bottom, 32)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
        .task {
            settingsLogger.info("Settings task started")
            refreshCounts()
            refreshSignInState()
            refreshSignalProfile()
            await refreshIdentityStatus()
            settingsLogger.info("Settings task completed: episodes=\(episodeCount, privacy: .public), queued=\(queuedCount, privacy: .public), signedIn=\(isSignedIn, privacy: .public), apple=\(appleCredentialState.displayText, privacy: .public), iCloud=\(cloudKitAvailability.displayText, privacy: .public)")
        }
        // Auto-clear the sign-in status copy so a stale "Sign-in
        // failed" line doesn't linger across the next Settings open.
        // Cancels any prior timer when the message changes so two
        // back-to-back attempts both get the full window.
        .onChange(of: signInMessage) { _, newValue in
            signInMessageClearTask?.cancel()
            guard newValue != nil else { return }
            signInMessageClearTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                if !Task.isCancelled {
                    withAnimation { signInMessage = nil }
                }
            }
        }
        .onDisappear { signInMessageClearTask?.cancel() }
    }

    // MARK: header + stats

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TunerLabel(text: "SETTINGS · CONFIG PANEL", color: .offscriptSignalYellow)
                    .lineLimit(1)
                Spacer()
                TunerLabel(text: isSyncActive ? "● SYNC" : (isSignedIn ? "● APPLE ID" : "○ LOCAL"),
                           color: isSyncActive ? .offscriptFnMode : (isSignedIn ? .offscriptFnInfo : .offscriptSoftPaper))
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Settings")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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
            stat(label: "SUBSCRIBED", value: "\(subscribedPodcastCount)")
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
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            TunerLabel(text: label, color: .offscriptSoftPaper, size: 8)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Combine the value+label pair into one accessibility element
        // so VoiceOver reads "12 SUBSCRIBED" once instead of "12,
        // SUBSCRIBED" as two separate stops.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label.lowercased())")
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
        VStack(alignment: .leading, spacing: 0) {
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
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isDefaultRatePickerExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        TunerLabel(
                            text: String(format: "%.2g×", currentDefaultRate),
                            color: .offscriptSignalYellow,
                            size: 11
                        )
                        Image(systemName: isDefaultRatePickerExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.offscriptSignalYellow)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Default playback rate")
                .accessibilityValue(String(format: "%.2g×", currentDefaultRate))
                .accessibilityHint(isDefaultRatePickerExpanded ? "Double-tap to collapse rate options." : "Double-tap to expand rate options.")
            }
            .padding(.top, 10)
            .padding(.bottom, isDefaultRatePickerExpanded ? 8 : 10)

            if isDefaultRatePickerExpanded {
                TunerRatePicker(
                    rates: PodcastPlaybackPreferences.supportedRates,
                    selectedRate: currentDefaultRate,
                    accessibilityActionPrefix: "Set default playback rate to"
                ) { rate in
                    PodcastPlaybackPreferences.setGlobalDefault(rate)
                    defaultRateRefresh = UUID()  // force re-read of static
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isDefaultRatePickerExpanded = false
                    }
                }
                .padding(.bottom, 10)
            }
        }
    }

    /// Wipe every per-podcast playback-rate override so all shows
    /// fall back to the global default. Useful escape hatch when the
    /// user accidentally fast-tasted everything to 2× and wants out.
    private var resetRatesRow: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    withAnimation(.easeOut(duration: 0.18)) {
                        isConfirmingResetRates = true
                    }
                } label: {
                    TunerLabel(
                        text: "× RESET",
                        color: .offscriptFnRecord,
                        size: 10
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isConfirmingResetRates)
                .accessibilityLabel("Reset per-podcast playback rates")
                .accessibilityHint("Asks for confirmation before clearing every show's custom rate")
                .accessibilityIdentifier("SettingsResetRates")
            }
            .padding(.vertical, 10)

            if isConfirmingResetRates {
                resetRatesConfirmStrip
                    .padding(.bottom, 10)
            }
        }
    }

    /// Tuner-styled inline confirm — matches the Queue × CLEAR ALL
    /// confirm pattern from #200 so destructive bulk-resets all use
    /// the same vocabulary across the app.
    private var resetRatesConfirmStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            TunerLabel(text: "● CONFIRM RESET", color: .offscriptFnRecord)
            Text("Clear every show's custom playback rate? This can't be undone.")
                .font(.system(size: 13))
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineSpacing(2)

            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isConfirmingResetRates = false
                    }
                } label: {
                    TunerLabel(text: "CANCEL", color: .offscriptPaperWhite, size: 11)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel reset per-podcast playback rates")
                .accessibilityIdentifier("SettingsResetRatesCancel")

                Button {
                    UserDefaults.standard.removeObject(forKey: "offscript.podcastRates")
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isConfirmingResetRates = false
                    }
                } label: {
                    TunerLabel(text: "× CONFIRM", color: .offscriptFnRecord, size: 11)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Confirm reset per-podcast playback rates")
                .accessibilityIdentifier("SettingsResetRatesConfirm")
            }
        }
        .padding(12)
        .overlay(Rectangle().stroke(Color.offscriptFnRecord.opacity(0.6), lineWidth: 1))
        .transition(.opacity.combined(with: .move(edge: .top)))
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
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
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

                Spacer(minLength: 10)

                TunerLabel(
                    text: isOn.wrappedValue ? "ON" : "OFF",
                    color: isOn.wrappedValue ? .offscriptStudioBlack : .offscriptSoftPaper,
                    size: 10
                )
                .frame(width: 58, height: 30)
                .background(isOn.wrappedValue ? Color.offscriptSignalYellow : Color.clear)
                .overlay(Rectangle().stroke(isOn.wrappedValue ? Color.offscriptSignalYellow : Color.offscriptHairline, lineWidth: 1))
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
        .accessibilityAddTraits(isOn.wrappedValue ? [.isButton, .isSelected] : .isButton)
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
                        .frame(minHeight: 44)
                        .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rebuild signal profile from current listening history")

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

    // MARK: recommendations

    // RecommendationMode chips meet 44pt min-height and announce
    // .isSelected to VoiceOver so the active mode is communicated
    // explicitly (background color alone isn't enough for a11y).
    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TunerLabel(text: "RECOMMENDATIONS · TUNER", color: .offscriptSignalYellow)

            HStack(spacing: 8) {
                ForEach(AppSettings.RecommendationMode.allCases, id: \.rawValue) { mode in
                    let isSelected = recommendationMode == mode
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            recommendationMode = mode
                            AppSettings.recommendationMode = mode
                        }
                    } label: {
                        TunerLabel(
                            text: mode.label,
                            color: isSelected ? .offscriptStudioBlack : .offscriptSignalYellow,
                            size: 9
                        )
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.vertical, 10)
                        .background(isSelected ? Color.offscriptSignalYellow : Color.clear)
                        .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(mode.label) recommendation mode")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            Text(recommendationMode.detail)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.offscriptPaperWhite.opacity(0.75))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
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
                    Text(iCloudStatusCopy)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.offscriptPaperWhite.opacity(0.7))

                    identityStatusRows

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showSignOutConfirmation.toggle()
                        }
                    } label: {
                        TunerLabel(text: "× SIGN OUT", color: .offscriptFnRecord, size: 10)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(minHeight: 44)
                            .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .accessibilityLabel(showSignOutConfirmation ? "Hide sign out confirmation" : "Sign out of OffScript")
                    .accessibilityHint(showSignOutConfirmation ? "" : "Stops iCloud sync on next launch. Local data remains on this device.")

                    if showSignOutConfirmation {
                        signOutConfirmationPanel
                    }
                }
            } else {
                signInPanel
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
    }

    private var signInPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TunerLabel(text: "○ APPLE ID", color: .offscriptSoftPaper)
                Spacer()
                TunerLabel(text: cloudKitAvailability.allowsSync ? "ICLOUD READY" : "LOCAL MODE", color: cloudKitAvailability.allowsSync ? .offscriptFnMode : .offscriptSoftPaper, size: 8)
            }

            Text("Sign in with Apple identifies this install. iCloud availability is checked separately before sync is enabled.")
                .font(.system(size: 13))
                .foregroundStyle(Color.offscriptPaperWhite.opacity(0.82))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                identityReadout(label: "CREDENTIAL", value: appleCredentialState.shortLabel, isReady: appleCredentialState.isAuthorized)
                Rectangle().fill(Color.offscriptHairline).frame(width: 1, height: 34)
                identityReadout(label: "CLOUD", value: cloudKitAvailability.shortLabel, isReady: cloudKitAvailability.allowsSync)
            }

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                handleSignInResult(result)
            }
            .signInWithAppleButtonStyle(.whiteOutline)
            .frame(height: 48)
            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

            if let signInMessage {
                Text(signInMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.offscriptSoftPaper)
                    .transition(.opacity)
            }
        }
        .padding(12)
        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
    }

    private func identityReadout(label: String, value: String, isReady: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            TunerLabel(text: label, color: .offscriptSoftPaper, size: 8)
            TunerLabel(text: value, color: isReady ? .offscriptFnMode : .offscriptSignalYellow, size: 9)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identityStatusRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            TunerLabel(
                text: appleCredentialState.displayText,
                color: appleCredentialState.isAuthorized ? .offscriptFnMode : .offscriptSoftPaper,
                size: 8
            )
            TunerLabel(
                text: cloudKitAvailability.displayText,
                color: cloudKitAvailability.allowsSync ? .offscriptFnMode : .offscriptSoftPaper,
                size: 8
            )
        }
        .padding(.top, 2)
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
                refreshSignInState()
                Task { await refreshIdentityStatus(enableSyncWhenAvailable: true) }
                withAnimation { signInMessage = "Signed in. Checking iCloud availability." }
                settingsLogger.info("Sign in with Apple succeeded for user \(credential.user, privacy: .private)")
            } catch {
                if let keychainError = error as? UserProfileService.KeychainError {
                    settingsLogger.error("Failed to persist Apple credential: \(keychainError.localizedDescription, privacy: .public), osStatus=\(keychainError.osStatus, privacy: .public)")
                } else {
                    settingsLogger.error("Failed to persist Apple credential: \(error.localizedDescription, privacy: .public)")
                }
                withAnimation { signInMessage = "Sign-in could not be saved. Please try again." }
            }
        case .failure(let error):
            settingsLogger.error("Sign in with Apple failed: \(error.localizedDescription, privacy: .public)")
            withAnimation { signInMessage = "Sign-in failed. Please try again." }
        }
    }

    private var signOutConfirmationPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            TunerLabel(text: "CONFIRM · SIGN OUT", color: .offscriptFnRecord)
            Text("Sync will stop on next launch. Your local data will remain on this device.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.offscriptPaperWhite.opacity(0.75))
                .lineSpacing(2)

            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showSignOutConfirmation = false
                    }
                } label: {
                    // Same Tuner confirm vocabulary as Queue × CLEAR
                    // ALL (#200), Settings × RESET (#229), and the
                    // PodcastDetail × UNSUBSCRIBE (#230): equal-width
                    // CANCEL / × CONFIRM at 44pt min-height with
                    // paperWhite Cancel.
                    TunerLabel(text: "CANCEL", color: .offscriptPaperWhite, size: 11)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel sign out")

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showSignOutConfirmation = false
                    }
                    signOut()
                } label: {
                    TunerLabel(text: "× SIGN OUT", color: .offscriptFnRecord, size: 11)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(Rectangle().stroke(Color.offscriptFnRecord, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Confirm sign out")
            }
        }
        .padding(12)
        .overlay(Rectangle().stroke(Color.offscriptFnRecord.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func signOut() {
        AppSettings.clearCredential()
        refreshSignInState()
        cloudSyncEnabled = false
        appleCredentialState = .signedOut
        settingsLogger.info("User signed out; sync disabled")
    }

    @MainActor
    private func refreshIdentityStatus(enableSyncWhenAvailable: Bool = false) async {
        settingsLogger.info("Settings identity refresh started: enableSyncWhenAvailable=\(enableSyncWhenAvailable, privacy: .public)")
        appleCredentialState = await AppleIdentityService.validateStoredCredential()
        cloudKitAvailability = await CloudKitAccountService.currentStatus()
        refreshSignInState()

        if enableSyncWhenAvailable {
            cloudSyncEnabled = appleCredentialState.isAuthorized && cloudKitAvailability.allowsSync
            signInMessage = cloudSyncEnabled
                ? "Signed in. Sync activates on next launch."
                : "Signed in. iCloud is not available on this device right now."
        }
        settingsLogger.info("Settings identity refresh completed: signedIn=\(isSignedIn, privacy: .public), apple=\(appleCredentialState.displayText, privacy: .public), iCloud=\(cloudKitAvailability.displayText, privacy: .public), cloudSyncEnabled=\(cloudSyncEnabled, privacy: .public), runtime=\(String(describing: AppSettings.cloudSyncRuntimeState), privacy: .public)")
    }

    private func refreshSignInState() {
        signedInUserID = AppSettings.currentUserID
        signedInDisplayName = AppSettings.displayName
    }

    private var iCloudStatusCopy: String {
        guard appleCredentialState.isAuthorized else {
            return "Apple sign-in needs repair before sync can resume."
        }
        guard cloudKitAvailability.allowsSync else {
            if cloudKitAvailability == .notConfigured {
                return "This build is missing iCloud entitlements. Sync stays local until the signed CloudKit profile lands."
            }
            return "Apple identity is saved; iCloud sync waits for an available iCloud account."
        }
        guard cloudSyncEnabled else {
            return "iCloud is available. Sign in again from this panel to arm sync."
        }
        switch AppSettings.cloudSyncRuntimeState {
        case .cloudBacked:
            return "iCloud sync is active for this launch."
        case .fallbackFailed:
            return "iCloud is available, but this launch fell back to local storage. Restart after the next signed build."
        case .localOnly:
            return "iCloud is ready. Sync activates on the next app launch."
        }
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
        settingsLogger.info("Settings signal profile refreshed: tags=\(signalTags.count, privacy: .public), shows=\(signalShows.count, privacy: .public), explicitSignals=\(explicitSignalCount, privacy: .public), completedSignals=\(completedSignalCount, privacy: .public)")
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
        subscribedPodcastCount = SettingsCountService.subscribedPodcastCount(in: modelContext)
        episodeCount  = (try? modelContext.fetchCount(FetchDescriptor<Episode>())) ?? 0
        unplayedCount = (try? modelContext.fetchCount(
            FetchDescriptor<Episode>(predicate: #Predicate<Episode> { !$0.isPlayed })
        )) ?? 0
        queuedCount   = (try? modelContext.fetchCount(
            FetchDescriptor<Episode>(predicate: #Predicate<Episode> { $0.isQueued })
        )) ?? 0
        settingsLogger.info("Settings counts refreshed: subscribed=\(subscribedPodcastCount, privacy: .public), episodes=\(episodeCount, privacy: .public), unplayed=\(unplayedCount, privacy: .public), queued=\(queuedCount, privacy: .public)")
    }
}

@MainActor
enum SettingsCountService {
    static func subscribedPodcastCount(in context: ModelContext) -> Int {
        (try? context.fetchCount(
            FetchDescriptor<Podcast>(predicate: #Predicate<Podcast> { $0.isSubscribed })
        )) ?? 0
    }
}

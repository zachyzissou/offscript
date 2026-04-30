import AuthenticationServices
import OSLog
import SwiftUI

struct OnboardingFlowView: View {
    let onComplete: (() -> Void)?
    @State private var step = 0
    @State private var selectedGenres: Set<Genre> = []
    @State private var selectedPodcasts: [PodcastSearchResult] = []
    @State private var signInErrorMessage: String?

    init(onComplete: (() -> Void)? = nil) {
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            // Tuner: pure OLED black field. No atmospheric gradient.
            Color.offscriptStudioBlack.ignoresSafeArea()

            switch step {
            case 0:
                welcomeScreen
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case 1:
                GenrePickerView(
                    selectedGenres: $selectedGenres,
                    onContinue: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 2 } },
                    onBack: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 0 } }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            case 2:
                PodcastPickerView(
                    selectedGenres: selectedGenres,
                    onContinue: { podcasts in
                        selectedPodcasts = podcasts
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 3 }
                    },
                    onBack: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 1 } }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            case 3:
                ImportProgressView(
                    podcasts: selectedPodcasts,
                    selectedGenres: selectedGenres,
                    onComplete: {
                        // ContentView owns @AppStorage("offscript.hasSeenOnboarding")
                        // and flips it inside this callback.
                        onComplete?()
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            default:
                EmptyView()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
    }

    // ── Tuner welcome — POWER ON ─────────────────────────────────────
    // Signal-acquired status pulse, OFF/SCRIPT wordmark in heavy display,
    // numbered manifesto rules, signal-yellow "POWER ON" CTA.
    private var welcomeScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Spacer(minLength: 40)

                // Signal acquired
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.offscriptSignalYellow)
                        .frame(width: 8, height: 8)
                    TunerLabel(text: "SIGNAL ACQUIRED", color: .offscriptSignalYellow, size: 10)
                }
                .staggeredEntrance(index: 0, delay: 0.10)

                // OFF / SCRIPT wordmark
                VStack(alignment: .leading, spacing: -12) {
                    Text("OFF")
                        .foregroundStyle(Color.offscriptPaperWhite)
                    HStack(spacing: 0) {
                        Text("SCRIPT")
                            .foregroundStyle(Color.offscriptPaperWhite)
                        Text(".")
                            .foregroundStyle(Color.offscriptSignalYellow)
                    }
                }
                .font(.system(size: 56, weight: .bold, design: .default))
                .tracking(-2)
                .staggeredEntrance(index: 1, delay: 0.10)

                TunerLabel(text: "A RECEIVER FOR WHAT YOU ACTUALLY LIKE", size: 10)
                    .staggeredEntrance(index: 2, delay: 0.10)

                Text("No algorithm pushing you somewhere. No paid placements. Just a tuner that listens to what you listen to and lines up the next thing — quietly, on this device.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .staggeredEntrance(index: 3, delay: 0.10)

                // Numbered manifesto
                VStack(spacing: 0) {
                    ForEach(Array(manifesto.enumerated()), id: \.offset) { i, line in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(String(format: "%02d", i + 1))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .tracking(0.6)
                                .foregroundStyle(Color.offscriptSignalYellow)
                                .monospacedDigit()
                            Text(line)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Color.offscriptPaperWhite)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .overlay(
                            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
                            alignment: .bottom
                        )
                        .staggeredEntrance(index: 4 + i, delay: 0.08)
                    }
                }

                Spacer(minLength: 24)

                // Sign in + Skip — sign-in button keeps Apple's appearance, skip
                // becomes the "POWER ON →" CTA in signal yellow.
                VStack(spacing: 14) {
                    SignInWithAppleButtonView(
                        onComplete: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                signInErrorMessage = nil
                                step = 1
                            }
                        },
                        onFailure: { message in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                signInErrorMessage = message
                            }
                        }
                    )
                    .frame(height: 48)
                    .staggeredEntrance(index: 8, delay: 0.10)

                    if let signInErrorMessage {
                        Text(signInErrorMessage)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(Color.offscriptFnRecord)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(Rectangle().stroke(Color.offscriptFnRecord.opacity(0.8), lineWidth: 1))
                            .transition(.opacity)
                    }

                    TunerLabel(text: "OR")

                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 1 }
                    } label: {
                        HStack {
                            Spacer()
                            Text("POWER ON →")
                                .font(.system(size: 14, weight: .bold, design: .default))
                                .tracking(2)
                                .foregroundStyle(Color.offscriptStudioBlack)
                            Spacer()
                        }
                        .padding(.vertical, 16)
                        .background(Color.offscriptSignalYellow)
                    }
                    .buttonStyle(.plain)
                    .staggeredEntrance(index: 9, delay: 0.10)
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 24)
        }
    }

    private var manifesto: [String] {
        [
            "On-device ML, never the cloud.",
            "A profile you can read and edit.",
            "Audio + video, equal billing.",
            "No paid placements, ever."
        ]
    }
}

// MARK: - Sign in with Apple

private struct SignInWithAppleButtonView: UIViewRepresentable {
    let onComplete: () -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        // Tuner: Apple's signin button has its own design language we can't
        // re-skin, so leave it stock — the chrome here is Apple's, not ours.
        // Sharp corners (radius 0) line up with the Tuner rectangle vocab.
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .white)
        button.cornerRadius = 0
        context.coordinator.presentationAnchorProvider = { [weak button] in
            button?.window
        }
        button.addTarget(context.coordinator,
                         action: #selector(Coordinator.handleSignIn),
                         for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}

    final class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        let onComplete: () -> Void
        let onFailure: (String) -> Void
        // Strong reference to the in-flight controller. Without this, the
        // controller is released as `handleSignIn()` returns and the delegate
        // callbacks (success / error) never fire — the symptom is "Sign in
        // with Apple does nothing." Apple's docs describe holding the
        // controller for the lifetime of the request.
        private var inFlightController: ASAuthorizationController?
        var presentationAnchorProvider: (() -> ASPresentationAnchor?)?

        init(onComplete: @escaping () -> Void, onFailure: @escaping (String) -> Void) {
            self.onComplete = onComplete
            self.onFailure = onFailure
        }

        @objc func handleSignIn() {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            inFlightController = controller
            controller.performRequests()
        }

        // MARK: ASAuthorizationControllerPresentationContextProviding
        // The system needs a window to present its sheet from. iOS 26 has
        // multiple connected scenes possible; we pick the first foreground
        // active one and fall back to the key window if none match. Without
        // this, the auth sheet refuses to present and the request errors out.
        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            if let anchor = presentationAnchorProvider?() {
                return anchor
            }
            let active = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first

            if let active {
                return active.windows.first(where: \.isKeyWindow)
                    ?? active.windows.first
                    ?? UIWindow(windowScene: active)
            }
            let logger = Logger(subsystem: "com.offscript", category: "AppleSignin")
            logger.error("Sign in with Apple requested without an active window scene; using detached fallback anchor")
            return ASPresentationAnchor(frame: .zero)
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                inFlightController = nil
                onFailure("SIGN-IN RETURNED NO APPLE ID CREDENTIAL")
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
                inFlightController = nil
                Task { @MainActor in
                    AppSettings.cloudSyncEnabled = (await CloudKitAccountService.currentStatus()).allowsSync
                    onComplete()
                }
            } catch {
                let logger = Logger(subsystem: "com.offscript", category: "AppleSignin")
                if let keychainError = error as? UserProfileService.KeychainError {
                    logger.error("Failed to persist Apple credential: \(keychainError.localizedDescription, privacy: .public), osStatus=\(keychainError.osStatus, privacy: .public)")
                } else {
                    logger.error("Failed to persist Apple credential: \(error.localizedDescription, privacy: .public)")
                }
                inFlightController = nil
                onFailure("SIGN-IN COULD NOT BE SAVED. TRY AGAIN.")
            }
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            // Surface the actual error — silent failure here is exactly what
            // had Sign in with Apple appearing broken to the user.
            let logger = Logger(subsystem: "com.offscript", category: "AppleSignin")
            logger.error("Sign in with Apple failed: \(error.localizedDescription, privacy: .public)")
            inFlightController = nil
            onFailure("SIGN-IN FAILED. RETRY OR POWER ON WITHOUT SYNC.")
        }
    }
}

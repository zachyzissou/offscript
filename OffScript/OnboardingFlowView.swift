import AuthenticationServices
import SwiftUI

struct OnboardingFlowView: View {
    let onComplete: (() -> Void)?
    @State private var step = 0
    @State private var selectedGenres: Set<Genre> = []
    @State private var selectedPodcasts: [PodcastSearchResult] = []

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
                (Text("OFF\n").foregroundStyle(Color.offscriptPaperWhite)
                 + Text("SCRIPT").foregroundStyle(Color.offscriptPaperWhite)
                 + Text(".").foregroundStyle(Color.offscriptSignalYellow))
                    .font(.system(size: 56, weight: .bold, design: .default))
                    .tracking(-2)
                    .lineSpacing(-12)
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
                    SignInWithAppleButtonView(onComplete: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 1 }
                    })
                    .frame(height: 48)
                    .staggeredEntrance(index: 8, delay: 0.10)

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

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .white)
        button.cornerRadius = 18
        button.addTarget(context.coordinator, action: #selector(Coordinator.handleSignIn), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}

    final class Coordinator: NSObject, ASAuthorizationControllerDelegate {
        let onComplete: () -> Void

        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }

        @objc func handleSignIn() {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.performRequests()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                // origin/main switched to @AppStorage for credential persistence —
                // write the user id and display name directly into UserDefaults.
                let displayName = [credential.fullName?.givenName, credential.fullName?.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                let defaults = UserDefaults.standard
                defaults.set(credential.user, forKey: "offscript.appleUserID")
                if !displayName.isEmpty {
                    defaults.set(displayName, forKey: "offscript.appleUserName")
                }
            }
            onComplete()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            onComplete()
        }
    }
}

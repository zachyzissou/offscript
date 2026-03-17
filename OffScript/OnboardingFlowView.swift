import AuthenticationServices
import SwiftUI

struct OnboardingFlowView: View {
    @AppStorage("offscript.hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var step = 0
    @State private var selectedGenres: Set<Genre> = []
    @State private var selectedPodcasts: [PodcastSearchResult] = []

    var body: some View {
        ZStack {
            // Atmospheric background (shared across all steps)
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.06, blue: 0.04),
                    Color.offscriptBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.offscriptAccent.opacity(0.08), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 400
            )
            .ignoresSafeArea()

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
                    onComplete: { hasSeenOnboarding = true }
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

    private var welcomeScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Spacer(minLength: 60)

                VStack(alignment: .leading, spacing: 18) {
                    Text("OffScript")
                        .font(.system(size: 46, weight: .bold, design: .serif))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.offscriptTextPrimary, Color.offscriptAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .staggeredEntrance(index: 0, delay: 0.12)

                    Text("Podcasts that feel curated,\nnot algorithmic.")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .staggeredEntrance(index: 1, delay: 0.12)

                    Text("OffScript learns from a few good picks to build a feed that feels edited — not endless.")
                        .font(.offscriptBody)
                        .foregroundStyle(Color.offscriptTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .staggeredEntrance(index: 2, delay: 0.12)
                }

                VStack(spacing: 12) {
                    SignInWithAppleButtonView(onComplete: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 1 }
                    })
                    .frame(height: 52)
                    .staggeredEntrance(index: 3, delay: 0.12)

                    Button("Skip for now") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 1 }
                    }
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextMuted)
                    .staggeredEntrance(index: 4, delay: 0.12)
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 24)
        }
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
                let displayName = [credential.fullName?.givenName, credential.fullName?.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                try? UserProfileService.saveCredential(
                    userID: credential.user,
                    displayName: displayName.isEmpty ? nil : displayName
                )
            }
            onComplete()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            onComplete()
        }
    }
}

// MARK: - Placeholder stubs (will be replaced by dedicated files in Tasks 5-6)

struct PodcastPickerView: View {
    let selectedGenres: Set<Genre>
    let onContinue: ([PodcastSearchResult]) -> Void
    let onBack: () -> Void
    var body: some View { Text("Podcast Picker — placeholder") }
}

struct ImportProgressView: View {
    let podcasts: [PodcastSearchResult]
    let selectedGenres: Set<Genre>
    let onComplete: () -> Void
    var body: some View { Text("Import Progress — placeholder") }
}

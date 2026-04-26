import AuthenticationServices
import SwiftUI
import UniformTypeIdentifiers

struct OnboardingFlowView: View {
    let onComplete: (() -> Void)?
    @State private var step = 0
    @State private var selectedGenres: Set<Genre> = []
    @State private var selectedPodcasts: [PodcastSearchResult] = []
    @State private var signInError: String?
    // Bring-your-shows step state.
    @State private var importerPresented = false
    @State private var importGuideSource: ImportSource?
    @State private var pendingImportURL: URL?

    init(onComplete: (() -> Void)? = nil) {
        self.onComplete = onComplete
    }

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
                BringYourShowsStep(
                    onContinue: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 2 } },
                    onBack: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 0 } },
                    onPickFile: { importerPresented = true },
                    onShowGuide: { source in importGuideSource = source }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            case 2:
                GenrePickerView(
                    selectedGenres: $selectedGenres,
                    onContinue: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 3 } },
                    onBack: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 1 } }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            case 3:
                PodcastPickerView(
                    selectedGenres: selectedGenres,
                    onContinue: { podcasts in
                        selectedPodcasts = podcasts
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 4 }
                    },
                    onBack: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 2 } }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            case 4:
                ImportProgressView(
                    podcasts: selectedPodcasts,
                    selectedGenres: selectedGenres,
                    onComplete: {
                        AppSettings.hasSeenOnboarding = true
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
        .fileImporter(
            isPresented: $importerPresented,
            allowedContentTypes: bringYourShowsContentTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                pendingImportURL = url
            }
        }
        .sheet(item: $importGuideSource) { source in
            ImportSourceGuideSheet(source: source, onPickFile: nil)
        }
        .sheet(item: Binding<PendingURL?>(
            get: { pendingImportURL.map(PendingURL.init) },
            set: { pendingImportURL = $0?.url }
        )) { wrapped in
            // After the user finishes (or cancels) the import sheet, advance
            // them to the genre picker so the flow doesn't strand them on
            // the bring-your-shows step.
            OPMLImportView(initialURL: wrapped.url)
                .onDisappear {
                    pendingImportURL = nil
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        if step == 1 { step = 2 }
                    }
                }
        }
    }

    private var bringYourShowsContentTypes: [UTType] {
        var types: [UTType] = [.xml, .data]
        if let opml = UTType("org.opml.opml") { types.insert(opml, at: 0) }
        if let byExt = UTType(filenameExtension: "opml") { types.insert(byExt, at: 0) }
        return types
    }

    private var welcomeScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Spacer(minLength: 60)

                VStack(alignment: .leading, spacing: 18) {
                    AnimatedOnboardingTitle()
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
                    SignInWithAppleButtonView(onSuccess: {
                        AppSettings.cloudSyncEnabled = true
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 1 }
                    }, onError: { message in
                        signInError = message
                    }, onCancel: {
                        // User dismissed the system sheet — no action.
                    })
                    .frame(height: 52)
                    .staggeredEntrance(index: 3, delay: 0.12)

                    if let signInError {
                        Text(signInError)
                            .font(.offscriptMeta)
                            .foregroundStyle(Color.offscriptDestructive)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    } else {
                        Text("Sign in to sync your library across devices")
                            .font(.offscriptMeta)
                            .foregroundStyle(Color.offscriptTextMuted)
                            .staggeredEntrance(index: 4, delay: 0.12)
                    }

                    Button("Skip for now") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 1 }
                    }
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextMuted)
                    .staggeredEntrance(index: 5, delay: 0.12)
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 24)
        }
    }
}

private struct PendingURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Animated Title

private struct AnimatedOnboardingTitle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Phase: CaseIterable { case enter, settle, breathe }

    var body: some View {
        Text("OffScript")
            .font(.system(size: 46, weight: .bold, design: .serif))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.offscriptTextPrimary, Color.offscriptAccent],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .modifier(TitlePhase(reduceMotion: reduceMotion))
    }

    private struct TitlePhase: ViewModifier {
        let reduceMotion: Bool

        func body(content: Content) -> some View {
            if reduceMotion {
                content
            } else {
                content
                    .phaseAnimator(Phase.allCases) { view, phase in
                        view
                            .opacity(phase == .enter ? 0 : 1)
                            .scaleEffect(phase == .enter ? 0.92 : (phase == .breathe ? 1.015 : 1.0), anchor: .leading)
                            .blur(radius: phase == .enter ? 6 : 0)
                    } animation: { phase in
                        switch phase {
                        case .enter:
                            return .easeOut(duration: 0.6)
                        case .settle:
                            return .spring(response: 0.6, dampingFraction: 0.78)
                        case .breathe:
                            return .easeInOut(duration: 4.0)
                        }
                    }
            }
        }
    }
}

// MARK: - Sign in with Apple

private struct SignInWithAppleButtonView: UIViewRepresentable {
    let onSuccess: () -> Void
    let onError: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSuccess: onSuccess, onError: onError, onCancel: onCancel)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .white)
        button.cornerRadius = 18
        button.addTarget(context.coordinator, action: #selector(Coordinator.handleSignIn), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}

    final class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        let onSuccess: () -> Void
        let onError: (String) -> Void
        let onCancel: () -> Void

        init(onSuccess: @escaping () -> Void, onError: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.onSuccess = onSuccess
            self.onError = onError
            self.onCancel = onCancel
        }

        @objc func handleSignIn() {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                onError("Sign in returned an unsupported credential.")
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
                onSuccess()
            } catch {
                onError("Couldn't save credential: \(error.localizedDescription)")
            }
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            // ASAuthorizationError.canceled (1001) is benign — the user closed the sheet.
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                onCancel()
            } else {
                onError(error.localizedDescription)
            }
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}

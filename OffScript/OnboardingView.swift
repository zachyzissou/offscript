import SwiftUI

struct OnboardingView: View {
    let onFinish: (_ jumpToSearch: Bool) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                // Richer atmospheric background
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.06, blue: 0.04),
                        Color.offscriptBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Subtle accent glow in the upper region
                RadialGradient(
                    colors: [Color.offscriptAccent.opacity(0.08), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 400
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        // App identity
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

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Build your Smart Feed in three good picks.")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.white)

                                Text("Add a few shows or topics you trust. OffScript uses those early signals to build a feed that feels edited instead of endless.")
                                    .font(.offscriptBody)
                                    .foregroundStyle(Color.offscriptTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .staggeredEntrance(index: 1, delay: 0.12)
                        }

                        HStack(spacing: 10) {
                            OnboardingStepIndicator(step: 1, text: "Add 3 shows")
                            OnboardingStepIndicator(step: 2, text: "Seed topics")
                            OnboardingStepIndicator(step: 3, text: "Get your feed")
                        }
                        .staggeredEntrance(index: 2, delay: 0.12)

                        VStack(spacing: 16) {
                            OnboardingCard(
                                icon: "hand.point.up.left.fill",
                                title: "Start with what you already trust",
                                detail: "Search for a few favorite shows, hosts, or topics. Three strong signals are enough to build your first feed."
                            )
                            .staggeredEntrance(index: 3, delay: 0.12)

                            OnboardingCard(
                                icon: "text.bubble.fill",
                                title: "OffScript explains its picks",
                                detail: "You’ll see why an episode showed up, whether it fits your day, and what it’s connected to."
                            )
                            .staggeredEntrance(index: 4, delay: 0.12)

                            OnboardingCard(
                                icon: "lock.shield.fill",
                                title: "Private by default",
                                detail: "Your listening profile stays local-first and on-device in this first version."
                            )
                            .staggeredEntrance(index: 5, delay: 0.12)
                        }

                        VStack(spacing: 12) {
                            Button("Add 3 shows to build my feed") {
                                onFinish(true)
                            }
                            .buttonStyle(OnboardingActionButtonStyle(prominent: true))

                            Button("Explore the sample library first") {
                                onFinish(false)
                            }
                            .buttonStyle(OnboardingActionButtonStyle(prominent: false))
                        }
                        .staggeredEntrance(index: 6, delay: 0.12)
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 48)
                    .padding(.bottom, 32)
                }
            }
        }
    }
}

private struct OnboardingStepIndicator: View {
    let step: Int
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(step)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.offscriptAccent)
                .frame(width: 22, height: 22)
                .background(Color.offscriptAccentSoft)
                .clipShape(Circle())

            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct OnboardingActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(prominent ? Color.black : Color.offscriptTextPrimary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(background(configuration: configuration))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(prominent ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
            )
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.97 : 1.0))
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private func background(configuration: Configuration) -> Color {
        if prominent {
            return Color.offscriptAccent.opacity(configuration.isPressed ? 0.82 : 1)
        }

        return Color.white.opacity(configuration.isPressed ? 0.12 : 0.08)
    }
}

private struct OnboardingCard: View {
    var icon: String? = nil
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let icon {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.offscriptAccent)
                    .frame(width: 32, height: 32)
                    .background(Color.offscriptAccentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.offscriptTextSecondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.offscriptHairline, lineWidth: 1)
        )
    }
}

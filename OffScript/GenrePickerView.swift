import SwiftUI

struct GenrePickerView: View {
    @Binding var selectedGenres: Set<Genre>
    let onContinue: () -> Void
    let onBack: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What are you into?")
                            .font(.system(.title, design: .serif, weight: .bold))
                            .foregroundStyle(Color.offscriptTextPrimary)
                            .staggeredEntrance(index: 0)

                        Text("Pick a few — we'll use these to find shows you'll actually listen to.")
                            .font(.offscriptBody)
                            .foregroundStyle(Color.offscriptTextSecondary)
                            .staggeredEntrance(index: 1)
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(Genre.allCases.enumerated()), id: \.element.id) { index, genre in
                            GenreCard(
                                genre: genre,
                                isSelected: selectedGenres.contains(genre),
                                onTap: { toggleGenre(genre) }
                            )
                            .staggeredEntrance(index: index + 2)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 120)
            }

            VStack(spacing: 12) {
                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(OnboardingContinueButtonStyle())

                Button("Back") { onBack() }
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextMuted)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                Color.offscriptBackground.opacity(0.95)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    private func toggleGenre(_ genre: Genre) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            if selectedGenres.contains(genre) {
                selectedGenres.remove(genre)
            } else {
                selectedGenres.insert(genre)
            }
        }
    }
}

private struct GenreCard: View {
    let genre: Genre
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: genre.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.offscriptAccent : Color.offscriptTextSecondary)

                Text(genre.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.offscriptTextPrimary : Color.offscriptTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 90)
            .background(isSelected ? Color.offscriptAccentSoft : Color.offscriptFillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: OffScriptTheme.Radius.medium, style: .continuous)
                    .stroke(isSelected ? Color.offscriptAccent : Color.offscriptHairline, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isSelected)
        .accessibilityLabel("\(genre.title)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct OnboardingContinueButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.offscriptAccent)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.97 : 1.0))
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

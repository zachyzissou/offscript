import SwiftUI

// MARK: - GenrePickerView (Tuner)
//
// "01 · TASTE / Pick your bands" — channel-bank-style genre selection.
// Each genre is a hairline rectangle with a mono channel index, the genre
// glyph in signal yellow when active, and a tracked-out caption.
struct GenrePickerView: View {
    @Binding var selectedGenres: Set<Genre>
    let onContinue: () -> Void
    let onBack: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        TunerLabel(text: "01 · TASTE", color: .offscriptSignalYellow, size: 10)
                            .staggeredEntrance(index: 0)

                        Text("Pick your bands")
                            .font(.system(size: 32, weight: .bold, design: .default))
                            .tracking(0)
                            .foregroundStyle(Color.offscriptPaperWhite)
                            .staggeredEntrance(index: 1)

                        Text("WE'LL TUNE TO THESE FREQUENCIES TO FIND YOUR CHANNELS")
                            .tunerFont(size: 9)
                            .foregroundStyle(Color.offscriptSoftPaper)
                            .staggeredEntrance(index: 2)
                    }

                    HStack {
                        TunerLabel(text: "\(selectedGenres.count) SELECTED",
                                   color: selectedGenres.isEmpty ? .offscriptSoftPaper : .offscriptSignalYellow)
                        Spacer()
                        TunerLabel(text: "\(Genre.allCases.count) BANDS")
                    }
                    .staggeredEntrance(index: 3)

                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Array(Genre.allCases.enumerated()), id: \.element.id) { index, genre in
                            GenreCard(
                                genre: genre,
                                index: index + 1,
                                isSelected: selectedGenres.contains(genre),
                                onTap: { toggleGenre(genre) }
                            )
                            .staggeredEntrance(index: index + 4)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 120)
            }

            // Bottom CTA bar — solid signal-yellow plate when ready, hairline when not.
            VStack(spacing: 10) {
                Button(action: onContinue) {
                    HStack(spacing: 0) {
                        Spacer()
                        Text(selectedGenres.isEmpty ? "PICK AT LEAST ONE BAND" : "CONTINUE →")
                            .font(.system(size: 13, weight: .bold, design: .default))
                            .tracking(2)
                            .foregroundStyle(selectedGenres.isEmpty
                                             ? Color.offscriptSoftPaper
                                             : Color.offscriptStudioBlack)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .background(selectedGenres.isEmpty ? Color.clear : Color.offscriptSignalYellow)
                    .overlay(
                        Rectangle().stroke(
                            selectedGenres.isEmpty ? Color.offscriptHairline : Color.clear,
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(.tunerPress)
                .disabled(selectedGenres.isEmpty)

                Button(action: onBack) {
                    TunerLabel(text: "← BACK")
                }
                .buttonStyle(.tunerPress)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.offscriptStudioBlack.ignoresSafeArea(edges: .bottom))
            .overlay(
                Rectangle()
                    .fill(Color.offscriptHairline)
                    .frame(height: 1),
                alignment: .top
            )
        }
        .background(Color.offscriptStudioBlack.ignoresSafeArea())
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
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(String(format: "%02d", index))
                        .tunerFont(size: 8, tracking: 1.4)
                        .foregroundStyle(isSelected ? Color.offscriptSignalYellow : Color.offscriptFadedPaper)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.offscriptSignalYellow)
                    }
                }

                Spacer()

                Image(systemName: genre.systemImage)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(isSelected ? Color.offscriptSignalYellow : Color.offscriptPaperWhite)

                Spacer().frame(height: 6)

                Text(genre.title.uppercased())
                    .tunerFont(size: 9, tracking: 1.2)
                    .foregroundStyle(isSelected ? Color.offscriptPaperWhite : Color.offscriptSoftPaper)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(isSelected ? Color.offscriptSignalYellow.opacity(0.08) : Color.clear)
            .overlay(
                Rectangle().stroke(
                    isSelected ? Color.offscriptSignalYellow : Color.offscriptHairline,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.tunerPress)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isSelected)
        .accessibilityLabel("\(genre.title)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// Kept for back-compat with any other call sites — internally maps to the
// signal-yellow plate CTA used in the new picker.
struct OnboardingContinueButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            Spacer()
            configuration.label
                .font(.system(size: 13, weight: .bold, design: .default))
                .tracking(2)
                .foregroundStyle(Color.offscriptStudioBlack)
            Spacer()
        }
        .padding(.vertical, 16)
        .background(Color.offscriptSignalYellow.opacity(configuration.isPressed ? 0.85 : 1))
        .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.99 : 1.0))
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

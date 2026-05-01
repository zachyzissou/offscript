import NaturalLanguage
import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Inline translation chip for episodes whose title or summary aren't in the
/// user's preferred language. Uses Apple's on-device Translation framework
/// (iOS 17.4+) — no network round-trip, no third-party API key.
///
/// Hidden when:
/// - Translation framework not available (older iOS, etc.)
/// - Source text already in the user's locale
/// - Source language detection fails
struct EpisodeTranslationView: View {
    let episode: Episode

    @State private var sourceLanguage: Locale.Language?
    @State private var targetLanguage = Locale.current.language
    @State private var translatedTitle: String?
    @State private var translatedSummary: String?
    @State private var isTranslationConfigured = false
    @State private var configuration: TranslationConfigurationToken?

    /// Wraps `TranslationSession.Configuration` so it survives @State storage.
    private struct TranslationConfigurationToken {
        let id = UUID()
    }

    var body: some View {
        Group {
            if let sourceLanguage,
               sourceLanguage.languageCode != targetLanguage.languageCode {
                content(sourceLanguage: sourceLanguage)
            } else {
                EmptyView()
            }
        }
        .task(id: episode.id) {
            sourceLanguage = detectLanguage(from: episode.title + " " + (episode.summary ?? ""))
        }
    }

    @ViewBuilder
    private func content(sourceLanguage: Locale.Language) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TunerLabel(text: "TRANSLATE · ON DEVICE", color: .offscriptSignalYellow)
                Spacer()
                TunerLabel(text: "SRC \(languageLabel(for: sourceLanguage).uppercased())",
                           color: .offscriptFnInfo)
            }

            if let translatedTitle {
                VStack(alignment: .leading, spacing: 6) {
                    Text(translatedTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.offscriptPaperWhite)
                        .fixedSize(horizontal: false, vertical: true)
                    if let translatedSummary, !translatedSummary.isEmpty {
                        Text(translatedSummary)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(Color.offscriptPaperWhite)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2)
                            .lineLimit(6)
                    }
                }
                .padding(.top, 2)
            } else {
                // Tuner-direction CTA — flat hairline-bordered button, mono.
                Button {
                    configuration = TranslationConfigurationToken()
                    isTranslationConfigured = true
                } label: {
                    HStack(spacing: 8) {
                        TunerLabel(text: "→ TRANSLATE TO \(languageLabel(for: targetLanguage).uppercased())",
                                   color: .offscriptSignalYellow,
                                   size: 10)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptHairline).frame(height: 1),
            alignment: .top
        )
        #if canImport(Translation)
        .translationTask(
            isTranslationConfigured ? makeConfiguration(source: sourceLanguage) : nil
        ) { session in
            await translate(using: session)
        }
        #endif
    }

    #if canImport(Translation)
    private func makeConfiguration(source: Locale.Language) -> TranslationSession.Configuration {
        TranslationSession.Configuration(source: source, target: targetLanguage)
    }

    private func translate(using session: TranslationSession) async {
        let titleRequest = TranslationSession.Request(sourceText: episode.title)
        let summaryText = (episode.summary ?? "").strippingHTML
        let summaryRequest = TranslationSession.Request(sourceText: summaryText)
        let requests = summaryText.isEmpty ? [titleRequest] : [titleRequest, summaryRequest]

        do {
            var titleOut: String?
            var summaryOut: String?
            for try await response in session.translate(batch: requests) {
                if response.clientIdentifier == titleRequest.clientIdentifier {
                    titleOut = response.targetText
                } else if response.clientIdentifier == summaryRequest.clientIdentifier {
                    summaryOut = response.targetText
                }
            }
            await MainActor.run {
                translatedTitle = titleOut ?? episode.title
                translatedSummary = summaryOut
            }
        } catch {
            // Translation framework will surface its own UI for downloading
            // language packs; if it errors here we just leave the action
            // available so the user can retry.
            await MainActor.run {
                isTranslationConfigured = false
            }
        }
    }
    #endif

    private func detectLanguage(from text: String) -> Locale.Language? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        return Locale.Language(identifier: dominant.rawValue)
    }

    private func languageLabel(for language: Locale.Language) -> String {
        guard let code = language.languageCode?.identifier else { return "" }
        return Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }
}

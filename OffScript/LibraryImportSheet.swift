import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private let importSheetLogger = Logger(subsystem: "com.offscript", category: "LibraryImport")

/// Tuner-styled import sheet for the Library "+" button. Two paths:
/// 1) Paste a podcast feed URL — single import, fast.
/// 2) Pick an OPML file — batch import every feed in the file with
///    per-row status so one bad feed doesn't fail the whole batch.
///
/// Reuses `FeedSyncService.importPodcast(...)` for both paths so a paste
/// or OPML import lands in the library indistinguishably from a
/// search-tap import.
struct LibraryImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    enum Mode: Hashable, Identifiable {
        case menu
        case pasteURL
        case opml(entries: [OPMLFeedEntry])

        var id: String {
            switch self {
            case .menu: "menu"
            case .pasteURL: "pasteURL"
            case .opml: "opml"
            }
        }
    }

    @State private var mode: Mode = .menu
    @State private var urlInput: String = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var importedTitle: String?
    @State private var opmlFilePresenting = false
    @State private var opmlImportProgress: [URL: ImportRowStatus] = [:]
    private let syncService = FeedSyncService()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.offscriptStudioBlack.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        switch mode {
                        case .menu: menuBody
                        case .pasteURL: pasteURLBody
                        case .opml(let entries): opmlBody(entries: entries)
                        }
                    }
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                    .padding(.top, 12)
                    .padding(.bottom, 90)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(Color.offscriptSignalYellow)
                }
            }
            .toolbarBackground(Color.offscriptStudioBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $opmlFilePresenting,
                allowedContentTypes: [.opml, .xml, .data],
                allowsMultipleSelection: false
            ) { result in
                handleOPMLPicked(result)
            }
        }
        .preferredColorScheme(.dark)
    }

    // ── Header ───────────────────────────────────────────────────────

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TunerLabel(text: "IMPORT · ADD CHANNELS", color: .offscriptSignalYellow)
                Spacer()
                TunerLabel(text: "URL · OPML", color: .offscriptFnInfo)
            }
            Text("Import")
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Color.offscriptPaperWhite)
            Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                .padding(.top, 4)
        }
    }

    // ── Mode: Menu ───────────────────────────────────────────────────

    private var menuBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            TunerLabel(text: "● PICK A SOURCE", color: .offscriptFnInfo)
            Text("Bring shows in by URL or OPML")
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.offscriptPaperWhite)
            Text("Paste a podcast feed URL to add a single show, or pick an OPML file exported from another podcast app to bring everything across at once.")
                .font(.system(size: 13))
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineSpacing(2)

            // Two big Tuner action keys, stacked.
            VStack(spacing: 10) {
                tunerActionKey(
                    text: "→ PASTE FEED URL",
                    color: .offscriptSignalYellow,
                    action: {
                        withAnimation(.easeInOut(duration: 0.18)) { mode = .pasteURL }
                    }
                )
                tunerActionKey(
                    text: "→ IMPORT OPML FILE",
                    color: .offscriptPaperWhite,
                    action: {
                        opmlFilePresenting = true
                    }
                )
            }
            .padding(.top, 8)

            if let importedTitle {
                Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                    .padding(.top, 8)
                HStack(spacing: 8) {
                    TunerLabel(text: "✓ ADDED", color: .offscriptFnMode, size: 9)
                    Text(importedTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.offscriptPaperWhite)
                    Spacer()
                }
            }

            if let errorMessage {
                errorStrip(message: errorMessage)
            }
        }
    }

    // ── Mode: Paste URL ──────────────────────────────────────────────

    private var pasteURLBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            backRow

            TunerLabel(text: "● FEED URL", color: .offscriptSignalYellow)
            Text("Paste a podcast feed URL")
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.offscriptPaperWhite)

            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.offscriptSignalYellow)
                TextField("",
                          text: $urlInput,
                          prompt: Text("https://example.com/feed.xml")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.offscriptSoftPaper))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .accentColor(Color.offscriptSignalYellow)
                    .onSubmit { Task { await importFromURLInput() } }
                if !urlInput.isEmpty {
                    Button { urlInput = "" } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.offscriptSoftPaper)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .overlay(Rectangle().stroke(Color.offscriptHairline, lineWidth: 1))

            tunerActionKey(
                text: isImporting ? "○ IMPORTING…" : "→ IMPORT",
                color: .offscriptSignalYellow,
                disabled: isImporting || urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: {
                    Task { await importFromURLInput() }
                }
            )

            if let importedTitle {
                Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                    .padding(.top, 4)
                HStack(spacing: 8) {
                    TunerLabel(text: "✓ ADDED", color: .offscriptFnMode, size: 9)
                    Text(importedTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.offscriptPaperWhite)
                    Spacer()
                }
            }

            if let errorMessage {
                errorStrip(message: errorMessage)
            }
        }
    }

    // ── Mode: OPML preview + batch import ────────────────────────────

    private func opmlBody(entries: [OPMLFeedEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            backRow

            HStack {
                TunerLabel(text: "● OPML PREVIEW", color: .offscriptSignalYellow)
                Spacer()
                TunerLabel(text: "\(entries.count) FEEDS", color: .offscriptFnInfo)
            }

            Text("Found \(entries.count) feed\(entries.count == 1 ? "" : "s")")
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.offscriptPaperWhite)

            tunerActionKey(
                text: isImporting ? "○ IMPORTING \(importedSuccessCount)/\(entries.count)…" : "→ IMPORT ALL",
                color: .offscriptSignalYellow,
                disabled: isImporting,
                action: {
                    Task { await batchImportOPML(entries) }
                }
            )

            // Per-row status — once import starts, each row shows whether
            // it succeeded, is queued, or failed (and why).
            LazyVStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                    opmlRow(idx: idx, entry: entry, status: opmlImportProgress[entry.feedURL] ?? .pending)
                    if idx < entries.count - 1 {
                        Rectangle().fill(Color.offscriptHairline).frame(height: 1)
                    }
                }
            }
            .padding(.top, 8)

            if let errorMessage {
                errorStrip(message: errorMessage)
            }
        }
    }

    private func opmlRow(idx: Int, entry: OPMLFeedEntry, status: ImportRowStatus) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(String(format: "%02d", idx + 1))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.offscriptSignalYellow)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title ?? entry.feedURL.host ?? entry.feedURL.absoluteString)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(1)
                Text(entry.feedURL.absoluteString)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.offscriptSoftPaper)
                    .lineLimit(1)
            }

            Spacer()

            TunerLabel(text: status.label, color: status.color, size: 8)
        }
        .padding(.vertical, 10)
    }

    // ── Shared chrome ────────────────────────────────────────────────

    private var backRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                mode = .menu
                errorMessage = nil
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                TunerLabel(text: "BACK", color: .offscriptSoftPaper, size: 10)
            }
            .foregroundStyle(Color.offscriptSoftPaper)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tunerActionKey(text: String,
                                color: Color,
                                disabled: Bool = false,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                TunerLabel(text: text, color: disabled ? .offscriptSoftPaper : color, size: 11)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .overlay(Rectangle().stroke(disabled ? Color.offscriptHairline : color, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func errorStrip(message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TunerLabel(text: "● IMPORT ERROR", color: .offscriptFnRecord)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.offscriptPaperWhite)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Color.offscriptFnRecord).frame(height: 1),
            alignment: .top
        )
    }

    private var importedSuccessCount: Int {
        opmlImportProgress.values.filter { if case .added = $0 { true } else { false } }.count
    }

    // ── Actions ──────────────────────────────────────────────────────

    @MainActor
    private func importFromURLInput() async {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        errorMessage = nil
        importedTitle = nil
        isImporting = true
        defer { isImporting = false }

        do {
            let result = try await PodcastImportService.resolve(urlString: trimmed)
            let podcast = try await syncService.importPodcast(from: result, into: modelContext)
            importedTitle = podcast.title
            urlInput = ""
        } catch {
            importSheetLogger.error("URL import failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func handleOPMLPicked(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // Security-scoped resource — file picker hands us a sandboxed
            // URL that needs an explicit access window.
            let accessGranted = url.startAccessingSecurityScopedResource()
            defer {
                if accessGranted { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                let entries = try PodcastImportService.extractFeedURLs(fromOPML: data)
                opmlImportProgress = Dictionary(
                    uniqueKeysWithValues: entries.map { ($0.feedURL, ImportRowStatus.pending) }
                )
                errorMessage = nil
                withAnimation(.easeInOut(duration: 0.18)) {
                    mode = .opml(entries: entries)
                }
            } catch {
                importSheetLogger.error("OPML pick failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            importSheetLogger.error("OPML picker error: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func batchImportOPML(_ entries: [OPMLFeedEntry]) async {
        isImporting = true
        defer { isImporting = false }
        errorMessage = nil

        // Sequentially — running 50 importPodcast calls in parallel would
        // hammer the iTunes lookup endpoint and trip rate limits. Per-row
        // status updates as we go so the user can watch progress.
        for entry in entries {
            opmlImportProgress[entry.feedURL] = .importing
            do {
                let result = try await PodcastImportService.resolve(opmlEntry: entry)
                _ = try await syncService.importPodcast(from: result, into: modelContext)
                opmlImportProgress[entry.feedURL] = .added
            } catch {
                importSheetLogger.error("OPML row failed for \(entry.feedURL.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                opmlImportProgress[entry.feedURL] = .failed
            }
        }
    }
}

// MARK: - Per-row status

enum ImportRowStatus {
    case pending
    case importing
    case added
    case failed

    var label: String {
        switch self {
        case .pending: "○ STANDBY"
        case .importing: "● IMPORTING"
        case .added: "✓ ADDED"
        case .failed: "✕ FAILED"
        }
    }

    var color: Color {
        switch self {
        case .pending: .offscriptSoftPaper
        case .importing: .offscriptSignalYellow
        case .added: .offscriptFnMode
        case .failed: .offscriptFnRecord
        }
    }
}

// MARK: - OPML UTType

extension UTType {
    /// OPML ships under several MIME / pasteboard types depending on which
    /// app exported it; declare one canonical UTType so .fileImporter
    /// accepts files exported from Apple Podcasts, Pocket Casts, Overcast,
    /// AntennaPod, and gPodder without the user having to fight the picker.
    static let opml = UTType(importedAs: "org.opml.opml", conformingTo: .xml)
}

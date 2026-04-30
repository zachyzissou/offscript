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
    @Query(
        filter: #Predicate<Podcast> { $0.isSubscribed == true },
        sort: [SortDescriptor(\Podcast.title)]
    ) private var subscribedPodcasts: [Podcast]

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
    @State private var exportFileURL: URL?
    @State private var isExportShareSheetPresented = false
    @ObservedObject private var batchImporter = BatchImportService.shared
    private let syncService = FeedSyncService()

    /// OPML row progress is read from the singleton so the sheet can be
    /// closed and reopened without losing state.
    private var opmlImportProgress: [URL: ImportRowStatus] {
        batchImporter.progress
    }

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
                    .padding(.top, OffScriptTheme.modalContentTopPadding)
                    .padding(.bottom, 90)
                }
            }
            // No `.toolbar` ToolbarItem — iOS 26 wraps toolbar buttons in
            // glass chrome. DONE key is rendered inline inside `header`.
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
            .sheet(isPresented: $isExportShareSheetPresented) {
                if let exportFileURL {
                    ShareSheet(items: [exportFileURL])
                        .tunerModalSurface()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // ── Header ───────────────────────────────────────────────────────

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TunerLabel(text: "IMPORT · ADD CHANNELS", color: .offscriptSignalYellow)
                    .lineLimit(1)
                Spacer()
                TunerLabel(text: "URL · OPML", color: .offscriptFnInfo)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Import")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.offscriptPaperWhite)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                // DONE inline — same reason every other sheet moved off
                // .toolbar ToolbarItem in 2.3.x.
                Button { dismiss() } label: {
                    TunerLabel(text: "DONE", color: .offscriptSignalYellow, size: 11)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(Rectangle().stroke(Color.offscriptSignalYellow, lineWidth: 1))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close import")
            }
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
                .tracking(0)
                .foregroundStyle(Color.offscriptPaperWhite)
            Text("Paste a podcast feed URL to add a single show, or pick an OPML file exported from another podcast app to bring everything across at once.")
                .font(.system(size: 13))
                .foregroundStyle(Color.offscriptPaperWhite)
                .lineSpacing(2)

            // Three Tuner action keys — paste, import OPML, export OPML.
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

                // Export — closes the loop with the OPML import path so
                // OffScript users can move out as easily as they moved in.
                // The exported file matches the format Apple Podcasts /
                // Pocket Casts / Overcast / AntennaPod accept.
                if !subscribedPodcasts.isEmpty {
                    Button {
                        prepareExport()
                    } label: {
                        HStack {
                            TunerLabel(
                                text: "↑ EXPORT \(subscribedPodcasts.count) SUBSCRIPTIONS",
                                color: .offscriptFnInfo, size: 11
                            )
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .overlay(Rectangle().stroke(Color.offscriptFnInfo, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
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
                .tracking(0)
                .foregroundStyle(Color.offscriptPaperWhite)

            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.offscriptSignalYellow)
                TextField("Podcast feed URL",
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
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear URL")
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
                .tracking(0)
                .foregroundStyle(Color.offscriptPaperWhite)

            // Hint that import keeps running after the sheet closes — the
            // user can dismiss this sheet, browse the library, do anything
            // else, and the batch finishes in the background.
            Text("Import runs in the background. You can close this sheet and keep using the app — Library will fill in as feeds finish.")
                .font(.system(size: 12))
                .foregroundStyle(Color.offscriptSoftPaper)
                .lineSpacing(2)

            tunerActionKey(
                text: batchImporter.isRunning
                    ? "○ IMPORTING \(batchImporter.addedCount)/\(entries.count)…"
                    : "→ IMPORT ALL · IN BACKGROUND",
                color: .offscriptSignalYellow,
                disabled: batchImporter.isRunning,
                action: {
                    batchImporter.start(entries: entries, modelContext: modelContext)
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
                    .truncationMode(.tail)
                Text(entry.feedURL.absoluteString)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.offscriptSoftPaper)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)

            Spacer()

            TunerLabel(text: status.label, color: status.color, size: 8)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
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

    private var importedSuccessCount: Int { batchImporter.addedCount }

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
            let podcast = try syncService.subscribeThenHydrate(from: result, into: modelContext)
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
                // Progress dict lives on the singleton — preview state
                // here is just "show this list, kick off when user taps".
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

    // OPML batch work lives in `BatchImportService.shared` so it survives
    // sheet dismissal — the user can close this sheet (or the app's
    // current foreground tab) and the import keeps running. Library
    // surfaces ongoing progress via `LibraryBatchImportStrip`.

    // ── Export ───────────────────────────────────────────────────────

    /// Generate an OPML file from the user's subscribed podcasts and
    /// hand it to the system share sheet. Lands in a temp directory so
    /// the OS cleans it up; if the user picks "Save to Files" the share
    /// sheet copies it elsewhere.
    private func prepareExport() {
        let data = PodcastOPMLExporter.export(podcasts: subscribedPodcasts)
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("offscript-subscriptions-\(timestamp).opml")
        do {
            try data.write(to: url, options: .atomic)
            exportFileURL = url
            isExportShareSheetPresented = true
        } catch {
            importSheetLogger.error("OPML export write failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't write the export file."
        }
    }
}

/// Thin wrapper around `UIActivityViewController` for sharing the
/// generated OPML file. SwiftUI's native `ShareLink` works for simple
/// cases but the explicit URL we want to share is a temp file, and
/// presenting a UIActivityViewController gives the user the full set
/// of share targets (Save to Files, AirDrop, Mail, etc.).
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Per-row status

enum ImportRowStatus {
    case pending
    case importing
    case added
    case skipped
    case failed
    case cancelled

    var label: String {
        switch self {
        case .pending: "○ STANDBY"
        case .importing: "● IMPORTING"
        case .added: "✓ ADDED"
        case .skipped: "✓ EXISTS"
        case .failed: "✕ FAILED"
        case .cancelled: "× CANCELLED"
        }
    }

    var color: Color {
        switch self {
        case .pending: .offscriptSoftPaper
        case .importing: .offscriptSignalYellow
        case .added: .offscriptFnMode
        case .skipped: .offscriptFnInfo
        case .failed: .offscriptFnRecord
        case .cancelled: .offscriptSoftPaper
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

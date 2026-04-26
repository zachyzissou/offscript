import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Two-stage flow:
/// 1. Pick an .opml file via the system Files picker.
/// 2. Show a review list grouped by Fresh / Already subscribed / Title match,
///    let the user toggle inclusion + confirm, then import in parallel.
struct OPMLImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var stage: Stage = .picker
    @State private var importerPresented = false
    @State private var candidates: [OPMLImportService.CandidateFeed] = []
    @State private var summary: OPMLImportService.ImportSummary?
    @State private var isImporting = false
    @State private var progress: (done: Int, total: Int) = (0, 0)
    @State private var errorMessage: String?

    private let service = OPMLImportService()

    private var opmlContentTypes: [UTType] {
        var types: [UTType] = [.xml, .text, .data]
        // Custom OPML type registered in Info.plist's UTImportedTypeDeclarations.
        if let opml = UTType("org.opml.opml") {
            types.insert(opml, at: 0)
        }
        if let byExtension = UTType(filenameExtension: "opml") {
            types.insert(byExtension, at: 0)
        }
        return types
    }

    enum Stage { case picker, review, importing, done }

    var body: some View {
        NavigationStack {
            content
                .background(Color.offscriptBackground.ignoresSafeArea())
                .navigationTitle("Import Subscriptions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(stage == .done ? "Done" : "Cancel") { dismiss() }
                            .tint(Color.offscriptAccent)
                    }
                    if stage == .review, candidates.contains(where: { $0.include && !$0.isDuplicate }) {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Import") { Task { await runImport() } }
                                .tint(Color.offscriptAccent)
                                .disabled(isImporting)
                        }
                    }
                }
                .preferredColorScheme(.dark)
        }
        .fileImporter(
            isPresented: $importerPresented,
            allowedContentTypes: opmlContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handlePickerResult(result)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .picker:
            pickerStage
        case .review:
            reviewStage
        case .importing:
            importingStage
        case .done:
            doneStage
        }
    }

    // MARK: - Picker

    private var pickerStage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.offscriptAccent)
                .padding(28)
                .background(Color.offscriptAccentSoft, in: Circle())

            VStack(spacing: 10) {
                Text("Bring your shows over")
                    .font(.offscriptDisplay)
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .multilineTextAlignment(.center)

                Text("Export an OPML file from Apple Podcasts, Pocket Casts, Overcast, Castro, or Spotify, then drop it in. We'll skip anything you already follow.")
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.offscriptMeta)
                    .foregroundStyle(Color.offscriptDestructive)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button {
                importerPresented = true
            } label: {
                Label("Choose OPML file", systemImage: "doc.badge.plus")
            }
            .buttonStyle(PrimaryPillButtonStyle())

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Review

    private var reviewStage: some View {
        let fresh = candidates.filter { $0.duplicate == .fresh }
        let dupes = candidates.filter { $0.isDuplicate }

        return ScrollView {
            VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                summaryHeader

                if !fresh.isEmpty {
                    section(title: "New shows", subtitle: "These will be added to your library.", items: fresh)
                }

                if !dupes.isEmpty {
                    section(
                        title: "Already in your library",
                        subtitle: "Off by default. Toggle on if you want OffScript to refresh them.",
                        items: dupes
                    )
                }

                Spacer(minLength: 24)
            }
            .padding(.vertical, OffScriptTheme.pagePadding)
        }
    }

    private var summaryHeader: some View {
        let fresh = candidates.filter { $0.duplicate == .fresh }.count
        let dupes = candidates.filter { $0.isDuplicate }.count

        return VStack(alignment: .leading, spacing: 10) {
            OffScriptUtilityHeader(
                eyebrow: "OPML",
                title: "Found \(candidates.count) shows",
                subtitle: "\(fresh) new, \(dupes) already followed"
            )
        }
        .padding(.horizontal, OffScriptTheme.pagePadding)
    }

    private func section(title: String, subtitle: String, items: [OPMLImportService.CandidateFeed]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.offscriptSectionTitle)
                    .foregroundStyle(Color.offscriptTextPrimary)
                Text(subtitle)
                    .font(.offscriptBody)
                    .foregroundStyle(Color.offscriptTextMuted)
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)

            VStack(spacing: 8) {
                ForEach(items) { item in
                    candidateRow(item)
                }
            }
            .padding(.horizontal, OffScriptTheme.pagePadding)
        }
    }

    private func candidateRow(_ item: OPMLImportService.CandidateFeed) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.feed.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .lineLimit(2)
                if let author = item.feed.author, !author.isEmpty {
                    Text(author)
                        .font(.offscriptMeta)
                        .foregroundStyle(Color.offscriptTextMuted)
                        .lineLimit(1)
                }
                if let host = item.feed.feedURL.host {
                    Text(host)
                        .font(.offscriptMicro)
                        .foregroundStyle(Color.offscriptTextMuted.opacity(0.7))
                        .lineLimit(1)
                }
                if let badge = duplicateBadge(item.duplicate) {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.offscriptAccentSecondaryMuted, in: Capsule())
                        .foregroundStyle(Color.offscriptAccentSecondary)
                }
            }

            Spacer()

            Toggle("", isOn: bindingForItem(item.id))
                .labelsHidden()
                .tint(Color.offscriptAccent)
        }
        .padding(14)
        .background(Color.offscriptCard, in: RoundedRectangle(cornerRadius: OffScriptTheme.Radius.small, style: .continuous))
    }

    private func duplicateBadge(_ state: OPMLImportService.DuplicateState) -> String? {
        switch state {
        case .fresh: return nil
        case .alreadySubscribed: return "ALREADY FOLLOWED"
        case .fuzzyTitleMatch: return "TITLE MATCH"
        }
    }

    private func bindingForItem(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: {
                candidates.first(where: { $0.id == id })?.include ?? false
            },
            set: { newValue in
                if let index = candidates.firstIndex(where: { $0.id == id }) {
                    candidates[index].include = newValue
                }
            }
        )
    }

    // MARK: - Importing

    private var importingStage: some View {
        VStack(spacing: 22) {
            Spacer()

            ProgressView(value: progressFraction)
                .progressViewStyle(.linear)
                .tint(Color.offscriptAccent)
                .padding(.horizontal, 36)

            Text("Importing \(progress.done) of \(progress.total)…")
                .font(.offscriptBody)
                .foregroundStyle(Color.offscriptTextSecondary)

            Spacer()
        }
    }

    private var progressFraction: Double {
        guard progress.total > 0 else { return 0 }
        return Double(progress.done) / Double(progress.total)
    }

    // MARK: - Done

    private var doneStage: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: summary?.failed.isEmpty == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(summary?.failed.isEmpty == true ? Color.offscriptAccent : Color.offscriptDestructive)

            VStack(spacing: 6) {
                Text(summary?.failed.isEmpty == true ? "Imported" : "Imported with issues")
                    .font(.offscriptDisplay)
                    .foregroundStyle(Color.offscriptTextPrimary)

                if let summary {
                    Text("\(summary.imported) added, \(summary.skipped) skipped, \(summary.failed.count) failed")
                        .font(.offscriptBody)
                        .foregroundStyle(Color.offscriptTextSecondary)
                }
            }

            if let summary, !summary.failed.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(summary.failed, id: \.0.id) { failed in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(failed.0.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.offscriptTextPrimary)
                                Text(failed.1)
                                    .font(.offscriptMeta)
                                    .foregroundStyle(Color.offscriptTextMuted)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.offscriptCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .frame(maxHeight: 180)
            }

            Spacer()
        }
    }

    // MARK: - Actions

    private func handlePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Files-app provided URL needs security-scoped access for sandboxed reads.
            let needsSecurityScope = url.startAccessingSecurityScopedResource()
            defer { if needsSecurityScope { url.stopAccessingSecurityScopedResource() } }

            do {
                let feeds = try service.parse(fileURL: url)
                guard !feeds.isEmpty else {
                    errorMessage = "Couldn't find any podcast feeds in that file."
                    return
                }
                let resolved = service.resolveDuplicates(feeds, in: modelContext)
                candidates = resolved
                stage = .review
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func runImport() async {
        isImporting = true
        stage = .importing
        defer { isImporting = false }

        let result = await service.importSelected(candidates, into: modelContext) { done, total in
            progress = (done, total)
        }
        summary = result
        stage = .done
        try? TasteProfileService.refresh(in: modelContext)
        TelemetryService.track(
            "opml_imported",
            metadata: [
                "imported": "\(result.imported)",
                "skipped": "\(result.skipped)",
                "failed": "\(result.failed.count)"
            ],
            in: modelContext
        )
    }
}

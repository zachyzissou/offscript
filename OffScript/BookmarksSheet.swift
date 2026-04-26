import SwiftData
import SwiftUI

/// All bookmarks for a single episode. Tapping one seeks the player to that
/// timestamp; long-press deletes. Designed to be presented as a sheet from
/// the player.
struct EpisodeBookmarksSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let episode: Episode

    @State private var bookmarks: [Bookmark] = []
    @State private var editingBookmark: Bookmark?
    @State private var newBookmarkNote: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OffScriptTheme.sectionSpacing) {
                    OffScriptUtilityHeader(
                        eyebrow: "Bookmarks",
                        title: episode.title,
                        subtitle: bookmarks.isEmpty
                            ? "Save spots in this episode you want to come back to."
                            : "\(bookmarks.count) saved \(bookmarks.count == 1 ? "spot" : "spots") in this episode."
                    )
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                    if bookmarks.isEmpty {
                        OffScriptEmptyState(
                            icon: "bookmark",
                            headline: "No bookmarks yet",
                            message: "Tap the bookmark button on the player while listening — we'll save the timestamp."
                        )
                    } else {
                        VStack(spacing: 10) {
                            ForEach(bookmarks) { bookmark in
                                BookmarkRow(bookmark: bookmark) {
                                    PlaybackController.shared.seek(to: bookmark.position)
                                    dismiss()
                                } onEdit: {
                                    editingBookmark = bookmark
                                    newBookmarkNote = bookmark.note ?? ""
                                } onDelete: {
                                    delete(bookmark)
                                }
                            }
                        }
                        .padding(.horizontal, OffScriptTheme.pagePadding)
                    }

                    Spacer(minLength: 32)
                }
                .padding(.vertical, 16)
            }
            .offscriptPageBackground()
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .tint(Color.offscriptAccent)
                }
            }
            .preferredColorScheme(.dark)
        }
        .task { reload() }
        .sheet(item: $editingBookmark) { bookmark in
            EditBookmarkSheet(bookmark: bookmark, note: $newBookmarkNote) {
                bookmark.note = newBookmarkNote.trimmingCharacters(in: .whitespacesAndNewlines)
                if bookmark.note?.isEmpty == true { bookmark.note = nil }
                try? modelContext.save()
                editingBookmark = nil
                reload()
            } onDelete: {
                delete(bookmark)
                editingBookmark = nil
            }
        }
    }

    private func reload() {
        let episodeID = episode.id
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate<Bookmark> { $0.episode?.id == episodeID },
            sortBy: [SortDescriptor(\Bookmark.position, order: .forward)]
        )
        bookmarks = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func delete(_ bookmark: Bookmark) {
        modelContext.delete(bookmark)
        try? modelContext.save()
        reload()
    }
}

private struct BookmarkRow: View {
    let bookmark: Bookmark
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onTap) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(positionLabel)
                            .font(.system(.headline, design: .monospaced).monospacedDigit())
                            .foregroundStyle(Color.offscriptAccent)
                        if let note = bookmark.note, !note.isEmpty {
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(Color.offscriptTextPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        } else {
                            Text("Tap to play from here")
                                .font(.offscriptMeta)
                                .foregroundStyle(Color.offscriptTextMuted)
                        }
                        Text(bookmark.createdAt.formatted(.relative(presentation: .numeric)))
                            .font(.offscriptMicro)
                            .foregroundStyle(Color.offscriptTextMuted.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.offscriptTextPrimary)
                        .frame(width: 36, height: 36)
                        .background(Color.offscriptFillLight, in: Circle())
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.offscriptCard, in: RoundedRectangle(cornerRadius: OffScriptTheme.Radius.small, style: .continuous))
        .contextMenu {
            Button { onEdit() } label: {
                Label("Edit Note", systemImage: "pencil")
            }
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var positionLabel: String {
        let total = Int(bookmark.position)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

private struct EditBookmarkSheet: View {
    let bookmark: Bookmark
    @Binding var note: String
    let onSave: () -> Void
    let onDelete: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Note")
                    .font(.offscriptSectionTitle)
                    .foregroundStyle(Color.offscriptTextPrimary)
                    .padding(.horizontal, OffScriptTheme.pagePadding)

                TextEditor(text: $note)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Color.offscriptCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, OffScriptTheme.pagePadding)
                    .frame(minHeight: 140)

                Spacer()
            }
            .padding(.top, 16)
            .offscriptPageBackground()
            .navigationTitle("Edit bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(Color.offscriptTextMuted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: onSave)
                        .tint(Color.offscriptAccent)
                        .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty && bookmark.note == nil)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete bookmark", systemImage: "trash")
                    }
                    .tint(Color.offscriptDestructive)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear { focused = true }
        }
    }
}

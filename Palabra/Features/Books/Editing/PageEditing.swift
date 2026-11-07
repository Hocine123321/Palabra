import SwiftUI

/// What the reader hands a page while it is in Edit mode: one closure per thing the person can do on that page.
/// Blocks are addressed by their position on the page.
struct PageEditing {
    var editDetails: () -> Void
    var editBlock: (Int) -> Void
    var insertBlock: (Int) -> Void
    var moveBlock: (Int, Int) -> Void
    var deleteBlock: (Int) -> Void
    var addPage: () -> Void
    var movePage: (Int) -> Void
    var deletePage: () -> Void
}

/// The sheets Edit mode can open.
enum EditSheet: Identifiable {
    case block(pageID: String, index: Int, draft: BlockDraft)
    case newBlock(pageID: String, at: Int)
    case details(pageID: String)

    var id: String {
        switch self {
        case .block(let pageID, let index, _): "block.\(pageID).\(index)"
        case .newBlock(let pageID, let at): "new.\(pageID).\(at)"
        case .details(let pageID): "details.\(pageID)"
        }
    }
}

/// Lesson title, page title and the optional line under it.
struct PageDetailsEditorView: View {
    @State var lessonTitle: String
    @State var pageTitle: String
    @State var dateLabel: String
    let onSave: (_ lessonTitle: String, _ pageTitle: String, _ dateLabel: String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Lesson") { TextField("Lesson title", text: $lessonTitle) }
                Section("Page") {
                    TextField("Page title", text: $pageTitle)
                    TextField("Line under the title (optional)", text: $dateLabel)
                }
            }
            .navigationTitle("Edit Titles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(lessonTitle, pageTitle, dateLabel)
                        dismiss()
                    }
                    .disabled(lessonTitle.trimmingCharacters(in: .whitespaces).isEmpty
                        || pageTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// The small menu shown under each block in Edit mode.
struct BlockEditMenu: View {
    let index: Int
    let count: Int
    let block: Block
    let editing: PageEditing
    @Environment(\.bookPalette) private var palette

    var body: some View {
        Menu {
            if BlockDraft(block) != nil {
                Button("Edit", systemImage: "pencil") { editing.editBlock(index) }
            }
            Button("Add Block Below", systemImage: "plus") { editing.insertBlock(index + 1) }
            Button("Move Up", systemImage: "arrow.up") { editing.moveBlock(index, index - 1) }
                .disabled(index == 0)
            Button("Move Down", systemImage: "arrow.down") { editing.moveBlock(index, index + 1) }
                .disabled(index >= count - 1)
            Button("Delete", systemImage: "trash", role: .destructive) { editing.deleteBlock(index) }
                .disabled(count <= 1)
        } label: {
            Label("Edit Block", systemImage: "ellipsis.circle")
                .font(palette.font(.footnote, weight: .semibold))
                .foregroundStyle(palette.accent)
        }
        .accessibilityIdentifier("blockMenu.\(index)")
    }
}

/// The page-level menu under the header in Edit mode.
struct PageEditMenu: View {
    let editing: PageEditing
    @Environment(\.bookPalette) private var palette

    var body: some View {
        Menu {
            Button("Edit Titles", systemImage: "pencil") { editing.editDetails() }
            Button("Add Block", systemImage: "plus") { editing.insertBlock(0) }
            Button("Add Page After", systemImage: "doc.badge.plus") { editing.addPage() }
            Button("Move Page Earlier", systemImage: "arrow.up") { editing.movePage(-1) }
            Button("Move Page Later", systemImage: "arrow.down") { editing.movePage(1) }
            Button("Delete Page", systemImage: "trash", role: .destructive) { editing.deletePage() }
        } label: {
            Label("Edit Page", systemImage: "square.and.pencil")
                .font(palette.font(.footnote, weight: .semibold))
                .foregroundStyle(palette.accent)
        }
        .accessibilityIdentifier("pageMenu")
    }
}

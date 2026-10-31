import SwiftUI

extension BooksViewStyle {
    var title: LocalizedStringKey {
        switch self {
        case .desk: return "3D desk"
        case .classic: return "Classic pages"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .desk:
            return "The books lie on a 3D desk. Turn real pages, pick up a magnifying glass, a ruler and a bookmark. Uses more battery."
        case .classic:
            return "Flat pages in a plain list, the way the Books tab used to look. Lighter on the battery."
        }
    }
}

extension SceneQuality {
    var title: LocalizedStringKey {
        switch self {
        case .standard: return "Standard"
        case .saver: return "Battery saver"
        }
    }
}

/// Everything about the Books tab that can be tweaked: how the books are shown, how the 3D desk is drawn, how pages read,
/// and clearing reading progress.
struct BooksSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var resetTarget: Book?

    var body: some View {
        @Bindable var shelf = environment.books
        Form {
            Section {
                Picker("View", selection: $shelf.preferences.viewStyle) {
                    ForEach(BooksViewStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .accessibilityIdentifier("booksViewStylePicker")
            } header: {
                Text("View")
            } footer: {
                Text(shelf.preferences.viewStyle.detail)
            }
            .themedSection()

            if shelf.preferences.viewStyle == .desk {
                Section {
                    Picker("Quality", selection: $shelf.preferences.sceneQuality) {
                        ForEach(SceneQuality.allCases) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }
                    .accessibilityIdentifier("booksQualityPicker")
                } header: {
                    Text("3D desk")
                } footer: {
                    Text("Battery saver draws the desk with fewer pixels and no shadows.")
                }
                .themedSection()
            }

            Section("Reading") {
                Picker("Text size", selection: $shelf.preferences.textSize) {
                    ForEach(ReaderTextSize.allCases) { size in
                        Text(size.titleKey).tag(size)
                    }
                }
                .accessibilityIdentifier("booksTextSizePicker")
                Picker("Memorize level", selection: $shelf.preferences.recallLevel) {
                    ForEach(RecallLevel.allCases) { level in
                        Text(level.titleKey).tag(level)
                    }
                }
                .accessibilityIdentifier("booksLevelPicker")
            }
            .themedSection()

            Section {
                ForEach(shelf.library.books.filter { !$0.isEmpty }) { book in
                    Button(role: .destructive) {
                        resetTarget = book
                    } label: {
                        Text("Reset progress: \(book.title)")
                    }
                    .accessibilityIdentifier("booksReset.\(book.id)")
                }
            } header: {
                Text("Reading progress")
            } footer: {
                Text("Clears the pages marked as read and the bookmark. The lessons are not touched.")
            }
            .themedSection()
        }
        .glassScreen()
        .navigationTitle("Books Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Reset reading progress?",
            isPresented: Binding(get: { resetTarget != nil }, set: { if !$0 { resetTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                if let book = resetTarget { shelf.resetProgress(bookID: book.id) }
                resetTarget = nil
            }
            Button("Cancel", role: .cancel) { resetTarget = nil }
        }
    }
}

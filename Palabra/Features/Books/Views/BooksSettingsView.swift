import SwiftUI

extension SceneQuality {
    var title: LocalizedStringKey {
        switch self {
        case .standard: return "Standard"
        case .saver: return "Battery saver"
        }
    }
}

/// Everything about the Books tab that can be tweaked: how the 3D desk is drawn, how pages read, and clearing reading progress.
struct BooksSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var resetTarget: Book?

    var body: some View {
        @Bindable var shelf = environment.books
        Form {
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

            Section {
                Toggle("Free view", isOn: $shelf.preferences.freeView)
                    .accessibilityIdentifier("booksFreeViewToggle")
                Toggle("Extra effects", isOn: $shelf.preferences.enhancements)
                    .accessibilityIdentifier("booksEnhancementsToggle")
            } footer: {
                Text("Free view lets you pinch to zoom out or in and drag to move the view while you read. Extra effects add soft shadows, depth of field, dust and lamp glow to the desk; they never touch the page you read, and Battery saver turns them off.")
            }
            .themedSection()

            Section {
                Button {
                    shelf.tourRequested = true
                    environment.router.tab = .books
                } label: {
                    Text("Pull a test")
                }
                .accessibilityIdentifier("pullATestButton")
            } header: {
                Text("Test")
            } footer: {
                Text("Runs a scripted walk through the Books tab, records the screen and writes a log you can share.")
            }
            .themedSection()

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

import SwiftUI
import UniformTypeIdentifiers

/// One folder of the file browser.
struct StorageFolderView: View {
    let browser: StorageBrowser
    let folder: URL
    let title: String
    let clipboard: StorageClipboard

    @State private var model: StorageFolderModel
    @State private var showImporter = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var renaming: StorageItem?
    @State private var renameText = ""
    @State private var deleting: StorageItem?

    init(browser: StorageBrowser, folder: URL, title: String, clipboard: StorageClipboard) {
        self.browser = browser
        self.folder = folder
        self.title = title
        self.clipboard = clipboard
        _model = State(initialValue: StorageFolderModel(browser: browser, folder: folder))
    }

    var body: some View {
        List {
            if model.items.isEmpty, !model.isLoading {
                Text(model.loadFailed ? "This folder can't be read." : "This folder is empty.")
                    .foregroundStyle(Theme.inkSecondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(model.items) { item in
                row(item)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
        .glassScreen()
        .overlay { if model.isLoading, model.items.isEmpty { ProgressView() } }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    if let source = clipboard.source {
                        Button { Task { await model.paste(source) } } label: { Label("Paste Here", systemImage: "doc.on.clipboard") }
                    }
                    Button { newFolderName = ""; showNewFolder = true } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                    Button { showImporter = true } label: { Label("Import File", systemImage: "square.and.arrow.down") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("storageFolderMenu")
            }
        }
        .task { await model.reload() }
        .refreshable { await model.reload() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { Task { await model.importFile(url) } }
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { let name = newFolderName; Task { await model.createFolder(named: name) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let item = renaming { let name = renameText; Task { await model.rename(item, to: name) } }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            "Delete this item?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let item = deleting { Task { await model.delete(item) } }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            if let item = deleting { Text("\(item.name) will be removed from this device. This can't be undone.") }
        }
        .alert("Couldn't Finish", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(LocalizedStringKey(model.errorMessage ?? ""))
        }
    }

    @ViewBuilder
    private func row(_ item: StorageItem) -> some View {
        let content = HStack(spacing: Theme.Spacing.sm + 4) {
            Image(systemName: item.isFolder ? "folder.fill" : "doc")
                .foregroundStyle(item.isFolder ? Theme.accent : Theme.inkSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.name).lineLimit(1).truncationMode(.middle)
                Text(verbatim: StorageView.format(item.size)).font(.footnote).foregroundStyle(Theme.inkSecondary).monospacedDigit()
            }
            Spacer(minLength: 0)
            if item.isProtected {
                Image(systemName: "lock.fill").font(.footnote).foregroundStyle(Theme.inkSecondary)
                    .accessibilityLabel(Text("Locked"))
            }
        }
        if item.isFolder {
            NavigationLink {
                StorageFolderView(browser: browser, folder: item.url, title: item.name, clipboard: clipboard)
            } label: { content }
            .contextMenu { actions(item) }
            .swipeActions(edge: .trailing) { deleteAction(item) }
        } else {
            content
                .contextMenu { actions(item) }
                .swipeActions(edge: .trailing) { deleteAction(item) }
        }
    }

    @ViewBuilder
    private func actions(_ item: StorageItem) -> some View {
        Button { clipboard.copy(item.url) } label: { Label("Copy", systemImage: "doc.on.doc") }
        if !item.isFolder { ShareLink(item: item.url) { Label("Share", systemImage: "square.and.arrow.up") } }
        if item.isFolder, let source = clipboard.source {
            Button { Task { await model.paste(source, into: item.url) } } label: { Label("Paste Into Folder", systemImage: "doc.on.clipboard") }
        }
        if !item.isProtected {
            Button { renameText = item.name; renaming = item } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { deleting = item } label: { Label("Delete", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private func deleteAction(_ item: StorageItem) -> some View {
        if !item.isProtected {
            Button(role: .destructive) { deleting = item } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

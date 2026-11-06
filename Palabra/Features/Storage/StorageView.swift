import SwiftUI

/// Settings → Storage: how much space each part of the app uses, and a file browser for the app's own folders.
struct StorageView: View {
    @State private var usage: [StorageUsage] = []
    @State private var clipboard = StorageClipboard()
    @State private var measured = false

    private var total: Int64 { usage.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        Form {
            Section {
                if !measured {
                    HStack { ProgressView(); Text("Measuring…").foregroundStyle(Theme.inkSecondary) }
                } else {
                    LabeledContent("Total") {
                        Text(verbatim: Self.format(total)).monospacedDigit().fontWeight(.semibold)
                    }
                    ForEach(usage, id: \.root) { entry in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            HStack {
                                Text(LocalizedStringKey(entry.root.title))
                                Spacer()
                                Text(verbatim: Self.format(entry.bytes)).monospacedDigit().foregroundStyle(Theme.inkSecondary)
                            }
                            ProgressView(value: total > 0 ? Double(entry.bytes) / Double(total) : 0)
                                .tint(Theme.accent)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } header: {
                Text("Space Used")
            }
            .themedSection()

            Section {
                ForEach(StorageRoot.allCases) { root in
                    NavigationLink {
                        StorageFolderView(browser: StorageBrowser(root: root.url()), folder: root.url(), title: root.title, clipboard: clipboard)
                    } label: {
                        HStack(spacing: Theme.Spacing.sm + 4) {
                            IconTile(systemImage: root.systemImage, tint: Theme.tileTints[1], size: 30)
                            Text(LocalizedStringKey(root.title))
                        }
                    }
                    .accessibilityIdentifier("storageRoot-\(root.rawValue)")
                }
            } header: {
                Text("Browse Files")
            } footer: {
                Text("The live library database is locked: it can't be changed, renamed or deleted here. For a safe backup of your library use Export in Settings.")
            }
            .themedSection()

            if clipboard.hasItem {
                Section {
                    Label {
                        Text("Copied: \(clipboard.name)")
                    } icon: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    Button("Clear Clipboard", role: .destructive) { clipboard.clear() }
                }
                .themedSection()
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .glassScreen()
        .task {
            usage = await StorageOverview.measure()
            measured = true
        }
    }

    static func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

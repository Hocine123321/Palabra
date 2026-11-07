import SwiftUI

/// One form for every block type. Edits a `BlockDraft`; Save is enabled once the draft makes a valid block.
struct BlockEditorView: View {
    @State private var draft: BlockDraft
    let isNew: Bool
    let onSave: (Block) -> Void
    @Environment(\.dismiss) private var dismiss

    init(draft: BlockDraft, isNew: Bool, onSave: @escaping (Block) -> Void) {
        _draft = State(initialValue: draft)
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                if isNew {
                    Section {
                        Picker("Block type", selection: kindBinding) {
                            ForEach(BlockDraft.Kind.allCases) { kind in Text(kind.titleKey).tag(kind) }
                        }
                    }
                }
                fields
            }
            .navigationTitle(isNew ? "New Block" : draft.kind.titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let block = draft.block() else { return }
                        onSave(block)
                        dismiss()
                    }
                    .disabled(draft.block() == nil)
                    .accessibilityIdentifier("blockEditorSave")
                }
            }
        }
    }

    private var kindBinding: Binding<BlockDraft.Kind> {
        Binding(get: { draft.kind }, set: { draft = BlockDraft(kind: $0) })
    }

    // MARK: Fields per kind

    @ViewBuilder private var fields: some View {
        switch draft.kind {
        case .heading:
            Section {
                multiline("Text", $draft.text)
                Picker("Level", selection: $draft.level) {
                    Text(verbatim: "1").tag(1)
                    Text(verbatim: "2").tag(2)
                    Text(verbatim: "3").tag(3)
                }
                .pickerStyle(.segmented)
            }
        case .paragraph:
            Section { multiline("Text", $draft.text) }
        case .list:
            Section {
                single("Title (optional)", $draft.title)
                Toggle("Numbered", isOn: $draft.ordered)
                multiline("One item per line", lines($draft.items))
            }
        case .keyPoint:
            Section {
                single("Label (optional)", $draft.label)
                multiline("Text", $draft.text)
            }
        case .quote:
            Section {
                multiline("Text", $draft.text)
                single("Source (optional)", $draft.source)
            }
        case .timeline:
            Section { single("Title (optional)", $draft.title) }
            rows(\.events, empty: TimelineEvent(date: "", title: "", detail: nil)) { event in
                single("Date", event.date)
                single("Event", event.title)
                single("Detail (optional)", optional(event.detail))
            }
        case .stats:
            Section { single("Title (optional)", $draft.title) }
            rows(\.stats, empty: StatItem(label: "", value: "", unit: nil, note: nil)) { item in
                single("Label", item.label)
                single("Value", item.value)
                single("Unit (optional)", optional(item.unit))
                single("Note (optional)", optional(item.note))
            }
        case .comparison:
            Section {
                single("Title (optional)", $draft.title)
                single("Corner label (optional)", $draft.corner)
                multiline("One column per line", lines($draft.columns))
            }
            rows(\.rows, empty: ComparisonRow(label: "", cells: [])) { row in
                single("Row", row.label)
                multiline("One cell per line, in column order", lines(row.cells))
            }
        case .causeEffect:
            Section { single("Title (optional)", $draft.title) }
            rows(\.stages, empty: FlowStage(label: nil, nodes: [""])) { stage in
                single("Group (optional)", optional(stage.label))
                multiline("One item per line", lines(stage.nodes))
            }
        case .process:
            Section { single("Title (optional)", $draft.title) }
            rows(\.steps, empty: ProcessStep(title: "", detail: nil)) { step in
                single("Step", step.title)
                single("Detail (optional)", optional(step.detail))
            }
        case .definitions:
            Section { single("Title (optional)", $draft.title) }
            rows(\.definitions, empty: DefinitionItem(id: nil, term: "", definition: "")) { item in
                single("Term", item.term)
                multiline("Definition", item.definition)
            }
        }
    }

    /// The repeated rows of a block: each row is a section of fields, swipe to delete, and a button adds a blank one.
    @ViewBuilder
    private func rows<T, Content: View>(
        _ path: WritableKeyPath<BlockDraft, [T]>,
        empty: T,
        @ViewBuilder content: @escaping (Binding<T>) -> Content
    ) -> some View {
        ForEach(Array(draft[keyPath: path].indices), id: \.self) { i in
            Section { content(rowBinding(path, i, empty)) }
        }
        .onDelete { offsets in
            guard draft[keyPath: path].count > offsets.count else { return }
            draft[keyPath: path].remove(atOffsets: offsets)
        }
        Section {
            Button("Add row") { draft[keyPath: path].append(empty) }
        }
    }

    /// A binding to one row that does nothing when the row has just been deleted (SwiftUI can ask once more).
    private func rowBinding<T>(_ path: WritableKeyPath<BlockDraft, [T]>, _ i: Int, _ fallback: T) -> Binding<T> {
        Binding(
            get: { draft[keyPath: path].indices.contains(i) ? draft[keyPath: path][i] : fallback },
            set: { if draft[keyPath: path].indices.contains(i) { draft[keyPath: path][i] = $0 } }
        )
    }

    private func single(_ title: LocalizedStringKey, _ text: Binding<String>) -> some View {
        TextField(title, text: text)
    }

    private func multiline(_ title: LocalizedStringKey, _ text: Binding<String>) -> some View {
        TextField(title, text: text, axis: .vertical).lineLimit(1...12)
    }

    private func optional(_ value: Binding<String?>) -> Binding<String> {
        Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    /// A list of strings edited as lines of text.
    private func lines(_ value: Binding<[String]>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue.joined(separator: "\n") },
            set: { value.wrappedValue = $0.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }
        )
    }
}

extension BlockDraft.Kind {
    var titleKey: LocalizedStringKey {
        switch self {
        case .heading: "Heading"
        case .paragraph: "Paragraph"
        case .list: "List"
        case .keyPoint: "Key point"
        case .quote: "Quote"
        case .timeline: "Timeline"
        case .stats: "Numbers"
        case .comparison: "Comparison"
        case .causeEffect: "Cause and effect"
        case .process: "Steps"
        case .definitions: "Terms"
        }
    }
}

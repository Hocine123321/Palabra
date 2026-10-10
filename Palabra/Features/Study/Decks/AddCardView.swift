import SwiftUI

/// Adds one card by hand to a user deck.
struct AddCardView: View {
    let deckID: UUID
    var onAdded: () -> Void = {}

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var front = ""
    @State private var back = ""
    @State private var duplicate = false

    private var canSave: Bool {
        !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Front", text: $front, axis: .vertical)
                        .lineLimit(1...4)
                        .accessibilityIdentifier("cardFrontField")
                    TextField("Back", text: $back, axis: .vertical)
                        .lineLimit(1...6)
                        .accessibilityIdentifier("cardBackField")
                } footer: {
                    if duplicate {
                        Text("This card is already in the deck.").foregroundStyle(Theme.error)
                    }
                }
                .themedSection()
            }
            .creamScreen()
            .navigationTitle("New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("saveCardButton")
                }
            }
        }
    }

    private func save() {
        let added = environment.cards.addCards(toDeck: deckID, drafts: [CardDraft(front: front, back: back)], now: Date())
        if added > 0 {
            onAdded()
            dismiss()
        } else {
            duplicate = true
        }
    }
}

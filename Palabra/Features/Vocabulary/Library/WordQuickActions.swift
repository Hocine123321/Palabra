import SwiftUI
import UIKit

/// The long-press menu shared by the grid tiles and the list rows: hear, copy, flag for review, open, delete.
private struct WordQuickActions: ViewModifier {
    let word: Word
    var onOpen: () -> Void
    var onDeleteRequest: () -> Void
    @Environment(AppEnvironment.self) private var environment
    @State private var flagged = 0

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button { onOpen() } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                Button {
                    WordQuickSpeaker.shared.hear(word, environment: environment)
                } label: {
                    Label("Hear Pronunciation", systemImage: "speaker.wave.2")
                }
                Button {
                    UIPasteboard.general.string = word.spanish
                } label: {
                    Label("Copy Word", systemImage: "doc.on.doc")
                }
                if !word.translation.isEmpty {
                    Button {
                        UIPasteboard.general.string = word.translation
                    } label: {
                        Label("Copy Meaning", systemImage: "text.quote")
                    }
                }
                Button {
                    if environment.flagForReview(word) { flagged += 1 }
                } label: {
                    Label("Flag for Review", systemImage: "flag")
                }
                Button(role: .destructive) { onDeleteRequest() } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .sensoryFeedback(.success, trigger: flagged)
    }
}

extension View {
    /// Adds the shared word menu (hear, copy, flag, open, delete) to a tile or row.
    func wordQuickActions(_ word: Word, onOpen: @escaping () -> Void, onDeleteRequest: @escaping () -> Void) -> some View {
        modifier(WordQuickActions(word: word, onOpen: onOpen, onDeleteRequest: onDeleteRequest))
    }
}

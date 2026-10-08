import SwiftUI

/// The Chat page: saved conversations, newest first, and a button to start a new one.
struct ChatListView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var rows: [Row] = []

    struct Row: Identifiable, Equatable {
        let id: UUID
        let title: String
        let preview: String
        let updatedAt: Date
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                EmptyStateView(
                    systemImage: "bubble.left.and.bubble.right",
                    title: "No chats yet",
                    message: "Start a chat to ask questions or have the assistant change your library."
                )
                .frame(maxHeight: .infinity)
                .background(Theme.background)
            } else {
                List {
                    Section {
                        ForEach(rows) { row in
                            NavigationLink(value: Router.Destination.chat(row.id)) {
                                rowView(row)
                            }
                            .accessibilityIdentifier("chatRow")
                        }
                        .onDelete(perform: delete)
                    }
                    .themedSection()
                }
                .creamScreen()
            }
        }
        .navigationTitle("Chat")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: newChat) { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New chat")
                    .accessibilityIdentifier("newChatButton")
            }
        }
        .onAppear(perform: reload)
    }

    private func rowView(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ChatTitleText(title: row.title)
                .font(Theme.Font.rowTitle)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            if !row.preview.isEmpty {
                Text(verbatim: row.preview)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            Text(row.updatedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private func reload() {
        rows = environment.chat.conversations().map { conversation in
            let last = conversation.turns.last { $0.status == .sent && (!$0.text.isEmpty || !$0.actions.isEmpty) }
            let preview = last.map { $0.text.isEmpty ? ($0.actions.first?.summary ?? "") : $0.text } ?? ""
            return Row(id: conversation.id, title: conversation.title, preview: String(preview.prefix(80)), updatedAt: conversation.updatedAt)
        }
    }

    private func newChat() {
        let conversation = environment.chat.create(title: ChatConversation.defaultTitle, wordID: nil, turns: [], now: Date())
        environment.router.path.append(.chat(conversation.id))
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets where rows.indices.contains(index) {
            environment.chat.delete(id: rows[index].id)
        }
        Motion.animate(Motion.standard) { reload() }
    }
}

/// A chat title: the placeholder is localized, anything else is the person's or the AI's text.
struct ChatTitleText: View {
    let title: String

    var body: some View {
        if title == ChatConversation.defaultTitle {
            Text("New chat")
        } else {
            Text(verbatim: title)
        }
    }
}

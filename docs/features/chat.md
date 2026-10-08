# Chat

The **Chat** page of the Spanish hub: a general assistant that answers like a chat app and can change things in the app. It replaces the old per-word chat sheet.

## Screens

- **Chat list** (`ChatListView`): saved conversations, newest first; New chat; swipe to delete.
- **Chat** (`ChatView`): messages, quiet "looked something up" chips for reads, confirmation cards for writes with **Apply** / **Not now**, input bar, starter chips on an empty chat.
- **Ask about this word** (word detail) opens a chat linked to that word, pushed above the word page (Back returns to the word). The first time, the word's old chat history is imported (`RootView.openChat`, the one place that knows `Word` and `Chat`). `Word.chatData` is left untouched.

## How the assistant acts

`ChatSession` (one per open conversation) runs a loop of at most 4 model calls per message:

1. The whole conversation is rendered as text (`ChatPrompts.transcript`, newest turns win within 24,000 characters) and sent through `AIClient.generateJSON` with the system instruction (`ChatPrompts.systemInstruction`: the registry manual for `.read` and `.write` capabilities, the reply protocol, the rules).
2. The reply is text, then optionally a line `---ACTIONS---` and a JSON array `[{"capability","args"}]` (≤ 5 calls, `ChatReplyParser`). A bad block gets one automatic retry with the problem appended, then falls back to the text alone.
3. **Reads** run at once and the loop continues with their results. **Writes** are saved as `pending` actions and the loop stops until the person taps Apply (run, then the model summarizes) or Not now (the model is told it was declined). Typing a new message instead counts as Not now.
4. Unknown capabilities and anything that is not `.read`/`.write` (`storage.*`, `ai.generate`) are recorded as failed and never run.

Every call goes through `CapabilityRegistry.call` like artifacts do; the chat's session has `artifactID == nil`. A write is never applied without the person's tap, so there is no grant sheet; the card is the consent. Pending writes survive relaunch (their arguments are stored).

## Capability packs added with the chat

| Name | Class | What |
|---|---|---|
| `words.add` | write | queue 1–20 words for AI generation (skips words already saved or queued); starts the queue |
| `words.place` | write | set category and/or tags of 1–50 words (names cleaned, merged onto known sections) |
| `study.decks` | read | decks with total/due/new counts |
| `study.addCards` | write | add 1–30 cards to a user deck by name, creating it when missing; never the Vocabulary deck; skips duplicates |

A capability's optional `describe` closure writes the confirmation line ("Add words: a, b"). Artifacts can request these capabilities too (writes need approval; specs can bind `study.decks`).

## Storage

`ChatConversation` (SwiftData, append-only property names): `id`, `title`, `wordID?`, `turnsData` (JSON `[ChatTurn]`, tolerant decoding), timestamps. Newest 200 turns, text ≤ 8,000, stored results ≤ 3,000 characters. `ChatTurn.actions` hold each call's state (`pending`, `applied`, `declined`, `failed`), its arguments and result.

## Structure

```
Core/Capabilities/        JSONValue, Capability, CapabilityRegistry, CodeFence (shared by Artifacts and Chat)
Features/Chat/
  Storage/       ChatConversation, ChatTurn, ChatAction, ChatRepository
  AI/            ChatPrompts, ChatReplyParser
  Conversation/  ChatSession (the loop)
  Library/       ChatListView, ChatView
```

## Testing

- `ChatReplyParserTests`, `ChatPromptsTests`, `ChatRepositoryTests`, `ChatSessionTests` (scripted model, real registry), `CapabilityPacksTests`.
- `StubAIClient.generateJSON` answers chat prompts when the system instruction contains `---ACTIONS---`: the last `USER:` block "add words" proposes `words.add` (alpha, beta), "list words" reads `library.words`, `fallo` fails, anything else echoes `Think of "…" this way.`; once results are in the transcript it answers "All done." / "Okay, I won't change anything." / "You have some words in your library.".
- `ChatUITests` and `SmokeUITests` cover the flows.

# Web companion, phase 4: changes from the web, the outbox, the review list

Status: built on `experimental`. Builds on [phases 2 and 3](2026-11-07-web-companion-phase2-3.md).

## What the person gets

On the Library tab there is an **Add words** box. It works with the phone away: the words wait under **Waiting for the phone**
and go out, in order, when the link is back. If the phone disagrees, the change moves to **Needs your review** with the reason in
plain words and **Try again** or **Drop**. Anything waiting can be cancelled.

## What can be changed from the web (and what cannot)

| Action | Waits offline? | Why |
|---|---|---|
| `words.add` | yes | the app already skips words it has |
| `words.place` (section, tags) | yes | refused with `conflict` if the word changed on the phone since the page saw it |
| `review.flag` | yes | repeating it is harmless |
| `ai.generate` | **no** | spends quota: only with a live link, answered or failed at once, never stored |
| deletes, `storage.*`, `study.addCards`, anything else | **no, refused** | not on the list |

The list lives in two places. **The phone is the one that matters** (`WebLinkDispatcher.writeAllowList`), because a page can
be tampered with. The page checks too (`QUEUEABLE`, `LIVE_ONLY`), including **again at send time**, so an altered stored queue
cannot make the page send `ai.generate` (a test caught that hole).

## Messages added

| Type | Payload | Reply |
|---|---|---|
| `write` | `{id, capability, args, base}` | `ack {result}` (plus `repeat: true` when it is a retry) or `reject {reason}` |
| `ai` | `{args}` for `ai.generate` | `ack {result}` or `reject {reason}` |

New reject reasons: `conflict`, `not-found`. Phone checks, in order: shape (id up to 80 characters), allow-list, the registry
calls it a write (AI: calls it `.ai`), a repeat of an action already run, the conflict check, then the call.

**Retry after a lost reply.** The page sends each action with an id. The phone remembers the last 200 ids and their results;
a repeat gets the first result and nothing runs twice. Only successes are remembered, so a refused action can be retried. This
memory is in RAM: after the app restarts, a retry is judged on its merits (adding words skips duplicates anyway).

**Conflict check for `words.place`.** There is no stored version on a word, and none was added (persisted names are frozen).
Instead `base` is a map from each touched word to a **placement token**: `category|tag1,tag2`, tags sorted by their UTF-8 bytes,
`\`, `|` and `,` escaped. It is plain text, not a hash, so two different placements can never share one. Swift
(`PlacementToken`) and JavaScript (`placementToken`) are pinned by the same vectors, including one where UTF-8 order and
UTF-16 order differ. If any word is stale or gone, the whole action is refused and nothing is half applied. "Try again" sends it
without a `base`, which means "do it anyway" and is the person's choice.

## Limits and decisions to review

- The page only offers **Add words** so far. `words.place` and `review.flag` are in the protocol, queue and phone, but there is no
  button for them yet; they arrive with the word detail screen in phase 5.
- **No AI button yet.** `callAiLive` and the phone side exist and are tested; the screens that use it (explain, chat) are phase 5.
- The queue is capped at 200 waiting actions.
- Queued changes follow the "Remember this computer" choice: with it off they are kept in memory only and lost when the tab closes.
  With it on they survive a reload. "Forget this computer" removes them.
- Order is kept strictly. If the phone does not answer, sending stops there and resumes later; a refusal moves that one aside and the
  next goes on.
- Nothing in Swift for phase 4 has been compiled or run yet.

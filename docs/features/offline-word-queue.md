# Offline word queue

Adding (or regenerating) a word while offline no longer dead-ends in an
error. The request is queued and generated automatically once the
connection comes back, so the person can keep typing in more words, close
the app, or do something else entirely.

## How it behaves

- **Detected upfront.** `AddWordFlow` checks connectivity before calling the
  AI at all, so there's no waiting for a timeout when you're clearly
  offline — it queues right away and shows a short "You're offline, queued"
  screen instead of the usual preview.
- **Also covers a mid-request drop.** If the connection was fine when you
  started but drops before the AI responds, the resilient client already
  waits a while and, if it gives up, that's treated the same as the upfront
  case: queued, not a dead-end error.
- **Visible in the library.** Every queued word shows as a row above your
  words (`QueuedWordsBanner`) — "Waiting for connection…", "Generating…",
  or, if something else went wrong, why, with a Retry button.
- **Drains automatically.** `WordQueueProcessor` works through the queue
  oldest-first, one at a time, quietly (no retry dialog interrupting what
  you're doing). It's nudged to check on app launch, on returning to the
  foreground, right after something is queued, and from a manual Retry.
- **Foreground only.** There's no background-execution hookup, so a queue
  left mid-flight when the app is backgrounded or killed just picks back up
  the next time the app is opened — including recovering an item that was
  mid-request when the app was killed, so it isn't stuck forever.
- **A setup problem doesn't retry forever.** A missing API key, no model
  selected, or a non-retryable AI error (an invalid key, a blocked prompt,
  ...) marks the item failed rather than looping — being back online
  wouldn't fix any of those anyway.
- **Survives a relaunch.** The queue is a SwiftData model (`WordQueueItem`),
  not in-memory state, so words typed in airplane mode on a flight are still
  there when you land.

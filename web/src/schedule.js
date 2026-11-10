// When to ask the Worker again. An incomplete copy usually means the phone is still sending, so look again soon (a few times).

export const NORMAL_MS = 60_000;
export const SOON_MS = 10_000;
export const MAX_SOON_RUNS = 6;

export function refreshDelay({ state, incompleteRuns }) {
  return state === "incomplete" && incompleteRuns < MAX_SOON_RUNS ? SOON_MS : NORMAL_MS;
}

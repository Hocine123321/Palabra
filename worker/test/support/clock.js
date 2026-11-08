/** A controllable clock in whole seconds. */
export function makeClock(start = 1_000_000) {
  let t = start;
  return {
    now: () => t,
    advance(seconds) {
      t += seconds;
    },
  };
}

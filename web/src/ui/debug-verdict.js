// Turns the page's state into one plain sentence for a beginner: how it is going, and the one thing to do next.
// Pure, so Node tests cover every case. Returns { tone: "ok" | "wait" | "bad", title, help } as translation keys.

export function verdict({ link, reason, failures = 0, online = true, secure = true } = {}) {
  if (!online) return { tone: "bad", title: "Your computer is offline", help: "Check this computer's internet connection." };
  if (link === "linked") return { tone: "ok", title: "Connected to your phone", help: "Everything is working." };
  if (link === "error") return { tone: "bad", title: "The phone no longer trusts this computer", help: "Press Forget this computer, then pair again." };
  if (reason === "relay" || reason === "relay-timeout") return { tone: "bad", title: "Cannot reach the relay", help: "Check the relay address, and that the relay is deployed." };
  if (reason === "phone-away") return { tone: "wait", title: "Waiting for your phone", help: "Open Palabra on the phone and keep it on screen." };
  if (link === "connecting") return { tone: "wait", title: "Connecting…", help: "This usually takes a few seconds." };
  if (failures >= 4) return { tone: "bad", title: "Your phone is not answering", help: "Keep Palabra open on the phone, then press Copy for support and send it to me." };
  if (link === "away" || link === "empty") return { tone: "wait", title: "Phone not reachable right now", help: "Open Palabra on the phone and keep it on screen." };
  return { tone: "wait", title: "Starting…", help: "One moment." };
}

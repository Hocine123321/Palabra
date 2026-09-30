# Self-healing AI calls, backup key and smart error reactions

## What changed
Failures used to be handled by each screen on its own, and background work (pronunciation, auto-organize) dropped errors silently. Now every AI call goes through one layer that reacts to each error differently.

| Error | Reaction |
|---|---|
| Offline | Waits for the connection to return. Does not use up retries. |
| Timeout, server error (5xx), cut-off or unreadable reply | Retries automatically, waiting 2s, 4s, 8s (configurable). |
| Rate limit (per minute) | Retries with the waits above; then switches to the backup key. |
| Daily quota used up | No waiting. Switches to the backup key at once, otherwise asks. |
| Invalid key / no permission | Switches to the backup key, otherwise asks (with a button to Settings). |
| Model gone | Asks, with a button to choose another model. |
| Blocked by safety filter | Stops and explains. Retrying cannot change it. |

## When automatic tries run out
A card asks: **Try Again**, **Retry with Longer Waits** (waits 4x longer, growing each time up to 5 minutes), or **Stop**. Options that cannot help are hidden (no "longer waits" for a spent quota).

## Backup key
Settings > Reliability > Backup API Key. Paste a key from a different Google account (keys from one account share one quota). The app uses it automatically when the main key keeps failing, and goes back to the main key as soon as it recovers.

## Nothing fails silently
Background tasks never pop up questions, but every failure is listed under Settings > Reliability > Recent Problems, and a status pill shows retries in progress.

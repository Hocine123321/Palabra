// The web app: pair once, then show the words from the local copy and keep it fresh. Not covered by the Node tests (it
// needs a real DOM and IndexedDB); everything it calls is.
import { OfflineError, createApi } from "./api.js";
import { importDataKey } from "./crypto.js";
import { openLocalDb } from "./localdb.js";
import { createPairing } from "./pairing.js";
import { dirFor, pickLang } from "./strings.js";
import { refreshDelay } from "./schedule.js";
import { AuthRevoked, RollbackDetected, describeCopy, pullOnce } from "./sync.js";
import { confirmScreen, mount, pairScreen, removedScreen, wordsScreen } from "./view.js";

const root = document.getElementById("app");
const lang = pickLang(navigator.language);
document.documentElement.lang = lang;
document.documentElement.dir = dirFor(lang);

const api = createApi(location.origin);
const POLL_MS = 1500;

let db;
let screenToken = 0; // a newer screen invalidates timers of the older one

function render(tree) {
  mount(root, tree);
}

async function main() {
  db = await openLocalDb();
  const creds = await db.getCredentials();
  if (creds) showWords();
  else showPairing();
}

// MARK: Pairing

async function showPairing() {
  const token = ++screenToken;
  const pairing = createPairing({ api, origin: location.origin });
  let confirmed = false;
  let code = null;

  const restart = () => showPairing();
  const cancel = async () => {
    screenToken++;
    await pairing.cancel().catch(() => {});
    showPairing();
  };
  const showStatus = (status, link = "") => render(pairScreen({ link, status, lang, onCancel: cancel, onRestart: restart }));
  const showConfirm = () => render(confirmScreen({ code, lang, waiting: confirmed, onMatch: () => { confirmed = true; showConfirm(); }, onCancel: cancel }));

  let link;
  try {
    ({ link } = await pairing.start());
  } catch {
    showStatus("error");
    return;
  }
  showStatus("waiting", link);

  const poll = async () => {
    if (token !== screenToken) return;
    let result;
    try {
      result = await pairing.poll();
    } catch (e) {
      if (e instanceof OfflineError) return setTimeout(poll, POLL_MS);
      return showStatus("error");
    }
    if (token !== screenToken) return;
    if (result.state === "expired" || result.state === "cancelled") return showStatus(result.state);
    if ((result.state === "joined" || result.state === "replied") && result.code !== code) {
      code = result.code;
      showConfirm();
    }
    if (result.state === "replied" && confirmed) {
      try {
        const got = await pairing.accept();
        await db.setCredentials({ mirrorId: got.mirrorId, deviceId: got.deviceId, deviceToken: got.deviceToken, keys: await importDataKey(got.dataKey) });
        screenToken++;
        return showWords();
      } catch {
        return showStatus("error");
      }
    }
    setTimeout(poll, POLL_MS);
  };
  setTimeout(poll, POLL_MS);
}

// MARK: Words

async function showWords() {
  const token = ++screenToken;
  let syncedAt = null;
  let status = null;
  let rollback = false; // the server sent older data than the saved copy: shown as a banner until a pull succeeds
  let copy = { state: "unverified", pushedAt: null };
  let incompleteRuns = 0; // consecutive pulls that ended incomplete: look again soon, a few times

  const draw = async () => {
    copy = await describeCopy(db);
    const rows = await db.itemsByKind("word");
    const words = rows
      .map((r) => ({ id: r.id, ...r.d }))
      .sort((a, b) => Date.parse(b.createdAt ?? "") - Date.parse(a.createdAt ?? "") || 0);
    render(wordsScreen({ words, syncedAt, status, freshness: { state: copy.state, pushedAt: copy.pushedAt, rollback }, lang, onRefresh: refresh }));
  };

  async function refresh() {
    if (token !== screenToken) return;
    status = "syncing";
    await draw();
    try {
      const result = await pullOnce({ api, db });
      syncedAt = Date.now();
      status = null;
      rollback = false;
      incompleteRuns = result.check.state === "incomplete" ? incompleteRuns + 1 : 0;
    } catch (e) {
      if (e instanceof RollbackDetected) {
        rollback = true;
        status = null;
        if (token === screenToken) await draw();
        return;
      }
      if (e instanceof AuthRevoked) {
        screenToken++;
        await db.clearAll();
        render(removedScreen({ lang, onPairAgain: showPairing }));
        return;
      }
      status = e instanceof OfflineError ? "offline" : "error";
    }
    if (token === screenToken) await draw();
  }

  await draw(); // the saved copy first, so the list is there before the network answers
  const loop = async () => {
    await refresh();
    if (token === screenToken) setTimeout(loop, refreshDelay({ state: copy.state, incompleteRuns }));
  };
  loop();
  window.addEventListener("online", () => token === screenToken && refresh());
}

main().catch(() => render(pairScreen({ link: "", status: "error", lang, onCancel: () => {}, onRestart: () => location.reload() })));

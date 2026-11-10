// Palabra Mirroring service worker: keeps the shell so the page opens offline. A classic script (no imports).
// scripts/build.mjs fills in the two constants below: the version (a hash of the shell files) and the list of shell paths.
// It never touches /api/*, other methods or other origins: the data lives in IndexedDB, not here.
const VERSION = "__VERSION__";
const SHELL = __SHELL__;
const PREFIX = "palabra-shell-";
const CACHE = PREFIX + VERSION;

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.addAll(SHELL))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((names) => Promise.all(names.filter((name) => name.startsWith(PREFIX) && name !== CACHE).map((name) => caches.delete(name))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin || url.pathname.startsWith("/api/")) return;
  event.respondWith(request.mode === "navigate" ? navigate(request, url) : fromCacheOrNetwork(request));
});

/** Network first, so a new deploy shows up; the cached shell when offline. Only a good answer for "/" refreshes the shell. */
async function navigate(request, url) {
  try {
    const response = await fetch(request);
    if (response.ok && url.pathname === "/") {
      const cache = await caches.open(CACHE);
      await cache.put("/", response.clone());
    }
    return response;
  } catch (error) {
    const shell = await caches.match("/");
    if (shell) return shell;
    throw error;
  }
}

async function fromCacheOrNetwork(request) {
  const hit = await caches.match(request);
  return hit || fetch(request);
}

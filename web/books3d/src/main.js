import { App } from './app.js';

const canvas = document.getElementById('stage');
const native = !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.palabra);
const post = (m) => {
  if (native) window.webkit.messageHandlers.palabra.postMessage(m);
  else if (window.__palabraHost) window.__palabraHost(m);
};
const app = new App(canvas, post);
window.palabra = {
  app,
  load: (payload, options) => app.load(payload, options || {}),
  command: (c) => app.command(c),
  snapshot: () => app.snapshot(),
};
window.addEventListener('error', (e) => post({ type: 'error', message: String(e.message || e) }));
window.addEventListener('unhandledrejection', (e) => post({ type: 'error', message: String(e.reason && e.reason.message || e.reason) }));
if (!native) import('./hud.js').then((m) => m.mountHud(app)).catch(() => {});

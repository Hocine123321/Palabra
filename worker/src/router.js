import { LIMITS } from "./limits.js";
import { isB64url, parseBearer, sha256Hex } from "./auth.js";

const HEADERS = { "Content-Type": "application/json", "Cache-Control": "no-store" };
const ID = (s) => isB64url(s, 22, 22);
const DEVICE_ID = (s) => isB64url(s, 1, 64);
const DIGITS = /^\d{1,15}$/;

function json(status, body, extra = {}) {
  return new Response(JSON.stringify(body), { status, headers: { ...HEADERS, ...extra } });
}
const error = (status, code, extra) => json(status, { error: code }, extra);

/** A store or backend result -> a Response. Success bodies drop `ok`; `pick` reshapes them. */
function respond(result, successStatus = 200, pick = (rest) => rest) {
  if (!result.ok) {
    const headers = result.retryAfter ? { "Retry-After": String(result.retryAfter) } : {};
    return error(result.status, result.error, headers);
  }
  const { ok, ...rest } = result;
  return json(successStatus, pick(rest));
}

/** Reads the body once, as text, enforcing the byte cap. Returns {text} or {response}. */
async function readText(request, cap) {
  const declared = request.headers.get("content-length");
  if (declared !== null && DIGITS.test(declared) && Number(declared) > cap) return { response: error(413, "too_large") };
  if (!request.body) return { text: "" };
  // Stream it, so a body without a length is dropped as soon as it passes the cap instead of being buffered whole.
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > cap) {
      await reader.cancel().catch(() => {});
      return { response: error(413, "too_large") };
    }
    chunks.push(value);
  }
  const all = new Uint8Array(size);
  let at = 0;
  for (const chunk of chunks) {
    all.set(chunk, at);
    at += chunk.byteLength;
  }
  return { text: new TextDecoder().decode(all) };
}

async function readJson(request, cap) {
  const body = await readText(request, cap);
  if (body.response) return body;
  let value;
  try {
    value = JSON.parse(body.text);
  } catch {
    return { response: error(400, "bad_request") };
  }
  if (value === null || typeof value !== "object" || Array.isArray(value)) return { response: error(400, "bad_request") };
  return { value };
}

/**
 * The whole REST API as one function over a backend (see Task 5 interface).
 * Never throws: anything unexpected is a 500 with no detail.
 */
export async function handleApi(request, backend, opts = {}) {
  const limits = { ...LIMITS, ...(opts.limits ?? {}) };
  try {
    const url = new URL(request.url);
    const parts = url.pathname.split("/").filter((p, i) => i === 0 || p !== "");
    // ["", "api", ...]
    if (parts[0] !== "" || parts[1] !== "api") return error(404, "not_found");
    const route = ROUTES.find((r) => r.match(parts.slice(2)));
    if (!route) return error(404, "not_found");
    const handler = Object.hasOwn(route.methods, request.method) ? route.methods[request.method] : null;
    if (!handler) return error(405, "method_not_allowed", { Allow: Object.keys(route.methods).join(", ") });
    const ctx = { request, backend, limits, url, args: route.match(parts.slice(2)) };
    return await handler(ctx);
  } catch {
    return error(500, "internal");
  }
}

/** IPv4 as is; IPv6 as its /64 (one household or server owns the whole prefix, so rotating inside it must not evade a limit). */
function addressKey(ip) {
  if (!ip.includes(":")) return ip;
  const [head, tail] = ip.split("::");
  const front = head ? head.split(":") : [];
  const back = tail ? tail.split(":") : [];
  const fill = tail === undefined ? [] : Array(Math.max(0, 8 - front.length - back.length)).fill("0");
  return [...front, ...fill, ...back].slice(0, 4).map((g) => g.toLowerCase().replace(/^0+(?=.)/, "")).join(":");
}

async function ipRate(ctx, name) {
  const ip = addressKey(ctx.request.headers.get("CF-Connecting-IP") ?? "unknown");
  const [limit, windowSec] = ctx.limits.rates[name];
  return ctx.backend.gate.rate(`${name}:${await sha256Hex(ip)}`, limit, windowSec);
}

/** Auth header and the mirror store for /api/m/<id>/...; or a refusal response. */
function mirrorOf(ctx) {
  const [mirrorId] = ctx.args;
  const bearer = ctx.request.headers.get("Authorization");
  // Refuse before touching the backend: nothing is created for a request that cannot be authorised.
  if (!parseBearer(bearer)) return { response: error(401, "unauthorized") };
  const mirror = ctx.backend.mirror(mirrorId);
  if (!mirror) return { response: error(404, "not_found") };
  return { mirror, bearer, mirrorId };
}

const pairId = (ctx) => ctx.args[0];

const ROUTES = [
  {
    match: (p) => (p.length === 1 && p[0] === "mirrors" ? [] : null),
    methods: {
      POST: async (ctx) => {
        const rate = await ipRate(ctx, "mirrorsCreate");
        if (!rate.ok) return respond(rate);
        const [dayLimit, dayWindow] = ctx.limits.rates.mirrorsDay;
        const day = await ctx.backend.gate.rate("mirrorsDay", dayLimit, dayWindow);
        if (!day.ok) return respond(day);
        const body = await readJson(ctx.request, ctx.limits.bodyBytes);
        if (body.response) return body.response;
        const { deviceId, ownerTokenHash } = body.value;
        const made = await ctx.backend.createMirror({ deviceId, ownerTokenHash });
        return respond(made, 201, (rest) => ({ mirrorId: rest.mirrorId, deviceId }));
      },
    },
  },
  {
    match: (p) => (p.length === 2 && p[0] === "pair" && p[1] === "start" ? [] : null),
    methods: {
      POST: async (ctx) => {
        const rate = await ipRate(ctx, "pairStart");
        if (!rate.ok) return respond(rate);
        const cap = await readText(ctx.request, ctx.limits.bodyBytes);
        if (cap.response) return cap.response;
        return respond(await ctx.backend.gate.startPairing(), 201);
      },
    },
  },
  {
    match: (p) => (p.length === 2 && p[0] === "pair" && ID(p[1]) ? [p[1]] : null),
    methods: {
      GET: async (ctx) => {
        const rate = await ipRate(ctx, "pairPoll");
        if (!rate.ok) return respond(rate);
        return respond(await ctx.backend.gate.getPairing(pairId(ctx)));
      },
    },
  },
  {
    match: (p) => (p.length === 3 && p[0] === "pair" && ID(p[1]) && p[2] === "join" ? [p[1]] : null),
    methods: {
      POST: async (ctx) => {
        const rate = await ipRate(ctx, "pairJoin");
        if (!rate.ok) return respond(rate);
        const body = await readJson(ctx.request, ctx.limits.bodyBytes);
        if (body.response) return body.response;
        return respond(await ctx.backend.gate.joinPairing(pairId(ctx), body.value.phonePub), 200, () => ({}));
      },
    },
  },
  {
    match: (p) => (p.length === 3 && p[0] === "pair" && ID(p[1]) && p[2] === "reply" ? [p[1]] : null),
    methods: {
      POST: async (ctx) => {
        const body = await readJson(ctx.request, ctx.limits.bodyBytes);
        if (body.response) return body.response;
        return respond(await ctx.backend.gate.replyPairing(pairId(ctx), body.value.sealed), 200, () => ({}));
      },
    },
  },
  {
    match: (p) => (p.length === 3 && p[0] === "pair" && ID(p[1]) && p[2] === "cancel" ? [p[1]] : null),
    methods: {
      POST: async (ctx) => {
        const cap = await readText(ctx.request, ctx.limits.bodyBytes);
        if (cap.response) return cap.response;
        return respond(await ctx.backend.gate.cancelPairing(pairId(ctx)), 200, () => ({}));
      },
    },
  },
  {
    match: (p) => (p.length === 3 && p[0] === "m" && ID(p[1]) && p[2] === "devices" ? [p[1]] : null),
    methods: {
      POST: async (ctx) => {
        const m = mirrorOf(ctx);
        if (m.response) return m.response;
        const body = await readJson(ctx.request, ctx.limits.bodyBytes);
        if (body.response) return body.response;
        const { deviceId, tokenHash } = body.value;
        return respond(await m.mirror.addDevice(m.bearer, { deviceId, tokenHash }), 201, () => ({}));
      },
      GET: async (ctx) => {
        const m = mirrorOf(ctx);
        if (m.response) return m.response;
        return respond(await m.mirror.listDevices(m.bearer));
      },
    },
  },
  {
    match: (p) => (p.length === 4 && p[0] === "m" && ID(p[1]) && p[2] === "devices" && DEVICE_ID(p[3]) ? [p[1], p[3]] : null),
    methods: {
      DELETE: async (ctx) => {
        const m = mirrorOf(ctx);
        if (m.response) return m.response;
        return respond(await m.mirror.removeDevice(m.bearer, ctx.args[1]), 200, () => ({}));
      },
    },
  },
  {
    match: (p) => (p.length === 3 && p[0] === "m" && ID(p[1]) && p[2] === "items" ? [p[1]] : null),
    methods: {
      PUT: async (ctx) => {
        const m = mirrorOf(ctx);
        if (m.response) return m.response;
        const body = await readJson(ctx.request, ctx.limits.bodyBytes);
        if (body.response) return body.response;
        return respond(await m.mirror.putItems(m.bearer, body.value.items));
      },
      GET: async (ctx) => {
        const m = mirrorOf(ctx);
        if (m.response) return m.response;
        const since = ctx.url.searchParams.get("since") ?? "0";
        const limit = ctx.url.searchParams.get("limit") ?? String(ctx.limits.listMax);
        if (!DIGITS.test(since) || !DIGITS.test(limit)) return error(400, "bad_request");
        return respond(await m.mirror.listItems(m.bearer, Number(since), Number(limit)));
      },
    },
  },
  {
    match: (p) => (p.length === 3 && p[0] === "m" && ID(p[1]) && p[2] === "state" ? [p[1]] : null),
    methods: {
      GET: async (ctx) => {
        const m = mirrorOf(ctx);
        if (m.response) return m.response;
        return respond(await m.mirror.state(m.bearer));
      },
    },
  },
  {
    match: (p) => (p.length === 3 && p[0] === "m" && ID(p[1]) && p[2] === "rotate" ? [p[1]] : null),
    methods: {
      POST: async (ctx) => {
        const m = mirrorOf(ctx);
        if (m.response) return m.response;
        const body = await readJson(ctx.request, ctx.limits.rotateBodyBytes);
        if (body.response) return body.response;
        return respond(await m.mirror.rotate(m.bearer, body.value));
      },
    },
  },
  {
    match: (p) => (p.length === 3 && p[0] === "m" && ID(p[1]) && p[2] === "rotation" ? [p[1]] : null),
    methods: {
      GET: async (ctx) => {
        const m = mirrorOf(ctx);
        if (m.response) return m.response;
        return respond(await m.mirror.rotation(m.bearer));
      },
    },
  },
];

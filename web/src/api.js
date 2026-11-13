// The Worker's REST API (docs/features/mirroring.md). Same origin only; no secrets in URLs or bodies.

export class ApiError extends Error {
  constructor(status, code) {
    super(`request failed (${status} ${code})`);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
  }
}

export class OfflineError extends Error {
  constructor() {
    super("offline");
    this.name = "OfflineError";
  }
}

export function createApi(origin, fetchImpl = (...args) => globalThis.fetch(...args)) {
  async function request(method, path, { bearer, body } = {}) {
    const headers = {};
    if (bearer) headers.Authorization = `Bearer ${bearer}`;
    if (body !== undefined) headers["Content-Type"] = "application/json";
    let res;
    try {
      res = await fetchImpl(origin + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), cache: "no-store" });
    } catch {
      throw new OfflineError();
    }
    let json = null;
    try {
      json = await res.json();
    } catch {
      /* not JSON */
    }
    if (!res.ok) throw new ApiError(res.status, typeof json?.error === "string" ? json.error : "unknown");
    return json ?? {};
  }

  return {
    pairStart: () => request("POST", "/api/pair/start"),
    pairGet: (pairId) => request("GET", `/api/pair/${pairId}`),
    pairCancel: async (pairId) => {
      await request("POST", `/api/pair/${pairId}/cancel`);
    },
    state: (mirrorId, bearer) => request("GET", `/api/m/${mirrorId}/state`, { bearer }),
    /** The caller's sealed key for the current epoch (404 when there is none). */
    rotation: (mirrorId, bearer) => request("GET", `/api/m/${mirrorId}/rotation`, { bearer }),
    items: (mirrorId, bearer, since, limit = 200) => request("GET", `/api/m/${mirrorId}/items?since=${since}&limit=${limit}`, { bearer }),
  };
}

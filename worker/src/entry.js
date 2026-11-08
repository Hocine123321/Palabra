import { handleApi } from "./router.js";

/** /api and /api/... go to the router; everything else is the static web app. */
export function makeFetch(getBackend) {
  return async function fetch(request, env) {
    const { pathname } = new URL(request.url);
    if (pathname === "/api" || pathname.startsWith("/api/")) {
      return handleApi(request, getBackend(env));
    }
    return env.ASSETS.fetch(request);
  };
}

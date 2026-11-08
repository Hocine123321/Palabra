import { doBackend, Gate, Mirror } from "./do.js";
import { makeFetch } from "./entry.js";

export { Gate, Mirror };
export default { fetch: makeFetch(doBackend) };

// Writes the shared protocol vectors with Node's crypto module (deliberately not src/crypto.js).
// Run: node web/scripts/make-vectors.mjs   Checked independently by verify-vectors.py.
import { createCipheriv, createECDH, createHash, createHmac, hkdfSync } from "node:crypto";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const OUT = fileURLToPath(new URL("../../PalabraTests/Mirroring/Fixtures/mirror-vectors.json", import.meta.url));
const hex = (b) => Buffer.from(b).toString("hex");
const b64u = (b) => Buffer.from(b).toString("base64url");
const fill = (n, v) => Buffer.alloc(n, v);
const hkdf = (ikm, salt, info) => Buffer.from(hkdfSync("sha256", ikm, salt, info, 32));

function seal(key, iv, aad, plaintext) {
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  cipher.setAAD(Buffer.from(aad, "utf8"));
  const ct = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return Buffer.concat([iv, ct, cipher.getAuthTag()]);
}

const dataKey = Buffer.from(Array.from({ length: 32 }, (_, i) => i));
const kAes = hkdf(dataKey, Buffer.alloc(0), "palabra-mirror-aes-v1");
const kId = hkdf(dataKey, Buffer.alloc(0), "palabra-mirror-id-key-v1");

const kind = "word";
const recordId = "6F9619FF-8B86-D011-B42D-00C04FC964FF";
const itemId = b64u(createHmac("sha256", kId).update(`${kind}|${recordId}`).digest().subarray(0, 16));

const itemPlain = JSON.stringify({ v: 1, k: kind, r: recordId, h: "abc123", g: 7, d: { spanish: "mañana", translation: "tomorrow", tags: ["tiempo"] } });
const itemSealed = seal(kAes, fill(12, 0x10), `palabra-mirror-item-v1|${itemId}`, Buffer.from(itemPlain, "utf8"));

const browser = createECDH("prime256v1");
browser.setPrivateKey(fill(32, 0x11));
const phone = createECDH("prime256v1");
phone.setPrivateKey(fill(32, 0x22));
const browserPub = browser.getPublicKey();
const phonePub = phone.getPublicKey();
const nonce = fill(16, 0x33);
const shared = browser.computeSecret(phonePub);
const kPair = hkdf(shared, nonce, "palabra-mirror-pair-v1");
const digest = createHash("sha256").update(Buffer.concat([browserPub, phonePub, nonce])).digest();
const matchCode = String(digest.readUInt32BE(0) % 10000).padStart(4, "0");

const pairId = b64u(fill(16, 0x44));
const wrapPlain = JSON.stringify({ v: 1, mirrorId: "MIRRORID", deviceId: "DEVICEID", deviceToken: "TOKEN", dataKey: b64u(dataKey) });
const wrapSealed = seal(kPair, fill(12, 0x55), `palabra-mirror-wrap-v1|${pairId}`, Buffer.from(wrapPlain, "utf8"));

// Manifest: ids in insertion order that differs from code-point order (`-` < digits < upper < `_` < lower).
const manifestIds = ["bQ_x9AbCdEfGhIjKlMnOp", "Zz9-aAbBcCdDeEfFgGhHiI", "_lead0AAAAAAAAAAAAAAAA", "-dash1AAAAAAAAAAAAAAAA", "a0b1c2d3e4f5g6h7i8j9kL"];
const sha256Hex = (text) => createHash("sha256").update(Buffer.from(text, "utf8")).digest("hex");
const manifestVector = { ids: manifestIds, idsHashHex: sha256Hex([...manifestIds].sort().join("\n")) };
const emptyVector = { idsHashHex: sha256Hex("") };

writeFileSync(
  OUT,
  JSON.stringify(
    {
      dataKeyHex: hex(dataKey),
      id: { kind, recordId, expected: itemId },
      item: { plaintextUtf8: itemPlain, ivHex: hex(fill(12, 0x10)), expectedSealed: b64u(itemSealed) },
      pair: {
        browserPrivHex: hex(fill(32, 0x11)),
        phonePrivHex: hex(fill(32, 0x22)),
        browserPubHex: hex(browserPub),
        phonePubHex: hex(phonePub),
        nonceHex: hex(nonce),
        pairId,
        kPairHex: hex(kPair),
        matchCode,
      },
      wrap: { plaintextUtf8: wrapPlain, ivHex: hex(fill(12, 0x55)), expectedSealed: b64u(wrapSealed) },
      manifest: manifestVector,
      empty: emptyVector,
    },
    null,
    2,
  ) + "\n",
);
console.log("wrote", OUT);

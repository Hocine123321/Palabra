"""Recomputes every expected value in mirror-vectors.json with the Python `cryptography` package.
The independent cross-check of make-vectors.mjs. Exits non-zero on any mismatch."""
import base64, hashlib, hmac, json, os, sys
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

path = os.path.join(os.path.dirname(__file__), "..", "..", "PalabraTests", "Mirroring", "Fixtures", "mirror-vectors.json")
v = json.load(open(path))
b64u = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
unb64u = lambda s: base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))
hkdf = lambda ikm, salt, info: HKDF(algorithm=hashes.SHA256(), length=32, salt=salt, info=info).derive(ikm)
failures = []

def check(name, got, want):
    if got != want:
        failures.append(name)
        print("MISMATCH", name, got, want)

data_key = bytes.fromhex(v["dataKeyHex"])
k_aes = hkdf(data_key, None, b"palabra-mirror-aes-v1")
k_id = hkdf(data_key, None, b"palabra-mirror-id-key-v1")
item_id = b64u(hmac.new(k_id, f'{v["id"]["kind"]}|{v["id"]["recordId"]}'.encode(), hashlib.sha256).digest()[:16])
check("item id", item_id, v["id"]["expected"])

iv = bytes.fromhex(v["item"]["ivHex"])
sealed = iv + AESGCM(k_aes).encrypt(iv, v["item"]["plaintextUtf8"].encode(), f"palabra-mirror-item-v1|{item_id}".encode())
check("sealed item", b64u(sealed), v["item"]["expectedSealed"])

p = v["pair"]
browser = ec.derive_private_key(int(p["browserPrivHex"], 16), ec.SECP256R1())
phone = ec.derive_private_key(int(p["phonePrivHex"], 16), ec.SECP256R1())
raw = lambda k: k.public_key().public_bytes(Encoding.X962, PublicFormat.UncompressedPoint)
check("browser pub", raw(browser).hex(), p["browserPubHex"])
check("phone pub", raw(phone).hex(), p["phonePubHex"])
nonce = bytes.fromhex(p["nonceHex"])
shared = browser.exchange(ec.ECDH(), phone.public_key())
check("shared symmetric", shared, phone.exchange(ec.ECDH(), browser.public_key()))
k_pair = hkdf(shared, nonce, b"palabra-mirror-pair-v1")
check("kPair", k_pair.hex(), p["kPairHex"])
digest = hashlib.sha256(bytes.fromhex(p["browserPubHex"]) + bytes.fromhex(p["phonePubHex"]) + nonce).digest()
check("match code", str(int.from_bytes(digest[:4], "big") % 10000).zfill(4), p["matchCode"])

w = v["wrap"]
wiv = bytes.fromhex(w["ivHex"])
wsealed = wiv + AESGCM(k_pair).encrypt(wiv, w["plaintextUtf8"].encode(), f'palabra-mirror-wrap-v1|{p["pairId"]}'.encode())
check("sealed wrap", b64u(wsealed), w["expectedSealed"])

ids = sorted(v["manifest"]["ids"])
check("manifest idsHash", hashlib.sha256("\n".join(ids).encode()).hexdigest(), v["manifest"]["idsHashHex"])
check("manifest ids are out of order in the file", v["manifest"]["ids"] != ids, True)
check("empty idsHash", hashlib.sha256(b"").hexdigest(), v["empty"]["idsHashHex"])

if failures:
    sys.exit(1)
print("OK: vectors verified independently")

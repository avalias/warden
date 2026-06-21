#!/usr/bin/env python3
"""
WARDEN — off-chain ledger hash-chain verifier.

The L4 ledger is tamper-evident: each entry stores
    entry_digest = keccak256(prev_entry_digest || seq || ts_ms || risk_bps ||
                             accepted || fault || trade_digest)
and the chain head advances on every record. This script re-derives the entire
chain from the on-chain `Recorded` events ALONE and confirms that every entry's
digest is exactly what the contract committed — so a forged, dropped, or
reordered entry is detectable by anyone, with no trust in the operator.

Usage:
    python scripts/verify_ledger.py                 # uses warden.config.json (package + vault)
    python scripts/verify_ledger.py --selftest      # check the keccak256 implementation only
    python scripts/verify_ledger.py --package 0x.. --vault 0x..

No third-party dependencies: keccak256 is implemented inline and self-tested.
"""
import argparse, json, sys, urllib.request

RPC = "https://fullnode.testnet.sui.io:443"

# ---- keccak256 (pre-NIST padding), pure python -------------------------------
_RC = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
]
_ROT = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61],
        [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]]
_MASK = (1 << 64) - 1


def _rol(x, n):
    return ((x << n) | (x >> (64 - n))) & _MASK


def keccak256(data: bytes) -> bytes:
    rate = 136  # bytes (1088 bits) for keccak-256
    m = bytearray(data)
    m.append(0x01)                       # keccak padding (NOT 0x06 SHA3)
    while len(m) % rate != 0:
        m.append(0x00)
    m[-1] |= 0x80
    S = [[0] * 5 for _ in range(5)]
    for off in range(0, len(m), rate):
        for i in range(rate // 8):
            S[i % 5][i // 5] ^= int.from_bytes(m[off + i * 8: off + i * 8 + 8], "little")
        for rnd in range(24):
            C = [S[x][0] ^ S[x][1] ^ S[x][2] ^ S[x][3] ^ S[x][4] for x in range(5)]
            D = [C[(x - 1) % 5] ^ _rol(C[(x + 1) % 5], 1) for x in range(5)]
            for x in range(5):
                for y in range(5):
                    S[x][y] ^= D[x]
            B = [[0] * 5 for _ in range(5)]
            for x in range(5):
                for y in range(5):
                    B[y][(2 * x + 3 * y) % 5] = _rol(S[x][y], _ROT[x][y])
            for x in range(5):
                for y in range(5):
                    S[x][y] = B[x][y] ^ ((~B[(x + 1) % 5][y]) & B[(x + 2) % 5][y])
            S[0][0] ^= _RC[rnd]
    out = bytearray()
    for i in range(4):
        out += S[i % 5][i // 5].to_bytes(8, "little")
    return bytes(out)


def _selftest():
    vectors = {
        b"": "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
        b"abc": "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45",
    }
    ok = True
    for msg, want in vectors.items():
        got = keccak256(msg).hex()
        flag = "OK" if got == want else "FAIL"
        if got != want:
            ok = False
        print(f"  keccak256({msg!r:12}) = {got}  [{flag}]")
    return ok


# ---- RPC + parsing -----------------------------------------------------------
def rpc(method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(RPC, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=25) as r:
        return json.load(r)["result"]


def to_bytes(v):
    """A Move vector<u8> in parsedJson may arrive as a list of ints, a 0x-hex
    string, or base64. Normalise to bytes."""
    if isinstance(v, list):
        return bytes(v)
    if isinstance(v, str):
        if v.startswith("0x"):
            return bytes.fromhex(v[2:])
        try:
            return bytes.fromhex(v)
        except ValueError:
            import base64
            return base64.b64decode(v)
    raise TypeError(f"cannot decode vector<u8>: {v!r}")


def fetch_recorded(package, vault):
    evs, cursor = [], None
    etype = f"{package}::ledger::Recorded"
    while True:
        page = rpc("suix_queryEvents", [{"MoveEventType": etype}, cursor, 50, False])
        for e in page.get("data", []):
            f = e["parsedJson"]
            if vault and f.get("vault") != vault:
                continue
            evs.append(f)
        if not page.get("hasNextPage"):
            break
        cursor = page.get("nextCursor")
    evs.sort(key=lambda f: int(f["seq"]))
    return evs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="warden.config.json")
    ap.add_argument("--package")
    ap.add_argument("--vault")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    print("keccak256 self-test:")
    if not _selftest():
        sys.exit("keccak256 implementation is broken — aborting.")
    if args.selftest:
        print("self-test passed."); return

    package, vault = args.package, args.vault
    if not (package and vault):
        try:
            cfg = json.load(open(args.config))
            package = package or cfg["package"]
            vault = vault or cfg["vault"]
        except Exception as e:
            sys.exit(f"need --package and --vault (or a readable {args.config}): {e}")

    print(f"\nverifying ledger hash-chain for vault {vault[:10]}... on package {package[:10]}...")
    entries = fetch_recorded(package, vault)
    if not entries:
        sys.exit("no Recorded events found for that vault.")

    prev = b""
    ok = True
    for f in entries:
        seq = int(f["seq"]); ts = int(f["ts_ms"]); risk = int(f["risk_bps"])
        accepted = bool(f["accepted"]); fault = int(f["fault"])
        td = to_bytes(f["trade_digest"]); claimed = to_bytes(f["entry_digest"])
        chain = (prev + seq.to_bytes(8, "little") + ts.to_bytes(8, "little")
                 + risk.to_bytes(8, "little") + (b"\x01" if accepted else b"\x00")
                 + bytes([fault]) + td)
        computed = keccak256(chain)
        match = computed == claimed
        ok = ok and match
        print(f"  seq {seq}: accepted={accepted} risk={risk}bps fault={fault} "
              f"entry={computed.hex()[:16]}...  [{'OK' if match else 'MISMATCH'}]")
        prev = computed

    print("\n" + ("CHAIN INTACT (PASS) - every entry re-derives exactly; the ledger is tamper-evident."
                  if ok else "CHAIN BROKEN (FAIL) - an entry does not match its committed digest."))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()

"""
warden — a tiny, dependency-free Python client for the WARDEN autonomous-agent
custody package on Sui. The sibling of the TypeScript SDK, in the same spirit as
this repo's verify_*.py: pure stdlib (urllib + json), no install required.

Two halves:
  * Readers pull the live, on-chain truth from a fullnode -- vault NAV
    (idle + deployed), the ledger's keccak hash-chain head, the market feed and
    whether it is stale, and the verifiable trade track record (accepted AND
    rejected). No trust in any server.
  * Command builders return the exact `sui client call ...` argv for each entry
    point. The SDK never holds keys or signs -- you run the command with your own
    CLI keypair / wallet. Custody stays where it belongs.

The deployed package is immutable, so this is a thin, stable shim over a fixed ABI.

    from warden import WardenClient, load_addresses
    w = WardenClient(load_addresses())
    print(w.get_vault_state())            # live NAV, frozen, ...
    print(w.feed_update_cmd(1_000_000, 1_000))   # argv you sign + run
"""
import json
import base64
import os
import urllib.request

TESTNET_RPC = "https://fullnode.testnet.sui.io:443"
CLOCK_ID = "0x6"
GAS_BUDGET = "60000000"

# field name -> config key, so readers stay declarative
_ADDRESS_KEYS = (
    "package", "vault", "policy", "gen_registry",
    "critic_registry", "critic_cap", "ledger", "feed",
)


def load_addresses(path=None):
    """Load on-chain object ids from warden.config.json (falls back to the
    example). Only the chain ids are read -- nothing else from the config."""
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = [path] if path else [
        os.path.join(here, "..", "..", "warden.config.json"),
        os.path.join(here, "..", "..", "warden.config.example.json"),
    ]
    for p in candidates:
        if p and os.path.exists(p):
            cfg = json.load(open(p))
            if isinstance(cfg.get("vault"), str) and cfg["vault"].startswith("0x") and len(cfg["vault"]) > 10:
                return {k: cfg[k] for k in _ADDRESS_KEYS}
    raise RuntimeError("no usable warden.config.json found (copy warden.config.example.json and fill in your ids)")


def _u64(x):
    """A u64 may arrive as int, numeric string, {value}, or {fields:{value}}."""
    if x is None:
        return 0
    if isinstance(x, bool):
        return int(x)
    if isinstance(x, int):
        return x
    if isinstance(x, str):
        return int(x)
    if isinstance(x, dict):
        if "value" in x:
            return _u64(x["value"])
        f = x.get("fields")
        if isinstance(f, dict) and "value" in f:
            return _u64(f["value"])
    return 0


def _to_hex(x):
    """A Move vector<u8> arrives as a list[int] (parsed content/events) or a
    base64 string. Normalise to 0x.. hex either way."""
    if x is None:
        return ""
    if isinstance(x, list):
        return "0x" + "".join("%02x" % (b & 0xFF) for b in x)
    if isinstance(x, str):
        try:
            return "0x" + base64.b64decode(x).hex()
        except Exception:
            return x
    return ""


class WardenClient:
    def __init__(self, addresses, rpc=TESTNET_RPC, clock_id=CLOCK_ID):
        self.addr = addresses
        self.rpc = rpc
        self.clock = clock_id

    # ------------------------------ RPC -------------------------------

    def _rpc(self, method, params):
        body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
        req = urllib.request.Request(self.rpc, data=body, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r).get("result")

    def _fields(self, oid):
        res = self._rpc("sui_getObject", [oid, {"showContent": True}]) or {}
        content = (res.get("data") or {}).get("content") or {}
        fields = content.get("fields")
        if not fields:
            raise RuntimeError("object %s has no readable content (wrong id / network?)" % oid)
        return fields

    # ---------------------------- readers -----------------------------

    def get_vault_state(self):
        """Live custody state. nav is conserved by every agent op; only the
        owner-withdraw path can shrink it."""
        f = self._fields(self.addr["vault"])
        idle, deployed = _u64(f.get("idle")), _u64(f.get("deployed"))
        return {
            "owner": f.get("owner", ""),
            "idle": idle,
            "deployed": deployed,
            "nav": idle + deployed,
            "shares": _u64(f.get("shares")),
            "frozen": bool(f.get("frozen")),
        }

    def get_ledger_state(self):
        """Append-only ledger head: monotonic sequence + keccak hash-chain head."""
        f = self._fields(self.addr["ledger"])
        return {
            "seq": _u64(f.get("seq")),
            "count": _u64(f.get("count")),
            "last_ms": _u64(f.get("last_ms")),
            "chain_head": _to_hex(f.get("prev_digest")),
        }

    def get_feed_state(self, now_ms=None):
        """Market feed the agent cannot forge, plus whether a read would be
        rejected as stale right now."""
        import time
        if now_ms is None:
            now_ms = int(time.time() * 1000)
        f = self._fields(self.addr["feed"])
        updated, max_age = _u64(f.get("updated_ms")), _u64(f.get("max_age_ms"))
        return {
            "feeder": f.get("feeder", ""),
            "price_e6": _u64(f.get("price_e6")),
            "depth": _u64(f.get("depth")),
            "updated_ms": updated,
            "max_age_ms": max_age,
            "stale": (max(0, now_ms) - updated) > max_age,
        }

    def get_ledger_history(self, limit=10):
        """The verifiable track record: most recent Recorded events, newest
        first. Rejected trades are here too -- the chain records what the agent
        was NOT allowed to do."""
        res = self._rpc("suix_queryEvents", [
            {"MoveEventType": "%s::ledger::Recorded" % self.addr["package"]},
            None, limit, True,
        ]) or {}
        out = []
        for e in res.get("data", []):
            p = e.get("parsedJson", {}) or {}
            out.append({
                "seq": int(p.get("seq", 0)),
                "ts_ms": int(p.get("ts_ms", 0)),
                "risk_bps": int(p.get("risk_bps", 0)),
                "accepted": bool(p.get("accepted")),
                "fault": int(p.get("fault", 0)),
                "trade_digest": _to_hex(p.get("trade_digest")),
                "entry_digest": _to_hex(p.get("entry_digest")),
            })
        return out

    # ------------------------- command builders -----------------------
    # Each returns the exact `sui client call` argv. The SDK never signs:
    #   import subprocess; subprocess.run(w.feed_update_cmd(1_000_000, 1_000))

    def _call(self, fn, args):
        return [
            "sui", "client", "call",
            "--package", self.addr["package"], "--module", "app", "--function", fn,
            "--args", *[str(a) for a in args],
            "--gas-budget", GAS_BUDGET, "--json",
        ]

    def agent_trade_cmd(self, amount, direction, claimed_risk_bps, walrus_blob="0x", tee_attestation="0x"):
        """The agent proposes a trade; it flows through all five gates atomically."""
        return self._call("agent_trade", [
            self.addr["vault"], self.addr["policy"], self.addr["gen_registry"],
            self.addr["critic_registry"], self.addr["critic_cap"], self.addr["ledger"], self.addr["feed"],
            amount, direction, claimed_risk_bps, walrus_blob, tee_attestation, self.clock,
        ])

    def feed_update_cmd(self, price_e6, depth):
        """The keeper writes market data (production: pulled from Pyth + DeepBook)."""
        return self._call("feed_update", [self.addr["feed"], price_e6, depth, self.clock])

    def owner_exit_cmd(self, owner_cap, amount):
        """The owner withdraws -- works even when the agent is frozen."""
        return self._call("owner_exit", [self.addr["vault"], owner_cap, amount])

    def owner_undeploy_cmd(self, owner_cap, amount):
        """The owner pulls deployed capital back into idle (the close leg)."""
        return self._call("owner_undeploy", [self.addr["vault"], owner_cap, amount])

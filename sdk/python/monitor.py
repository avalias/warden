"""
warden monitor -- tail the on-chain leash and react.

Polls the vault, ledger and market feed via the Python SDK and emits alerts when
the chain's state changes: a freeze (the agent has been halted), an unfreeze, new
ledger entries (accepted AND rejected), a stale feed, or a move in NAV. As entries
arrive it checks that the keccak hash-chain head advances -- tamper-evidence in
real time.

    python monitor.py --once            # one snapshot + any alerts, then exit
    python monitor.py --interval 5      # watch forever, polling every 5s

Read-only: no keys, no signing, no gas. This is the operational counterpart to
the thesis -- you can WATCH the leash hold, live. ASCII output (console-safe).
"""
import argparse
import time
from warden import WardenClient, load_addresses, TESTNET_RPC

FAULTS = {0: "none", 1: "diverged", 2: "ceiling", 3: "unsafe-direction"}


def _ts(ms):
    if not ms:
        return "-"
    return time.strftime("%Y-%m-%d %H:%M:%SZ", time.gmtime(ms / 1000))


def _log(tag, msg):
    print("[%s] %-6s %s" % (time.strftime("%H:%M:%S"), tag, msg), flush=True)


def read(w):
    return {"vault": w.get_vault_state(), "ledger": w.get_ledger_state(), "feed": w.get_feed_state()}


def report_initial(w, s):
    v, l, f = s["vault"], s["ledger"], s["feed"]
    _log("STATE", "NAV=%s MIST (idle %s + deployed %s)  frozen=%s" % (v["nav"], v["idle"], v["deployed"], v["frozen"]))
    _log("STATE", "ledger seq=%s  chain_head=%s" % (l["seq"], l["chain_head"][:18] + "..."))
    _log("STATE", "feed price_e6=%s depth=%s updated=%s stale=%s" % (f["price_e6"], f["depth"], _ts(f["updated_ms"]), f["stale"]))
    if v["frozen"]:
        _log("ALERT", "vault is FROZEN -- the agent is halted (owner withdraw still works)")
    if f["stale"]:
        _log("WARN", "feed is STALE -- the guardian will reject reads until the keeper updates it")
    if f["price_e6"] == 0:
        _log("WARN", "feed price is ZERO (uninitialized?) -- guardian would derive 0 risk; do NOT trade until the keeper posts a real price")
    # show the most recent entry for context
    hist = w.get_ledger_history(1)
    if hist:
        e = hist[0]
        verdict = "ACCEPTED" if e["accepted"] else ("REJECTED(%s)" % FAULTS.get(e["fault"], e["fault"]))
        _log("LEDGER", "#%s %s risk=%sbps @ %s" % (e["seq"], verdict, e["risk_bps"], _ts(e["ts_ms"])))


def report_diff(w, prev, cur):
    pv, cv = prev["vault"], cur["vault"]
    pl, cl = prev["ledger"], cur["ledger"]
    pf, cf = prev["feed"], cur["feed"]

    if cv["frozen"] and not pv["frozen"]:
        _log("ALERT", "vault FROZEN -- agent halted; reason is the latest ledger fault")
    elif not cv["frozen"] and pv["frozen"]:
        _log("OK", "vault UNFROZEN -- the owner lifted the freeze; agent active again")

    if cv["nav"] != pv["nav"]:
        delta = cv["nav"] - pv["nav"]
        sign = "+" if delta >= 0 else ""
        _log("NAV", "NAV %s -> %s MIST (%s%s)" % (pv["nav"], cv["nav"], sign, delta))

    if cf["stale"] and not pf["stale"]:
        _log("WARN", "feed went STALE -- guardian reads will be rejected")
    elif not cf["stale"] and pf["stale"]:
        _log("OK", "feed is FRESH again")

    if cf["price_e6"] == 0 and pf["price_e6"] != 0:
        _log("WARN", "feed price is ZERO (uninitialized?) -- guardian would derive 0 risk; do NOT trade until the keeper posts a real price")

    new = int(cl["seq"]) - int(pl["seq"])
    if new > 0:
        # tamper-evidence: a new entry MUST advance the keccak chain head
        chain_moved = cl["chain_head"] != pl["chain_head"]
        _log("LEDGER", "%d new entr%s -- chain head %s (advanced=%s)" % (
            new, "y" if new == 1 else "ies", cl["chain_head"][:18] + "...", chain_moved))
        if not chain_moved:
            _log("ALERT", "hash-chain head did NOT advance on a new entry -- tamper signal!")
        for e in reversed(w.get_ledger_history(min(new, 20))):
            verdict = "ACCEPTED" if e["accepted"] else ("REJECTED(%s)" % FAULTS.get(e["fault"], e["fault"]))
            _log("LEDGER", "  #%s %s risk=%sbps entry=%s..." % (e["seq"], verdict, e["risk_bps"], e["entry_digest"][:18]))


def main():
    ap = argparse.ArgumentParser(description="Watch the WARDEN on-chain leash and react to state changes.")
    ap.add_argument("--once", action="store_true", help="print one snapshot + alerts, then exit")
    ap.add_argument("--interval", type=float, default=10.0, help="poll seconds (default 10)")
    ap.add_argument("--rpc", default=TESTNET_RPC, help="fullnode RPC url")
    args = ap.parse_args()

    w = WardenClient(load_addresses(), rpc=args.rpc)
    _log("BOOT", "watching WARDEN %s" % w.addr["package"])

    prev = None
    while True:
        try:
            cur = read(w)
            if prev is None:
                report_initial(w, cur)
            else:
                report_diff(w, prev, cur)
            prev = cur
        except Exception as e:  # a transient RPC hiccup must not kill the watcher
            _log("ERR", "read failed: %s" % e)
        if args.once:
            break
        time.sleep(args.interval)

    if args.once:
        _log("DONE", "one-shot snapshot complete")


if __name__ == "__main__":
    main()

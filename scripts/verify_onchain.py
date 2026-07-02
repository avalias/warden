#!/usr/bin/env python3
"""
WARDEN — continuous on-chain proof verifier.

Re-checks, against Sui testnet, that everything the submission claims is still
live and true — with ZERO trust in this repo and no Sui CLI required (pure
stdlib + the public RPC). Run it yourself, or let CI run it on every push and on
a daily schedule:

    python scripts/verify_onchain.py

Exits 0 only if: the canonical package is live, the UpgradeCap is burned
(immutable), the make_immutable tx succeeded, and all 15 lifecycle transactions
exist and succeeded with their expected events.
"""
import json, sys, urllib.request

RPC = "https://fullnode.testnet.sui.io:443"
PACKAGE = "0xfd613140878e6e12487208bc8185b119a14031daac7149de860c2d9771527437"
UPGRADE_CAP = "0x8c6b9c18b9a3924459302ab281fd105419fcc9a334ad9b2548d6c0d8114d282e"
BURN_TX = "G9rS4pWStqjx6K5GC9dKZa8sZF3ymybEpWiE6DKTDPuW"

# (label, digest, required-events-subset)
LIFECYCLE = [
    ("open_vault",     "6A3E24RDkxY4NZuFKXGqYuEHC26ErSvFWA2oU9RHTErP", []),
    ("feed_open",      "AXoLFcpihLzFLDzdFzRk6QkTbsivXSVCNTdNuE5DZQRW", []),
    ("feed_deep",      "5yVaWE8nvXYeWw6ZBWbnNHk7MXh5cWKxZ8uGqXftzNUL", ["Updated"]),
    ("accepted_trade", "7xhJysZxJpQJ5t7sucLRdxc2o1nNSHtpumof8FBbKBRR", ["Recorded"]),
    ("feed_thin",      "3pWWdm6Vz3twFjLEmJcoB5jYvgzwM3793Cy6RBZtHtpH", ["Updated"]),
    ("heart_freeze",   "9BbwxdsRB43kE63sEiZqubksMRGVJMxr5EALBx7BUi9m", ["VaultFrozen", "Recorded"]),
    ("owner_exit",     "AwXb1KEesP3YxFYAmjrZ3SsTHdDfuuubAH8L4YjUVpM8", ["Withdrawn"]),
    ("open_hedge",     "D6czQv4oeBD2zKvRz4Tzwy1d2xTvpssVSdy6C1UoqcxW", []),
    ("settle_hedge",   "Bfx9mj4Fxas9nqvx3BZawyZjrqWTvPZns1gijc1nrMjw", ["Settled"]),
    ("kyc_open",       "8KB9sdwbK9Y3QPzkVhBLdF4ppzTo8Na4jHveYiBXKy1R", []),
    ("kyc_set",        "HxG4sAwsXxhzHRXE8rchY1YWmm1RBpRZYrWy2QZ7KQg1", []),
    ("oracle_propose", "8dfTVWENwsHmRhcWpYc8g282zz1eaMwcTdgV8NCVGNSx", []),
    ("oracle_finalize","BxXzCrkSZzCJT2f2cx6VS4Tou7aBnZfMkcMJkurfPVdz", []),
    ("inherit_open",   "JxYNBvnFtcBCkkDsFgoLaAVZVpANKMJVxP32N85qw91", []),
    ("inherit_claim",  "EiDvSwCajnDxhMRQm2FKVoXfMeqDMdSQXe8U6PR2RRWU", ["Inherited"]),
]

# The lifecycle kept running after submission: the keeper feeding live DeepBook
# v3 market data, the owner lifting the demo freeze (with a fresh policy), and
# an accepted trade whose reasoning blob lives on Walrus testnet — the blob id
# is anchored in the recorded transaction's inputs.
CONTINUED = [
    ("keeper_deepbook_feed",  "EXr7EPu9W9HoEBHVnrnkNx1xaagbcDr4XyuGDeQUPPyi", ["Updated"]),
    ("keeper_feed_refresh",   "J9CpoXkWcQpcym6KT5NiZhVwf2Es1HdYSq1RWBcopiR9", ["Updated"]),
    ("owner_unfreeze_policy", "311vmCEH98hnFxwp8twZZQMFHan9KAeJLMEHTvGi8PYF", []),
    ("walrus_proof_trade",    "HHhaTYCtM9BJFDRu7qVUz8V6Q6QgvrbYQ5qgJiG7aaxn", ["Recorded"]),
]


def rpc(method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(RPC, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def main():
    fails = []

    def check(ok, label):
        print(f"  [{'OK ' if ok else 'FAIL'}] {label}")
        if not ok:
            fails.append(label)

    print("package + immutability:")
    pkg = rpc("sui_getObject", [PACKAGE, {"showType": True}]).get("result", {})
    check(bool(pkg.get("data")) and pkg["data"].get("type") == "package", "canonical package is live")
    cap = rpc("sui_getObject", [UPGRADE_CAP, {"showType": True}]).get("result", {})
    check(bool(cap.get("error")) and not cap.get("data"), "UpgradeCap is burned -> package is immutable")
    burn = rpc("sui_getTransactionBlock", [BURN_TX, {"showEffects": True}]).get("result")
    check(burn and burn["effects"]["status"]["status"] == "success", "make_immutable (burn) tx succeeded")

    def check_txs(title, txs):
        print(title + ":")
        for label, dig, want in txs:
            res = rpc("sui_getTransactionBlock", [dig, {"showEvents": True, "showEffects": True}]).get("result")
            if not res:
                check(False, f"{label}: tx missing"); continue
            status = res["effects"]["status"]["status"]
            events = {e["type"].split("::")[-1] for e in res.get("events", [])}
            ok = status == "success" and all(w in events for w in want)
            check(ok, f"{label}: {status}" + (f" events={sorted(events)}" if want else ""))

    check_txs("15-tx lifecycle", LIFECYCLE)
    check_txs("continued lifecycle (post-submission)", CONTINUED)

    print()
    if fails:
        print(f"VERIFICATION FAILED ({len(fails)} issue(s)).")
        sys.exit(1)
    print(f"ALL {3 + len(LIFECYCLE) + len(CONTINUED)} CHECKS PASS — package immutable, full lifecycle live on Sui testnet.")


if __name__ == "__main__":
    main()

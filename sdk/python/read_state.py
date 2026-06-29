"""
Read-only smoke: pull WARDEN's live state straight from Sui testnet and print it.
No keys, no signing, no gas -- just proof the readers work against the real,
immutable package. Pure stdlib; ASCII output (safe on any console).

    cd sdk/python && python read_state.py
"""
from warden import WardenClient, load_addresses


def main():
    w = WardenClient(load_addresses())
    print("WARDEN @ %s" % w.addr["package"])
    print("  (Sui testnet, read-only)\n")

    v = w.get_vault_state()
    print("VAULT")
    print("  owner     %s" % v["owner"])
    print("  idle      %s MIST" % v["idle"])
    print("  deployed  %s MIST" % v["deployed"])
    print("  NAV       %s MIST   (idle + deployed, conserved by agent ops)" % v["nav"])
    print("  frozen    %s\n" % v["frozen"])

    f = w.get_feed_state()
    print("FEED")
    print("  price_e6  %s" % f["price_e6"])
    print("  depth     %s" % f["depth"])
    print("  stale     %s   (max_age %s ms)\n" % (f["stale"], f["max_age_ms"]))

    l = w.get_ledger_state()
    print("LEDGER")
    print("  seq        %s" % l["seq"])
    print("  count      %s" % l["count"])
    print("  chain_head %s\n" % l["chain_head"])

    hist = w.get_ledger_history(5)
    print("LEDGER HISTORY (latest %d)" % len(hist))
    for e in hist:
        verdict = "ACCEPTED" if e["accepted"] else ("REJECTED(fault=%d)" % e["fault"])
        print("  #%d  %s  risk=%dbps  entry=%s..." % (e["seq"], verdict, e["risk_bps"], e["entry_digest"][:18]))

    print("\nExample build (you sign + run): feed_update_cmd(1_000_000, 1_000)")
    print("  " + " ".join(w.feed_update_cmd(1_000_000, 1_000)))
    print("\nOK -- live state read from the immutable package with zero trust in any server.")


if __name__ == "__main__":
    main()

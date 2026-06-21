#!/usr/bin/env bash
# Reproduce the full WARDEN L0->L6 lifecycle on Sui testnet (12 transactions).
#
#   L0/L1/L2/L4  open_vault -> accepted -> freeze-on-lie -> owner_exit
#   L3           open_hedge -> settle_hedge (bounded drawdown)
#   L5           kyc_open -> kyc_set ; oracle_propose -> (wait) -> oracle_finalize
#   L6           inherit_open -> (wait) -> inherit_claim
#
# Usage: PKG=0x<packageId> SEED=0x<sui-coin> ./demo.sh
# (SEED is a Coin<SUI> object you own; it becomes the vault's capital.)
set -euo pipefail

: "${PKG:?set PKG to the published packageId}"
: "${SEED:?set SEED to a Coin<SUI> object id to fund the vault}"
ME=$(sui client active-address)

# call <function> <args...> -> prints raw json on fd 3, pretty digest+events on stdout
call() {
  local fn="$1"; shift
  if [ "$#" -gt 0 ]; then
    sui client call --package "$PKG" --module app --function "$fn" --args "$@" --gas-budget 60000000 --json
  else
    sui client call --package "$PKG" --module app --function "$fn" --gas-budget 60000000 --json
  fi
}
show() { python -c "import json,sys;d=json.load(sys.stdin);print('   ',d['digest'],d['effects']['status']['status'],[e['type'].split('::')[-1] for e in d.get('events',[])])"; }
# id <jsonfile> <TypeSuffix> -> objectId of the first created object of that type
oid() { python -c "import json,sys;d=json.load(open(sys.argv[1]));print([c['objectId'] for c in d['objectChanges'] if c['type']=='created' and sys.argv[2] in c['objectType']][0])" "$1" "$2"; }
T=$(mktemp -d)

echo "== L0/L1: open_vault =="
call open_vault "$SEED" "$ME" 50000000 200000000 60000 20000000 3600000 0x6 > "$T/ov.json"; show < "$T/ov.json"
V=$(oid "$T/ov.json" "vault::Vault"); POL=$(oid "$T/ov.json" "WardenPolicy"); REG=$(oid "$T/ov.json" "GenerationRegistry")
CREG=$(oid "$T/ov.json" "CriticRegistry"); CCAP=$(oid "$T/ov.json" "CriticCap"); LED=$(oid "$T/ov.json" "TradeLedger"); OCAP=$(oid "$T/ov.json" "OwnerCap")

echo "== L2: accepted trade (deep book, claim matches chain) =="
call agent_trade "$V" "$POL" "$REG" "$CREG" "$CCAP" "$LED" 10000000 0 0 1000000 1000000000000 0x7472 0x7772 0x7474 0x6 | show
echo "== L2: the heart (agent lies; thin book) -> FREEZE =="
call agent_trade "$V" "$POL" "$REG" "$CREG" "$CCAP" "$LED" 10000000 1 0 1000000 1000 0x6c6965 0x7772 0x7474 0x6 | show
echo "== L0: owner_exit (works while frozen) =="
call owner_exit "$V" "$OCAP" 5000000 | show

echo "== L3: open_hedge -> settle_hedge =="
call open_hedge "$V" 50000000 50 1000000 900000 2000 0x6 > "$T/h.json"; show < "$T/h.json"
HC=$(oid "$T/h.json" "HedgedCarry")
call settle_hedge "$HC" 800000 0x6 | show

echo "== L5: KYC gate =="
call kyc_open > "$T/k.json"; show < "$T/k.json"; KREG=$(oid "$T/k.json" "KycRegistry")
call kyc_set "$KREG" "$ME" true | show

echo "== L5: optimistic oracle (4s challenge window) =="
call oracle_propose 0x425443 "$ME" 1 1000 4000 0x6 > "$T/o.json"; show < "$T/o.json"; CLAIM=$(oid "$T/o.json" "oracle::Claim")
echo "   ...waiting out the challenge window..."; sleep 5
call oracle_finalize "$CLAIM" 0x6 | show

echo "== L6: dead-man-switch (4s dormancy) =="
call inherit_open "$ME" 4000 0x6 > "$T/i.json"; show < "$T/i.json"; SW=$(oid "$T/i.json" "inheritance::Switch")
echo "   ...waiting out the dormancy period..."; sleep 5
call inherit_claim "$SW" 0x6 | show

echo "== done: full L0->L6 lifecycle reproduced on-chain =="

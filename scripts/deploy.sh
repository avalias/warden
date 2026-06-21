#!/usr/bin/env bash
# Deploy the WARDEN package to the active Sui environment.
# Usage: ./deploy.sh            (publishes contracts/ and prints the packageId)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/contracts"

echo "==> Building + testing"
sui move build
sui move test

echo "==> Publishing to $(sui client active-env)"
OUT="$ROOT/.publish.json"
sui client publish --gas-budget 200000000 --json > "$OUT"

PKG=$(python -c "import json;print([c['packageId'] for c in json.load(open(r'$OUT'))['objectChanges'] if c['type']=='published'][0])")
echo "==> Published package: $PKG"
echo "    explorer: https://suiscan.xyz/testnet/object/$PKG"
echo "$PKG"

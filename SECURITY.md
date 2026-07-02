# Security

## Scope

WARDEN is a **testnet** deployment built for Sui Overflow 2026. No real funds are
at risk. The canonical package is **immutable** — the `UpgradeCap` was burned
([make_immutable tx](https://suiscan.xyz/testnet/tx/G9rS4pWStqjx6K5GC9dKZa8sZF3ymybEpWiE6DKTDPuW)) —
so on-chain fixes ship as a *new* package, never as a silent upgrade.

## Reporting

Found something? Open a
[GitHub security advisory](https://github.com/avalias/warden/security/advisories/new)
or a plain issue if it's not sensitive. There is no bug bounty; there is honest
triage and public credit.

## Known, openly tracked limitations

We ran an adversarial review against our own code and published everything it
found — see [ROADMAP.md](ROADMAP.md) (*"Surfaced by our own adversarial code
review; tracked openly rather than hidden"*), each item pinned by a named test
where possible:

- the reduce direction is a guardian **gate label**; the executed leg is
  deploy-only (`test_reduce_label_still_deploys`),
- a zero-price (uninitialized) feed derives 0 risk — the keeper must post a
  non-zero price (`test_zero_price_feed_derives_zero_risk`),
- the demo critic entry reduces to a same-signer approval,
- the L4 replay-set is O(n) per append,
- L5/L6 satellites (oracle bonds, shared dead-man-switch, VRF draw) are
  primitives with a hardening roadmap.

## Verify, don't trust

- `python scripts/verify_onchain.py` — package immutable + full lifecycle live
  (pure stdlib, no Sui CLI).
- `python scripts/verify_ledger.py` — re-derives the keccak hash-chain from
  on-chain events.
- `cd contracts && sui move test` — the full unit + property suite.
- CI re-runs the on-chain verification on every push and daily.

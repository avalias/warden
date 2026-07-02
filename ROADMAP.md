# WARDEN — Roadmap

The deployed package is **immutable** (the `UpgradeCap` is burned) — the leash
itself cannot be changed. Everything below therefore ships as a **new package**
plus off-chain tooling; the current canonical package keeps its frozen,
on-chain-proven guarantees while the protocol evolves around it.

Status is tracked honestly: what's **on-chain today**, and what's **next**.

## On-chain today (frozen, immutable)
- **L0** non-custodial vault with a real-`Balance` value plane (deploy/undeploy move real capital; NAV conserved; owner-only withdraw, works while frozen).
- **L1** non-transferable scoped policy + one-tx generation revocation.
- **L2 — the heart** on-chain risk re-derivation from a keeper feed the agent can't forge → clamp / freeze on divergence; on-chain-derived, replay-protected trade digest.
- **L4** keccak **hash-chained**, no-delete ledger (re-derivable off-chain via `scripts/verify_ledger.py`).
- **L3, L5, L6** primitives: bounded-drawdown hedge; KYC gate + optimistic oracle; dead-man-switch + commit-reveal draw.

## Next — hardening the satellites (next package)
*Surfaced by our own adversarial code review; tracked openly rather than hidden.*
- **L6 dead-man-switch:** share the `Switch` object so a third-party beneficiary (not just the owner) can trigger the claim after dormancy; assert `sender == beneficiary`. *Workaround shipped without a new package:* the SDK's `buildInheritOpenSharedTx` opens the switch as a shared object via a PTB (`inheritance::new` + `public_share_object`) — devInspect-verified against the deployed package; the `sender == beneficiary` assert still needs the new package.
- **L6 prize draw:** take real `Coin` custody (not a counter) and replace `acc % n` with VRF / a commit-reveal seed that the last revealer cannot grind.
- **L5 oracle:** escrow a real bond on `dispute`, slashed/paid on resolution, so the optimistic fast-path can't be griefed for free.
- **L2 critic:** enforce `critic ≠ agent` at mint, and ship a real second-signer veto flow (a distinct critic key escrowing its verdict) — as shipped, the same-tx hot-potato `Verdict` reduces to a same-signer approval.
- **L2 value plane:** branch `settle()` to `undeploy` on the reduce direction — in the shipped package `direction` is a guardian gate label only and the executed leg is deploy-only (pinned by `test_reduce_label_still_deploys`); the ceiling and divergence checks do operate on the true post-trade exposure.
- **L2 feed:** reject `price_e6 == 0` on read/update — an uninitialized or zero-price feed currently derives 0 risk (pinned by `test_zero_price_feed_derives_zero_risk`); the keeper must post a non-zero price, and the SDK monitor flags a zero-price feed.
- **L4 ledger:** replace the O(n) `seen` replay-guard (`VecSet` linear scan) with a `Table`/dynamic-field so per-append gas stays O(1) as history grows; the keccak hash chain already provides the tamper-evidence.

## Next — the value plane (real venue)
- Wire `vault::deploy` to a **DeepBook v3** market/limit order against `idle`; `strategy::settle` against the live feed with real PnL movement.
- Minimal **NAV / shares / protocol fee** so depositor economics are real.
- A **keeper service** pulling **Pyth + DeepBook** into `feed_update` — *first leg shipped:* [`scripts/keeper/`](scripts/keeper/) reads live DeepBook v3 mid-price + level-2 depth and posts it into the feed ([tx `EXr7EPu9…`](https://suiscan.xyz/testnet/tx/EXr7EPu9W9HoEBHVnrnkNx1xaagbcDr4XyuGDeQUPPyi)); Pyth cross-checking and a permissionless feeder set (removing the single-feeder trust root) remain.

## Next — confidentiality & distribution
- **Seal** threshold-IBE + **Nautilus/Nitro** TEE attestation; native **Confidential Transfers**. *(The real **Walrus** write shipped: the seq-3 reasoning blob lives on Walrus testnet — [retrievable](https://aggregator.walrus-testnet.walrus.space/v1/blobs/gUICc2caGFERGeoDztYrR4GHv6XmSFlEAL-UjtcA4HI), anchored in [tx `HHhaTYCt…`](https://suiscan.xyz/testnet/tx/HHhaTYCtM9BJFDRu7qVUz8V6Q6QgvrbYQ5qgJiG7aaxn) — so two of the three receipt proofs are live; Seal-encrypting the blob and the TEE leg remain.)*
- **x402** agent-payment rail. *(An **MCP server** (agent-runtime tools) plus typed **TypeScript** and dependency-free **Python** SDKs — live-state readers + transaction builders — have shipped in [`sdk/`](sdk/).)*

## Tooling / assurance
- **Move Prover** specs for the custody invariant (only `owner_withdraw` reduces withdrawable `idle`) and the guardian safety invariant (`ok ⇒ derived ≤ ceiling`, danger-zone ⇒ `REDUCE`-only).
- Keep `scripts/verify_onchain.py` + `scripts/verify_ledger.py` green in CI (push + daily), so the on-chain proof is continuously, automatically re-verified.

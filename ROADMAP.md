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
- **L6 dead-man-switch:** share the `Switch` object so a third-party beneficiary (not just the owner) can trigger the claim after dormancy; assert `sender == beneficiary`.
- **L6 prize draw:** take real `Coin` custody (not a counter) and replace `acc % n` with VRF / a commit-reveal seed that the last revealer cannot grind.
- **L5 oracle:** escrow a real bond on `dispute`, slashed/paid on resolution, so the optimistic fast-path can't be griefed for free.
- **L2 critic:** enforce `critic ≠ agent` at mint, and ship a real second-signer veto flow (a distinct critic key escrowing its verdict).

## Next — the value plane (real venue)
- Wire `vault::deploy` to a **DeepBook v3** market/limit order against `idle`; `strategy::settle` against the live feed with real PnL movement.
- Minimal **NAV / shares / protocol fee** so depositor economics are real.
- A **keeper service** pulling **Pyth + DeepBook** into `feed_update` (removes the single-feeder trust root).

## Next — confidentiality & distribution
- **Seal** threshold-IBE + **Nautilus/Nitro** TEE attestation; native **Confidential Transfers**; a real **Walrus** write of the agent's sealed reasoning (turning two of the three receipt proofs real).
- **x402** agent-payment rail; an **MCP** server + a Python SDK. *(A typed TypeScript SDK — live-state readers + unsigned PTB builders — has shipped in [`sdk/`](sdk/).)*

## Tooling / assurance
- **Move Prover** specs for the custody invariant (only `owner_withdraw` reduces withdrawable `idle`) and the guardian safety invariant (`ok ⇒ derived ≤ ceiling`, danger-zone ⇒ `REDUCE`-only).
- Keep `scripts/verify_onchain.py` + `scripts/verify_ledger.py` green in CI (push + daily), so the on-chain proof is continuously, automatically re-verified.

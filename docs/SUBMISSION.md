# WARDEN — Sui Overflow 2026 submission

Copy-paste fields for the DeepSurge submission form.

---

**Project name:** WARDEN

**Tagline:** The autonomous AI fund you don't have to trust.

**Track:** The Agentic Web  *(sub-track: Autonomous Agent Wallet)* — also relevant to DeFi & Payments.

**One-liner:**
> A regulated-ready, fully verifiable, non-custodial autonomous asset manager on Sui where the AI only *proposes* and the chain re-derives, clamps, freezes, and proves every move.

---

## Description

Every autonomous "AI wallet" shares one flaw: you must **trust the agent** — it holds a broad key, you trust its own risk numbers, and its reasoning is off-chain and deniable.

WARDEN inverts this. The AI emits an unsigned intent; then a deterministic, fail-closed **Guardian re-derives the risk on-chain** from a keeper-fed feed the agent can't forge, a separable **critic capability** co-signs (single-operator in the demo; a distinct critic signer in multi-party deployment), the agent is **clamped to the risk-reducing direction**, and on any divergence the **vault freezes** — while the owner can always withdraw. The critic signs a digest **derived on-chain** from the trade, and every decision is recorded in a keccak **hash-chained**, no-delete three-proof ledger.

That single inversion turns "a cute agent" into infrastructure a regulated institution can actually fund, because trusting the agent is no longer required.

The design is organized into seven composable layers under one thesis: **trust-minimization**. This submission ships **all seven** — L0 non-custodial custody, L1 object-capability + revocation, L2 the chain-never-trusts-the-AI core, L3 a self-hedging bounded-drawdown strategy, L4 the append-only ledger, L5 a closed-loop KYC gate + Move-native optimistic oracle, and L6 dead-man-switch inheritance + a no-loss commit-reveal draw — built, unit-tested, and deployed.

## What's built (and verifiable)

- **Sui Move package**, 13 modules: `vault · policy · guardian · critic · ledger · strategy · feed · compliance · oracle · inheritance · prize · warden · app`.
- **43/43 Move unit tests passing** — the heart (direct guardian coverage: risk arithmetic, the divergence boundary, the hard ceiling, the safe-direction clamp both ways), every gate's negative path (L1 per-tx/window/expiry/pause/wrong-vault, L2 critic veto + wrong identity, L4 monotonic append, L0 reserve floor/frozen/owner-only/unfreeze), freeze-on-divergence, non-custodial withdraw, generation revocation, the L3 bounded-drawdown invariant, L5 KYC gating + the oracle window, and L6 inheritance + the no-loss draw.
- **Deployed + verified on Sui testnet, `owner: Immutable`** — the `UpgradeCap` was **burned** ([make_immutable tx](https://suiscan.xyz/testnet/tx/G9rS4pWStqjx6K5GC9dKZa8sZF3ymybEpWiE6DKTDPuW)), so the package can never be changed, not even by us.
- **On-chain proof:** the **full L0→L6 lifecycle is anchored on testnet** across **15 clickable transactions**. Reproducible via `scripts/demo.sh`.

## How to verify

- **Package:** `0xfd613140878e6e12487208bc8185b119a14031daac7149de860c2d9771527437`
  → https://suiscan.xyz/testnet/object/0xfd613140878e6e12487208bc8185b119a14031daac7149de860c2d9771527437
- **The 15-tx lifecycle** (all on testnet):
  - open_vault — https://suiscan.xyz/testnet/tx/6A3E24RDkxY4NZuFKXGqYuEHC26ErSvFWA2oU9RHTErP
  - feed_open (keeper market feed) — https://suiscan.xyz/testnet/tx/AXoLFcpihLzFLDzdFzRk6QkTbsivXSVCNTdNuE5DZQRW
  - feed_update (deep book) — https://suiscan.xyz/testnet/tx/5yVaWE8nvXYeWw6ZBWbnNHk7MXh5cWKxZ8uGqXftzNUL
  - accepted trade (Guardian reads the feed) — https://suiscan.xyz/testnet/tx/7xhJysZxJpQJ5t7sucLRdxc2o1nNSHtpumof8FBbKBRR
  - feed_update (keeper posts a thin book / crash) — https://suiscan.xyz/testnet/tx/3pWWdm6Vz3twFjLEmJcoB5jYvgzwM3793Cy6RBZtHtpH
  - **the heart** (chain reads the feed → freeze) — https://suiscan.xyz/testnet/tx/9BbwxdsRB43kE63sEiZqubksMRGVJMxr5EALBx7BUi9m
  - owner exit while frozen — https://suiscan.xyz/testnet/tx/AwXb1KEesP3YxFYAmjrZ3SsTHdDfuuubAH8L4YjUVpM8
  - open hedge (L3) — https://suiscan.xyz/testnet/tx/D6czQv4oeBD2zKvRz4Tzwy1d2xTvpssVSdy6C1UoqcxW
  - settle hedge — bounded drawdown (L3) — https://suiscan.xyz/testnet/tx/Bfx9mj4Fxas9nqvx3BZawyZjrqWTvPZns1gijc1nrMjw
  - kyc_open (L5) — https://suiscan.xyz/testnet/tx/8KB9sdwbK9Y3QPzkVhBLdF4ppzTo8Na4jHveYiBXKy1R
  - kyc_set / verify (L5) — https://suiscan.xyz/testnet/tx/HxG4sAwsXxhzHRXE8rchY1YWmm1RBpRZYrWy2QZ7KQg1
  - oracle_propose (L5) — https://suiscan.xyz/testnet/tx/8dfTVWENwsHmRhcWpYc8g282zz1eaMwcTdgV8NCVGNSx
  - oracle_finalize (L5) — https://suiscan.xyz/testnet/tx/BxXzCrkSZzCJT2f2cx6VS4Tou7aBnZfMkcMJkurfPVdz
  - inherit_open (L6) — https://suiscan.xyz/testnet/tx/JxYNBvnFtcBCkkDsFgoLaAVZVpANKMJVxP32N85qw91
  - inherit_claim (L6) — https://suiscan.xyz/testnet/tx/EiDvSwCajnDxhMRQm2FKVoXfMeqDMdSQXe8U6PR2RRWU
- **Tests:** `cd contracts && sui move test` → 43/43.
- **Verify the ledger hash-chain (no trust required):** `python scripts/verify_ledger.py` re-derives every entry from the on-chain `Recorded` events and prints `CHAIN INTACT`.
- **Real capital, not a counter:** after the accepted trade the vault's `deployed` holds **10,000,000 real MIST**; the frozen trade kept the rest safe in `idle`. NAV (`idle + deployed`) is conserved — funds never leave the vault.

## Tech stack

**Used today (in the on-chain code + agent):** Sui Move (object-capabilities, hot-potato settlement, `Clock`, events, `keccak256`), the on-chain `OracleFeed` (keeper-written price + order-book depth the guardian re-derives from), and the off-chain agent on a frontier LLM.

**Designed-for integrations (roadmap — not yet wired into the Move code):** DeepBook v3 (execution venue + the depth source the guardian would re-derive from), Pyth (signed price source for the feed), Walrus + Seal + Nautilus TEE (sealed reasoning, confidentiality, attested facts), zkLogin/Enoki (onboarding).

## Links

- **Repo:** https://github.com/avalias/warden
- **Site (landing + live dApp):** https://avalias.github.io/warden  ·  dApp at /app/
- **Architecture (full 7-layer spec):** [docs/ARCHITECTURE.md](ARCHITECTURE.md)
- **Demo video script:** [docs/DEMO_SCRIPT.md](DEMO_SCRIPT.md)
- **Demo video:** _(add URL)_

## Roadmap (honestly labeled, not claimed as built)

The seven layers are built and on-chain. What remains is not a *layer* but the heaviest *integrations* inside L5/L6:

- **L5 deepening:** wire the KYC gate into compliance-gated DeepBook/CLMM venue adapters; add native **Confidential Transfers** and **Seal threshold-IBE + Nautilus/Nitro attestation** for private risk models.
- **L6 distribution:** the **x402** agent-payment rail, an **MCP** server + TS/Py/Rust SDKs, and Walrus-Sites hosting with byte-level integrity.

An **AI agent** is included — [`agent/agent.py`](agent/agent.py), an LLM-powered loop that reads the on-chain feed and proposes `agent_trade` under the policy. Productionizing it (sealing the reasoning to Walrus, scheduling, multi-asset) is roadmap; the trust-minimization is the point: the chain vets whatever the agent proposes.

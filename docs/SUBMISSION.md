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

WARDEN inverts this. The AI emits an unsigned intent; then a deterministic, fail-closed **Guardian re-derives the risk on-chain** from a keeper-fed feed the agent can't forge, a separable **critic capability** co-signs (single-operator in the demo; a distinct critic signer in multi-party deployment), the agent is **clamped to the risk-reducing direction**, and on any divergence the **vault freezes** — while the owner can always withdraw. Every decision is recorded in an append-only, monotonic, no-delete three-proof ledger.

That single inversion turns "a cute agent" into infrastructure a regulated institution can actually fund, because trusting the agent is no longer required.

The design is organized into seven composable layers under one thesis: **trust-minimization**. This submission ships **all seven** — L0 non-custodial custody, L1 object-capability + revocation, L2 the chain-never-trusts-the-AI core, L3 a self-hedging bounded-drawdown strategy, L4 the append-only ledger, L5 a closed-loop KYC gate + Move-native optimistic oracle, and L6 dead-man-switch inheritance + a no-loss commit-reveal draw — built, unit-tested, and deployed.

## What's built (and verifiable)

- **Sui Move package**, 13 modules: `vault · policy · guardian · critic · ledger · strategy · feed · compliance · oracle · inheritance · prize · warden · app`.
- **26/26 Move unit tests passing** — the heart (direct guardian coverage: risk arithmetic, the divergence boundary, the hard ceiling, the safe-direction clamp both ways) + freeze-on-divergence, non-custodial withdraw, capability scope, generation revocation, the L3 bounded-drawdown invariant, L5 KYC gating + the oracle window, and L6 inheritance + the no-loss draw.
- **Deployed + verified on Sui testnet.** (The `UpgradeCap` is retained by the deployer; burning it for immutability is a deliberate, pending step.)
- **On-chain proof:** the **full L0→L6 lifecycle is anchored on testnet** across **15 clickable transactions**. Reproducible via `scripts/demo.sh`.

## How to verify

- **Package:** `0x823f8490c1ce2d576a4d3ed3631fda93d7327f4daaea4fe6ecabf8ea64826902`
  → https://suiscan.xyz/testnet/object/0x823f8490c1ce2d576a4d3ed3631fda93d7327f4daaea4fe6ecabf8ea64826902
- **The 15-tx lifecycle** (all on testnet):
  - open_vault — https://suiscan.xyz/testnet/tx/4KFjVaGoGaQyW6wArhTH3xsPNViyR3Tc8nR3rdhz7Mav
  - feed_open (keeper market feed) — https://suiscan.xyz/testnet/tx/9v9okf2NxDiq3RRjD4jUXWyD4LHjzapWGHMVPuFUWVdV
  - feed_update (deep book) — https://suiscan.xyz/testnet/tx/B1MraJK5ZPT7qVm8VGtkvMigouZTC11711zmrDxmDxai
  - accepted trade (Guardian reads the feed) — https://suiscan.xyz/testnet/tx/JATEczbhRMujdQGP7kYaj8vmYA2i4EMzT3BLgMzhsSQ3
  - feed_update (keeper posts a thin book / crash) — https://suiscan.xyz/testnet/tx/4suhsbWvXuCTwZ2oec8LYZZNoxPRjpcpE4kcpqAXJ5sn
  - **the heart** (chain reads the feed → freeze) — https://suiscan.xyz/testnet/tx/DwEojYEqLWPkNw2LVNPNKuDEhcFzvyvZxArN4y9jaSHB
  - owner exit while frozen — https://suiscan.xyz/testnet/tx/DDGNzNjcyMMVK7bDQGTkmeuqdEkCeep9KuXS733WLScz
  - open hedge (L3) — https://suiscan.xyz/testnet/tx/EvPehBHiPFmAviqT3ECGSjfmpWK9K5kdvdy7rqtyGnS3
  - settle hedge — bounded drawdown (L3) — https://suiscan.xyz/testnet/tx/F1iw1TqUDScR8UKSLbb1eUgdmCgdPEfLUCyBCtHXS7Ad
  - kyc_open (L5) — https://suiscan.xyz/testnet/tx/9DfUvb7YMGS9wmBsCchuFgr3MvSnMZzgtbHfwyCxQEyq
  - kyc_set / verify (L5) — https://suiscan.xyz/testnet/tx/2bifydHzn7amCxQ27XGLtjQt71nSSFJPCgdALo74BvbU
  - oracle_propose (L5) — https://suiscan.xyz/testnet/tx/5TZiHZcxcpS6bASbwiddQf6AzocKvGajv322oPZ4bt7S
  - oracle_finalize (L5) — https://suiscan.xyz/testnet/tx/738N3XQ5NhoeMrFDWkcEukcpk1Tg9ZRmdKEUm143653c
  - inherit_open (L6) — https://suiscan.xyz/testnet/tx/At9aN8sxcJ5PtpQEw66nnuH8mKsEozxQLTDoCXcDk38j
  - inherit_claim (L6) — https://suiscan.xyz/testnet/tx/E5mWFNNNoYiUdxbxgEJo39aSGG3kGsdoig26QJiufum8
- **Tests:** `cd contracts && sui move test` → 26/26.

## Tech stack

**Used today (in the on-chain code + agent):** Sui Move (object-capabilities, hot-potato settlement, `Clock`, events, `keccak256`), the on-chain `OracleFeed` (keeper-written price + order-book depth the guardian re-derives from), and the off-chain agent on the Claude API (`claude-opus-4-8`).

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

An **AI agent** is included — [`agent/agent.py`](agent/agent.py), a Claude (`claude-opus-4-8`) loop that reads the on-chain feed and proposes `agent_trade` under the policy. Productionizing it (sealing the reasoning to Walrus, scheduling, multi-asset) is roadmap; the trust-minimization is the point: the chain vets whatever the agent proposes.

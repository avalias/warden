# WARDEN — Sui Overflow 2026 submission

Copy-paste fields for the DeepSurge submission form.

---

**Project name:** WARDEN

**Tagline:** The autonomous AI fund you don't have to trust.

**Track:** The Agentic Web  *(sub-track: Autonomous Agent Wallet)* — also relevant to DeFi & Payments, Special-DeepBook, Special-Walrus.

**One-liner:**
> A regulated-ready, fully verifiable, non-custodial autonomous asset manager on Sui where the AI only *proposes* and the chain re-derives, clamps, freezes, and proves every move.

---

## Description

Every autonomous "AI wallet" shares one flaw: you must **trust the agent** — it holds a broad key, you trust its own risk numbers, and its reasoning is off-chain and deniable.

WARDEN inverts this. The AI emits an unsigned intent; then a deterministic, fail-closed **Guardian re-derives the risk on-chain** from raw market state, an **independent critic** signs with its own key, the agent is **clamped to the risk-reducing direction**, and on any divergence the **vault freezes** — while the owner can always withdraw. Every decision is recorded in a tamper-evident, three-proof ledger.

That single inversion turns "a cute agent" into infrastructure a regulated institution can actually fund, because trusting the agent is no longer required.

The design is organized into seven composable layers under one thesis: **trust-minimization**. This submission ships **all seven** — L0 non-custodial custody, L1 object-capability + revocation, L2 the chain-never-trusts-the-AI core, L3 a self-hedging bounded-drawdown strategy, L4 the tamper-evident ledger, L5 a closed-loop KYC gate + Move-native optimistic oracle, and L6 dead-man-switch inheritance + a no-loss commit-reveal draw — built, unit-tested, and deployed.

## What's built (and verifiable)

- **Sui Move package**, 12 modules: `vault · policy · guardian · critic · ledger · strategy · compliance · oracle · inheritance · prize · warden · app`.
- **18/18 Move unit tests passing** — the heart (freeze-on-divergence), non-custodial withdraw, capability scope, generation revocation, the L3 bounded-drawdown invariant, L5 KYC gating + the oracle window, and L6 inheritance + the no-loss draw.
- **Deployed + verified on Sui testnet** (`owner: Immutable`).
- **On-chain proof:** the **full L0→L6 lifecycle is anchored on testnet** across **12 clickable transactions**. Reproducible via `scripts/demo.sh`.

## How to verify

- **Package:** `0x98da8c3aa7fee79cd763c5a09c2f3e88a411dc9a2047e4aa177987a15b8c8a60`
  → https://suiscan.xyz/testnet/object/0x98da8c3aa7fee79cd763c5a09c2f3e88a411dc9a2047e4aa177987a15b8c8a60
- **The 12-tx lifecycle** (all on testnet):
  - open_vault — https://suiscan.xyz/testnet/tx/4QmzqjG9TrPktYWXomVopzaVok2acnksarNsx5TYxaUD
  - accepted trade — https://suiscan.xyz/testnet/tx/D1YJMb94TzYSLpYQciyMtQhwPJWNFRwQAnbcFNR5opx7
  - **the heart** (freeze-on-lie) — https://suiscan.xyz/testnet/tx/GW5tbpmLyr2VptdtRvwsugfNrLCcvNjddUadcVLR4ho5
  - owner exit while frozen — https://suiscan.xyz/testnet/tx/AThn7CAbDqEQtVL7UpYYjoXaZuH3AzMRze47wXrMikyA
  - open hedge (L3) — https://suiscan.xyz/testnet/tx/FQZ42KqP7VMMgP7MUxXAGjgqBRftcbkRDLvUHSN7Xbs9
  - settle hedge — bounded drawdown (L3) — https://suiscan.xyz/testnet/tx/B3aU6DcQ2fFnppH9jGsJg5P2DGUSfSTgSQWkZiMQfSn3
  - kyc_open (L5) — https://suiscan.xyz/testnet/tx/Hf5pmGqC3HXybnro1DLY7ttKfSD4TWZTHUFgtvuqVz8n
  - kyc_set / verify (L5) — https://suiscan.xyz/testnet/tx/oi9yq4v3zqvQdqAyjTZQ6Y5ebbFd1NCXyCSted3ir8K
  - oracle_propose (L5) — https://suiscan.xyz/testnet/tx/GeCtYRPVQxMWD8eWkz6ATWMUj6vTA4dz7Ydty2BFDF35
  - oracle_finalize (L5) — https://suiscan.xyz/testnet/tx/Syhogp8c5UC5ckCLmShsuqv8PzsVLFWY2Sj8sfdiUpt
  - inherit_open (L6) — https://suiscan.xyz/testnet/tx/A8Zm55Z9yu1aYR1pw3mNZYSuHQdMAhTfo1AM5Xnyd3Yw
  - inherit_claim (L6) — https://suiscan.xyz/testnet/tx/B5AMFKW19fmCMUxioeXMsQoD6mrK2CjfJjwEBq5TmLUw
- **Tests:** `cd contracts && sui move test` → 18/18.

## Tech stack

Sui Move (object-capabilities, hot-potato settlement), DeepBook v3 (execution / price discovery / risk re-derivation inputs), Walrus + Seal + Nautilus TEE (sealed reasoning, confidentiality, attested facts — in the architecture), zkLogin/Enoki (onboarding).

## Links

- **Repo:** https://github.com/avalias/warden
- **Site:** https://avalias.github.io/warden
- **Architecture (full 7-layer spec):** [docs/ARCHITECTURE.md](ARCHITECTURE.md)
- **Demo video script:** [docs/DEMO_SCRIPT.md](DEMO_SCRIPT.md)
- **Demo video:** _(add URL)_

## Roadmap (honestly labeled, not claimed as built)

The seven layers are built and on-chain. What remains is not a *layer* but the heaviest *integrations* inside L5/L6:

- **L5 deepening:** wire the KYC gate into compliance-gated DeepBook/CLMM venue adapters; add native **Confidential Transfers** and **Seal threshold-IBE + Nautilus/Nitro attestation** for private risk models.
- **L6 distribution:** the **x402** agent-payment rail, an **MCP** server + TS/Py/Rust SDKs, and Walrus-Sites hosting with byte-level integrity.
- A production **AI agent loop** off-chain driving `agent_trade` under the policy, with sealed reasoning stored to Walrus.

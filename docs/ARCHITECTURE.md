# WARDEN — Architecture

> **Give the machine the markets. Give the chain the leash.**

WARDEN is a regulated-ready, fully verifiable, non-custodial autonomous asset
manager on Sui. The AI never holds authority over funds — it only *proposes*.
The chain re-derives the truth, clamps the agent, freezes on divergence, and
proves every move. The result is an agent that is powerful at the markets and
structurally **powerless to do harm**.

This document specifies the design: seven composable layers under one thesis —
**trust-minimization** — and the thirteen Move modules that implement them.

---

## The thesis

Every autonomous "AI wallet" shares one flaw: you must **trust the agent**. It
holds a broad key, you trust its own risk numbers, and its reasoning is
off-chain and deniable.

WARDEN inverts this. Authority is an *object*, not a key. Risk is re-computed
*on-chain*, not taken on the agent's word. Reasoning and outcomes are *anchored*,
not asserted. Compliance and continuity are *enforced by the protocol*, not by a
back office. Every layer below exists to make that single inversion real, and
each is load-bearing — remove one and the guarantee weakens.

---

## The seven layers

### L0 — Non-custodial custody
Funds live inside a user-owned `Vault` as a real `Balance<T>`. The agent steers
**real capital** between `idle` and `deployed` (NAV = `idle + deployed`, always
conserved — funds never leave the vault object); the **only** path that *removes*
capital is the `OwnerCap`, and it works even while the agent is frozen. Freezing
halts the agent — it never blocks the owner.
*Module: `vault`.*

### L1 — Authority is an object, not a key
The agent holds a non-transferable `WardenPolicy` (a `key`-only capability with
no `store` ability) bounded by per-tx cap, rolling-window cap, reserve floor and
expiry. A `GenerationRegistry` is a revocation lattice: bump the generation and
every policy of an older generation dies in a single transaction.
*Module: `policy`.*

### L2 — The chain never trusts the AI  ♥ (the heart)
The AI proposes an unsigned intent. A deterministic, fail-closed **Guardian
re-derives the risk on-chain** from raw market state, clamps the agent to the
risk-reducing direction inside a danger zone, and rejects fills above a hard
ceiling. A **critic capability** (`CriticCap`) — a separable approval identity,
held by the owner in the single-operator demo and by a distinct critic signer in
the intended multi-party deployment — co-signs the proposal over a digest
**derived on-chain** from the trade contents, so its approval is bound to exactly
what was proposed. If the chain's re-derivation diverges from the agent's claim,
the **vault freezes** and only governance can lift it.
*Modules: `guardian`, `critic`.*

### L3 — Structured-product engine (it hedges itself)
A `HedgedCarry` position earns carry over time and holds a downside hedge. Below
the strike the hedge payout offsets further spot losses (up to integer rounding),
so the **maximum drawdown is bounded by construction** — verified by the
`test_drawdown_is_bounded` unit test, and the `Settled` event carries both the
realized magnitude and the drawdown floor for on-chain checking.
*Module: `strategy`.*

### L4 — Verifiable, tamper-evident record
Every decision is appended to a monotonic, **non-backdated, no-delete, keccak
hash-chained** ledger — you cannot drop or forge an entry without breaking the
chain — and each trade digest is **replay-protected**. Each entry carries a
three-proof receipt (the Sui tx digest, plus Walrus-blob and TEE-attestation
placeholder fields). Rejected attempts are recorded too.
*Module: `ledger`.*

### L5 — Compliance & confidentiality (institution-ready)
A closed-loop **KYC registry** gates regulated value so it only moves between
verified holders, with an auditor capability for read-only oversight. A
**Move-native optimistic oracle** resolves real-world outcomes with a challenge
window: propose with a bond, dispute while the window is open, finalize when it
closes, escalate disputes to a resolver.
*Modules: `compliance`, `oracle`.*

### L6 — Continuity, governance & distribution
A **dead-man-switch** keeps an asset the owner's via a heartbeat; after a
dormancy period a named beneficiary inherits control. A **no-loss prize draw**
selects a winner by commit-reveal (`keccak256`), with principal preserved by
construction.
*Modules: `inheritance`, `prize`.*

### Orchestration
A trade is a Move **hot potato** (`Trade`, no abilities): once the AI proposes
it, it must pass policy → critic → guardian and be settled in the **same**
transaction, or the transaction does not type-check. Funds never leave the vault;
the agent only steers within the leash.
*Modules: `warden` (orchestrator), `app` (CLI/PTB entry points).*

---

## Anatomy of one trade

```
🧠 propose → ⛓️ re-derive → ⚖️ critic → 🛡️ clamp → 🧊 (or freeze) → ⚡ execute → 🔏 attest
   AI emits    Guardian       2nd agent   safe-dir +   divergence →    notional      Recorded
   intent      recomputes     own key     ceiling      vault freezes   only          + receipt
```

The agent never touches money directly. Five gates stand between intent and
execution — policy, critic, guardian, the vault freeze, and the ledger record;
any divergence freezes the position and records the rejection.

---

## Why Sui / Move

- **Object model** — capabilities, vaults, ledgers and registries are first-class
  objects with owners, not rows in a contract's storage.
- **Abilities** — `key`-without-`store` makes a capability non-transferable;
  a struct with *no* abilities becomes a hot potato that cannot be dropped or
  stored, only discharged. These give protocol guarantees at the type level.
- **`Clock`** — on-chain time powers the oracle window, the dead-man-switch
  dormancy, and the non-backdated ledger.
- **PTB** (programmable transaction blocks) — compose propose-and-settle
  atomically so the gates cannot be skipped.

---

## Engineering rigor

- **43/43 Move unit tests** — the heart (direct guardian coverage: the risk
  arithmetic, the divergence boundary, the hard ceiling, and the safe-direction
  clamp both ways), every gate's negative path (L1 per-tx / window / expiry /
  pause / wrong-vault, L2 critic veto + wrong identity, L4 monotonic append, L0
  reserve floor / frozen / owner-only / unfreeze), freeze-on-divergence,
  non-custodial withdraw, generation revocation, the L3 bounded-drawdown
  invariant, L5 KYC gating + the oracle window, and L6 inheritance + the
  no-loss draw.
- **Deployed + verified on Sui testnet**, with the full L0→L6 lifecycle anchored
  on-chain across **15 clickable transactions** and reproducible via
  `scripts/demo.sh`. The `UpgradeCap` has been **burned** — the package is
  immutable; even the deployer cannot change the leash.
- Transparent commit history; deployed package matches the source.

---

## What's built vs. roadmap (stated honestly)

**Built, tested, deployed, on-chain:** all seven layers (13 modules), every
primitive unit-tested, the full L0→L6 lifecycle in 15 transactions on Sui
testnet. The off-chain AI agent (`agent/agent.py`, LLM-powered) is built and
proposes `agent_trade` under the policy.

**Roadmap** — not a *layer*, but the heaviest *integrations* inside L5/L6: full
Seal threshold-IBE, Nautilus/Nitro TEE attestation, native Confidential
Transfers, an x402 agent-payment rail with an MCP server + SDKs, and sealing the
agent's reasoning to Walrus. (Deployment is on testnet; mainnet-ready.)

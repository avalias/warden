<div align="center">

# 🛡️ WARDEN

### The autonomous AI fund you don't have to trust.

**Give the machine the markets. Give the chain the leash.**
*Машине — рынки. Цепи — поводок.*

[![Sui Overflow 2026](https://img.shields.io/badge/Sui_Overflow-2026-4da2ff?style=flat-square)](https://sui.io)
[![Track](https://img.shields.io/badge/Track-The_Agentic_Web-37e0ac?style=flat-square)](#)
[![Testnet](https://img.shields.io/badge/testnet-deployed_%26_verified-2ecc71?style=flat-square)](https://suiscan.xyz/testnet/object/0xe65932ac7cba6db749d3deea0a6fbaeb0ea4fb64f7bcbb2b8446cb112fc736dc)
[![Move tests](https://img.shields.io/badge/move_tests-41%2F41_passing-2ecc71?style=flat-square)](#-tests)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)

[**Live site**](https://avalias.github.io/warden) · [**Live dApp**](https://avalias.github.io/warden/app/) · [**Architecture**](docs/ARCHITECTURE.md) · [**On-chain proof**](#-proven-on-chain-testnet) · [**Contracts**](contracts/sources)

</div>

---

## The one idea

Every autonomous "AI wallet" asks you to **trust the agent** — it holds a broad key, you trust its own risk numbers, its reasoning is off-chain and deniable.

**WARDEN inverts this.** The AI only *proposes*. The chain *re-derives the truth, clamps the agent, freezes on divergence, and proves every move*. The agent is powerful — and structurally **powerless to do harm**.

That single inversion turns "a cute agent" into **infrastructure a regulated institution can legally fund** — because trusting the agent is no longer required.

---

## ✅ Proven on-chain (testnet)

This is not a mock. The package is deployed and verified, and the full lifecycle has been executed on Sui testnet — including the heart of the design: **the chain catching the agent in a lie and freezing the vault.**

| | Value |
|---|---|
| **Package** | [`0xe65932ac7cba6db749d3deea0a6fbaeb0ea4fb64f7bcbb2b8446cb112fc736dc`](https://suiscan.xyz/testnet/object/0xe65932ac7cba6db749d3deea0a6fbaeb0ea4fb64f7bcbb2b8446cb112fc736dc) |
| **Network** | Sui testnet (`chain-id 4c78adac`) · deployed & source-verified |
| **Modules** | `vault · policy · guardian · critic · ledger · strategy · feed · compliance · oracle · inheritance · prize · warden · app` |

**Don't trust it — click it:**

| Step | What it proves | Transaction |
|---|---|---|
| `open_vault` | Non-custodial vault + revocation/critic registries + hash-chained ledger created | [`AMrkW41h…`](https://suiscan.xyz/testnet/tx/AMrkW41hV29bumhxHkWzg8AZiLawC6bPy21LREh3sGkR) |
| `feed_open` / `feed_update` | **Market-data integrity** — a keeper posts price + order-book depth to a shared on-chain feed the agent **cannot forge**; the Guardian reads *this*, never a caller-supplied number | [`5MdGhMu7…`](https://suiscan.xyz/testnet/tx/5MdGhMu7gu9LqnFdEnF7J9iLXEfipkMgoMhXLmLrkwTp) · [`3iThjDcC…`](https://suiscan.xyz/testnet/tx/3iThjDcCtQvTDE61KC7akytXkMcZdA7LHG1Jts19iU57) |
| `agent_trade` ✅ | A valid trade clears all five gates (Guardian reads the deep-book feed) → `Recorded{accepted:true, seq:1}` | [`3xe3ZTwy…`](https://suiscan.xyz/testnet/tx/3xe3ZTwyXsbYN1o8bc9Dx6RpuE3cK5A5aFaM71ASpUeN) |
| `feed_update` 📉 | The keeper posts a **thin order book** (a crash) to the feed | [`FazP2eW8…`](https://suiscan.xyz/testnet/tx/FazP2eW81Fg1B7xLkDmRPLcXAFaxQDdwhNmPiNxDfhaW) |
| `agent_trade` 🧊 | **The heart.** The agent still claims `risk=0`; the chain re-derives risk **from the feed** (not the agent), gets `10000bps`, catches the lie → **`VaultFrozen`** + `Recorded{accepted:false, seq:2}` | [`AtjSozeL…`](https://suiscan.xyz/testnet/tx/AtjSozeLGYdgAR7efSqQCgpTMoewWAyYUPisx8Ez9Thb) |
| `owner_exit` | Owner withdraws **even while frozen** → `Withdrawn` (non-custodial) | [`DPFwzNt6…`](https://suiscan.xyz/testnet/tx/DPFwzNt62ecpL8ye981ReEDE9ikRXCbRNpYrdrQ3FWK4) |
| `open_hedge` | **L3** — opens a self-hedging carry position over the vault notional | [`5vHuVv7z…`](https://suiscan.xyz/testnet/tx/5vHuVv7zx151bDEbrQCXNkAMxnKa8ksyFhN2qt6He9zG) |
| `settle_hedge` | **L3** — settles at a crash price → `Settled{ magnitude 5001950 ≤ drawdown_floor 5002000 }` (loss bounded by construction, on-chain) | [`5VCMrBho…`](https://suiscan.xyz/testnet/tx/5VCMrBhoDoj6aur7rcGJwW7VCeVsoC5nG7hRtkuX3FdU) |
| `kyc_open` / `kyc_set` | **L5** — open a closed-loop KYC registry and verify a holder (protocol-level compliance) | [`FwnwGcw5…`](https://suiscan.xyz/testnet/tx/FwnwGcw53bJt9gd9yTDQyauP8k35uukzyT6bxe1moFPb) · [`583MyhQK…`](https://suiscan.xyz/testnet/tx/583MyhQKn6iHYzwSQCU2viEoKc3XeHVeHoKhQ6uLgWek) |
| `oracle_propose` → `oracle_finalize` | **L5** — propose an outcome with a challenge window; finalize once it closes (Move-native optimistic oracle) | [`Chu8hy4T…`](https://suiscan.xyz/testnet/tx/Chu8hy4THzMZnUeFq8C8At2VUbUqacpMPQtqv6ztwRyR) · [`CXi2xuVi…`](https://suiscan.xyz/testnet/tx/CXi2xuVithoDhwK5jFKmfJMg9RwAMyvXrPQTE4BHohyz) |
| `inherit_open` → `inherit_claim` | **L6** — dead-man-switch: open with a dormancy timer; after it elapses the beneficiary inherits → **`Inherited`** | [`FrUpWum8…`](https://suiscan.xyz/testnet/tx/FrUpWum8JJrf2KPUdEVuQQ4ucGB55Hpen46MUAe8M8bk) · [`BizxznXJ…`](https://suiscan.xyz/testnet/tx/BizxznXJ6fzDhLr842ocVjEVSwDWnT4VSgepNav5RFFJ) |

**All seven layers are anchored on-chain** across these 15 transactions, reproducible via [`scripts/demo.sh`](scripts/demo.sh), and covered by the **41/41 Move unit tests**.

---

## 🏛️ Architecture — seven layers, one leash

Each layer is **load-bearing under a single thesis** (trust-minimization) — not a feature dump. **Layer 2 is the heart: the chain never trusts the AI.** Full spec in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

```
        ↑  THE CHAIN IS THE REFEREE · NON-CUSTODIAL · THE AGENT NEVER HOLDS THE LEASH  ↑
  ┌──────────────────────────────────────────────────────────────────────────────────┐
  │ L6  Continuity & distribution — dead-man-switch · no-loss prize           ◀ built │
  │ L5  Compliance & confidentiality — KYC gate · optimistic oracle           ◀ built │
  │ L4  Verifiable record — three-proof receipts · hash-chained ledger        ◀ built │
  │ L3  Structured-product engine — self-hedging, bounded drawdown            ◀ built │
  │ L2 ♥ THE CHAIN NEVER TRUSTS THE AI — re-derive · clamp · critic · freeze   ◀ built │
  │ L1  Authority is an object, not a key — object-capability + revocation     ◀ built │
  │ L0  Non-custodial custody — user-owned vault · no-withdraw boundary        ◀ built │
  └──────────────────────────────────────────────────────────────────────────────────┘
```

This repo ships **all seven layers** — built, unit-tested (41/41), and deployed, with the full L0→L6 lifecycle anchored on-chain in 15 transactions. (L5/L6 ship their core on-chain primitives — KYC gating, optimistic oracle, dead-man-switch, no-loss draw; the full confidentiality stack — Seal/Nautilus/Confidential-Transfers — remains an integration roadmap.)

### How a single trade survives the chain

```
🧠 propose → ⛓️ re-derive → ⚖️ critic → 🛡️ clamp → 🧊 (or freeze) → ⚡ execute → 🔏 attest
   AI emits    guardian       2nd agent   safe-dir +   divergence →    notional      Recorded
   intent      recomputes     own key     risk ceiling vault freezes   only          + receipt
```

The `Trade` is a Move **hot potato** (no abilities): once proposed it *must* pass policy + guardian + critic and be settled in the same transaction, or the transaction does not type-check.

---

## 🤖 The AI agent

[`agent/agent.py`](agent/agent.py) is the agent half of the fund: a **Claude-powered** loop (`claude-opus-4-8`, structured outputs) that reads the on-chain market feed and vault state, reasons about a trade within the policy bounds, and submits an `agent_trade` proposal.

The point of the whole architecture is that this agent is *untrusted*. Whatever Claude decides — even a hallucinated or mis-calibrated risk number — the on-chain Guardian re-derives risk from the same feed and freezes the vault on divergence. The agent proposes; the chain disposes.

```bash
export ANTHROPIC_API_KEY=...                       # never hardcoded
pip install -r agent/requirements.txt
python agent/agent.py --config warden.config.json            # dry-run (prints the decision)
python agent/agent.py --config warden.config.json --submit   # send it; the chain vets it
```

---

## 📂 Repo layout

```
warden/
├── index.html              # tier-1 landing page (zero build; == web/)
├── logo.svg
├── contracts/              # Sui Move package
│   ├── Move.toml
│   ├── Published.toml      # on-chain publication record (committed)
│   ├── sources/
│   │   ├── vault.move      # L0  non-custodial custody
│   │   ├── policy.move     # L1  object-capability + revocation lattice
│   │   ├── guardian.move   # L2  on-chain risk re-derivation (the heart)
│   │   ├── critic.move     # L2  independent critic, its own identity
│   │   ├── feed.move       # L2  on-chain market feed (keeper-fed, agent-proof)
│   │   ├── ledger.move     # L4  append-only three-proof record
│   │   ├── strategy.move    # L3  self-hedging carry, bounded drawdown
│   │   ├── compliance.move  # L5  closed-loop KYC gate + auditor cap
│   │   ├── oracle.move      # L5  Move-native optimistic oracle
│   │   ├── inheritance.move # L6  dead-man-switch inheritance
│   │   ├── prize.move       # L6  no-loss commit-reveal prize draw
│   │   ├── warden.move     # orchestrator (hot-potato Trade flow)
│   │   └── app.move        # entry points (CLI/PTB-callable)
│   └── tests/  warden_tests · guardian_tests · strategy_tests · l5_l6_tests
├── app/                    # interactive dApp (live dashboard + wallet actions)
├── agent/                  # the Claude-powered trading agent (agent.py)
├── scripts/                # deploy.sh + demo.sh (reproduce the on-chain run)
├── docs/ARCHITECTURE.md    # full 7-layer architecture spec
└── web/                    # same landing page, for separate hosting
```

---

## 🧪 Tests

```bash
cd contracts
sui move test
```

```
[ PASS ] test_happy_path                          # a valid trade clears all gates
[ PASS ] test_divergence_freezes_and_records      # the heart: chain catches the lie, freezes, records
[ PASS ] test_owner_withdraw_works_even_when_frozen  # non-custodial guarantee
[ PASS ] test_per_tx_cap_breach_aborts            # capability scope is enforced
[ PASS ] test_revocation_kills_policy             # one tx revokes the whole generation
[ PASS ] test_derive_known_triples                # L2 heart: risk arithmetic on known triples
[ PASS ] test_divergence_boundary                 # L2 heart: 200bps divergence tolerance boundary
[ PASS ] test_ceiling_fault                       # L2 heart: hard ceiling rejects > 7000bps
[ PASS ] test_unsafe_dir_increase_freezes         # L2 heart: clamp blocks a risk-increasing trade
[ PASS ] test_unsafe_dir_reduce_accepts           # L2 heart: de-risking is allowed in the danger zone
[ PASS ] test_extreme_inputs_saturate             # L2 heart: extreme inputs saturate, never overflow
[ PASS ] test_carry_accrues_linearly              # L3: carry accrues over time
[ PASS ] test_hedge_pays_below_strike_only        # L3: the put pays below strike
[ PASS ] test_drawdown_is_bounded                 # L3: max loss is bounded by construction
[ PASS ] test_kyc_gates_recipients                # L5: KYC verify / revoke
[ PASS ] test_unverified_recipient_aborts         # L5: gated transfer blocks non-verified
[ PASS ] test_oracle_finalizes_after_window       # L5: optimistic oracle window
[ PASS ] test_oracle_finalize_before_window_aborts# L5: cannot finalize early
[ PASS ] test_oracle_dispute_then_resolver_decides# L5: dispute → resolver decides
[ PASS ] test_inheritance_claim_after_dormancy    # L6: beneficiary inherits after dormancy
[ PASS ] test_inheritance_claim_too_early_aborts  # L6: cannot claim early
[ PASS ] test_inheritance_ping_resets_clock       # L6: a ping resets the timer
[ PASS ] test_prize_commit_reveal_draw_no_loss    # L6: verifiable draw, principal preserved
[ PASS ] test_prize_bad_reveal_aborts             # L6: reveal must match the commit
[ PASS ] test_feed_stale_read_aborts              # oracle feed: stale data is rejected
[ PASS ] test_feed_only_feeder_updates            # oracle feed: only the keeper can write
[ PASS ] test_window_cap_trips                    # L1: rolling-window cap enforced
[ PASS ] test_window_resets_after_window_ms       # L1: window resets after window_ms
[ PASS ] test_policy_expiry_aborts                # L1: an expired policy is rejected
[ PASS ] test_paused_blocks_spend                 # L1: pause halts the agent
[ PASS ] test_policy_wrong_vault_aborts           # L1: a policy is bound to its vault
[ PASS ] test_critic_approval_returns_digest      # L2: critic approval binds the trade digest
[ PASS ] test_critic_rejection_aborts_settlement  # L2: the critic veto blocks settlement
[ PASS ] test_unsanctioned_critic_aborts          # L2: only the sanctioned critic counts
[ PASS ] test_ledger_seq_is_monotonic_no_delete   # L4: monotonic append, no delete path
[ PASS ] test_deploy_respects_reserve_floor       # L0: the reserve floor is enforced
[ PASS ] test_deploy_blocked_while_frozen         # L0: a frozen vault blocks the agent
[ PASS ] test_withdraw_rejects_wrong_cap          # L0: only the right OwnerCap withdraws
[ PASS ] test_unfreeze_restores_agent             # L0: owner unfreeze restores the agent
[ PASS ] test_critic_must_sign_the_real_digest    # L2: critic must sign the on-chain-derived digest
[ PASS ] test_ledger_rejects_replayed_digest      # L4: a replayed trade digest is rejected
Test result: OK. Total tests: 41; passed: 41; failed: 0
```

---

## 🚀 Build · deploy · run

```bash
# build + test
cd contracts && sui move build && sui move test

# deploy to testnet (writes Published.toml)
sui client publish --gas-budget 100000000

# run the full lifecycle on-chain (open → trade → freeze → exit)
cd ../scripts && ./demo.sh
```

Serve the landing page (zero build):

```bash
python -m http.server 4178   # → http://localhost:4178
# deploy: Walrus Sites (`site-builder publish .`), GitHub Pages, Vercel, …
```

---

## 📊 Why it holds up

- **Real-world application.** A construction a regulated institution can actually fund, because trusting the agent isn't required — the chain structurally prevents theft (non-custodial + object-capability), mis-allocation (on-chain risk re-derivation from a feed the agent can't forge → clamp → freeze), and misreporting (a keccak **hash-chained**, no-delete three-proof ledger, with the trade digest derived on-chain). Compliance (L5) and inheritance (L6) make it institution- and continuity-ready.
- **Technical depth.** A load-bearing stack of Sui primitives — object-capabilities with hot-potato enforcement, a revocation lattice, on-chain risk re-derivation against a keeper-fed oracle, a dual-key critic, a proven bounded-drawdown, a Move-native optimistic oracle, a dead-man-switch and a verifiable draw — composed under one thesis, deployed and proven on-chain.

**Honest scope:** all **seven layers** are built, unit-tested (41/41), deployed, and anchored on-chain. What remains a roadmap is not a *layer* but the heaviest *integrations* inside L5/L6 — full Seal threshold-IBE, Nautilus/Nitro attestation, native Confidential Transfers, and the x402/MCP distribution surface — specified in the architecture doc and not claimed as shipped. Every on-chain primitive here is real, tested, and clickable.

---

## License

MIT — see [LICENSE](LICENSE).

<div align="center">

*Sui Overflow 2026 · The Agentic Web (Autonomous Agent Wallet)*
**Seven composable layers under one thesis: trust-minimization.**

</div>

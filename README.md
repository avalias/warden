<div align="center">

# 🛡️ WARDEN

### The autonomous AI fund you don't have to trust.

**Give the machine the markets. Give the chain the leash.**
*Машине — рынки. Цепи — поводок.*

[![Sui Overflow 2026](https://img.shields.io/badge/Sui_Overflow-2026-4da2ff?style=flat-square)](https://sui.io)
[![Track](https://img.shields.io/badge/Track-The_Agentic_Web-37e0ac?style=flat-square)](#)
[![Testnet](https://img.shields.io/badge/testnet-deployed_%26_verified-2ecc71?style=flat-square)](https://suiscan.xyz/testnet/object/0x823f8490c1ce2d576a4d3ed3631fda93d7327f4daaea4fe6ecabf8ea64826902)
[![Move tests](https://img.shields.io/badge/move_tests-20%2F20_passing-2ecc71?style=flat-square)](#-tests)
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
| **Package** | [`0x823f8490c1ce2d576a4d3ed3631fda93d7327f4daaea4fe6ecabf8ea64826902`](https://suiscan.xyz/testnet/object/0x823f8490c1ce2d576a4d3ed3631fda93d7327f4daaea4fe6ecabf8ea64826902) |
| **Network** | Sui testnet (`chain-id 4c78adac`) · `owner: Immutable` ✓ |
| **Modules** | `vault · policy · guardian · critic · ledger · strategy · feed · compliance · oracle · inheritance · prize · warden · app` |

**Don't trust it — click it:**

| Step | What it proves | Transaction |
|---|---|---|
| `open_vault` | Non-custodial vault + revocation/critic registries + tamper-evident ledger created | [`4KFjVaGo…`](https://suiscan.xyz/testnet/tx/4KFjVaGoGaQyW6wArhTH3xsPNViyR3Tc8nR3rdhz7Mav) |
| `feed_open` / `feed_update` | **Market-data integrity** — a keeper posts price + order-book depth to a shared on-chain feed the agent **cannot forge**; the Guardian reads *this*, never a caller-supplied number | [`9v9okf2N…`](https://suiscan.xyz/testnet/tx/9v9okf2NxDiq3RRjD4jUXWyD4LHjzapWGHMVPuFUWVdV) · [`B1MraJK5…`](https://suiscan.xyz/testnet/tx/B1MraJK5ZPT7qVm8VGtkvMigouZTC11711zmrDxmDxai) |
| `agent_trade` ✅ | A valid trade clears all five gates (Guardian reads the deep-book feed) → `Recorded{accepted:true, seq:1}` | [`JATEczbh…`](https://suiscan.xyz/testnet/tx/JATEczbhRMujdQGP7kYaj8vmYA2i4EMzT3BLgMzhsSQ3) |
| `feed_update` 📉 | The keeper posts a **thin order book** (a crash) to the feed | [`4suhsbWv…`](https://suiscan.xyz/testnet/tx/4suhsbWvXuCTwZ2oec8LYZZNoxPRjpcpE4kcpqAXJ5sn) |
| `agent_trade` 🧊 | **The heart.** The agent still claims `risk=0`; the chain re-derives risk **from the feed** (not the agent), gets `10000bps`, catches the lie → **`VaultFrozen`** + `Recorded{accepted:false, seq:2}` | [`DwEojYEq…`](https://suiscan.xyz/testnet/tx/DwEojYEqLWPkNw2LVNPNKuDEhcFzvyvZxArN4y9jaSHB) |
| `owner_exit` | Owner withdraws **even while frozen** → `Withdrawn` (non-custodial) | [`DDGNzNjc…`](https://suiscan.xyz/testnet/tx/DDGNzNjcyMMVK7bDQGTkmeuqdEkCeep9KuXS733WLScz) |
| `open_hedge` | **L3** — opens a self-hedging carry position over the vault notional | [`EvPehBHi…`](https://suiscan.xyz/testnet/tx/EvPehBHiPFmAviqT3ECGSjfmpWK9K5kdvdy7rqtyGnS3) |
| `settle_hedge` | **L3** — settles at a crash price → `Settled{ magnitude 5001950 ≤ drawdown_floor 5002000 }` (loss bounded by construction, on-chain) | [`F1iw1TqU…`](https://suiscan.xyz/testnet/tx/F1iw1TqUDScR8UKSLbb1eUgdmCgdPEfLUCyBCtHXS7Ad) |
| `kyc_open` / `kyc_set` | **L5** — open a closed-loop KYC registry and verify a holder (protocol-level compliance) | [`9DfUvb7Y…`](https://suiscan.xyz/testnet/tx/9DfUvb7YMGS9wmBsCchuFgr3MvSnMZzgtbHfwyCxQEyq) · [`2bifydHz…`](https://suiscan.xyz/testnet/tx/2bifydHzn7amCxQ27XGLtjQt71nSSFJPCgdALo74BvbU) |
| `oracle_propose` → `oracle_finalize` | **L5** — propose an outcome with a challenge window; finalize once it closes (Move-native optimistic oracle) | [`5TZiHZcx…`](https://suiscan.xyz/testnet/tx/5TZiHZcxcpS6bASbwiddQf6AzocKvGajv322oPZ4bt7S) · [`738N3XQ5…`](https://suiscan.xyz/testnet/tx/738N3XQ5NhoeMrFDWkcEukcpk1Tg9ZRmdKEUm143653c) |
| `inherit_open` → `inherit_claim` | **L6** — dead-man-switch: open with a dormancy timer; after it elapses the beneficiary inherits → **`Inherited`** | [`At9aN8sx…`](https://suiscan.xyz/testnet/tx/At9aN8sxcJ5PtpQEw66nnuH8mKsEozxQLTDoCXcDk38j) · [`E5mWFNNN…`](https://suiscan.xyz/testnet/tx/E5mWFNNNoYiUdxbxgEJo39aSGG3kGsdoig26QJiufum8) |

**All seven layers are anchored on-chain** across these 15 transactions, reproducible via [`scripts/demo.sh`](scripts/demo.sh), and covered by the **20/20 Move unit tests**.

---

## 🏛️ Architecture — seven layers, one leash

Each layer is **load-bearing under a single thesis** (trust-minimization) — not a feature dump. **Layer 2 is the heart: the chain never trusts the AI.** Full spec in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

```
        ↑  THE CHAIN IS THE REFEREE · NON-CUSTODIAL · THE AGENT NEVER HOLDS THE LEASH  ↑
  ┌──────────────────────────────────────────────────────────────────────────────────┐
  │ L6  Continuity & distribution — dead-man-switch · no-loss prize           ◀ built │
  │ L5  Compliance & confidentiality — KYC gate · optimistic oracle           ◀ built │
  │ L4  Verifiable record — three-proof receipts · tamper-evident ledger      ◀ built │
  │ L3  Structured-product engine — self-hedging, bounded drawdown            ◀ built │
  │ L2 ♥ THE CHAIN NEVER TRUSTS THE AI — re-derive · clamp · critic · freeze   ◀ built │
  │ L1  Authority is an object, not a key — object-capability + revocation     ◀ built │
  │ L0  Non-custodial custody — user-owned vault · no-withdraw boundary        ◀ built │
  └──────────────────────────────────────────────────────────────────────────────────┘
```

This repo ships **all seven layers** — built, unit-tested (20/20), and deployed, with the full L0→L6 lifecycle anchored on-chain in 15 transactions. (L5/L6 ship their core on-chain primitives — KYC gating, optimistic oracle, dead-man-switch, no-loss draw; the full confidentiality stack — Seal/Nautilus/Confidential-Transfers — remains an integration roadmap.)

### How a single trade survives the chain

```
🧠 propose → ⛓️ re-derive → ⚖️ critic → 🛡️ clamp → 🧊 (or freeze) → ⚡ execute → 🔏 attest
   AI emits    guardian       2nd agent   safe-dir +   divergence →    notional      Recorded
   intent      recomputes     own key     SVI ceiling  vault freezes   only          + receipt
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
│   │   ├── ledger.move     # L4  tamper-evident three-proof record
│   │   ├── strategy.move    # L3  self-hedging carry, bounded drawdown
│   │   ├── compliance.move  # L5  closed-loop KYC gate + auditor cap
│   │   ├── oracle.move      # L5  Move-native optimistic oracle
│   │   ├── inheritance.move # L6  dead-man-switch inheritance
│   │   ├── prize.move       # L6  no-loss commit-reveal prize draw
│   │   ├── warden.move     # orchestrator (hot-potato Trade flow)
│   │   └── app.move        # entry points (CLI/PTB-callable)
│   └── tests/  warden_tests · strategy_tests · l5_l6_tests
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
Test result: OK. Total tests: 20; passed: 20; failed: 0
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

- **Real-world application.** A construction a regulated institution can actually fund, because trusting the agent isn't required — the chain structurally prevents theft (non-custodial + object-capability), mis-allocation (on-chain risk re-derivation from a feed the agent can't forge → clamp → freeze), and misreporting (tamper-evident three-proof ledger). Compliance (L5) and inheritance (L6) make it institution- and continuity-ready.
- **Technical depth.** A load-bearing stack of Sui primitives — object-capabilities with hot-potato enforcement, a revocation lattice, on-chain risk re-derivation against a keeper-fed oracle, a dual-key critic, a proven bounded-drawdown, a Move-native optimistic oracle, a dead-man-switch and a verifiable draw — composed under one thesis, deployed and proven on-chain.

**Honest scope:** all **seven layers** are built, unit-tested (20/20), deployed, and anchored on-chain. What remains a roadmap is not a *layer* but the heaviest *integrations* inside L5/L6 — full Seal threshold-IBE, Nautilus/Nitro attestation, native Confidential Transfers, and the x402/MCP distribution surface — specified in the architecture doc and not claimed as shipped. Every on-chain primitive here is real, tested, and clickable.

---

## License

MIT — see [LICENSE](LICENSE).

<div align="center">

*Sui Overflow 2026 · The Agentic Web (Autonomous Agent Wallet)*
**Seven composable layers under one thesis: trust-minimization.**

</div>

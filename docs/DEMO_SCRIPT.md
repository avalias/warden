# WARDEN — 2.5-minute demo video script

Goal: show the one idea (the chain holds the leash) and **prove it live** — the
chain catching the agent in a lie and freezing the vault, on testnet.

Tooling on screen: the landing page, a terminal with `sui` CLI, and Suiscan.

---

### Scene 1 — The problem (0:00–0:20)
**On screen:** landing page hero (`index.html`).
**Narration:**
> "Every autonomous AI wallet has the same flaw: you have to *trust the agent*.
> It holds a broad key, you trust its own risk numbers, and its reasoning is
> off-chain and deniable. WARDEN flips that."

### Scene 2 — The inversion (0:20–0:45)
**On screen:** scroll to "The inversion" (✕ default vs ✓ WARDEN), then the
7-layer stack; pause on **Layer 2 — the heart**.
**Narration:**
> "The AI only *proposes*. The chain re-derives the truth, clamps the agent,
> freezes on divergence, and proves every move. Seven layers, one thesis:
> trust-minimization. Five of them are built and deployed today."

### Scene 3 — The heart, LIVE (0:45–1:35)  ← the money shot
**On screen:** terminal. Run the freeze trade where the agent lies (claims
`risk=0`, thin order book):
```bash
sui client call --package 0x823f84…6902 --module app --function agent_trade \
  --args $VAULT $POLICY $REG $CREG $CCAP $LEDGER 3000000 1 0 1000000 1000 \
         0x6c6965 0x77616c727573 0x746565 0x6 --gas-budget 14000000
```
**Narration:**
> "Watch. The agent proposes a trade and *claims* the risk is zero. But the
> Guardian re-derives risk on-chain from the raw order book — and gets ten
> thousand basis points. The numbers diverge. The chain doesn't argue —"
**On screen:** cut to Suiscan tx
[`DwEojYEq…`](https://suiscan.xyz/testnet/tx/DwEojYEqyr2VptdtRvwsugfNrLCcvNjddUadcVLR4ho5),
highlight the `VaultFrozen` and `Recorded{accepted:false}` events.
**Narration:**
> "— it freezes the vault. The agent is now powerless. And notice: even the
> independent critic had approved this trade. The chain still caught it."

### Scene 4 — Non-custodial (1:35–2:00)
**On screen:** the `test_owner_withdraw_works_even_when_frozen` test passing
(`sui move test`), and the `owner_exit` code in `app.move`.
**Narration:**
> "The freeze stops the agent — never the owner. The withdraw path is gated by
> the owner capability and works even while frozen. Your funds are never the
> agent's to take."

### Scene 5 — It hedges itself (2:00–2:25)
**On screen:** `strategy.move` + the `test_drawdown_is_bounded` test.
**Narration:**
> "Layer 3 is a self-hedging carry position. Below the hedge strike, the payout
> exactly offsets further losses — so the maximum drawdown is *bounded by
> construction*, and we prove it on-chain, not in a pitch deck."

### Scene 6 — Compliant, and it outlives you (L5/L6) (2:25–2:55)
**On screen:** the proof section's L5/L6 rows; quick cuts to the
`kyc_set`, `oracle_finalize`, and `inherit_claim` transactions on Suiscan.
**Narration:**
> "It's institution-ready: a closed-loop KYC gate means regulated value only
> moves between verified holders, and a Move-native optimistic oracle settles
> outcomes with a challenge window. And it outlives its owner — a dead-man-switch
> hands the position to a named beneficiary after dormancy. All on-chain."

### Scene 7 — Recap (2:55–3:15)
**On screen:** the proof section (15 transactions) + the GitHub repo.
**Narration:**
> "All seven layers — built, twenty passing Move tests, and the full lifecycle
> anchored on-chain across fifteen transactions. Seven composable layers under one
> thesis. Give the machine the markets. Give the chain the leash. That's WARDEN."

---

**Lower-thirds / links to show:**
- Package: `0x823f8490c1ce2d576a4d3ed3631fda93d7327f4daaea4fe6ecabf8ea64826902`
- Repo: github.com/avalias/warden · Site: avalias.github.io/warden
- The heart tx: `DwEojYEq…` · L5 oracle: `738N3XQ5…` · L6 inherit: `E5mWFNNN…`

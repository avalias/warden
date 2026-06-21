/// Entry points — the CLI/PTB-callable surface that wires the WARDEN
/// primitives into a usable app. Typed to `SUI` for a clean demo; the
/// underlying `vault::Vault<T>` is generic.
module warden::app;

use sui::coin::Coin;
use sui::clock::Clock;
use sui::sui::SUI;
use warden::vault;
use warden::policy;
use warden::critic;
use warden::ledger;
use warden::warden;
use warden::strategy::{Self, HedgedCarry};
use warden::compliance::{Self, KycRegistry};
use warden::oracle::{Self, Claim};
use warden::inheritance::{Self, Switch};
use warden::feed::{Self, OracleFeed};

/// Open a non-custodial vault funded by `seed`, wire its revocation
/// registry, critic registry and tamper-evident ledger, share the shared
/// objects, and hand the caller their `OwnerCap`, a scoped `WardenPolicy`,
/// and (for the single-operator demo) the `CriticCap`.
entry fun open_vault(
    seed: Coin<SUI>,
    critic_addr: address,
    per_tx_cap: u64,
    window_cap: u64,
    window_ms: u64,
    reserve_floor: u64,
    ttl_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let (mut v, ocap) = vault::new<SUI>(ctx);
    vault::deposit(&mut v, seed, ctx);
    let vid = vault::vault_id(&v);

    let reg = policy::init_registry(vid, ctx);
    let pol = policy::mint(
        &reg, vid, ctx.sender(),
        per_tx_cap, window_cap, window_ms, reserve_floor, ttl_ms,
        clock, ctx,
    );
    let creg = critic::init_registry(vid, critic_addr, ctx);
    let led = ledger::new(vid, ctx);

    // shared state
    vault::share(v);
    policy::share_registry(reg);
    critic::share_registry(creg);
    ledger::share(led);

    // owner keeps the withdraw cap; agent keeps the (non-transferable) policy
    transfer::public_transfer(ocap, ctx.sender());
    policy::transfer_policy(pol, ctx.sender());
    critic::mint_cap_to(critic_addr, ctx);
}

/// The agent proposes a trade; it flows through all five gates atomically.
/// On a guardian fault the vault freezes and the rejection is recorded —
/// the call still succeeds (the freeze persists), it just doesn't execute.
entry fun agent_trade(
    v: &mut vault::Vault<SUI>,
    pol: &mut policy::WardenPolicy,
    reg: &policy::GenerationRegistry,
    creg: &critic::CriticRegistry,
    ccap: &critic::CriticCap,
    led: &mut ledger::TradeLedger,
    market: &OracleFeed,
    amount: u64,
    direction: u8,
    claimed_risk_bps: u64,
    digest: vector<u8>,
    walrus_blob: vector<u8>,
    tee_attestation: vector<u8>,
    clock: &Clock,
) {
    let t = warden::propose(v, amount, direction, claimed_risk_bps, digest);
    let verdict = critic::judge(ccap, digest, true);
    warden::settle(
        t, v, pol, reg, creg, verdict, led,
        market, walrus_blob, tee_attestation, clock,
    ); // returns a Receipt (drop) — the Recorded event carries the proof
}

/// Open the shared market-data feed (caller becomes the keeper/feeder).
entry fun feed_open(max_age_ms: u64, clock: &Clock, ctx: &mut TxContext) {
    feed::share(feed::new(ctx.sender(), max_age_ms, clock, ctx));
}

/// The keeper writes market data (production: pulled from Pyth + DeepBook).
entry fun feed_update(market: &mut OracleFeed, price_e6: u64, depth: u64, clock: &Clock, ctx: &TxContext) {
    feed::update(market, price_e6, depth, clock, ctx);
}

/// L3 — open a self-hedging carry position over the vault's notional.
entry fun open_hedge(
    v: &vault::Vault<SUI>,
    notional: u64,
    carry_bps_per_day: u64,
    entry_price_e6: u64,
    strike_e6: u64,
    hedge_cost: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let p = strategy::open(
        vault::vault_id(v), notional, carry_bps_per_day,
        entry_price_e6, strike_e6, hedge_cost, clock, ctx,
    );
    transfer::public_transfer(p, ctx.sender());
}

/// L3 — settle a hedge position at a price; emits an auditable result
/// carrying the proven drawdown floor.
entry fun settle_hedge(p: &HedgedCarry, price_e6: u64, clock: &Clock) {
    strategy::settle(p, price_e6, clock);
}

// ---- L5: compliance ----

entry fun kyc_open(ctx: &mut TxContext) {
    compliance::share_registry(compliance::init_registry(ctx));
}

entry fun kyc_set(reg: &mut KycRegistry, who: address, ok: bool, ctx: &TxContext) {
    compliance::set_verified(reg, who, ok, ctx);
}

// ---- L5: optimistic oracle ----

entry fun oracle_propose(
    question: vector<u8>, resolver: address, proposed: u8, bond: u64,
    window_ms: u64, clock: &Clock, ctx: &mut TxContext,
) {
    oracle::share(oracle::propose(question, resolver, proposed, bond, window_ms, clock, ctx));
}

entry fun oracle_finalize(c: &mut Claim, clock: &Clock) { oracle::finalize(c, clock); }

// ---- L6: dead-man-switch inheritance ----

entry fun inherit_open(beneficiary: address, dormancy_ms: u64, clock: &Clock, ctx: &mut TxContext) {
    transfer::public_transfer(inheritance::new(beneficiary, dormancy_ms, clock, ctx), ctx.sender());
}

entry fun inherit_claim(s: &mut Switch, clock: &Clock) { inheritance::claim(s, clock); }

/// Owner withdraws — works even when the agent is frozen (non-custodial).
entry fun owner_exit(
    v: &mut vault::Vault<SUI>,
    cap: &vault::OwnerCap,
    amount: u64,
    ctx: &mut TxContext,
) {
    let c = vault::owner_withdraw(v, cap, amount, ctx);
    transfer::public_transfer(c, ctx.sender());
}

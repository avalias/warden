/// WARDEN — the orchestrator that holds the leash.
///
/// A trade is a hot potato (`Trade` has no abilities): once the AI
/// proposes it, it MUST flow through policy + guardian + critic and be
/// settled in the SAME programmable transaction. The agent never touches
/// funds — it only steers within the leash. The five gates:
///
///   L1  policy   — capability scope (caps, window, reserve, expiry, gen)
///   L2  guardian — the chain re-derives risk; clamps; freezes on fault
///   L2  critic   — an independent identity must have approved THIS digest
///   L0  vault    — execute as notional only; funds never leave
///   L4  ledger   — append a three-proof receipt, tamper-evident
module warden::warden;

use sui::clock::Clock;
use sui::hash;
use std::bcs;
use warden::vault::{Self, Vault};
use warden::policy::{Self, WardenPolicy, GenerationRegistry};
use warden::guardian;
use warden::critic::{Self, CriticRegistry, Verdict};
use warden::ledger::{Self, TradeLedger, Receipt};
use warden::feed::{Self, OracleFeed};

const EVaultMismatch: u64 = 0;
const ECriticDigestMismatch: u64 = 1;

/// Hot potato. No `key`, `store`, `copy`, or `drop` → it cannot be
/// abandoned; the only way to discharge it is `settle`.
public struct Trade {
    vault: ID,
    amount: u64,
    direction: u8,
    claimed_risk_bps: u64,
    exposure_after: u64,
    digest: vector<u8>,
}

/// 1) The AI proposes an intent. Nothing is trusted or executed yet.
/// The digest is derived ON-CHAIN from the trade contents (it is NOT a
/// caller-supplied number) so the critic's approval is cryptographically
/// bound to exactly (amount, direction, claimed risk, resulting exposure).
public fun propose<T>(
    v: &Vault<T>,
    amount: u64,
    direction: u8,
    claimed_risk_bps: u64,
): Trade {
    let exposure_after = vault::deployed(v) + amount;
    let mut bytes = bcs::to_bytes(&amount);
    vector::append(&mut bytes, bcs::to_bytes(&direction));
    vector::append(&mut bytes, bcs::to_bytes(&claimed_risk_bps));
    vector::append(&mut bytes, bcs::to_bytes(&exposure_after));
    let digest = hash::keccak256(&bytes);
    Trade { vault: vault::vault_id(v), amount, direction, claimed_risk_bps, exposure_after, digest }
}

/// The on-chain-derived digest the critic must sign — bound to the trade.
public fun trade_digest(t: &Trade): vector<u8> { t.digest }

/// 2) Run every gate and discharge the hot potato. On a guardian fault
///    the vault is FROZEN and a rejected entry is recorded (the freeze
///    persists — it does not revert). Hard capability/critic breaches
///    abort the whole tx, as they should.
public fun settle<T>(
    t: Trade,
    v: &mut Vault<T>,
    pol: &mut WardenPolicy,
    reg: &GenerationRegistry,
    creg: &CriticRegistry,
    verdict: Verdict,
    l: &mut TradeLedger,
    market: &OracleFeed,
    walrus_blob: vector<u8>,
    tee_attestation: vector<u8>,
    clock: &Clock,
): Receipt {
    let Trade { vault: tv, amount, direction, claimed_risk_bps, exposure_after, digest } = t;
    assert!(tv == vault::vault_id(v), EVaultMismatch);

    // L1 — capability scope (hard stop on breach)
    policy::assert_and_spend(pol, reg, amount, clock);

    // L2 — independent critic must have approved THIS exact digest
    let judged = critic::consume(creg, verdict);
    assert!(judged == digest, ECriticDigestMismatch);

    // L2 — read market data from the on-chain feed the agent does NOT control,
    // then re-derive risk from it (never from a caller-supplied number).
    let (price_e6, depth) = feed::read(market, clock);
    let a = guardian::evaluate(claimed_risk_bps, direction, exposure_after, price_e6, depth);

    if (guardian::ok(&a)) {
        // L0 — execute within the leash; funds never leave the vault
        vault::deploy(v, amount, policy::reserve_floor(pol));
        // L4 — append an accepted three-proof receipt
        ledger::record(
            l, guardian::derived(&a), amount, direction, true, guardian::fault(&a),
            digest, walrus_blob, tee_attestation, clock,
        )
    } else {
        // The chain caught what the agent (and even the critic) missed.
        vault::freeze_vault(v, guardian::fault(&a));
        // L4 — record the REJECTED attempt; nothing executed
        ledger::record(
            l, guardian::derived(&a), 0, direction, false, guardian::fault(&a),
            digest, walrus_blob, tee_attestation, clock,
        )
    }
}

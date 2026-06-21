/// L4 — Verifiable, tamper-evident track record.
///
/// Append-only. The sequence number is monotonic and there is NO delete
/// path — you cannot quietly drop a losing trade. Timestamps are
/// non-backdated (each entry's time is >= the previous, taken from the
/// Sui `Clock`). Every entry carries a three-proof receipt: the Sui tx
/// digest, the Walrus blob id of the sealed reasoning, and a TEE
/// attestation hash. Rejected trades are recorded too — accountability
/// includes the things the agent was NOT allowed to do.
module warden::ledger;

use sui::clock::{Self, Clock};
use sui::event;
use sui::hash;
use sui::vec_set::{Self, VecSet};
use std::bcs;

const ENonMonotonic: u64 = 0;
const EReplayedDigest: u64 = 1;

public struct TradeLedger has key {
    id: UID,
    vault: ID,
    seq: u64,       // monotonic; only ever increments
    last_ms: u64,   // non-backdated guard
    count: u64,
    prev_digest: vector<u8>,      // running hash-chain head (tamper-evidence)
    seen: VecSet<vector<u8>>,     // trade digests already recorded (replay guard)
}

public struct Receipt has store, copy, drop {
    seq: u64,
    ts_ms: u64,
    risk_bps: u64,
    amount: u64,        // notional actually executed (0 if rejected)
    direction: u8,
    accepted: bool,
    fault: u8,
    trade_digest: vector<u8>,
    entry_digest: vector<u8>,      // keccak(prev_digest || entry fields) — the chain link
    walrus_blob: vector<u8>,       // sealed reasoning blob id
    tee_attestation: vector<u8>,   // enclave attestation hash
}

public struct Recorded has copy, drop {
    vault: ID, seq: u64, ts_ms: u64, risk_bps: u64, accepted: bool,
    entry_digest: vector<u8>,
}

public fun new(vault: ID, ctx: &mut TxContext): TradeLedger {
    TradeLedger {
        id: object::new(ctx), vault, seq: 0, last_ms: 0, count: 0,
        prev_digest: vector[], seen: vec_set::empty<vector<u8>>(),
    }
}

/// Append an entry. Enforces monotonic sequence, non-decreasing time, and
/// digest uniqueness (no replay), and chains each entry into a keccak hash
/// chain so any forged or dropped entry is detectable off-chain.
public fun record(
    l: &mut TradeLedger,
    risk_bps: u64,
    amount: u64,
    direction: u8,
    accepted: bool,
    fault: u8,
    trade_digest: vector<u8>,
    walrus_blob: vector<u8>,
    tee_attestation: vector<u8>,
    clock: &Clock,
): Receipt {
    let now = clock::timestamp_ms(clock);
    assert!(now >= l.last_ms, ENonMonotonic);
    assert!(!vec_set::contains(&l.seen, &trade_digest), EReplayedDigest);
    l.seq = l.seq + 1;
    l.last_ms = now;
    l.count = l.count + 1;

    // hash-chain: entry_digest = keccak(prev || seq || ts || risk || accepted || fault || trade_digest)
    let mut chain = l.prev_digest;
    vector::append(&mut chain, bcs::to_bytes(&l.seq));
    vector::append(&mut chain, bcs::to_bytes(&now));
    vector::append(&mut chain, bcs::to_bytes(&risk_bps));
    vector::append(&mut chain, bcs::to_bytes(&accepted));
    vector::append(&mut chain, bcs::to_bytes(&fault));
    vector::append(&mut chain, trade_digest);
    let entry_digest = hash::keccak256(&chain);
    l.prev_digest = entry_digest;
    vec_set::insert(&mut l.seen, trade_digest);

    event::emit(Recorded { vault: l.vault, seq: l.seq, ts_ms: now, risk_bps, accepted, entry_digest });
    Receipt {
        seq: l.seq, ts_ms: now, risk_bps, amount, direction, accepted, fault,
        trade_digest, entry_digest, walrus_blob, tee_attestation,
    }
}

public fun seq(l: &TradeLedger): u64 { l.seq }
public fun count(l: &TradeLedger): u64 { l.count }
public fun chain_head(l: &TradeLedger): vector<u8> { l.prev_digest } // off-chain re-walk anchor
public fun share(l: TradeLedger) { transfer::share_object(l) }

public fun receipt_seq(r: &Receipt): u64 { r.seq }
public fun receipt_risk(r: &Receipt): u64 { r.risk_bps }
public fun receipt_accepted(r: &Receipt): bool { r.accepted }
public fun receipt_fault(r: &Receipt): u8 { r.fault }
public fun receipt_entry_digest(r: &Receipt): vector<u8> { r.entry_digest }

#[test_only]
public fun destroy_for_testing(l: TradeLedger) {
    let TradeLedger { id, vault: _, seq: _, last_ms: _, count: _, prev_digest: _, seen: _ } = l;
    object::delete(id);
}

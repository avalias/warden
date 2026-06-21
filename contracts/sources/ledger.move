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

const ENonMonotonic: u64 = 0;

public struct TradeLedger has key {
    id: UID,
    vault: ID,
    seq: u64,       // monotonic; only ever increments
    last_ms: u64,   // non-backdated guard
    count: u64,
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
    walrus_blob: vector<u8>,       // sealed reasoning blob id
    tee_attestation: vector<u8>,   // enclave attestation hash
}

public struct Recorded has copy, drop {
    vault: ID, seq: u64, ts_ms: u64, risk_bps: u64, accepted: bool,
}

public fun new(vault: ID, ctx: &mut TxContext): TradeLedger {
    TradeLedger { id: object::new(ctx), vault, seq: 0, last_ms: 0, count: 0 }
}

/// Append an entry. Enforces monotonic sequence and non-decreasing time.
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
    l.seq = l.seq + 1;
    l.last_ms = now;
    l.count = l.count + 1;
    event::emit(Recorded { vault: l.vault, seq: l.seq, ts_ms: now, risk_bps, accepted });
    Receipt {
        seq: l.seq, ts_ms: now, risk_bps, amount, direction, accepted, fault,
        trade_digest, walrus_blob, tee_attestation,
    }
}

public fun seq(l: &TradeLedger): u64 { l.seq }
public fun count(l: &TradeLedger): u64 { l.count }
public fun share(l: TradeLedger) { transfer::share_object(l) }

public fun receipt_seq(r: &Receipt): u64 { r.seq }
public fun receipt_risk(r: &Receipt): u64 { r.risk_bps }
public fun receipt_accepted(r: &Receipt): bool { r.accepted }
public fun receipt_fault(r: &Receipt): u8 { r.fault }

#[test_only]
public fun destroy_for_testing(l: TradeLedger) {
    let TradeLedger { id, vault: _, seq: _, last_ms: _, count: _ } = l;
    object::delete(id);
}

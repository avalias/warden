/// L5 — Move-native optimistic oracle.
///
/// An outcome is proposed with a bond. During a challenge window anyone can
/// dispute it. After the window an unchallenged claim finalizes to the
/// proposed outcome; a disputed claim is flagged for governance and only the
/// resolver can finalize it. "Provenance, not truth" — the chain records who
/// said what and when, and gives a window to contest.
module warden::oracle;

use sui::clock::{Self, Clock};

const EWindowOpen: u64 = 0;     // tried to finalize before the window closed
const EWindowClosed: u64 = 1;   // tried to dispute after the window closed
const EAlreadyFinal: u64 = 2;
const EDisputed: u64 = 3;       // disputed claims need the resolver
const ENotResolver: u64 = 4;

public struct Claim has key {
    id: UID,
    question: vector<u8>,
    proposer: address,
    resolver: address,          // governance address that resolves disputes
    proposed: u8,
    bond: u64,
    opened_ms: u64,
    window_ms: u64,
    disputed: bool,
    finalized: bool,
    final_outcome: u8,
}

public fun propose(
    question: vector<u8>, resolver: address, proposed: u8, bond: u64,
    window_ms: u64, clock: &Clock, ctx: &mut TxContext,
): Claim {
    Claim {
        id: object::new(ctx),
        question, proposer: ctx.sender(), resolver, proposed, bond,
        opened_ms: clock::timestamp_ms(clock), window_ms,
        disputed: false, finalized: false, final_outcome: 0,
    }
}

/// Contest a claim — only while the window is open.
public fun dispute(c: &mut Claim, clock: &Clock) {
    assert!(!c.finalized, EAlreadyFinal);
    assert!(clock::timestamp_ms(clock) < c.opened_ms + c.window_ms, EWindowClosed);
    c.disputed = true;
}

/// Finalize an UNCHALLENGED claim after its window closes.
public fun finalize(c: &mut Claim, clock: &Clock): u8 {
    assert!(!c.finalized, EAlreadyFinal);
    assert!(clock::timestamp_ms(clock) >= c.opened_ms + c.window_ms, EWindowOpen);
    assert!(!c.disputed, EDisputed);
    c.finalized = true;
    c.final_outcome = c.proposed;
    c.final_outcome
}

/// Resolve a DISPUTED claim — only the governance resolver.
public fun resolve(c: &mut Claim, outcome: u8, ctx: &TxContext): u8 {
    assert!(!c.finalized, EAlreadyFinal);
    assert!(c.disputed, EDisputed);
    assert!(ctx.sender() == c.resolver, ENotResolver);
    c.finalized = true;
    c.final_outcome = outcome;
    outcome
}

public fun is_final(c: &Claim): bool { c.finalized }
public fun outcome(c: &Claim): u8 { c.final_outcome }
public fun disputed(c: &Claim): bool { c.disputed }
public fun share(c: Claim) { transfer::share_object(c) }

#[test_only]
public fun destroy_for_testing(c: Claim) {
    let Claim { id, question: _, proposer: _, resolver: _, proposed: _, bond: _,
        opened_ms: _, window_ms: _, disputed: _, finalized: _, final_outcome: _ } = c;
    object::delete(id);
}
